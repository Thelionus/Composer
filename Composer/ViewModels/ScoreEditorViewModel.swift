import Foundation
import Combine
import SwiftUI

// MARK: - ScoreEditorViewModel

@MainActor
final class ScoreEditorViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var part: Part
    @Published var selectedNotes: Set<UUID> = []
    @Published var undoStack: [Part] = []
    @Published var redoStack: [Part] = []
    @Published var isPlaying: Bool = false
    @Published var currentBeat: Double = 0.0
    @Published var zoomLevel: CGFloat = 1.0
    @Published var rangeViolations: [RangeViolation] = []
    @Published var showingViolationAlert: Bool = false

    // MARK: - Constants

    private let maxUndoSteps = 100
    private let playbackEngine = PlaybackEngine()

    // MARK: - Initializer

    init(part: Part) {
        self.part = part
    }

    // MARK: - Selection

    func selectNote(_ id: UUID) {
        if selectedNotes.contains(id) {
            selectedNotes.remove(id)
        } else {
            selectedNotes.insert(id)
        }
    }

    func selectAll() {
        selectedNotes = Set(part.notes.map { $0.id })
    }

    func clearSelection() {
        selectedNotes.removeAll()
    }

    func toggleSelection(_ id: UUID) {
        if selectedNotes.contains(id) {
            selectedNotes.remove(id)
        } else {
            selectedNotes.insert(id)
        }
    }

    // MARK: - Note Editing

    func moveNote(_ id: UUID, semitones: Int) {
        guard let index = part.notes.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        let newPitch = max(0, min(127, part.notes[index].pitch + semitones))
        part.notes[index].pitch = newPitch
        // Re-validate range after move
        validateRange(noteIndex: index)
    }

    func moveSelectedNotes(semitones: Int) {
        guard !selectedNotes.isEmpty else { return }
        pushUndo()
        for id in selectedNotes {
            guard let index = part.notes.firstIndex(where: { $0.id == id }) else { continue }
            let newPitch = max(0, min(127, part.notes[index].pitch + semitones))
            part.notes[index].pitch = newPitch
            validateRange(noteIndex: index)
        }
    }

    func changeNoteDuration(_ id: UUID, duration: NoteDuration) {
        guard let index = part.notes.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        part.notes[index].duration = duration
    }

    func setArticulation(_ id: UUID, articulation: Articulation) {
        guard let index = part.notes.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        part.notes[index].articulation = articulation
    }

    func setDynamic(_ id: UUID, dynamic: Dynamic) {
        guard let index = part.notes.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        part.notes[index].dynamic = dynamic
    }

    func setDynamicForSelected(_ dynamic: Dynamic) {
        guard !selectedNotes.isEmpty else { return }
        pushUndo()
        for id in selectedNotes {
            if let index = part.notes.firstIndex(where: { $0.id == id }) {
                part.notes[index].dynamic = dynamic
            }
        }
    }

    func setArticulationForSelected(_ articulation: Articulation) {
        guard !selectedNotes.isEmpty else { return }
        pushUndo()
        for id in selectedNotes {
            if let index = part.notes.firstIndex(where: { $0.id == id }) {
                part.notes[index].articulation = articulation
            }
        }
    }

    func deleteNote(_ id: UUID) {
        pushUndo()
        part.notes.removeAll { $0.id == id }
        selectedNotes.remove(id)
    }

    func deleteSelectedNotes() {
        guard !selectedNotes.isEmpty else { return }
        pushUndo()
        part.notes.removeAll { selectedNotes.contains($0.id) }
        selectedNotes.removeAll()
    }

    func addNote(_ note: Note) {
        pushUndo()
        part.notes.append(note)
        part.notes.sort { $0.startBeat < $1.startBeat }
        validateRangesAllNotes()
    }

    func clearFlag(_ id: UUID) {
        guard let index = part.notes.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        part.notes[index].isFlagged = false
        part.notes[index].flagReason = nil
    }

    // MARK: - Tie Notes

    func tieSelectedNotes() {
        guard selectedNotes.count == 2 else { return }
        pushUndo()
        let sorted = part.notes
            .filter { selectedNotes.contains($0.id) }
            .sorted { $0.startBeat < $1.startBeat }

        guard sorted.count == 2 else { return }
        if let index = part.notes.firstIndex(where: { $0.id == sorted[0].id }) {
            part.notes[index].isTied = true
        }
    }

    // MARK: - Undo / Redo

    func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append(part)
        part = undoStack.removeLast()
    }

    func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append(part)
        part = redoStack.removeLast()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func pushUndo() {
        undoStack.append(part)
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst()
        }
        redoStack.removeAll() // Clear redo stack on new action
    }

    // MARK: - Range Validation

    @discardableResult
    func validateRanges() -> [RangeViolation] {
        var violations: [RangeViolation] = []
        for note in part.notes {
            if note.isRest || note.pitch < 0 { continue }
            if !part.instrument.isNoteInRange(note.pitch) {
                let violation = RangeViolation(
                    note: note,
                    reason: "\(note.noteName) is outside the range of \(part.instrument.name) (\(part.instrument.rangeDisplay))"
                )
                violations.append(violation)
            }
        }
        rangeViolations = violations
        if !violations.isEmpty {
            showingViolationAlert = true
        }
        return violations
    }

    private func validateRangesAllNotes() {
        part.validateNoteRanges()
    }

    private func validateRange(noteIndex: Int) {
        guard noteIndex < part.notes.count else { return }
        let note = part.notes[noteIndex]
        if note.isRest || note.pitch < 0 { return }
        if !part.instrument.isNoteInRange(note.pitch) {
            part.notes[noteIndex].isFlagged = true
            part.notes[noteIndex].flagReason = "\(note.noteName) is outside the range of \(part.instrument.name)"
        } else {
            if part.notes[noteIndex].flagReason?.contains("outside the range") == true {
                part.notes[noteIndex].isFlagged = false
                part.notes[noteIndex].flagReason = nil
            }
        }
    }

    // MARK: - Playback

    func playAll(tempo: Double) {
        isPlaying = true
        playbackEngine.play(notes: part.sortedNotes, instrument: part.instrument, tempo: tempo)
        // Observe playback engine state
        Task {
            while playbackEngine.isPlaying {
                currentBeat = playbackEngine.currentBeat
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms refresh
            }
            isPlaying = false
        }
    }

    func playSelection(tempo: Double) {
        let selectedNotesList = part.notes.filter { selectedNotes.contains($0.id) }
        guard !selectedNotesList.isEmpty else { return }
        isPlaying = true
        playbackEngine.play(notes: selectedNotesList, instrument: part.instrument, tempo: tempo)
        Task {
            while playbackEngine.isPlaying {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            isPlaying = false
        }
    }

    func stopPlayback() {
        playbackEngine.stop()
        isPlaying = false
    }

    func auditionNote(_ note: Note) {
        let duration = note.duration.seconds(atTempo: 120)
        playbackEngine.playNote(
            midiNote: note.pitch,
            velocity: note.velocity,
            duration: duration,
            midiProgram: part.instrument.midiProgram
        )
    }

    // MARK: - Zoom

    func zoomIn() {
        zoomLevel = min(3.0, zoomLevel + 0.25)
    }

    func zoomOut() {
        zoomLevel = max(0.5, zoomLevel - 0.25)
    }

    func resetZoom() {
        zoomLevel = 1.0
    }

    // MARK: - Computed Properties

    var selectedNote: Note? {
        guard selectedNotes.count == 1, let id = selectedNotes.first else { return nil }
        return part.notes.first { $0.id == id }
    }

    var hasSelection: Bool { !selectedNotes.isEmpty }

    var flaggedNotesCount: Int {
        part.notes.filter { $0.isFlagged }.count
    }

    var noteCountDisplay: String {
        "\(part.notes.count) note\(part.notes.count == 1 ? "" : "s")"
    }
}
