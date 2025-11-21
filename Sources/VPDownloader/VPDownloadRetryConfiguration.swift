import Foundation

/// Controls retry behaviour for downloads.
public struct VPDownloadRetryConfiguration: Sendable {
    public enum Backoff: Sendable {
        case none
        case constant(TimeInterval)
        case exponential(initial: TimeInterval, multiplier: Double, maximum: TimeInterval)
    }

    public let maxAttempts: Int
    public let backoff: Backoff

    /// - Parameters:
    ///   - maxAttempts: Total attempts (initial try + retries). Must be >= 1.
    ///   - backoff: Strategy used between retries. Defaults to exponential backoff.
    public init(maxAttempts: Int = 3, backoff: Backoff = .exponential(initial: 0.5, multiplier: 2, maximum: 8)) {
        precondition(maxAttempts >= 1, "Retry attempts must be at least 1.")
        self.maxAttempts = maxAttempts
        self.backoff = backoff
    }

    public static let `default` = VPDownloadRetryConfiguration()

    func delay(forAttempt attempt: Int) -> UInt64 {
        guard attempt < maxAttempts else { return 0 }

        let seconds: TimeInterval
        switch backoff {
        case .none:
            seconds = 0
        case .constant(let value):
            seconds = max(0, value)
        case .exponential(let initial, let multiplier, let maximum):
            let exponent = max(0, attempt - 1)
            let computed = initial * pow(multiplier, Double(exponent))
            seconds = min(max(computed, 0), maximum)
        }

        guard seconds > 0 else { return 0 }
        return UInt64(seconds * 1_000_000_000)
    }
}
