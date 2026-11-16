import SwiftUI
import AVKit
import AVFoundation
import Foundation

// MARK: - Models
// Все поля сделаны опциональными: структура JSON восстановлена из скомпилированного
// расширения, поэтому декодер должен переживать отсутствие любого поля.

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

struct NamedItem: Decodable, Hashable {
    let id: Int?
    let name: String?
    let label: String?
    var title: String { name ?? label ?? "" }
}

struct Cover: Decodable, Hashable {
    let thumbnail: String?
    let `default`: String?
    let md: String?
}

struct Anime: Decodable, Identifiable, Hashable {
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
        summary = try? c.decode(String.self, forKey: .summary)
        genres = try? c.decode([NamedItem].self, forKey: .genres)
        authors = try? c.decode([NamedItem].self, forKey: .authors)
        otherNames = try? c.decode([String].self, forKey: .otherNames)
        episodesCount = try? c.decode(Int.self, forKey: .episodesCount)
        status = try? c.decode(NamedItem.self, forKey: .status)
        type = try? c.decode(NamedItem.self, forKey: .type)
        ageRestriction = try? c.decode(NamedItem.self, forKey: .ageRestriction)
        releaseDateString = try? c.decode(String.self, forKey: .releaseDateString)
        // rate_avg приходит то строкой, то числом
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
}

// MARK: - API
enum APIError: LocalizedError {
    case badURL, http(Int), noVideo
    var errorDescription: String? {
        switch self {
        case .badURL: return "Некорректный адрес запроса"
        case .http(let c): return "Сервер вернул ошибку \(c)"
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
            throw APIError.http(http.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }

    func catalog(filter: CatalogFilter, page: Int) async throws -> (items: [Anime], hasNext: Bool) {
        var q: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "sort_by", value: filter.sortBy.rawValue),
            .init(name: "sort_type", value: "desc"),
            .init(name: "site_id[]", value: "5"),
            .init(name: "fields[]", value: "rate_avg"),
            .init(name: "fields[]", value: "episodes_count"),
        ]
        if !filter.query.trimmingCharacters(in: .whitespaces).isEmpty {
            q.append(.init(name: "q", value: filter.query))
        }
        if filter.ongoingOnly { q.append(.init(name: "status[]", value: "2")) }
        let r = try await get("/anime", query: q, as: Envelope<[Anime]>.self)
        let hasNext = r.meta?.hasNextPage ?? !r.data.isEmpty
        return (r.data, hasNext)
    }

    func details(slug: String) async throws -> Anime {
        let fields = ["summary", "genres", "authors", "otherNames", "rate_avg", "episodes_count", "ageRestriction", "releaseDateString"]
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
        let servers = (try? await serversTask) ?? []
        guard let base = servers.first?.url else { throw APIError.noVideo }

        var result: [PlayableVariant] = []
        for p in detail.players ?? [] where p.isNative {
            let subURL: URL? = p.subtitles?.first?.src.flatMap { URL(string: absolute($0, base: base)) }
            let qualities = (p.video?.quality ?? []).sorted { ($0.quality ?? 0) > ($1.quality ?? 0) }
            for q in qualities {
                guard let href = q.href, let url = URL(string: absolute(href, base: base)) else { continue }
                let qt = q.quality.map { "\($0)p" } ?? ""
                result.append(PlayableVariant(title: "\(p.label) · \(qt)", url: url, subtitle: subURL))
            }
        }
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
            AsyncImage(url: anime.imageURL) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: Rectangle().fill(.quaternary).overlay(ProgressView())
                }
            }
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

    init(anime: Anime) { _vm = StateObject(wrappedValue: DetailViewModel(anime: anime)) }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    AsyncImage(url: vm.anime.imageURL) { $0.resizable().scaledToFill() } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
                    .frame(width: 110, height: 165)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(vm.anime.displayTitle).font(.headline)
                        if let n = vm.anime.name, n != vm.anime.displayTitle {
                            Text(n).font(.caption).foregroundStyle(.secondary)
                        }
                        if let s = vm.anime.status?.title, !s.isEmpty { Label(s, systemImage: "dot.radiowaves.left.and.right") }
                        if let t = vm.anime.type?.title, !t.isEmpty { Label(t, systemImage: "tv") }
                        if let r = vm.anime.rateAvg { Label(r, systemImage: "star.fill") }
                    }.font(.footnote)
                }
                if let g = vm.anime.genres, !g.isEmpty {
                    Text(g.map(\.title).joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
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
        .task { await vm.load() }
        .fullScreenCover(item: $selected) { ep in
            PlayerScreen(episode: ep, animeTitle: vm.anime.displayTitle)
        }
    }
}

// MARK: - Player
@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var variants: [PlayableVariant] = []
    @Published var current: PlayableVariant?
    @Published var player: AVPlayer?
    @Published var error: String?
    @Published var isLoading = true

    func load(episodeID: Int) async {
        isLoading = true; error = nil
        do {
            variants = try await AnimelibAPI.shared.variants(episodeID: episodeID)
            if let first = variants.first { select(first) }
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }

    func select(_ v: PlayableVariant) {
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
                    if let p = vm.player {
                        VideoPlayer(player: p)
                    } else if vm.isLoading {
                        ProgressView().tint(.white)
                    } else if let e = vm.error {
                        Text(e).foregroundStyle(.white).padding()
                    }
                }
                .aspectRatio(16/9, contentMode: .fit)

                List {
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
            CatalogView()
        }
    }
}
