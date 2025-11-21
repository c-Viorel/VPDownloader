import Foundation

/// Represents where the downloaded file should be stored.
public struct VPDownloadDestination: Sendable {
    public let directory: URL
    public let fileName: String?
    public let overwriteExisting: Bool

    /// - Parameters:
    ///   - directory: Folder where the file should be written. Must be a file URL.
    ///   - fileName: Optional custom file name. When omitted, the file name is derived from the source URL.
    ///   - overwriteExisting: When `true`, existing files with the same name are replaced.
    public init(directory: URL, fileName: String? = nil, overwriteExisting: Bool = true) {
        precondition(directory.isFileURL, "VPDownloadDestination expects file URL destinations.")
        self.directory = directory
        self.fileName = fileName
        self.overwriteExisting = overwriteExisting
    }
}
