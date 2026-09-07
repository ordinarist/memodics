import Foundation
import MemodicsCore

/// Owns the database, services, and lookup pipeline for the running app.
///
/// Keeps the local DB in Application Support and rebuilds the translation
/// provider whenever provider settings change. Database, services, and UI stay
/// cleanly separated (SPEC §26); everything is local (SPEC §22).
final class AppEnvironment {

    let database: Database
    let cache: CacheService
    let vocabulary: VocabularyService
    let history: LookupHistoryService
    private(set) var pipeline: LookupPipeline

    private let settings: SettingsStore

    init(settings: SettingsStore) throws {
        self.settings = settings

        let dbURL = try AppEnvironment.databaseURL()
        self.database = try Database(path: dbURL.path)
        self.cache = CacheService(database: database)
        self.vocabulary = VocabularyService(database: database)
        self.history = LookupHistoryService(database: database)
        self.pipeline = AppEnvironment.makePipeline(settings: settings, cache: cache,
                                                    vocabulary: vocabulary, history: history)
    }

    /// Recreate the pipeline with a provider built from current settings.
    func reloadProvider() {
        pipeline = AppEnvironment.makePipeline(settings: settings, cache: cache,
                                               vocabulary: vocabulary, history: history)
    }

    private static func makePipeline(settings: SettingsStore, cache: CacheService,
                                     vocabulary: VocabularyService, history: LookupHistoryService) -> LookupPipeline {
        let provider = LLMTranslationProvider(configuration: settings.providerConfiguration())
        return LookupPipeline(provider: provider, cache: cache, vocabulary: vocabulary, history: history)
    }

    /// `~/Library/Application Support/Memodics/memodics.sqlite`, creating the
    /// directory if needed.
    static func databaseURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Memodics", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("memodics.sqlite")
    }
}
