import Foundation

/// A persisted Eagle voice profile associated with a display name.
///
/// `profileData` holds the raw bytes returned from `EagleProfile.getBytes()`
/// (or whatever the equivalent serialization method on `EagleProfile` is in
/// your installed SDK version — see `EagleProfileBytesAdapter`).
struct SpeakerProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    var profileData: Data

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), profileData: Data) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.profileData = profileData
    }

    var profileSizeBytes: Int { profileData.count }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useBytes]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(profileSizeBytes))
    }
}
