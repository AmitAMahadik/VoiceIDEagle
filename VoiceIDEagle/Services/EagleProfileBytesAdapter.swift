import Foundation
import Eagle

/// Isolates the small part of the Eagle SDK whose API shape sometimes
/// differs between releases: serializing and deserializing `EagleProfile`.
///
/// As of the current Eagle iOS SDK the canonical surface is:
///     public init(profileBytes: [UInt8])
///     public func getBytes() -> [UInt8]
///
/// If your installed SDK version names these differently (e.g. it exposes a
/// `Data`-returning variant, throws, or names the initializer `init(bytes:)`)
/// update this single file. The rest of the app calls only these two
/// helpers.
enum EagleProfileBytesAdapter {

    /// Returns the raw bytes of an `EagleProfile`, ready to persist.
    static func bytes(from profile: EagleProfile) -> Data {
        let raw = profile.getBytes()
        return Data(raw)
    }

    /// Reconstructs an `EagleProfile` from previously persisted bytes.
    static func profile(from data: Data) throws -> EagleProfile {
        guard !data.isEmpty else { throw AppError.corruptProfileData }
        let bytes = [UInt8](data)
        return EagleProfile(profileBytes: bytes)
    }
}
