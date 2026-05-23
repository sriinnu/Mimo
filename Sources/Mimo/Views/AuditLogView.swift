//
//  AuditLogView.swift
//  Mimo
//
//  The time machine. Every config write Mimo has made, in reverse-chronological
//  order — with a one-click undo on each row. The layout treats each entry like
//  a small exhibit card: timestamp, who triggered it, what touched what, and
//  the literal before/after values in mono. Reverted rows wear a strikethrough
//  and a quieter palette; the past stays visible but visibly past.
//

import SwiftUI

struct AuditLogView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject private var auditLog = IdentityAuditLog.shared

    @State private var showClearConfirm = false
    @State private var revertingID: UUID?
    @State private var revertError: String?
    @State private var showRevertError = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if auditLog.entries.isEmpty {
                    emptyState
                } else {
                    ForEach(groupedEntries, id: \.id) { group in
                        groupHeader(group)
                        VStack(spacing: 10) {
                            ForEach(group.entries) { entry in
                                auditCard(entry)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(MimoMotion.snap, value: auditLog.entries)
        .alert("Clear time machine?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                withAnimation(MimoMotion.snap) {
                    auditLog.clear()
                }
            }
        } message: {
            Text("This erases Mimo's local audit log. The changes she already made to your config stay — only the history disappears. This cannot be undone.")
        }
        .alert("Couldn't undo", isPresented: $showRevertError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(revertError ?? "Something went wrong.")
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            MimoMascot(
                mood: .curious,
                palette: MimoEmotion.fear.palette,
                size: 40,
                animateAmbient: false
            )
            .frame(width: 52, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text("Time machine")
                    .font(MimoFont.headline(15))
                    .foregroundStyle(MimoPalette.ink)
                Text("Every change Mimo made, in order.")
                    .font(MimoFont.caption(11))
                    .foregroundStyle(MimoPalette.inkSecondary)
            }
            Spacer()

            if !auditLog.entries.isEmpty {
                trashButton
            }
        }
    }

    @ViewBuilder
    private var trashButton: some View {
        Button {
            showClearConfirm = true
        } label: {
            ZStack {
                Circle()
                    .fill(MimoEmotion.anger.wash)
                    .frame(width: 30, height: 30)
                Image(systemName: Constants.SystemImage.trash)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MimoEmotion.anger.body)
            }
        }
        .buttonStyle(.plain)
        .mimoPress()
        .help("Clear the entire audit log")
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 14) {
            MimoMascot(
                mood: .idle,
                palette: MimoEmotion.fear.palette,
                size: 96
            )
            .frame(height: 116)
            Text("Nothing's happened yet.")
                .font(MimoFont.headline(14))
                .foregroundStyle(MimoPalette.ink)
            Text("Once Mimo writes config, you'll see it here.")
                .font(MimoFont.body(11))
                .foregroundStyle(MimoPalette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Groups (Today / Yesterday / dates)

    private struct EntryGroup: Identifiable {
        let id: String
        let title: String
        let entries: [AuditEntry]
    }

    private var groupedEntries: [EntryGroup] {
        let calendar = Calendar.current
        let now = Date()
        // Key by start-of-day so two different Mondays don't collapse.
        var buckets: [(key: String, title: String, sortDate: Date, items: [AuditEntry])] = []

        for entry in auditLog.entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            let key = String(Int(day.timeIntervalSince1970))
            let title: String
            if calendar.isDateInToday(entry.timestamp) {
                title = "Today"
            } else if calendar.isDateInYesterday(entry.timestamp) {
                title = "Yesterday"
            } else if let diff = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: now)).day,
                      diff < 7 {
                let f = DateFormatter()
                f.dateFormat = "EEEE"
                title = f.string(from: entry.timestamp)
            } else {
                let f = DateFormatter()
                f.dateFormat = "MMM d, yyyy"
                title = f.string(from: entry.timestamp)
            }
            if let idx = buckets.firstIndex(where: { $0.key == key }) {
                buckets[idx].items.append(entry)
            } else {
                buckets.append((key, title, day, [entry]))
            }
        }
        return buckets.map { EntryGroup(id: $0.key, title: $0.title, entries: $0.items) }
    }

    @ViewBuilder
    private func groupHeader(_ group: EntryGroup) -> some View {
        HStack(spacing: 8) {
            Text(group.title)
                .font(MimoFont.caption(10, weight: .bold))
                .foregroundStyle(MimoPalette.inkTertiary)
                .textCase(.uppercase)
            Rectangle()
                .fill(MimoPalette.inkTertiary.opacity(0.18))
                .frame(height: 1)
        }
        .padding(.top, 6)
    }

    // MARK: - Audit row

    @ViewBuilder
    private func auditCard(_ entry: AuditEntry) -> some View {
        let palette = profilePalette(for: entry)
        let isReverting = revertingID == entry.id

        VStack(alignment: .leading, spacing: 10) {
            // Top row — profile dot, name, scope, timestamp
            HStack(alignment: .center, spacing: 10) {
                profileDot(palette: palette)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.profileName)
                            .font(MimoFont.body(13, weight: .semibold))
                            .foregroundStyle(MimoPalette.ink)
                            .strikethrough(entry.isReverted)
                        scopeBadge(entry.scope)
                    }
                    Text(entry.summary)
                        .font(MimoFont.body(12))
                        .foregroundStyle(MimoPalette.inkSecondary)
                        .strikethrough(entry.isReverted)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(relativeTimestamp(entry.timestamp))
                        .font(MimoFont.caption(10, weight: .semibold))
                        .foregroundStyle(MimoPalette.inkTertiary)
                        .help(Self.absoluteFormatter.string(from: entry.timestamp))
                    if entry.isReverted {
                        MimoBadge(text: "undone", palette: MimoEmotion.fear.palette)
                    }
                }
            }

            // Before / after — only render when we have something to show.
            if shouldShowDiff(entry) {
                diffStrip(entry: entry)
            }

            // Footer — path + undo
            HStack(spacing: 10) {
                if let path = entry.path {
                    pathChip(path)
                }
                Spacer()
                MimoPillButton(
                    title: entry.isReverted ? "Undone" : (isReverting ? "Undoing..." : "Undo"),
                    icon: entry.isReverted ? Constants.SystemImage.checkmark : Constants.SystemImage.undo,
                    palette: palette
                ) {
                    revert(entry)
                }
                .disabled(entry.isReverted || isReverting)
                .opacity(entry.isReverted ? 0.4 : 1.0)
            }
        }
        .padding(14)
        .mimoCard(cornerRadius: 16)
        .opacity(entry.isReverted ? 0.7 : 1.0)
    }

    @ViewBuilder
    private func profileDot(palette: MimoPaintPalette) -> some View {
        ZStack {
            Circle()
                .fill(palette.body)
                .frame(width: 30, height: 30)
                .shadow(color: palette.body.opacity(0.35), radius: 4, y: 1)
            Circle()
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                .frame(width: 30, height: 30)
        }
    }

    @ViewBuilder
    private func scopeBadge(_ scope: AuditScope) -> some View {
        HStack(spacing: 4) {
            Image(systemName: scope.iconName)
                .font(.system(size: 8, weight: .bold))
            Text(scope.label)
                .font(MimoFont.caption(9, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .foregroundStyle(MimoPalette.inkSecondary)
        .background(
            Capsule(style: .continuous)
                .fill(MimoPalette.surfaceSunken)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(MimoPalette.inkTertiary.opacity(0.2), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func pathChip(_ path: String) -> some View {
        Text(shorten(path))
            .font(MimoFont.mono(10, weight: .medium))
            .foregroundStyle(MimoPalette.inkTertiary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(MimoPalette.surfaceSunken)
            )
            .help(path)
    }

    @ViewBuilder
    private func diffStrip(entry: AuditEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let before = entry.before {
                diffLine(prefix: "−", text: before, palette: MimoEmotion.anger.palette)
            } else {
                diffLine(prefix: "−", text: "(not set)", palette: MimoEmotion.anger.palette, faded: true)
            }
            if let after = entry.after {
                diffLine(prefix: "+", text: after, palette: MimoEmotion.serenity.palette)
            } else {
                diffLine(prefix: "+", text: "(unset)", palette: MimoEmotion.serenity.palette, faded: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MimoPalette.surfaceSunken)
        )
    }

    @ViewBuilder
    private func diffLine(prefix: String, text: String, palette: MimoPaintPalette, faded: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(prefix)
                .font(MimoFont.mono(11, weight: .bold))
                .foregroundStyle(palette.body)
                .frame(width: 12, alignment: .leading)
            Text(truncated(text))
                .font(MimoFont.mono(10, weight: .medium))
                .foregroundStyle(faded ? MimoPalette.inkTertiary : MimoPalette.inkSecondary)
                .lineLimit(3)
        }
    }

    // MARK: - Helpers

    private func profilePalette(for entry: AuditEntry) -> MimoPaintPalette {
        if let profileID = entry.profileID,
           let profile = appModel.availableProfiles.first(where: { $0.id == profileID }) {
            return profile.colorID.palette
        }
        return MimoEmotion.fear.palette
    }

    private func relativeTimestamp(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        if interval < 60 {
            return "just now"
        }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    private func truncated(_ s: String) -> String {
        if s.count > 200 {
            return String(s.prefix(200)) + "…"
        }
        return s
    }

    /// Don't show diff lines for whole-file snapshots (sshConfig, mimoProfiles)
    /// — the content is too long to render usefully. We surface only the
    /// summary and a path chip for those scopes.
    private func shouldShowDiff(_ entry: AuditEntry) -> Bool {
        switch entry.scope {
        case .gitConfigGlobal, .gitConfigRepo:
            return true
        case .sshConfig, .mimoProfiles, .firstRunImport:
            return false
        }
    }

    private func shorten(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Revert flow

    private func revert(_ entry: AuditEntry) {
        revertingID = entry.id
        Task {
            do {
                _ = try await IdentityAuditLog.shared.revert(entry)
            } catch {
                revertError = error.localizedDescription
                showRevertError = true
            }
            revertingID = nil
            // Re-sync detection — the active profile may have flipped.
            await appModel.detectActiveProfile()
        }
    }
}
