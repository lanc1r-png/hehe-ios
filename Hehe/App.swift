import SwiftUI
import AVKit
import AVFoundation
import Foundation
import WebKit

// MARK: - Тема и общие элементы дизайна

enum Theme {
    static let accent = Color(red: 0.66, green: 0.48, blue: 1.0)
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Theme.accent.opacity(0.35), .clear],
                           center: .topLeading, startRadius: 20, endRadius: 460)
            RadialGradient(colors: [Color.pink.opacity(0.18), .clear],
                           center: .bottomTrailing, startRadius: 20, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Material.ultraThinMaterial), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct Pill: View {
    let icon: String
    let text: String
    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

/// Раскладка «теги в несколько строк».
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX && x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Models

struct Envelope<T: Decodable>: Decodable {
    let data: T
    let meta: PageMeta?
}

struct PageMeta: Decodable {
    let hasNextPage: Bool?
    let currentPage: Int?

    enum CodingKeys: String, CodingKey {
        case hasNextPage = "has_next_page"
        case currentPage = "current_page"
    }
}

struct NamedItem: Codable, Hashable {
    let id: Int?
    let name: String?
    let label: String?
    var title: String { name ?? label ?? "" }

    enum CodingKeys: String, CodingKey { case id, name, label }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id))
            ?? (try? c.decode(String.self, forKey: .id)).flatMap { Int($0) }
        name = try? c.decode(String.self, forKey: .name)
        label = try? c.decode(String.self, forKey: .label)
    }
}

struct RichNode: Decodable {
    let type: String?
    let text: String?
    let content: [RichNode]?

    var plainText: String {
        if type == "text" { return text ?? "" }
        let inner = (content ?? []).map { $0.plainText }.joined()
        switch type {
        case "paragraph", "heading": return inner + "\n"
        case "hardBreak": return "\n"
        default: return inner
        }
    }
}

struct RichText: Decodable {
    let text: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            text = s
        } else if let node = try? c.decode(RichNode.self) {
            text = node.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            text = ""
        }
    }
}

struct Cover: Codable, Hashable {
    let thumbnail: String?
    let `default`: String?
    let md: String?
}

struct Anime: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let rusName: String?
    let engName: String?
    let slugUrl: String?
    let cover: Cover?
    let summary: String?
    let genres: [NamedItem]?
    let authors: [NamedItem]?
    let otherNames: [String]?
    let episodesCount: Int?
    let rateAvg: String?
    let status: NamedItem?
    let type: NamedItem?
    let ageRestriction: NamedItem?
    let releaseDateString: String?

    var displayTitle: String {
        if let r = rusName, !r.isEmpty { return r }
        return name ?? engName ?? "Без названия"
    }
    var imageURL: URL? {
        let s = cover?.thumbnail ?? cover?.md ?? cover?.default
        return s.flatMap(URL.init(string:))
    }

    enum CodingKeys: String, CodingKey {
        case id, name, summary, genres, authors, cover, status, type
        case rusName = "rus_name"
        case engName = "eng_name"
        case slugUrl = "slug_url"
        case otherNames
        case episodesCount = "episodes_count"
        case rateAvg = "rate_avg"
        case ageRestriction
        case releaseDateString
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try? c.decode(String.self, forKey: .name)
        rusName = try? c.decode(String.self, forKey: .rusName)
        engName = try? c.decode(String.self, forKey: .engName)
        slugUrl = try? c.decode(String.self, forKey: .slugUrl)
        cover = try? c.decode(Cover.self, forKey: .cover)
        summary = (try? c.decode(RichText.self, forKey: .summary))?.text
        genres = try? c.decode([NamedItem].self, forKey: .genres)
        authors = try? c.decode([NamedItem].self, forKey: .authors)
        otherNames = try? c.decode([String].self, forKey: .otherNames)
        episodesCount = try? c.decode(Int.self, forKey: .episodesCount)
        status = try? c.decode(NamedItem.self, forKey: .status)
        type = try? c.decode(NamedItem.self, forKey: .type)
        ageRestriction = try? c.decode(NamedItem.self, forKey: .ageRestriction)
        releaseDateString = try? c.decode(String.self, forKey: .releaseDateString)
        if let s = try? c.decode(String.self, forKey: .rateAvg) { rateAvg = s }
        else if let d = try? c.decode(Double.self, forKey: .rateAvg) { rateAvg = String(format: "%.1f", d) }
        else { rateAvg = nil }
    }
}

struct EpisodeShort: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let number: String?
    let season: String?
    let date: String?

    var title: String {
        let n = number.map { "Серия \($0)" } ?? "Серия"
        if let name, !name.isEmpty { return "\(n) · \(name)" }
        return n
    }

    enum CodingKeys: String, CodingKey { case id, name, number, season, date = "created_at" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try? c.decode(String.self, forKey: .name)
        season = (try? c.decode(String.self, forKey: .season))
            ?? (try? c.decode(Int.self, forKey: .season)).map(String.init)
        number = (try? c.decode(String.self, forKey: .number))
            ?? (try? c.decode(Int.self, forKey: .number)).map(String.init)
        date = try? c.decode(String.self, forKey: .date)
    }
}

struct VideoQuality: Decodable, Hashable {
    let href: String?
    let quality: Int?
}

struct VideoInfo: Decodable, Hashable {
    let quality: [VideoQuality]?
}

struct SubtitleInfo: Decodable, Hashable {
    let src: String?
    let format: String?
}

struct Team: Decodable, Hashable {
    let name: String?
}

struct EpisodePlayer: Decodable, Hashable {
    let id: Int?
    let player: String?
    let team: Team?
    let translationType: NamedItem?
    let video: VideoInfo?
    let subtitles: [SubtitleInfo]?
    let src: String?

    var isNative: Bool { (player ?? "").lowercased() == "animelib" }
    var label: String {
        let t = team?.name ?? "—"
        let k = translationType?.title ?? ""
        return k.isEmpty ? t : "\(t) (\(k))"
    }

    enum CodingKeys: String, CodingKey {
        case id, player, team, video, subtitles, src
        case translationType = "translation_type"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try? c.decode(Int.self, forKey: .id)
        player = try? c.decode(String.self, forKey: .player)
        team = try? c.decode(Team.self, forKey: .team)
        translationType = try? c.decode(NamedItem.self, forKey: .translationType)
        video = try? c.decode(VideoInfo.self, forKey: .video)
        subtitles = try? c.decode([SubtitleInfo].self, forKey: .subtitles)
        src = try? c.decode(String.self, forKey: .src)
    }
}

struct EpisodeDetail: Decodable {
    let id: Int
    let players: [EpisodePlayer]?
}

struct VideoServer: Decodable, Hashable {
    let id: String?
    let label: String?
    let url: String?
}

struct Constants: Decodable {
    let videoServers: [VideoServer]?
}

struct PlayableVariant: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let url: URL
    let subtitle: URL?
    var isWeb = false
}

struct FilterOptions {
    var genres: [NamedItem] = []
    var tags: [NamedItem] = []
    var types: [NamedItem] = []
    var statuses: [NamedItem] = []
    var isEmpty: Bool { genres.isEmpty && tags.isEmpty && types.isEmpty && statuses.isEmpty }
}

// MARK: - API
enum APIError: LocalizedError {
    case badURL, http(Int, String), noVideo
    var errorDescription: String? {
        switch self {
        case .badURL: return "Некорректный адрес запроса"
        case .http(let c, let body): return "Сервер вернул ошибку \(c): \(body)"
        case .noVideo: return "Для этой серии нет доступного видео"
        }
    }
}

struct CatalogFilter: Equatable {
    var query: String = ""
    var sortBy: SortOption = .rating
    var genres: Set<Int> = []
    var tags: Set<Int> = []
    var types: Set<Int> = []
    var statuses: Set<Int> = []

    var activeCount: Int { genres.count + tags.count + types.count + statuses.count }

    enum SortOption: String, CaseIterable, Identifiable {
        case rating = "rate_avg"
        case views = "views"
        case newest = "created_at"
        case lastEpisode = "last_episode_at"
        case name = "name"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .rating: return "По рейтингу"
            case .views: return "По просмотрам"
            case .newest: return "Новинки"
            case .lastEpisode: return "Свежие серии"
            case .name: return "По названию"
            }
        }
    }
}

actor AnimelibAPI {
    static let shared = AnimelibAPI()

    private let apiURL = "https://api.cdnlibs.org/api"
    private let session: URLSession
    private let decoder = JSONDecoder()
    private var cachedServers: [VideoServer]?

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        session = URLSession(configuration: cfg)
    }

    nonisolated var playbackHeaders: [String: String] {
        ["Referer": "https://v5.animelib.org/", "Origin": "https://v5.animelib.org"]
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        guard var comps = URLComponents(string: apiURL + path) else { throw APIError.badURL }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError.badURL }
        var req = URLRequest(url: url)
        for (k, v) in playbackHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, body)
        }
        return try decoder.decode(T.self, from: data)
    }

    func catalog(filter: CatalogFilter, page: Int) async throws -> (items: [Anime], hasNext: Bool) {
        do {
            return try await fetchCatalog(filter: filter, page: page, withSite: true)
        } catch APIError.http(let code, _) where code == 422 {
            return try await fetchCatalog(filter: filter, page: page, withSite: false)
        }
    }

    private func fetchCatalog(filter: CatalogFilter, page: Int, withSite: Bool) async throws -> (items: [Anime], hasNext: Bool) {
        var q: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "sort_by", value: filter.sortBy.rawValue),
            .init(name: "sort_type", value: "desc"),
        ]
        if withSite { q.append(.init(name: "site_id[]", value: "5")) }
        let text = filter.query.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { q.append(.init(name: "q", value: text)) }
        for id in filter.genres.sorted() { q.append(.init(name: "genres[]", value: String(id))) }
        for id in filter.tags.sorted() { q.append(.init(name: "tags[]", value: String(id))) }
        for id in filter.types.sorted() { q.append(.init(name: "types[]", value: String(id))) }
        for id in filter.statuses.sorted() { q.append(.init(name: "status[]", value: String(id))) }
        let r = try await get("/anime", query: q, as: Envelope<[Anime]>.self)
        let hasNext = r.meta?.hasNextPage ?? !r.data.isEmpty
        return (r.data, hasNext)
    }

    /// Списки жанров, тегов, типов и статусов берём у сайта.
    func filterOptions() async -> FilterOptions {
        var o = FilterOptions()
        o.genres = await constantList("genres", keys: ["genres"])
        o.tags = await constantList("tags", keys: ["tags"])
        o.types = await constantList("types", keys: ["types", "type"])
        o.statuses = await constantList("status", keys: ["status", "statuses"])
        return o
    }

    private func constantList(_ field: String, keys: [String]) async -> [NamedItem] {
        let q = [URLQueryItem(name: "fields[]", value: field)]
        guard let dict = try? await get("/constants", query: q, as: Envelope<[String: [NamedItem]]>.self).data else {
            return []
        }
        var list: [NamedItem] = []
        for k in keys {
            if let v = dict[k] { list = v; break }
        }
        if list.isEmpty { list = dict.values.first ?? [] }
        return list.filter { $0.id != nil && !$0.title.isEmpty }
    }

    func rawText(_ path: String, query: [URLQueryItem] = []) async -> String {
        guard var comps = URLComponents(string: apiURL + path) else { return "bad url" }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { return "bad url" }
        var req = URLRequest(url: url)
        for (k, v) in playbackHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return "HTTP \(code)\n" + (String(data: data.prefix(1800), encoding: .utf8) ?? "")
        } catch {
            return "Ошибка: \(error.localizedDescription)"
        }
    }

    func details(slug: String) async throws -> Anime {
        let base = ["summary", "genres", "authors", "otherNames"]
        func query(_ f: [String]) -> [URLQueryItem] { f.map { URLQueryItem(name: "fields[]", value: $0) } }
        do {
            return try await get("/anime/\(slug)", query: query(base + ["rate_avg"]), as: Envelope<Anime>.self).data
        } catch {
            return try await get("/anime/\(slug)", query: query(base), as: Envelope<Anime>.self).data
        }
    }

    func episodes(animeID: Int) async throws -> [EpisodeShort] {
        let q = [URLQueryItem(name: "anime_id", value: String(animeID))]
        return try await get("/episodes", query: q, as: Envelope<[EpisodeShort]>.self).data
    }

    func episodeDetail(id: Int) async throws -> EpisodeDetail {
        try await get("/episodes/\(id)", as: Envelope<EpisodeDetail>.self).data
    }

    private func videoServers() async throws -> [VideoServer] {
        if let c = cachedServers { return c }
        let q = [URLQueryItem(name: "fields[]", value: "videoServers")]
        let c = try await get("/constants", query: q, as: Envelope<Constants>.self).data
        let s = c.videoServers ?? []
        cachedServers = s
        return s
    }

    func variants(episodeID: Int) async throws -> [PlayableVariant] {
        async let detailTask = episodeDetail(id: episodeID)
        async let serversTask = videoServers()
        let detail = try await detailTask
        let base: String? = (try? await serversTask)?.first?.url

        var native: [PlayableVariant] = []
        var web: [PlayableVariant] = []
        for p in detail.players ?? [] {
            if p.isNative {
                guard let base = base else { continue }
                let subURL: URL? = p.subtitles?.first?.src.flatMap { URL(string: absolute($0, base: base)) }
                let qualities = (p.video?.quality ?? []).sorted { ($0.quality ?? 0) > ($1.quality ?? 0) }
                for q in qualities {
                    guard let href = q.href, let url = URL(string: absolute(href, base: base)) else { continue }
                    let qt = q.quality.map { "\($0)p" } ?? ""
                    native.append(PlayableVariant(title: "\(p.label) · \(qt)", url: url, subtitle: subURL))
                }
            } else if let src = p.src {
                let full = src.hasPrefix("//") ? "https:" + src : src
                if let url = URL(string: full) {
                    web.append(PlayableVariant(title: "\(p.label) · \(p.player ?? "Плеер")", url: url, subtitle: nil, isWeb: true))
                }
            }
        }
        let result = native + web
        if result.isEmpty { throw APIError.noVideo }
        return result
    }

    private func absolute(_ href: String, base: String) -> String {
        if href.hasPrefix("http") { return href }
        let b = base.hasSuffix("/") ? String(base.dropLast()) : base
        let h = href.hasPrefix("/") ? href : "/" + href
        return b + "/" + h
    }
}

// MARK: - Images (с заголовком Referer)
final class ImageCache {
    static let shared = NSCache<NSURL, UIImage>()
}

struct RemoteImage: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Rectangle().fill(.quaternary)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if failed {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .clipped()
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { failed = true; return }
        if let cached = ImageCache.shared.object(forKey: url as NSURL) { image = cached; return }
        for attempt in 0..<3 {
            if Task.isCancelled { return }
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            req.setValue("https://v5.animelib.org/", forHTTPHeaderField: "Referer")
            req.setValue("image/*", forHTTPHeaderField: "Accept")
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
               let img = UIImage(data: data) {
                ImageCache.shared.setObject(img, forKey: url as NSURL)
                image = img
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (attempt + 1)))
        }
        if !Task.isCancelled { failed = true }
    }
}

// MARK: - Favorites
@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()
    @Published private(set) var items: [Anime] = []
    private let key = "favorites.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let a = try? JSONDecoder().decode([Anime].self, from: d) {
            items = a
        }
    }

    func contains(_ a: Anime) -> Bool { items.contains { $0.id == a.id } }

    func toggle(_ a: Anime) {
        if let i = items.firstIndex(where: { $0.id == a.id }) {
            items.remove(at: i)
        } else {
            items.insert(a, at: 0)
        }
        if let d = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }
}

struct FavoritesView: View {
    @ObservedObject private var favorites = FavoritesStore.shared
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if favorites.items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "heart.slash").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Пока пусто.\nОткройте тайтл и нажмите сердечко.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 100)
                }
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(favorites.items) { anime in
                        NavigationLink(value: anime) { AnimeCard(anime: anime) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
            .background(AppBackground())
            .navigationTitle("Избранное")
            .navigationDestination(for: Anime.self) { DetailView(anime: $0) }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            CatalogView()
                .tabItem { Label("Каталог", systemImage: "square.grid.2x2") }
            FavoritesView()
                .tabItem { Label("Избранное", systemImage: "heart") }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Catalog
@MainActor
final class CatalogViewModel: ObservableObject {
    @Published var items: [Anime] = []
    @Published var filter = CatalogFilter()
    @Published var isLoading = false
    @Published var error: String?
    @Published var options = FilterOptions()
    @Published var optionsLoading = false

    private var page = 1
    private var hasNext = true
    private var generation = 0

    func reload() async {
        generation += 1
        page = 1; hasNext = true; items = []; error = nil
        isLoading = false
        await loadMore()
    }

    func loadMore() async {
        guard hasNext, !isLoading else { return }
        isLoading = true
        let gen = generation
        defer { if gen == generation { isLoading = false } }
        do {
            let r = try await AnimelibAPI.shared.catalog(filter: filter, page: page)
            guard gen == generation else { return }
            let known = Set(items.map(\.id))
            items += r.items.filter { !known.contains($0.id) }
            hasNext = r.hasNext
            page += 1
        } catch {
            guard gen == generation else { return }
            self.error = error.localizedDescription
        }
    }

    func toggle(_ kp: WritableKeyPath<CatalogFilter, Set<Int>>, _ id: Int) {
        if filter[keyPath: kp].contains(id) {
            filter[keyPath: kp].remove(id)
        } else {
            filter[keyPath: kp].insert(id)
        }
    }

    func resetFilters() {
        filter.genres = []; filter.tags = []; filter.types = []; filter.statuses = []
    }

    func loadOptionsIfNeeded(force: Bool = false) async {
        guard !optionsLoading, force || options.isEmpty else { return }
        optionsLoading = true
        options = await AnimelibAPI.shared.filterOptions()
        optionsLoading = false
    }
}

struct SearchBar: View {
    @Binding var text: String
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Поиск по названию", text: $text)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                    onSubmit()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

struct OptionBlock: View {
    let title: String
    let items: [NamedItem]
    let keyPath: WritableKeyPath<CatalogFilter, Set<Int>>
    @ObservedObject var vm: CatalogViewModel

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                FlowLayout(spacing: 8) {
                    ForEach(items, id: \.id) { item in
                        Chip(title: item.title,
                             selected: item.id.map { vm.filter[keyPath: keyPath].contains($0) } ?? false) {
                            if let id = item.id { vm.toggle(keyPath, id) }
                        }
                    }
                }
            }
        }
    }
}

struct FilterSheet: View {
    @ObservedObject var vm: CatalogViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Сортировка").font(.headline)
                        FlowLayout(spacing: 8) {
                            ForEach(CatalogFilter.SortOption.allCases) { opt in
                                Chip(title: opt.title, selected: vm.filter.sortBy == opt) {
                                    vm.filter.sortBy = opt
                                }
                            }
                        }
                    }

                    if vm.optionsLoading {
                        HStack { ProgressView(); Text("Загружаю жанры и теги…").foregroundStyle(.secondary) }
                    } else if vm.options.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Не удалось загрузить жанры и теги.").foregroundStyle(.secondary)
                            Button("Повторить") { Task { await vm.loadOptionsIfNeeded(force: true) } }
                        }
                    }

                    OptionBlock(title: "Тип", items: vm.options.types, keyPath: \.types, vm: vm)
                    OptionBlock(title: "Статус", items: vm.options.statuses, keyPath: \.statuses, vm: vm)
                    OptionBlock(title: "Жанры", items: vm.options.genres, keyPath: \.genres, vm: vm)
                    OptionBlock(title: "Теги", items: vm.options.tags, keyPath: \.tags, vm: vm)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppBackground())
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Сбросить") { vm.resetFilters() }
                        .disabled(vm.filter.activeCount == 0)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Показать") {
                        dismiss()
                        Task { await vm.reload() }
                    }
                    .bold()
                }
            }
        }
        .task { await vm.loadOptionsIfNeeded() }
    }
}

struct CatalogView: View {
    @StateObject private var vm = CatalogViewModel()
    @State private var showFilters = false
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    SearchBar(text: $vm.filter.query) { Task { await vm.reload() } }
                    Button { showFilters = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(vm.filter.activeCount > 0 ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Material.ultraThinMaterial), in: Circle())
                            .overlay(alignment: .topTrailing) {
                                if vm.filter.activeCount > 0 {
                                    Text("\(vm.filter.activeCount)")
                                        .font(.caption2.bold())
                                        .padding(4)
                                        .background(Color.pink, in: Circle())
                                        .offset(x: 4, y: -4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                ScrollView {
                    if let e = vm.error, vm.items.isEmpty {
                        VStack(spacing: 12) {
                            Text(e).multilineTextAlignment(.center).foregroundStyle(.secondary)
                            Button("Повторить") { Task { await vm.reload() } }
                        }
                        .padding(.top, 60).padding(.horizontal)
                    } else if vm.items.isEmpty && !vm.isLoading {
                        Text("Ничего не найдено")
                            .foregroundStyle(.secondary)
                            .padding(.top, 80)
                    }
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(vm.items) { anime in
                            NavigationLink(value: anime) { AnimeCard(anime: anime) }
                                .buttonStyle(.plain)
                                .onAppear {
                                    if anime.id == vm.items.last?.id { Task { await vm.loadMore() } }
                                }
                        }
                    }
                    .padding(.horizontal, 14)
                    if vm.isLoading { ProgressView().padding() }
                }
                .scrollDismissesKeyboard(.immediately)
                .refreshable { await vm.reload() }
            }
            .background(AppBackground())
            .navigationTitle("Hehe")
            .navigationDestination(for: Anime.self) { DetailView(anime: $0) }
            .sheet(isPresented: $showFilters) { FilterSheet(vm: vm) }
            .task { if vm.items.isEmpty { await vm.reload() } }
        }
    }
}

struct AnimeCard: View {
    let anime: Anime
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: anime.imageURL)
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                .overlay(alignment: .bottomLeading) {
                    if let r = anime.rateAvg {
                        Label(r, systemImage: "star.fill")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(6)
                    }
                }
            Text(anime.displayTitle)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}

// MARK: - Detail
@MainActor
final class DetailViewModel: ObservableObject {
    @Published var anime: Anime
    @Published var episodes: [EpisodeShort] = []
    @Published var isLoading = true
    @Published var error: String?

    init(anime: Anime) { self.anime = anime }

    func load() async {
        isLoading = true; error = nil
        do {
            if let slug = anime.slugUrl {
                async let d = AnimelibAPI.shared.details(slug: slug)
                async let e = AnimelibAPI.shared.episodes(animeID: anime.id)
                if let full = try? await d { anime = full }
                episodes = try await e
            } else {
                episodes = try await AnimelibAPI.shared.episodes(animeID: anime.id)
            }
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }
}

struct DetailView: View {
    @StateObject private var vm: DetailViewModel
    @State private var selected: EpisodeShort?
    @State private var expanded = false
    @ObservedObject private var favorites = FavoritesStore.shared

    init(anime: Anime) { _vm = StateObject(wrappedValue: DetailViewModel(anime: anime)) }

    private var backdrop: some View {
        ZStack {
            Color.black
            RemoteImage(url: vm.anime.imageURL)
                .blur(radius: 50)
                .opacity(0.55)
            LinearGradient(colors: [.clear, .black.opacity(0.85), .black], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    RemoteImage(url: vm.anime.imageURL)
                        .frame(width: 120, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(vm.anime.displayTitle).font(.title3.bold())
                        if let n = vm.anime.name, n != vm.anime.displayTitle {
                            Text(n).font(.caption).foregroundStyle(.secondary)
                        }
                        FlowLayout(spacing: 6) {
                            if let s = vm.anime.status?.title, !s.isEmpty { Pill(icon: "dot.radiowaves.left.and.right", text: s) }
                            if let t = vm.anime.type?.title, !t.isEmpty { Pill(icon: "tv", text: t) }
                            if let a = vm.anime.ageRestriction?.title, !a.isEmpty { Pill(icon: "exclamationmark.shield", text: a) }
                            if let r = vm.anime.rateAvg { Pill(icon: "star.fill", text: r) }
                        }
                    }
                }

                if let g = vm.anime.genres, !g.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(g, id: \.id) { item in
                            Text(item.title)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Theme.accent.opacity(0.28), in: Capsule())
                        }
                    }
                }

                if let s = vm.anime.summary, !s.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(s).font(.callout).lineLimit(expanded ? nil : 5)
                        if s.count > 220 {
                            Button(expanded ? "Свернуть" : "Читать полностью") {
                                withAnimation { expanded.toggle() }
                            }
                            .font(.footnote.bold())
                        }
                        if let au = vm.anime.authors, !au.isEmpty {
                            Text("Автор: " + au.map(\.title).joined(separator: ", "))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }

                if let slug = vm.anime.slugUrl, let url = URL(string: "https://v5.animelib.org/ru/anime/\(slug)") {
                    Link(destination: url) {
                        Label("Открыть на сайте", systemImage: "safari")
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }

                Text("Серии").font(.title3.bold())
                if vm.isLoading { ProgressView() }
                if let e = vm.error { Text(e).foregroundStyle(.red).font(.footnote) }
                if !vm.isLoading && vm.episodes.isEmpty && vm.error == nil {
                    Text("Серий пока нет").foregroundStyle(.secondary)
                }
                LazyVStack(spacing: 8) {
                    ForEach(vm.episodes) { ep in
                        Button { selected = ep } label: {
                            HStack(spacing: 12) {
                                Text(ep.number ?? "–")
                                    .font(.subheadline.bold())
                                    .frame(width: 38, height: 38)
                                    .background(Theme.accent.opacity(0.28), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text((ep.name?.isEmpty == false ? ep.name! : "Серия \(ep.number ?? "")"))
                                        .font(.subheadline)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    if let s = ep.season, s != "1" {
                                        Text("Сезон \(s)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "play.fill").foregroundStyle(Theme.accent)
                            }
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(backdrop)
        .navigationTitle(vm.anime.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { favorites.toggle(vm.anime) } label: {
                    Image(systemName: favorites.contains(vm.anime) ? "heart.fill" : "heart")
                        .foregroundStyle(favorites.contains(vm.anime) ? Color.pink : Color.primary)
                }
            }
        }
        .task { await vm.load() }
        .fullScreenCover(item: $selected) { ep in
            PlayerScreen(episode: ep, animeTitle: vm.anime.displayTitle)
        }
    }
}

// MARK: - Player
/// Страница плеера Kodik встраивается как iframe на «странице сайта» (baseURL),
/// так же, как это делает сам сайт.
struct WebPlayerView: UIViewRepresentable {
    let url: URL

    final class Coordinator { var loaded: URL? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        v.isOpaque = false
        v.backgroundColor = .black
        v.scrollView.isScrollEnabled = false
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>html,body{margin:0;height:100%;background:#000}
        iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style>
        </head><body>
        <iframe src="\(url.absoluteString)" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe>
        </body></html>
        """
        v.loadHTMLString(html, baseURL: URL(string: "https://v5.animelib.org/"))
    }
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var variants: [PlayableVariant] = []
    @Published var current: PlayableVariant?
    @Published var player: AVPlayer?
    @Published var error: String?
    @Published var isLoading = true
    @Published var debug = ""

    func load(episodeID: Int) async {
        isLoading = true; error = nil
        do {
            variants = try await AnimelibAPI.shared.variants(episodeID: episodeID)
            if let first = variants.first { select(first) }
        } catch {
            self.error = error.localizedDescription
            let a = await AnimelibAPI.shared.rawText("/episodes/\(episodeID)")
            debug = a
        }
        isLoading = false
    }

    func select(_ v: PlayableVariant) {
        if v.isWeb {
            player?.pause()
            player = nil
            current = v
            return
        }
        let time = player?.currentTime()
        current = v
        let asset = AVURLAsset(url: v.url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": AnimelibAPI.shared.playbackHeaders
        ])
        let p = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        if let t = time, t.isValid, t.seconds > 1 { p.seek(to: t) }
        player?.pause()
        player = p
        p.play()
    }

    func stop() { player?.pause(); player = nil }
}

struct PlayerScreen: View {
    let episode: EpisodeShort
    let animeTitle: String
    @StateObject private var vm = PlayerViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    if let v = vm.current, v.isWeb {
                        WebPlayerView(url: v.url)
                    } else if let p = vm.player {
                        VideoPlayer(player: p)
                    } else if vm.isLoading {
                        ProgressView().tint(.white)
                    } else if let e = vm.error {
                        Text(e).foregroundStyle(.white).padding()
                    }
                }
                .aspectRatio(16/9, contentMode: .fit)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !vm.debug.isEmpty {
                            Text(vm.debug)
                                .font(.system(size: 9, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        if !vm.variants.isEmpty {
                            Text("Озвучка и качество").font(.headline).padding(.top, 8)
                        }
                        ForEach(vm.variants) { v in
                            Button { vm.select(v) } label: {
                                HStack {
                                    Text(v.title).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                    Spacer()
                                    if v.id == vm.current?.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                                    }
                                }
                                .padding(12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                        if let v = vm.current, v.isWeb {
                            Link(destination: v.url) {
                                Label("Открыть этот плеер в Safari", systemImage: "safari")
                                    .font(.footnote)
                            }
                            .padding(.top, 6)
                        }
                    }
                    .padding(14)
                }
            }
            .background(AppBackground())
            .navigationTitle(episode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { vm.stop(); dismiss() }
                }
            }
        }
        .task { await vm.load(episodeID: episode.id) }
        .onDisappear { vm.stop() }
    }
}

// MARK: - App
@main
struct HeheApp: App {
    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
