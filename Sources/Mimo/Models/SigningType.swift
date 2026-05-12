//
//  SigningType.swift
//  Mimo
//

import Foundation

enum SigningType: String, CaseIterable, Identifiable, Codable, Equatable {
    case none, gpg, ssh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .gpg: "GPG"
        case .ssh: "SSH"
        }
    }
}
