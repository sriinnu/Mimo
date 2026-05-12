//
//  MimoApp.swift
//
//
//  Created by Srinivas Pendela on 27/04/2026.
//

import SwiftUI

@main
struct MimoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
