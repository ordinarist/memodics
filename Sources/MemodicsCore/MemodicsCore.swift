import Foundation

/// Umbrella namespace for the Memodics reading-assistant core library.
///
/// `MemodicsCore` contains all platform-independent, unit-testable logic:
/// text normalization, cache-key generation, the SQLite database layer,
/// persistence services, and the translation-provider abstraction.
///
/// AppKit / SwiftUI / Accessibility code lives in the `Memodics` executable
/// target and depends on this library, keeping UI and macOS-specific APIs
/// isolated from the testable core (SPEC §26).
public enum Memodics {
    /// Semantic version of the core library.
    public static let version = "0.2.0"
}
