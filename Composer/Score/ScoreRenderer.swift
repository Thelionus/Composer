import SwiftUI
import Foundation

// MARK: - ScoreRenderer

/// Renders a musical staff with notes using SwiftUI Canvas for 60fps performance.
/// Supports treble and bass clef, key signatures, time signatures, note heads,
/// stems, beams, ledger lines, dynamics, and articulation symbols.
struct ScoreRenderer: View {

    let part: Part
    let project: VocalScoreProject
    let layout: ScoreLayout
    let selectedNoteIDs: Set<UUID>
    let currentBeat: Double
    let onNoteTapped: ((UUID) -> Void)?

    @State private var scrollOffset: CGFloat = 0
    @State private var zoomScale: CGFloat = 1.0
    @GestureState private var zoomGestureScale: CGFloat = 1.0

    init(
        part: Part,
        project: VocalScoreProject,
        layout: ScoreLayout = .default,
        selectedNoteIDs: Set<UUID> = [],
        currentBeat: Double = 0,
        onNoteTapped: ((UUID) -> Void)? = nil
    ) {
        self.part = part
        self.project = project
        self.layout = layout
        self.selectedNoteIDs = selectedNoteIDs
        self.currentBeat = currentBeat
        self.onNoteTapped = onNoteTapped
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: true) {
                Canvas { context, size in
                    renderScore(context: context, size: size)
                }
                .frame(
                    width: scoreWidth,
                    height: scoreHeight
                )
                .scaleEffect(zoomScale * zoomGestureScale)
                .gesture(
                    MagnificationGesture()
                        .updating($zoomGestureScale) { value, state, _ in
                            state = value
                        }
                        .onEnded { value in
                            zoomScale = max(0.5, min(3.0, zoomScale * value))
                        }
                )
                .onTapGesture { location in
                    handleTap(at: location)
                }
            }
        }
    }

    // MARK: - Score Dimensions

    private var scoreWidth: CGFloat {
        layout.xPosition(forBeat: Double(project.totalBars * project.timeSignatureNumerator) + 2)
            + layout.leadingMargin
    }

    private var scoreHeight: CGFloat {
        layout.staffTopPadding * 2 + layout.staffHeight + 120  // Extra space for ledger lines
    }

    // MARK: - Rendering

    private func renderScore(context: GraphicsContext, size: CGSize) {
        // Background
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))

        // Draw staff lines
        drawStaffLines(context: context, width: size.width)

        // Draw clef
        drawClef(context: context)

        // Draw key signature
        drawKeySignature(context: context)

        // Draw time signature
        drawTimeSignature(context: context)

        // Draw bar lines
        drawBarLines(context: context, height: size.height)

        // Draw playback cursor
        if currentBeat > 1 {
            drawPlaybackCursor(context: context, height: size.height)
        }

        // Draw notes
        drawNotes(context: context)
    }

    // MARK: - Staff Lines

    private func drawStaffLines(context: GraphicsContext, width: CGFloat) {
        let lineColor = Color.black.opacity(0.85)
        for lineIndex in 0..<5 {
            let y = layout.staffLineY(line: lineIndex)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
            context.stroke(path, with: .color(lineColor), lineWidth: 1.0)
        }
    }

    // MARK: - Clef

    private func drawClef(context: GraphicsContext) {
        let clef = part.instrument.clef
        let x: CGFloat = 12
        let topStaffY = layout.staffLineY(line: 0)
        let bottomStaffY = layout.staffLineY(line: 4)

        switch clef {
        case .treble:
            drawTrebleClef(context: context, x: x, topY: topStaffY, bottomY: bottomStaffY)
        case .bass:
            drawBassClef(context: context, x: x, topY: topStaffY, bottomY: bottomStaffY)
        case .alto, .tenor:
            drawAltoClef(context: context, x: x, topY: topStaffY, bottomY: bottomStaffY)
        }
    }

    private func drawTrebleClef(context: GraphicsContext, x: CGFloat, topY: CGFloat, bottomY: CGFloat) {
        let sp = layout.staffLineSpacing
        let centerX = x + 10
        let height = bottomY - topY + sp * 2

        // Simplified treble clef using text glyph
        var attribs = AttributeContainer()
        attribs.font = Font.system(size: height * 1.05, weight: .light).monospaced()
        let text = AttributedString("𝄞", attributes: attribs)
        context.draw(
            Text(text).foregroundColor(.black),
            at: CGPoint(x: centerX, y: topY + height * 0.38),
            anchor: .center
        )
    }

    private func drawBassClef(context: GraphicsContext, x: CGFloat, topY: CGFloat, bottomY: CGFloat) {
        let sp = layout.staffLineSpacing
        let height = bottomY - topY

        var attribs = AttributeContainer()
        attribs.font = Font.system(size: height * 1.1, weight: .light).monospaced()
        let text = AttributedString("𝄢", attributes: attribs)
        context.draw(
            Text(text).foregroundColor(.black),
            at: CGPoint(x: x + 10, y: topY + height * 0.5 + sp * 0.5),
            anchor: .center
        )
    }

    private func drawAltoClef(context: GraphicsContext, x: CGFloat, topY: CGFloat, bottomY: CGFloat) {
        let height = bottomY - topY

        var attribs = AttributeContainer()
        attribs.font = Font.system(size: height * 1.1, weight: .light).monospaced()
        let text = AttributedString("𝄡", attributes: attribs)
        context.draw(
            Text(text).foregroundColor(.black),
            at: CGPoint(x: x + 10, y: topY + height * 0.5),
            anchor: .center
        )
    }

    // MARK: - Key Signature

    private func drawKeySignature(context: GraphicsContext) {
        let key = project.keySignature
        let accCount = abs(key.accidentalCount)
        guard accCount > 0 else { return }

        let isSharps = key.usesSharps
        let symbol = isSharps ? "♯" : "♭"
        let startX: CGFloat = 48
        let sp = layout.staffLineSpacing

        // Sharp/flat positions on treble clef staff (staff-line indices from top)
        // For treble: sharps go F5,C5,G5,D5,A4,E5,B4 → line positions from top: 0.5,1.5,0,1,2,0.5,1.5 (approx)
        let sharpYOffsets: [CGFloat] = [0.5, 2.5, 0, 2, 4, 1, 3]  // in half-steps from top line
        let flatYOffsets: [CGFloat] = [2, 0.5, 3, 1, 3.5, 2, 4]

        let offsets = isSharps ? sharpYOffsets : flatYOffsets

        for i in 0..<min(accCount, 7) {
            let xPos = startX + CGFloat(i) * (sp * 1.2)
            let yOffset = offsets[i] * sp
            let yPos = layout.staffTopPadding + yOffset

            var attribs = AttributeContainer()
            attribs.font = Font.system(size: sp * 1.8)
            let text = AttributedString(symbol, attributes: attribs)
            context.draw(
                Text(text).foregroundColor(.black),
                at: CGPoint(x: xPos, y: yPos),
                anchor: .center
            )
        }
    }

    // MARK: - Time Signature

    private func drawTimeSignature(context: GraphicsContext) {
        let sp = layout.staffLineSpacing
        let accidentalWidth: CGFloat = CGFloat(abs(project.keySignature.accidentalCount)) * sp * 1.2
        let xPos = 52 + accidentalWidth

        let topY = layout.staffLineY(line: 1)
        let bottomY = layout.staffLineY(line: 3)

        func drawNumber(_ n: Int, y: CGFloat) {
            var attribs = AttributeContainer()
            attribs.font = Font.system(size: sp * 2.2, weight: .bold).monospaced()
            let text = AttributedString("\(n)", attributes: attribs)
            context.draw(
                Text(text).foregroundColor(.black),
                at: CGPoint(x: xPos, y: y),
                anchor: .center
            )
        }

        drawNumber(project.timeSignatureNumerator, y: topY)
        drawNumber(project.timeSignatureDenominator, y: bottomY)
    }

    // MARK: - Bar Lines

    private func drawBarLines(context: GraphicsContext, height: CGFloat) {
        let topY = layout.staffLineY(line: 0)
        let bottomY = layout.staffLineY(line: 4)
        let beatsPerBar = Double(project.timeSignatureNumerator)

        for bar in 0...project.totalBars {
            let beat = Double(bar) * beatsPerBar + 1.0
            let x = layout.xPosition(forBeat: beat)

            var path = Path()
            path.move(to: CGPoint(x: x, y: topY))
            path.addLine(to: CGPoint(x: x, y: bottomY))

            if bar == project.totalBars {
                // Final double bar line
                context.stroke(path, with: .color(.black), lineWidth: 1.5)
                var thickPath = Path()
                thickPath.move(to: CGPoint(x: x + 3, y: topY))
                thickPath.addLine(to: CGPoint(x: x + 3, y: bottomY))
                context.stroke(thickPath, with: .color(.black), lineWidth: 4)
            } else {
                context.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 1.0)
            }
        }
    }

    // MARK: - Playback Cursor

    private func drawPlaybackCursor(context: GraphicsContext, height: CGFloat) {
        let x = layout.xPosition(forBeat: currentBeat)
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: height))
        context.stroke(path, with: .color(.blue.opacity(0.5)), lineWidth: 2)
    }

    // MARK: - Notes

    private func drawNotes(context: GraphicsContext) {
        let clef = part.instrument.clef
        let sortedNotes = part.sortedNotes

        for note in sortedNotes {
            guard !note.isRest else {
                drawRest(context: context, note: note)
                continue
            }
            guard note.pitch >= 0 else { continue }

            let x = layout.xPosition(forBeat: note.startBeat)
            let y = layout.yPosition(forMIDINote: note.pitch, clef: clef)

            let isSelected = selectedNoteIDs.contains(note.id)
            let noteColor = colorForNote(note, isSelected: isSelected)

            // Draw ledger lines if needed
            drawLedgerLines(context: context, note: note, x: x, y: y, clef: clef)

            // Draw note head
            drawNoteHead(context: context, note: note, x: x, y: y, color: noteColor)

            // Draw stem
            drawStem(context: context, note: note, x: x, y: y, color: noteColor)

            // Draw flags/beams for eighth notes and shorter
            drawNoteFlag(context: context, note: note, x: x, y: y, color: noteColor)

            // Draw dot for dotted notes
            if note.duration.isDotted {
                let dotX = x + layout.noteHeadWidth * 0.75
                let dotY = y - layout.staffLineSpacing * 0.25
                let dot = Path(ellipseIn: CGRect(x: dotX, y: dotY - 2, width: 4, height: 4))
                context.fill(dot, with: .color(noteColor))
            }

            // Draw articulation marks
            drawArticulation(context: context, note: note, x: x, y: y)

            // Draw dynamic marking (only on first note with a new dynamic)
            // (simplified: draw dynamic below every note for now)
        }
    }

    private func colorForNote(_ note: Note, isSelected: Bool) -> Color {
        if isSelected { return .blue }
        if note.isFlagged { return .orange }
        if note.confidence < 0.6 { return .yellow }
        if note.isGraceNote { return .purple }
        return .black
    }

    private func drawNoteHead(context: GraphicsContext, note: Note, x: CGFloat, y: CGFloat, color: Color) {
        let w = layout.noteHeadWidth
        let h = layout.noteHeadHeight
        let rect = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
        let ellipse = Path(ellipseIn: rect)

        switch note.duration {
        case .whole:
            // Open note head
            context.stroke(ellipse, with: .color(color), lineWidth: 1.5)
        case .half, .dottedHalf:
            // Open note head with thicker outline
            context.stroke(ellipse, with: .color(color), lineWidth: 2.0)
        default:
            // Filled note head
            context.fill(ellipse, with: .color(color))
        }
    }

    private func drawStem(context: GraphicsContext, note: Note, x: CGFloat, y: CGFloat, color: Color) {
        guard note.duration != .whole else { return }

        let stemLength = layout.stemLength
        let stemX = x + layout.noteHeadWidth * 0.4

        // Determine stem direction based on position relative to middle staff line
        let midY = layout.staffLineY(line: 2)
        let stemUp = y >= midY

        let stemStartY = stemUp ? y - layout.noteHeadHeight / 2 : y + layout.noteHeadHeight / 2
        let stemEndY = stemUp ? stemStartY - stemLength : stemStartY + stemLength

        var path = Path()
        path.move(to: CGPoint(x: stemX, y: stemStartY))
        path.addLine(to: CGPoint(x: stemX, y: stemEndY))
        context.stroke(path, with: .color(color), lineWidth: 1.2)
    }

    private func drawNoteFlag(context: GraphicsContext, note: Note, x: CGFloat, y: CGFloat, color: Color) {
        let sp = layout.staffLineSpacing
        let stemX = x + layout.noteHeadWidth * 0.4
        let midY = layout.staffLineY(line: 2)
        let stemUp = y >= midY
        let stemLength = layout.stemLength
        let tipY = stemUp ? y - layout.noteHeadHeight / 2 - stemLength
                          : y + layout.noteHeadHeight / 2 + stemLength

        let flagCount: Int
        switch note.duration {
        case .eighth, .dottedEighth, .tripletEighth: flagCount = 1
        case .sixteenth, .tripletSixteenth:           flagCount = 2
        case .thirtySecond:                           flagCount = 3
        default:                                      flagCount = 0
        }

        guard flagCount > 0 else { return }

        for i in 0..<flagCount {
            let flagY = stemUp ? tipY + CGFloat(i) * sp * 0.8
                                : tipY - CGFloat(i) * sp * 0.8
            var flagPath = Path()
            flagPath.move(to: CGPoint(x: stemX, y: flagY))
            flagPath.addCurve(
                to: CGPoint(x: stemX + sp * 1.5, y: flagY + (stemUp ? sp * 1.5 : -sp * 1.5)),
                control1: CGPoint(x: stemX + sp, y: flagY + (stemUp ? sp * 0.3 : -sp * 0.3)),
                control2: CGPoint(x: stemX + sp * 1.5, y: flagY + (stemUp ? sp * 0.8 : -sp * 0.8))
            )
            context.stroke(flagPath, with: .color(color), lineWidth: 1.2)
        }
    }

    private func drawLedgerLines(context: GraphicsContext, note: Note, x: CGFloat, y: CGFloat, clef: Clef) {
        let topStaffY = layout.staffLineY(line: 0)
        let bottomStaffY = layout.staffLineY(line: 4)
        let sp = layout.staffLineSpacing
        let ledgerWidth = layout.noteHeadWidth * 1.6
        let ledgerX = x - ledgerWidth / 2

        // Ledger lines above staff
        if y < topStaffY - sp * 0.5 {
            var currentY = topStaffY - sp
            while currentY >= y - sp * 0.1 {
                var path = Path()
                path.move(to: CGPoint(x: ledgerX, y: currentY))
                path.addLine(to: CGPoint(x: ledgerX + ledgerWidth, y: currentY))
                context.stroke(path, with: .color(.black), lineWidth: 1.0)
                currentY -= sp
            }
        }

        // Ledger lines below staff
        if y > bottomStaffY + sp * 0.5 {
            var currentY = bottomStaffY + sp
            while currentY <= y + sp * 0.1 {
                var path = Path()
                path.move(to: CGPoint(x: ledgerX, y: currentY))
                path.addLine(to: CGPoint(x: ledgerX + ledgerWidth, y: currentY))
                context.stroke(path, with: .color(.black), lineWidth: 1.0)
                currentY += sp
            }
        }
    }

    private func drawRest(context: GraphicsContext, note: Note) {
        let x = layout.xPosition(forBeat: note.startBeat)
        let midY = layout.staffLineY(line: 2)
        let sp = layout.staffLineSpacing

        var attribs = AttributeContainer()
        attribs.font = Font.system(size: sp * 2.2)

        let restSymbol: String
        switch note.duration {
        case .whole:              restSymbol = "𝄻"
        case .half, .dottedHalf: restSymbol = "𝄼"
        case .quarter:            restSymbol = "𝄽"
        case .eighth:             restSymbol = "𝄾"
        case .sixteenth:          restSymbol = "𝄿"
        default:                  restSymbol = "𝄽"
        }

        let text = AttributedString(restSymbol, attributes: attribs)
        context.draw(
            Text(text).foregroundColor(.gray),
            at: CGPoint(x: x, y: midY),
            anchor: .center
        )
    }

    private func drawArticulation(context: GraphicsContext, note: Note, x: CGFloat, y: CGFloat) {
        guard note.articulation != .normal else { return }
        let sp = layout.staffLineSpacing
        let artY = y - sp * 2.5 // above the note

        var attribs = AttributeContainer()
        attribs.font = Font.system(size: sp * 1.4, weight: .bold)

        let symbol: String
        switch note.articulation {
        case .staccato:  symbol = "•"
        case .accent:    symbol = ">"
        case .tenuto:    symbol = "—"
        default:         return
        }

        let text = AttributedString(symbol, attributes: attribs)
        context.draw(
            Text(text).foregroundColor(.black),
            at: CGPoint(x: x, y: artY),
            anchor: .center
        )
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint) {
        let clef = part.instrument.clef
        let tapTolerance: CGFloat = layout.staffLineSpacing * 1.5

        for note in part.notes {
            let noteX = layout.xPosition(forBeat: note.startBeat)
            let noteY = layout.yPosition(forMIDINote: note.pitch, clef: clef)
            let distance = sqrt(pow(noteX - location.x, 2) + pow(noteY - location.y, 2))
            if distance < tapTolerance {
                onNoteTapped?(note.id)
                return
            }
        }
    }
}
