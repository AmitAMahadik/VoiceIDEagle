import SwiftUI

struct DiarizationView: View {
    @StateObject private var viewModel: DiarizationViewModel
    @ObservedObject private var profileStore: SpeakerProfileStore
    @Environment(\.dismiss) private var dismiss

    init(profileStore: SpeakerProfileStore, permissionService: MicrophonePermissionService) {
        self.profileStore = profileStore
        _viewModel = StateObject(
            wrappedValue: DiarizationViewModel(
                profileStore: profileStore,
                permissionService: permissionService,
                falconService: FalconDiarizationService(),
                classifier: EagleSegmentClassifier()
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                switch viewModel.phase {
                case .idle:
                    idleSection
                case .recording:
                    recordingSection
                case .processing:
                    processingSection
                case .results:
                    resultsSection
                case .failed(let message):
                    failedSection(message)
                }
            }
            .padding(20)
        }
        .navigationTitle("Diarize")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Diarization",
            isPresented: Binding(
                get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.alertMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(viewModel.alertMessage ?? "") }
        )
        .onDisappear { viewModel.cancel() }
    }

    // MARK: - Phases

    private var idleSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.wave.2")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("Who's speaking?")
                .font(.title2.weight(.semibold))
            Text("Record a conversation to see speaker turns. Enrolled voices will be tagged with their names — others will appear as Speaker 1, 2, …")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if profileStore.profiles.isEmpty {
                noProfilesBanner
            }

            PrimaryButton(title: "Start Recording", systemImage: "record.circle") {
                viewModel.startRecording()
            }
            .padding(.top, 8)

            Text("Recording stops automatically after 5 minutes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            disclaimer
        }
    }

    private var recordingSection: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, viewModel.elapsedSec / DiarizationViewModel.maxRecordingSec)))
                    .stroke(Color.red,
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: viewModel.elapsedSec)
                VStack(spacing: 4) {
                    Image(systemName: "record.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title)
                    Text(elapsedString(viewModel.elapsedSec))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("recording")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 220, height: 220)
            .padding(.vertical, 8)

            PrimaryButton(title: "Stop & Analyze", systemImage: "stop.circle") {
                viewModel.stopAndAnalyze()
            }
            SecondaryButton(title: "Cancel", systemImage: "xmark") {
                viewModel.cancel()
            }

            Text("Speak naturally. Multiple speakers are okay — Falcon will separate them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
    }

    private var processingSection: some View {
        VStack(spacing: 18) {
            ProgressView()
                .scaleEffect(1.5)
                .padding(.top, 24)
            Text("Analyzing speakers…")
                .font(.headline)
            Text("Diarizing audio and matching against enrolled voices.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var resultsSection: some View {
        VStack(spacing: 16) {
            summaryCard

            if !profileStore.profiles.isEmpty {
                thresholdCard
            } else {
                noProfilesBanner
            }

            timelineList

            HStack(spacing: 12) {
                SecondaryButton(title: "New Recording", systemImage: "arrow.counterclockwise") {
                    viewModel.cancel()
                }
                PrimaryButton(title: "Done", systemImage: "checkmark") {
                    dismiss()
                }
            }
            disclaimer
        }
    }

    private func failedSection(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "Try Again", systemImage: "arrow.counterclockwise") {
                viewModel.cancel()
            }
        }
        .padding(.top, 32)
    }

    // MARK: - Result subviews

    private var summaryCard: some View {
        let identified = Set(viewModel.segments.compactMap { $0.speakerName }).count
        let total = Set(viewModel.segments.map { $0.speakerTag }).count
        return VStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("\(viewModel.segments.count) segments · \(total) speaker\(total == 1 ? "" : "s")")
                .font(.headline)
            if !profileStore.profiles.isEmpty {
                Text("\(identified) identified · \(total - identified) anonymous")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18)
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
            Text("Tags below this score fall back to Speaker N.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var timelineList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Timeline")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(viewModel.segments) { segment in
                SegmentRow(segment: segment)
            }
        }
    }

    private var noProfilesBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .foregroundStyle(.orange)
            Text("Enroll voices first to label speakers by name. Without profiles, every turn shows as Speaker 1, 2, …")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.12))
        )
    }

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield")
                .foregroundStyle(.secondary)
            Text("Diarization runs entirely on-device. Audio is never sent off the phone and isn't stored after the session.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func elapsedString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

private struct SegmentRow: View {
    let segment: DiarizedSegment

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color(for: segment.speakerTag))
                    .frame(width: 36, height: 36)
                Text("\(segment.speakerTag + 1)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(segment.displayName)
                        .font(.headline)
                    if segment.isIdentified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text("\(timeString(segment.startSec)) → \(timeString(segment.endSec)) · \(durationString(segment.durationSec))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let confidence = segment.confidence {
                Text("\(Int((confidence * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.accentColor.opacity(0.12))
                    )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = ["\(segment.displayName) from \(timeString(segment.startSec)) to \(timeString(segment.endSec))"]
        if let confidence = segment.confidence {
            parts.append("\(Int((confidence * 100).rounded())) percent confidence")
        }
        return parts.joined(separator: ", ")
    }

    private func timeString(_ seconds: Float) -> String {
        let total = Int(seconds.rounded(.down))
        let minutes = total / 60
        let secs = total % 60
        let hundredths = Int((seconds - Float(total)) * 100)
        return String(format: "%d:%02d.%02d", minutes, secs, hundredths)
    }

    private func durationString(_ seconds: Float) -> String {
        String(format: "%.1fs", seconds)
    }

    /// Stable per-tag color picked from a small palette.
    private func color(for tag: Int) -> Color {
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .teal, .green, .brown]
        return palette[((tag % palette.count) + palette.count) % palette.count]
    }
}
