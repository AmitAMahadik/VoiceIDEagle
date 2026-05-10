import Foundation
import Eagle

/// Wraps the Picovoice `EagleProfiler` lifecycle for the enrollment flow.
///
/// All Eagle calls are routed through a serial dispatch queue so the audio
/// capture thread never blocks on SDK work and we never re-enter the SDK
/// concurrently.
final class EagleEnrollmentService: @unchecked Sendable {

    /// Required audio sample rate (16 kHz on current SDK builds).
    static var sampleRate: Int { EagleProfiler.sampleRate }

    /// Required frame size for `enroll(pcm:)`.
    static var frameLength: Int { EagleProfiler.frameLength }

    private var profiler: EagleProfiler?
    private let queue = DispatchQueue(label: "com.voiceideagle.eagle.enroll", qos: .userInitiated)

    // MARK: - Lifecycle

    func start() throws {
        try queue.sync {
            guard profiler == nil else { return }
            do {
                profiler = try EagleProfiler(
                    accessKey: AppConfig.picovoiceAccessKey,
                    voiceThreshold: AppConfig.voiceThreshold
                )
            } catch let error as EagleError {
                throw AppError.from(error, fallback: .eagleInitializationFailed(error.localizedDescription))
            } catch {
                throw AppError.eagleInitializationFailed(error.localizedDescription)
            }
        }
    }

    /// Feeds one PCM frame into the profiler. Returns the current enrollment
    /// percentage (0..100).
    @discardableResult
    func processFrame(_ pcm: [Int16]) throws -> Float {
        try queue.sync {
            guard let profiler else {
                throw AppError.enrollmentFailed("Profiler is not initialized.")
            }
            do {
                return try profiler.enroll(pcm: pcm)
            } catch let error as EagleError {
                throw AppError.from(error, fallback: .enrollmentFailed(error.localizedDescription))
            } catch {
                throw AppError.enrollmentFailed(error.localizedDescription)
            }
        }
    }

    /// Exports the completed profile as bytes ready to be persisted.
    func exportProfile() throws -> Data {
        try queue.sync {
            guard let profiler else {
                throw AppError.enrollmentFailed("Profiler is not initialized.")
            }
            do {
                let profile = try profiler.export()
                return EagleProfileBytesAdapter.bytes(from: profile)
            } catch let error as EagleError {
                throw AppError.from(error, fallback: .enrollmentFailed(error.localizedDescription))
            } catch {
                throw AppError.enrollmentFailed(error.localizedDescription)
            }
        }
    }

    func reset() {
        queue.sync {
            try? profiler?.reset()
        }
    }

    func stop() {
        queue.sync {
            profiler?.delete()
            profiler = nil
        }
    }

    deinit {
        // Already-allocated `EagleProfiler` releases itself in its own deinit.
        // We simply drop the reference here.
        profiler = nil
    }
}
