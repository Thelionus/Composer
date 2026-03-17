import Foundation
import AVFoundation
import Combine

// MARK: - PlaybackEngine

/// AVAudioEngine-based playback engine using AVAudioUnitSampler for General MIDI
/// instrument synthesis. Supports multi-part playback with per-channel volume and pan.
@MainActor
final class PlaybackEngine: ObservableObject {

    // MARK: - Published Properties

    @Published var isPlaying: Bool = false
    @Published var currentBeat: Double = 1.0
    @Published var playbackError: String?

    // MARK: - Private State

    private let engine = AVAudioEngine()
    private var samplers: [Int: AVAudioUnitSampler] = [:]  // key: MIDI channel 0–15
    private var mixer: AVAudioMixerNode
    private var playbackTask: Task<Void, Never>?
    private var beatTimer: Timer?
    private var playbackStartTime: Date?
    private var playbackStartBeat: Double = 1.0

    // Tempo state
    private var currentTempo: Double = 120.0
    private var secondsPerBeat: Double { 60.0 / currentTempo }

    // MARK: - Initializer

    init() {
        self.mixer = engine.mainMixerNode

        setupEngine()
    }

    // MARK: - Engine Setup

    private func setupEngine() {
        do {
            try configureAudioSession()
        } catch {
            playbackError = "Audio session error: \(error.localizedDescription)"
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }

    private func sampler(forChannel channel: Int) -> AVAudioUnitSampler {
        if let existing = samplers[channel] { return existing }

        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: mixer, format: nil)
        samplers[channel] = sampler
        return sampler
    }

    private func startEngineIfNeeded() throws {
        guard !engine.isRunning else { return }
        try engine.start()
    }

    // MARK: - Public Playback API

    /// Play all parts of a project starting at a given beat.
    func play(
        parts: [Part],
        tempo: Double,
        startBeat: Double = 1.0,
        onBeatChanged: ((Double) -> Void)? = nil
    ) {
        stop()

        currentTempo = tempo
        playbackStartBeat = startBeat
        isPlaying = true
        currentBeat = startBeat
        playbackStartTime = Date()

        // Configure each part on its own MIDI channel (up to 16)
        for (channelIndex, part) in parts.prefix(16).enumerated() {
            let sampler = sampler(forChannel: channelIndex)
            sampler.volume = part.isMuted ? 0.0 : part.volume
            sampler.pan = part.pan

            // Set MIDI program for instrument
            sendProgramChange(
                channel: UInt8(channelIndex),
                program: UInt8(part.instrument.midiProgram),
                sampler: sampler
            )
        }

        do {
            try startEngineIfNeeded()
        } catch {
            playbackError = "Engine start failed: \(error.localizedDescription)"
            isPlaying = false
            return
        }

        // Schedule note events asynchronously
        playbackTask = Task { [weak self] in
            guard let self else { return }
            await self.schedulePlayback(parts: parts, tempo: tempo, startBeat: startBeat)
        }

        // Beat tracking timer
        beatTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying, let startTime = self.playbackStartTime else { return }
            let elapsed = Date().timeIntervalSince(startTime)
            let beatsElapsed = elapsed / self.secondsPerBeat
            let beat = self.playbackStartBeat + beatsElapsed
            Task { @MainActor in
                self.currentBeat = beat
                onBeatChanged?(beat)
            }
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        beatTimer?.invalidate()
        beatTimer = nil
        isPlaying = false
        playbackStartTime = nil

        // All notes off on all channels
        for (_, sampler) in samplers {
            for note in 0..<128 {
                sampler.stopNote(UInt8(note), onChannel: 0)
            }
        }
    }

    /// Play a single note for audition (e.g. from score editor).
    func playNote(
        midiNote: Int,
        velocity: Int,
        duration: TimeInterval,
        midiProgram: Int,
        channel: Int = 0
    ) {
        let s = sampler(forChannel: channel)
        sendProgramChange(channel: UInt8(channel), program: UInt8(midiProgram), sampler: s)

        do {
            try startEngineIfNeeded()
        } catch {
            return
        }

        s.startNote(UInt8(midiNote), withVelocity: UInt8(velocity), onChannel: UInt8(channel))

        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run {
                s.stopNote(UInt8(midiNote), onChannel: UInt8(channel))
            }
        }
    }

    /// Play a sequence of notes for a single part.
    func play(notes: [Note], instrument: Instrument, tempo: Double) {
        stop()
        currentTempo = tempo
        isPlaying = true
        playbackStartTime = Date()
        playbackStartBeat = notes.map { $0.startBeat }.min() ?? 1.0

        let channel = 0
        let sampler = sampler(forChannel: channel)
        sampler.volume = 1.0
        sampler.pan = 0.0
        sendProgramChange(channel: UInt8(channel), program: UInt8(instrument.midiProgram), sampler: sampler)

        do {
            try startEngineIfNeeded()
        } catch {
            isPlaying = false
            return
        }

        playbackTask = Task { [weak self] in
            guard let self else { return }
            let spb = 60.0 / tempo

            for note in notes.sorted(by: { $0.startBeat < $1.startBeat }) {
                guard !Task.isCancelled else { break }
                guard !note.isRest else { continue }

                // Wait until note's start time
                let noteBeat = note.startBeat
                let waitSeconds = (noteBeat - self.playbackStartBeat) * spb
                let waitNS = UInt64(max(0, waitSeconds) * 1_000_000_000)

                do {
                    try await Task.sleep(nanoseconds: waitNS)
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }

                let noteDuration = note.duration.seconds(atTempo: tempo)
                    * Double(note.articulation.durationMultiplier)

                let s = await MainActor.run { self.samplers[channel] }
                s?.startNote(UInt8(note.pitch), withVelocity: UInt8(note.velocity), onChannel: UInt8(channel))

                let stopDelay = UInt64(noteDuration * 1_000_000_000)
                try? await Task.sleep(nanoseconds: stopDelay)
                s?.stopNote(UInt8(note.pitch), onChannel: UInt8(channel))
            }

            await MainActor.run { self.isPlaying = false }
        }
    }

    /// Set volume for a specific part channel.
    func setVolume(_ volume: Float, forChannel channel: Int) {
        samplers[channel]?.volume = volume
    }

    /// Set pan for a specific part channel.
    func setPan(_ pan: Float, forChannel channel: Int) {
        samplers[channel]?.pan = pan
    }

    // MARK: - Private Scheduling

    private func schedulePlayback(parts: [Part], tempo: Double, startBeat: Double) async {
        let spb = 60.0 / tempo

        // Collect all note events across parts and sort by start time
        var events: [(beat: Double, midiNote: Int, velocity: Int, durationSecs: Double, channel: Int)] = []

        for (channelIndex, part) in parts.prefix(16).enumerated() {
            guard !part.isMuted else { continue }
            for note in part.notes {
                guard !note.isRest && note.pitch >= 0 && note.startBeat >= startBeat else { continue }
                let durationSec = note.duration.seconds(atTempo: tempo)
                    * Double(note.articulation.durationMultiplier)
                events.append((
                    beat: note.startBeat,
                    midiNote: note.pitch,
                    velocity: note.velocity,
                    durationSecs: durationSec,
                    channel: channelIndex
                ))
            }
        }

        events.sort { $0.beat < $1.beat }

        let referenceTime = Date()

        for event in events {
            guard !Task.isCancelled else { break }

            let targetTime = (event.beat - startBeat) * spb
            let elapsed = Date().timeIntervalSince(referenceTime)
            let delay = targetTime - elapsed

            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    break
                }
            }

            guard !Task.isCancelled else { break }

            let sampler = await MainActor.run { self.samplers[event.channel] }
            sampler?.startNote(
                UInt8(event.midiNote),
                withVelocity: UInt8(min(127, event.velocity)),
                onChannel: UInt8(event.channel)
            )

            // Schedule note off
            let stopDelay = UInt64(event.durationSecs * 1_000_000_000)
            Task {
                try? await Task.sleep(nanoseconds: stopDelay)
                let s = await MainActor.run { self.samplers[event.channel] }
                s?.stopNote(UInt8(event.midiNote), onChannel: UInt8(event.channel))
            }
        }

        await MainActor.run { self.isPlaying = false }
    }

    // MARK: - MIDI Helpers

    private func sendProgramChange(channel: UInt8, program: UInt8, sampler: AVAudioUnitSampler) {
        sampler.sendProgramChange(program, onChannel: channel)
    }
}
