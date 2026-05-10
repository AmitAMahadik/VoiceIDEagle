import Foundation
import Eagle

/// Classifies a chunk of PCM audio against the enrolled `SpeakerProfile`s
/// using Eagle in batch mode.
///
/// Why a separate service from `EagleRecognitionService`? That one owns a
/// long-lived `Eagle` instance for streaming live identification. For
/// diarization we want the opposite pattern: every Falcon-tagged speaker
/// group is scored in isolation, with no carry-over of internal voice
/// context from the previous group. That means a fresh `Eagle` per
/// classification call.
///
/// The class is `@unchecked Sendable` because all access to the cached
/// `EagleProfile` array goes through the serial dispatch queue.
final class EagleSegmentClassifier: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.voiceideagle.eagle.classifier", qos: .userInitiated)
    private var profiles: [SpeakerProfile] = []
    private var eagleProfiles: [EagleProfile] = []

    // MARK: - Setup

    /// Reconstructs `EagleProfile` objects from persisted bytes once so each
    /// call to `classify(pcm:)` doesn't pay for it. Throws if any stored
    /// profile is unreadable.
    func prepare(profiles: [SpeakerProfile]) throws {
        try queue.sync {
            self.eagleProfiles = try profiles.map { profile in
                do {
                    return try EagleProfileBytesAdapter.profile(from: profile.profileData)
                } catch {
                    throw AppError.corruptProfileData
                }
            }
            self.profiles = profiles
        }
    }

    /// Releases held SDK objects.
    func reset() {
        queue.sync {
            profiles.removeAll()
            eagleProfiles.removeAll()
        }
    }

    /// The profiles in score-vector order, matching the array layout that
    /// `classify(pcm:)` returns.
    var profilesInOrder: [SpeakerProfile] {
        queue.sync { profiles }
    }

    // MARK: - Classification

    /// Runs Eagle over `pcm` (at `Eagle.sampleRate`, mono, 16-bit) and
    /// returns the averaged score vector aligned to `profilesInOrder`.
    ///
    /// Returns `nil` if there isn't enough voice in `pcm` for Eagle to
    /// produce any score frames. The caller should treat that as
    /// "speaker undetermined" and fall back to `Speaker N`.
    func classify(pcm: [Int16]) throws -> [Float]? {
        try queue.sync {
            guard !eagleProfiles.isEmpty, !pcm.isEmpty else { return nil }

            // Fresh Eagle per call so no accumulated context leaks between
            // diarization tags. Init/teardown is on the order of a few ms.
            let eagle: Eagle
            do {
                eagle = try Eagle(
                    accessKey: AppConfig.picovoiceAccessKey,
                    voiceThreshold: AppConfig.voiceThreshold
                )
            } catch let error as EagleError {
                throw AppError.from(error, fallback: .eagleInitializationFailed(error.localizedDescription))
            } catch {
                throw AppError.eagleInitializationFailed(error.localizedDescription)
            }
            defer { eagle.delete() }

            let frameLen: Int
            do {
                frameLen = try eagle.minProcessSamples()
            } catch {
                throw AppError.recognitionFailed(error.localizedDescription)
            }
            guard frameLen > 0 else { return nil }

            let profileCount = eagleProfiles.count
            var sums = [Float](repeating: 0, count: profileCount)
            var validFrames = 0

            var index = 0
            while index + frameLen <= pcm.count {
                let chunk = Array(pcm[index..<(index + frameLen)])
                index += frameLen
                do {
                    if let scores = try eagle.process(pcm: chunk, speakerProfiles: eagleProfiles) {
                        for i in 0..<min(scores.count, profileCount) {
                            sums[i] += scores[i]
                        }
                        validFrames += 1
                    }
                } catch let error as EagleError {
                    throw AppError.from(error, fallback: .recognitionFailed(error.localizedDescription))
                } catch {
                    throw AppError.recognitionFailed(error.localizedDescription)
                }
            }

            guard validFrames > 0 else { return nil }
            return sums.map { $0 / Float(validFrames) }
        }
    }
}
