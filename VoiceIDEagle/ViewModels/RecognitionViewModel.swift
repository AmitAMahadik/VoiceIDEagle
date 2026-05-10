import Combine
import Foundation
import UIKit

@MainActor
final class RecognitionViewModel: ObservableObject {

    @Published var state: RecognitionState = .idle
    @Published var scores: [SpeakerScore] = []
    @Published var bestMatch: SpeakerScore?
    @Published var threshold: Float
    @Published var alertMessage: String?

    private let profileStore: SpeakerProfileStore
    private let permissionService: MicrophonePermissionService
    private let recognitionService: EagleRecognitionService
    private var audioCapture: AudioCaptureService?

    /// Rolling window of recent score frames used to smooth the displayed
    /// values. Kept on the main actor; mutated only from main.
    private var recentFrames: [[Float]] = []
    private let smoothingWindow = 5

    /// Track whether the last identification fired haptic feedback so we
    /// don't fire it on every frame the user remains identified.
    private var lastIdentifiedID: UUID?

    init(profileStore: SpeakerProfileStore,
         permissionService: MicrophonePermissionService,
         recognitionService: EagleRecognitionService) {
        self.profileStore = profileStore
        self.permissionService = permissionService
        self.recognitionService = recognitionService

        let saved = UserDefaults.standard.float(forKey: AppConfig.identificationThresholdKey)
        self.threshold = saved == 0 ? AppConfig.defaultIdentificationThreshold : saved
    }

    convenience init(profileStore: SpeakerProfileStore,
                     permissionService: MicrophonePermissionService) {
        self.init(
            profileStore: profileStore,
            permissionService: permissionService,
            recognitionService: EagleRecognitionService()
        )
    }

    // MARK: - Controls

    func startListening() {
        Task { await beginListening() }
    }

    func stopListening() {
        audioCapture?.stop()
        audioCapture = nil
        recognitionService.stop()
        state = .stopped
    }

    func resetSession() {
        recognitionService.reset()
        recentFrames.removeAll()
        scores = []
        bestMatch = nil
        lastIdentifiedID = nil
        if state != .idle, state != .stopped {
            state = .listening
        }
    }

    func updateThreshold(_ value: Float) {
        threshold = value
        UserDefaults.standard.set(value, forKey: AppConfig.identificationThresholdKey)
        recomputeBestMatch()
    }

    // MARK: - Listening

    private func beginListening() async {
        guard AppConfig.picovoiceAccessKeyIfPresent != nil else {
            present(.missingAccessKey); return
        }

        let profiles = profileStore.profiles
        guard !profiles.isEmpty else {
            present(.noEnrolledProfiles); return
        }

        let granted = await permissionService.requestIfNeeded()
        guard granted else {
            present(.microphonePermissionDenied); return
        }

        do {
            try recognitionService.start(profiles: profiles)
        } catch let error as AppError {
            present(error); return
        } catch {
            present(.eagleInitializationFailed(error.localizedDescription)); return
        }

        let frameLength = recognitionService.minProcessSamples
        guard frameLength > 0 else {
            recognitionService.stop()
            present(.eagleInitializationFailed("Eagle reported a zero-length frame size."))
            return
        }

        recentFrames.removeAll()
        scores = profiles.map { SpeakerScore(speaker: $0, score: 0) }
        bestMatch = nil
        lastIdentifiedID = nil

        let capture = AudioCaptureService(
            targetSampleRate: Double(EagleRecognitionService.sampleRate),
            frameLength: frameLength
        )
        self.audioCapture = capture

        let recognitionService = self.recognitionService

        do {
            try capture.start { [weak self] frame in
                // Audio capture serial queue. Eagle work routes through its
                // own internal queue, so this call is thread-safe.
                do {
                    let scores = try recognitionService.processFrame(frame)
                    let orderedProfiles = recognitionService.profilesInOrder
                    Task { @MainActor [weak self] in
                        self?.applyScores(scores, profiles: orderedProfiles)
                    }
                } catch let error as AppError {
                    Task { @MainActor [weak self] in self?.fail(error) }
                } catch {
                    let message = error.localizedDescription
                    Task { @MainActor [weak self] in
                        self?.fail(.recognitionFailed(message))
                    }
                }
            }
        } catch let error as AppError {
            recognitionService.stop()
            present(error); return
        } catch {
            recognitionService.stop()
            present(.audioEngineFailed(error.localizedDescription)); return
        }

        state = .listening
    }

    private func applyScores(_ scoreVector: [Float]?, profiles: [SpeakerProfile]) {
        guard let scoreVector, !scoreVector.isEmpty, scoreVector.count == profiles.count else {
            // Not enough audio yet — keep prior scores faded but preserve
            // the listening state.
            if state != .stopped { state = .listening }
            return
        }

        recentFrames.append(scoreVector)
        if recentFrames.count > smoothingWindow {
            recentFrames.removeFirst(recentFrames.count - smoothingWindow)
        }

        let smoothed = averagedScores(recentFrames, profileCount: profiles.count)
        let speakerScores = zip(profiles, smoothed).map { SpeakerScore(speaker: $0, score: $1) }
            .sorted { $0.score > $1.score }
        self.scores = speakerScores
        state = .identifying
        recomputeBestMatch()
    }

    private func averagedScores(_ frames: [[Float]], profileCount: Int) -> [Float] {
        guard !frames.isEmpty else { return Array(repeating: 0, count: profileCount) }
        var totals = Array(repeating: Float(0), count: profileCount)
        for frame in frames {
            for index in 0..<min(frame.count, profileCount) {
                totals[index] += frame[index]
            }
        }
        return totals.map { $0 / Float(frames.count) }
    }

    private func recomputeBestMatch() {
        guard let top = scores.first else {
            bestMatch = nil
            return
        }
        if top.score >= threshold {
            bestMatch = top
            if lastIdentifiedID != top.id {
                lastIdentifiedID = top.id
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } else {
            bestMatch = nil
            lastIdentifiedID = nil
        }
    }

    private func fail(_ error: AppError) {
        if case .stopped = state { return }
        audioCapture?.stop()
        audioCapture = nil
        recognitionService.stop()
        state = .failed(error.errorDescription ?? "Unknown error")
        alertMessage = error.errorDescription
    }

    private func present(_ error: AppError) {
        alertMessage = error.errorDescription
    }

}
