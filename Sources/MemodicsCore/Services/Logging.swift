import Foundation

/// Severity of a log entry. Ordered so callers can filter by minimum level.
public enum LogLevel: Int, Comparable {
    case debug = 0, info, warning, error

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Fixed-width-ish label used in log lines.
    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

/// A sink for diagnostic log entries. Mockable so the app never needs real disk
/// I/O in tests. Implementations must never throw or crash the caller (SPEC §24).
public protocol Logging {
    func log(_ level: LogLevel, _ message: String)
}

public extension Logging {
    func debug(_ message: String) { log(.debug, message) }
    func info(_ message: String) { log(.info, message) }
    func warning(_ message: String) { log(.warning, message) }
    func error(_ message: String) { log(.error, message) }
}
