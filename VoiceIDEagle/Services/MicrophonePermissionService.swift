import Combine
import AVFoundation
import Foundation

@MainActor
final class MicrophonePermissionService: ObservableObject {

    enum Status {
        case undetermined
        case denied
        case granted
    }

    @Published private(set) var status: Status = .undetermined

    init() {
        refresh()
    }

    func refresh() {
        let raw = AVAudioApplication.shared.recordPermission
        switch raw {
        case .undetermined: status = .undetermined
        case .denied:       status = .denied
        case .granted:      status = .granted
        @unknown default:   status = .undetermined
        }
    }

    /// Requests microphone permission. Returns true if granted.
    func requestIfNeeded() async -> Bool {
        if status == .granted { return true }
        let granted = await AVAudioApplication.requestRecordPermission()
        await MainActor.run { self.status = granted ? .granted : .denied }
        return granted
    }
}
