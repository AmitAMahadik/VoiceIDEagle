import Foundation
import Eagle
import Falcon

enum AppError: LocalizedError, Equatable {
    case missingAccessKey
    case microphonePermissionDenied
    case noEnrolledProfiles
    case audioEngineFailed(String)
    case eagleInitializationFailed(String)
    case enrollmentFailed(String)
    case recognitionFailed(String)
    case corruptProfileData
    case duplicateName
    case emptyName
    case diarizationFailed(String)
    case falconInitializationFailed(String)
    case noAudioCaptured
    case activationLimitReached
    case activationThrottled
    case activationRefused

    var errorDescription: String? {
        switch self {
        case .missingAccessKey:
            return "Picovoice AccessKey is missing. Configure PICOVOICE_ACCESS_KEY in your .env file."
        case .microphonePermissionDenied:
            return "Microphone access is required. Enable it in Settings > Privacy."
        case .noEnrolledProfiles:
            return "No enrolled speakers. Enroll a voice before identifying."
        case .audioEngineFailed(let message):
            return "Audio engine error: \(message)"
        case .eagleInitializationFailed(let message):
            return "Could not initialize Eagle: \(message)"
        case .enrollmentFailed(let message):
            return "Enrollment failed: \(message)"
        case .recognitionFailed(let message):
            return "Recognition failed: \(message)"
        case .corruptProfileData:
            return "A stored speaker profile is unreadable. Try re-enrolling that speaker."
        case .duplicateName:
            return "A speaker with that name already exists."
        case .emptyName:
            return "Please enter a non-empty name."
        case .diarizationFailed(let message):
            return "Diarization failed: \(message)"
        case .falconInitializationFailed(let message):
            return "Could not initialize Falcon: \(message)"
        case .noAudioCaptured:
            return "No audio was captured. Try recording for at least a few seconds."
        case .activationLimitReached:
            return "Picovoice activation limit reached for this AccessKey."
        case .activationThrottled:
            return "Picovoice request was throttled. Please try again shortly."
        case .activationRefused:
            return "Picovoice refused the AccessKey. Verify it is correct and active."
        }
    }

    /// Maps an Eagle SDK error onto a user-facing `AppError`.
    /// Falls back to the supplied default for unknown sub-cases.
    static func from(_ error: EagleError, fallback: AppError) -> AppError {
        if error is EagleActivationLimitError { return .activationLimitReached }
        if error is EagleActivationThrottledError { return .activationThrottled }
        if error is EagleActivationRefusedError { return .activationRefused }
        if error is EagleActivationError { return .activationRefused }
        return fallback
    }

    /// Maps a Falcon SDK error onto a user-facing `AppError`. Activation
    /// errors collapse onto the same shared cases as Eagle since both SDKs
    /// share one Picovoice AccessKey.
    static func from(_ error: FalconError, fallback: AppError) -> AppError {
        if error is FalconActivationLimitError { return .activationLimitReached }
        if error is FalconActivationThrottledError { return .activationThrottled }
        if error is FalconActivationRefusedError { return .activationRefused }
        if error is FalconActivationError { return .activationRefused }
        return fallback
    }
}
