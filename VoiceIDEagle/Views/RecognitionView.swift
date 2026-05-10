import SwiftUI

struct RecognitionView: View {
    @StateObject private var viewModel: RecognitionViewModel
    @ObservedObject private var profileStore: SpeakerProfileStore
    @Environment(\.dismiss) private var dismiss

    init(profileStore: SpeakerProfileStore, permissionService: MicrophonePermissionService) {
        self.profileStore = profileStore
        _viewModel = StateObject(
            wrappedValue: RecognitionViewModel(
                profileStore: profileStore,
                permissionService: permissionService
            )
        )
    }

    var body: some View {
        Group {
            if profileStore.profiles.isEmpty {
                EmptyStateView(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "No enrolled voices",
                    message: "Enroll at least one speaker before identifying.",
                    actionTitle: "Go Back",
                    action: { dismiss() }
                )
            } else {
                content
            }
        }
        .navigationTitle("Identify")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Identification",
            isPresented: Binding(
                get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.alertMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(viewModel.alertMessage ?? "") }
        )
        .onDisappear { viewModel.stopListening() }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                resultCard
                thresholdCard
                scoresList
                controls
                disclaimer
            }
            .padding(20)
        }
    }

    // MARK: - Sections

    private var resultCard: some View {
        VStack(spacing: 12) {
            Image(systemName: viewModel.bestMatch != nil ? "person.wave.2.fill" : "questionmark.circle")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(viewModel.bestMatch != nil ? Color.accentColor : .secondary)

            if let match = viewModel.bestMatch {
                Text(match.speaker.name)
                    .font(.title.weight(.bold))
                Text("\(match.percentage)% confidence")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if case .listening = viewModel.state {
                Text("Listening…")
                    .font(.title2.weight(.semibold))
                Text("Speak naturally to be identified.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if case .identifying = viewModel.state {
                Text("Unknown Speaker")
                    .font(.title2.weight(.semibold))
                Text("No enrolled voice matched above the threshold.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(viewModel.state.description)
                    .font(.title3.weight(.semibold))
                Text("Tap Start Listening to begin.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var thresholdCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Identification threshold")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.2f", viewModel.threshold))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { viewModel.threshold },
                    set: { viewModel.updateThreshold($0) }
                ),
                in: 0.3...0.95,
                step: 0.01
            )
            Text("Scores at or above this value count as a match.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var scoresList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Speakers")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(viewModel.scores) { score in
                ScoreBarView(
                    name: score.speaker.name,
                    score: score.score,
                    isMatched: viewModel.bestMatch?.id == score.id
                )
            }
            if viewModel.scores.isEmpty {
                Text("No scores yet. Start listening to see live confidence values.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .opacity(viewModel.state == .listening && viewModel.scores.allSatisfy({ $0.score == 0 }) ? 0.7 : 1)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            switch viewModel.state {
            case .idle, .stopped, .failed:
                PrimaryButton(title: "Start Listening", systemImage: "record.circle") {
                    viewModel.startListening()
                }
            case .listening, .identifying:
                PrimaryButton(title: "Stop Listening", systemImage: "stop.circle") {
                    viewModel.stopListening()
                }
                SecondaryButton(title: "Reset Session", systemImage: "arrow.counterclockwise") {
                    viewModel.resetSession()
                }
            }
        }
    }

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield")
                .foregroundStyle(.secondary)
            Text("Voice identification is not foolproof. Do not use it as the sole factor for high-security authentication.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}
