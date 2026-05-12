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

    #if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
    #endif
    private let updaterService = UpdaterService()

    let appModel = AppModel()

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        observeActiveProfile()

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
            .sink { [weak self] _ in self?.refreshStatusIcon() }
            .store(in: &cancellables)

        MimoThemeStore.shared.$theme
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusIcon() }
            .store(in: &cancellables)
    }

    private func refreshStatusIcon() {
        guard let button = statusItem?.button else { return }
        let emotion = appModel.activeProfileID.map(MimoPalette.emotion(for:)) ?? .joy
        if let image = mimoStatusBarImage(emotion: emotion, size: 18) {
            image.isTemplate = false
            button.image = image
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
    }

    @objc func checkForUpdates(_ sender: Any?) {
        #if canImport(Sparkle)
        updaterController?.checkForUpdates(sender)
        #endif
    }
}
