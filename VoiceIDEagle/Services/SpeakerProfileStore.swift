import Combine
import Foundation

/// Local-only persistence for `SpeakerProfile` records.
///
/// Profiles are stored as a single Codable JSON file inside the app's
/// Application Support directory. The Eagle profile bytes live inside the
/// JSON as base64 (Foundation's default `Data` Codable representation).
@MainActor
final class SpeakerProfileStore: ObservableObject {

    @Published private(set) var profiles: [SpeakerProfile] = []

    private let storeURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let supportDir: URL
        do {
            supportDir = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            // Fall back to caches if Application Support is unavailable.
            supportDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        }

        let appDir = supportDir.appendingPathComponent("VoiceIDEagle", isDirectory: true)
        if !fileManager.fileExists(atPath: appDir.path) {
            try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        }

        self.storeURL = appDir.appendingPathComponent("profiles.json")
        self.profiles = loadProfiles()
    }

    // MARK: - CRUD

    func loadProfiles() -> [SpeakerProfile] {
        guard fileManager.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let decoded = try decoder.decode([SpeakerProfile].self, from: data)
            self.profiles = decoded
            return decoded
        } catch {
            // Corrupt or older format. Start clean rather than crash.
            #if DEBUG
            print("SpeakerProfileStore: failed to decode \(storeURL.path): \(error)")
            #endif
            return []
        }
    }

    @discardableResult
    func saveProfile(_ profile: SpeakerProfile) -> Bool {
        if profiles.contains(where: { $0.id == profile.id }) {
            return updateProfile(profile)
        }
        profiles.append(profile)
        return persist()
    }

    @discardableResult
    func updateProfile(_ profile: SpeakerProfile) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return false
        }
        profiles[index] = profile
        return persist()
    }

    @discardableResult
    func renameProfile(id: UUID, to newName: String) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            return false
        }
        profiles[index].name = newName
        return persist()
    }

    @discardableResult
    func deleteProfile(id: UUID) -> Bool {
        profiles.removeAll { $0.id == id }
        return persist()
    }

    @discardableResult
    func deleteAllProfiles() -> Bool {
        profiles.removeAll()
        return persist()
    }

    func nameExists(_ name: String, excluding id: UUID? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces).lowercased()
        return profiles.contains { profile in
            profile.id != id &&
            profile.name.trimmingCharacters(in: .whitespaces).lowercased() == trimmed
        }
    }

    // MARK: - Private

    @discardableResult
    private func persist() -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(profiles)
            try data.write(to: storeURL, options: [.atomic])
            return true
        } catch {
            #if DEBUG
            print("SpeakerProfileStore: failed to persist: \(error)")
            #endif
            return false
        }
    }
}
