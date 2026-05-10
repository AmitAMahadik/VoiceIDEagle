import Foundation

enum EnrollmentState: Equatable {
    case idle
    case listening
    case enrolling(percent: Double)
    case complete
    case failed(String)

    var description: String {
        switch self {
        case .idle: return "Idle"
        case .listening: return "Listening"
        case .enrolling: return "Enrolling"
        case .complete: return "Complete"
        case .failed(let message): return "Failed: \(message)"
        }
    }

    var percent: Double {
        if case .enrolling(let p) = self { return p }
        if case .complete = self { return 100 }
        return 0
    }

    var isActive: Bool {
        switch self {
        case .listening, .enrolling: return true
        default: return false
        }
    }
}
