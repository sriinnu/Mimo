//
//  GitProvider.swift
//  Mimo
//
//  Created by Srinivas Pendela on 12/05/2026
//

import Foundation

enum GitProvider: String, CaseIterable, Identifiable, Codable, Equatable {
    case github, azureDevOps, gitlab, bitbucket, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .github: "GitHub"
        case .azureDevOps: "Azure DevOps"
        case .gitlab: "GitLab"
        case .bitbucket: "Bitbucket"
        case .custom: "Custom"
        }
    }

    var sshURLPrefix: String {
        switch self {
        case .github: "git@github.com:"
        case .azureDevOps: "git@ssh.dev.azure.com:v3/"
        case .gitlab: "git@gitlab.com:"
        case .bitbucket: "git@bitbucket.org:"
        case .custom: ""
        }
    }

    var httpsURLPrefix: String {
        switch self {
        case .github: "https://github.com/"
        case .azureDevOps: "https://dev.azure.com/"
        case .gitlab: "https://gitlab.com/"
        case .bitbucket: "https://bitbucket.org/"
        case .custom: ""
        }
    }

    var iconName: String {
        switch self {
        case .github: "globe"
        case .azureDevOps: "building.2.fill"
        case .gitlab: "fox.fill"
        case .bitbucket: "bucket.fill"
        case .custom: "lock.shield.fill"
        }
    }

    var defaultHost: String {
        switch self {
        case .github: "github.com"
        case .azureDevOps: "ssh.dev.azure.com"
        case .gitlab: "gitlab.com"
        case .bitbucket: "bitbucket.org"
        case .custom: ""
        }
    }
}
