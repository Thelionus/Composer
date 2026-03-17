import Foundation
import Combine
import SwiftUI

// MARK: - ExportFormat

enum ExportFormat: String, CaseIterable, Identifiable {
    case musicXML = "MusicXML"
    case midi     = "MIDI"
    case pdf      = "PDF"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .musicXML: return "musicxml"
        case .midi:     return "mid"
        case .pdf:      return "pdf"
        }
    }

    var mimeType: String {
        switch self {
        case .musicXML: return "application/vnd.recordare.musicxml+xml"
        case .midi:     return "audio/midi"
        case .pdf:      return "application/pdf"
        }
    }

    var icon: String {
        switch self {
        case .musicXML: return "doc.text"
        case .midi:     return "music.note.list"
        case .pdf:      return "doc.richtext"
        }
    }
}

// MARK: - ProjectViewModel

@MainActor
final class ProjectViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var projects: [VocalScoreProject] = []
    @Published var currentProject: VocalScoreProject?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var sortOrder: SortOrder = .modifiedDesc

    // MARK: - Dependencies

    private let xmlExporter = MusicXMLExporter()
    private let midiExporter = MIDIExporter()

    // MARK: - Persistence

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var projectsFileURL: URL {
        documentsURL.appendingPathComponent("projects.json")
    }

    // MARK: - Initializer

    init() {
        loadProjects()
    }

    // MARK: - CRUD

    func createProject(
        title: String = "Untitled Composition",
        composer: String = "",
        tempo: Double = 120,
        keySignature: KeySignature = .cMajor
    ) -> VocalScoreProject {
        let project = VocalScoreProject(
            title: title,
            composer: composer,
            tempo: tempo,
            keySignature: keySignature
        )
        projects.insert(project, at: 0)
        saveProjects()
        return project
    }

    func deleteProject(_ project: VocalScoreProject) {
        projects.removeAll { $0.id == project.id }
        if currentProject?.id == project.id {
            currentProject = nil
        }
        saveProjects()
    }

    func deleteProjects(at offsets: IndexSet) {
        let sorted = sortedProjects
        for index in offsets {
            let project = sorted[index]
            projects.removeAll { $0.id == project.id }
            if currentProject?.id == project.id {
                currentProject = nil
            }
        }
        saveProjects()
    }

    func updateProject(_ updated: VocalScoreProject) {
        if let index = projects.firstIndex(where: { $0.id == updated.id }) {
            var project = updated
            project.modifiedAt = Date()
            projects[index] = project
            if currentProject?.id == project.id {
                currentProject = project
            }
        }
        saveProjects()
    }

    func addPart(_ part: Part, to projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].parts.append(part)
        projects[index].markModified()
        if currentProject?.id == projectID {
            currentProject = projects[index]
        }
        saveProjects()
    }

    func removePart(_ partID: UUID, from projectID: UUID) {
        guard let pIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[pIndex].parts.removeAll { $0.id == partID }
        projects[pIndex].markModified()
        if currentProject?.id == projectID {
            currentProject = projects[pIndex]
        }
        saveProjects()
    }

    func updatePart(_ part: Part, in projectID: UUID) {
        guard let pIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        if let partIndex = projects[pIndex].parts.firstIndex(where: { $0.id == part.id }) {
            projects[pIndex].parts[partIndex] = part
            projects[pIndex].markModified()
            if currentProject?.id == projectID {
                currentProject = projects[pIndex]
            }
        }
        saveProjects()
    }

    func duplicateProject(_ project: VocalScoreProject) {
        var duplicate = project
        duplicate.id = UUID()
        duplicate.title = "\(project.title) (Copy)"
        duplicate.createdAt = Date()
        duplicate.modifiedAt = Date()
        // Give each part a new ID to avoid conflicts
        duplicate.parts = project.parts.map { part in
            var newPart = part
            newPart.id = UUID()
            newPart.notes = part.notes.map { note in
                var newNote = note
                newNote.id = UUID()
                return newNote
            }
            return newPart
        }
        projects.insert(duplicate, at: 0)
        saveProjects()
    }

    // MARK: - Sorted Projects

    enum SortOrder: String, CaseIterable {
        case modifiedDesc = "Recently Modified"
        case modifiedAsc  = "Oldest First"
        case titleAsc     = "Title A–Z"
        case titleDesc    = "Title Z–A"
    }

    var sortedProjects: [VocalScoreProject] {
        switch sortOrder {
        case .modifiedDesc: return projects.sorted { $0.modifiedAt > $1.modifiedAt }
        case .modifiedAsc:  return projects.sorted { $0.modifiedAt < $1.modifiedAt }
        case .titleAsc:     return projects.sorted { $0.title < $1.title }
        case .titleDesc:    return projects.sorted { $0.title > $1.title }
        }
    }

    // MARK: - Persistence

    func loadProjects() {
        isLoading = true
        defer { isLoading = false }

        guard FileManager.default.fileExists(atPath: projectsFileURL.path) else {
            // First launch — create a sample project
            let sample = VocalScoreProject.sampleProject
            projects = [sample]
            saveProjects()
            return
        }

        do {
            let data = try Data(contentsOf: projectsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            projects = try decoder.decode([VocalScoreProject].self, from: data)
        } catch {
            errorMessage = "Failed to load projects: \(error.localizedDescription)"
            projects = []
        }
    }

    func saveProjects() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(projects)
            try data.write(to: projectsFileURL, options: .atomic)
        } catch {
            errorMessage = "Failed to save projects: \(error.localizedDescription)"
        }
    }

    // MARK: - Export

    func exportProject(_ project: VocalScoreProject, format: ExportFormat) throws -> URL {
        let fileName = sanitizeFilename(project.title) + ".\(format.fileExtension)"
        let exportURL = documentsURL.appendingPathComponent("Exports").appendingPathComponent(fileName)

        // Ensure exports directory exists
        let exportsDir = documentsURL.appendingPathComponent("Exports")
        if !FileManager.default.fileExists(atPath: exportsDir.path) {
            try FileManager.default.createDirectory(at: exportsDir, withIntermediateDirectories: true)
        }

        switch format {
        case .musicXML:
            try xmlExporter.exportToFile(project: project, url: exportURL)

        case .midi:
            let data = try midiExporter.export(project: project)
            try data.write(to: exportURL, options: .atomic)

        case .pdf:
            // PDF export is a Phase 2 feature — write a placeholder text file
            let placeholder = "PDF export coming in Phase 2.\n\nProject: \(project.title)\nParts: \(project.parts.count)"
            guard let data = placeholder.data(using: .utf8) else {
                throw ExportError.encodingFailed
            }
            let txtURL = exportURL.deletingPathExtension().appendingPathExtension("txt")
            try data.write(to: txtURL, options: .atomic)
            return txtURL
        }

        return exportURL
    }

    // MARK: - Helpers

    private func sanitizeFilename(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " -_"))
        return name.unicodeScalars
            .filter { allowed.contains($0) }
            .reduce("") { $0 + String($1) }
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
    }
}
