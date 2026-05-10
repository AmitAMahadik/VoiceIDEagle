import Foundation

/// A single diarized speaker turn.
///
/// `speakerTag` is Falcon's anonymous integer label (the same tag means the
/// same speaker within one diarization run). `speakerName` and `confidence`
/// are populated when Eagle classification matches the segment to one of
/// the enrolled profiles.
struct DiarizedSegment: Identifiable, Hashable {
    let id: UUID
    let speakerTag: Int
    let startSec: Float
    let endSec: Float
    var speakerName: String?
    var confidence: Float?

    init(
        id: UUID = UUID(),
        speakerTag: Int,
        startSec: Float,
        endSec: Float,
        speakerName: String? = nil,
        confidence: Float? = nil
    ) {
        self.id = id
        self.speakerTag = speakerTag
        self.startSec = startSec
        self.endSec = endSec
        self.speakerName = speakerName
        self.confidence = confidence
    }

    var durationSec: Float { max(0, endSec - startSec) }

    /// Display name to render in the UI. Falls back to "Speaker N" when
    /// Eagle couldn't (or wasn't asked to) tag this turn.
    var displayName: String {
        speakerName ?? "Speaker \(speakerTag)"
    }

    var isIdentified: Bool { speakerName != nil }
}
