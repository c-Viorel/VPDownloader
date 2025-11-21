# VPDownloader

Swift 6 ready downloader that writes any remote file to any folder on Apple platforms. The library ships with retry logic, destination helpers, and batteries-included documentation/tests.

## Highlights
- ✅ Swift Package Manager library using Swift tools 6.2.
- ✅ `VPFileDownloader` handles downloads, validation, disk writes, and cancellations.
- ✅ Fully controllable destinations (`/path/to/folder`, custom names, overwrite rules).
- ✅ Configurable retry strategy with constant or exponential backoff.
- ✅ Thorough unit test coverage with a deterministic `URLProtocol` stub.
- ✅ Global `VPFileDownloader.shared` registry lets you inspect running downloads or share a single session across the app.

## Installation
Add the package from the root of your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/VPDownloader.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "VPDownloader", package: "VPDownloader")
        ]
    )
]
```

## Usage

```swift
import VPDownloader

let downloader = VPFileDownloader()
let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
let destination = VPDownloadDestination(directory: downloadsDirectory, fileName: "Movie.mp4")

let savedURL = try await downloader.download(from: URL(string: "https://example.com/movie.mp4")!,
                                             destination: destination) { progress in
    if let fraction = progress.fractionCompleted {
        print("Download is \(fraction * 100)% complete")
    }
}
print("Saved to", savedURL.path)
```

### Custom Retry Logic

```swift
let retry = VPDownloadRetryConfiguration(
    maxAttempts: 5,
    backoff: .exponential(initial: 0.5, multiplier: 1.5, maximum: 10)
)

try await downloader.download(
    from: fileURL,
    to: downloadsDirectory,
    fileName: "backup.dmg",
    retryConfiguration: retry
)
```

### Tips
- Pass any headers using the `headers` parameter (`Authorization`, `Range`, etc.).
- Inspect download progress via the closure or observe `bytesReceived`/`fractionCompleted` to drive UI updates.
- Use multiple downloader instances with custom `URLSessionConfiguration` for background or ephemeral sessions.
- Share a single downloader across the app with `VPFileDownloader.shared`, and drive list UIs by calling `await downloader.activeDownloadsList()` to inspect/manage all active transfers.
- Detect `VPDownloadError.destinationExists` to prompt the user before overwriting files.

### Background Sessions

Create a downloader backed by `URLSessionConfiguration.background` with one line:

```swift
let backgroundDownloader = VPFileDownloader(
    backgroundIdentifier: "com.yourcompany.app.downloads",
    sharedContainerIdentifier: "group.com.yourcompany.shared"
)
```

Schedule downloads the same way—Swift Concurrency awaits completion while still allowing the OS to optimize transfers when your app is suspended.


## Testing

The package ships with unit tests powered by a deterministic `URLProtocol` stub. Run them anytime with:

```bash
swift test
```
