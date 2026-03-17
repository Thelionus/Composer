import Foundation

// MARK: - MIDIExporter

/// Exports a VocalScoreProject to Standard MIDI File Format Type 1 (multi-track).
/// Produces valid SMF with header chunk, tempo track, and one track per Part.
struct MIDIExporter {

    // MARK: - MIDI Constants

    private let ticksPerQuarterNote: UInt16 = 480 // High resolution for accurate timing

    // MARK: - Public API

    func export(project: VocalScoreProject) throws -> Data {
        var data = Data()

        let trackCount = project.parts.count + 1 // +1 for tempo track

        // Header chunk
        data.append(contentsOf: midiHeaderChunk(trackCount: trackCount))

        // Track 0: Tempo & Time Signature
        data.append(contentsOf: tempoTrack(project: project))

        // One track per part
        for (index, part) in project.parts.enumerated() {
            data.append(contentsOf: partTrack(part: part, channel: UInt8(index % 16), project: project))
        }

        return data
    }

    func exportToFile(project: VocalScoreProject, url: URL) throws {
        let data = try export(project: project)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Header Chunk

    /// Builds the 14-byte MIDI header chunk.
    private func midiHeaderChunk(trackCount: Int) -> [UInt8] {
        var bytes: [UInt8] = []

        // Chunk type "MThd"
        bytes.append(contentsOf: Array("MThd".utf8))

        // Chunk length (always 6 for header)
        bytes.append(contentsOf: uint32ToBytes(6))

        // Format: 1 (multi-track)
        bytes.append(contentsOf: uint16ToBytes(1))

        // Number of tracks
        bytes.append(contentsOf: uint16ToBytes(UInt16(trackCount)))

        // Division: ticks per quarter note
        bytes.append(contentsOf: uint16ToBytes(ticksPerQuarterNote))

        return bytes
    }

    // MARK: - Tempo Track (Track 0)

    /// Builds the tempo track containing tempo and time signature meta events.
    private func tempoTrack(project: VocalScoreProject) -> [UInt8] {
        var events: [UInt8] = []

        // Delta time 0
        events.append(contentsOf: varLengthEncode(0))

        // Tempo meta event: FF 51 03 tt tt tt
        // microseconds per quarter note = 60,000,000 / BPM
        let microsecondsPerBeat = UInt32(60_000_000.0 / project.tempo)
        events.append(0xFF)
        events.append(0x51)
        events.append(0x03)
        events.append(contentsOf: uint24ToBytes(microsecondsPerBeat))

        // Delta time 0
        events.append(contentsOf: varLengthEncode(0))

        // Time signature meta event: FF 58 04 nn dd cc bb
        // nn = numerator, dd = denominator as power of 2, cc = MIDI clocks per metronome click, bb = 32nd notes per MIDI quarter
        let denominatorPow: UInt8 = UInt8(log2(Double(project.timeSignatureDenominator)))
        events.append(0xFF)
        events.append(0x58)
        events.append(0x04)
        events.append(UInt8(project.timeSignatureNumerator))
        events.append(denominatorPow)
        events.append(24)  // 24 MIDI clocks per metronome click
        events.append(8)   // 8 thirty-second notes per MIDI quarter note

        // Delta time 0
        events.append(contentsOf: varLengthEncode(0))

        // Key signature meta event: FF 59 02 sf mi
        // sf = number of sharps/flats (-7 to 7), mi = 0 major, 1 minor
        let sf = Int8(project.keySignature.accidentalCount)
        events.append(0xFF)
        events.append(0x59)
        events.append(0x02)
        events.append(UInt8(bitPattern: sf))
        events.append(project.keySignature.isMinor ? 0x01 : 0x00)

        // Track name meta event
        let trackName = Array("\(project.title) - Tempo Track".utf8)
        events.append(contentsOf: varLengthEncode(0))
        events.append(0xFF)
        events.append(0x03)
        events.append(contentsOf: varLengthEncode(UInt32(trackName.count)))
        events.append(contentsOf: trackName)

        // End of Track
        events.append(contentsOf: varLengthEncode(0))
        events.append(0xFF)
        events.append(0x2F)
        events.append(0x00)

        return trackChunk(events: events)
    }

    // MARK: - Part Track

    /// Builds one MIDI track for a single Part.
    private func partTrack(part: Part, channel: UInt8, project: VocalScoreProject) -> [UInt8] {
        var events: [MIDIEvent] = []

        // Track name
        events.append(MIDIEvent(tick: 0, bytes: metaTextEvent(type: 0x03, text: part.name)))

        // Program change for instrument
        let programChange: [UInt8] = [0xC0 | channel, UInt8(part.instrument.midiProgram)]
        events.append(MIDIEvent(tick: 0, bytes: programChange))

        // Volume (CC 7) and Pan (CC 10)
        let volumeCC: UInt8 = UInt8(min(127, Int(part.volume * 127)))
        let panCC: UInt8 = UInt8(min(127, Int((part.pan + 1.0) * 63.5)))
        events.append(MIDIEvent(tick: 0, bytes: [0xB0 | channel, 0x07, volumeCC]))
        events.append(MIDIEvent(tick: 0, bytes: [0xB0 | channel, 0x0A, panCC]))

        // Note On / Note Off events
        for note in part.sortedNotes {
            guard !note.isRest && note.pitch >= 0 else { continue }

            let startTick = beatToTick(note.startBeat - 1.0) // 0-indexed
            let durationTicks = beatToTick(note.duration.beats)
            let endTick = startTick + durationTicks

            let velocity = part.isMuted ? 0 : UInt8(min(127, note.velocity))

            // Note On
            events.append(MIDIEvent(
                tick: startTick,
                bytes: [0x90 | channel, UInt8(note.pitch), velocity]
            ))

            // Note Off
            events.append(MIDIEvent(
                tick: endTick,
                bytes: [0x80 | channel, UInt8(note.pitch), 0x40]
            ))
        }

        // Sort events by tick
        events.sort { $0.tick < $1.tick }

        // Convert to delta-time encoded bytes
        var trackBytes: [UInt8] = []
        var currentTick: UInt32 = 0

        for event in events {
            let delta = event.tick >= currentTick ? event.tick - currentTick : 0
            trackBytes.append(contentsOf: varLengthEncode(delta))
            trackBytes.append(contentsOf: event.bytes)
            currentTick = event.tick
        }

        // End of Track
        trackBytes.append(contentsOf: varLengthEncode(0))
        trackBytes.append(0xFF)
        trackBytes.append(0x2F)
        trackBytes.append(0x00)

        return trackChunk(events: trackBytes)
    }

    // MARK: - Track Chunk Wrapper

    private func trackChunk(events: [UInt8]) -> [UInt8] {
        var chunk: [UInt8] = []
        chunk.append(contentsOf: Array("MTrk".utf8))
        chunk.append(contentsOf: uint32ToBytes(UInt32(events.count)))
        chunk.append(contentsOf: events)
        return chunk
    }

    // MARK: - Encoding Helpers

    /// Encode value as MIDI variable-length quantity.
    private func varLengthEncode(_ value: UInt32) -> [UInt8] {
        if value == 0 { return [0x00] }

        var bytes: [UInt8] = []
        var v = value
        bytes.insert(UInt8(v & 0x7F), at: 0)
        v >>= 7

        while v > 0 {
            bytes.insert(UInt8((v & 0x7F) | 0x80), at: 0)
            v >>= 7
        }

        return bytes
    }

    private func uint16ToBytes(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    private func uint24ToBytes(_ value: UInt32) -> [UInt8] {
        [UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private func uint32ToBytes(_ value: UInt32) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
         UInt8((value >> 8) & 0xFF),  UInt8(value & 0xFF)]
    }

    /// Convert beat position (0-indexed) to MIDI tick count.
    private func beatToTick(_ beats: Double) -> UInt32 {
        UInt32(max(0, beats * Double(ticksPerQuarterNote)))
    }

    private func metaTextEvent(type: UInt8, text: String) -> [UInt8] {
        let textBytes = Array(text.utf8)
        var event: [UInt8] = [0xFF, type]
        event.append(contentsOf: varLengthEncode(UInt32(textBytes.count)))
        event.append(contentsOf: textBytes)
        return event
    }
}

// MARK: - MIDIEvent

/// Internal representation of a single MIDI event with an absolute tick position.
private struct MIDIEvent {
    let tick: UInt32
    let bytes: [UInt8]
}
