import AppKit
import VPDownloader

/// Simple demonstration controller showing two downloads with progress.
@MainActor
final class ViewController: NSViewController {
    private enum DownloadItem {
        case current
        case previous

        var url: URL {
            switch self {
            case .current:
                return URL(string: "https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/jquery-speedtest/100MB.txt")!
            case .previous:
                return URL(string: "https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/jquery-speedtest/100MB.txt")!
            }
        }
        

        var title: String {
            switch self {
            case .current: return "Download 1"
            case .previous: return "Download 2"
            }
        }
    }

    private let downloader = VPFileDownloader.shared
    private var tasks: [DownloadItem: Task<Void, Never>] = [:]

    private let stackView = NSStackView()
    private let statusLabelCurrent = NSTextField(labelWithString: "Idle")
    private let statusLabelPrevious = NSTextField(labelWithString: "Idle")
    private let progressCurrent = NSProgressIndicator()
    private let progressPrevious = NSProgressIndicator()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureStackView()
        configureRow(
            for: .current,
            progress: progressCurrent,
            statusLabel: statusLabelCurrent
        )
        configureRow(
            for: .previous,
            progress: progressPrevious,
            statusLabel: statusLabelPrevious
        )
        let logButton = NSButton(title: "Log Active Downloads", target: self, action: #selector(logActiveDownloads))
        logButton.bezelStyle = .rounded
        stackView.addArrangedSubview(logButton)
    }

    override var representedObject: Any? {
        didSet { }
    }

    // MARK: - UI Construction

    private func configureStackView() {
        stackView.orientation = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 24)
        ])
    }

    private func configureRow(
        for item: DownloadItem,
        progress: NSProgressIndicator,
        statusLabel: NSTextField
    ) {
        let button = NSButton(title: item.title, target: self, action: #selector(startDownload(_:)))
        button.tag = tag(for: item)
        button.bezelStyle = .rounded

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor

        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.doubleValue = 0

        let column = NSStackView(views: [button, progress, statusLabel])
        column.orientation = .vertical
        column.spacing = 8

        stackView.addArrangedSubview(column)
    }

    private func tag(for item: DownloadItem) -> Int {
        switch item {
        case .current: return 101
        case .previous: return 102
        }
    }

    private func item(for tag: Int) -> DownloadItem? {
        switch tag {
        case 101: return .current
        case 102: return .previous
        default: return nil
        }
    }

    // MARK: - Actions

    @objc
    private func startDownload(_ sender: NSButton) {
        guard let item = item(for: sender.tag) else { return }
        let targetProgress = item == .current ? progressCurrent : progressPrevious
        let targetLabel = item == .current ? statusLabelCurrent : statusLabelPrevious
        tasks[item]?.cancel()

        targetProgress.doubleValue = 0
        targetLabel.stringValue = "Starting…"

        let destinationFolder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!

        tasks[item] = Task { [weak self] in
            guard let self else { return }
            do {
                let savedURL = try await downloader.download(
                    from: item.url,
                    to: destinationFolder,
                    progressHandler: { progress in
                        DispatchQueue.main.async {
                            targetProgress.doubleValue = progress.fractionCompleted ?? 0
                            let received = ByteCountFormatter.string(fromByteCount: Int64(progress.bytesReceived), countStyle: .file)
                            if let expected = progress.totalBytesExpected {
                                let total = ByteCountFormatter.string(fromByteCount: Int64(expected), countStyle: .file)
                                targetLabel.stringValue = "Downloading \(received) / \(total)"
                            } else {
                                targetLabel.stringValue = "Downloading \(received)…"
                            }
                        }
                    }
                )

                DispatchQueue.main.async {
                    targetProgress.doubleValue = 1
                    targetLabel.stringValue = "Saved to Desktop as \(savedURL.lastPathComponent)"
                }
            } catch is CancellationError {
                DispatchQueue.main.async {
                    targetLabel.stringValue = "Cancelled"
                    targetProgress.doubleValue = 0
                }
            } catch {
                DispatchQueue.main.async {
                    targetLabel.stringValue = "Failed: \(error.localizedDescription)"
                    targetProgress.doubleValue = 0
                }
            }
        }
    }

    @objc
    private func logActiveDownloads() {
        Task {
            let downloads = await downloader.activeDownloadsList()
            if downloads.isEmpty {
                NSLog("No active downloads")
            } else {
                for download in downloads {
                    NSLog("Active download \(download.identifier): \(download.source.lastPathComponent) -> \(download.destination.path)")
                }
            }
        }
    }
}
