import Foundation

enum ProjectStoreError: Error { case notFound, ioError }

final class ProjectStore {
    static let shared = ProjectStore()
    private init() {}

    private var root: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var indexURL: URL { root.appendingPathComponent("index.json") }

    func list() -> [AnalysisProject] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? JSONDecoder().decode([AnalysisProject].self, from: data)) ?? []
    }

    func saveIndex(_ projects: [AnalysisProject]) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(projects) { try? data.write(to: indexURL, options: .atomic) }
    }

    func folder(for project: AnalysisProject) -> URL {
        let url = root.appendingPathComponent(project.folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func fileURL(for project: AnalysisProject, relative: String) -> URL {
        folder(for: project).appendingPathComponent(relative)
    }

    func upsert(project: AnalysisProject) {
        var items = list()
        if let i = items.firstIndex(where: { $0.id == project.id }) { items[i] = project }
        else { items.insert(project, at: 0) }
        saveIndex(items)
    }

    func delete(project: AnalysisProject) {
        var items = list()
        items.removeAll { $0.id == project.id }
        saveIndex(items)
        let folder = folder(for: project)
        try? FileManager.default.removeItem(at: folder)
    }
}

