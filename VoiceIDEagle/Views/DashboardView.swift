import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel(permissionService: MicrophonePermissionService(), profileStore: SpeakerProfileStore())

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    StatusCardView(
                        permissionStatus: viewModel.permissionStatus,
                        profileCount: viewModel.profileCount,
                        sdkReady: viewModel.sdkReady
                    )

                    if let configurationError = viewModel.configurationError {
                        configurationBanner(configurationError)
                    }

                    actionButtons

                    privacyNote
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("VoiceID Eagle")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh status")
                }
            }
            .onAppear { viewModel.refresh() }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("On-device speaker recognition")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            NavigationLink {
                EnrollmentView(
                    profileStore: viewModel.profileStore,
                    permissionService: viewModel.permissionService
                )
            } label: {
                buttonLabel(title: "Enroll New Voice", systemImage: "person.crop.circle.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.sdkReady)

            NavigationLink {
                RecognitionView(
                    profileStore: viewModel.profileStore,
                    permissionService: viewModel.permissionService
                )
            } label: {
                buttonLabel(title: "Identify Speaker", systemImage: "mic.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.indigo)
            .disabled(!viewModel.sdkReady)

            NavigationLink {
                ProfileManagementView(profileStore: viewModel.profileStore)
            } label: {
                buttonLabel(title: "Manage Profiles", systemImage: "person.2.gobackward")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func buttonLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
            Text(title).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.secondary)
            Text("Voice profiles are stored locally on this device. Audio is processed on-device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private func configurationBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Configuration required").fontWeight(.semibold)
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }
}

#Preview {
    DashboardView()
}

