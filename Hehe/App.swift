import SwiftUI
import AVKit
import AVFoundation
import Foundation
import WebKit

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
    var ongoingOnly = false

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
        if !filter.query.trimmingCharacters(in: .whitespaces).isEmpty {
            q.append(.init(name: "q", value: filter.query))
        }
        if filter.ongoingOnly { q.append(.init(name: "status[]", value: "2")) }
        let r = try await get("/anime", query: q, as: Envelope<[Anime]>.self)
        let hasNext = r.meta?.hasNextPage ?? !r.data.isEmpty
        return (r.data, hasNext)
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
        let fields = ["summary", "genres", "authors", "otherNames"]
        let q = fields.map { URLQueryItem(name: "fields[]", value: $0) }
        return try await get("/anime/\(slug)", query: q, as: Envelope<Anime>.self).data
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
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if favorites.items.isEmpty {
                    Text("Пока пусто. Откройте тайтл и нажмите сердечко.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 80).padding(.horizontal)
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(favorites.items) { anime in
                        NavigationLink(value: anime) { AnimeCard(anime: anime) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
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
    }
}

// MARK: - Catalog
@MainActor
final class CatalogViewModel: ObservableObject {
    @Published var items: [Anime] = []
    @Published var filter = CatalogFilter()
    @Published var isLoading = false
    @Published var error: String?

    private var page = 1
    private var hasNext = true
    private var generation = 0

    func reload() async {
        generation += 1
        page = 1; hasNext = true; items = []; error = nil
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
}

struct CatalogView: View {
    @StateObject private var vm = CatalogViewModel()
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let e = vm.error, vm.items.isEmpty {
                    VStack(spacing: 12) {
                        Text(e).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("Повторить") { Task { await vm.reload() } }
                    }.padding(.top, 60).padding(.horizontal)
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(vm.items) { anime in
                        NavigationLink(value: anime) { AnimeCard(anime: anime) }
                            .buttonStyle(.plain)
                            .onAppear {
                                if anime.id == vm.items.last?.id { Task { await vm.loadMore() } }
                            }
                    }
                }
                .padding(.horizontal, 12)
                if vm.isLoading { ProgressView().padding() }
            }
            .navigationTitle("Hehe")
            .navigationDestination(for: Anime.self) { DetailView(anime: $0) }
            .searchable(text: $vm.filter.query, prompt: "Поиск аниме")
            .onSubmit(of: .search) { Task { await vm.reload() } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Сортировка", selection: $vm.filter.sortBy) {
                            ForEach(CatalogFilter.SortOption.allCases) { Text($0.title).tag($0) }
                        }
                        Toggle("Только онгоинги", isOn: $vm.filter.ongoingOnly)
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
            .onChange(of: vm.filter.sortBy) { _ in Task { await vm.reload() } }
            .onChange(of: vm.filter.ongoingOnly) { _ in Task { await vm.reload() } }
            .onChange(of: vm.filter.query) { q in if q.isEmpty { Task { await vm.reload() } } }
            .task { if vm.items.isEmpty { await vm.reload() } }
            .refreshable { await vm.reload() }
        }
    }
}

struct AnimeCard: View {
    let anime: Anime
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: anime.imageURL)
            .aspectRatio(2/3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(anime.displayTitle).font(.footnote).lineLimit(2)
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
    @ObservedObject private var favorites = FavoritesStore.shared

    init(anime: Anime) { _vm = StateObject(wrappedValue: DetailViewModel(anime: anime)) }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    RemoteImage(url: vm.anime.imageURL)
                    .frame(width: 110, height: 165)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(vm.anime.displayTitle).font(.headline)
                        if let n = vm.anime.name, n != vm.anime.displayTitle {
                            Text(n).font(.caption).foregroundStyle(.secondary)
                        }
                        if let s = vm.anime.status?.title, !s.isEmpty { Label(s, systemImage: "dot.radiowaves.left.and.right") }
                        if let t = vm.anime.type?.title, !t.isEmpty { Label(t, systemImage: "tv") }
                        if let a = vm.anime.ageRestriction?.title, !a.isEmpty { Label(a, systemImage: "exclamationmark.shield") }
                        if let r = vm.anime.rateAvg { Label(r, systemImage: "star.fill") }
                    }.font(.footnote)
                }
                if let g = vm.anime.genres, !g.isEmpty {
                    Text(g.map(\.title).joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                }
                if let au = vm.anime.authors, !au.isEmpty {
                    Text("Автор: " + au.map(\.title).joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
                }
                if let s = vm.anime.summary, !s.isEmpty {
                    Text(s).font(.callout)
                }
            }
            Section("Серии") {
                if vm.isLoading { ProgressView() }
                if let e = vm.error { Text(e).foregroundStyle(.red) }
                ForEach(vm.episodes) { ep in
                    Button { selected = ep } label: {
                        HStack {
                            Text(ep.title).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "play.circle")
                        }
                    }
                }
            }
        }
        .navigationTitle(vm.anime.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { favorites.toggle(vm.anime) } label: {
                    Image(systemName: favorites.contains(vm.anime) ? "heart.fill" : "heart")
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
struct WebPlayerView: UIViewRepresentable {
    let url: URL

    final class Coordinator { var loaded: URL? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        v.backgroundColor = .black
        v.scrollView.isScrollEnabled = false
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        var req = URLRequest(url: url)
        req.setValue("https://v5.animelib.org/", forHTTPHeaderField: "Referer")
        v.load(req)
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
            let b = await AnimelibAPI.shared.rawText("/constants", query: [URLQueryItem(name: "fields[]", value: "videoServers")])
            debug = a + "\n---\n" + b
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

                List {
                    if !vm.debug.isEmpty {
                        Section("Отладка (пришлите скриншот)") {
                            Text(vm.debug)
                                .font(.system(size: 9, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    Section("Озвучка и качество") {
                        ForEach(vm.variants) { v in
                            Button {
                                vm.select(v)
                            } label: {
                                HStack {
                                    Text(v.title).foregroundStyle(.primary)
                                    Spacer()
                                    if v.id == vm.current?.id { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                }
            }
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
