import SwiftUI

// MARK: - ProjectListView

struct ProjectListView: View {
    @EnvironmentObject private var viewModel: ProjectViewModel
    @State private var showingNewProjectSheet = false
    @State private var newProjectTitle = ""
    @State private var newProjectComposer = ""
    @State private var newProjectTempo: Double = 120
    @State private var newProjectKey: KeySignature = .cMajor
    @State private var searchText = ""
    @State private var showingSortMenu = false

    var filteredProjects: [VocalScoreProject] {
        let sorted = viewModel.sortedProjects
        if searchText.isEmpty { return sorted }
        return sorted.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.composer.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if filteredProjects.isEmpty && searchText.isEmpty {
                emptyStateView
            } else {
                projectList
            }
        }
        .navigationTitle("VocalScore Pro")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search compositions")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                sortButton
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                newProjectButton
            }
        }
        .sheet(isPresented: $showingNewProjectSheet) {
            newProjectSheet
        }
    }

    // MARK: - Project List

    private var projectList: some View {
        List {
            ForEach(filteredProjects) { project in
                NavigationLink(destination: ProjectDetailView(project: project)) {
                    ProjectRowView(project: project)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.deleteProject(project)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        viewModel.duplicateProject(project)
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    .tint(.blue)
                }
            }
            .onDelete { offsets in
                viewModel.deleteProjects(at: offsets)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            viewModel.loadProjects()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "music.note.tv")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(
                    LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            VStack(spacing: 8) {
                Text("No Compositions Yet")
                    .font(.title2.bold())

                Text("Tap the + button to create your\nfirst orchestral composition.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showingNewProjectSheet = true
            } label: {
                Label("New Composition", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Toolbar Items

    private var newProjectButton: some View {
        Button {
            newProjectTitle = ""
            newProjectComposer = ""
            newProjectTempo = 120
            newProjectKey = .cMajor
            showingNewProjectSheet = true
        } label: {
            Image(systemName: "plus")
                .fontWeight(.semibold)
        }
    }

    private var sortButton: some View {
        Menu {
            Picker("Sort By", selection: $viewModel.sortOrder) {
                ForEach(ProjectViewModel.SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    // MARK: - New Project Sheet

    private var newProjectSheet: some View {
        NavigationStack {
            Form {
                Section("Composition Details") {
                    TextField("Title", text: $newProjectTitle)
                    TextField("Composer Name", text: $newProjectComposer)
                }

                Section("Musical Settings") {
                    HStack {
                        Text("Tempo")
                        Spacer()
                        Text("\(Int(newProjectTempo)) BPM")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $newProjectTempo, in: 40...240, step: 1)

                    Picker("Key Signature", selection: $newProjectKey) {
                        ForEach(KeySignature.allCases) { key in
                            Text(key.displayName).tag(key)
                        }
                    }
                }
            }
            .navigationTitle("New Composition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingNewProjectSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let title = newProjectTitle.isEmpty ? "Untitled Composition" : newProjectTitle
                        let _ = viewModel.createProject(
                            title: title,
                            composer: newProjectComposer,
                            tempo: newProjectTempo,
                            keySignature: newProjectKey
                        )
                        showingNewProjectSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - ProjectRowView

struct ProjectRowView: View {
    let project: VocalScoreProject

    private let dateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(spacing: 14) {
            // Project color indicator
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.8), .blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: "music.quarternote.3")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.headline)
                    .lineLimit(1)

                if !project.composer.isEmpty {
                    Text(project.composer)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Label("\(project.parts.count)", systemImage: "pianokeys")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label("\(project.timeSignatureDisplay) • \(Int(project.tempo)) BPM", systemImage: "metronome")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(dateFormatter.localizedString(for: project.modifiedAt, relativeTo: Date()))
                .font(.caption2)
                .foregroundColor(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ProjectListView()
            .environmentObject(ProjectViewModel())
    }
}
