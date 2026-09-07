import SwiftUI
import MemodicsCore

/// View model backing the translation popup. Marking a word understood updates
/// the popup live (highlight removed) and persists via the injected callback.
@MainActor
final class PopupViewModel: ObservableObject {
    @Published var original: String
    @Published var translation: String
    @Published var vocabulary: [LookupVocabulary]
    let servedFromCache: Bool

    /// Links original + translation scrolling (SPEC §14).
    let scrollSync = ScrollSyncController()

    private let onMarkUnderstood: (VocabularyItem) -> Void

    init(outcome: LookupOutcome, onMarkUnderstood: @escaping (VocabularyItem) -> Void) {
        self.original = outcome.originalText
        self.translation = outcome.translation
        self.vocabulary = outcome.vocabulary
        self.servedFromCache = outcome.servedFromCache
        self.onMarkUnderstood = onMarkUnderstood
    }

    func markUnderstood(_ entry: LookupVocabulary) {
        onMarkUnderstood(entry.item)
        // Reflect immediately: understood → no highlight (SPEC §11, §13).
        vocabulary = vocabulary.map { v in
            guard v.item.id == entry.item.id else { return v }
            var updatedItem = v.item
            updatedItem.status = .understood
            return LookupVocabulary(item: updatedItem, surfaceForm: v.surfaceForm,
                                    meaning: v.meaning, highlightLevel: 0)
        }
    }
}

/// The floating translation popup. SPEC §14: original text (with highlighted
/// vocabulary), translation, vocabulary analysis + lookup counts, and the
/// ability to mark vocabulary as understood.
struct PopupView: View {
    @ObservedObject var model: PopupViewModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Memodics").font(.headline)
                if model.servedFromCache {
                    Text("cached").font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }

            sectionLabel("Selected text")
            SyncableTextView(text: model.original,
                             matches: AttributedHighlighter.originalMatches(model.vocabulary),
                             controller: model.scrollSync)
                .frame(height: 92)
                .background(sectionBackground)

            sectionLabel("Translation")
            SyncableTextView(text: model.translation,
                             matches: AttributedHighlighter.translationMatches(model.vocabulary),
                             controller: model.scrollSync)
                .frame(height: 92)
                .background(sectionBackground)

            if !model.vocabulary.isEmpty {
                sectionLabel("Vocabulary")
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.vocabulary, id: \.item.id) { entry in
                            vocabularyRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 190)
            }
        }
        .padding(14)
        .frame(width: 380)
    }

    @ViewBuilder
    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06))
    }

    @ViewBuilder
    private func vocabularyRow(_ entry: LookupVocabulary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(entry.highlightLevel > 0
                      ? HighlightPalette.swiftUIColor(forLevel: entry.highlightLevel)
                      : Color.secondary.opacity(0.3))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.item.lemma).fontWeight(.medium)
                    Text("× \(entry.item.lookupCount)").font(.caption).foregroundStyle(.secondary)
                }
                if !entry.meaning.isEmpty {
                    Text(entry.meaning).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if entry.item.status == .understood {
                Label("Understood", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly).foregroundStyle(.green)
            } else {
                Button("Mark understood") { model.markUnderstood(entry) }
                    .font(.caption).buttonStyle(.borderless)
            }
        }
    }
}
