import SwiftUI

struct StatusCardView: View {
    let permissionStatus: MicrophonePermissionService.Status
    let profileCount: Int
    let eagleReady: Bool
    let falconReady: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            row(
                icon: "mic.circle",
                title: "Microphone",
                value: permissionText,
                tint: permissionTint
            )
            Divider()
            row(
                icon: "person.wave.2",
                title: "Enrolled Voices",
                value: "\(profileCount)",
                tint: .accentColor
            )
            Divider()
            row(
                icon: (eagleReady && falconReady) ? "checkmark.seal" : "exclamationmark.triangle",
                title: "SDKs",
                value: sdkSummary,
                tint: (eagleReady && falconReady) ? .green : .orange
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func row(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
            }
            Spacer()
        }
    }

    private var permissionText: String {
        switch permissionStatus {
        case .undetermined: return "Not requested"
        case .denied:       return "Denied"
        case .granted:      return "Granted"
        }
    }

    private var permissionTint: Color {
        switch permissionStatus {
        case .undetermined: return .orange
        case .denied:       return .red
        case .granted:      return .green
        }
    }

    private var sdkSummary: String {
        "Eagle \(eagleReady ? "✓" : "✕")   Falcon \(falconReady ? "✓" : "✕")"
    }
}
