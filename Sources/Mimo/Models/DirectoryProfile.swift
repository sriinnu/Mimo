//
//  DirectoryProfile.swift
//  Mimo
//

import Foundation

struct DirectoryProfile: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var directoryPath: String
    var profileID: UUID

    init(
        id: UUID = UUID(),
        directoryPath: String,
        profileID: UUID
    ) {
        self.id = id
        self.directoryPath = directoryPath
        self.profileID = profileID
    }
}
