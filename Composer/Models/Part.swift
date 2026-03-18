import Foundation

// MARK: - Part

/// A single instrumental part within a VocalScoreProject.
struct Part: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var instrument: Instrument
    var notes: [Note]
    var isVisible: Bool
    var isMuted: Bool
    var isSolo: Bool
    var volume: Float     // 0.0–1.0
    var pan: Float        // -1.0 (left) to 1.0 (right)
    var color: String     // Hex color string for UI differentiation
    var isAIGenerated: Bool
    var recordingURL: URL?

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        name: String = "",
        instrument: Instrument = Instrument.defaultInstrument,
        notes: [Note] = [],
        isVisible: Bool = true,
        isMuted: Bool = false,
        isSolo: Bool = false,
        volume: Float = 0.8,
        pan: Float = 0.0,
        color: String = "#E74C3C",
        isAIGenerated: Bool = false,
        recordingURL: URL? = nil
    ) {
        self.id = id
        self.name = name.isEmpty ? instrument.name : name
        self.instrument = instrument
        self.notes = notes
        self.isVisible = isVisible
        self.isMuted = isMuted
        self.isSolo = isSolo
        self.volume = volume
        self.pan = pan
        self.color = color
        self.isAIGenerated = isAIGenerated
        self.recordingURL = recordingURL
    }

    // MARK: - Computed Properties

    /// Number of notes in this part.
    var noteCount: Int { notes.count }

    /// The beat position of the last note end.
    var lastBeat: Double {
        notes.map { $0.endBeat }.max() ?? 1.0
    }

    /// Notes sorted by start beat.
    var sortedNotes: [Note] {
        notes.sorted { $0.startBeat < $1.startBeat }
    }

    /// Notes that are flagged as out-of-range or uncertain.
    var flaggedNotes: [Note] {
        notes.filter { $0.isFlagged }
    }

    /// Notes that are AI-generated vs. user-edited.
    var aiGeneratedNotes: [Note] {
        notes.filter { $0.confidence < 1.0 }
    }

    /// The beat range covered by notes in this part.
    var beatRange: ClosedRange<Double> {
        let start = notes.map { $0.startBeat }.min() ?? 1.0
        let end = notes.map { $0.endBeat }.max() ?? 2.0
        return start...end
    }

    // MARK: - Mutation Helpers

    mutating func addNote(_ note: Note) {
        notes.append(note)
    }

    mutating func removeNote(id: UUID) {
        notes.removeAll { $0.id == id }
    }

    mutating func updateNote(_ updated: Note) {
        if let index = notes.firstIndex(where: { $0.id == updated.id }) {
            notes[index] = updated
        }
    }

    mutating func validateNoteRanges() {
        for index in notes.indices {
            let note = notes[index]
            if !instrument.isNoteInRange(note.pitch) && !note.isRest {
                notes[index].isFlagged = true
                notes[index].flagReason = "Note \(note.noteName) is outside the range of \(instrument.name) (\(instrument.rangeDisplay))"
            } else if notes[index].isFlagged && notes[index].flagReason?.contains("outside the range") == true {
                // Clear range flags only (keep other flags)
                notes[index].isFlagged = false
                notes[index].flagReason = nil
            }
        }
    }
}

// MARK: - RangeViolation (used in ScoreEditorViewModel)

struct RangeViolation: Identifiable {
    let id: UUID
    let noteID: UUID
    let noteName: String
    let reason: String

    init(note: Note, reason: String) {
        self.id = UUID()
        self.noteID = note.id
        self.noteName = note.noteName
        self.reason = reason
    }
}
