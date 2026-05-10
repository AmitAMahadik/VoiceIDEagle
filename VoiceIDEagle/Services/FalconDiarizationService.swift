import Foundation
import Falcon

/// Wraps the Picovoice `Falcon` speaker-diarization engine.
///
/// Falcon is a **batch** API in the iOS binding: `process(_ pcm:)` consumes
/// the full audio buffer and returns all detected segments in one call. We
/// keep one engine alive across the recording session so the cost of
/// initializing the model is paid once.
///
/// All SDK calls run on a serial dispatch queue so we never re-enter the
/// engine concurrently and the audio thread never blocks on it.
final class FalconDiarizationService: @unchecked Sendable {

    /// Required audio sample rate (16 kHz on current SDK builds).
    static var sampleRate: Int { Int(Falcon.sampleRate) }

    private var falcon: Falcon?
    private let queue = DispatchQueue(label: "com.voiceideagle.falcon", qos: .userInitiated)

    // MARK: - Lifecycle

    func start() throws {
        try queue.sync {
            guard falcon == nil else { return }
            do {
                falcon = try Falcon(accessKey: AppConfig.picovoiceAccessKey)
            } catch let error as FalconError {
                throw AppError.from(error, fallback: .falconInitializationFailed(error.localizedDescription))
            } catch {
                throw AppError.falconInitializationFailed(error.localizedDescription)
            }
        }
    }

    /// Diarizes the supplied PCM buffer in one shot.
    func process(pcm: [Int16]) throws -> [FalconSegment] {
        try queue.sync {
            guard let falcon else {
                throw AppError.diarizationFailed("Falcon is not initialized.")
            }
            guard !pcm.isEmpty else { throw AppError.noAudioCaptured }
            do {
                return try falcon.process(pcm)
            } catch let error as FalconError {
                throw AppError.from(error, fallback: .diarizationFailed(error.localizedDescription))
            } catch {
                throw AppError.diarizationFailed(error.localizedDescription)
            }
        }
    }

    func stop() {
        queue.sync {
            falcon?.delete()
            falcon = nil
        }
    }

    deinit {
        falcon?.delete()
        falcon = nil
    }
}
