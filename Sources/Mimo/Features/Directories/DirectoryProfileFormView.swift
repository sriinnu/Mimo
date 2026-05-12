//
//  DirectoryProfileFormView.swift
//  Mimo
//

import SwiftUI

struct DirectoryProfileFormView: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var isPresented: Bool
    @State private var directoryPath: String = ""
    @State private var selectedProfileID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Constants.Strings.addDirectory)
                .font(MimoFont.headline(14))
                .foregroundStyle(MimoPalette.ink)

            VStack(alignment: .leading, spacing: 4) {
                Text(Constants.Strings.directoryPath)
                    .font(MimoFont.caption(10))
                    .foregroundStyle(MimoPalette.inkTertiary)

                HStack(spacing: 8) {
                    TextField("/path/to/folder", text: $directoryPath)
                        .textFieldStyle(.roundedBorder)
                        .font(MimoFont.body(12))

                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            directoryPath = url.path
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: Constants.SystemImage.folder)
                                .font(.system(size: 10, weight: .semibold))
                            Text(Constants.Strings.browse)
                                .font(MimoFont.caption(11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(MimoPalette.ink)
                        .background(
                            Capsule(style: .continuous).fill(MimoPalette.surfaceSunken)
                        )
                    }
                    .buttonStyle(.plain)
                    .mimoPress()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Constants.Strings.selectProfile)
                    .font(MimoFont.caption(10))
                    .foregroundStyle(MimoPalette.inkTertiary)

                Picker("", selection: $selectedProfileID) {
                    Text("Choose...").tag(nil as UUID?)
                    ForEach(appModel.availableProfiles) { profile in
                        Text(profile.name).tag(profile.id as UUID?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            HStack {
                Spacer()
                MimoPillButton(
                    title: "Save mapping",
                    icon: Constants.SystemImage.checkmark,
                    emotion: .disgust,
                    prominent: true
                ) {
                    guard let profileID = selectedProfileID, !directoryPath.isEmpty else { return }
                    appModel.addDirectoryProfile(directoryPath: directoryPath, profileID: profileID)
                    withAnimation(MimoMotion.snap) { isPresented = false }
                }
                .disabled(directoryPath.isEmpty || selectedProfileID == nil)
                .opacity((directoryPath.isEmpty || selectedProfileID == nil) ? 0.55 : 1.0)
            }
        }
        .padding(18)
        .mimoCard(cornerRadius: 18)
    }
}
