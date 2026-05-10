import SwiftUI

struct ProfileManagementView: View {
    @StateObject private var viewModel: ProfileManagementViewModel
    @State private var pendingRename: SpeakerProfile?
    @State private var renameText: String = ""
    @State private var showDeleteAllConfirmation = false

    init(profileStore: SpeakerProfileStore) {
        _viewModel = StateObject(
            wrappedValue: ProfileManagementViewModel(profileStore: profileStore)
        )
    }

    var body: some View {
        Group {
            if viewModel.profiles.isEmpty {
                EmptyStateView(
                    systemImage: "person.crop.circle",
                    title: "No profiles yet",
                    message: "Enrolled voice profiles will appear here."
                )
            } else {
                List {
                    Section {
                        ForEach(viewModel.profiles) { profile in
                            ProfileRow(profile: profile) {
                                pendingRename = profile
                                renameText = profile.name
                            }
                        }
                        .onDelete { indexSet in
                            indexSet
                                .map { viewModel.profiles[$0].id }
                                .forEach { viewModel.deleteProfile(id: $0) }
                        }
                    }

                    Section {
                        Button(role: .destructive) {
                            showDeleteAllConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete all profiles")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewModel.profiles.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .alert(
            "Rename profile",
            isPresented: Binding(
                get: { pendingRename != nil },
                set: { if !$0 { pendingRename = nil } }
            )
        ) {
            TextField("Name", text: $renameText)
                .textInputAutocapitalization(.words)
            Button("Save") {
                if let id = pendingRename?.id {
                    viewModel.renameProfile(id: id, to: renameText)
                }
                pendingRename = nil
            }
            Button("Cancel", role: .cancel) { pendingRename = nil }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.alertMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(viewModel.alertMessage ?? "") }
        )
        .confirmationDialog(
            "Delete all profiles?",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                viewModel.deleteAllProfiles()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Voice profiles are stored only on this device.")
        }
    }
}

private struct ProfileRow: View {
    let profile: SpeakerProfile
    let onRename: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onRename) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Rename \(profile.name)")
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Enrolled \(formatter.string(from: profile.createdAt)) · \(profile.formattedSize)"
    }
}
