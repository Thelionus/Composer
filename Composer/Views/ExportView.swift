import SwiftUI

// MARK: - ExportView

struct ExportView: View {
    let project: VocalScoreProject

    @EnvironmentObject private var projectViewModel: ProjectViewModel
    @State private var selectedFormat: ExportFormat = .musicXML
    @State private var titleOverride: String = ""
    @State private var composerOverride: String = ""
    @State private var isExporting = false
    @State private var exportedURL: URL? = nil
    @State private var exportError: String? = nil
    @State private var showingShareSheet = false
    @State private var showingSuccessAlert = false

    private var currentTitle: String {
        titleOverride.isEmpty ? project.title : titleOverride
    }
    private var currentComposer: String {
        composerOverride.isEmpty ? project.composer : composerOverride
    }

    var body: some View {
        Form {
            // Metadata section
            Section("Project Metadata") {
                HStack {
                    Text("Title")
                    Spacer()
                    TextField(project.title, text: $titleOverride)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Composer")
                    Spacer()
                    TextField(project.composer.isEmpty ? "Unknown" : project.composer, text: $composerOverride)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            }

            // Format selection
            Section("Export Format") {
                ForEach(ExportFormat.allCases) { format in
                    HStack {
                        Image(systemName: format.icon)
                            .foregroundColor(.purple)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(format.rawValue)
                                .font(.body)
                            Text(formatDescription(format))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if selectedFormat == format {
                            Image(systemName: "checkmark")
                                .foregroundColor(.purple)
                                .fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedFormat = format
                    }
                }
            }

            // Project summary
            Section("Summary") {
                LabeledContent("Parts", value: "\(project.parts.count)")
                LabeledContent("Total Notes", value: "\(project.totalNoteCount)")
                LabeledContent("Duration", value: durationString)
                LabeledContent("Tempo", value: "\(Int(project.tempo)) BPM")
                LabeledContent("Key", value: project.keySignature.displayName)
                LabeledContent("Time", value: project.timeSignatureDisplay)
            }

            // Export button
            Section {
                Button {
                    performExport()
                } label: {
                    HStack {
                        Spacer()
                        if isExporting {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Exporting...")
                        } else {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export as \(selectedFormat.rawValue)")
                        }
                        Spacer()
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.vertical, 4)
                }
                .disabled(isExporting || project.parts.isEmpty)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(project.parts.isEmpty ? Color.gray : Color.purple)
                )
            } footer: {
                if project.parts.isEmpty {
                    Text("Add at least one instrument part before exporting.")
                        .foregroundColor(.orange)
                }
            }

            // Error display
            if let error = exportError {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Export Complete", isPresented: $showingSuccessAlert) {
            Button("Share") {
                showingShareSheet = true
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your \(selectedFormat.rawValue) file is ready.")
        }
    }

    // MARK: - Export Logic

    private func performExport() {
        isExporting = true
        exportError = nil

        // Build a modified copy with override metadata
        var exportProject = project
        if !titleOverride.isEmpty { exportProject.title = titleOverride }
        if !composerOverride.isEmpty { exportProject.composer = composerOverride }

        Task {
            do {
                let url = try projectViewModel.exportProject(exportProject, format: selectedFormat)
                await MainActor.run {
                    exportedURL = url
                    isExporting = false
                    showingSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatDescription(_ format: ExportFormat) -> String {
        switch format {
        case .musicXML: return "Compatible with Sibelius, Finale, MuseScore, Dorico"
        case .midi:     return "Standard MIDI Type 1, compatible with all DAWs"
        case .pdf:      return "Printable score (Phase 2)"
        }
    }

    private var durationString: String {
        let totalSeconds = project.durationSeconds
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - ShareSheet

/// UIKit share sheet wrapper for SwiftUI.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
