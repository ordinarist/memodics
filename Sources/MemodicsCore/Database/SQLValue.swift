import Foundation

/// A bindable SQLite value used by the typed database helpers.
public enum SQLValue {
    case int(Int64)
    case double(Double)
    case text(String)
    case null

    public static func int(_ value: Int) -> SQLValue { .int(Int64(value)) }

    /// Convenience for optional text (maps `nil` to SQL NULL).
    public static func text(_ value: String?) -> SQLValue {
        value.map { .text($0) } ?? .null
    }
}
