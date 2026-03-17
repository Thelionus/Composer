import SwiftUI

// MARK: - WaveformView

/// Real-time Canvas-based waveform display.
/// Draws audio samples as a scrolling center-line waveform.
struct WaveformView: View {
    let samples: [Float]
    var isRecording: Bool = false
    var waveformColor: Color = .green
    var backgroundColor: Color = Color(.systemBackground).opacity(0.1)
    var lineWidth: CGFloat = 1.5

    @State private var phase: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            drawWaveform(context: context, size: size)
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isRecording ? Color.red.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
        .onAppear {
            if isRecording {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    phase += 1
                }
            }
        }
    }

    // MARK: - Drawing

    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        let midY = size.height / 2
        let width = size.width
        let height = size.height

        // Background
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(backgroundColor)
        )

        // Center line
        var centerLinePath = Path()
        centerLinePath.move(to: CGPoint(x: 0, y: midY))
        centerLinePath.addLine(to: CGPoint(x: width, y: midY))
        context.stroke(centerLinePath, with: .color(.white.opacity(0.15)), lineWidth: 0.5)

        guard !samples.isEmpty else {
            // Draw idle flat line
            drawIdleLine(context: context, size: size)
            return
        }

        // Waveform path
        let sampleCount = samples.count
        let stepX = width / CGFloat(sampleCount)
        let amplitudeScale = height * 0.45  // 45% of half-height for headroom

        var waveformPath = Path()
        waveformPath.move(to: CGPoint(x: 0, y: midY))

        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * stepX
            let clampedSample = max(-1.0, min(1.0, sample))
            let y = midY - CGFloat(clampedSample) * amplitudeScale
            if index == 0 {
                waveformPath.move(to: CGPoint(x: x, y: y))
            } else {
                waveformPath.addLine(to: CGPoint(x: x, y: y))
            }
        }

        // Draw filled waveform with gradient
        var fillPath = waveformPath
        fillPath.addLine(to: CGPoint(x: width, y: midY))
        fillPath.addLine(to: CGPoint(x: 0, y: midY))
        fillPath.closeSubpath()

        context.fill(
            fillPath,
            with: .color(waveformColor.opacity(0.2))
        )

        context.stroke(
            waveformPath,
            with: .color(isRecording ? .red.opacity(0.9) : waveformColor.opacity(0.85)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )

        // Mirror waveform below center
        var mirrorPath = Path()
        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * stepX
            let clampedSample = max(-1.0, min(1.0, sample))
            let y = midY + CGFloat(clampedSample) * amplitudeScale * 0.6
            if index == 0 {
                mirrorPath.move(to: CGPoint(x: x, y: y))
            } else {
                mirrorPath.addLine(to: CGPoint(x: x, y: y))
            }
        }

        context.stroke(
            mirrorPath,
            with: .color((isRecording ? Color.red : waveformColor).opacity(0.3)),
            style: StrokeStyle(lineWidth: lineWidth * 0.6, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawIdleLine(context: GraphicsContext, size: CGSize) {
        let midY = size.height / 2

        // Flat dotted line when idle
        var path = Path()
        path.move(to: CGPoint(x: 0, y: midY))
        path.addLine(to: CGPoint(x: size.width, y: midY))
        context.stroke(
            path,
            with: .color(.white.opacity(0.2)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
        )

        // "Ready" text
        var attribs = AttributeContainer()
        attribs.font = Font.system(size: 12)
        let text = AttributedString("Tap record to begin", attributes: attribs)
        context.draw(
            Text(text).foregroundColor(.white.opacity(0.4)),
            at: CGPoint(x: size.width / 2, y: midY),
            anchor: .center
        )
    }
}

// MARK: - LevelMeterView

/// A vertical VU meter bar showing audio input level.
struct LevelMeterView: View {
    let level: Float  // 0–1 normalized
    var segments: Int = 20
    var activeColor: Color = .green
    var warningColor: Color = .yellow
    var clippingColor: Color = .red

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 2) {
                ForEach((0..<segments).reversed(), id: \.self) { segment in
                    let segThreshold = Float(segment) / Float(segments)
                    let isActive = level > segThreshold
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isActive ? segmentColor(segment) : Color.secondary.opacity(0.15))
                        .frame(height: geo.size.height / CGFloat(segments) - 2)
                }
            }
        }
    }

    private func segmentColor(_ segment: Int) -> Color {
        let fraction = Float(segment) / Float(segments)
        if fraction > 0.85 { return clippingColor }
        if fraction > 0.65 { return warningColor }
        return activeColor
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        WaveformView(
            samples: (0..<256).map { i in sin(Float(i) * 0.2) * 0.8 },
            isRecording: true
        )
        .frame(height: 100)
        .padding()

        WaveformView(samples: [], isRecording: false)
            .frame(height: 80)
            .padding()
    }
    .background(Color.black)
}
