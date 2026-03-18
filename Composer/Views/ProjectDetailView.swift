import SwiftUI

// MARK: - ProjectDetailTab

enum ProjectDetailTab: String, CaseIterable {
    case score  = "Score"
    case mixer  = "Mixer"
    case export = "Export"

    var icon: String {
        switch self {
        case .score:  return "music.note.list"
        case .mixer:  return "slider.horizontal.3"
        case .export: return "square.and.arrow.up"
        }
    }
}

// MARK: - ProjectDetailView

struct ProjectDetailView: View {
    let project: VocalScoreProject

    @EnvironmentObject private var projectViewModel: ProjectViewModel
    @StateObject private var playbackEngine = PlaybackEngine()
    @State private var selectedTab: ProjectDetailTab = .score
    @State private var showingInstrumentPicker = false
    @State private var showingRecordingView = false
    @State private var selectedInstrumentForRecording: Instrument? = nil
    @State private var showingAISheet = false
    @State private var editingProjectTitle = false
    @State private var titleDraft = ""
    @State private var navigateToEditor: Part? = nil
    @State private var contextMenuPart: Part? = nil
    @State private var showingRenameSheet = false
    @State private var renameDraft = ""

    private var currentProject: VocalScoreProject {
        projectViewModel.projects.first { $0.id == project.id } ?? project
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab content
            Group {
                switch selectedTab {
                case .score:
                    partsList
                case .mixer:
                    mixerContent
                case .export:
                    exportContent
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedTab)

            // Bottom tab bar
            bottomTabBar
        }
        .navigationTitle(currentProject.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                transportControls
                aiButton
            }
            ToolbarItem(placement: .navigationBarLeading) {
                projectInfoButton
            }
        }
        .sheet(isPresented: $showingInstrumentPicker) {
            InstrumentPickerView { instrument in
                // Navigate to RecordingView after instrument selection
                selectedInstrumentForRecording = instrument
                showingInstrumentPicker = false
                showingRecordingView = true
            }
        }
        .sheet(isPresented: $showingRecordingView) {
            if let instrument = selectedInstrumentForRecording {
                NavigationStack {
                    RecordingView(instrument: instrument) { part in
                        projectViewModel.addPart(part, to: currentProject.id)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAISheet) {
            AIComingSoonSheet()
        }
        .sheet(isPresented: $showingRenameSheet) {
            renameSheet
        }
        .navigationDestination(item: $navigateToEditor) { part in
            ScoreEditorView(part: part, project: currentProject)
        }
    }

    // MARK: - Parts List

    private var partsList: some View {
        List {
            Section {
                ForEach(currentProject.parts) { part in
                    PartRowView(
                        part: part,
                        onTap: { navigateToEditor = part },
                        onToggleMute: { toggleMute(part) },
                        onToggleSolo: { toggleSolo(part) },
                        onDelete: { deletePart(part) },
                        onRename: {
                            contextMenuPart = part
                            renameDraft = part.name
                            showingRenameSheet = true
                        }
                    )
                }
                .onDelete { offsets in
                    deletePartsAt(offsets: offsets)
                }

                // Add Part button
                Button {
                    showingInstrumentPicker = true
                } label: {
                    Label("Add Part", systemImage: "plus.circle.fill")
                        .foregroundColor(.purple)
                        .font(.body.weight(.medium))
                }
            } header: {
                HStack {
                    Text("Parts (\(currentProject.parts.count))")
                    Spacer()
                    Text("\(currentProject.timeSignatureDisplay) • \(Int(currentProject.tempo)) BPM • \(currentProject.keySignature.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if currentProject.parts.isEmpty {
                emptyPartsOverlay
            }
        }
    }

    private var emptyPartsOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.mic")
                .font(.system(size: 52, weight: .thin))
                .foregroundColor(.purple.opacity(0.6))

            Text("No Parts Yet")
                .font(.title3.bold())

            Text("Add an instrument part to start\nbuilding your score.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingInstrumentPicker = true
            } label: {
                Label("Add First Part", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding()
    }

    // MARK: - Mixer Content

    private var mixerContent: some View {
        // Build a local binding to current project's parts
        MixerView(
            project: Binding(
                get: { currentProject },
                set: { updated in projectViewModel.updateProject(updated) }
            ),
            onPartUpdated: { part in
                projectViewModel.updatePart(part, in: currentProject.id)
            }
        )
    }

    // MARK: - Export Content

    private var exportContent: some View {
        ExportView(project: currentProject)
    }

    // MARK: - Bottom Tab Bar

    private var bottomTabBar: some View {
        HStack(spacing: 0) {
            ForEach(ProjectDetailTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20))
                        Text(tab.rawValue)
                            .font(.caption2)
                    }
                    .foregroundColor(selectedTab == tab ? .purple : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Toolbar Items

    private var transportControls: some View {
        HStack(spacing: 12) {
            Button {
                if playbackEngine.isPlaying {
                    playbackEngine.stop()
                } else {
                    playbackEngine.play(
                        parts: currentProject.parts,
                        tempo: currentProject.tempo
                    )
                }
            } label: {
                Image(systemName: playbackEngine.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundColor(playbackEngine.isPlaying ? .orange : .purple)
            }
        }
    }

    private var aiButton: some View {
        Button {
            showingAISheet = true
        } label: {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 16))
                .foregroundColor(.purple)
        }
    }

    private var projectInfoButton: some View {
        Button {
            selectedTab = .export
        } label: {
            Image(systemName: "info.circle")
        }
    }

    // MARK: - Rename Sheet

    private var renameSheet: some View {
        NavigationStack {
            Form {
                Section("Part Name") {
                    TextField("Name", text: $renameDraft)
                }
            }
            .navigationTitle("Rename Part")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingRenameSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let part = contextMenuPart {
                            renamePart(part, newName: renameDraft)
                        }
                        showingRenameSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(220)])
    }

    // MARK: - Actions

    private func addPart(with instrument: Instrument) {
        let defaultColor = instrument.family.color
        let part = Part(
            name: instrument.name,
            instrument: instrument,
            color: defaultColor
        )
        projectViewModel.addPart(part, to: currentProject.id)
    }

    private func deletePart(_ part: Part) {
        projectViewModel.removePart(part.id, from: currentProject.id)
    }

    private func deletePartsAt(offsets: IndexSet) {
        let parts = currentProject.parts
        for index in offsets {
            if index < parts.count {
                projectViewModel.removePart(parts[index].id, from: currentProject.id)
            }
        }
    }

    private func toggleMute(_ part: Part) {
        var updated = part
        updated.isMuted.toggle()
        if updated.isMuted { updated.isSolo = false }
        projectViewModel.updatePart(updated, in: currentProject.id)
    }

    private func toggleSolo(_ part: Part) {
        var updated = part
        updated.isSolo.toggle()
        if updated.isSolo { updated.isMuted = false }
        projectViewModel.updatePart(updated, in: currentProject.id)
    }

    private func renamePart(_ part: Part, newName: String) {
        var updated = part
        updated.name = newName.isEmpty ? part.instrument.name : newName
        projectViewModel.updatePart(updated, in: currentProject.id)
    }
}

// MARK: - PartRowView

struct PartRowView: View {
    let part: Part
    let onTap: () -> Void
    let onToggleMute: () -> Void
    let onToggleSolo: () -> Void
    let onDelete: () -> Void
    let onRename: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Instrument icon with family color
            ZStack {
                Circle()
                    .fill(Color(hex: part.color)?.opacity(0.2) ?? Color.purple.opacity(0.2))
                    .frame(width: 40, height: 40)
                Image(systemName: part.instrument.icon)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: part.color) ?? .purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(part.name)
                        .font(.headline)
                        .lineLimit(1)

                    if part.isAIGenerated {
                        Image(systemName: "wand.and.stars")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                }

                Text("\(part.instrument.name) • \(part.noteCount) notes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Mute / Solo buttons
            HStack(spacing: 8) {
                Button(action: onToggleMute) {
                    Text("M")
                        .font(.caption.bold())
                        .frame(width: 26, height: 26)
                        .background(part.isMuted ? Color.orange : Color.secondary.opacity(0.2))
                        .foregroundColor(part.isMuted ? .white : .secondary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button(action: onToggleSolo) {
                    Text("S")
                        .font(.caption.bold())
                        .frame(width: 26, height: 26)
                        .background(part.isSolo ? Color.yellow : Color.secondary.opacity(0.2))
                        .foregroundColor(part.isSolo ? .black : .secondary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Edit Score", systemImage: "pencil")
            }

            Button {
                onRename()
            } label: {
                Label("Rename", systemImage: "character.cursor.ibeam")
            }

            Divider()

            Button {
                onToggleMute()
            } label: {
                Label(part.isMuted ? "Unmute" : "Mute", systemImage: part.isMuted ? "speaker.wave.2" : "speaker.slash")
            }

            Button {
                onToggleSolo()
            } label: {
                Label(part.isSolo ? "Unsolo" : "Solo", systemImage: "s.circle")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Part", systemImage: "trash")
            }
        }
    }
}

// MARK: - AIComingSoonSheet

struct AIComingSoonSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.purple.opacity(0.2), .blue.opacity(0.2)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 100, height: 100)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(LinearGradient(colors: [.purple, .blue],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                }

                VStack(spacing: 12) {
                    Text("AI Assistant")
                        .font(.title.bold())

                    Text("Coming in Phase 2")
                        .font(.headline)
                        .foregroundColor(.purple)

                    Text("The AI Assistant will help you:\n• Harmonize your melody\n• Orchestrate for full ensemble\n• Generate counter-melodies\n• Suggest chord progressions")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Got It!")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                        .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
        guard cleaned.count == 6, let hexValue = UInt32(cleaned, radix: 16) else { return nil }
        let r = Double((hexValue >> 16) & 0xFF) / 255.0
        let g = Double((hexValue >> 8) & 0xFF) / 255.0
        let b = Double(hexValue & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
