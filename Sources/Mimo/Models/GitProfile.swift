//
//  GitProfile.swift
//  Mimo
//
//  Created by Srinivas Pendela on 26/03/2026
//

import Foundation

struct GitProfile: Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var userName: String
    var userEmail: String
    var signingKey: String?
    var sshKeyPath: String?
    var provider: GitProvider
    var providerURL: String?
    var signingType: SigningType
    var credentialHelper: CredentialHelper
    var isActive: Bool

    init(
        id: UUID = UUID(),
        name: String,
        userName: String,
        userEmail: String,
        signingKey: String? = nil,
        sshKeyPath: String? = nil,
        provider: GitProvider = .custom,
        providerURL: String? = nil,
        signingType: SigningType = .none,
        credentialHelper: CredentialHelper = .osxkeychain,
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.userName = userName
        self.userEmail = userEmail
        self.signingKey = signingKey
        self.sshKeyPath = sshKeyPath
        self.provider = provider
        self.providerURL = providerURL
        self.signingType = signingType
        self.credentialHelper = credentialHelper
        self.isActive = isActive
    }
}

extension GitProfile: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, userName, userEmail, signingKey, sshKeyPath
        case provider, providerURL, signingType, credentialHelper, isActive
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        userName = try c.decode(String.self, forKey: .userName)
        userEmail = try c.decode(String.self, forKey: .userEmail)
        signingKey = try c.decodeIfPresent(String.self, forKey: .signingKey)
        sshKeyPath = try c.decodeIfPresent(String.self, forKey: .sshKeyPath)
        provider = (try? c.decode(GitProvider.self, forKey: .provider)) ?? .custom
        providerURL = try c.decodeIfPresent(String.self, forKey: .providerURL)
        signingType = (try? c.decode(SigningType.self, forKey: .signingType)) ?? .none
        credentialHelper = (try? c.decode(CredentialHelper.self, forKey: .credentialHelper)) ?? .osxkeychain
        isActive = try c.decode(Bool.self, forKey: .isActive)
    }
}

extension GitProfile {
    static let example = GitProfile(
        name: "Personal",
        userName: "John Doe",
        userEmail: "john@personal.com",
        sshKeyPath: "~/.ssh/id_ed25519",
        isActive: true
    )

    static let examples: [GitProfile] = [
        GitProfile(
            name: "Personal",
            userName: "John Doe",
            userEmail: "john@personal.com",
            sshKeyPath: "~/.ssh/id_ed25519_personal",
            isActive: true
        ),
        GitProfile(
            name: "Work",
            userName: "John Doe",
            userEmail: "john.doe@company.com",
            sshKeyPath: "~/.ssh/id_ed25519_work",
            isActive: false
        ),
    ]
}
