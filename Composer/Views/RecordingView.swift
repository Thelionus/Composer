import SwiftUI

// MARK: - RecordingView

/// Full-screen recording interface for capturing sung voice input.
struct RecordingView: View {
    let instrument: Instrument
    let onAccept: (Part) -> Void

    @StateObject private var viewModel = RecordingViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingGridPicker = false
    @State private var pulseAnimation = false

    var body: some View {
        ZStack {
            // Background
            backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.horizontal)
                    .padding(.top)

                Spacer()

                // Pitch meter
                PitchMeterView(
                    noteName: viewModel.currentNoteName,
                    centsDeviation: viewModel.centsDeviation,
                    confidence: viewModel.pitchConfidence
                )
                .frame(height: 80)
                .padding(.horizontal, 32)

                Spacer(minLength: 16)

                // Waveform
                WaveformView(
                    samples: viewModel.waveformSamples,
                    isRecording: viewModel.state.isRecording
                )
                .frame(height: 100)
                .padding(.horizontal, 16)
                .cornerRadius(12)

                Spacer(minLength: 16)

                // Note preview (when reviewing)
                if viewModel.state == .reviewing {
                    notePreviewSection
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Recording controls
                recordingControls
                    .padding(.vertical, 24)

                // Bottom controls
                bottomControls
                    .padding(.bottom, 24)
            }
        }
        .navigationTitle("Record: \(instrument.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    viewModel.reset()
                    dismiss()
                }
                .foregroundColor(.white)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Quantization Grid", selection: $viewModel.quantizationGrid) {
                        ForEach(QuantizationGrid.allCases) { grid in
                            Text(grid.displayName).tag(grid)
                        }
                    }
                } label: {
                    Image(systemName: "music.note")
                        .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            viewModel.selectedInstrument = instrument
        }
        .onDisappear {
            viewModel.reset()
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: stateColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var stateColors: [Color] {
        switch viewModel.state {
        case .recording:  return [Color(red: 0.4, green: 0.0, blue: 0.0), Color(red: 0.15, green: 0.0, blue: 0.0)]
        case .processing: return [Color(red: 0.1, green: 0.1, blue: 0.3), Color(red: 0.05, green: 0.05, blue: 0.15)]
        case .reviewing:  return [Color(red: 0.0, green: 0.1, blue: 0.3), Color(red: 0.0, green: 0.05, blue: 0.15)]
        default:          return [Color(red: 0.05, green: 0.05, blue: 0.2), Color(red: 0.02, green: 0.02, blue: 0.1)]
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: instrument.icon)
                        .foregroundColor(.white.opacity(0.8))
                    Text(instrument.name)
                        .font(.headline)
                        .foregroundColor(.white)
                }

                Text(viewModel.state.displayName)
                    .font(.subheadline)
                    .foregroundColor(viewModel.statusColor.opacity(0.9))
            }

            Spacer()

            // Take counter
            if !viewModel.takes.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Take \(viewModel.selectedTake + 1)/\(viewModel.takes.count)")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.white.opacity(0.15))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Note Preview

    private var notePreviewSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Detected Notes")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("\(viewModel.detectedNotes.count) notes")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 20)

            if viewModel.detectedNotes.isEmpty {
                Text("No notes detected. Try recording again with more volume.")
                    .font(.subheadline)
                    .foregroundColor(.orange.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.detectedNotes.prefix(24)) { note in
                            NoteChipView(note: note)
                        }
                        if viewModel.detectedNotes.count > 24 {
                            Text("+\(viewModel.detectedNotes.count - 24)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 8)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            // Audition button
            Button {
                viewModel.auditNotes(tempo: 120)
            } label: {
                Label("Audition Notes", systemImage: "play.circle")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 12)
        .background(.white.opacity(0.07))
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    // MARK: - Recording Controls

    private var recordingControls: some View {
        ZStack {
            // Pulse ring when recording
            if viewModel.state == .recording {
                Circle()
                    .stroke(Color.red.opacity(0.4), lineWidth: 3)
                    .frame(width: 100, height: 100)
                    .scaleEffect(pulseAnimation ? 1.4 : 1.0)
                    .opacity(pulseAnimation ? 0 : 0.8)
                    .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: pulseAnimation)
                    .onAppear { pulseAnimation = true }
                    .onDisappear { pulseAnimation = false }
            }

            // Main record button
            Button {
                switch viewModel.state {
                case .idle, .reviewing:
                    viewModel.startRecording()
                case .recording:
                    viewModel.stopRecording()
                default:
                    break
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(recordButtonColor)
                        .frame(width: 80, height: 80)
                        .shadow(color: recordButtonColor.opacity(0.5), radius: 12, x: 0, y: 4)

                    recordButtonIcon
                        .font(.system(size: 30, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .disabled(viewModel.state == .processing)
            .scaleEffect(viewModel.state == .recording ? 0.95 : 1.0)
            .animation(.spring(response: 0.3), value: viewModel.state)
        }
    }

    private var recordButtonColor: Color {
        switch viewModel.state {
        case .idle:       return .red
        case .recording:  return .red.opacity(0.8)
        case .processing: return .gray
        case .reviewing:  return Color(red: 0.8, green: 0.2, blue: 0.2)
        default:          return .red
        }
    }

    private var recordButtonIcon: some View {
        Group {
            if viewModel.state == .recording {
                Image(systemName: "stop.fill")
            } else if viewModel.state == .processing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.3)
            } else {
                Image(systemName: "mic.fill")
            }
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 16) {
            // Take switcher (if multiple takes)
            if viewModel.takes.count > 1 {
                takeSwitcher
            }

            // Accept / Discard (when reviewing)
            if viewModel.state == .reviewing {
                HStack(spacing: 24) {
                    Button {
                        viewModel.discardTake()
                    } label: {
                        Label("Discard", systemImage: "trash")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 130)
                            .padding(.vertical, 14)
                            .background(.white.opacity(0.15))
                            .cornerRadius(14)
                    }

                    Button {
                        let part = viewModel.acceptTake()
                        onAccept(part)
                        dismiss()
                    } label: {
                        Label("Accept", systemImage: "checkmark")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 130)
                            .padding(.vertical, 14)
                            .background(Color.green)
                            .cornerRadius(14)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal)
        .animation(.spring(response: 0.4), value: viewModel.state)
    }

    private var takeSwitcher: some View {
        HStack(spacing: 8) {
            Button {
                if viewModel.selectedTake > 0 {
                    viewModel.selectTake(viewModel.selectedTake - 1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(viewModel.selectedTake > 0 ? .white : .white.opacity(0.3))
            }
            .disabled(viewModel.selectedTake == 0)

            Text("Take \(viewModel.selectedTake + 1) of \(viewModel.takes.count)")
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(minWidth: 120)

            Button {
                if viewModel.selectedTake < viewModel.takes.count - 1 {
                    viewModel.selectTake(viewModel.selectedTake + 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(viewModel.selectedTake < viewModel.takes.count - 1 ? .white : .white.opacity(0.3))
            }
            .disabled(viewModel.selectedTake >= viewModel.takes.count - 1)
        }
    }
}

// MARK: - NoteChipView

struct NoteChipView: View {
    let note: Note

    var chipColor: Color {
        if note.isFlagged { return .orange }
        if note.confidence < 0.6 { return .yellow.opacity(0.8) }
        if note.isRest { return .gray }
        return .white.opacity(0.25)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(note.isRest ? "𝄽" : note.noteName)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
            Text(note.duration.rawValue.prefix(3))
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(chipColor)
        .cornerRadius(8)
    }
}
