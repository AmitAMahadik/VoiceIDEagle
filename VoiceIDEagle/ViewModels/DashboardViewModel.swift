import Combine
import Foundation
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {

    @Published var profileCount: Int = 0
    @Published var permissionStatus: MicrophonePermissionService.Status = .undetermined
    @Published var sdkReady: Bool = false
    @Published var eagleReady: Bool = false
    @Published var falconReady: Bool = false
    @Published var configurationError: String?

    let permissionService: MicrophonePermissionService
    let profileStore: SpeakerProfileStore

    private var cancellables = Set<AnyCancellable>()

    init(permissionService: MicrophonePermissionService,
         profileStore: SpeakerProfileStore) {
        self.permissionService = permissionService
        self.profileStore = profileStore

        permissionService.$status
            .receive(on: RunLoop.main)
            .assign(to: &$permissionStatus)

        profileStore.$profiles
            .map(\.count)
            .receive(on: RunLoop.main)
            .assign(to: &$profileCount)

        evaluateConfiguration()
    }

    @MainActor
    static func make() -> DashboardViewModel {
        DashboardViewModel(permissionService: MicrophonePermissionService(),
                           profileStore: SpeakerProfileStore())
    }

    func refresh() {
        permissionService.refresh()
        _ = profileStore.loadProfiles()
        evaluateConfiguration()
    }

    func requestMicrophonePermission() {
        Task { _ = await permissionService.requestIfNeeded() }
    }

    private func evaluateConfiguration() {
        if AppConfig.picovoiceAccessKeyIfPresent == nil {
            configurationError = AppError.missingAccessKey.errorDescription
            sdkReady = false
            eagleReady = false
            falconReady = false
        } else {
            configurationError = nil

            var eagleError: AppError?
            var falconError: AppError?

            let eagleService = EagleEnrollmentService()
            do {
                try eagleService.start()
                eagleReady = true
            } catch let error as AppError {
                eagleReady = false
                eagleError = error
            } catch {
                eagleReady = false
                eagleError = .eagleInitializationFailed(error.localizedDescription)
            }
            eagleService.stop()

            let falconService = FalconDiarizationService()
            do {
                try falconService.start()
                falconReady = true
            } catch let error as AppError {
                falconReady = false
                falconError = error
            } catch {
                falconReady = false
                falconError = .falconInitializationFailed(error.localizedDescription)
            }
            falconService.stop()

            sdkReady = eagleReady && falconReady
            configurationError = eagleError?.errorDescription ?? falconError?.errorDescription
        }
    }
}
