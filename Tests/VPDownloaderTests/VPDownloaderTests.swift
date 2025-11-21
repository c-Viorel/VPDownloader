import XCTest
@testable import VPDownloader

final class VPFileDownloaderTests: XCTestCase {
    func testDownloadSucceedsWithCustomFileName() async throws {
        VPURLProtocolStub.reset()
        let downloader = makeDownloader()
        let destinationDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = VPDownloadDestination(directory: destinationDirectory, fileName: "video.bin")
        let url = URL(string: "https://example.com/video.bin")!
        let payload = Data("payload".utf8)
        VPURLProtocolStub.enqueue(.success((response(for: url, status: 200, contentLength: payload.count), payload)))

        let savedURL = try await downloader.download(from: url, destination: destination)
        let fileContents = try Data(contentsOf: savedURL)

        XCTAssertEqual(payload, fileContents)
        XCTAssertEqual(savedURL.lastPathComponent, "video.bin")
    }

    func testDownloadRetriesUntilSuccess() async throws {
        VPURLProtocolStub.reset()
        let downloader = makeDownloader()
        let url = URL(string: "https://example.com/retry.bin")!
        let destinationDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = VPDownloadDestination(directory: destinationDirectory)
        let payload = Data("retry".utf8)

        VPURLProtocolStub.enqueue(.failure(URLError(.timedOut)))
        VPURLProtocolStub.enqueue(.success((response(for: url, status: 200, contentLength: payload.count), payload)))

        let savedURL = try await downloader.download(
            from: url,
            destination: destination,
            retryConfiguration: VPDownloadRetryConfiguration(maxAttempts: 2, backoff: .constant(0))
        )

        let requestCount = VPURLProtocolStub.recordedRequests
        XCTAssertEqual(requestCount, 2)
        let fileContents = try Data(contentsOf: savedURL)
        XCTAssertEqual(payload, fileContents)
    }

    func testDownloadFailsWhenOverwriteDisabledAndFileExists() async throws {
        VPURLProtocolStub.reset()
        let downloader = makeDownloader()
        let url = URL(string: "https://example.com/existing.bin")!
        let destinationDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destinationURL = destinationDirectory.appendingPathComponent("existing.bin")
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: destinationURL)
        let destination = VPDownloadDestination(directory: destinationDirectory, overwriteExisting: false)
        let payload = Data("new".utf8)
        VPURLProtocolStub.enqueue(.success((response(for: url, status: 200, contentLength: payload.count), payload)))

        await XCTAssertThrowsErrorAsync(
            try await downloader.download(from: url, destination: destination)
        ) { error in
            guard case VPDownloadError.destinationExists(let path) = error else {
                return XCTFail("Expected destinationExists, received \(error)")
            }
            XCTAssertEqual(path, destinationURL)
        }
    }

    func testProgressHandlerReceivesUpdates() async throws {
        VPURLProtocolStub.reset()
        let downloader = makeDownloader()
        let url = URL(string: "https://example.com/progress.bin")!
        let destinationDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = VPDownloadDestination(directory: destinationDirectory, fileName: "progress.bin")
        let payload = Data(repeating: 1, count: 4096)
        VPURLProtocolStub.enqueue(.success((response(for: url, status: 200, contentLength: payload.count), payload)))

        let recorder = VPLockedState<[VPDownloadProgress]>([])
        let savedURL = try await downloader.download(from: url, destination: destination) { progress in
            recorder.withLock { $0.append(progress) }
        }

        let events = recorder.withLock { $0 }
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events.last?.bytesReceived, payload.count)
        XCTAssertEqual(events.last?.fractionCompleted, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))
    }

    func testBackgroundInitializerConfiguresIdentifier() {
        let identifier = "com.vpdownloader.tests.background.\(UUID().uuidString)"
        let downloader = VPFileDownloader(backgroundIdentifier: identifier)
        XCTAssertEqual(downloader.configuration.identifier, identifier)
    }

    // MARK: - Helpers

    private func makeDownloader() -> VPFileDownloader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VPURLProtocolStub.self]
        return VPFileDownloader(configuration: configuration)
    }

    private func response(for url: URL, status: Int, contentLength: Int? = nil) -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let contentLength {
            headers["Content-Length"] = String(contentLength)
        }
        return HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
    }
}

// MARK: - URLProtocol Stub

final class VPURLProtocolStub: URLProtocol {
    private static let state = VPLockedState(VPURLProtocolStubState())

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let result = VPURLProtocolStub.state.withLock { state -> Result<(URLResponse, Data), Error>? in
            state.requestCount += 1
            guard !state.queue.isEmpty else { return nil }
            return state.queue.removeFirst()
        }

        guard let client = client else { return }

        guard let result else {
            client.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch result {
        case .success(let payload):
            client.urlProtocol(self, didReceive: payload.0, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: payload.1)
            client.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func enqueue(_ result: Result<(URLResponse, Data), Error>) {
        state.withLock { $0.queue.append(result) }
    }

    static func reset() {
        state.withLock {
            $0.queue.removeAll()
            $0.requestCount = 0
        }
    }

    static var recordedRequests: Int {
        state.withLock { $0.requestCount }
    }
}

private struct VPURLProtocolStubState {
    var queue: [Result<(URLResponse, Data), Error>] = []
    var requestCount = 0
}

private final class VPLockedState<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<R>(_ operation: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return operation(&value)
    }
}

// MARK: - Async Assertion Helper

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
