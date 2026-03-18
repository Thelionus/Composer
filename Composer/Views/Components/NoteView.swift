import SwiftUI

// MARK: - NoteView

/// An individual note pill/chip component for use in lists, previews, and the score editor palette.
struct NoteView: View {
    let note: Note
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil
    var compact: Bool = false

    private var noteColor: Color {
        if isSelected { return .blue }
        if note.isFlagged { return .orange }
        if note.isRest { return .gray }
        if note.confidence < 0.5 { return .yellow.opacity(0.8) }
        return .purple
    }

    var body: some View {
        if compact {
            compactView
        } else {
            fullView
        }
    }

    // MARK: - Full Note Card

    private var fullView: some View {
        VStack(spacing: 4) {
            // Note head representation
            ZStack {
                Circle()
                    .fill(noteColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                if note.isRest {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                } else {
                    VStack(spacing: 1) {
                        Text(note.noteName)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(noteColor)
                        Text("\(note.octave)")
                            .font(.system(size: 10))
                            .foregroundColor(noteColor.opacity(0.7))
                    }
                }

                // Flag indicator
                if note.isFlagged {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 10, height: 10)
                        .offset(x: 16, y: -16)
                }
            }

            // Duration
            Text(note.duration.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)

            // Dynamic
            Text(note.dynamic.rawValue)
                .font(.system(size: 10, weight: .bold, design: .serif))
                .italic()
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? noteColor.opacity(0.1) : Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? noteColor : Color.clear, lineWidth: 1.5)
                )
        )
        .onTapGesture { onTap?() }
    }

    // MARK: - Compact Chip

    private var compactView: some View {
        HStack(spacing: 4) {
            Text(note.isRest ? "𝄽" : note.noteName)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(noteColor)

            if note.duration.isDotted {
                Circle()
                    .fill(noteColor)
                    .frame(width: 3, height: 3)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(noteColor.opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(isSelected ? noteColor : Color.clear, lineWidth: 1)
                )
        )
        .onTapGesture { onTap?() }
    }
}

// MARK: - NoteGrid

/// A flowing grid of NoteView chips for displaying all notes of a part.
struct NoteGrid: View {
    let notes: [Note]
    let selectedIDs: Set<UUID>
    let onTap: (UUID) -> Void

    let columns = [GridItem(.adaptive(minimum: 60, maximum: 90))]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(notes) { note in
                NoteView(
                    note: note,
                    isSelected: selectedIDs.contains(note.id),
                    onTap: { onTap(note.id) },
                    compact: false
                )
            }
        }
    }
}

// MARK: - NoteStrip

/// A horizontal scrolling strip of compact note chips.
struct NoteStrip: View {
    let notes: [Note]
    var maxVisible: Int = 32
    var onTap: ((UUID) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(notes.prefix(maxVisible)) { note in
                    NoteView(note: note, onTap: { onTap?(note.id) }, compact: true)
                }

                if notes.count > maxVisible {
                    Text("+\(notes.count - maxVisible)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 12) {
            NoteView(note: Note(pitch: 60, duration: .quarter, velocity: 80))
            NoteView(note: Note(pitch: 64, duration: .eighth, velocity: 95, dynamic: .f), isSelected: true)
            NoteView(note: Note(pitch: -1, duration: .half))
            NoteView(note: Note(pitch: 72, duration: .sixteenth, confidence: 0.4, isFlagged: true, flagReason: "Out of range"))
        }
        .padding()

        NoteStrip(notes: (60...72).map { midi in
            Note(pitch: midi, duration: .quarter)
        })
        .padding()
    }
}
