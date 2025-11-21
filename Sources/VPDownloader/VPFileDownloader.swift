import Foundation

/// Swift 6-ready downloader that persists data to disk with retry logic.
///
/// ### Basic download
/// ```swift
/// let downloader = VPFileDownloader()
/// let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
/// try await downloader.download(
///     from: URL(string: "https://cdn.example.com/asset.mov")!,
///     to: documents,
///     fileName: "asset.mov"
/// )
/// ```
///
/// ### Custom destination with overwrite protection
/// ```swift
/// let destination = VPDownloadDestination(directory: documents, fileName: "report.pdf", overwriteExisting: false)
/// do {
///     try await downloader.download(from: reportURL, destination: destination)
/// } catch VPDownloadError.destinationExists {
///     // Ask the user whether they want to replace the file.
/// }
/// ```
///
/// ### Progress updates + background session
/// ```swift
/// let backgroundDownloader = VPFileDownloader(backgroundIdentifier: "com.yourcompany.bg.downloads")
/// _ = try await backgroundDownloader.download(from: bigURL, to: documents) { progress in
///     DispatchQueue.main.async {
///         self.progressView.progress = Float(progress.fractionCompleted ?? 0)
///     }
/// }
/// ```
public final class VPFileDownloader {
    private let session: URLSession
    private let fileManager: FileManager

    /// Creates a downloader with a custom `URLSession`.
    public init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    /// Convenience initializer for providing a session configuration.
    public convenience init(configuration: URLSessionConfiguration, fileManager: FileManager = .default) {
        self.init(session: URLSession(configuration: configuration), fileManager: fileManager)
    }

    /// Convenience initializer for background-friendly sessions.
    ///
    /// - Parameters:
    ///   - identifier: Unique identifier for the background session.
    ///   - sharedContainerIdentifier: Optional shared container for storing files outside the app sandbox.
    ///   - isDiscretionary: When true the OS can schedule transfers for optimal performance.
    public convenience init(
        backgroundIdentifier identifier: String,
        sharedContainerIdentifier: String? = nil,
        isDiscretionary: Bool = false,
        fileManager: FileManager = .default
    ) {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sharedContainerIdentifier = sharedContainerIdentifier
        configuration.isDiscretionary = isDiscretionary
        self.init(configuration: configuration, fileManager: fileManager)
    }

    /// The underlying session configuration, useful for inspection/testing.
    public var configuration: URLSessionConfiguration {
        session.configuration
    }

    /// Downloads a file and writes it to disk.
    ///
    /// - Parameters:
    ///   - sourceURL: Remote location of the file.
    ///   - destination: Destination descriptor describing folder, file name, and overwrite behaviour.
    ///   - retryConfiguration: Retry behaviour. Defaults to exponential backoff with three attempts.
    ///   - headers: Optional HTTP headers to send alongside the request.
    ///   - progressHandler: Receives progress updates on an arbitrary queue.
    /// - Returns: The final file URL on disk.
    @discardableResult
    public func download(
        from sourceURL: URL,
        destination: VPDownloadDestination,
        retryConfiguration: VPDownloadRetryConfiguration = .default,
        headers: [String: String] = [:],
        progressHandler: (@Sendable (VPDownloadProgress) -> Void)? = nil
    ) async throws -> URL {
        return try await executeWithRetry(retryConfiguration: retryConfiguration) { [self] in
            try Task.checkCancellation()
            var request = URLRequest(url: sourceURL)
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw VPDownloadError.invalidResponse
            }
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                throw VPDownloadError.httpError(statusCode: httpResponse.statusCode)
            }

            let destinationURL = try prepareDestinationURL(from: sourceURL, destination: destination)
            try ensureDestinationWritable(destinationURL, overwrite: destination.overwriteExisting)
            try await persist(
                stream: bytes,
                response: httpResponse,
                to: destinationURL,
                overwrite: destination.overwriteExisting,
                progressHandler: progressHandler
            )
            return destinationURL
        }
    }

    /// Convenience overload that builds the `VPDownloadDestination` for you.
    @discardableResult
    public func download(
        from sourceURL: URL,
        to directory: URL,
        fileName: String? = nil,
        overwriteExisting: Bool = true,
        retryConfiguration: VPDownloadRetryConfiguration = .default,
        headers: [String: String] = [:],
        progressHandler: (@Sendable (VPDownloadProgress) -> Void)? = nil
    ) async throws -> URL {
        let destination = VPDownloadDestination(
            directory: directory,
            fileName: fileName,
            overwriteExisting: overwriteExisting
        )
        return try await download(
            from: sourceURL,
            destination: destination,
            retryConfiguration: retryConfiguration,
            headers: headers,
            progressHandler: progressHandler
        )
    }

    private func executeWithRetry<T>(
        retryConfiguration: VPDownloadRetryConfiguration,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var attempt = 1
        var lastError: Error?

        while attempt <= retryConfiguration.maxAttempts {
            do {
                return try await operation()
            } catch {
                if let downloadError = error as? VPDownloadError, !downloadError.isRetryable {
                    throw downloadError
                }
                lastError = error
                if attempt == retryConfiguration.maxAttempts {
                    throw error
                }
                let delay = retryConfiguration.delay(forAttempt: attempt)
                if delay > 0 {
                    try await Task.sleep(nanoseconds: delay)
                }
                attempt += 1
            }
        }
        throw lastError ?? VPDownloadError.invalidResponse
    }

    private func prepareDestinationURL(
        from sourceURL: URL,
        destination: VPDownloadDestination
    ) throws -> URL {
        let directory = destination.directory
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw VPDownloadError.destinationIsNotDirectory(directory)
            }
        } else {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                throw VPDownloadError.failedToPrepareDirectory(directory, underlying: error)
            }
        }

        let resolvedFileName = try resolveFileName(from: sourceURL, customName: destination.fileName)
        return directory.appendingPathComponent(resolvedFileName)
    }

    private func resolveFileName(from sourceURL: URL, customName: String?) throws -> String {
        if let customName {
            let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        let fallback = sourceURL.lastPathComponent
        guard !fallback.isEmpty else {
            throw VPDownloadError.emptyFileName
        }
        return fallback
    }

    private func ensureDestinationWritable(_ url: URL, overwrite: Bool) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        guard overwrite else {
            throw VPDownloadError.destinationExists(url)
        }
    }

    private func persist(
        stream: URLSession.AsyncBytes,
        response: URLResponse,
        to destinationURL: URL,
        overwrite: Bool,
        progressHandler: (@Sendable (VPDownloadProgress) -> Void)?
    ) async throws {
        let expectedLength = response.expectedContentLength >= 0 ? Int(response.expectedContentLength) : nil
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".vp-downloader-\(UUID().uuidString)")

        guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw VPDownloadError.failedToWrite(
                temporaryURL,
                underlying: CocoaError(.fileWriteUnknown)
            )
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: temporaryURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw VPDownloadError.failedToWrite(temporaryURL, underlying: error)
        }

        defer { try? handle.close() }

        var bytesReceived = 0
        var buffer = Data()
        let chunkSize = 64 * 1024
        buffer.reserveCapacity(chunkSize)

        func flushBuffer() throws {
            guard !buffer.isEmpty else { return }
            try handle.write(contentsOf: buffer)
            if let progressHandler {
                let progress = VPDownloadProgress(bytesReceived: bytesReceived, totalBytesExpected: expectedLength)
                progressHandler(progress)
            }
            buffer.removeAll(keepingCapacity: true)
        }

        do {
            for try await byte in stream {
                buffer.append(byte)
                bytesReceived += 1
                if buffer.count >= chunkSize {
                    try flushBuffer()
                }
            }
            try flushBuffer()
            try finalizeDownload(from: temporaryURL, to: destinationURL, overwrite: overwrite)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func finalizeDownload(from temporaryURL: URL, to destinationURL: URL, overwrite: Bool) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            guard overwrite else {
                throw VPDownloadError.destinationExists(destinationURL)
            }
            do {
                try fileManager.removeItem(at: destinationURL)
            } catch {
                throw VPDownloadError.failedToWrite(destinationURL, underlying: error)
            }
        }

        do {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            throw VPDownloadError.failedToWrite(destinationURL, underlying: error)
        }
    }
}
