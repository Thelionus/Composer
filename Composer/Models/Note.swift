import Foundation

// MARK: - Note

/// Represents a single musical note within a Part.
struct Note: Identifiable, Codable, Hashable {
    var id: UUID
    var pitch: Int          // MIDI note number 0–127 (middle C = 60)
    var duration: NoteDuration
    var startBeat: Double   // beat position in the piece (1-indexed)
    var velocity: Int       // 0–127, representing dynamics
    var articulation: Articulation
    var dynamic: Dynamic
    var isTied: Bool        // tied to the next note of the same pitch
    var isGraceNote: Bool
    var confidence: Float   // 0–1, from pitch detection algorithm
    var isFlagged: Bool     // out-of-instrument-range or uncertain transcription
    var flagReason: String?

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        pitch: Int = 60,
        duration: NoteDuration = .quarter,
        startBeat: Double = 1.0,
        velocity: Int = 80,
        articulation: Articulation = .normal,
        dynamic: Dynamic = .mf,
        isTied: Bool = false,
        isGraceNote: Bool = false,
        confidence: Float = 1.0,
        isFlagged: Bool = false,
        flagReason: String? = nil
    ) {
        self.id = id
        self.pitch = pitch
        self.duration = duration
        self.startBeat = startBeat
        self.velocity = velocity
        self.articulation = articulation
        self.dynamic = dynamic
        self.isTied = isTied
        self.isGraceNote = isGraceNote
        self.confidence = confidence
        self.isFlagged = isFlagged
        self.flagReason = flagReason
    }

    // MARK: - Computed Properties

    /// End beat position (exclusive).
    var endBeat: Double {
        startBeat + duration.beats
    }

    /// Human-readable note name (e.g. "C4", "F#5").
    var noteName: String {
        Note.midiNoteToName(pitch)
    }

    /// Returns true if the note is a rest (pitch == -1 by convention).
    var isRest: Bool {
        pitch == -1
    }

    // MARK: - Static Helpers

    static func midiNoteToName(_ midi: Int) -> String {
        guard midi >= 0 && midi <= 127 else { return "?" }
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (midi / 12) - 1
        let name = noteNames[midi % 12]
        return "\(name)\(octave)"
    }

    static func midiNoteToFrequency(_ midi: Int) -> Float {
        // A4 = MIDI 69 = 440 Hz
        return 440.0 * pow(2.0, Float(midi - 69) / 12.0)
    }

    /// The pitch class (0–11, where 0 = C).
    var pitchClass: Int {
        pitch % 12
    }

    /// The octave number.
    var octave: Int {
        (pitch / 12) - 1
    }
}

// MARK: - NoteDuration

enum NoteDuration: String, Codable, CaseIterable, Identifiable {
    case whole          = "Whole"
    case half           = "Half"
    case quarter        = "Quarter"
    case eighth         = "Eighth"
    case sixteenth      = "16th"
    case thirtySecond   = "32nd"
    case dottedHalf     = "Dotted Half"
    case dottedQuarter  = "Dotted Quarter"
    case dottedEighth   = "Dotted Eighth"
    case tripletQuarter = "Triplet Quarter"
    case tripletEighth  = "Triplet Eighth"
    case tripletSixteenth = "Triplet 16th"

    var id: String { rawValue }

    /// Duration in beats (quarter note = 1.0 beat).
    var beats: Double {
        switch self {
        case .whole:            return 4.0
        case .half:             return 2.0
        case .quarter:          return 1.0
        case .eighth:           return 0.5
        case .sixteenth:        return 0.25
        case .thirtySecond:     return 0.125
        case .dottedHalf:       return 3.0
        case .dottedQuarter:    return 1.5
        case .dottedEighth:     return 0.75
        case .tripletQuarter:   return 2.0 / 3.0
        case .tripletEighth:    return 1.0 / 3.0
        case .tripletSixteenth: return 1.0 / 6.0
        }
    }

    /// Duration in seconds given a BPM.
    func seconds(atTempo bpm: Double) -> Double {
        beats * (60.0 / bpm)
    }

    /// The MusicXML type string for this duration.
    var musicXMLType: String {
        switch self {
        case .whole:                                        return "whole"
        case .half, .dottedHalf:                           return "half"
        case .quarter, .dottedQuarter, .tripletQuarter:    return "quarter"
        case .eighth, .dottedEighth, .tripletEighth:       return "eighth"
        case .sixteenth, .tripletSixteenth:                return "16th"
        case .thirtySecond:                                return "32nd"
        }
    }

    var isDotted: Bool {
        switch self {
        case .dottedHalf, .dottedQuarter, .dottedEighth: return true
        default: return false
        }
    }

    var isTriplet: Bool {
        switch self {
        case .tripletQuarter, .tripletEighth, .tripletSixteenth: return true
        default: return false
        }
    }

    /// SF Symbol name for toolbar icons.
    var symbolName: String {
        switch self {
        case .whole:           return "1.circle"
        case .half:            return "2.circle"
        case .quarter:         return "4.circle"
        case .eighth:          return "8.circle"
        case .sixteenth:       return "16.circle"
        case .thirtySecond:    return "32.circle"
        case .dottedHalf:      return "2.circle.fill"
        case .dottedQuarter:   return "4.circle.fill"
        case .dottedEighth:    return "8.circle.fill"
        case .tripletQuarter:  return "3.circle"
        case .tripletEighth:   return "3.circle.fill"
        case .tripletSixteenth: return "3.square"
        }
    }

    /// The nearest standard (non-triplet) duration equal to or shorter than this one.
    var quantizationResolution: Double {
        beats
    }

    /// Finds the closest NoteDuration to a given number of beats.
    static func nearest(beats: Double) -> NoteDuration {
        var closest = NoteDuration.quarter
        var smallestDiff = Double.infinity
        for dur in NoteDuration.allCases {
            let diff = abs(dur.beats - beats)
            if diff < smallestDiff {
                smallestDiff = diff
                closest = dur
            }
        }
        return closest
    }
}

// MARK: - Articulation

enum Articulation: String, Codable, CaseIterable, Identifiable {
    case normal       = "Normal"
    case staccato     = "Staccato"
    case legato       = "Legato"
    case accent       = "Accent"
    case tenuto       = "Tenuto"
    case pizzicato    = "Pizzicato"
    case arco         = "Arco"
    case tremolo      = "Tremolo"
    case colLegno     = "Col Legno"
    case sulPonticello = "Sul Ponticello"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .normal:        return "music.note"
        case .staccato:      return "circle.fill"
        case .legato:        return "link"
        case .accent:        return "greaterthan"
        case .tenuto:        return "minus"
        case .pizzicato:     return "p.circle"
        case .arco:          return "a.circle"
        case .tremolo:       return "waveform"
        case .colLegno:      return "c.circle"
        case .sulPonticello: return "s.circle"
        }
    }

    /// MusicXML articulation tag name (empty string if no standard tag).
    var musicXMLTag: String {
        switch self {
        case .staccato:  return "staccato"
        case .accent:    return "accent"
        case .tenuto:    return "tenuto"
        default:         return ""
        }
    }

    /// Multiplier applied to note duration for MIDI rendering.
    var durationMultiplier: Float {
        switch self {
        case .staccato:  return 0.5
        case .legato:    return 1.0
        case .tenuto:    return 0.95
        default:         return 0.85
        }
    }
}

// MARK: - Dynamic

enum Dynamic: String, Codable, CaseIterable, Identifiable {
    case ppp = "ppp"
    case pp  = "pp"
    case p   = "p"
    case mp  = "mp"
    case mf  = "mf"
    case f   = "f"
    case ff  = "ff"
    case fff = "fff"
    case sfz = "sfz"

    var id: String { rawValue }

    /// MIDI velocity value corresponding to this dynamic level.
    var midiVelocity: Int {
        switch self {
        case .ppp: return 16
        case .pp:  return 33
        case .p:   return 49
        case .mp:  return 64
        case .mf:  return 80
        case .f:   return 96
        case .ff:  return 112
        case .fff: return 127
        case .sfz: return 120
        }
    }

    /// A numeric intensity value (0–1) for graphical rendering.
    var intensity: Float {
        Float(midiVelocity) / 127.0
    }
}
