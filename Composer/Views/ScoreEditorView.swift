import SwiftUI

// MARK: - ScoreEditorView

/// Touch-optimized score editor with zoomable staff, note selection and editing.
struct ScoreEditorView: View {
    let part: Part
    let project: VocalScoreProject

    @StateObject private var viewModel: ScoreEditorViewModel
    @EnvironmentObject private var projectViewModel: ProjectViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingRangeAlert = false
    @State private var showingAddNoteSheet = false
    @State private var selectedDuration: NoteDuration = .quarter
    @State private var selectedArticulation: Articulation = .normal
    @State private var selectedDynamic: Dynamic = .mf
    @State private var bottomToolbarMode: BottomToolbarMode = .note
    @State private var showingFlagDetail: RangeViolation? = nil

    init(part: Part, project: VocalScoreProject) {
        self.part = part
        self.project = project
        _viewModel = StateObject(wrappedValue: ScoreEditorViewModel(part: part))
    }

    enum BottomToolbarMode: String, CaseIterable {
        case note        = "Note"
        case articulation = "Articulation"
        case dynamic     = "Dynamic"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main score canvas
            scoreCanvas

            Divider()

            // Bottom toolbar
            bottomToolbar
        }
        .navigationTitle(viewModel.part.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                undoRedoButtons
                playButton
                validateButton
            }
        }
        .alert("Range Violations", isPresented: $viewModel.showingViolationAlert) {
            Button("OK") { viewModel.showingViolationAlert = false }
        } message: {
            Text(rangeViolationSummary)
        }
        .onDisappear {
            saveChanges()
        }
    }

    // MARK: - Score Canvas

    private var scoreCanvas: some View {
        ZStack(alignment: .topTrailing) {
            // The score renderer
            ScoreRenderer(
                part: viewModel.part,
                project: project,
                layout: ScoreLayout.default,
                selectedNoteIDs: viewModel.selectedNotes,
                currentBeat: viewModel.currentBeat
            ) { noteID in
                viewModel.selectNote(noteID)
                // Audition the selected note
                if let note = viewModel.part.notes.first(where: { $0.id == noteID }) {
                    viewModel.auditionNote(note)
                }
            }
            .background(Color.white)

            // Selection info overlay
            if viewModel.hasSelection {
                selectionInfoOverlay
                    .padding(12)
            }

            // Flagged note indicator
            if viewModel.flaggedNotesCount > 0 && !viewModel.hasSelection {
                flagBadge
                    .padding(12)
            }
        }
        // Pitch drag gesture on selected note
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard viewModel.selectedNotes.count == 1,
                          let noteID = viewModel.selectedNotes.first else { return }
                    // Vertical drag to change pitch (drag up = pitch up)
                    let semitoneThreshold: CGFloat = ScoreLayout.default.staffLineSpacing * 0.5
                    let semitones = Int(-value.translation.height / semitoneThreshold)
                    if semitones != 0 {
                        viewModel.moveNote(noteID, semitones: semitones)
                    }
                }
        )
    }

    private var selectionInfoOverlay: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let note = viewModel.selectedNote {
                Text(note.noteName)
                    .font(.headline.monospaced())
                    .foregroundColor(.blue)
                Text(note.duration.rawValue)
                    .font(.caption)
                    .foregroundColor(.blue.opacity(0.8))
                if note.isFlagged, let reason = note.flagReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 180)
                }
            } else {
                Text("\(viewModel.selectedNotes.count) selected")
                    .font(.headline)
                    .foregroundColor(.blue)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
    }

    private var flagBadge: some View {
        Button {
            viewModel.validateRanges()
        } label: {
            Label("\(viewModel.flaggedNotesCount) issue\(viewModel.flaggedNotesCount > 1 ? "s" : "")",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold())
                .foregroundColor(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .cornerRadius(10)
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        VStack(spacing: 0) {
            // Mode selector
            Picker("Tool", selection: $bottomToolbarMode) {
                ForEach(BottomToolbarMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Tool content
            Group {
                switch bottomToolbarMode {
                case .note:
                    durationToolbar
                case .articulation:
                    articulationToolbar
                case .dynamic:
                    dynamicToolbar
                }
            }
            .frame(height: 60)
        }
        .background(.bar)
    }

    private var durationToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(NoteDuration.allCases) { duration in
                    Button {
                        selectedDuration = duration
                        if let noteID = viewModel.selectedNotes.first, viewModel.selectedNotes.count == 1 {
                            viewModel.changeNoteDuration(noteID, duration: duration)
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: duration.symbolName)
                                .font(.system(size: 14))
                            Text(String(duration.rawValue.prefix(3)))
                                .font(.system(size: 9))
                        }
                        .frame(width: 44, height: 44)
                        .background(selectedDuration == duration ? Color.purple : Color.clear)
                        .foregroundColor(selectedDuration == duration ? .white : .primary)
                        .cornerRadius(8)
                    }
                }

                Divider().frame(height: 30)

                // Delete selected
                Button {
                    viewModel.deleteSelectedNotes()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 18))
                        .foregroundColor(.red)
                        .frame(width: 44, height: 44)
                }
                .disabled(!viewModel.hasSelection)
            }
            .padding(.horizontal, 12)
        }
    }

    private var articulationToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Articulation.allCases) { art in
                    Button {
                        selectedArticulation = art
                        if viewModel.hasSelection {
                            viewModel.setArticulationForSelected(art)
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: art.symbolName)
                                .font(.system(size: 14))
                            Text(String(art.rawValue.prefix(4)))
                                .font(.system(size: 9))
                        }
                        .frame(width: 52, height: 44)
                        .background(selectedArticulation == art ? Color.purple : Color.clear)
                        .foregroundColor(selectedArticulation == art ? .white : .primary)
                        .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var dynamicToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Dynamic.allCases) { dynamic in
                    Button {
                        selectedDynamic = dynamic
                        if viewModel.hasSelection {
                            viewModel.setDynamicForSelected(dynamic)
                        }
                    } label: {
                        Text(dynamic.rawValue)
                            .font(.system(size: 15, weight: .bold, design: .serif))
                            .italic()
                            .frame(width: 40, height: 44)
                            .background(selectedDynamic == dynamic ? Color.purple : Color.clear)
                            .foregroundColor(selectedDynamic == dynamic ? .white : .primary)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Toolbar Buttons

    private var undoRedoButtons: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!viewModel.canUndo)

            Button {
                viewModel.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!viewModel.canRedo)
        }
    }

    private var playButton: some View {
        Button {
            if viewModel.isPlaying {
                viewModel.stopPlayback()
            } else if viewModel.hasSelection {
                viewModel.playSelection(tempo: project.tempo)
            } else {
                viewModel.playAll(tempo: project.tempo)
            }
        } label: {
            Image(systemName: viewModel.isPlaying ? "stop.fill" : "play.fill")
                .foregroundColor(viewModel.isPlaying ? .orange : .purple)
        }
    }

    private var validateButton: some View {
        Button {
            viewModel.validateRanges()
        } label: {
            Image(systemName: viewModel.flaggedNotesCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle")
                .foregroundColor(viewModel.flaggedNotesCount > 0 ? .orange : .green)
        }
    }

    // MARK: - Helpers

    private var rangeViolationSummary: String {
        if viewModel.rangeViolations.isEmpty {
            return "All notes are within instrument range."
        }
        let first3 = viewModel.rangeViolations.prefix(3).map { $0.reason }.joined(separator: "\n")
        let extra = viewModel.rangeViolations.count > 3 ? "\n+\(viewModel.rangeViolations.count - 3) more" : ""
        return first3 + extra
    }

    private func saveChanges() {
        // Propagate changes back to the project
        projectViewModel.updatePart(viewModel.part, in: project.id)
    }
}
