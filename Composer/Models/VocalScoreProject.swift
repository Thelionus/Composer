import Foundation

// MARK: - VocalScoreProject

/// The root model representing a complete composition project.
struct VocalScoreProject: Identifiable, Codable {
    var id: UUID
    var title: String
    var composer: String
    var createdAt: Date
    var modifiedAt: Date
    var tempo: Double                   // BPM
    var timeSignatureNumerator: Int
    var timeSignatureDenominator: Int
    var keySignature: KeySignature
    var parts: [Part]
    var totalBars: Int

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        title: String = "Untitled Composition",
        composer: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        tempo: Double = 120.0,
        timeSignatureNumerator: Int = 4,
        timeSignatureDenominator: Int = 4,
        keySignature: KeySignature = .cMajor,
        parts: [Part] = [],
        totalBars: Int = 32
    ) {
        self.id = id
        self.title = title
        self.composer = composer
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.tempo = tempo
        self.timeSignatureNumerator = timeSignatureNumerator
        self.timeSignatureDenominator = timeSignatureDenominator
        self.keySignature = keySignature
        self.parts = parts
        self.totalBars = totalBars
    }

    // MARK: - Computed Properties

    /// Total duration of the piece in seconds based on tempo and total bars.
    var durationSeconds: Double {
        let beatsPerBar = Double(timeSignatureNumerator)
        let totalBeats = beatsPerBar * Double(totalBars)
        return (totalBeats / tempo) * 60.0
    }

    /// Number of active (non-muted) parts.
    var activePartsCount: Int {
        parts.filter { !$0.isMuted }.count
    }

    /// Total note count across all parts.
    var totalNoteCount: Int {
        parts.reduce(0) { $0 + $1.notes.count }
    }

    /// A human-readable description of the time signature.
    var timeSignatureDisplay: String {
        "\(timeSignatureNumerator)/\(timeSignatureDenominator)"
    }

    /// Touch-up the modifiedAt timestamp whenever parts change.
    mutating func markModified() {
        modifiedAt = Date()
    }
}

// MARK: - KeySignature

enum KeySignature: String, Codable, CaseIterable, Identifiable {
    // Major keys
    case cMajor       = "C Major"
    case gMajor       = "G Major"
    case dMajor       = "D Major"
    case aMajor       = "A Major"
    case eMajor       = "E Major"
    case bMajor       = "B Major"
    case fSharpMajor  = "F# Major"
    case fMajor       = "F Major"
    case bFlatMajor   = "Bb Major"
    case eFlatMajor   = "Eb Major"
    case aFlatMajor   = "Ab Major"
    case dFlatMajor   = "Db Major"

    // Minor keys
    case aMinor       = "A Minor"
    case eMinor       = "E Minor"
    case bMinor       = "B Minor"
    case fSharpMinor  = "F# Minor"
    case cSharpMinor  = "C# Minor"
    case dMinor       = "D Minor"
    case gMinor       = "G Minor"
    case cMinor       = "C Minor"
    case fMinor       = "F Minor"
    case bFlatMinor   = "Bb Minor"

    var id: String { rawValue }

    /// Display-friendly name.
    var displayName: String { rawValue }

    /// Number of sharps (positive) or flats (negative) in the key signature.
    var accidentalCount: Int {
        switch self {
        case .cMajor, .aMinor:         return 0
        case .gMajor, .eMinor:         return 1
        case .dMajor, .bMinor:         return 2
        case .aMajor, .fSharpMinor:    return 3
        case .eMajor, .cSharpMinor:    return 4
        case .bMajor:                  return 5
        case .fSharpMajor:             return 6
        case .fMajor, .dMinor:         return -1
        case .bFlatMajor, .gMinor:     return -2
        case .eFlatMajor, .cMinor:     return -3
        case .aFlatMajor, .fMinor:     return -4
        case .dFlatMajor, .bFlatMinor: return -5
        }
    }

    /// Returns true if the key uses sharps, false if flats, nil if C major/A minor.
    var usesSharps: Bool {
        accidentalCount > 0
    }

    var isMinor: Bool {
        switch self {
        case .aMinor, .eMinor, .bMinor, .fSharpMinor,
             .cSharpMinor, .dMinor, .gMinor, .cMinor,
             .fMinor, .bFlatMinor:
            return true
        default:
            return false
        }
    }

    /// The MIDI note numbers (0–11 representing pitch class) that are affected by sharps or flats.
    var alteredPitchClasses: [Int] {
        if accidentalCount == 0 { return [] }

        // Order of sharps: F C G D A E B (pitch classes 5,0,7,2,9,4,11)
        let sharpOrder: [Int] = [5, 0, 7, 2, 9, 4, 11]
        // Order of flats: B E A D G C F (pitch classes 11,4,9,2,7,0,5)
        let flatOrder: [Int] = [11, 4, 9, 2, 7, 0, 5]

        if accidentalCount > 0 {
            return Array(sharpOrder.prefix(accidentalCount))
        } else {
            return Array(flatOrder.prefix(-accidentalCount))
        }
    }
}

// MARK: - Sample Projects

extension VocalScoreProject {
    static var sampleProject: VocalScoreProject {
        VocalScoreProject(
            title: "Symphony No. 1",
            composer: "New Composer",
            tempo: 120,
            timeSignatureNumerator: 4,
            timeSignatureDenominator: 4,
            keySignature: .cMajor,
            parts: [],
            totalBars: 32
        )
    }
}
