import SwiftUI

// MARK: - PitchMeterView

/// Displays the current detected note name and cents deviation from equal temperament.
/// Color-coded: green = in tune, yellow = ±10–25 cents, red = >25 cents off.
struct PitchMeterView: View {
    let noteName: String
    let centsDeviation: Float  // -50 to +50 cents
    let confidence: Float      // 0–1

    private var tuningColor: Color {
        let absDeviation = abs(centsDeviation)
        if confidence < 0.3 { return .secondary }
        if absDeviation <= 10 { return .green }
        if absDeviation <= 25 { return .yellow }
        return .red
    }

    private var tuningLabel: String {
        if confidence < 0.3 { return "–" }
        let absDeviation = abs(centsDeviation)
        if absDeviation <= 5 { return "In Tune" }
        let sign = centsDeviation > 0 ? "+" : ""
        return "\(sign)\(Int(centsDeviation))¢"
    }

    var body: some View {
        HStack(spacing: 20) {
            // Note name display
            VStack(spacing: 4) {
                Text(noteName)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundColor(tuningColor)
                    .animation(.spring(response: 0.2), value: noteName)

                Text(tuningLabel)
                    .font(.caption)
                    .foregroundColor(tuningColor.opacity(0.9))
            }
            .frame(minWidth: 80)

            // Cents deviation meter
            CentsDeviationMeter(cents: centsDeviation, confidence: confidence)
                .frame(maxWidth: .infinity, maxHeight: 40)
        }
    }
}

// MARK: - CentsDeviationMeter

/// A horizontal bar showing cents deviation from ±50 cents.
struct CentsDeviationMeter: View {
    let cents: Float   // -50 to +50
    let confidence: Float

    private var normalizedPosition: CGFloat {
        // Maps -50..+50 to 0..1
        CGFloat((cents + 50) / 100)
    }

    private var indicatorColor: Color {
        guard confidence > 0.3 else { return .secondary }
        let absC = abs(cents)
        if absC <= 10 { return .green }
        if absC <= 25 { return .yellow }
        return .red
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 8)

                // Center tick
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 2, height: 14)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // Zone coloring
                HStack(spacing: 0) {
                    Rectangle().fill(Color.red.opacity(0.15))
                        .frame(width: geo.size.width * 0.15)
                    Rectangle().fill(Color.yellow.opacity(0.15))
                        .frame(width: geo.size.width * 0.1)
                    Rectangle().fill(Color.green.opacity(0.2))
                        .frame(width: geo.size.width * 0.5)
                    Rectangle().fill(Color.yellow.opacity(0.15))
                        .frame(width: geo.size.width * 0.1)
                    Rectangle().fill(Color.red.opacity(0.15))
                        .frame(width: geo.size.width * 0.15)
                }
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // Indicator
                if confidence > 0.3 {
                    Circle()
                        .fill(indicatorColor)
                        .frame(width: 16, height: 16)
                        .shadow(color: indicatorColor.opacity(0.6), radius: 4, x: 0, y: 0)
                        .position(
                            x: max(8, min(geo.size.width - 8, normalizedPosition * geo.size.width)),
                            y: geo.size.height / 2
                        )
                        .animation(.spring(response: 0.1, dampingFraction: 0.8), value: cents)
                }

                // Labels
                HStack {
                    Text("-50¢")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("0")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("+50¢")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .offset(y: 14)
            }
        }
    }
}

// MARK: - CompactPitchDisplay

/// A compact inline pitch indicator for use in toolbars and small spaces.
struct CompactPitchDisplay: View {
    let noteName: String
    let confidence: Float

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(confidence > 0.5 ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)

            Text(noteName)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 32) {
            PitchMeterView(noteName: "A4", centsDeviation: -8, confidence: 0.92)
                .padding(.horizontal)

            PitchMeterView(noteName: "C#5", centsDeviation: 32, confidence: 0.75)
                .padding(.horizontal)

            PitchMeterView(noteName: "--", centsDeviation: 0, confidence: 0.1)
                .padding(.horizontal)
        }
    }
}
