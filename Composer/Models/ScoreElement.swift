import Foundation
import SwiftUI

// MARK: - ScoreElement
// Generic protocol and concrete types for elements that appear in the score view.

protocol ScoreElement: Identifiable {
    var id: UUID { get }
    var startBeat: Double { get }
    var displayLayer: ScoreLayer { get }
}

// MARK: - ScoreLayer

enum ScoreLayer: Int, Comparable {
    case background = 0
    case staff      = 1
    case barLines   = 2
    case noteHeads  = 3
    case stems      = 4
    case beams      = 5
    case accidentals = 6
    case articulations = 7
    case dynamics   = 8
    case text       = 9

    static func < (lhs: ScoreLayer, rhs: ScoreLayer) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - BarLine

struct BarLine: ScoreElement {
    var id: UUID = UUID()
    var startBeat: Double
    var barNumber: Int
    var style: BarLineStyle
    var displayLayer: ScoreLayer { .barLines }
}

enum BarLineStyle: String, Codable {
    case regular     = "Regular"
    case double      = "Double"
    case finalDouble = "Final"
    case repeatStart = "Repeat Start"
    case repeatEnd   = "Repeat End"
}

// MARK: - TimeSignatureElement

struct TimeSignatureElement: ScoreElement {
    var id: UUID = UUID()
    var startBeat: Double
    var numerator: Int
    var denominator: Int
    var displayLayer: ScoreLayer { .text }
}

// MARK: - DynamicMark

struct DynamicMark: ScoreElement {
    var id: UUID = UUID()
    var startBeat: Double
    var dynamic: Dynamic
    var noteID: UUID
    var displayLayer: ScoreLayer { .dynamics }
}

// MARK: - TempoMark

struct TempoMark: ScoreElement {
    var id: UUID = UUID()
    var startBeat: Double
    var bpm: Double
    var text: String
    var displayLayer: ScoreLayer { .text }
}

// MARK: - ScoreLayout

/// Layout constants for the score renderer.
struct ScoreLayout {
    /// Distance in points between adjacent staff lines.
    let staffLineSpacing: CGFloat

    /// Total height of the 5-line staff.
    var staffHeight: CGFloat { staffLineSpacing * 4 }

    /// Width of a single quarter note position.
    var beatWidth: CGFloat

    /// Horizontal margin before the first note.
    let leadingMargin: CGFloat

    /// Height of a note head (= staffLineSpacing).
    var noteHeadHeight: CGFloat { staffLineSpacing }

    /// Width of a note head.
    var noteHeadWidth: CGFloat { staffLineSpacing * 1.4 }

    /// Standard stem length.
    var stemLength: CGFloat { staffLineSpacing * 3.5 }

    /// Vertical offset from canvas top to the top staff line.
    let staffTopPadding: CGFloat

    static let `default` = ScoreLayout(
        staffLineSpacing: 10,
        beatWidth: 60,
        leadingMargin: 80,
        staffTopPadding: 40
    )

    static let compact = ScoreLayout(
        staffLineSpacing: 7,
        beatWidth: 45,
        leadingMargin: 60,
        staffTopPadding: 28
    )

    // MARK: - Coordinate Helpers

    /// Vertical center Y-position of a staff line (0 = top line, 4 = bottom line).
    func staffLineY(line: Int) -> CGFloat {
        staffTopPadding + CGFloat(line) * staffLineSpacing
    }

    /// Y-position for a given MIDI note number on the staff, relative to `clef`.
    func yPosition(forMIDINote midi: Int, clef: Clef) -> CGFloat {
        let bottomLine = clef.bottomLineNote
        // Each half-step is half a staff-space; diatonic steps map 1:1 to staff positions
        let semitones = midi - bottomLine
        // Convert semitones to staff steps (diatonic scale)
        let staffStep = diatonicStep(fromSemitones: semitones)
        // Bottom line is at line 4 (index 4 from top in 5-line staff)
        let lineFromTop = 4 - (staffStep / 2)   // divide by 2 because steps go every half-space
        return staffTopPadding + CGFloat(lineFromTop) * staffLineSpacing
    }

    /// Horizontal X-position for a given beat.
    func xPosition(forBeat beat: Double) -> CGFloat {
        leadingMargin + CGFloat(beat - 1.0) * beatWidth
    }

    // MARK: - Private Helpers

    /// Approximates the number of diatonic scale steps from a semitone interval.
    private func diatonicStep(fromSemitones semitones: Int) -> Int {
        // Maps chromatic interval to diatonic step count
        // Octave = 12 semitones = 7 steps
        let octaves = semitones / 12
        let remainder = semitones % 12
        let diatonicRemainders = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6]
        let remSteps = remainder >= 0 ? diatonicRemainders[remainder] :
                       -diatonicRemainders[(-remainder) % 12]
        return octaves * 7 + remSteps
    }
}

// MARK: - NoteRenderInfo

/// Pre-computed rendering information for a single note.
struct NoteRenderInfo: Identifiable {
    let id: UUID
    let note: Note
    let x: CGFloat
    let y: CGFloat
    let stemUp: Bool
    let showLedgerLines: [CGFloat]  // Y positions for ledger lines
    let showAccidental: Accidental
    let beamGroup: Int?             // Index of beam group, nil if not beamed
}

enum Accidental {
    case none, sharp, flat, natural
}
