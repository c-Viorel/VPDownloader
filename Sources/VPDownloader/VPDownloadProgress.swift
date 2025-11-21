import Foundation

/// Reports ongoing download progress.
public struct VPDownloadProgress: Sendable {
    public let bytesReceived: Int
    public let totalBytesExpected: Int?

    public init(bytesReceived: Int, totalBytesExpected: Int?) {
        self.bytesReceived = bytesReceived
        self.totalBytesExpected = totalBytesExpected
    }

    /// Ratio between 0 and 1 when the total byte count is known.
    public var fractionCompleted: Double? {
        guard let totalBytesExpected, totalBytesExpected > 0 else {
            return nil
        }
        guard totalBytesExpected >= bytesReceived else {
            return 1
        }
        return Double(bytesReceived) / Double(totalBytesExpected)
    }
}
