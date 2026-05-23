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
//    - If Mimo quits mid-phantom, phantom state is forgotten on launch
//      (cleared defensively in AppDelegate). The git identity remains as the
//      phantom profile until the user switches manually — by design, this
//      is the safer failure mode than auto-reverting on relaunch (which
//      could surprise a user who's still inside the same session).
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
        self.capturedHeadSHA = repoRoot.flatMap { Self.headSHA(in: $0) }
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
        appModel.phantomReturnToID = nil
        appModel.phantomStartedAt = nil
        capturedRepoRoot = nil
        capturedHeadSHA = nil
        startDate = nil
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

            let current = Self.headSHA(in: repoRoot)
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

    /// Synchronous, blocking probe — runs `git -C <repo> rev-parse HEAD`.
    /// Returns nil for empty repos / errors. We don't reuse ShellService
    /// because that's an actor and this is called from a non-isolated
    /// context inside the poll loop; a direct Process keeps things simple.
    nonisolated static func headSHA(in repoRoot: URL) -> String? {
        let process = Process()
        let outPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repoRoot.path, "rev-parse", "HEAD"]
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8) ?? ""
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
