import Foundation

/// Strongly-typed access to environment-driven configuration.
///
/// IMPORTANT: The Picovoice AccessKey is loaded exclusively from the `.env`
/// file at runtime. Never hardcode the key in source code.
enum AppConfig {
    /// Picovoice AccessKey loaded from `.env`. Crashes early if missing so
    /// that misconfiguration is obvious during development.
    static var picovoiceAccessKey: String {
        guard let key = EnvironmentLoader.shared.picovoiceAccessKey,
              !key.isEmpty else {
            fatalError("Missing PICOVOICE_ACCESS_KEY in .env")
        }
        return key
    }

    /// Non-throwing variant for the UI layer to display configuration errors
    /// gracefully instead of crashing.
    static var picovoiceAccessKeyIfPresent: String? {
        EnvironmentLoader.shared.picovoiceAccessKey
    }

    /// User-visible threshold (default 0.65) above which a speaker is
    /// considered identified. Stored in UserDefaults.
    static let identificationThresholdKey = "identificationThreshold"
    static let defaultIdentificationThreshold: Float = 0.65

    /// Picovoice's own internal `voiceThreshold` for Eagle. Lower than the
    /// app-level identification threshold; controls how aggressively Eagle
    /// emits scores when there is little voice activity.
    static let voiceThreshold: Float = 0.3

    /// Minimum speaking time required before enrollment can complete.
    static let minEnrollmentDurationSec: TimeInterval = 8
}
