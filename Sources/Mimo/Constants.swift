//
//  Constants.swift
//  
//
//  Created by Srinivas Pendela on 27/04/2026.
//

import SwiftUI

enum Constants {

    // MARK: - System Images

    enum SystemImage {
        static let appIcon = "person.2.circle"
        static let appIconFill = "person.2.circle.fill"
        static let profile = "person.circle.fill"
        static let profileAdd = "person.crop.circle.badge.plus"
        static let switchProfile = "arrow.right.circle.fill"
        static let editProfile = "pencil.circle.fill"
        static let deleteProfile = "trash.circle.fill"
        static let key = "key.fill"
        static let keySlash = "key.slash"
        static let shieldCheck = "checkmark.shield.fill"
        static let copy = "doc.on.doc.fill"
        static let refresh = "arrow.clockwise"
        static let folder = "folder.fill"
        static let power = "power"
        static let info = "info.circle.fill"
        static let settings = "slider.horizontal.3"
        static let gear = "gearshape.fill"
        static let drive = "externaldrive.fill"
        static let warning = "exclamationmark.triangle.fill"
        static let checkmark = "checkmark.circle.fill"
        static let plus = "plus"
        static let minus = "minus"
        static let plusCircle = "plus.circle.fill"
        static let sshManage = "key.horizontal.fill"
        static let profileManage = "person.text.rectangle.fill"
        static let quit = "rectangle.portrait.and.arrow.right"
        static let profileTab = "person.2.fill"
        static let sshTab = "key.fill"
        static let settingsTab = "gearshape.fill"
        static let generateKey = "bolt.fill"
        static let calendar = "calendar"
        static let sparkle = "sparkles"
        static let update = "arrow.up.circle.fill"
        static let directories = "folder.badge.gearshape"
        static let signing = "signature"
        static let directory = "folder.fill.badge.plus"
        static let clone = "arrow.down.circle.fill"
        static let branch = "arrow.triangle.branch"
        static let dirty = "circle.badge.xmark"
        static let clean = "checkmark.circle.fill"
        static let hookOn = "checkmark.shield.fill"
        static let hookOff = "shield.slash"
        static let timeMachine = "clock.arrow.circlepath"
        static let undo = "arrow.uturn.backward"
        static let trash = "trash"
    }

    // MARK: - Font Sizes

    enum FontSize {
        static let title: CGFloat = 16
        static let headline: CGFloat = 14
        static let body: CGFloat = 13
        static let callout: CGFloat = 12
        static let caption: CGFloat = 11
        static let caption2: CGFloat = 10
        static let statusBarIcon: CGFloat = 18
        static let emptyStateIcon: CGFloat = 36
        static let aboutIcon: CGFloat = 50
        static let aboutTitle: CGFloat = 28
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 1
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
        static let xl: CGFloat = 10
        static let xxl: CGFloat = 12
        static let xxxl: CGFloat = 16
        static let xxxxl: CGFloat = 20
    }

    // MARK: - Layout

    enum Layout {
        static let popoverWidth: CGFloat = 320
        static let popoverHeight: CGFloat = 460
        static let cornerRadius: CGFloat = 12
        static let cornerRadiusSmall: CGFloat = 8
        static let cornerRadiusCapsule: CGFloat = 6
        static let borderWidth: CGFloat = 0.5
        static let activeIndicatorSize: CGFloat = 8
        static let statusBarIconSize: CGFloat = 18
        static let dotSize: CGFloat = 10
        static let managementWidth: CGFloat = 680
        static let managementHeight: CGFloat = 480
        static let sidebarWidth: CGFloat = 180
        static let tabPillHeight: CGFloat = 28
        static let aboutWidth: CGFloat = 320
        static let iconSize: CGFloat = 20
        static let rowHeight: CGFloat = 36
    }

    // MARK: - Opacity

    enum Opacity {
        static let backgroundBlur: Double = 0.8
        static let divider: Double = 0.2
        static let hover: Double = 0.05
        static let active: Double = 0.12
        static let secondary: Double = 0.6
        static let tertiary: Double = 0.4
        static let glassHighlight: Double = 0.15
        static let glassBorder: Double = 0.3
    }

    // MARK: - Strings

    enum Strings {
        static let appName = "Mimo"
        static let appSubtitle = "Git Identity Manager"
        static let noActiveProfile = "No active profile"
        static let noProfiles = "No Profiles Yet"
        static let noProfilesHint = "Add a git profile to get started."
        static let noSSHKeys = "No SSH Keys Found"
        static let noSSHKeysHint = "No keys were detected in ~/.ssh"
        static let addProfile = "Add Profile"
        static let editProfile = "Edit Profile"
        static let newProfile = "New Profile"
        static let saveChanges = "Save Changes"
        static let cancel = "Cancel"
        static let delete = "Delete"
        static let refresh = "Refresh"
        static let openSSH = "Open .ssh"
        static let active = "Active"
        static let manageSSH = "Manage SSH"
        static let manageProfile = "Manage Profile"
        static let quitApp = "Quit \(appName)"
        static let scanningSSH = "Scanning SSH keys..."
        static let deleteProfileTitle = "Delete Profile?"
        static let deleteProfileMessage = "This will remove the profile from \(appName)."
        static let deleteSSHTitle = "Delete SSH Key?"
        static let publicKeyCopied = "Public key copied!"
        static let noPublicKey = "No public key found."
        static let sshKeys = "SSH Keys"
        static let generateKey = "Generate Key"
        static let selectYourKey = "Select your key"
        static let identity = "IDENTITY"
        static let sshKey = "SSH KEY"
        static let type = "Type"
        static let email = "Email"
        static let file = "File"
        static let passphrase = "Passphrase"
        static let optional = "Optional"
        static let checkForUpdates = "Check for Updates..."
        static let updateAvailable = "New update available!"
        static let updateNow = "Update Now"
        static let aboutApp = "About \(appName)"
        static let version = "Version"
        static let directories = "Directories"
        static let directoryHint = "Map folders to git profiles"
        static let addDirectory = "Add Directory"
        static let directoryPath = "Directory Path"
        static let selectProfile = "Select Profile"
        static let browse = "Browse"
        static let signing = "Signing"
        static let signingType = "Sign Type"
        static let credentialHelper = "Credential Helper"
        static let cloneRepo = "Clone Repository"
        static let cloneURL = "Repository URL"
        static let cloneInto = "Clone Into"
        static let cloning = "Cloning..."
        static let cloneSuccess = "Cloned successfully!"
        static let repoStatus = "Repository"
        static let noRepo = "No git repo detected"
        static let provider = "Provider"

        // Pre-commit guardrail hook
        static let precommitInstalled = "Guard on"
        static let precommitMissing = "Guard off"
        static let precommitInstallFailedTitle = "Couldn't install the guardrail"
        static let precommitUninstallFailedTitle = "Couldn't remove the guardrail"
        static let precommitOK = "OK"
    }

    // MARK: - Form Placeholders

    enum Placeholder {
        static let profileName = "Profile Name"
        static let gitUserName = "Git User Name"
        static let gitEmail = "Git Email"
        static let email = "your@email.com"
        static let filename = "id_ed25519_new"
        static let passphrase = "Optional"
    }

    // MARK: - Form Labels

    enum Label {
        static let profileName = "Profile Name"
        static let gitUserName = "Git User Name"
        static let gitEmail = "Git Email"
        static let sshKey = "SSH KEY"
        static let profiles = "Profiles"
        static let profile = "Profile"
        static let ssh = "SSH"
    }

    // MARK: - Animation

    enum Animation {
        static let defaultDuration: Double = 0.15
        static let formDuration: Double = 0.2
        static let statusDuration: UInt64 = 2_500_000_000
    }

    // MARK: - Persistence

    enum Persistence {
        static let profilesKey = "com.sriinnu.mimo.profiles"
        static let directoriesKey = "com.sriinnu.mimo.directories"
        static let autoSwitchKey = "com.sriinnu.mimo.autoSwitchOnMismatch"
    }

    // MARK: - Management Tab

    enum ManagementTab: String, CaseIterable, Identifiable {
        case profile = "Profile"
        case ssh = "SSH"
        case directories = "Dirs"
        case signing = "Sign"
        case timeMachine = "Time"

        var id: String { rawValue }
    }
}

