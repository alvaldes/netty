import AppKit

/// Icons the user imported, kept as copies in Netty's Application Support folder
/// so they survive the original file being moved or deleted.
struct CustomIconStore {
    struct UnreadableImage: Error {}

    static let allowedExtensions = ["svg", "pdf", "png"]

    let folder: URL

    init(folder: URL = URL.applicationSupportDirectory.appending(path: "Netty/Icons", directoryHint: .isDirectory)) {
        self.folder = folder
    }

    /// Copies an SVG, PDF or PNG into the store and returns its new file name.
    func importImage(from url: URL) throws -> String {
        let fileExtension = url.pathExtension.lowercased()
        guard Self.allowedExtensions.contains(fileExtension), NSImage(contentsOf: url) != nil else {
            throw UnreadableImage()
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        try FileManager.default.copyItem(at: url, to: folder.appending(path: fileName))
        return fileName
    }

    func image(named fileName: String) -> NSImage? {
        // Only names this store created: never a path.
        guard !fileName.contains("/") else { return nil }
        return NSImage(contentsOf: folder.appending(path: fileName))
    }
}
