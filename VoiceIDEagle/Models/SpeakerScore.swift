import Foundation

struct SpeakerScore: Identifiable, Hashable {
    let speaker: SpeakerProfile
    let score: Float

    var id: UUID { speaker.id }

    var percentage: Int { Int((score * 100).rounded()) }
}
