import Foundation

/// Appends leveled, timestamped log lines to a file on disk, with a single
/// size-based rollover. All work is serialized on a private queue and every
/// failure is swallowed — logging must never affect app behavior (SPEC §24).
public final class FileLogger: Logging {

    private let fileURL: URL
    private let rolledURL: URL
    private let minimumLevel: LogLevel
    private let maxBytes: Int
    private let queue = DispatchQueue(label: "com.memodics.filelogger")
    private let dateProvider: () -> Date

    public init(fileURL: URL,
                minimumLevel: LogLevel = .info,
                maxBytes: Int = 2 * 1024 * 1024,
                dateProvider: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.rolledURL = URL(fileURLWithPath: fileURL.path + ".1")
        self.minimumLevel = minimumLevel
        self.maxBytes = maxBytes
        self.dateProvider = dateProvider
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
    }

    public func log(_ level: LogLevel, _ message: String) {
        guard level >= minimumLevel else { return }
        let line = "[\(timestamp())] [\(level.label)] \(message)\n"
        queue.sync {
            rotateIfNeeded()
            append(line)
        }
    }

    // MARK: - Private

    private lazy var formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func timestamp() -> String {
        formatter.string(from: dateProvider())
    }

    private func rotateIfNeeded() {
        let fm = FileManager.default
        guard let size = try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
              size >= maxBytes else { return }
        try? fm.removeItem(at: rolledURL)
        try? fm.moveItem(at: fileURL, to: rolledURL)
    }

    private func append(_ line: String) {
        let fm = FileManager.default
        guard let data = line.data(using: .utf8) else { return }
        // Ensure the directory exists (nested paths, first write).
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if fm.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
