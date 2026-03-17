# VocalScore Pro

**Transform your voice into orchestral music scores.**

VocalScore Pro is a native iOS app that lets musicians, composers, and music students sing or hum a melody and automatically transcribe it into a full orchestral score with pitch detection, rhythm quantization, and multi-instrument support.

---

## Features (Phase 1 MVP)

| Feature | Status |
|---------|--------|
| Voice recording (AVAudioEngine) | ✅ |
| Real-time pitch detection (YIN algorithm) | ✅ |
| Rhythm quantization to musical grid | ✅ |
| 27 orchestral instruments (5 families) | ✅ |
| Canvas-based score editor | ✅ |
| Note editing (pitch, duration, articulation, dynamic) | ✅ |
| Undo/redo (100 steps) | ✅ |
| Multi-part mixer with volume/pan/solo/mute | ✅ |
| MusicXML 4.0 export | ✅ |
| Standard MIDI Type 1 export | ✅ |
| Project management with JSON persistence | ✅ |
| Range validation with flagging | ✅ |
| Onboarding flow | ✅ |
| AI Orchestration Assistant | 🔜 Phase 2 |
| PDF score export | 🔜 Phase 2 |
| Audio bounce/render | 🔜 Phase 2 |

---

## Requirements

- **iOS 17.0+**
- **iPhone** (landscape and portrait supported)
- **Xcode 15.0+**
- **Swift 5.9**
- Microphone permission (required for recording)

---

## Setup

1. Clone or download the project
2. Open `Composer.xcodeproj` in Xcode 15 or later
3. Select your development team in **Signing & Capabilities**
4. Set the bundle identifier to something unique if needed (`com.cognitivegroup.vocalscorepro`)
5. Build and run on a physical device or simulator (note: microphone recording requires a real device for best results)

---

## Architecture

The project follows a clean MVVM architecture with clear separation of concerns:

```
Composer/
├── Models/              # Codable data models (VocalScoreProject, Part, Note, Instrument)
├── Audio/               # AVAudioEngine wrappers (recording, pitch detection, playback)
├── Score/               # Export engines (MusicXML, MIDI) + score renderer
├── ViewModels/          # ObservableObject state managers
└── Views/               # SwiftUI views + Canvas components
```

### Key Design Decisions

**Pitch Detection**: Uses a YIN-inspired autocorrelation algorithm implemented directly in Swift (no CoreML dependency). Processes 44.1 kHz audio buffers on a background queue and publishes results to the main thread using `@MainActor`.

**Score Rendering**: Both `ScoreRenderer` and `StaffView` use SwiftUI's `Canvas` API for 60fps drawing of staff lines, note heads, stems, beams, ledger lines, and articulation marks — no UIKit required.

**Rhythm Quantization**: `RhythmQuantizer` converts raw pitch event timestamps into beat-aligned `Note` objects using configurable grid resolution (1/4 to 1/32, including triplets).

**MIDI Export**: Hand-crafted Standard MIDI File Type 1 binary encoder — no third-party library needed. Encodes variable-length quantities, tempo/time signature meta events, and per-track note events.

**MusicXML Export**: Generates valid MusicXML 4.0 markup with full part-list, measure attributes, note pitch/duration/dynamics, articulations, and transpositions.

**Persistence**: Projects are serialized as pretty-printed JSON to the app's Documents directory using `JSONEncoder`/`JSONDecoder` with `.iso8601` date strategy.

---

## Instrument Catalog (27 instruments)

| Family | Instruments |
|--------|-------------|
| **Strings** | Violin I, Violin II, Viola, Cello, Double Bass |
| **Woodwinds** | Flute, Oboe, Clarinet (Bb), Bassoon, Alto Sax, Tenor Sax |
| **Brass** | French Horn (F), Trumpet (Bb), Trombone, Tuba |
| **Percussion** | Timpani, Xylophone, Glockenspiel, Harp, Marimba, Vibraphone |
| **Keyboard** | Piano, Harpsichord, Celesta, Pipe Organ, Electric Piano, Accordion |

All instruments include:
- MIDI program number (General MIDI)
- Written range (lowest/highest MIDI note)
- Transposition interval (concert pitch offset)
- Clef assignment
- Out-of-range note flagging

---

## Recording Workflow

1. **Choose instrument** — InstrumentPickerView shows grouped instrument families with range graphics
2. **Record** — RecordingView shows real-time waveform and pitch meter while you sing
3. **Process** — RhythmQuantizer converts the pitch timeline to grid-aligned notes
4. **Review** — See detected notes as chips; audition via playback
5. **Accept or Discard** — Accepted take becomes a Part in your project

---

## Score Editor

- **Tap** a note to select it (blue highlight)
- **Drag up/down** to transpose selected note by semitone
- **Bottom toolbar** switches between: Note Duration | Articulation | Dynamic
- **Undo/Redo** — up to 100 steps
- **Range validation** — flagged notes shown in orange with reason popover
- **Playback** — play all or play selection via AVAudioUnitSampler

---

## Export

- **MusicXML 4.0** — compatible with Sibelius, Finale, MuseScore, Dorico, and any MusicXML-aware notation software
- **Standard MIDI Type 1** — compatible with all DAWs (Logic Pro, Ableton, Pro Tools, GarageBand, etc.)
- Files written to `Documents/Exports/` and shared via iOS share sheet

---

## Phase 2 Roadmap

- **AI Orchestration Assistant** — automatic harmonization, chord generation, orchestral arrangement suggestions
- **PDF Score Export** — formatted printable scores
- **Audio Bounce** — render the project to a stereo audio file
- **Collaborative Editing** — share projects via CloudKit
- **Soundfont Management** — load custom SF2/SF3 soundfonts
- **Notation Plugins** — send to external apps via AudioBus/AUv3

---

## License

Copyright © 2026 CognitiveGroup. All rights reserved.
