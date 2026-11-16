import SwiftUI
import AVKit
import AVFoundation
import Foundation
import WebKit
import Security

// MARK: - Тема и общие элементы дизайна

enum Theme {
    static let defaultAccentHex = "A87AFF"
    /// Акцентный цвет берётся из настроек и меняется на лету.
    static var accent: Color {
        Color(hex: UserDefaults.standard.string(forKey: "accent.hex") ?? defaultAccentHex)
    }
}

enum Settings {
    static func bool(_ key: String, _ def: Bool) -> Bool {
        (UserDefaults.standard.object(forKey: key) as? Bool) ?? def
    }
}

extension Color {
    init(hex: String) {
        let t = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: t).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 255) / 255,
                  green: Double((v >> 8) & 255) / 255,
                  blue: Double(v & 255) / 255)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
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
    var kodik = false
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

    func rawData(_ path: String, query: [URLQueryItem] = [], token: String? = nil,
                 method: String = "GET", json: [String: Any]? = nil) async throws -> Data {
        guard var comps = URLComponents(string: apiURL + path) else { throw APIError.badURL }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError.badURL }
        var req = URLRequest(url: url)
        for (k, v) in playbackHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("5", forHTTPHeaderField: "Site-Id")
        if let t = token { req.setValue("Bearer " + t, forHTTPHeaderField: "Authorization") }
        req.httpMethod = method
        if let j = json {
            req.httpBody = try JSONSerialization.data(withJSONObject: j)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }
        return data
    }

    func rawText(_ path: String, query: [URLQueryItem] = [], token: String? = nil) async -> String {
        guard var comps = URLComponents(string: apiURL + path) else { return "bad url" }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { return "bad url" }
        var req = URLRequest(url: url)
        for (k, v) in playbackHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("5", forHTTPHeaderField: "Site-Id")
        if let t = token { req.setValue("Bearer " + t, forHTTPHeaderField: "Authorization") }
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
                    let isK = full.contains("kodik")
                    web.append(PlayableVariant(title: "\(p.label) · \(p.player ?? "Плеер")", url: url, subtitle: nil, isWeb: true, kodik: isK))
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

    func clear() {
        items = []
        UserDefaults.standard.removeObject(forKey: key)
    }

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

struct SettingsView: View {
    @AppStorage("accent.hex") private var accentHex = Theme.defaultAccentHex
    @AppStorage("set.autoNative") private var autoNative = true
    @AppStorage("set.resume") private var resume = true
    @AppStorage("set.platform") private var platform = "anime"
    @ObservedObject private var auth = AuthStore.shared
    @State private var custom: Color = Theme.accent
    @State private var info: String?

    private let presets: [(String, String)] = [
        ("Фиолетовый", "A87AFF"), ("Розовый", "FF6FA8"), ("Синий", "4F9DFF"),
        ("Бирюзовый", "2EC4B6"), ("Зелёный", "5BD16A"), ("Оранжевый", "FF9F43"), ("Красный", "FF5A5F")
    ]
    private let platforms: [(String, String, String, Bool)] = [
        ("anime", "Аниме", "AnimeLib", true),
        ("manga", "Манга", "MangaLib", false),
        ("ranobe", "Ранобэ", "RanobeLib", false),
        ("hentai", "Хентай", "HentaiLib · 18+", false)
    ]

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    card("Цвет акцента") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(presets, id: \.1) { p in
                                    Circle()
                                        .fill(Color(hex: p.1))
                                        .frame(width: 36, height: 36)
                                        .overlay {
                                            if accentHex.uppercased() == p.1 {
                                                Image(systemName: "checkmark").font(.footnote.bold()).foregroundStyle(.white)
                                            }
                                        }
                                        .onTapGesture { accentHex = p.1 }
                                }
                            }
                        }
                        ColorPicker("Свой цвет", selection: $custom, supportsOpacity: false)
                            .onChange(of: custom) { c in accentHex = c.hexString }
                    }

                    card("Платформа") {
                        ForEach(platforms, id: \.0) { pl in
                            Button { if pl.3 { platform = pl.0 } } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pl.1).foregroundStyle(pl.3 ? Color.primary : Color.secondary)
                                        Text(pl.2).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if !pl.3 {
                                        Text("Скоро").font(.caption2.bold())
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(Color.white.opacity(0.1), in: Capsule())
                                    } else if platform == pl.0 {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    card("Воспроизведение") {
                        Toggle("Родной плеер iOS, если получится", isOn: $autoNative)
                        Toggle("Продолжать с места остановки", isOn: $resume)
                        Text("Если родной плеер выключен, серии всегда идут в веб-плеере Kodik.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tint(Theme.accent)

                    card("Данные") {
                        Button("Очистить кэш обложек") {
                            ImageCache.shared.removeAllObjects(); info = "Кэш обложек очищен"
                        }
                        Button("Сбросить историю просмотра") {
                            ProgressStore.shared.clear(); info = "История просмотра сброшена"
                        }
                        Button("Очистить избранное") {
                            FavoritesStore.shared.clear(); info = "Избранное очищено"
                        }
                        if let i = info { Text(i).font(.caption).foregroundStyle(.secondary) }
                    }

                    card("Аккаунт") {
                        if let u = auth.user {
                            Text("Вы вошли как \(u.username)")
                            Button("Выйти", role: .destructive) { auth.signOut() }
                        } else {
                            Text("Вход выполняется во вкладке «Профиль».").foregroundStyle(.secondary)
                        }
                    }

                    card("О приложении") {
                        Text("Hehe · версия 1.0")
                        Text("Данные: animelib.org. Приложение неофициальное.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
            }
            .background(AppBackground())
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct RootView: View {
    @AppStorage("accent.hex") private var accentHex = Theme.defaultAccentHex
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            CatalogView()
                .tabItem { Label("Каталог", systemImage: "square.grid.2x2") }
                .tag(0)
            FavoritesView()
                .tabItem { Label("Избранное", systemImage: "heart") }
                .tag(1)
            ProfileView()
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape") }
                .tag(3)
        }
        .id(accentHex)
        .tint(Color(hex: accentHex))
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

    private var filterButton: some View {
        Button { showFilters = true } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.headline)
                .frame(width: 42, height: 42)
                .background(vm.filter.activeCount > 0 ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Material.ultraThinMaterial), in: Circle())
                .overlay(alignment: .topTrailing) {
                    if vm.filter.activeCount > 0 {
                        Text("\(vm.filter.activeCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Color.pink, in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
            ScrollView {
                VStack(spacing: 10) {
                    HStack {
                        Text("Hehe")
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                        Spacer()
                        filterButton
                    }
                    SearchBar(text: $vm.filter.query) { Task { await vm.reload() } }
                }
                .padding(.horizontal, 14)
                .padding(.top, geo.safeAreaInsets.top + 4)
                .padding(.bottom, 10)

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
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) {
                // мягкое размытие под строкой состояния: обложки заезжают под неё, как в системных приложениях
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: geo.safeAreaInsets.top + 14)
                    .mask(LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.75),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom))
                    .allowsHitTesting(false)
                    .offset(y: -geo.safeAreaInsets.top)
            }
            }
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
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
    @State private var showComments = false
    @State private var showBookmark = false
    @ObservedObject private var progress = ProgressStore.shared
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

                if let slug = vm.anime.slugUrl, let url = URL(string: "https://animelib.org/ru/anime/\(slug)") {
                    Link(destination: url) {
                        Label("Открыть на сайте", systemImage: "safari")
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }

                Button { showComments = true } label: {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(Theme.accent)
                        Text("Комментарии").font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Text("Серии").font(.title3.bold())
                if vm.isLoading { ProgressView() }
                if let e = vm.error { Text(e).foregroundStyle(.red).font(.footnote) }
                if !vm.isLoading && vm.episodes.isEmpty && vm.error == nil {
                    Text("Серий пока нет").foregroundStyle(.secondary)
                }
                LazyVStack(spacing: 8) {
                    ForEach(vm.episodes) { ep in
                        let pr = progress.get(ep.id)
                        Button { selected = ep } label: {
                            HStack(spacing: 12) {
                                Text(ep.number ?? "–")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(pr != nil ? Color.secondary : Color.primary)
                                    .frame(width: 38, height: 38)
                                    .background(pr != nil ? Color.gray.opacity(0.3) : Theme.accent.opacity(0.28), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text((ep.name?.isEmpty == false ? ep.name! : "Серия \(ep.number ?? "")"))
                                        .font(.subheadline)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    if let s = ep.season, s != "1" {
                                        Text("Сезон \(s)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    if let pr = pr {
                                        Text(pr.finished ? "Просмотрено"
                                             : pr.position > 5 ? "Остановились на \(formatTime(pr.position))"
                                             : "Открывали")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .foregroundStyle(pr != nil ? Color.secondary : Color.primary)
                                Spacer()
                                Image(systemName: (pr?.finished ?? false) ? "checkmark.circle.fill" : "play.fill")
                                    .foregroundStyle(pr != nil ? Color.gray : Theme.accent)
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showBookmark = true } label: { Image(systemName: "bookmark") }
                Button { favorites.toggle(vm.anime) } label: {
                    Image(systemName: favorites.contains(vm.anime) ? "heart.fill" : "heart")
                        .foregroundStyle(favorites.contains(vm.anime) ? Color.pink : Color.primary)
                }
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $showComments) { CommentsView(anime: vm.anime) }
        .sheet(isPresented: $showBookmark) { BookmarkSheet(anime: vm.anime) }
        .fullScreenCover(item: $selected) { ep in
            PlayerScreen(episode: ep, animeTitle: vm.anime.displayTitle)
        }
    }
}

// MARK: - Прогресс просмотра
struct WatchProgress: Codable {
    var position: Double
    var duration: Double
    var updated: Date
    var finished: Bool { duration > 0 && position / duration > 0.92 }
}

@MainActor
final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()
    @Published private(set) var items: [String: WatchProgress] = [:]
    private let key = "progress.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let v = try? JSONDecoder().decode([String: WatchProgress].self, from: d) {
            items = v
        }
    }

    func clear() {
        items = [:]
        UserDefaults.standard.removeObject(forKey: key)
    }

    func get(_ id: Int) -> WatchProgress? { items[String(id)] }
    func position(_ id: Int) -> Double { items[String(id)]?.position ?? 0 }

    func opened(_ id: Int) {
        if items[String(id)] == nil {
            items[String(id)] = WatchProgress(position: 0, duration: 0, updated: Date())
            save()
        }
    }

    func update(_ id: Int, position: Double, duration: Double) {
        items[String(id)] = WatchProgress(position: position, duration: duration, updated: Date())
        save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: key) }
    }
}

func formatTime(_ t: Double) -> String {
    let s = Int(t)
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
}

// MARK: - Kodik (прямое получение потока)
enum KodikError: LocalizedError {
    case page, params, noLinks, decode
    case server(String)
    var errorDescription: String? {
        switch self {
        case .page: return "не открылась страница плеера"
        case .params: return "не найдены параметры плеера"
        case .noLinks: return "плеер не вернул ссылки на видео"
        case .decode: return "не удалось расшифровать ссылку"
        case .server(let t): return "ответ Kodik: " + t
        }
    }
}

enum Kodik {
    static let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static func match(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    static func fetch(_ url: URL, referer: String) async throws -> String {
        var req = URLRequest(url: url)
        req.setValue(referer, forHTTPHeaderField: "Referer")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let t = String(data: data, encoding: .utf8) else { throw KodikError.page }
        return t
    }

    static func resolve(_ pageURL: URL) async throws -> [(Int, URL)] {
        let html = try await fetch(pageURL, referer: "https://animelib.org/")
        // параметры подписи: ищем каждое поле отдельно, формат страницы может меняться
        var params: [String: Any] = [:]
        for k in ["d", "d_sign", "pd", "pd_sign", "ref", "ref_sign"] {
            if let v = match("\\\\?[\"']" + k + "\\\\?[\"']\\s*:\\s*\\\\?[\"']([^\"'\\\\]*)", in: html) { params[k] = v }
        }
        if params["d_sign"] == nil || params["pd_sign"] == nil {
            let hasKey = html.contains("urlParams")
            let head = String(html.prefix(70)).replacingOccurrences(of: "\n", with: " ")
            throw KodikError.server("нет параметров (страница \(html.count) симв., urlParams: \(hasKey ? "есть" : "нет"), начало: \(head))")
        }

        let parts = pageURL.pathComponents.filter { $0 != "/" }
        let type = match("videoInfo\\.type\\s*=\\s*'([^']+)'", in: html) ?? (parts.count > 0 ? parts[0] : "")
        let id = match("videoInfo\\.id\\s*=\\s*'?([0-9]+)'?", in: html) ?? (parts.count > 1 ? parts[1] : "")
        let hash = match("videoInfo\\.hash\\s*=\\s*'([^']+)'", in: html) ?? (parts.count > 2 ? parts[2] : "")
        guard !type.isEmpty, !id.isEmpty, !hash.isEmpty else { throw KodikError.params }

        // путь запроса прячется в скрипте плеера, по умолчанию /ftor
        var path = "/ftor"
        if let script = match("<script[^>]+src=\"(/assets/js/app\\.player[^\"]+)\"", in: html),
           let su = URL(string: "https://" + (pageURL.host ?? "kodikplayer.com") + script),
           let js = try? await fetch(su, referer: pageURL.absoluteString),
           let b64 = match("url:\\s*atob\\(\\s*[\"']([^\"']+)[\"']\\s*\\)", in: js),
           let d = Data(base64Encoded: b64), let p = String(data: d, encoding: .utf8), p.hasPrefix("/") {
            path = p
        }

        var fields: [(String, String)] = []
        for k in ["d", "d_sign", "pd", "pd_sign", "ref", "ref_sign"] {
            fields.append((k, (params[k] as? String) ?? ""))
        }
        fields += [("bad_user", "true"), ("cdn_is_working", "true"),
                   ("type", type), ("hash", hash), ("id", id), ("info", "{}")]
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = fields.map { k, v in
            k + "=" + (v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)
        }.joined(separator: "&")

        guard let ftor = URL(string: "https://" + (pageURL.host ?? "kodikplayer.com") + path) else { throw KodikError.page }
        var req = URLRequest(url: ftor)
        req.httpMethod = "POST"
        req.httpBody = body.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("https://" + (pageURL.host ?? "kodikplayer.com"), forHTTPHeaderField: "Origin")
        req.setValue(pageURL.absoluteString, forHTTPHeaderField: "Referer")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let links = obj["links"] as? [String: Any] else {
            let t = String(data: data.prefix(140), encoding: .utf8) ?? ""
            throw KodikError.server(t)
        }

        var result: [(Int, URL)] = []
        for (q, v) in links {
            guard let arr = v as? [[String: Any]], let src = arr.first?["src"] as? String,
                  let quality = Int(q) else { continue }
            guard var text = decode(src) else { throw KodikError.decode }
            if text.hasPrefix("//") { text = "https:" + text }
            if let u = URL(string: text) { result.append((quality, u)) }
        }
        if result.isEmpty { throw KodikError.noLinks }
        return result.sorted { $0.0 > $1.0 }
    }

    /// Ссылка зашифрована сдвигом букв (ROT-N) и base64; перебираем сдвиг.
    static func decode(_ s: String) -> String? {
        if s.hasPrefix("http") || s.hasPrefix("//") { return s }
        for shift in 0..<26 {
            var out = ""
            for c in s.unicodeScalars {
                let v = c.value
                if v >= 65 && v <= 90 {
                    out.unicodeScalars.append(UnicodeScalar((v - 65 + UInt32(shift)) % 26 + 65)!)
                } else if v >= 97 && v <= 122 {
                    out.unicodeScalars.append(UnicodeScalar((v - 97 + UInt32(shift)) % 26 + 97)!)
                } else {
                    out.unicodeScalars.append(c)
                }
            }
            var b = out.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while b.count % 4 != 0 { b += "=" }
            if let d = Data(base64Encoded: b), let t = String(data: d, encoding: .utf8),
               t.hasPrefix("http") || t.hasPrefix("//") {
                return t
            }
        }
        return nil
    }
}

// MARK: - Player
/// Страница плеера Kodik встраивается как iframe на «странице сайта» (baseURL),
/// так же, как это делает сам сайт.
struct WebPlayerView: UIViewRepresentable {
    let url: URL
    var onStream: ((URL) -> Void)? = nil

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var loaded: URL?
        var onStream: ((URL) -> Void)?
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            guard let t = m.body as? String, t.hasPrefix("http"), let u = URL(string: t) else { return }
            DispatchQueue.main.async { self.onStream?(u) }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    static let sniffer = """
    (function(){
      if (window.__heheSniff) return; window.__heheSniff = true;
      var sent = {};
      function post(u){
        try { if (!sent[u]) { sent[u] = 1; window.webkit.messageHandlers.hehe.postMessage(u); } } catch (e) {}
      }
      function report(u){
        try {
          if (!u) return;
          var a = new URL(String(u), location.href).href;
          if (/\\.m3u8|\\.mp4/.test(a)) post(a);
        } catch (e) {}
      }
      var oo = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(m, u){ report(u); return oo.apply(this, arguments); };
      var of = window.fetch;
      if (of) window.fetch = function(a){ report(typeof a === 'string' ? a : (a && a.url)); return of.apply(this, arguments); };
      setInterval(function(){
        var vs = document.getElementsByTagName('video');
        for (var i = 0; i < vs.length; i++) {
          var u = vs[i].currentSrc || vs[i].src;
          if (u && u.indexOf('http') === 0) report(u);
        }
      }, 700);
    })();
    """

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.userContentController.add(context.coordinator, name: "hehe")
        cfg.userContentController.addUserScript(
            WKUserScript(source: Self.sniffer, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.customUserAgent = Kodik.ua
        v.isOpaque = false
        v.backgroundColor = .black
        v.scrollView.isScrollEnabled = false
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {
        context.coordinator.onStream = onStream
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
        v.loadHTMLString(html, baseURL: URL(string: "https://animelib.org/"))
    }
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var variants: [PlayableVariant] = []
    @Published var current: PlayableVariant?
    @Published var player: AVPlayer?
    @Published var qualities: [PlayableVariant] = []
    @Published var currentQuality: UUID?
    @Published var showWeb = false
    @Published var isResolving = false
    @Published var note: String?
    @Published var error: String?
    @Published var isLoading = true
    @Published var debug = ""
    var autoNative = true
    var episodeID = 0
    var lastPosition: Double = 0
    private var timeObserver: Any?
    private var observedPlayer: AVPlayer?

    var usesWeb: Bool {
        guard let v = current, v.isWeb else { return false }
        return !v.kodik || showWeb
    }

    func load(episodeID: Int) async {
        isLoading = true; error = nil
        self.episodeID = episodeID
        ProgressStore.shared.opened(episodeID)
        lastPosition = Settings.bool("set.resume", true) ? ProgressStore.shared.position(episodeID) : 0
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
        note = nil
        showWeb = false
        autoNative = Settings.bool("set.autoNative", true)
        qualities = []
        current = v
        if v.kodik {
            savePosition(); detachObserver()
            player?.pause(); player = nil
            if autoNative { Task { await playKodik(v) } } else { showWeb = true }
        } else if v.isWeb {
            savePosition(); detachObserver()
            player?.pause(); player = nil
            showWeb = true
        } else {
            startAV(v.url, headers: AnimelibAPI.shared.playbackHeaders)
        }
    }

    func playKodik(_ v: PlayableVariant) async {
        isResolving = true
        defer { isResolving = false }
        do {
            let links = try await Kodik.resolve(v.url)
            guard current?.id == v.id else { return }
            qualities = links.map { PlayableVariant(title: "\($0.0)p", url: $0.1, subtitle: nil) }
            if let best = qualities.first { pickQuality(best) }
        } catch {
            guard current?.id == v.id else { return }
            note = "Прямой поток не получен (\(error.localizedDescription)). Пробую получить его через веб-плеер."
            showWeb = true
        }
    }

    func pickQuality(_ q: PlayableVariant) {
        currentQuality = q.id
        startAV(q.url, headers: ["Referer": "https://kodikplayer.com/", "Origin": "https://kodikplayer.com", "User-Agent": Kodik.ua])
    }

    func forceWeb() { autoNative = false; showWeb = true; note = nil }

    /// Веб-плеер Kodik отдал адрес потока: переключаемся на родной плеер iOS.
    func webStream(_ u: URL) {
        guard autoNative, showWeb, current?.kodik == true else { return }
        showWeb = false
        note = "Играет в родном плеере (\(u.host ?? "kodik"))"
        startAV(u, headers: ["Referer": "https://kodikplayer.com/", "Origin": "https://kodikplayer.com", "User-Agent": Kodik.ua])
    }

    private func startAV(_ url: URL, headers: [String: String]) {
        savePosition()
        if let t = player?.currentTime(), t.isValid, t.seconds > 1 { lastPosition = t.seconds }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let p = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        if lastPosition > 1 { p.seek(to: CMTime(seconds: lastPosition, preferredTimescale: 600)) }
        detachObserver()
        player?.pause()
        player = p
        let id = episodeID
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { [weak self, weak p] t in
            let dur = p?.currentItem?.duration.seconds ?? 0
            let pos = t.seconds
            Task { @MainActor in
                guard pos.isFinite, pos > 1 else { return }
                self?.lastPosition = pos
                ProgressStore.shared.update(id, position: pos, duration: dur.isFinite ? dur : 0)
            }
        }
        observedPlayer = p
        p.play()
    }

    private func detachObserver() {
        if let o = timeObserver, let p = observedPlayer { p.removeTimeObserver(o) }
        timeObserver = nil; observedPlayer = nil
    }

    private func savePosition() {
        guard let p = player else { return }
        let pos = p.currentTime().seconds
        let dur = p.currentItem?.duration.seconds ?? 0
        if pos.isFinite, pos > 1, episodeID != 0 {
            lastPosition = pos
            ProgressStore.shared.update(episodeID, position: pos, duration: dur.isFinite ? dur : 0)
        }
    }

    func stop() { savePosition(); detachObserver(); player?.pause(); player = nil }
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
                    if vm.usesWeb, let v = vm.current {
                        WebPlayerView(url: v.url, onStream: v.kodik ? { vm.webStream($0) } : nil)
                    } else if let p = vm.player {
                        VideoPlayer(player: p)
                    } else if vm.isLoading || vm.isResolving {
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
                        if let n = vm.note {
                            Text(n).font(.footnote).foregroundStyle(.orange)
                        }
                        if vm.qualities.count > 0 {
                            Text("Качество").font(.headline).padding(.top, 4)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(vm.qualities) { q in
                                        Button { vm.pickQuality(q) } label: {
                                            Text(q.title)
                                                .font(.subheadline.bold())
                                                .padding(.horizontal, 14).padding(.vertical, 8)
                                                .background(q.id == vm.currentQuality ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Material.ultraThinMaterial), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        if !vm.variants.isEmpty {
                            Text("Озвучка").font(.headline).padding(.top, 8)
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
                            if v.kodik && !vm.showWeb {
                                Button("Показать веб-плеер вместо прямого") { vm.forceWeb() }
                                    .font(.footnote)
                            }
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

// MARK: - JSON-помощники (формат ответов сайта разный, разбираем мягко)
enum J {
    static func obj(_ d: Data) -> Any? { try? JSONSerialization.jsonObject(with: d) }

    static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) }
        return nil
    }

    static func str(_ v: Any?) -> String? {
        if let s = v as? String, !s.isEmpty { return s }
        return nil
    }

    static func text(_ v: Any?) -> String {
        if let s = v as? String { return stripHTML(s) }
        if let d = v as? [String: Any] {
            let type = (d["type"] as? String) ?? ""
            if type == "text" { return (d["text"] as? String) ?? "" }
            let inner = ((d["content"] as? [Any]) ?? []).map { text($0) }.joined()
            switch type {
            case "paragraph", "heading": return inner + "\n"
            case "hardBreak": return "\n"
            default: return inner
            }
        }
        if let a = v as? [Any] { return a.map { text($0) }.joined() }
        return ""
    }

    static func stripHTML(_ s: String) -> String {
        guard s.contains("<") else { return s }
        var t = s.replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n")
        t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return t.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    static func url(_ v: Any?) -> URL? {
        var s: String?
        if let x = v as? String { s = x }
        else if let d = v as? [String: Any] {
            s = str(d["url"]) ?? str(d["default"]) ?? str(d["md"]) ?? str(d["thumbnail"]) ?? str(d["src"])
        }
        guard var t = s else { return nil }
        if t.hasPrefix("//") { t = "https:" + t }
        if t.hasPrefix("/") { t = "https://cover.cdnlibs.org" + t }
        return URL(string: t)
    }

    static func date(_ s: String?) -> String {
        guard let s = s else { return "" }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f1.date(from: s) ?? f2.date(from: s) {
            let out = DateFormatter()
            out.locale = Locale(identifier: "ru_RU")
            out.dateFormat = "d MMM yyyy"
            return out.string(from: d)
        }
        return String(s.prefix(10))
    }
}

// MARK: - Keychain (токен входа хранится в защищённом хранилище)
enum Keychain {
    static func set(_ value: String, key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - Комментарии
struct CommentItem: Identifiable {
    let id: Int
    let text: String
    let username: String
    let avatar: URL?
    let up: Int
    let down: Int
    let date: String
    let replyCount: Int
    let replies: [CommentItem]

    init?(_ d: [String: Any], extra: [CommentItem] = []) {
        guard let cid = J.int(d["id"]) else { return nil }
        id = cid
        text = J.text(d["comment"] ?? d["content"] ?? d["text"] ?? d["body"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let u = (d["user"] as? [String: Any]) ?? [:]
        username = J.str(u["username"]) ?? J.str(u["name"]) ?? "Аноним"
        avatar = J.url(u["avatar"])
        let votes = d["votes"] as? [String: Any]
        up = J.int(votes?["up"]) ?? J.int(d["likes_count"]) ?? J.int(d["likes"]) ?? J.int(d["votes_up"]) ?? 0
        down = J.int(votes?["down"]) ?? J.int(d["dislikes_count"]) ?? 0
        date = J.date(J.str(d["created_at"]) ?? J.str(d["date"]))
        let rawReplies = (d["replies"] as? [[String: Any]])
            ?? (d["children"] as? [[String: Any]])
            ?? (d["comments"] as? [[String: Any]]) ?? []
        let parsed = rawReplies.compactMap { CommentItem($0) } + extra
        replies = parsed
        replyCount = max(parsed.count, J.int(d["comments_count"]) ?? J.int(d["replies_count"])
            ?? J.int(d["children_count"]) ?? 0)
    }
}

/// Ответ сервера может быть списком или объектом со вложенными массивами:
/// собираем все комментарии, где бы они ни лежали, и выстраиваем ветки по parent_comment.
enum CommentParser {
    static func collect(_ v: Any, into out: inout [[String: Any]]) {
        if let d = v as? [String: Any] {
            if J.int(d["id"]) != nil, d["comment"] != nil { out.append(d); return }
            for k in d.keys.sorted() { if let x = d[k] { collect(x, into: &out) } }
        } else if let a = v as? [Any] {
            for x in a { collect(x, into: &out) }
        }
    }

    static func parse(_ root: Any) -> [CommentItem] {
        var raw: [[String: Any]] = []
        collect(root, into: &raw)
        var seen = Set<Int>()
        raw = raw.filter { d in
            guard let id = J.int(d["id"]) else { return false }
            return seen.insert(id).inserted
        }
        let ids = Set(raw.compactMap { J.int($0["id"]) })
        var children: [Int: [[String: Any]]] = [:]
        var tops: [[String: Any]] = []
        for d in raw {
            if let p = J.int(d["parent_comment"]), p != J.int(d["id"]), ids.contains(p) {
                children[p, default: []].append(d)
            } else {
                tops.append(d)
            }
        }
        func build(_ d: [String: Any], depth: Int) -> CommentItem? {
            let id = J.int(d["id"]) ?? 0
            let kids = depth < 6 ? (children[id] ?? []).compactMap { build($0, depth: depth + 1) } : []
            return CommentItem(d, extra: kids)
        }
        return tops.compactMap { build($0, depth: 0) }
    }
}

@MainActor
final class CommentsViewModel: ObservableObject {
    @Published var items: [CommentItem] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var debug = ""
    @Published var loadingReplies: Set<Int> = []
    @Published var repliesLoaded: [Int: [CommentItem]] = [:]
    @Published var replyTarget: CommentItem?

    let animeID: Int
    let slug: String
    private var page = 1
    private var finished = false

    init(animeID: Int, slug: String) {
        self.animeID = animeID
        self.slug = slug
    }

    private func q(_ n: String, _ v: String) -> URLQueryItem { URLQueryItem(name: n, value: v) }

    private func firstPageQuery() -> [URLQueryItem] {
        [q("post_id", String(animeID)), q("post_type", "anime"), q("page", "1")]
    }

    private func fetch(page: Int) async throws -> ([CommentItem], Bool?) {
        let attempts: [(String, [URLQueryItem])] = [
            ("/comments", [q("post_id", String(animeID)), q("post_type", "anime"), q("page", String(page))]),
            ("/comments", [q("post_id", String(animeID)), q("post_type", "anime"), q("page", String(page)),
                           q("sort_by", "created_at"), q("sort_type", "desc")])
        ]
        var lastError: Error = APIError.badURL
        for (path, query) in attempts {
            do {
                let data = try await AnimelibAPI.shared.rawData(path, query: query, token: AuthStore.shared.token)
                guard let root = J.obj(data) else { continue }
                let list = CommentParser.parse(root)
                let meta = (root as? [String: Any])?["meta"] as? [String: Any]
                return (list, meta?["has_next_page"] as? Bool)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func loadMore() async {
        guard !isLoading, !finished else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (list, hasNext) = try await fetch(page: page)
            let known = Set(items.map { $0.id })
            let fresh = list.filter { !known.contains($0.id) }
            items += fresh
            page += 1
            if fresh.isEmpty || hasNext == false { finished = true }
            error = nil
            if items.isEmpty {
                debug = await AnimelibAPI.shared.rawText("/comments", query: firstPageQuery())
            }
        } catch {
            finished = true
            if items.isEmpty {
                self.error = error.localizedDescription
                debug = await AnimelibAPI.shared.rawText("/comments", query: firstPageQuery())
            }
        }
    }

    func reload() async {
        items = []
        repliesLoaded = [:]
        page = 1
        finished = false
        await loadMore()
    }

    /// Возвращает текст ошибки или nil при успехе.
    func send(_ text: String, parent: Int?) async -> String? {
        guard let t = AuthStore.shared.token else { return "Сначала войдите во вкладке «Профиль»" }
        var base: [String: Any] = ["comment": text, "post_id": animeID, "post_type": "anime"]
        if let p = parent { base["parent_comment"] = p }
        var alt = base
        alt["is_spoiler"] = false
        alt["attachments"] = [Any]()
        var last = ""
        for b in [base, alt] {
            do {
                _ = try await AnimelibAPI.shared.rawData("/comments", token: t, method: "POST", json: b)
                return nil
            } catch {
                last = error.localizedDescription
            }
        }
        return last
    }

    func like(_ id: Int) async -> String? {
        guard let t = AuthStore.shared.token else { return "Сначала войдите во вкладке «Профиль»" }
        let attempts: [(String, [String: Any])] = [
            ("/comments/\(id)/vote", ["type": "up"]),
            ("/comments/\(id)/vote", ["vote": 1]),
            ("/comments/\(id)/like", [:])
        ]
        var last = ""
        for (path, body) in attempts {
            do {
                _ = try await AnimelibAPI.shared.rawData(path, token: t, method: "POST", json: body)
                return nil
            } catch {
                last = error.localizedDescription
            }
        }
        return last
    }

    func loadReplies(_ c: CommentItem) async {
        loadingReplies.insert(c.id)
        defer { loadingReplies.remove(c.id) }
        let known = Set(items.map { $0.id })
        for key in ["parent_comment", "parent_id", "parent_comment_id"] {
            let query = [q("post_id", String(animeID)), q("post_type", "anime"), q(key, String(c.id))]
            if let data = try? await AnimelibAPI.shared.rawData("/comments", query: query, token: AuthStore.shared.token),
               let root = J.obj(data) {
                let list = CommentParser.parse(root).filter { $0.id != c.id && !known.contains($0.id) }
                if !list.isEmpty { repliesLoaded[c.id] = list; return }
            }
        }
        repliesLoaded[c.id] = []
    }
}

struct CommentRow: View {
    let c: CommentItem
    var depth = 0
    @ObservedObject var vm: CommentsViewModel
    @State private var expanded = false
    @State private var liked = false
    @State private var note: String?

    private var children: [CommentItem] {
        c.replies.isEmpty ? (vm.repliesLoaded[c.id] ?? []) : c.replies
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                RemoteImage(url: c.avatar)
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(c.username).font(.subheadline.bold())
                        Text(c.date).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(c.text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 16) {
                        Button {
                            Task {
                                if let e = await vm.like(c.id) { note = e } else { liked = true; note = nil }
                            }
                        } label: {
                            Label("\(c.up + (liked ? 1 : 0))", systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.caption)
                                .foregroundStyle(liked ? Theme.accent : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        if c.down > 0 {
                            Label("\(c.down)", systemImage: "hand.thumbsdown").font(.caption)
                        }
                        if AuthStore.shared.token != nil {
                            Button { vm.replyTarget = c } label: {
                                Text("Ответить").font(.caption.bold()).foregroundStyle(Theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        if c.replyCount > 0 {
                            Button {
                                expanded.toggle()
                                if expanded && children.isEmpty { Task { await vm.loadReplies(c) } }
                            } label: {
                                Text(expanded ? "Скрыть ответы" : "Ответы (\(c.replyCount))")
                                    .font(.caption.bold())
                                    .foregroundStyle(Theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    if let n = note {
                        Text("Не вышло: " + n).font(.caption2).foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
            }
            if expanded {
                if vm.loadingReplies.contains(c.id) { ProgressView() }
                ForEach(children) { r in
                    CommentRow(c: r, depth: depth + 1, vm: vm)
                }
                .padding(.leading, depth < 2 ? 18 : 0)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ComposeSheet: View {
    let title: String
    let send: (String) async -> String?
    let onSent: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    @State private var sending = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 180)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                if let e = error {
                    Text(e).font(.footnote).foregroundStyle(.orange)
                }
                Spacer()
            }
            .padding(14)
            .background(AppBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(sending ? "…" : "Отправить") {
                        Task {
                            sending = true
                            error = await send(text.trimmingCharacters(in: .whitespacesAndNewlines))
                            sending = false
                            if error == nil { onSent(); dismiss() }
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                }
            }
        }
    }
}

struct CommentsView: View {
    let anime: Anime
    @StateObject private var vm: CommentsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCompose = false

    init(anime: Anime) {
        self.anime = anime
        _vm = StateObject(wrappedValue: CommentsViewModel(animeID: anime.id, slug: anime.slugUrl ?? String(anime.id)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(vm.items) { c in
                        CommentRow(c: c, vm: vm)
                            .onAppear {
                                if c.id == vm.items.last?.id { Task { await vm.loadMore() } }
                            }
                    }
                    if vm.isLoading { ProgressView().padding() }
                    if let e = vm.error {
                        Text(e).font(.footnote).foregroundStyle(.red).padding(.top, 30)
                    }
                    if vm.items.isEmpty && !vm.isLoading {
                        if vm.error == nil {
                            Text("Комментариев пока нет").foregroundStyle(.secondary).padding(.top, 30)
                        }
                        if !vm.debug.isEmpty {
                            Text(vm.debug)
                                .font(.system(size: 9, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
            }
            .background(AppBackground())
            .navigationTitle("Комментарии")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCompose = true } label: { Image(systemName: "square.and.pencil") }
                }
            }
            .sheet(isPresented: $showCompose) {
                ComposeSheet(title: "Новый комментарий",
                             send: { await vm.send($0, parent: nil) },
                             onSent: { Task { await vm.reload() } })
            }
            .sheet(item: $vm.replyTarget) { target in
                ComposeSheet(title: "Ответ для \(target.username)",
                             send: { await vm.send($0, parent: target.id) },
                             onSent: { Task { await vm.reload() } })
            }
            .task { await vm.loadMore() }
        }
    }
}

// MARK: - Вход через сайт и профиль
struct ProfileUser {
    let id: Int
    let username: String
    let avatar: URL?
    var streak: Int? = nil
    var maxStreak: Int? = nil
    var level: Int? = nil
    var premium = false
}

@MainActor
final class AuthStore: ObservableObject {
    static let shared = AuthStore()
    @Published var token: String?
    @Published var user: ProfileUser?
    @Published var error: String?

    init() {
        token = Keychain.get("lib.token")
        if token != nil { Task { await refreshUser() } }
    }

    func signIn(access: String, refresh: String?) async {
        token = access
        Keychain.set(access, key: "lib.token")
        if let r = refresh { Keychain.set(r, key: "lib.refresh") }
        await refreshUser()
    }

    func signOut() {
        token = nil
        user = nil
        Keychain.delete("lib.token")
        Keychain.delete("lib.refresh")
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                modifiedSince: .distantPast) {}
    }

    func refreshUser() async {
        guard let t = token else { return }
        do {
            let data = try await AnimelibAPI.shared.rawData("/auth/me", token: t)
            guard let root = J.obj(data) as? [String: Any] else { throw APIError.badURL }
            let d = (root["data"] as? [String: Any]) ?? root
            guard let id = J.int(d["id"]) else { throw APIError.badURL }
            let st = d["login_streak"] as? [String: Any]
            user = ProfileUser(id: id,
                               username: J.str(d["username"]) ?? J.str(d["name"]) ?? "Профиль",
                               avatar: J.url(d["avatar"]),
                               streak: J.int(st?["login_streak"]) ?? J.int(d["login_streak"]),
                               maxStreak: J.int(st?["max_login_streak"]),
                               level: J.int(d["level"]) ?? J.int((d["user_level"] as? [String: Any])?["level"]),
                               premium: ((d["premium"] as? [String: Any])?["enabled"] as? Bool) ?? false)
            error = nil
        } catch {
            if case APIError.http(let code, _) = error, code == 401 || code == 403 {
                signOut()
                self.error = "Сессия закончилась, войдите снова"
            } else {
                self.error = error.localizedDescription
            }
        }
    }
}

struct LoginWebView: UIViewRepresentable {
    var onToken: (String, String?) -> Void

    final class Coordinator {
        var timer: Timer?
        weak var web: WKWebView?
        var onToken: ((String, String?) -> Void)?
        var done = false
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let v = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        v.customUserAgent = Kodik.ua
        v.isOpaque = false
        v.backgroundColor = .black
        v.load(URLRequest(url: URL(string: "https://animelib.org/ru/")!))
        let c = context.coordinator
        c.web = v
        c.onToken = onToken
        c.timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak c] _ in
            guard let c = c, let web = c.web, !c.done else { return }
            web.evaluateJavaScript("JSON.stringify(Object.assign({}, window.localStorage))") { res, _ in
                guard let s = res as? String,
                      let data = s.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data),
                      let tok = LoginWebView.findToken(obj) else { return }
                c.done = true
                c.timer?.invalidate()
                DispatchQueue.main.async { c.onToken?(tok.0, tok.1) }
            }
        }
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) { context.coordinator.onToken = onToken }

    static func dismantleUIView(_ v: WKWebView, coordinator: Coordinator) {
        coordinator.timer?.invalidate()
    }

    static func findToken(_ obj: Any) -> (String, String?)? {
        if let d = obj as? [String: Any] {
            if let a = d["access_token"] as? String, !a.isEmpty { return (a, d["refresh_token"] as? String) }
            for v in d.values { if let r = findToken(v) { return r } }
        } else if let arr = obj as? [Any] {
            for v in arr { if let r = findToken(v) { return r } }
        } else if let s = obj as? String, s.hasPrefix("{") || s.hasPrefix("["),
                  let data = s.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: data) {
            return findToken(o)
        }
        return nil
    }
}

struct LoginSheet: View {
    @ObservedObject private var auth = AuthStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Войдите на сайте как обычно. Как только вход завершится, приложение подхватит его само.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(10)
                LoginWebView { access, refresh in
                    Task {
                        await auth.signIn(access: access, refresh: refresh)
                        dismiss()
                    }
                }
            }
            .background(AppBackground())
            .navigationTitle("Вход через сайт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
            }
        }
    }
}

struct BookmarkFolder: Identifiable, Hashable {
    let id: Int
    let name: String
    let count: Int?
}

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var folders: [BookmarkFolder] = []
    @Published var selected: Int?
    @Published var items: [Anime] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var debug = ""
    var totalTitles: Int { folders.compactMap { $0.count }.reduce(0, +) }

    private var userID: Int?
    private var token: String?
    private var page = 1
    private var finished = false

    func configure(userID: Int, token: String) {
        self.userID = userID
        self.token = token
    }

    func loadFolders() async {
        guard let uid = userID, let t = token else { return }
        do {
            let data = try await AnimelibAPI.shared.rawData("/bookmarks/folder/\(uid)", token: t)
            guard let root = J.obj(data) as? [String: Any],
                  let arr = root["data"] as? [[String: Any]] else {
                error = "Неожиданный ответ сервера для списков"
                debug = await AnimelibAPI.shared.rawText("/bookmarks/folder/\(uid)", token: t)
                return
            }
            folders = arr.compactMap { d -> BookmarkFolder? in
                guard let id = J.int(d["id"]) else { return nil }
                return BookmarkFolder(id: id,
                                      name: J.str(d["name"]) ?? J.str(d["title"]) ?? "Список",
                                      count: J.int(d["count"]) ?? J.int(d["items_count"]) ?? J.int(d["titles_count"]))
            }
            if selected == nil || !folders.contains(where: { $0.id == selected }) {
                selected = folders.first?.id
            }
            error = nil
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func select(_ id: Int) async {
        selected = id
        await reload()
    }

    func reload() async {
        items = []
        page = 1
        finished = false
        debug = ""
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, !finished, let uid = userID, let t = token else { return }
        isLoading = true
        defer { isLoading = false }
        var query = [URLQueryItem(name: "user_id", value: String(uid)),
                     URLQueryItem(name: "page", value: String(page))]
        if let s = selected { query.append(URLQueryItem(name: "status", value: String(s))) }
        do {
            let data = try await AnimelibAPI.shared.rawData("/bookmarks", query: query, token: t)
            guard let root = J.obj(data) as? [String: Any],
                  let arr = root["data"] as? [[String: Any]] else { finished = true; return }
            let list = arr.compactMap { Self.anime(from: $0) }
            let known = Set(items.map { $0.id })
            let fresh = list.filter { !known.contains($0.id) }
            items += fresh
            page += 1
            if fresh.isEmpty { finished = true }
            error = nil
            if items.isEmpty {
                debug = await AnimelibAPI.shared.rawText("/bookmarks", query: query, token: t)
            }
        } catch {
            finished = true
            self.error = error.localizedDescription
        }
    }

    static func anime(from d: [String: Any]) -> Anime? {
        var candidates: [[String: Any]] = []
        for v in d.values { if let sub = v as? [String: Any] { candidates.append(sub) } }
        candidates.append(d)
        var best: (Int, Anime)?
        for c in candidates {
            guard J.int(c["id"]) != nil else { continue }
            var score = 0
            if J.str(c["rus_name"]) != nil { score += 4 }
            if J.str(c["name"]) != nil { score += 2 }
            if c["cover"] != nil { score += 2 }
            if J.str(c["slug_url"]) != nil { score += 1 }
            guard score >= 3,
                  let data = try? JSONSerialization.data(withJSONObject: c),
                  let a = try? JSONDecoder().decode(Anime.self, from: data) else { continue }
            if best == nil || score > best!.0 { best = (score, a) }
        }
        return best?.1
    }
}

struct BookmarkSheet: View {
    let anime: Anime
    @ObservedObject private var auth = AuthStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var folders: [BookmarkFolder] = []
    @State private var message: String?
    @State private var done: Int?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if auth.token == nil {
                        Text("Войдите во вкладке «Профиль», чтобы добавлять тайтлы в свои списки на сайте.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 40)
                    } else {
                        ForEach(folders) { f in
                            Button { Task { await add(f) } } label: {
                                HStack {
                                    Text(f.name).foregroundStyle(.primary)
                                    Spacer()
                                    if done == f.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                                    }
                                }
                                .padding(14)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .disabled(busy)
                        }
                        if !folders.isEmpty {
                            Button(role: .destructive) { Task { await remove() } } label: {
                                Text("Убрать из списков").frame(maxWidth: .infinity).padding(12)
                            }
                            .disabled(busy)
                        }
                    }
                    if let m = message {
                        Text(m).font(.footnote).foregroundStyle(.orange).padding(.top, 6)
                    }
                }
                .padding(14)
            }
            .background(AppBackground())
            .navigationTitle("В список")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } } }
            .task { await loadFolders() }
        }
    }

    private func loadFolders() async {
        guard let t = auth.token, let uid = auth.user?.id else { return }
        do {
            let data = try await AnimelibAPI.shared.rawData("/bookmarks/folder/\(uid)", token: t)
            guard let root = J.obj(data) as? [String: Any],
                  let arr = root["data"] as? [[String: Any]] else { return }
            folders = arr.compactMap { d in
                guard let id = J.int(d["id"]) else { return nil }
                return BookmarkFolder(id: id, name: J.str(d["name"]) ?? J.str(d["title"]) ?? "Список", count: nil)
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func add(_ f: BookmarkFolder) async {
        guard let t = auth.token else { return }
        busy = true
        defer { busy = false }
        let bodies: [[String: Any]] = [
            ["id": anime.id, "type": f.id, "model": "anime"],
            ["bookmark": ["type": f.id], "id": anime.id, "model": "anime"],
            ["type": f.id, "relation_id": anime.id, "relation_type": "anime"]
        ]
        var last = ""
        for b in bodies {
            do {
                _ = try await AnimelibAPI.shared.rawData("/bookmarks", token: t, method: "POST", json: b)
                done = f.id
                message = nil
                return
            } catch {
                last = error.localizedDescription
            }
        }
        message = "Не получилось добавить: " + last
    }

    private func remove() async {
        guard let t = auth.token else { return }
        busy = true
        defer { busy = false }
        for q in [[URLQueryItem(name: "type", value: "anime")], []] {
            do {
                _ = try await AnimelibAPI.shared.rawData("/bookmarks/\(anime.id)", query: q, token: t, method: "DELETE")
                done = nil
                message = "Убрано из списков"
                return
            } catch {
                message = "Не получилось убрать: " + error.localizedDescription
            }
        }
    }
}

struct ProfileView: View {
    @ObservedObject private var auth = AuthStore.shared
    @StateObject private var vm = ProfileViewModel()
    @State private var showLogin = false
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    private func stat(_ icon: String, _ tint: Color, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let u = auth.user {
                    VStack(spacing: 16) {
                        VStack(spacing: 12) {
                            HStack(spacing: 14) {
                                RemoteImage(url: u.avatar)
                                    .frame(width: 72, height: 72)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Theme.accent, lineWidth: 2))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(u.username).font(.title3.bold())
                                    if u.premium {
                                        Label("Premium", systemImage: "crown.fill")
                                            .font(.caption.bold())
                                            .foregroundStyle(.yellow)
                                    }
                                    Button("Выйти") { auth.signOut() }
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                }
                                Spacer()
                            }
                            HStack(spacing: 8) {
                                if let st = u.streak { stat("flame.fill", .orange, "Серия: \(st) дн.") }
                                if let lv = u.level { stat("star.fill", .yellow, "Уровень \(lv)") }
                                if vm.totalTitles > 0 { stat("rectangle.stack.fill", Theme.accent, "\(vm.totalTitles) тайтлов") }
                                Spacer(minLength: 0)
                            }
                        }
                        .padding(14)
                        .background(
                            LinearGradient(colors: [Theme.accent.opacity(0.35), Color.white.opacity(0.05)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.12)))

                        if !vm.folders.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(vm.folders) { f in
                                        Button { Task { await vm.select(f.id) } } label: {
                                            Text(f.count.map { "\(f.name) · \($0)" } ?? f.name)
                                                .font(.subheadline.weight(.semibold))
                                                .padding(.horizontal, 14).padding(.vertical, 8)
                                                .background(f.id == vm.selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Material.ultraThinMaterial), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        if let e = vm.error {
                            Text(e).font(.footnote).foregroundStyle(.red)
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
                        if vm.isLoading { ProgressView() }
                        if vm.items.isEmpty && !vm.isLoading {
                            Text("В этом списке пока ничего нет").foregroundStyle(.secondary)
                            if !vm.debug.isEmpty {
                                Text(vm.debug)
                                    .font(.system(size: 9, design: .monospaced))
                                    .textSelection(.enabled)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(14)
                } else if auth.token != nil {
                    VStack(spacing: 12) {
                        ProgressView()
                        if let e = auth.error {
                            Text(e).font(.footnote).foregroundStyle(.red)
                            Button("Повторить") { Task { await auth.refreshUser() } }
                            Button("Выйти") { auth.signOut() }.foregroundStyle(.red)
                        }
                    }
                    .padding(.top, 80)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Theme.accent)
                        Text("Профиль").font(.title2.bold())
                        Text("Войдите через сайт, чтобы видеть свои списки: смотрю, в планах, просмотрено и другие.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        if let e = auth.error {
                            Text(e).font(.footnote).foregroundStyle(.orange)
                        }
                        Button { showLogin = true } label: {
                            Text("Войти через сайт")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(24)
                    .padding(.top, 40)
                }
            }
            .background(AppBackground())
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Anime.self) { DetailView(anime: $0) }
            .sheet(isPresented: $showLogin) { LoginSheet() }
            .task(id: auth.user?.id) {
                if let u = auth.user, let t = auth.token {
                    vm.configure(userID: u.id, token: t)
                    await vm.loadFolders()
                }
            }
        }
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
