import AVFoundation
import Foundation

/// Captures microphone audio with AVAudioEngine and delivers fixed-length
/// mono Int16 PCM frames to a callback.
///
/// `frameLength` is the exact number of samples each callback invocation
/// receives. Eagle requires fixed-size frames:
///   - During enrollment: feed `EagleProfiler.frameLength`
///   - During recognition: feed `Eagle.minProcessSamples()` (or any multiple
///     thereof — we use the value directly)
///
/// Frames smaller than `frameLength` are buffered internally until a full
/// frame is available. The audio thread is never blocked by Eagle work — the
/// callback runs on a serial dispatch queue.
final class AudioCaptureService: @unchecked Sendable {

    typealias FrameHandler = @Sendable ([Int16]) -> Void

    private let targetSampleRate: Double
    private let frameLength: Int
    private let queue: DispatchQueue

    private let audioEngine = AVAudioEngine()
    private let lock = NSLock()
    private var pendingSamples: [Int16] = []
    private var frameHandler: FrameHandler?
    private(set) var isRunning: Bool = false

    init(targetSampleRate: Double, frameLength: Int) {
        self.targetSampleRate = targetSampleRate
        self.frameLength = frameLength
        self.queue = DispatchQueue(label: "com.voiceideagle.audio", qos: .userInitiated)
    }

    /// Starts capturing. `handler` is invoked on a background queue with
    /// fixed-size mono Int16 PCM frames at `targetSampleRate`.
    func start(frameHandler: @escaping FrameHandler) throws {
        guard !isRunning else { return }

        try configureAudioSession()

        self.frameHandler = frameHandler
        self.pendingSamples.removeAll(keepingCapacity: true)

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        // Some devices return a zero-frame format when the mic isn't ready.
        guard inputFormat.sampleRate > 0 else {
            throw AppError.audioEngineFailed("Input format is unavailable.")
        }

        // Tap with the input node's native format. We resample/convert in
        // the buffer callback via PCMConverter.
        let bufferSize: AVAudioFrameCount = 1024
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.queue.async {
                self.handleBuffer(buffer)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AppError.audioEngineFailed(error.localizedDescription)
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRunning = false

        lock.lock()
        pendingSamples.removeAll(keepingCapacity: false)
        frameHandler = nil
        lock.unlock()

        // Best-effort: deactivate the session so other apps can reclaim it.
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Private

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .measurement,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setPreferredSampleRate(targetSampleRate)
            try session.setActive(true, options: [])
        } catch {
            throw AppError.audioEngineFailed(error.localizedDescription)
        }
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let samples = PCMConverter.convertToMonoInt16(
            buffer: buffer,
            targetSampleRate: targetSampleRate
        ), !samples.isEmpty else {
            return
        }

        lock.lock()
        pendingSamples.append(contentsOf: samples)

        var framesToDeliver: [[Int16]] = []
        while pendingSamples.count >= frameLength {
            let frame = Array(pendingSamples.prefix(frameLength))
            pendingSamples.removeFirst(frameLength)
            framesToDeliver.append(frame)
        }
        let handler = frameHandler
        lock.unlock()

        guard let handler else { return }
        for frame in framesToDeliver {
            handler(frame)
        }
    }
}
