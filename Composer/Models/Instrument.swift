import Foundation

// MARK: - Instrument

/// Represents a single orchestral instrument with its MIDI and notation properties.
struct Instrument: Identifiable, Codable, Hashable {
    var id: String          // e.g. "violin_I"
    var name: String
    var family: InstrumentFamily
    var midiProgram: Int    // General MIDI program number (0–127)
    var lowestNote: Int     // MIDI note number
    var highestNote: Int    // MIDI note number
    var transposition: Int  // Semitones to add for concert pitch (0 = concert pitch instrument)
    var clef: Clef
    var icon: String        // SF Symbol name

    // MARK: - Computed Properties

    var rangeDisplay: String {
        "\(Note.midiNoteToName(lowestNote)) – \(Note.midiNoteToName(highestNote))"
    }

    var isTransposing: Bool {
        transposition != 0
    }

    func isNoteInRange(_ midiNote: Int) -> Bool {
        midiNote >= lowestNote && midiNote <= highestNote
    }
}

// MARK: - InstrumentFamily

enum InstrumentFamily: String, Codable, CaseIterable, Identifiable {
    case strings    = "Strings"
    case woodwinds  = "Woodwinds"
    case brass      = "Brass"
    case percussion = "Percussion"
    case keyboard   = "Keyboard"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .strings:    return "music.note"
        case .woodwinds:  return "wind"
        case .brass:      return "horn"
        case .percussion: return "drum"
        case .keyboard:   return "pianokeys"
        }
    }

    var color: String {
        switch self {
        case .strings:    return "#E74C3C"
        case .woodwinds:  return "#27AE60"
        case .brass:      return "#F39C12"
        case .percussion: return "#8E44AD"
        case .keyboard:   return "#2980B9"
        }
    }
}

// MARK: - Clef

enum Clef: String, Codable {
    case treble = "Treble"
    case bass   = "Bass"
    case alto   = "Alto"
    case tenor  = "Tenor"

    /// The MIDI note that sits on the middle line of the staff for this clef.
    var midLineNote: Int {
        switch self {
        case .treble: return 71  // B4
        case .bass:   return 47  // B2
        case .alto:   return 60  // C4
        case .tenor:  return 57  // A3
        }
    }

    /// The MIDI note on the bottom line of the staff.
    var bottomLineNote: Int {
        switch self {
        case .treble: return 64  // E4
        case .bass:   return 43  // G2
        case .alto:   return 53  // F3
        case .tenor:  return 50  // D3
        }
    }
}

// MARK: - Instrument Catalog

extension Instrument {
    /// The complete orchestral instrument catalog — 27 instruments across 5 families.
    static let catalog: [Instrument] = [
        // MARK: Strings
        Instrument(
            id: "violin_I",
            name: "Violin I",
            family: .strings,
            midiProgram: 40,
            lowestNote: 55,   // G3
            highestNote: 103, // G7
            transposition: 0,
            clef: .treble,
            icon: "music.note"
        ),
        Instrument(
            id: "violin_II",
            name: "Violin II",
            family: .strings,
            midiProgram: 40,
            lowestNote: 55,   // G3
            highestNote: 100, // E7
            transposition: 0,
            clef: .treble,
            icon: "music.note"
        ),
        Instrument(
            id: "viola",
            name: "Viola",
            family: .strings,
            midiProgram: 41,
            lowestNote: 48,   // C3
            highestNote: 91,  // G6
            transposition: 0,
            clef: .alto,
            icon: "music.note"
        ),
        Instrument(
            id: "cello",
            name: "Cello",
            family: .strings,
            midiProgram: 42,
            lowestNote: 36,   // C2
            highestNote: 76,  // E5
            transposition: 0,
            clef: .bass,
            icon: "music.note"
        ),
        Instrument(
            id: "double_bass",
            name: "Double Bass",
            family: .strings,
            midiProgram: 43,
            lowestNote: 28,   // E1 (sounds an octave lower, but written pitch)
            highestNote: 67,  // G4
            transposition: -12,
            clef: .bass,
            icon: "music.note"
        ),

        // MARK: Woodwinds
        Instrument(
            id: "flute",
            name: "Flute",
            family: .woodwinds,
            midiProgram: 73,
            lowestNote: 60,   // C4
            highestNote: 96,  // C7
            transposition: 0,
            clef: .treble,
            icon: "wind"
        ),
        Instrument(
            id: "oboe",
            name: "Oboe",
            family: .woodwinds,
            midiProgram: 68,
            lowestNote: 58,   // Bb3
            highestNote: 91,  // G6
            transposition: 0,
            clef: .treble,
            icon: "wind"
        ),
        Instrument(
            id: "clarinet_bb",
            name: "Clarinet (Bb)",
            family: .woodwinds,
            midiProgram: 71,
            lowestNote: 50,   // D3 (written), sounds C3
            highestNote: 89,  // F6 (written)
            transposition: -2,
            clef: .treble,
            icon: "wind"
        ),
        Instrument(
            id: "bassoon",
            name: "Bassoon",
            family: .woodwinds,
            midiProgram: 70,
            lowestNote: 34,   // Bb1
            highestNote: 75,  // Eb5
            transposition: 0,
            clef: .bass,
            icon: "wind"
        ),
        Instrument(
            id: "alto_sax",
            name: "Alto Saxophone",
            family: .woodwinds,
            midiProgram: 65,
            lowestNote: 49,   // Db3 (written)
            highestNote: 80,  // Ab5 (written)
            transposition: -9,
            clef: .treble,
            icon: "wind"
        ),
        Instrument(
            id: "tenor_sax",
            name: "Tenor Saxophone",
            family: .woodwinds,
            midiProgram: 66,
            lowestNote: 44,   // Ab2 (written)
            highestNote: 75,  // Eb5 (written)
            transposition: -14,
            clef: .treble,
            icon: "wind"
        ),

        // MARK: Brass
        Instrument(
            id: "french_horn",
            name: "French Horn (F)",
            family: .brass,
            midiProgram: 60,
            lowestNote: 34,   // Bb1 (written)
            highestNote: 77,  // F5 (written)
            transposition: -7,
            clef: .treble,
            icon: "horn"
        ),
        Instrument(
            id: "trumpet_bb",
            name: "Trumpet (Bb)",
            family: .brass,
            midiProgram: 56,
            lowestNote: 52,   // E3 (written)
            highestNote: 82,  // Bb5 (written)
            transposition: -2,
            clef: .treble,
            icon: "horn"
        ),
        Instrument(
            id: "trombone",
            name: "Trombone",
            family: .brass,
            midiProgram: 57,
            lowestNote: 34,   // Bb1
            highestNote: 72,  // C5
            transposition: 0,
            clef: .bass,
            icon: "horn"
        ),
        Instrument(
            id: "tuba",
            name: "Tuba",
            family: .brass,
            midiProgram: 58,
            lowestNote: 24,   // C1
            highestNote: 60,  // C4
            transposition: 0,
            clef: .bass,
            icon: "horn"
        ),

        // MARK: Percussion
        Instrument(
            id: "timpani",
            name: "Timpani",
            family: .percussion,
            midiProgram: 47,
            lowestNote: 36,   // C2
            highestNote: 55,  // G3
            transposition: 0,
            clef: .bass,
            icon: "drum"
        ),
        Instrument(
            id: "xylophone",
            name: "Xylophone",
            family: .percussion,
            midiProgram: 13,
            lowestNote: 65,   // F4
            highestNote: 108, // C8
            transposition: 12,
            clef: .treble,
            icon: "drum"
        ),
        Instrument(
            id: "glockenspiel",
            name: "Glockenspiel",
            family: .percussion,
            midiProgram: 9,
            lowestNote: 79,   // G5 (written; sounds 2 octaves higher)
            highestNote: 108, // C8
            transposition: 24,
            clef: .treble,
            icon: "drum"
        ),
        Instrument(
            id: "harp",
            name: "Harp",
            family: .percussion,
            midiProgram: 46,
            lowestNote: 24,   // C1
            highestNote: 103, // G7
            transposition: 0,
            clef: .treble,   // uses grand staff
            icon: "music.quarternote.3"
        ),
        Instrument(
            id: "marimba",
            name: "Marimba",
            family: .percussion,
            midiProgram: 12,
            lowestNote: 45,   // A2
            highestNote: 96,  // C7
            transposition: 0,
            clef: .treble,
            icon: "drum"
        ),

        // MARK: Keyboard
        Instrument(
            id: "piano",
            name: "Piano",
            family: .keyboard,
            midiProgram: 0,
            lowestNote: 21,   // A0
            highestNote: 108, // C8
            transposition: 0,
            clef: .treble,   // uses grand staff
            icon: "pianokeys"
        ),
        Instrument(
            id: "harpsichord",
            name: "Harpsichord",
            family: .keyboard,
            midiProgram: 6,
            lowestNote: 29,   // F1
            highestNote: 101, // F7
            transposition: 0,
            clef: .treble,
            icon: "pianokeys"
        ),
        Instrument(
            id: "celesta",
            name: "Celesta",
            family: .keyboard,
            midiProgram: 8,
            lowestNote: 60,   // C4 (written; sounds an octave higher)
            highestNote: 96,  // C7
            transposition: 12,
            clef: .treble,
            icon: "pianokeys"
        ),
        Instrument(
            id: "organ",
            name: "Pipe Organ",
            family: .keyboard,
            midiProgram: 19,
            lowestNote: 36,   // C2
            highestNote: 96,  // C7
            transposition: 0,
            clef: .treble,
            icon: "pianokeys"
        ),
        Instrument(
            id: "electric_piano",
            name: "Electric Piano",
            family: .keyboard,
            midiProgram: 4,
            lowestNote: 28,   // E1
            highestNote: 103, // G7
            transposition: 0,
            clef: .treble,
            icon: "pianokeys"
        ),
        Instrument(
            id: "accordion",
            name: "Accordion",
            family: .keyboard,
            midiProgram: 21,
            lowestNote: 41,   // F2
            highestNote: 89,  // F6
            transposition: 0,
            clef: .treble,
            icon: "pianokeys"
        ),
        Instrument(
            id: "vibraphone",
            name: "Vibraphone",
            family: .percussion,
            midiProgram: 11,
            lowestNote: 53,   // F3
            highestNote: 89,  // F6
            transposition: 0,
            clef: .treble,
            icon: "drum"
        )
    ]

    /// Instruments grouped by family, preserving score order.
    static var catalogByFamily: [InstrumentFamily: [Instrument]] {
        Dictionary(grouping: catalog, by: \.family)
    }

    static func instrument(withID id: String) -> Instrument? {
        catalog.first { $0.id == id }
    }

    static var defaultInstrument: Instrument { catalog[0] } // Violin I
}
