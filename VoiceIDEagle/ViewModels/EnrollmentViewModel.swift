import Combine
import Foundation
import UIKit

@MainActor
final class EnrollmentViewModel: ObservableObject {

    enum Step: Equatable {
        case nameEntry
        case instructions
        case capturing
        case finished
    }

    @Published var step: Step = .nameEntry
    @Published var name: String = ""
    @Published var state: EnrollmentState = .idle
    @Published var alertMessage: String?

    private let profileStore: SpeakerProfileStore
    private let permissionService: MicrophonePermissionService
    private let enrollmentService: EagleEnrollmentService
    private var audioCapture: AudioCaptureService?

    init(profileStore: SpeakerProfileStore,
         permissionService: MicrophonePermissionService,
         enrollmentService: EagleEnrollmentService = EagleEnrollmentService()) {
        self.profileStore = profileStore
        self.permissionService = permissionService
        self.enrollmentService = enrollmentService
    }

    // MARK: - Step transitions

    func proceedFromNameEntry() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            present(.emptyName); return
        }
        if profileStore.nameExists(trimmed) {
            present(.duplicateName); return
        }
        name = trimmed
        step = .instructions
    }

    func proceedFromInstructions() {
        Task { await beginEnrollment() }
    }

    func cancel() {
        stopAudioCapture()
        enrollmentService.stop()
        state = .idle
        step = .nameEntry
    }

    func reset() {
        stopAudioCapture()
        enrollmentService.reset()
        state = .idle
        step = .instructions
    }

    // MARK: - Enrollment

    private func beginEnrollment() async {
        guard AppConfig.picovoiceAccessKeyIfPresent != nil else {
            present(.missingAccessKey); return
        }

        let granted = await permissionService.requestIfNeeded()
        guard granted else {
            present(.microphonePermissionDenied); return
        }

        do {
            try enrollmentService.start()
        } catch let error as AppError {
            present(error); return
        } catch {
            present(.eagleInitializationFailed(error.localizedDescription)); return
        }

        let capture = AudioCaptureService(
            targetSampleRate: Double(EagleEnrollmentService.sampleRate),
            frameLength: EagleEnrollmentService.frameLength
        )
        self.audioCapture = capture

        // Capture services locally so the @Sendable closure does not need
        // to reach back through `self` (which is MainActor-isolated).
        let enrollmentService = self.enrollmentService

        do {
            try capture.start { [weak self] frame in
                // This runs on the audio capture's serial queue.
                // EagleEnrollmentService routes calls through its own
                // internal queue so this synchronous call is safe.
                do {
                    let percent = try enrollmentService.processFrame(frame)
                    Task { @MainActor in
                        guard let self else { return }
                        if percent >= 100 {
                            await self.completeEnrollment()
                        } else {
                            self.state = .enrolling(percent: Double(percent))
                        }
                    }
                } catch let error as AppError {
                    Task { @MainActor in self?.fail(error) }
                } catch {
                    let message = error.localizedDescription
                    Task { @MainActor in
                        self?.fail(.enrollmentFailed(message))
                    }
                }
            }
        } catch let error as AppError {
            enrollmentService.stop()
            present(error); return
        } catch {
            enrollmentService.stop()
            present(.audioEngineFailed(error.localizedDescription)); return
        }

        state = .listening
        step = .capturing
    }

    private func completeEnrollment() async {
        // Stop audio first so no more frames arrive while we export.
        stopAudioCapture()

        let bytes: Data
        do {
            bytes = try enrollmentService.exportProfile()
        } catch let error as AppError {
            enrollmentService.stop()
            present(error); return
        } catch {
            enrollmentService.stop()
            present(.enrollmentFailed(error.localizedDescription)); return
        }

        enrollmentService.stop()

        let profile = SpeakerProfile(name: name, profileData: bytes)
        profileStore.saveProfile(profile)

        state = .complete
        step = .finished
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func fail(_ error: AppError) {
        // Ignore late-arriving frame errors after we've already completed.
        if step == .finished { return }
        if case .complete = state { return }
        stopAudioCapture()
        enrollmentService.stop()
        state = .failed(error.errorDescription ?? "Unknown error")
        alertMessage = error.errorDescription
    }

    // MARK: - Helpers

    private func stopAudioCapture() {
        audioCapture?.stop()
        audioCapture = nil
    }

    private func present(_ error: AppError) {
        alertMessage = error.errorDescription
        if state.isActive {
            state = .failed(error.errorDescription ?? "Unknown error")
        }
    }

    deinit {
        // Ensure resources are released even if the view goes away mid-flow.
        audioCapture?.stop()
        // enrollmentService handles its own cleanup in deinit.
    }
}
