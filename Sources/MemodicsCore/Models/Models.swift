import Foundation

/// Learning state of a vocabulary item. SPEC §11.
public enum VocabularyStatus: String, Codable, Sendable {
    case learning
    case understood
}

/// Common European Framework of Reference level of a vocabulary item. SPEC §16.
public enum CEFRLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case a1, a2, b1, b2, c1, c2

    /// Ordered by CaseIterable ordinal: a1 < a2 < … < c2.
    public static func < (lhs: CEFRLevel, rhs: CEFRLevel) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    /// Tolerant parse: lowercases/trims input; unknown → nil.
    public init?(loose raw: String) {
        self.init(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

/// Category of a vocabulary unit. SPEC §16. Multi-word units (phrasal verbs,
/// idioms, collocations) are first-class and must not be split into words.
public enum VocabularyType: String, Codable, Sendable {
    case word
    case phrase
    case phrasalVerb = "phrasal_verb"
    case idiom
    case collocation
    case conjunction   // conjunctions / discourse connectives (e.g. "nevertheless")
}

public extension VocabularyType {
    /// Display ordering for the popup: single dictionary headwords first,
    /// then multi-word units, then connectives. SPEC §9 ranking.
    var displayRank: Int {
        switch self {
        case .word: return 0
        case .phrase, .phrasalVerb, .idiom, .collocation: return 1
        case .conjunction: return 2
        }
    }
}

/// A canonical, learnable vocabulary item. SPEC §16.
public struct VocabularyItem: Equatable, Sendable {
    public var id: Int64
    public var lemma: String
    public var type: VocabularyType
    public var meaning: String
    public var translation: String
    public var lookupCount: Int
    public var status: VocabularyStatus
    public var firstSeenAt: Date
    public var lastSeenAt: Date
    public var cefr: CEFRLevel?

    public init(id: Int64, lemma: String, type: VocabularyType, meaning: String,
                translation: String, lookupCount: Int, status: VocabularyStatus,
                firstSeenAt: Date, lastSeenAt: Date, cefr: CEFRLevel? = nil) {
        self.id = id
        self.lemma = lemma
        self.type = type
        self.meaning = meaning
        self.translation = translation
        self.lookupCount = lookupCount
        self.status = status
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.cefr = cefr
    }
}

/// A cached translation of a normalized sentence/selection. SPEC §15.
public struct SentenceCacheEntry: Equatable, Sendable {
    public var id: Int64
    public var textHash: String
    public var normalizedText: String
    public var translation: String
    public var analysisJSON: String
    public var createdAt: Date
    public var lastUsedAt: Date

    public init(id: Int64, textHash: String, normalizedText: String, translation: String,
                analysisJSON: String, createdAt: Date, lastUsedAt: Date) {
        self.id = id
        self.textHash = textHash
        self.normalizedText = normalizedText
        self.translation = translation
        self.analysisJSON = analysisJSON
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

/// A single lookup event, preserving what the user actually encountered. SPEC §17.
public struct Lookup: Equatable, Sendable {
    public var id: Int64
    public var selectedText: String
    public var normalizedText: String
    public var sourceApplication: String?
    public var context: String?
    public var translation: String
    public var createdAt: Date

    public init(id: Int64, selectedText: String, normalizedText: String,
                sourceApplication: String?, context: String?, translation: String,
                createdAt: Date) {
        self.id = id
        self.selectedText = selectedText
        self.normalizedText = normalizedText
        self.sourceApplication = sourceApplication
        self.context = context
        self.translation = translation
        self.createdAt = createdAt
    }
}

/// A concrete appearance of a vocabulary item inside a lookup. SPEC §18.
public struct VocabularyOccurrence: Equatable, Sendable {
    public var id: Int64
    public var vocabularyId: Int64
    public var lookupId: Int64
    public var surfaceForm: String
    public var context: String?
    public var createdAt: Date

    public init(id: Int64, vocabularyId: Int64, lookupId: Int64, surfaceForm: String,
                context: String?, createdAt: Date) {
        self.id = id
        self.vocabularyId = vocabularyId
        self.lookupId = lookupId
        self.surfaceForm = surfaceForm
        self.context = context
        self.createdAt = createdAt
    }
}
