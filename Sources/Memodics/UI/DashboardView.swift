import SwiftUI
import MemodicsCore

/// Backs the dashboard, reading vocabulary and history from the services with
/// search, status filtering, and paged loading (SPEC §19).
@MainActor
final class DashboardViewModel: ObservableObject {

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all, learning, understood
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var status: VocabularyStatus? {
            switch self {
            case .all: return nil
            case .learning: return .learning
            case .understood: return .understood
            }
        }
    }

    @Published var query = ""
    @Published var statusFilter: StatusFilter = .all
    @Published var items: [VocabularyItem] = []
    @Published var total = 0
    @Published var selectedID: Int64?
    @Published var occurrences: [VocabularyOccurrence] = []
    @Published var levelEstimate: EnglishLevelEstimate?
    @Published var cefrCounts: [CEFRLevel: (understood: Int, learning: Int)] = [:]

    private let pageSize = 50
    private let environment: AppEnvironment

    init(environment: AppEnvironment) { self.environment = environment }

    var selectedItem: VocabularyItem? { items.first { $0.id == selectedID } }
    var canLoadMore: Bool { items.count < total }

    /// Reload from the first page using the current query/filter. With
    /// `keepingLoaded`, re-fetch as many rows as are currently loaded so the
    /// list doesn't collapse back to page 1 after an in-place change.
    func reload(keepingLoaded: Bool = false) {
        let status = statusFilter.status
        let limit = keepingLoaded ? max(pageSize, items.count) : pageSize
        total = (try? environment.vocabulary.count(matching: query, status: status)) ?? 0
        items = (try? environment.vocabulary.search(query, status: status, limit: limit, offset: 0)) ?? []
        if selectedID == nil || !items.contains(where: { $0.id == selectedID }) {
            selectedID = items.first?.id
        }
        loadOccurrences()
        let counts = (try? environment.vocabulary.vocabularyCountsByCEFR()) ?? [:]
        cefrCounts = counts
        let understood = counts.mapValues(\.understood)
        levelEstimate = EnglishLevelEstimator.estimate(understoodByLevel: understood)
    }

    /// Append the next page (pagination for large vocabularies, SPEC §19).
    func loadMore() {
        let status = statusFilter.status
        let next = (try? environment.vocabulary.search(query, status: status,
                                                       limit: pageSize, offset: items.count)) ?? []
        items.append(contentsOf: next)
    }

    func select(_ id: Int64?) {
        selectedID = id
        loadOccurrences()
    }

    func loadOccurrences() {
        guard let id = selectedID else { occurrences = []; return }
        occurrences = (try? environment.history.occurrences(forVocabularyId: id)) ?? []
    }

    func markUnderstood(_ id: Int64) {
        try? environment.vocabulary.markUnderstood(id: id)
        reloadKeepingPosition(after: id)
    }

    func markLearning(_ id: Int64) {
        try? environment.vocabulary.markLearning(id: id)
        reloadKeepingPosition(after: id)
    }

    /// Refresh after a status change without resetting pagination. If the item
    /// dropped out of the filtered list, select its neighbour instead of the first row.
    private func reloadKeepingPosition(after id: Int64) {
        let oldIndex = items.firstIndex { $0.id == id }
        let wasSelected = selectedID == id
        reload(keepingLoaded: true)
        if wasSelected, !items.contains(where: { $0.id == id }), let i = oldIndex, !items.isEmpty {
            selectedID = items[min(i, items.count - 1)].id
            loadOccurrences()
        }
    }
}

/// Vocabulary dashboard: searchable/filterable list + detail with historical
/// contexts. SPEC §19.
struct DashboardView: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let item = model.selectedItem {
                detail(item)
            } else {
                ContentUnavailableView("No vocabulary yet",
                                       systemImage: "text.book.closed",
                                       description: Text("Look up some English text to start building your vocabulary."))
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .onAppear { model.reload() }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            levelCard
            Picker("", selection: $model.statusFilter) {
                ForEach(DashboardViewModel.StatusFilter.allCases) { f in
                    Text(f.title).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            .onChange(of: model.statusFilter) { _, _ in model.reload() }

            List(selection: Binding(get: { model.selectedID }, set: { model.select($0) })) {
                ForEach(model.items, id: \.id) { item in
                    row(item).tag(item.id)
                }
                if model.canLoadMore {
                    Button("Load more (\(model.items.count) of \(model.total))") { model.loadMore() }
                        .buttonStyle(.borderless)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .overlay(alignment: .bottom) {
                Text("\(model.total) item\(model.total == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(4)
            }
        }
        .frame(minWidth: 280)
        .searchable(text: $model.query, placement: .sidebar, prompt: "Search word or meaning")
        .onChange(of: model.query) { _, _ in model.reload() }
        .navigationTitle("Vocabulary")
    }

    @ViewBuilder
    private var levelCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your English level").font(.headline)
            if let est = model.levelEstimate, let level = est.level {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(level.rawValue.uppercased()).font(.system(size: 34, weight: .bold))
                    Text("confidence: \(est.confidence.rawValue)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Keep looking up words to estimate your level.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            cefrChart
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        .padding(12)
    }

    @ViewBuilder
    private var cefrChart: some View {
        let maxCount = max(1, model.cefrCounts.values.map { $0.understood + $0.learning }.max() ?? 1)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(CEFRLevel.allCases, id: \.self) { band in
                let c = model.cefrCounts[band] ?? (understood: 0, learning: 0)
                VStack(spacing: 2) {
                    ZStack(alignment: .bottom) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                            .frame(width: 18, height: 60)
                        VStack(spacing: 0) {
                            Capsule().fill(Color.orange.opacity(0.7))
                                .frame(width: 18, height: 60 * CGFloat(c.learning) / CGFloat(maxCount))
                            Capsule().fill(Color.green.opacity(0.8))
                                .frame(width: 18, height: 60 * CGFloat(c.understood) / CGFloat(maxCount))
                        }
                    }
                    Text(band.rawValue.uppercased()).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: VocabularyItem) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.lemma).fontWeight(.medium)
                Text(item.type.rawValue).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(item.lookupCount)").monospacedDigit().foregroundStyle(.secondary)
            statusBadge(item.status)
        }
    }

    @ViewBuilder
    private func detail(_ item: VocabularyItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(item.lemma).font(.largeTitle.bold())
                    statusBadge(item.status)
                    Spacer()
                    if item.status == .understood {
                        Button("Mark as learning") { model.markLearning(item.id) }
                    } else {
                        Button("Mark as understood") { model.markUnderstood(item.id) }
                            .buttonStyle(.borderedProminent)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    GridRow { Text("Meaning").foregroundStyle(.secondary); Text(item.meaning) }
                    GridRow { Text("Type").foregroundStyle(.secondary); Text(item.type.rawValue) }
                    GridRow { Text("Lookups").foregroundStyle(.secondary); Text("\(item.lookupCount)") }
                    GridRow { Text("First seen").foregroundStyle(.secondary); Text(item.firstSeenAt.formatted()) }
                    GridRow { Text("Last seen").foregroundStyle(.secondary); Text(item.lastSeenAt.formatted()) }
                }

                Divider()
                Text("Contexts").font(.headline)
                if model.occurrences.isEmpty {
                    Text("No recorded contexts yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(model.occurrences, id: \.id) { occ in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(occ.context ?? occ.surfaceForm)
                            Text(occ.createdAt.formatted()).font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                    }
                }
                Spacer()
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: VocabularyStatus) -> some View {
        Text(status.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(status == .understood ? Color.green.opacity(0.2) : Color.blue.opacity(0.2)))
    }
}
