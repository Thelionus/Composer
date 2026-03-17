import SwiftUI

// MARK: - StaffView

/// A Canvas-based musical staff renderer for displaying a subset of notes.
/// Renders clef, key signature, time signature, note heads, stems, and bar lines.
/// Suitable for use as a preview component; ScoreRenderer handles the full score editor.
struct StaffView: View {
    let notes: [Note]
    var clef: Clef = .treble
    var keySignature: KeySignature = .cMajor
    var timeSignature: (Int, Int) = (4, 4)
    var tempo: Double = 120
    var selectedNoteIDs: Set<UUID> = []
    var onNoteTapped: ((UUID) -> Void)? = nil

    private let layout = ScoreLayout(
        staffLineSpacing: 9,
        beatWidth: 52,
        leadingMargin: 72,
        staffTopPadding: 32
    )

    var body: some View {
        Canvas { context, size in
            renderStaff(context: context, size: size)
        }
        .background(Color.white)
        .cornerRadius(8)
        .onTapGesture { location in
            handleTap(at: location)
        }
    }

    // MARK: - Main Render

    private func renderStaff(context: GraphicsContext, size: CGSize) {
        // White background
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))

        // Staff lines
        for line in 0..<5 {
            let y = layout.staffLineY(line: line)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(.black.opacity(0.8)), lineWidth: 0.8)
        }

        // Clef symbol
        drawClefSymbol(context: context)

        // Key signature
        drawKeySignature(context: context)

        // Time signature
        drawTimeSignature(context: context)

        // Bar lines
        drawBarLines(context: context, width: size.width)

        // Notes
        for note in notes.sorted(by: { $0.startBeat < $1.startBeat }) {
            drawNote(context: context, note: note)
        }
    }

    // MARK: - Clef

    private func drawClefSymbol(context: GraphicsContext) {
        let topY = layout.staffLineY(line: 0)
        let bottomY = layout.staffLineY(line: 4)
        let height = bottomY - topY
        let sp = layout.staffLineSpacing

        var attribs = AttributeContainer()
        let clefChar: String
        let fontSize: CGFloat
        let yPos: CGFloat

        switch clef {
        case .treble:
            clefChar = "𝄞"
            fontSize = height * 1.05 + sp * 2
            yPos = topY + height * 0.38
        case .bass:
            clefChar = "𝄢"
            fontSize = height * 1.05
            yPos = topY + height * 0.5
        case .alto, .tenor:
            clefChar = "𝄡"
            fontSize = height * 1.05
            yPos = topY + height * 0.5
        }

        attribs.font = Font.system(size: fontSize, weight: .light)
        let text = AttributedString(clefChar, attributes: attribs)
        context.draw(
            Text(text).foregroundColor(.black),
            at: CGPoint(x: 14, y: yPos),
            anchor: .center
        )
    }

    // MARK: - Key Signature

    private func drawKeySignature(context: GraphicsContext) {
        let accCount = abs(keySignature.accidentalCount)
        guard accCount > 0 else { return }

        let isSharps = keySignature.usesSharps
        let symbol = isSharps ? "♯" : "♭"
        let sp = layout.staffLineSpacing

        let sharpYOffsets: [CGFloat] = [0.5, 2.5, 0, 2, 4, 1, 3]
        let flatYOffsets: [CGFloat] = [2, 0.5, 3, 1, 3.5, 2, 4]
        let offsets = isSharps ? sharpYOffsets : flatYOffsets

        for i in 0..<min(accCount, 7) {
            let x = 42 + CGFloat(i) * sp * 1.2
            let y = layout.staffTopPadding + offsets[i] * sp
            var attribs = AttributeContainer()
            attribs.font = Font.system(size: sp * 1.7)
            let text = AttributedString(symbol, attributes: attribs)
            context.draw(Text(text).foregroundColor(.black), at: CGPoint(x: x, y: y), anchor: .center)
        }
    }

    // MARK: - Time Signature

    private func drawTimeSignature(context: GraphicsContext) {
        let sp = layout.staffLineSpacing
        let accidentalWidth = CGFloat(abs(keySignature.accidentalCount)) * sp * 1.2
        let xPos = 46 + accidentalWidth

        for (num, lineIdx) in [(timeSignature.0, 1), (timeSignature.1, 3)] {
            let y = layout.staffLineY(line: lineIdx)
            var attribs = AttributeContainer()
            attribs.font = Font.system(size: sp * 2.0, weight: .bold).monospaced()
            let text = AttributedString("\(num)", attributes: attribs)
            context.draw(Text(text).foregroundColor(.black), at: CGPoint(x: xPos, y: y), anchor: .center)
        }
    }

    // MARK: - Bar Lines

    private func drawBarLines(context: GraphicsContext, width: CGFloat) {
        let topY = layout.staffLineY(line: 0)
        let bottomY = layout.staffLineY(line: 4)
        let beatsPerBar = Double(timeSignature.0)
        let lastBeat = notes.map { $0.endBeat }.max() ?? 5.0
        let barCount = Int(ceil(lastBeat / beatsPerBar)) + 1

        for bar in 1..<barCount {
            let beat = Double(bar) * beatsPerBar + 1.0
            let x = layout.xPosition(forBeat: beat)
            guard x < width else { break }

            var path = Path()
            path.move(to: CGPoint(x: x, y: topY))
            path.addLine(to: CGPoint(x: x, y: bottomY))
            context.stroke(path, with: .color(.black.opacity(0.7)), lineWidth: 0.8)
        }
    }

    // MARK: - Note Rendering

    private func drawNote(context: GraphicsContext, note: Note) {
        if note.isRest || note.pitch < 0 {
            drawRestSymbol(context: context, note: note)
            return
        }

        let x = layout.xPosition(forBeat: note.startBeat)
        let y = layout.yPosition(forMIDINote: note.pitch, clef: clef)
        let isSelected = selectedNoteIDs.contains(note.id)
        let color = noteColor(note, isSelected: isSelected)
        let sp = layout.staffLineSpacing

        // Ledger lines
        drawLedgerLinesIfNeeded(context: context, midiNote: note.pitch, x: x, y: y)

        // Note head
        let headW = layout.noteHeadWidth
        let headH = layout.noteHeadHeight
        let headRect = CGRect(x: x - headW / 2, y: y - headH / 2, width: headW, height: headH)
        let ellipse = Path(ellipseIn: headRect)

        switch note.duration {
        case .whole:
            context.stroke(ellipse, with: .color(color), lineWidth: 1.5)
        case .half, .dottedHalf:
            context.stroke(ellipse, with: .color(color), lineWidth: 1.8)
        default:
            context.fill(ellipse, with: .color(color))
        }

        // Stem
        if note.duration != .whole {
            let midStaffY = layout.staffLineY(line: 2)
            let stemUp = y >= midStaffY
            let stemX = x + headW * 0.4
            let stemStart = stemUp ? y - headH / 2 : y + headH / 2
            let stemEnd = stemUp ? stemStart - layout.stemLength : stemStart + layout.stemLength

            var stemPath = Path()
            stemPath.move(to: CGPoint(x: stemX, y: stemStart))
            stemPath.addLine(to: CGPoint(x: stemX, y: stemEnd))
            context.stroke(stemPath, with: .color(color), lineWidth: 1.0)

            // Flags
            let flagCount: Int
            switch note.duration {
            case .eighth, .dottedEighth, .tripletEighth: flagCount = 1
            case .sixteenth, .tripletSixteenth:           flagCount = 2
            case .thirtySecond:                           flagCount = 3
            default:                                      flagCount = 0
            }

            for flagIdx in 0..<flagCount {
                let flagY = stemUp
                    ? stemEnd + CGFloat(flagIdx) * sp * 0.8
                    : stemEnd - CGFloat(flagIdx) * sp * 0.8
                var flagPath = Path()
                flagPath.move(to: CGPoint(x: stemX, y: flagY))
                flagPath.addCurve(
                    to: CGPoint(x: stemX + sp * 1.2, y: flagY + (stemUp ? sp * 1.2 : -sp * 1.2)),
                    control1: CGPoint(x: stemX + sp * 0.8, y: flagY),
                    control2: CGPoint(x: stemX + sp * 1.2, y: flagY + (stemUp ? sp * 0.6 : -sp * 0.6))
                )
                context.stroke(flagPath, with: .color(color), lineWidth: 1.0)
            }
        }

        // Dot for dotted durations
        if note.duration.isDotted {
            let dot = Path(ellipseIn: CGRect(x: x + headW * 0.6, y: y - 3, width: 4, height: 4))
            context.fill(dot, with: .color(color))
        }

        // Articulation symbol
        if note.articulation != .normal {
            let artY = y - sp * 2.2
            var attribs = AttributeContainer()
            attribs.font = Font.system(size: sp * 1.3, weight: .bold)
            let sym: String
            switch note.articulation {
            case .staccato: sym = "·"
            case .accent:   sym = ">"
            case .tenuto:   sym = "—"
            default:        sym = ""
            }
            if !sym.isEmpty {
                let text = AttributedString(sym, attributes: attribs)
                context.draw(Text(text).foregroundColor(.black), at: CGPoint(x: x, y: artY), anchor: .center)
            }
        }
    }

    private func drawRestSymbol(context: GraphicsContext, note: Note) {
        let x = layout.xPosition(forBeat: note.startBeat)
        let midY = layout.staffLineY(line: 2)
        let sp = layout.staffLineSpacing

        let symbol: String
        switch note.duration {
        case .whole:                      symbol = "𝄻"
        case .half, .dottedHalf:          symbol = "𝄼"
        case .quarter, .dottedQuarter:    symbol = "𝄽"
        case .eighth, .dottedEighth:      symbol = "𝄾"
        case .sixteenth:                  symbol = "𝄿"
        default:                          symbol = "𝄽"
        }

        var attribs = AttributeContainer()
        attribs.font = Font.system(size: sp * 2.0)
        let text = AttributedString(symbol, attributes: attribs)
        context.draw(Text(text).foregroundColor(.gray), at: CGPoint(x: x, y: midY), anchor: .center)
    }

    private func drawLedgerLinesIfNeeded(context: GraphicsContext, midiNote: Int, x: CGFloat, y: CGFloat) {
        let topY = layout.staffLineY(line: 0)
        let bottomY = layout.staffLineY(line: 4)
        let sp = layout.staffLineSpacing
        let lw = layout.noteHeadWidth * 1.6
        let lx = x - lw / 2

        if y < topY - sp * 0.5 {
            var cur = topY - sp
            while cur >= y - sp * 0.1 {
                var p = Path()
                p.move(to: CGPoint(x: lx, y: cur))
                p.addLine(to: CGPoint(x: lx + lw, y: cur))
                context.stroke(p, with: .color(.black), lineWidth: 0.8)
                cur -= sp
            }
        }

        if y > bottomY + sp * 0.5 {
            var cur = bottomY + sp
            while cur <= y + sp * 0.1 {
                var p = Path()
                p.move(to: CGPoint(x: lx, y: cur))
                p.addLine(to: CGPoint(x: lx + lw, y: cur))
                context.stroke(p, with: .color(.black), lineWidth: 0.8)
                cur += sp
            }
        }
    }

    private func noteColor(_ note: Note, isSelected: Bool) -> Color {
        if isSelected { return .blue }
        if note.isFlagged { return .orange }
        if note.confidence < 0.6 { return .yellow.opacity(0.8) }
        return .black
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint) {
        let tolerance: CGFloat = layout.staffLineSpacing * 1.5
        for note in notes {
            let noteX = layout.xPosition(forBeat: note.startBeat)
            let noteY = layout.yPosition(forMIDINote: note.pitch, clef: clef)
            let dist = sqrt(pow(noteX - location.x, 2) + pow(noteY - location.y, 2))
            if dist < tolerance {
                onNoteTapped?(note.id)
                return
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleNotes: [Note] = [
        Note(pitch: 60, duration: .quarter, startBeat: 1.0),
        Note(pitch: 64, duration: .eighth, startBeat: 2.0),
        Note(pitch: 67, duration: .quarter, startBeat: 2.5),
        Note(pitch: 72, duration: .half, startBeat: 3.0),
        Note(pitch: -1, duration: .quarter, startBeat: 5.0),
        Note(pitch: 55, duration: .quarter, startBeat: 6.0, isFlagged: true, flagReason: "Out of range"),
    ]

    StaffView(
        notes: sampleNotes,
        clef: .treble,
        keySignature: .gMajor,
        timeSignature: (4, 4)
    )
    .frame(height: 120)
    .padding()
}
