import Combine
import Foundation
import UIKit
import Falcon

/// Orchestrates the record → Falcon → Eagle pipeline for diarization.
///
/// Flow:
/// 1. The user starts recording. Mic audio is captured via the shared
///    `AudioCaptureService` at Falcon's required sample rate. Every PCM
///    frame is appended to an in-memory buffer.
/// 2. The user stops recording. We hand the full buffer to Falcon to
///    diarize, then group the PCM by speaker tag and run Eagle on each
///    group via `EagleSegmentClassifier`.
/// 3. For each unique tag, the best-matching enrolled profile is chosen if
///    its averaged Eagle score is at or above the identification threshold.
///    Tags that don't clear the threshold (or have no enrolled profiles)
///    fall back to "Speaker N".
@MainActor
final class DiarizationViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case recording
        case processing
        case results
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var segments: [DiarizedSegment] = []
    @Published private(set) var elapsedSec: TimeInterval = 0
    @Published var threshold: Float
    @Published var alertMessage: String?

    /// Hard cap on recording length so the buffer doesn't grow unbounded.
    /// At 16 kHz mono Int16 this is ~9.6 MB / 5 minutes — comfortable.
    nonisolated static let maxRecordingSec: TimeInterval = 5 * 60

    private let profileStore: SpeakerProfileStore
    private let permissionService: MicrophonePermissionService
    private let falconService: FalconDiarizationService
    private let classifier: EagleSegmentClassifier

    private var audioCapture: AudioCaptureService?
    private var recordingStart: Date?
    private var elapsedTimerTask: Task<Void, Never>?

    /// Thread-safe scratch buffer for incoming PCM. Owned as a Sendable
    /// class so it can be captured into the audio thread's frame handler
    /// without main-actor isolation concerns.
    private let captureBuffer = CaptureBuffer()

    /// Per-tag averaged score vectors from the most recent Eagle pass.
    /// Keeping these around lets us re-label segments live when the user
    /// adjusts the threshold without re-running the pipeline.
    private var tagScores: [Int: [Float]] = [:]
    private var orderedProfiles: [SpeakerProfile] = []
    private var rawSegments: [RawSegment] = []

    init(
        profileStore: SpeakerProfileStore,
        permissionService: MicrophonePermissionService,
        falconService: FalconDiarizationService,
        classifier: EagleSegmentClassifier
    ) {
        self.profileStore = profileStore
        self.permissionService = permissionService
        self.falconService = falconService
        self.classifier = classifier

        let saved = UserDefaults.standard.float(forKey: AppConfig.identificationThresholdKey)
        self.threshold = saved == 0 ? AppConfig.defaultIdentificationThreshold : saved
    }

    // MARK: - Controls

    func startRecording() {
        Task { await beginRecording() }
    }

    func stopAndAnalyze() {
        guard phase == .recording else { return }
        let pcm = stopCaptureAndDrain()
        elapsedTimerTask?.cancel()
        elapsedTimerTask = nil

        guard !pcm.isEmpty else {
            falconService.stop()
            present(.noAudioCaptured)
            return
        }

        let profiles = profileStore.profiles
        let threshold = self.threshold
        phase = .processing

        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let result = try self.runPipeline(
                    pcm: pcm,
                    profiles: profiles,
                    falcon: self.falconService,
                    classifier: self.classifier,
                    threshold: threshold
                )
                self.falconService.stop()
                self.classifier.reset()
                self.applyResult(result)
            } catch let error as AppError {
                self.falconService.stop()
                self.classifier.reset()
                self.fail(error)
            } catch {
                self.falconService.stop()
                self.classifier.reset()
                let message = error.localizedDescription
                self.fail(.diarizationFailed(message))
            }
        }
    }

    func cancel() {
        _ = stopCaptureAndDrain()
        elapsedTimerTask?.cancel()
        elapsedTimerTask = nil
        falconService.stop()
        classifier.reset()
        segments = []
        rawSegments = []
        tagScores = [:]
        orderedProfiles = []
        elapsedSec = 0
        phase = .idle
    }

    func updateThreshold(_ value: Float) {
        threshold = value
        UserDefaults.standard.set(value, forKey: AppConfig.identificationThresholdKey)
        relabelSegments()
    }

    // MARK: - Recording

    private func beginRecording() async {
        guard AppConfig.picovoiceAccessKeyIfPresent != nil else {
            present(.missingAccessKey); return
        }

        let granted = await permissionService.requestIfNeeded()
        guard granted else {
            present(.microphonePermissionDenied); return
        }

        // Spin up Falcon eagerly so any activation error surfaces before we
        // ask the user to keep talking for 30 seconds.
        do {
            try falconService.start()
        } catch let error as AppError {
            present(error); return
        } catch {
            present(.falconInitializationFailed(error.localizedDescription)); return
        }

        clearBuffer()
        segments = []
        rawSegments = []
        tagScores = [:]
        orderedProfiles = []

        // Frame size here is just our delivery cadence — Falcon doesn't
        // require fixed frames. 1600 samples ≈ 100 ms at 16 kHz.
        let capture = AudioCaptureService(
            targetSampleRate: Double(FalconDiarizationService.sampleRate),
            frameLength: 1600
        )
        self.audioCapture = capture

        let buffer = self.captureBuffer
        do {
            try capture.start { [weak self] frame in
                let count = buffer.append(frame)
                let secs = Double(count) / Double(FalconDiarizationService.sampleRate)
                if secs >= Self.maxRecordingSec {
                    Task { @MainActor [weak self] in self?.stopAndAnalyze() }
                }
            }
        } catch let error as AppError {
            audioCapture = nil
            falconService.stop()
            present(error); return
        } catch {
            audioCapture = nil
            falconService.stop()
            present(.audioEngineFailed(error.localizedDescription)); return
        }

        recordingStart = Date()
        elapsedSec = 0
        phase = .recording
        startElapsedTimer()
    }

    private func startElapsedTimer() {
        elapsedTimerTask?.cancel()
        elapsedTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self, let start = self.recordingStart else { continue }
                self.elapsedSec = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopCaptureAndDrain() -> [Int16] {
        audioCapture?.stop()
        audioCapture = nil
        recordingStart = nil
        return captureBuffer.drain()
    }

    private func clearBuffer() {
        captureBuffer.clear()
    }

    // MARK: - Pipeline (runs off the main actor)

    private struct RawSegment: Sendable, Hashable {
        let tag: Int
        let startSec: Float
        let endSec: Float
    }

    private struct PipelineResult: Sendable {
        let rawSegments: [RawSegment]
        let tagScores: [Int: [Float]]
        let orderedProfiles: [SpeakerProfile]
    }

    private func runPipeline(
        pcm: [Int16],
        profiles: [SpeakerProfile],
        falcon: FalconDiarizationService,
        classifier: EagleSegmentClassifier,
        threshold: Float
    ) throws -> PipelineResult {
        // 1. Falcon diarization.
        let falconSegments = try falcon.process(pcm: pcm)
        let raw = falconSegments.map { RawSegment(tag: $0.speakerTag, startSec: $0.startSec, endSec: $0.endSec) }

        // 2. If there are no enrolled profiles we don't need Eagle at all —
        // every segment will just become "Speaker N".
        guard !profiles.isEmpty else {
            return PipelineResult(rawSegments: raw, tagScores: [:], orderedProfiles: [])
        }

        // 3. Group PCM by Falcon tag.
        let sampleRate = Float(FalconDiarizationService.sampleRate)
        var pcmByTag: [Int: [Int16]] = [:]
        for segment in falconSegments {
            let startIdx = max(0, Int((segment.startSec * sampleRate).rounded()))
            let endIdx = min(pcm.count, Int((segment.endSec * sampleRate).rounded()))
            guard endIdx > startIdx else { continue }
            pcmByTag[segment.speakerTag, default: []].append(contentsOf: pcm[startIdx..<endIdx])
        }

        // 4. Run Eagle once per tag against all enrolled profiles.
        try classifier.prepare(profiles: profiles)
        var scores: [Int: [Float]] = [:]
        for (tag, tagPCM) in pcmByTag {
            if let vector = try classifier.classify(pcm: tagPCM) {
                scores[tag] = vector
            }
        }

        return PipelineResult(
            rawSegments: raw,
            tagScores: scores,
            orderedProfiles: profiles
        )
    }

    // MARK: - Result handling

    private func applyResult(_ result: PipelineResult) {
        rawSegments = result.rawSegments
        tagScores = result.tagScores
        orderedProfiles = result.orderedProfiles
        relabelSegments()

        if rawSegments.isEmpty {
            phase = .idle
            alertMessage = "Falcon found no speaker segments. Try a longer or clearer recording."
        } else {
            phase = .results
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// Recomputes display names for all segments using the cached per-tag
    /// scores. Cheap enough to call on every threshold change.
    private func relabelSegments() {
        guard !rawSegments.isEmpty else {
            segments = []; return
        }

        // Resolve each unique tag to a display name once, then map.
        var nameForTag: [Int: (name: String, confidence: Float)] = [:]
        for (tag, scoreVector) in tagScores {
            guard !scoreVector.isEmpty,
                  scoreVector.count == orderedProfiles.count else { continue }
            var bestIndex = 0
            var bestScore = scoreVector[0]
            for index in 1..<scoreVector.count where scoreVector[index] > bestScore {
                bestScore = scoreVector[index]
                bestIndex = index
            }
            if bestScore >= threshold {
                nameForTag[tag] = (orderedProfiles[bestIndex].name, bestScore)
            }
        }

        segments = rawSegments.map { raw in
            let resolved = nameForTag[raw.tag]
            return DiarizedSegment(
                speakerTag: raw.tag,
                startSec: raw.startSec,
                endSec: raw.endSec,
                speakerName: resolved?.name,
                confidence: resolved?.confidence
            )
        }
    }

    private func present(_ error: AppError) {
        alertMessage = error.errorDescription
        if phase == .recording || phase == .processing {
            phase = .failed(error.errorDescription ?? "Unknown error")
        }
    }

    private func fail(_ error: AppError) {
        alertMessage = error.errorDescription
        phase = .failed(error.errorDescription ?? "Unknown error")
    }

}

/// Thread-safe append-only PCM buffer. Lives outside the main actor so the
/// audio capture thread can write to it without crossing isolation
/// boundaries. All access is serialized through an internal `NSLock`.
private final class CaptureBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Int16] = []

    @discardableResult
    func append(_ frame: [Int16]) -> Int {
        lock.lock(); defer { lock.unlock() }
        samples.append(contentsOf: frame)
        return samples.count
    }

    func drain() -> [Int16] {
        lock.lock(); defer { lock.unlock() }
        let result = samples
        samples.removeAll(keepingCapacity: false)
        return result
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        samples.removeAll(keepingCapacity: true)
    }
}
