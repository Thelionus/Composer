import SwiftUI

// MARK: - InstrumentPickerView

struct InstrumentPickerView: View {
    let onSelect: (Instrument) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedInstrument: Instrument? = nil
    @State private var navigateToRecording = false

    // Whether to skip the recording step and just select
    var skipRecording: Bool = false

    var filteredFamilies: [InstrumentFamily] {
        InstrumentFamily.allCases.filter { family in
            filteredInstruments(for: family).isEmpty == false
        }
    }

    func filteredInstruments(for family: InstrumentFamily) -> [Instrument] {
        let byFamily = Instrument.catalog.filter { $0.family == family }
        if searchText.isEmpty { return byFamily }
        return byFamily.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredFamilies, id: \.self) { family in
                    Section(family.rawValue) {
                        ForEach(filteredInstruments(for: family)) { instrument in
                            InstrumentRowView(
                                instrument: instrument,
                                isSelected: selectedInstrument?.id == instrument.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedInstrument = instrument
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search instruments")
            .navigationTitle("Choose Instrument")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Select") {
                        if let instrument = selectedInstrument {
                            onSelect(instrument)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedInstrument == nil)
                }
            }
        }
    }
}

// MARK: - InstrumentRowView

struct InstrumentRowView: View {
    let instrument: Instrument
    let isSelected: Bool

    private var familyColor: Color {
        Color(hex: instrument.family.color) ?? .purple
    }

    var body: some View {
        HStack(spacing: 14) {
            // Family color icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(familyColor.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: instrument.icon)
                    .font(.system(size: 16))
                    .foregroundColor(familyColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(instrument.name)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? familyColor : .primary)

                HStack(spacing: 6) {
                    Text(instrument.clef.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // Mini range display
                    Text(instrument.rangeDisplay)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if instrument.isTransposing {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Transposing")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // Mini keyboard range graphic
            MiniKeyboardRangeView(
                lowestNote: instrument.lowestNote,
                highestNote: instrument.highestNote
            )
            .frame(width: 60, height: 22)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(familyColor)
                    .font(.system(size: 18))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? familyColor.opacity(0.05) : Color.clear)
        )
    }
}

// MARK: - MiniKeyboardRangeView

/// A tiny graphical representation of a piano keyboard showing an instrument's range.
struct MiniKeyboardRangeView: View {
    let lowestNote: Int
    let highestNote: Int

    private let totalKeys = 88  // Standard piano range A0–C8
    private let pianoLowest = 21 // A0 MIDI

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                drawMiniKeyboard(context: context, size: size)
            }
        }
    }

    private func drawMiniKeyboard(context: GraphicsContext, size: CGSize) {
        let totalWidth = size.width
        let keyWidth = totalWidth / CGFloat(totalKeys)

        // Draw all keys first (white)
        for key in 0..<totalKeys {
            let midi = pianoLowest + key
            let isBlack = isBlackKey(midi)
            if !isBlack {
                let xPos = whiteKeyIndex(midi) * keyWidth
                let inRange = midi >= lowestNote && midi <= highestNote
                let rect = CGRect(x: xPos, y: 0, width: keyWidth - 0.5, height: size.height)
                context.fill(Path(rect), with: .color(inRange ? .blue.opacity(0.6) : .gray.opacity(0.3)))
            }
        }

        // Draw black keys on top
        for key in 0..<totalKeys {
            let midi = pianoLowest + key
            if isBlackKey(midi) {
                let whiteIdx = whiteKeyIndex(midi - 1)
                let xPos = whiteIdx * keyWidth + keyWidth * 0.65
                let inRange = midi >= lowestNote && midi <= highestNote
                let rect = CGRect(x: xPos, y: 0, width: keyWidth * 0.7, height: size.height * 0.65)
                context.fill(Path(rect), with: .color(inRange ? .blue.opacity(0.8) : .black.opacity(0.6)))
            }
        }
    }

    private func isBlackKey(_ midi: Int) -> Bool {
        let pitchClass = midi % 12
        return [1, 3, 6, 8, 10].contains(pitchClass)
    }

    private func whiteKeyIndex(_ midi: Int) -> CGFloat {
        let notesPerOctave: [Int] = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6]
        let octave = (midi - pianoLowest) / 12
        let pitchClass = (midi - pianoLowest) % 12
        let whiteIdx = octave * 7 + notesPerOctave[max(0, pitchClass)]
        return CGFloat(whiteIdx)
    }
}
