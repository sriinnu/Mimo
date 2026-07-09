//
//  PhantomModeService.swift
//  Mimo
//
//  Phantom mode — temporary identity for one commit, then auto-revert.
//
//  Flow:
//    1. User clicks "Use once" on a profile from the popover row.
//    2. We capture the current profile id (return-to) and the HEAD SHA of
//       the foreground repo (if any), then switch identity via AppModel.
//    3. A slow poll (4s) watches the captured repo's HEAD. The first time
//       it changes, we flip the identity back and clear phantom state.
//    4. If no commit happens within the timeout window (15 min in-repo,
//       5 min no-repo), we revert anyway and log the timeout.
//
//  Edges:
//    - `git commit --amend` *does* change HEAD, so amends count as the trigger
//      (consistent with the user's intent to make one commit as this identity).
//    - Branch switch doesn't change HEAD identity-of-tip, but it *does* change
//      the SHA the working tree points at — so a `git switch other-branch`
//      could trigger an early revert. Documented; not common in this flow.
//    - Survives quits: an in-flight session is persisted to
//      ~/.config/mimo/phantom.json. On relaunch we resume the HEAD-watch —
//      and if HEAD already moved (commit landed) or the timeout elapsed
//      while we were down, we auto-revert then. So a force-quit mid-phantom
//      no longer leaves the identity stranded on the phantom profile.
//

import Foundation

@MainActor
final class PhantomModeService: ObservableObject {

    // MARK: Tuning

    /// Poll cadence for HEAD watching. Slower than RepoStateService since
    /// this is a one-shot detection — a few extra seconds of latency on the
    /// auto-revert is fine; CPU is not.
    private let pollInterval: TimeInterval = 4.0

    /// Max time to wait for a commit when a repo was captured.
    private let inRepoTimeout: TimeInterval = 15 * 60  // 15 minutes

    /// Max time to wait when no repo was captured at activation (no foreground
    /// git repo). We revert purely on time in that case.
    private let noRepoTimeout: TimeInterval = 5 * 60   // 5 minutes

    // MARK: Singleton

    static let shared = PhantomModeService()

    private init() {}

    // MARK: State

    private weak var appModel: AppModel?
    private var pollTask: Task<Void, Never>?
    private var capturedRepoRoot: URL?
    private var capturedHeadSHA: String?
    private var startDate: Date?

    /// True while a phantom session is in flight.
    var isActive: Bool { pollTask != nil }

    // MARK: Persistence (survives quits)

    /// What we serialize to disk so a phantom session can resume after a quit.
    private struct PersistedPhantomState: Codable {
        let returnToID: UUID
        let startedAt: Date
        let capturedRepoRoot: URL?
        let capturedHeadSHA: String?
    }

    private var phantomStateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mimo/phantom.json")
    }

    /// Snapshot the in-flight session to disk (mode 0600). Called once `start`
    /// has captured state + flipped the identity.
    private func persistState() {
        guard let returnID = appModel?.phantomReturnToID,
              let started = startDate else { return }
        let state = PersistedPhantomState(
            returnToID: returnID,
            startedAt: started,
            capturedRepoRoot: capturedRepoRoot,
            capturedHeadSHA: capturedHeadSHA
        )
        do {
            let dir = phantomStateURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: phantomStateURL, options: [.atomic])
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: phantomStateURL.path
            )
        } catch {
            print("[PhantomMode] failed to persist state: \(error.localizedDescription)")
        }
    }

    private func clearPersistedState() {
        try? FileManager.default.removeItem(at: phantomStateURL)
    }

    // MARK: Public API

    /// Begin a phantom session: switch identity to `asProfile`, remember
    /// `originalProfileID` for the auto-revert, and (if `repoRoot` is non-nil)
    /// capture its HEAD SHA so we can detect the next commit.
    ///
    /// Safe to call from the UI; AppModel is required for the actual switch.
    func start(
        asProfile profile: GitProfile,
        originalProfileID: UUID?,
        in repoRoot: URL?,
        appModel: AppModel
    ) async {
        // Already running? Cancel cleanly first so we don't pile up tasks.
        if isActive { cancel(appModel: appModel) }

        self.appModel = appModel
        self.capturedRepoRoot = repoRoot
        var initialSHA: String?
        if let repoRoot { initialSHA = await Self.headSHA(in: repoRoot) }
        self.capturedHeadSHA = initialSHA
        let started = Date()
        self.startDate = started

        // Flip identity through the SAME path a normal activation uses, so
        // git-config writes (and audit logs, via PR D) happen identically.
        await appModel.switchProfile(to: profile)

        // Only stamp phantom state after the switch lands, so the UI's
        // "phantom" presentation lines up with the actual active profile.
        appModel.phantomReturnToID = originalProfileID
        appModel.phantomStartedAt = started

        // Audit: phantom session started
        let returnName = originalProfileID.flatMap { id in
            appModel.availableProfiles.first(where: { $0.id == id })?.name
        } ?? "none"
        IdentityAuditLog.shared.record(
            AuditEntry(
                profileID: profile.id,
                profileName: profile.name,
                scope: .gitConfigGlobal,
                summary: "phantom mode started (returning to \(returnName))",
                before: nil,
                after: profile.name,
                configKey: "phantom"
            )
        )

        // Persist so a force-quit mid-phantom can resume (or auto-revert) on
        // the next launch instead of stranding the identity.
        persistState()

        pollTask = Task { [weak self, weak appModel] in
            guard let self else { return }
            await self.runLoop(appModel: appModel)
        }
    }

    /// Cancel phantom mode and flip back to the original profile immediately.
    /// Called by user tapping the phantom badge, or internally on timeout.
    func cancel(appModel: AppModel) {
        pollTask?.cancel()
        pollTask = nil
        clearPersistedState()

        let returnID = appModel.phantomReturnToID
        let activeName = appModel.activeProfile?.name ?? "unknown"
        appModel.phantomReturnToID = nil
        appModel.phantomStartedAt = nil
        capturedRepoRoot = nil
        capturedHeadSHA = nil
        startDate = nil

        // Audit: phantom session cancelled
        IdentityAuditLog.shared.record(
            AuditEntry(
                profileID: returnID,
                profileName: "Phantom",
                scope: .gitConfigGlobal,
                summary: "phantom mode cancelled (was \(activeName))",
                before: activeName,
                after: returnID.flatMap({ id in appModel.availableProfiles.first(where: { $0.id == id })?.name }) ?? "none",
                configKey: "phantom"
            )
        )

        if let returnID,
           let original = appModel.availableProfiles.first(where: { $0.id == returnID }) {
            Task { await appModel.switchProfile(to: original) }
        }
    }

    /// Clear any in-flight phantom state without performing a revert switch.
    /// Used at app launch to guarantee phantom mode never persists across
    /// quits — see AppDelegate.
    func clearOnLaunch(appModel: AppModel) {
        pollTask?.cancel()
        pollTask = nil
        clearPersistedState()
        appModel.phantomReturnToID = nil
        appModel.phantomStartedAt = nil
        capturedRepoRoot = nil
        capturedHeadSHA = nil
        startDate = nil
    }

    /// Resume (or finish) a phantom session that was in flight when Mimo quit.
    /// If we were past the timeout or the captured repo's HEAD already moved
    /// while we were down, auto-revert now. Otherwise restart the HEAD-watch.
    /// Called from AppDelegate on launch instead of the old clear-on-launch.
    func resumeOnLaunch(appModel: AppModel) async {
        guard FileManager.default.fileExists(atPath: phantomStateURL.path),
              let data = try? Data(contentsOf: phantomStateURL)
        else {
            clearPersistedState()
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(PersistedPhantomState.self, from: data) else {
            // Nothing persisted (or corrupt) — nothing to resume.
            clearPersistedState()
            return
        }

        self.appModel = appModel
        self.startDate = state.startedAt
        self.capturedRepoRoot = state.capturedRepoRoot
        self.capturedHeadSHA = state.capturedHeadSHA
        appModel.phantomReturnToID = state.returnToID
        appModel.phantomStartedAt = state.startedAt

        let timeout = (state.capturedRepoRoot != nil) ? inRepoTimeout : noRepoTimeout

        // Past the timeout window while down → revert now.
        if Date().timeIntervalSince(state.startedAt) >= timeout {
            print("[PhantomMode] resumed past timeout — auto-reverting.")
            revert(appModel: appModel)
            return
        }
        // A repo was captured — if HEAD already moved, the commit landed → revert.
        if let repoRoot = state.capturedRepoRoot {
            let current = await Self.headSHA(in: repoRoot)
            if current != state.capturedHeadSHA {
                print("[PhantomMode] resumed after a commit — auto-reverting.")
                revert(appModel: appModel)
                return
            }
        }

        // Still in-flight — pick the watch back up.
        pollTask = Task { [weak self, weak appModel] in
            guard let self else { return }
            await self.runLoop(appModel: appModel)
        }
    }

    // MARK: Loop

    private func runLoop(appModel: AppModel?) async {
        guard let started = startDate else { return }
        let timeout = (capturedRepoRoot != nil) ? inRepoTimeout : noRepoTimeout

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            if Task.isCancelled { return }

            // Timeout check — applies in both repo and no-repo cases.
            if Date().timeIntervalSince(started) >= timeout {
                print("[PhantomMode] Timeout (\(Int(timeout))s) — auto-reverting.")
                if let appModel { await MainActor.run { self.revert(appModel: appModel) } }
                return
            }

            // No repo captured → time-only mode; nothing more to do this tick.
            guard let repoRoot = capturedRepoRoot else { continue }

            let current = await Self.headSHA(in: repoRoot)
            // If the captured SHA was nil (e.g. a freshly-initialized repo
            // with no commits) and we now have a SHA, that *is* a change.
            if current != capturedHeadSHA {
                if let appModel { await MainActor.run { self.revert(appModel: appModel) } }
                return
            }
        }
    }

    /// Perform the auto-revert: swap identity back, clear phantom state,
    /// and tear down the poll task.
    private func revert(appModel: AppModel) {
        let returnID = appModel.phantomReturnToID
        let activeName = appModel.activeProfile?.name ?? "unknown"
        pollTask = nil
        clearPersistedState()
        capturedRepoRoot = nil
        capturedHeadSHA = nil
        startDate = nil
        appModel.phantomReturnToID = nil
        appModel.phantomStartedAt = nil

        // Audit: phantom session reverted (commit detected or timeout)
        IdentityAuditLog.shared.record(
            AuditEntry(
                profileID: returnID,
                profileName: "Phantom",
                scope: .gitConfigGlobal,
                summary: "phantom mode reverted (was \(activeName))",
                before: activeName,
                after: returnID.flatMap({ id in appModel.availableProfiles.first(where: { $0.id == id })?.name }) ?? "none",
                configKey: "phantom"
            )
        )

        guard let returnID,
              let original = appModel.availableProfiles.first(where: { $0.id == returnID })
        else { return }
        Task { await appModel.switchProfile(to: original) }
    }

    // MARK: Git HEAD probe

    /// `git -C <repo> rev-parse HEAD`, run off the main thread. Returns nil
    /// for empty repos / errors. Routed through `ShellService.capture` so the
    /// blocking happens on a background executor — not the main actor, which
    /// this service otherwise runs on.
    nonisolated static func headSHA(in repoRoot: URL) async -> String? {
        let result = try? await ShellService.capture(
            executable: "/usr/bin/env",
            arguments: ["git", "-C", repoRoot.path, "rev-parse", "HEAD"],
            environment: nil
        )
        guard let result, result.status == 0, !result.output.isEmpty else { return nil }
        return result.output
    }
}
