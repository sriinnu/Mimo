//
//  CredentialHelper.swift
//  Mimo
//

import Foundation

enum CredentialHelper: String, CaseIterable, Identifiable, Codable, Equatable {
    case osxkeychain, cache, store, none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .osxkeychain: "macOS Keychain"
        case .cache: "Cache (in-memory)"
        case .store: "Store (plain text)"
        case .none: "None"
        }
    }
}
