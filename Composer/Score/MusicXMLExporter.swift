import Foundation

// MARK: - MusicXMLExporter

/// Exports a VocalScoreProject to MusicXML 4.0 format.
/// Produces a valid multi-part score with all notes, key/time signatures, tempo, and articulations.
struct MusicXMLExporter {

    // MARK: - Public API

    /// Export project to MusicXML Data.
    func export(project: VocalScoreProject) throws -> Data {
        let xml = buildXMLString(project: project)
        guard let data = xml.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }
        return data
    }

    /// Write MusicXML directly to a file URL.
    func exportToFile(project: VocalScoreProject, url: URL) throws {
        let data = try export(project: project)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - XML Construction

    private func buildXMLString(project: VocalScoreProject) -> String {
        var lines: [String] = []

        // XML Declaration
        lines.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        lines.append(#"<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">"#)
        lines.append(#"<score-partwise version="4.0">"#)

        // Work / Movement / Credit
        lines.append("  <work>")
        lines.append("    <work-title>\(xmlEscape(project.title))</work-title>")
        lines.append("  </work>")
        lines.append("  <identification>")
        lines.append("    <creator type=\"composer\">\(xmlEscape(project.composer))</creator>")
        lines.append("    <encoding>")
        lines.append("      <software>VocalScore Pro</software>")
        lines.append("      <encoding-date>\(ISO8601DateFormatter().string(from: project.createdAt))</encoding-date>")
        lines.append("    </encoding>")
        lines.append("  </identification>")

        // Defaults (staff size)
        lines.append("  <defaults>")
        lines.append("    <scaling>")
        lines.append("      <millimeters>7</millimeters>")
        lines.append("      <tenths>40</tenths>")
        lines.append("    </scaling>")
        lines.append("  </defaults>")

        // Part List
        lines.append("  <part-list>")
        for (index, part) in project.parts.enumerated() {
            let partID = "P\(index + 1)"
            lines.append("    <score-part id=\"\(partID)\">")
            lines.append("      <part-name>\(xmlEscape(part.name))</part-name>")
            lines.append("      <part-abbreviation>\(abbreviation(part.name))</part-abbreviation>")
            lines.append("      <score-instrument id=\"\(partID)-I1\">")
            lines.append("        <instrument-name>\(xmlEscape(part.instrument.name))</instrument-name>")
            lines.append("      </score-instrument>")
            lines.append("      <midi-instrument id=\"\(partID)-I1\">")
            lines.append("        <midi-channel>\(min(index + 1, 16))</midi-channel>")
            lines.append("        <midi-program>\(part.instrument.midiProgram + 1)</midi-program>")
            lines.append("        <volume>\(Int(part.volume * 127))</volume>")
            lines.append("        <pan>\(Int(part.pan * 64))</pan>")
            lines.append("      </midi-instrument>")
            lines.append("    </score-part>")
        }
        lines.append("  </part-list>")

        // Parts
        for (index, part) in project.parts.enumerated() {
            let partID = "P\(index + 1)"
            lines.append(contentsOf: buildPart(part, partID: partID, project: project))
        }

        lines.append("</score-partwise>")
        return lines.joined(separator: "\n")
    }

    // MARK: - Part Builder

    private func buildPart(_ part: Part, partID: String, project: VocalScoreProject) -> [String] {
        var lines: [String] = []
        lines.append("  <part id=\"\(partID)\">")

        let beatsPerBar = project.timeSignatureNumerator
        let totalBars = project.totalBars

        // Sort notes by start beat
        let sortedNotes = part.sortedNotes

        // Group notes into measures
        var measureNotes: [[Note]] = Array(repeating: [], count: totalBars + 1)
        for note in sortedNotes {
            let barIndex = Int((note.startBeat - 1.0) / Double(beatsPerBar))
            let clampedBar = max(0, min(barIndex, totalBars - 1))
            measureNotes[clampedBar].append(note)
        }

        for barIndex in 0..<totalBars {
            let barNumber = barIndex + 1
            let barNotes = measureNotes[barIndex]

            lines.append("    <measure number=\"\(barNumber)\">")

            // Attributes (only on first measure, or when they change)
            if barNumber == 1 {
                lines.append(contentsOf: buildMeasureAttributes(project: project, part: part))
            }

            // Tempo direction on first measure
            if barNumber == 1 {
                lines.append("      <direction placement=\"above\">")
                lines.append("        <direction-type>")
                lines.append("          <metronome parentheses=\"no\">")
                lines.append("            <beat-unit>quarter</beat-unit>")
                lines.append("            <per-minute>\(Int(project.tempo))</per-minute>")
                lines.append("          </metronome>")
                lines.append("        </direction-type>")
                lines.append("        <sound tempo=\"\(Int(project.tempo))\"/>")
                lines.append("      </direction>")
            }

            // Notes in this measure
            if barNotes.isEmpty {
                // Whole-measure rest
                lines.append(contentsOf: buildWholeRest(beats: beatsPerBar))
            } else {
                // Sort by start beat within measure
                for note in barNotes.sorted(by: { $0.startBeat < $1.startBeat }) {
                    lines.append(contentsOf: buildNote(note, project: project, part: part))
                }
            }

            lines.append("    </measure>")
        }

        lines.append("  </part>")
        return lines
    }

    // MARK: - Attributes Block

    private func buildMeasureAttributes(project: VocalScoreProject, part: Part) -> [String] {
        var lines: [String] = []
        let divisions = 16 // divisions per quarter note (enough for 32nd notes)

        lines.append("      <attributes>")
        lines.append("        <divisions>\(divisions)</divisions>")

        // Key signature
        let accCount = project.keySignature.accidentalCount
        lines.append("        <key>")
        lines.append("          <fifths>\(accCount)</fifths>")
        lines.append("          <mode>\(project.keySignature.isMinor ? "minor" : "major")</mode>")
        lines.append("        </key>")

        // Time signature
        lines.append("        <time>")
        lines.append("          <beats>\(project.timeSignatureNumerator)</beats>")
        lines.append("          <beat-type>\(project.timeSignatureDenominator)</beat-type>")
        lines.append("        </time>")

        // Clef
        lines.append("        <clef>")
        switch part.instrument.clef {
        case .treble:
            lines.append("          <sign>G</sign>")
            lines.append("          <line>2</line>")
        case .bass:
            lines.append("          <sign>F</sign>")
            lines.append("          <line>4</line>")
        case .alto:
            lines.append("          <sign>C</sign>")
            lines.append("          <line>3</line>")
        case .tenor:
            lines.append("          <sign>C</sign>")
            lines.append("          <line>4</line>")
        }
        lines.append("        </clef>")

        // Transposition
        if part.instrument.transposition != 0 {
            let semitones = part.instrument.transposition
            let octaves = semitones / 12
            let chromatic = semitones % 12
            lines.append("        <transpose>")
            if octaves != 0 {
                lines.append("          <octave-change>\(octaves)</octave-change>")
            }
            lines.append("          <chromatic>\(chromatic)</chromatic>")
            lines.append("        </transpose>")
        }

        lines.append("      </attributes>")
        return lines
    }

    // MARK: - Note Builder

    private func buildNote(_ note: Note, project: VocalScoreProject, part: Part) -> [String] {
        let divisions = 16
        var lines: [String] = []

        lines.append("      <note>")

        if note.isRest || note.pitch < 0 {
            lines.append("        <rest/>")
        } else {
            // Pitch
            let noteName = midiToStepOctave(note.pitch)
            lines.append("        <pitch>")
            lines.append("          <step>\(noteName.step)</step>")
            if noteName.alter != 0 {
                lines.append("          <alter>\(noteName.alter)</alter>")
            }
            lines.append("          <octave>\(noteName.octave)</octave>")
            lines.append("        </pitch>")
        }

        // Duration in divisions
        let durationDivs = Int(note.duration.beats * Double(divisions))
        lines.append("        <duration>\(max(1, durationDivs))</duration>")

        // Voice
        lines.append("        <voice>1</voice>")

        // Note type
        lines.append("        <type>\(noteTypeName(note.duration))</type>")

        // Dot
        if note.duration.isDotted {
            lines.append("        <dot/>")
        }

        // Tied
        if note.isTied {
            lines.append("        <tie type=\"start\"/>")
        }

        // Accidental (simplified: always from key sig context)
        let alteration = midiToStepOctave(note.pitch).alter
        if alteration != 0 {
            lines.append("        <accidental>\(alteration > 0 ? "sharp" : "flat")</accidental>")
        }

        // Staff
        lines.append("        <staff>1</staff>")

        // Notations block for articulations, dynamics, ties
        var notations: [String] = []

        if note.isTied {
            notations.append("          <tied type=\"start\"/>")
        }

        let artTag = note.articulation.musicXMLTag
        if !artTag.isEmpty {
            notations.append("          <articulations>")
            notations.append("            <\(artTag)/>")
            notations.append("          </articulations>")
        }

        // Dynamic
        notations.append("          <dynamics>")
        notations.append("            <\(note.dynamic.rawValue)/>")
        notations.append("          </dynamics>")

        if !notations.isEmpty {
            lines.append("        <notations>")
            lines.append(contentsOf: notations)
            lines.append("        </notations>")
        }

        lines.append("      </note>")
        return lines
    }

    private func buildWholeRest(beats: Int) -> [String] {
        let divisions = 16
        let duration = beats * divisions
        return [
            "      <note>",
            "        <rest measure=\"yes\"/>",
            "        <duration>\(duration)</duration>",
            "        <voice>1</voice>",
            "        <type>whole</type>",
            "        <staff>1</staff>",
            "      </note>"
        ]
    }

    // MARK: - Helpers

    private struct NoteComponents {
        let step: String
        let alter: Int  // 1 = sharp, -1 = flat, 0 = natural
        let octave: Int
    }

    private func midiToStepOctave(_ midi: Int) -> NoteComponents {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let altNames  = [  0,    1,   0,    1,   0,   0,    1,   0,    1,   0,    1,   0]
        let steps     = ["C","C","D","D","E","F","F","G","G","A","A","B"]
        let pitchClass = midi % 12
        let octave = (midi / 12) - 1
        return NoteComponents(
            step: steps[pitchClass],
            alter: altNames[pitchClass],
            octave: octave
        )
    }

    private func noteTypeName(_ duration: NoteDuration) -> String {
        switch duration {
        case .whole:                                        return "whole"
        case .half, .dottedHalf:                           return "half"
        case .quarter, .dottedQuarter, .tripletQuarter:    return "quarter"
        case .eighth, .dottedEighth, .tripletEighth:       return "eighth"
        case .sixteenth, .tripletSixteenth:                return "16th"
        case .thirtySecond:                                return "32nd"
        }
    }

    private func abbreviation(_ name: String) -> String {
        let words = name.split(separator: " ")
        if let first = words.first {
            return String(first.prefix(3)) + "."
        }
        return String(name.prefix(4))
    }

    private func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - ExportError

enum ExportError: LocalizedError {
    case encodingFailed
    case fileWriteFailed(String)
    case invalidProject(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:           return "Failed to encode export data."
        case .fileWriteFailed(let msg): return "File write failed: \(msg)"
        case .invalidProject(let msg):  return "Invalid project: \(msg)"
        }
    }
}
