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
    private var captureStartTime: Date?
    private var isCompletingEnrollment = false

    init(profileStore: SpeakerProfileStore,
         permissionService: MicrophonePermissionService,
         enrollmentService: EagleEnrollmentService) {
        self.profileStore = profileStore
        self.permissionService = permissionService
        self.enrollmentService = enrollmentService
    }

    convenience init(profileStore: SpeakerProfileStore,
                     permissionService: MicrophonePermissionService) {
        self.init(
            profileStore: profileStore,
            permissionService: permissionService,
            enrollmentService: EagleEnrollmentService()
        )
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
        captureStartTime = nil
        isCompletingEnrollment = false
        state = .idle
        step = .nameEntry
    }

    func reset() {
        stopAudioCapture()
        enrollmentService.reset()
        captureStartTime = nil
        isCompletingEnrollment = false
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
                        let elapsed = Date().timeIntervalSince(self.captureStartTime ?? .distantPast)
                        let minimumMet = elapsed >= AppConfig.minEnrollmentDurationSec
                        if percent >= 100, minimumMet, !self.isCompletingEnrollment {
                            self.isCompletingEnrollment = true
                            await self.completeEnrollment()
                        } else {
                            // Before minimum duration is met, show time-based
                            // progress so the UI continues to move naturally.
                            let timePercent = Float(
                                min(
                                    max(elapsed / AppConfig.minEnrollmentDurationSec, 0),
                                    0.99
                                ) * 100
                            )
                            let displayed = minimumMet ? percent : timePercent
                            self.state = .enrolling(percent: Double(displayed))
                        }
                    }
                } catch let error as AppError {
                    Task { @MainActor [weak self] in self?.fail(error) }
                } catch {
                    let message = error.localizedDescription
                    Task { @MainActor [weak self] in
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
        captureStartTime = Date()
        isCompletingEnrollment = false
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
        captureStartTime = nil

        let profile = SpeakerProfile(name: name, profileData: bytes)
        profileStore.saveProfile(profile)

        state = .complete
        step = .finished
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func fail(_ error: AppError) {
        // Ignore late frame errors once enrollment is no longer actively capturing.
        guard step == .capturing else { return }
        if case .complete = state { return }
        stopAudioCapture()
        enrollmentService.stop()
        captureStartTime = nil
        isCompletingEnrollment = false
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

}
