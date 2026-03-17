import SwiftUI

// MARK: - MixerView

/// Mixer console view showing volume faders, pan controls, and solo/mute for each part.
struct MixerView: View {
    @Binding var project: VocalScoreProject
    let onPartUpdated: (Part) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(project.parts.indices, id: \.self) { index in
                    MixerChannelView(
                        part: $project.parts[index],
                        onChanged: { onPartUpdated(project.parts[index]) }
                    )
                }

                Divider()
                    .frame(height: 400)
                    .padding(.horizontal, 8)

                // Master output channel
                MasterChannelView()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .center) {
            if project.parts.isEmpty {
                Text("No parts — add instruments to the project first.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }
}

// MARK: - MixerChannelView

struct MixerChannelView: View {
    @Binding var part: Part
    let onChanged: () -> Void

    private var familyColor: Color {
        Color(hex: part.color) ?? .purple
    }

    var body: some View {
        VStack(spacing: 8) {
            // Instrument icon
            ZStack {
                Circle()
                    .fill(familyColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: part.instrument.icon)
                    .font(.system(size: 15))
                    .foregroundColor(familyColor)
            }

            // Part name
            Text(part.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 72)

            Spacer(minLength: 8)

            // Pan knob (rendered as a small slider)
            VStack(spacing: 2) {
                Text("PAN")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)

                PanKnobView(value: $part.pan)
                    .frame(width: 44, height: 44)
                    .onChange(of: part.pan) { _, _ in onChanged() }
            }

            // Solo / Mute buttons
            HStack(spacing: 4) {
                Button {
                    part.isSolo.toggle()
                    if part.isSolo { part.isMuted = false }
                    onChanged()
                } label: {
                    Text("S")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(part.isSolo ? Color.yellow : Color.secondary.opacity(0.2))
                        .foregroundColor(part.isSolo ? .black : .secondary)
                        .cornerRadius(6)
                }

                Button {
                    part.isMuted.toggle()
                    if part.isMuted { part.isSolo = false }
                    onChanged()
                } label: {
                    Text("M")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(part.isMuted ? Color.orange : Color.secondary.opacity(0.2))
                        .foregroundColor(part.isMuted ? .white : .secondary)
                        .cornerRadius(6)
                }
            }

            // Volume fader
            VStack(spacing: 4) {
                Text("VOL")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)

                // Vertical slider using rotation trick
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        // Track
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 8)
                            .frame(maxWidth: .infinity)

                        // Fill
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [familyColor.opacity(0.6), familyColor],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 8, height: CGFloat(part.volume) * geo.size.height)
                            .frame(maxWidth: .infinity, alignment: .center)

                        // Thumb
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .shadow(radius: 2)
                            .frame(width: 22, height: 8)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .offset(y: -(CGFloat(part.volume) * geo.size.height - 4))
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let newVolume = Float(1.0 - value.location.y / geo.size.height)
                                part.volume = max(0, min(1, newVolume))
                                onChanged()
                            }
                    )
                }
                .frame(height: 120)

                Text("\(Int(part.volume * 100))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .frame(width: 90)
        .opacity(part.isMuted ? 0.5 : 1.0)
    }
}

// MARK: - PanKnobView

/// Circular pan control rendered as a rotary knob.
struct PanKnobView: View {
    @Binding var value: Float  // -1.0 to 1.0

    @State private var lastDragY: CGFloat = 0

    private var angle: Double {
        Double(value) * 135.0  // ±135 degrees
    }

    var body: some View {
        ZStack {
            // Knob track
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 3)
                .frame(width: 36, height: 36)

            // Active arc
            Circle()
                .trim(from: 0.375, to: 0.375 + Double(value + 1.0) / 2.0 * 0.25)
                .stroke(Color.purple, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 36, height: 36)

            // Indicator line
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: 10)
                .offset(y: -12)
                .rotationEffect(.degrees(angle))

            // Center dot
            Circle()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 20, height: 20)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let delta = Float(-(drag.location.y - lastDragY) / 100.0)
                    value = max(-1.0, min(1.0, value + delta))
                    lastDragY = drag.location.y
                }
                .onEnded { _ in lastDragY = 0 }
        )
        .overlay(alignment: .bottom) {
            Text(panLabel)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .offset(y: 16)
        }
    }

    private var panLabel: String {
        if abs(value) < 0.05 { return "C" }
        let pct = Int(abs(value) * 100)
        return value < 0 ? "L\(pct)" : "R\(pct)"
    }
}

// MARK: - MasterChannelView

struct MasterChannelView: View {
    @State private var masterVolume: Float = 1.0

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.purple)
            }

            Text("Master")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.primary)

            Spacer(minLength: 8)

            // VU Meter placeholder
            VStack(spacing: 2) {
                ForEach((0..<8).reversed(), id: \.self) { level in
                    Rectangle()
                        .fill(vuColor(for: level))
                        .frame(width: 16, height: 6)
                        .cornerRadius(2)
                        .opacity(Double(level) < Double(masterVolume * 8) ? 1.0 : 0.2)
                }
            }
            .frame(height: 80)

            Spacer(minLength: 8)

            Text("MASTER")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 8)
                        .frame(maxWidth: .infinity)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [.green, .yellow, .orange],
                            startPoint: .bottom,
                            endPoint: .top
                        ))
                        .frame(width: 8, height: CGFloat(masterVolume) * geo.size.height)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            masterVolume = max(0, min(1, Float(1.0 - value.location.y / geo.size.height)))
                        }
                )
            }
            .frame(height: 120)

            Text("\(Int(masterVolume * 100))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .frame(width: 90)
    }

    private func vuColor(for level: Int) -> Color {
        switch level {
        case 0...4: return .green
        case 5...6: return .yellow
        default:    return .red
        }
    }
}
