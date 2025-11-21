import Foundation

/// Errors thrown by `VPFileDownloader`.
public enum VPDownloadError: Error, LocalizedError, Sendable {
    case invalidResponse
    case httpError(statusCode: Int)
    case emptyFileName
    case destinationIsNotDirectory(URL)
    case destinationExists(URL)
    case failedToPrepareDirectory(URL, underlying: Error)
    case failedToWrite(URL, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server response was not HTTP."
        case .httpError(let statusCode):
            return "Server responded with HTTP status code \(statusCode)."
        case .emptyFileName:
            return "Unable to infer a file name. Please provide one explicitly."
        case .destinationIsNotDirectory(let url):
            return "The path \(url.path) is not a directory."
        case .destinationExists(let url):
            return "A file already exists at \(url.path)."
        case .failedToPrepareDirectory(let url, let underlying):
            return "Failed to prepare directory at \(url.path): \(underlying.localizedDescription)"
        case .failedToWrite(let url, let underlying):
            return "Failed to write file at \(url.path): \(underlying.localizedDescription)"
        }
    }
}

extension VPDownloadError {
    var isRetryable: Bool {
        switch self {
        case .invalidResponse, .httpError:
            return true
        case .emptyFileName,
             .destinationIsNotDirectory,
             .destinationExists,
             .failedToPrepareDirectory,
             .failedToWrite:
            return false
        }
    }
}
