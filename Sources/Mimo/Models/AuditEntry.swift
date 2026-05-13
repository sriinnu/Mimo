//
//  AuditEntry.swift
//  Mimo
//
//  A single line in Mimo's diary. Every time Mimo writes config — touches
//  ~/.gitconfig, ~/.ssh/config, or ~/.config/mimo/profiles — an entry like
//  this lands in audit.jsonl. Each one is a complete unit: who triggered it,
//  what changed, what it was before, what it is now. That's enough to
//  reverse a step, even hours later.
//

import Foundation

/// The surface Mimo wrote to. We split repo-level config out from global so
/// the revert path knows whether to run `git config --global` or
/// `git config -f <path>`.
enum AuditScope: Codable, Equatable, Hashable {
    case gitConfigGlobal
    case gitConfigRepo(path: String)
    case sshConfig
    /// The contents of `~/.config/mimo/profiles/<UUID>.gitconfig` — the
    /// per-profile include file used by directory mappings.
    case mimoProfiles

    // Stable string tag so a future schema rename doesn't break old logs.
    private enum CodingKeys: String, CodingKey {
        case kind
        case path
    }

    private enum Kind: String, Codable {
        case gitConfigGlobal
        case gitConfigRepo
        case sshConfig
        case mimoProfiles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .gitConfigGlobal: self = .gitConfigGlobal
        case .gitConfigRepo:
            let path = try c.decode(String.self, forKey: .path)
            self = .gitConfigRepo(path: path)
        case .sshConfig: self = .sshConfig
        case .mimoProfiles: self = .mimoProfiles
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .gitConfigGlobal:
            try c.encode(Kind.gitConfigGlobal, forKey: .kind)
        case .gitConfigRepo(let path):
            try c.encode(Kind.gitConfigRepo, forKey: .kind)
            try c.encode(path, forKey: .path)
        case .sshConfig:
            try c.encode(Kind.sshConfig, forKey: .kind)
        case .mimoProfiles:
            try c.encode(Kind.mimoProfiles, forKey: .kind)
        }
    }

    /// SF Symbol used in the audit log row.
    var iconName: String {
        switch self {
        case .gitConfigGlobal: return "globe"
        case .gitConfigRepo:   return "folder.fill"
        case .sshConfig:       return "key.horizontal.fill"
        case .mimoProfiles:    return "person.text.rectangle.fill"
        }
    }

    /// Short label shown next to the icon.
    var label: String {
        switch self {
        case .gitConfigGlobal:        return "Global git"
        case .gitConfigRepo(let p):   return "Repo · \((p as NSString).lastPathComponent)"
        case .sshConfig:              return "SSH config"
        case .mimoProfiles:           return "Mimo profile file"
        }
    }
}

/// A single Mimo write, captured as data so it can be replayed in reverse.
///
/// `before` and `after` are nullable on purpose:
/// - `before = nil, after = "x"` → the key didn't exist; reverting means
///   *unsetting* it.
/// - `before = "y", after = "x"` → the key was set to y; reverting means
///   setting it back to y.
/// - `before = "y", after = nil` → the key was unset by Mimo; reverting
///   means setting it back to y.
struct AuditEntry: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let timestamp: Date
    /// Which Mimo profile triggered this change. `nil` if the write
    /// originated from somewhere not tied to a single profile.
    let profileID: UUID?
    /// Snapshot of the profile's display name at write-time — kept so the
    /// audit row still reads sensibly after the profile is deleted.
    let profileName: String
    let scope: AuditScope
    /// File or repo path involved — for display only. The scope already
    /// carries the structural location for revert.
    let path: String?
    /// Human-readable summary: *"set user.email to work@co.com"*.
    let summary: String
    /// Value before the write, if known. `nil` means it didn't exist.
    let before: String?
    /// Value after the write. `nil` means the write *unset* the value.
    let after: String?
    /// True once this entry has been undone. Reverted entries can't be
    /// reverted again from the UI.
    let isReverted: Bool
    /// For git-config writes — which key Mimo touched (e.g. "user.email").
    /// Empty string for non-git-config scopes.
    let configKey: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        profileID: UUID?,
        profileName: String,
        scope: AuditScope,
        path: String? = nil,
        summary: String,
        before: String?,
        after: String?,
        isReverted: Bool = false,
        configKey: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.profileID = profileID
        self.profileName = profileName
        self.scope = scope
        self.path = path
        self.summary = summary
        self.before = before
        self.after = after
        self.isReverted = isReverted
        self.configKey = configKey
    }
}

// MARK: - Convenience builders

extension AuditEntry {
    /// Factory for the most common kind of write: setting a single git
    /// config key in the global config. Builds the human-readable summary
    /// from the key and value so call sites stay tidy.
    static func gitConfigGlobal(
        profileID: UUID?,
        profileName: String,
        key: String,
        before: String?,
        after: String?
    ) -> AuditEntry {
        let summary: String
        switch (before, after) {
        case (nil, let new?):
            summary = "set \(key) to \(new)"
        case (_, nil):
            summary = "unset \(key)"
        case (let old?, let new?):
            summary = old == new
                ? "rewrote \(key) (no change)"
                : "changed \(key) from \(old) to \(new)"
        case (nil, nil):
            summary = "touched \(key)"
        }
        return AuditEntry(
            profileID: profileID,
            profileName: profileName,
            scope: .gitConfigGlobal,
            path: nil,
            summary: summary,
            before: before,
            after: after,
            configKey: key
        )
    }
}
