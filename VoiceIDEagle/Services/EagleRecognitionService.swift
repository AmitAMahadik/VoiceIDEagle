import Foundation
import Combine
import Eagle

/// Wraps the Picovoice `Eagle` recognizer lifecycle.
///
/// In current Eagle iOS SDK builds, `Eagle.init` does NOT take an array of
/// speaker profiles. Profiles are supplied to each `process(pcm:speakerProfiles:)`
/// call instead. This service stores the active profiles internally so the
/// rest of the app sees a uniform "start with profiles, feed frames, get
/// scores" surface.
///
/// Some older SDK examples show `Eagle(accessKey:speakerProfiles:voiceThreshold:)`.
/// If your installed SDK version uses that signature, adjust `start(profiles:)`
/// and `processFrame(_:)` accordingly — that is the only place this matters.
final class EagleRecognitionService: @unchecked Sendable {

    static var sampleRate: Int { Eagle.sampleRate }

    private var eagle: Eagle?
    private var orderedProfiles: [SpeakerProfile] = []
    private var orderedEagleProfiles: [EagleProfile] = []
    private var cachedFrameLength: Int = 0
    private let queue = DispatchQueue(label: "com.voiceideagle.eagle.recognize", qos: .userInitiated)

    // MARK: - Lifecycle

    func start(profiles: [SpeakerProfile]) throws {
        guard !profiles.isEmpty else { throw AppError.noEnrolledProfiles }

        try queue.sync {
            // Always start fresh. Cheaper than tracking mutations and
            // guarantees the profile order matches the input array.
            eagle?.delete()
            eagle = nil
            orderedProfiles = []
            orderedEagleProfiles = []
            cachedFrameLength = 0

            do {
                let eagleProfiles = try profiles.map { profile -> EagleProfile in
                    do {
                        return try EagleProfileBytesAdapter.profile(from: profile.profileData)
                    } catch {
                        throw AppError.corruptProfileData
                    }
                }

                let engine = try Eagle(
                    accessKey: AppConfig.picovoiceAccessKey,
                    voiceThreshold: AppConfig.voiceThreshold
                )

                let frameLen = try engine.minProcessSamples()

                eagle = engine
                orderedProfiles = profiles
                orderedEagleProfiles = eagleProfiles
                cachedFrameLength = frameLen
            } catch let error as AppError {
                throw error
            } catch let error as EagleError {
                throw AppError.from(error, fallback: .eagleInitializationFailed(error.localizedDescription))
            } catch {
                throw AppError.eagleInitializationFailed(error.localizedDescription)
            }
        }
    }

    /// Returns scores aligned to the profile order passed into `start(...)`.
    /// Returns `nil` if Eagle has not yet accumulated enough audio to emit a
    /// score this frame (the caller should treat that as "still listening").
    func processFrame(_ pcm: [Int16]) throws -> [Float]? {
        try queue.sync {
            guard let eagle, !orderedEagleProfiles.isEmpty else { return nil }
            do {
                return try eagle.process(pcm: pcm, speakerProfiles: orderedEagleProfiles)
            } catch let error as EagleError {
                throw AppError.from(error, fallback: .recognitionFailed(error.localizedDescription))
            } catch {
                throw AppError.recognitionFailed(error.localizedDescription)
            }
        }
    }

    /// Resets the recognizer's accumulated audio context. The current Eagle
    /// SDK does not expose `eagle.reset()`, so we recreate the engine.
    func reset() {
        queue.sync {
            guard !orderedProfiles.isEmpty else { return }
            eagle?.delete()
            eagle = nil
            // Best-effort recreate; ignore failure (caller can `start` again).
            if let recreated = try? Eagle(
                accessKey: AppConfig.picovoiceAccessKey,
                voiceThreshold: AppConfig.voiceThreshold
            ) {
                eagle = recreated
            }
        }
    }

    func stop() {
        queue.sync {
            eagle?.delete()
            eagle = nil
            orderedProfiles.removeAll()
            orderedEagleProfiles.removeAll()
            cachedFrameLength = 0
        }
    }

    var profilesInOrder: [SpeakerProfile] {
        queue.sync { orderedProfiles }
    }

    /// Number of samples each call to `processFrame(_:)` should receive.
    /// Returns 0 before `start(...)` has been called.
    var minProcessSamples: Int {
        queue.sync { cachedFrameLength }
    }

    deinit {
        eagle?.delete()
        eagle = nil
    }
}

