//
//  AppDelegate.swift
//  Mimo
//
//  Created by Srinivas Pendela on 27/04/2026.
//

import Cocoa
import Combine
import SwiftUI
#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()

    /// Periodic ping that flickers the status-bar mascot into a brief wince
    /// while a mismatch persists. Lives only as long as a mismatch is active
    /// and the popover is closed — we don't want it firing while the user is
    /// already looking at the full-fidelity wince inside the popover.
    private var winceTimer: Timer?
    /// Latest cached `ForegroundRepoState`, so the wince timer and tooltip
    /// updater can read state without re-subscribing.
    private var currentRepoState: ForegroundRepoState = .empty

    #if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
    #endif
    private let updaterService = UpdaterService()
    private let repoStateService = RepoStateService()

    let appModel = AppModel()

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        if enforceSingleInstance() { return }

        setupStatusItem()
        setupPopover()
        observeActiveProfile()
        repoStateService.start(observing: appModel)

        // Resume a phantom session that was in flight when Mimo last quit —
        // or auto-revert it if the commit landed / timeout elapsed while down.
        Task { await PhantomModeService.shared.resumeOnLaunch(appModel: appModel) }

        #if canImport(Sparkle)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterService,
            userDriverDelegate: nil
        )
        if let updater = updaterController?.updater {
            updaterService.setup(with: updater)
        }
        #endif
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        refreshStatusIcon()
    }

    private func observeActiveProfile() {
        appModel.$activeProfileID
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusIcon()
                self?.refreshTooltip()
            }
            .store(in: &cancellables)

        MimoThemeStore.shared.$theme
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusIcon() }
            .store(in: &cancellables)

        // Foreground repo state — drives both the tooltip narration and the
        // status-bar wince pulse when a mismatch is detected.
        appModel.$foregroundRepoState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.currentRepoState = state
                self.refreshTooltip()
                self.reconcileWinceTimer()
            }
            .store(in: &cancellables)
    }

    /// Paint the status item with the eye-dots in the active profile's palette.
    /// `mood` lets callers (the wince pulse) momentarily swap in the closed-eye
    /// variant without changing the active profile.
    private func refreshStatusIcon(mood: MimoEyes.Mood = .normal) {
        guard let button = statusItem?.button else { return }
        let palette = appModel.activeProfile?.colorID.palette ?? MimoEmotion.joy.palette
        if let image = mimoStatusBarImage(palette: palette, size: 18, mood: mood) {
            image.isTemplate = false
            button.image = image
        }
    }

    // MARK: - Tooltip narration

    /// Refreshes the status-item tooltip from the latest profile + repo state.
    /// Three shapes:
    ///   - No repo:     "Mimo — <active profile>"
    ///   - In a repo:   "<active> · <repo> · <branch>[*]"
    ///   - Mismatch:    "⚠ Expected <expected> · <repo> · <branch>[*]"
    private func refreshTooltip() {
        guard let button = statusItem?.button else { return }
        let state = currentRepoState
        let activeName = appModel.activeProfile?.name ?? "no profile"

        guard let repoRoot = state.repoRoot else {
            button.toolTip = "\(Constants.Strings.appName) — \(activeName)"
            return
        }

        let repoName = repoRoot.lastPathComponent
        let branch = state.branch ?? "detached"
        let dirty = state.isDirty ? "*" : ""

        if state.hasMismatch,
           let expectedID = state.expectedProfileID,
           let expected = appModel.availableProfiles.first(where: { $0.id == expectedID }) {
            button.toolTip = "⚠ Expected \(expected.name) · \(repoName) · \(branch)\(dirty)"
        } else {
            button.toolTip = "\(activeName) · \(repoName) · \(branch)\(dirty)"
        }
    }

    // MARK: - Status-bar wince pulse

    /// Starts or stops the periodic status-bar wince based on:
    ///   1. mismatch active, AND
    ///   2. popover currently closed (full-fidelity wince already shows there).
    /// Re-entrant safe — invalidates any prior timer before installing a new one.
    private func reconcileWinceTimer() {
        let popoverOpen = popover?.isShown == true
        let shouldRun = currentRepoState.hasMismatch && !popoverOpen

        if shouldRun {
            // Already running? Leave it.
            if winceTimer?.isValid == true { return }
            // Every 6s: brief squeeze (~260ms), then back to normal.
            winceTimer = Timer.scheduledTimer(
                withTimeInterval: 6.0,
                repeats: true
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.pulseWince()
                }
            }
            // Fire one immediately so the user sees the first wince ~now,
            // not in six seconds — but only if the popover is still closed.
            pulseWince()
        } else {
            winceTimer?.invalidate()
            winceTimer = nil
            // Make sure we end on the resting eyes, not mid-wince.
            refreshStatusIcon(mood: .normal)
        }
    }

    /// One wince beat in the status bar: closed eyes for ~260ms, then back.
    private func pulseWince() {
        guard currentRepoState.hasMismatch, popover?.isShown != true else { return }
        refreshStatusIcon(mood: .wincing)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 260_000_000)
            // Return to resting eyes. reconcileWinceTimer decides whether the
            // next beat fires; here we only end this one.
            self?.refreshStatusIcon(mood: .normal)
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        let contentView = MenuBarView()
            .environmentObject(appModel)
            .environmentObject(updaterService)

        let host = NSHostingController(rootView: contentView)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = host
        // Need delegate callbacks so we can resume the status-bar wince when
        // the popover closes via outside-click (which doesn't go through
        // `togglePopover` and so wouldn't otherwise reach `reconcileWinceTimer`).
        popover.delegate = self

        self.popover = popover
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            popover.contentViewController?.view.window?.makeKey()
        }
        // Popover open ↔ status-bar wince mute. Reconcile whenever it toggles.
        reconcileWinceTimer()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        #if canImport(Sparkle)
        updaterController?.checkForUpdates(sender)
        #endif
    }

    // MARK: - Single instance

    /// If another Mimo is already running, bring it forward and quit ourselves.
    /// Returns true when the calling launch should bail before setting up state.
    /// Without this guard, `open -n Mimo.app` or a stale orphan would let two
    /// instances fight over the status item + UserDefaults profiles file.
    private func enforceSingleInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }
        guard let existing = others.first else { return false }

        existing.activate(options: [.activateAllWindows])
        NSApp.terminate(nil)
        return true
    }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
    // Transient-close path (outside click). Resume the status-bar wince pulse
    // if a mismatch is still active.
    func popoverDidClose(_ notification: Notification) {
        reconcileWinceTimer()
    }

    func popoverDidShow(_ notification: Notification) {
        // Belt-and-suspenders: also stop the timer here in case the popover
        // is ever shown programmatically without going through `togglePopover`.
        reconcileWinceTimer()
    }
}
