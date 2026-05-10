import Combine
import Foundation

@MainActor
final class ProfileManagementViewModel: ObservableObject {

    @Published var profiles: [SpeakerProfile] = []
    @Published var alertMessage: String?

    private let profileStore: SpeakerProfileStore
    private var cancellables = Set<AnyCancellable>()

    init(profileStore: SpeakerProfileStore) {
        self.profileStore = profileStore
        profileStore.$profiles
            .receive(on: RunLoop.main)
            .assign(to: &$profiles)
    }

    func deleteProfile(id: UUID) {
        profileStore.deleteProfile(id: id)
    }

    func renameProfile(id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alertMessage = AppError.emptyName.errorDescription
            return
        }
        if profileStore.nameExists(trimmed, excluding: id) {
            alertMessage = AppError.duplicateName.errorDescription
            return
        }
        profileStore.renameProfile(id: id, to: trimmed)
    }

    func deleteAllProfiles() {
        profileStore.deleteAllProfiles()
    }
}
