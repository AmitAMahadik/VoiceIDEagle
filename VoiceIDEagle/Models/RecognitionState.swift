import Foundation

enum RecognitionState: Equatable {
    case idle
    case listening
    case identifying
    case stopped
    case failed(String)

    var description: String {
        switch self {
        case .idle: return "Idle"
        case .listening: return "Listening…"
        case .identifying: return "Identifying"
        case .stopped: return "Stopped"
        case .failed(let message): return "Failed: \(message)"
        }
    }
}
