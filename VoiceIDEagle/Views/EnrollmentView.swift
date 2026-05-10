import SwiftUI

struct EnrollmentView: View {
    @StateObject private var viewModel: EnrollmentViewModel
    @Environment(\.dismiss) private var dismiss

    init(profileStore: SpeakerProfileStore, permissionService: MicrophonePermissionService) {
        _viewModel = StateObject(
            wrappedValue: EnrollmentViewModel(
                profileStore: profileStore,
                permissionService: permissionService
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                switch viewModel.step {
                case .nameEntry:    nameStep
                case .instructions: instructionsStep
                case .capturing:    capturingStep
                case .finished:     finishedStep
                }
            }
            .padding(20)
        }
        .navigationTitle("Enroll Voice")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Enrollment",
            isPresented: Binding(
                get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.alertMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(viewModel.alertMessage ?? "") }
        )
        .interactiveDismissDisabled(viewModel.step == .capturing)
    }

    // MARK: - Steps

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 1 of 3").font(.caption).foregroundStyle(.secondary)
            Text("Who are we enrolling?").font(.title2.weight(.semibold))
            Text("Enter a display name for this voice profile.")
                .font(.subheadline).foregroundStyle(.secondary)

            TextField("e.g. Alex", text: $viewModel.name)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { viewModel.proceedFromNameEntry() }
                .padding(.top, 8)

            PrimaryButton(
                title: "Continue",
                systemImage: "arrow.right",
                isEnabled: !viewModel.name.trimmingCharacters(in: .whitespaces).isEmpty
            ) {
                viewModel.proceedFromNameEntry()
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var instructionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 2 of 3").font(.caption).foregroundStyle(.secondary)
            Text("Get ready to record").font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                bullet("Speak naturally for several seconds.", icon: "mic")
                bullet("Use a quiet environment.", icon: "moon.zzz")
                bullet("Do not switch speakers during enrollment.", icon: "person.fill.questionmark")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
            )

            PrimaryButton(title: "Start Enrollment", systemImage: "record.circle") {
                viewModel.proceedFromInstructions()
            }
            .padding(.top, 8)

            SecondaryButton(title: "Back", systemImage: "chevron.left") {
                viewModel.cancel()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var capturingStep: some View {
        VStack(spacing: 24) {
            Text("Step 3 of 3").font(.caption).foregroundStyle(.secondary)
            Text("Listening to \(viewModel.name)…").font(.title2.weight(.semibold))

            progressRing

            Text(viewModel.state.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Status: \(viewModel.state.description)")

            SecondaryButton(title: "Cancel", systemImage: "xmark") {
                viewModel.cancel()
                dismiss()
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var finishedStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Enrolled!").font(.title.weight(.bold))
            Text("\(viewModel.name) was added to your local profiles.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "Done", systemImage: "checkmark") {
                dismiss()
            }
            .padding(.top, 12)
        }
        .padding(.top, 32)
    }

    // MARK: - Helpers

    private func bullet(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(Color.accentColor)
            Text(text).font(.subheadline)
        }
    }

    private var progressRing: some View {
        let percent = viewModel.state.percent
        return ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: 14)
            Circle()
                .trim(from: 0, to: CGFloat(percent / 100))
                .stroke(Color.accentColor,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: percent)
            VStack(spacing: 4) {
                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("enrolled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 200, height: 200)
        .padding(.vertical, 8)
        .accessibilityLabel("Enrollment progress \(Int(percent.rounded())) percent")
    }
}
