import SwiftUI
import AVKit
import AVFoundation
import Foundation
import WebKit
import Security
import Network
import Combine
import ImageIO
import UniformTypeIdentifiers

// MARK: - Тема и общие элементы дизайна

enum Theme {
    static let defaultAccentHex = "A87AFF"
    /// Акцентный цвет берётся из настроек и меняется на лету.
    private static var cachedHex = ""
    private static var cachedColor = Color(hex: defaultAccentHex)
    private static var cachedSecondary = Color(hex: defaultAccentHex)
    private static var dirty = true
    private static let observer: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in Theme.dirty = true }

    /// Второй цвет фона: тот же акцент, сдвинутый по оттенку. Меняется вместе с акцентом.
    private static func shifted(_ hex: String) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(Color(hex: hex)).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let nh = (h + 0.07).truncatingRemainder(dividingBy: 1)
        return Color(hue: Double(nh), saturation: Double(s), brightness: Double(b))
    }

    private static func refresh() {
        _ = observer
        guard dirty else { return }
        dirty = false
        let hex = UserDefaults.standard.string(forKey: "accent.hex") ?? defaultAccentHex
        if hex != cachedHex {
            cachedHex = hex
            cachedColor = Color(hex: hex)
            cachedSecondary = shifted(hex)
        }
    }

    static var accent2: Color { refresh(); return cachedSecondary }

    /// Цвета, которые сами подстраиваются под светлую и тёмную тему.
    static let card = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.08) : UIColor(white: 0, alpha: 0.06) })
    static let chip = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.10) : UIColor(white: 0, alpha: 0.08) })
    static let base = Color(uiColor: .systemBackground)

    static var accent: Color { refresh(); return cachedColor }
}

/// Сайт сети Lib, с которым сейчас работает приложение (аниме или ранобэ).
struct LibSite: Hashable {
    let key: String
    let id: String
    let referer: String
    let origin: String
    let apiPath: String
    let postType: String
    let title: String

    var isRanobe: Bool { key == "ranobe" }
    var isManga: Bool { key == "manga" || key == "hentai" }
    var isHentai: Bool { key == "hentai" }
    /// Ранобэ и манга устроены одинаково: тайтл, тома и главы.
    var isBook: Bool { key != "anime" }

    static let anime = LibSite(key: "anime", id: "5", referer: "https://v5.animelib.org/",
                               origin: "https://v5.animelib.org", apiPath: "/anime",
                               postType: "anime", title: "Аниме")
    static let ranobe = LibSite(key: "ranobe", id: "3", referer: "https://ranobelib.me/",
                                origin: "https://ranobelib.me", apiPath: "/manga",
                                postType: "manga", title: "Ранобэ")

    static let manga = LibSite(key: "manga", id: "1", referer: "https://mangalib.me/",
                               origin: "https://mangalib.me", apiPath: "/manga",
                               postType: "manga", title: "Манга")

    static let hentai = LibSite(key: "hentai", id: "4", referer: "https://kz.hentailib.me/",
                                origin: "https://kz.hentailib.me", apiPath: "/manga",
                                postType: "manga", title: "Hentai")

    static var current: LibSite {
        switch UserDefaults.standard.string(forKey: "set.platform") {
        case "ranobe": return .ranobe
        case "manga": return .manga
        case "hentai": return .hentai
        default: return .anime
        }
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            Theme.base
            RadialGradient(colors: [Theme.accent.opacity(dark ? 0.35 : 0.22), .clear],
                           center: .topLeading, startRadius: 20, endRadius: 460)
            RadialGradient(colors: [Theme.accent2.opacity(dark ? 0.24 : 0.14), .clear],
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
        Button { Haptics.select(); action() } label: {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.chip), in: Capsule())
        }
        .buttonStyle(.pressable)
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
            .background(Theme.chip, in: Capsule())
    }
}

// MARK: - Страница тайтла: общие детали оформления
struct GlassPill: View {
    let icon: String
    let text: String
    var tint: Color? = nil
    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint ?? Color.primary)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .glassCapsule()
    }
}

struct TitleHero: View {
    let cover: URL?
    let title: String
    let subtitle: String?
    let pills: [(String, String)]
    var body: some View {
        VStack(spacing: 14) {
            RemoteImage(url: cover, maxPixel: 700)
                .frame(width: 172, height: 258)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
            VStack(spacing: 5) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 8)
            if !pills.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(pills.enumerated()), id: \.offset) { _, p in
                            GlassPill(icon: p.0, text: p.1, tint: p.0 == "star.fill" ? .yellow : nil)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

struct PrimaryActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.headline)
                Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .leading, endPoint: .trailing),
                        in: Capsule())
            .shadow(color: Theme.accent.opacity(0.45), radius: 14, y: 6)
        }
        .buttonStyle(.pressable)
    }
}

struct GenreStrip: View {
    let genres: [NamedItem]
    var tags: [NamedItem] = []
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(genres.enumerated()), id: \.offset) { _, g in
                    Button {
                        guard let id = g.id else { return }
                        Haptics.tap()
                        AppRouter.shared.openCatalog(genre: id)
                    } label: {
                        Text(g.title)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Theme.accent.opacity(0.2), in: Capsule())
                            .overlay(Capsule().stroke(Theme.accent.opacity(0.35), lineWidth: 0.6))
                    }
                    .buttonStyle(.pressable)
                }
                ForEach(Array(tags.enumerated()), id: \.offset) { _, t in
                    Button {
                        guard let id = t.id else { return }
                        Haptics.tap()
                        AppRouter.shared.openCatalog(tag: id)
                    } label: {
                        Text("#" + t.title)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Theme.chip, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }
}

struct SummaryCard: View {
    let text: String
    @Binding var expanded: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text).font(.callout).lineSpacing(3).lineLimit(expanded ? nil : 5)
            if text.count > 220 {
                Button(expanded ? "Свернуть" : "Читать полностью") {
                    withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 0.5))
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
    let slug: String?
    var title: String { name ?? label ?? "" }

    enum CodingKeys: String, CodingKey { case id, name, label, slug = "slug_url" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id))
            ?? (try? c.decode(String.self, forKey: .id)).flatMap { Int($0) }
        name = try? c.decode(String.self, forKey: .name)
        label = try? c.decode(String.self, forKey: .label)
        slug = try? c.decode(String.self, forKey: .slug)
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

struct RatingBox: Decodable {
    let average: String?
    let votes: Int?
    enum K: String, CodingKey { case average, votes }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        if let v = try? c.decode(Int.self, forKey: .votes) { votes = v }
        else if let sv = try? c.decode(String.self, forKey: .votes), let v = Int(sv) { votes = v }
        else { votes = nil }
        if let s = try? c.decode(String.self, forKey: .average) { average = s }
        else if let x = try? c.decode(Double.self, forKey: .average) { average = String(format: "%.1f", x) }
        else { average = nil }
    }
}

struct Anime: Codable, Identifiable, Hashable {
    private enum RatingKeys: String, CodingKey { case rating }

    let id: Int
    let name: String?
    let rusName: String?
    let engName: String?
    let slugUrl: String?
    let cover: Cover?
    let summary: String?
    let genres: [NamedItem]?
    let tags: [NamedItem]?
    let authors: [NamedItem]?
    let otherNames: [String]?
    let episodesCount: Int?
    let rateAvg: String?
    let rateVotes: Int?
    let status: NamedItem?
    let type: NamedItem?
    let ageRestriction: NamedItem?
    let releaseDateString: String?

    var displayTitle: String {
        if let r = rusName, !r.isEmpty { return r }
        return name ?? engName ?? "Без названия"
    }
    /// Для карточек. У манги и ранобэ миниатюра слишком мелкая и выглядит пиксельной, берём средний размер.
    var imageURL: URL? {
        let s = LibSite.current.isBook
            ? (cover?.md ?? cover?.default ?? cover?.thumbnail)
            : (cover?.thumbnail ?? cover?.md ?? cover?.default)
        return s.flatMap(URL.init(string:))
    }
    /// Для крупных карточек на главной: средний размер, чтобы не мылилось.
    var posterURL: URL? {
        (cover?.md ?? cover?.default ?? cover?.thumbnail).flatMap(URL.init(string:))
    }
    /// Для крупной обложки на странице тайтла.
    var largeImageURL: URL? {
        (cover?.default ?? cover?.md ?? cover?.thumbnail).flatMap(URL.init(string:))
    }

    enum CodingKeys: String, CodingKey {
        case id, name, summary, genres, tags, authors, cover, status, type
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
        tags = try? c.decode([NamedItem].self, forKey: .tags)
        authors = try? c.decode([NamedItem].self, forKey: .authors)
        otherNames = try? c.decode([String].self, forKey: .otherNames)
        episodesCount = try? c.decode(Int.self, forKey: .episodesCount)
        status = try? c.decode(NamedItem.self, forKey: .status)
        type = try? c.decode(NamedItem.self, forKey: .type)
        ageRestriction = try? c.decode(NamedItem.self, forKey: .ageRestriction)
        releaseDateString = try? c.decode(String.self, forKey: .releaseDateString)
        rateVotes = (try? decoder.container(keyedBy: RatingKeys.self))
            .flatMap { try? $0.decode(RatingBox.self, forKey: .rating) }?.votes
        if let s = try? c.decode(String.self, forKey: .rateAvg) { rateAvg = s }
        else if let d = try? c.decode(Double.self, forKey: .rateAvg) { rateAvg = String(format: "%.1f", d) }
        else if let rc = try? decoder.container(keyedBy: RatingKeys.self),
                let rb = try? rc.decode(RatingBox.self, forKey: .rating),
                let av = rb.average { rateAvg = av }
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
    var player = ""
    var options: [PlayableVariant] = []
    var alts: [URL] = []
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
        case .http(let c, let body):
            // ответ сайта — JSON с \u-кодами: достаём из него читаемые сообщения
            if let d = body.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) {
                var msgs: [String] = []
                func walk(_ v: Any) {
                    if let s = v as? String { msgs.append(s) }
                    else if let a = v as? [Any] { a.forEach(walk) }
                    else if let o = v as? [String: Any] { o.keys.sorted().forEach { walk(o[$0]!) } }
                }
                walk(obj)
                if !msgs.isEmpty { return "Ошибка \(c): " + msgs.joined(separator: "; ") }
            }
            return "Сервер вернул ошибку \(c): \(body.prefix(200))"
        case .noVideo: return "Для этой серии нет доступного видео"
        }
    }
}

struct CatalogFilter: Equatable {
    var query: String = ""
    var sortBy: SortOption = .views
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

        /// Названия полей сортировки у разных сайтов отличаются, пробуем по очереди.
        func aliases(_ site: LibSite) -> [String] {
            guard site.isBook else { return [rawValue] }
            switch self {
            case .rating: return ["rate_avg", "rating_score"]
            case .views: return ["views"]
            case .newest: return ["created_at"]
            case .lastEpisode: return ["last_chapter_at", "last_episode_at"]
            case .name: return ["name", "rus_name"]
            }
        }

        func label(_ ranobe: Bool) -> String {
            if ranobe && self == .lastEpisode { return "Последние обновления" }
            if ranobe && self == .views { return "По чтению" }
            return title
        }
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

    nonisolated var siteHeaders: [String: String] {
        let site = LibSite.current
        return ["Referer": site.referer, "Origin": site.origin, "Site-Id": site.id]
    }

    nonisolated var playbackHeaders: [String: String] {
        ["Referer": "https://v5.animelib.org/", "Origin": "https://v5.animelib.org"]
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        guard var comps = URLComponents(string: apiURL + path) else { throw APIError.badURL }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError.badURL }
        var req = URLRequest(url: url)
        for (k, v) in siteHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // вошедшему пользователю сайт показывает и тайтлы 18+ (гостям они скрыты)
        let tok = Keychain.get("lib.token")
        if let t = tok { req.setValue("Bearer " + t, forHTTPHeaderField: "Authorization") }
        var (data, resp) = try await session.data(for: req)
        if tok != nil, let http = resp as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
            req.setValue(nil, forHTTPHeaderField: "Authorization")   // токен устарел: пробуем как гость
            (data, resp) = try await session.data(for: req)
        }
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data.prefix(1500), encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, body)
        }
        return try decoder.decode(T.self, from: data)
    }

    func catalog(filter: CatalogFilter, page: Int) async throws -> (items: [Anime], hasNext: Bool) {
        let site = LibSite.current
        var lastError: Error = APIError.badURL
        for sort in filter.sortBy.aliases(site) {
            for withSite in [true, false] {
                do {
                    return try await fetchCatalog(filter: filter, page: page, withSite: withSite, sort: sort, site: site)
                } catch APIError.http(let code, let body) where code == 422 || code == 400 {
                    lastError = APIError.http(code, body)
                }
            }
        }
        throw lastError
    }

    /// «По рейтингу» без тайтлов с парой оценок: иначе наверх попадает всё, что оценили один-два человека на десятку.
    func catalogRated(filter: CatalogFilter, startPage: Int) async throws -> (items: [Anime], hasNext: Bool, next: Int) {
        let minVotes = LibSite.current.isBook ? 20 : 100
        var page = startPage
        var out: [Anime] = []
        var firstRaw: [Anime] = []
        var hasNext = true
        var batches = 0
        var lastError: Error?
        while batches < 6 && hasNext && out.count < 18 {
            let pages = Array(page..<(page + 4))
            // Четыре страницы сразу: наверху рейтинга много тайтлов с парой оценок, их надо быстро пролистать.
            let results: [(Int, [Anime]?, Bool, Error?)] = await withTaskGroup(of: (Int, [Anime]?, Bool, Error?).self) { group in
                for pg in pages {
                    group.addTask {
                        do {
                            let r = try await AnimelibAPI.shared.catalog(filter: filter, page: pg)
                            return (pg, r.items, r.hasNext, nil)
                        } catch {
                            return (pg, nil, false, error)
                        }
                    }
                }
                var all: [(Int, [Anime]?, Bool, Error?)] = []
                for await r in group { all.append(r) }
                return all.sorted { $0.0 < $1.0 }
            }
            var stop = false
            for (_, items, next, err) in results {
                guard let items else { lastError = err; stop = true; break }
                if batches == 0 { firstRaw += items }
                out += items.filter { ($0.rateVotes ?? Int.max) >= minVotes }
                hasNext = next
                if !next { stop = true; break }
            }
            page += pages.count
            batches += 1
            if stop { break }
        }
        if out.isEmpty {
            if firstRaw.isEmpty, let e = lastError { throw e }
            // Фильтр по числу оценок ничего не нашёл: лучше показать список как есть, чем пустой экран.
            out = firstRaw
        }
        return (out, hasNext, page)
    }

    private func fetchCatalog(filter: CatalogFilter, page: Int, withSite: Bool, sort: String, site: LibSite) async throws -> (items: [Anime], hasNext: Bool) {
        var q: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "sort_by", value: sort),
            .init(name: "sort_type", value: "desc"),
        ]
        if withSite { q.append(.init(name: "site_id[]", value: site.id)) }
        let text = filter.query.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { q.append(.init(name: "q", value: text)) }
        for id in filter.genres.sorted() { q.append(.init(name: "genres[]", value: String(id))) }
        for id in filter.tags.sorted() { q.append(.init(name: "tags[]", value: String(id))) }
        for id in filter.types.sorted() { q.append(.init(name: "types[]", value: String(id))) }
        for id in filter.statuses.sorted() { q.append(.init(name: "status[]", value: String(id))) }
        let r = try await get(site.apiPath, query: q, as: Envelope<[Anime]>.self)
        let hasNext = r.meta?.hasNextPage ?? !r.data.isEmpty
        return (r.data, hasNext)
    }

    private var authorParam: [String: String] = [:]

    /// Все тайтлы одного автора. Имя параметра фильтра сайт нигде не описывает,
    /// поэтому пробуем варианты (по id и по slug) и принимаем тот, что реально меняет выдачу.
    func byAuthor(_ id: Int, slug: String?, page: Int) async throws -> (items: [Anime], hasNext: Bool) {
        let site = LibSite.current
        func run(_ extra: [URLQueryItem]) async throws -> (items: [Anime], hasNext: Bool) {
            for withSite in [true, false] {
                var q: [URLQueryItem] = [
                    .init(name: "page", value: String(page)),
                    .init(name: "sort_by", value: "rate_avg"),
                    .init(name: "sort_type", value: "desc")
                ] + extra
                if withSite { q.append(.init(name: "site_id[]", value: site.id)) }
                do {
                    let r = try await get(site.apiPath, query: q, as: Envelope<[Anime]>.self)
                    return (r.data, r.meta?.hasNextPage ?? !r.data.isEmpty)
                } catch APIError.http(let code, _) where (code == 422 || code == 400) && withSite {
                    continue
                }
            }
            throw APIError.badURL
        }
        // Настоящий запрос сайта: тайтлы автора = каталог с target_id и target_model=people.
        if let r = try? await run([.init(name: "target_id", value: String(id)),
                                   .init(name: "target_model", value: "people")]) {
            return r
        }
        // Уже найденный параметр: имя и вид значения («id» или «slug»).
        if let known = authorParam[site.key] {
            let parts = known.split(separator: "|").map(String.init)
            let value = (parts.count > 1 && parts[1] == "slug") ? (slug ?? String(id)) : String(id)
            return try await run([.init(name: parts[0], value: value)])
        }
        let baseline = (try? await run([]))?.items.map { $0.id } ?? []
        let names = ["authors[]", "people[]", "author[]", "peoples[]", "persons[]", "authors", "people",
                     "author", "person", "artists[]", "creators[]", "staff[]", "people_id", "author_id"]
        var values: [(String, String)] = [("id", String(id))]
        if let sl = slug, !sl.isEmpty { values.append(("slug", sl)) }
        var log: [String] = []
        for (kind, value) in values {
            for name in names {
                do {
                    let r = try await run([.init(name: name, value: value)])
                    let ids = r.items.map { $0.id }
                    if !ids.isEmpty && ids != baseline {
                        authorParam[site.key] = "\(name)|\(kind)"
                        return r
                    }
                    log.append("\(name)=\(kind): \(ids.isEmpty ? "пусто" : "как в общем списке")")
                } catch APIError.http(let code, _) {
                    log.append("\(name)=\(kind): \(code)")
                } catch {
                    log.append("\(name)=\(kind): сбой")
                }
            }
        }
        // Запасной путь: страница автора сама может отдавать список его работ.
        let key = (slug?.isEmpty == false) ? slug! : String(id)
        var tryLog: [String] = []
        if page == 1 {
            let tail = site.apiPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            var tries: [(String, [URLQueryItem])] = [("/people/\(key)", [])]
            for f in ["titles", "manga", "anime", "ranobe", "works", "books", "comics", "projects"] {
                tries.append(("/people/\(key)", [.init(name: "fields[]", value: f)]))
            }
            for sub in ["titles", "works", tail, "books", "projects"] {
                tries.append(("/people/\(key)/\(sub)", []))
            }
            for (path, q) in tries {
                let label = path + (q.isEmpty ? "" : "?" + q.map { $0.name + "=" + ($0.value ?? "") }.joined(separator: "&"))
                do {
                    let data = try await rawData(path, query: q)
                    guard let root = J.obj(data) else { tryLog.append("\(label): не JSON"); continue }
                    let found = titlesIn(root)
                    if !found.isEmpty { return (found, false) }
                    tryLog.append("\(label): ответ есть, тайтлов нет")
                } catch APIError.http(let code, _) {
                    tryLog.append("\(label): HTTP \(code)")
                } catch {
                    tryLog.append("\(label): сбой")
                }
            }
        }
        var keys = ""
        if let data = try? await rawData("/people/\(key)"), let root = J.obj(data) as? [String: Any],
           let d = root["data"] as? [String: Any] {
            keys = d.keys.sorted().joined(separator: ", ")
        }
        throw APIError.http(404, "Фильтр по автору не сработал (параметры каталога не меняют выдачу).\n"
                            + tryLog.joined(separator: "\n") + "\nПоля автора: " + keys)
    }

    /// Собирает тайтлы из любого ответа: объекты с id и slug_url (авторов, людей и команды пропускаем).
    private func titlesIn(_ root: Any, onlyAnime: Bool = false) -> [Anime] {
        var out: [Anime] = []
        var seen = Set<Int>()
        let siteKey = LibSite.current.key
        func walk(_ v: Any) {
            if let d = v as? [String: Any] {
                let model = (d["model"] as? String)?.lowercased() ?? ""
                let isTitleLike = J.int(d["id"]) != nil && d["slug_url"] != nil
                    && !["people", "user", "team"].contains(model)
                let sameSite = !["anime", "manga", "ranobe", "hentai"].contains(model) || model == siteKey
                let wanted = onlyAnime ? (model == "anime" && isTitleLike) : sameSite
                if isTitleLike, wanted,
                   let data = try? JSONSerialization.data(withJSONObject: d),
                   let a = try? decoder.decode(Anime.self, from: data) {
                    if seen.insert(a.id).inserted { out.append(a) }
                    return
                }
                for x in d.values { walk(x) }
            } else if let arr = v as? [Any] {
                for x in arr { walk(x) }
            }
        }
        walk(root)
        return out
    }

    /// «Похожие» и «Связанное» для карточки тайтла (формат ответа разбираем мягко).
    func similarTitles(slug: String) async -> (similar: [Anime], related: [Anime], adapt: [Anime], note: String) {
        let base = LibSite.current.apiPath + "/" + slug
        var notes: [String] = []
        var lists: [[Anime]] = []
        var adapt: [Anime] = []
        for sub in ["similar", "relations"] {
            do {
                let data = try await rawData(base + "/" + sub)
                if let root = J.obj(data) {
                    lists.append(titlesIn(root).filter { $0.slugUrl != slug })
                    if sub == "relations", LibSite.current.isBook { adapt = titlesIn(root, onlyAnime: true) }
                } else {
                    lists.append([])
                    notes.append("\(sub): не JSON")
                }
            } catch {
                lists.append([])
                notes.append("\(sub): \(error.localizedDescription)")
            }
        }
        let sim = lists[0]
        let simIDs = Set(sim.map { $0.id })
        let rel = lists[1].filter { !simIDs.contains($0.id) }
        return (sim, rel, adapt, notes.joined(separator: "; "))
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
        for (k, v) in siteHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // у HentaiLib контент закрыт для гостей: отправляем токен вошедшего пользователя
        let auth = token ?? Keychain.get("lib.token")
        if let t = auth { req.setValue("Bearer " + t, forHTTPHeaderField: "Authorization") }
        req.httpMethod = method
        if let j = json {
            req.httpBody = try JSONSerialization.data(withJSONObject: j)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        var (data, resp) = try await session.data(for: req)
        if token == nil, auth != nil, let http = resp as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
            req.setValue(nil, forHTTPHeaderField: "Authorization")
            (data, resp) = try await session.data(for: req)
        }
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode, String(data: data.prefix(1500), encoding: .utf8) ?? "")
        }
        return data
    }

    func rawText(_ path: String, query: [URLQueryItem] = [], token: String? = nil) async -> String {
        guard var comps = URLComponents(string: apiURL + path) else { return "bad url" }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { return "bad url" }
        var req = URLRequest(url: url)
        for (k, v) in siteHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
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
        let path = LibSite.current.apiPath + "/" + slug
        if let a = try? await get(path, query: query(base + ["tags", "rate_avg"]), as: Envelope<Anime>.self).data { return a }
        do {
            return try await get(path, query: query(base + ["rate_avg"]), as: Envelope<Anime>.self).data
        } catch {
            return try await get(path, query: query(base), as: Envelope<Anime>.self).data
        }
    }

    /// Сколько серий/глав у тайтла и когда вышла последняя (если сайт сообщает дату).
    func updateInfo(slug: String?) async -> (count: Int?, date: String?) {
        guard let slug, !slug.isEmpty else { return (nil, nil) }
        let path = LibSite.current.apiPath + "/" + slug
        guard let data = try? await rawData(path), let root = J.obj(data) else { return (nil, nil) }
        return FavUpdate.parse(root)
    }

    func episodes(animeID: Int) async throws -> [EpisodeShort] {
        let q = [URLQueryItem(name: "anime_id", value: String(animeID))]
        return try await get("/episodes", query: q, as: Envelope<[EpisodeShort]>.self).data
    }

    func episodeDetail(id: Int) async throws -> EpisodeDetail {
        try await get("/episodes/\(id)", as: Envelope<EpisodeDetail>.self).data
    }

    private(set) var variantNote = ""

    private func videoServers() async throws -> [VideoServer] {
        if let c = cachedServers, !c.isEmpty { return c }
        let q = [URLQueryItem(name: "fields[]", value: "videoServers")]
        let data = try await rawData("/constants", query: q)
        guard let root = J.obj(data) as? [String: Any] else { return [] }
        let d = (root["data"] as? [String: Any]) ?? root
        let arr = (d["videoServers"] as? [[String: Any]]) ?? []
        let list = arr.compactMap { e -> VideoServer? in
            guard let u = J.str(e["url"]) else { return nil }
            return VideoServer(id: J.str(e["id"]), label: J.str(e["label"]), url: u)
        }
        if !list.isEmpty { cachedServers = list }
        return list
    }

    func variants(episodeID: Int) async throws -> [PlayableVariant] {
        let token = Keychain.get("lib.token")
        async let dataTask = rawData("/episodes/\(episodeID)", token: token)
        async let serversTask = videoServers()
        let data = try await dataTask
        let servers = (try? await serversTask) ?? []
        let mainServer = servers.first { ($0.id ?? "").lowercased().contains("main") } ?? servers.first
        let base: String? = mainServer?.url
        let otherBases: [String] = servers.compactMap { $0.url }.filter { $0 != base }

        guard let root = J.obj(data) as? [String: Any] else { throw APIError.badURL }
        let d = (root["data"] as? [String: Any]) ?? root
        let players = (d["players"] as? [[String: Any]]) ?? []

        var native: [PlayableVariant] = []
        var web: [PlayableVariant] = []
        var seen: [String: Int] = [:]
        for p in players {
            let name = J.str(p["player"]) ?? ""
            seen[name, default: 0] += 1
            let team = J.str((p["team"] as? [String: Any])?["name"]) ?? "—"
            let tt = p["translation_type"] as? [String: Any]
            let kind = J.str(tt?["label"]) ?? J.str(tt?["title"]) ?? J.str(tt?["name"]) ?? ""
            let label = kind.isEmpty ? team : "\(team) (\(kind))"

            if name.lowercased() == "animelib" {
                guard let base = base else { continue }
                let video = p["video"] as? [String: Any]
                let list = (video?["quality"] as? [[String: Any]]) ?? []
                let sub: URL? = ((p["subtitles"] as? [[String: Any]])?.first).flatMap { J.str($0["src"]) }
                    .flatMap { URL(string: absolute($0, base: base)) }
                var options: [PlayableVariant] = []
                for q in list.sorted(by: { (J.int($0["quality"]) ?? 0) > (J.int($1["quality"]) ?? 0) }) {
                    guard let href = J.str(q["href"]), let url = URL(string: absolute(href, base: base)) else { continue }
                    let h = J.int(q["quality"]).map { "\($0)p" } ?? "—"
                    var opt = PlayableVariant(title: h, url: url, subtitle: sub)
                    opt.alts = otherBases.compactMap { URL(string: absolute(href, base: $0)) }
                    options.append(opt)
                }
                guard let best = options.first else { continue }
                var v = PlayableVariant(title: label, url: best.url, subtitle: sub)
                v.player = "Animelib"
                v.options = options
                native.append(v)
            } else if let src = J.str(p["src"]) {
                let full = src.hasPrefix("//") ? "https:" + src : src
                if let url = URL(string: full) {
                    let isK = full.contains("kodik")
                    var v = PlayableVariant(title: "\(label) · \(name.isEmpty ? "Плеер" : name)", url: url,
                                            subtitle: nil, isWeb: true, kodik: isK)
                    v.player = name.isEmpty ? "Плеер" : name
                    web.append(v)
                }
            }
        }

        var note = ""
        if native.isEmpty {
            let list = seen.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: ", ")
            if seen.keys.contains(where: { $0.lowercased() == "animelib" }) {
                note = base == nil
                    ? "Animelib: адрес видео-сервера не получен (в ответе: \(list))"
                    : "Animelib: в ответе есть плеер, но без ссылок на видео"
            } else {
                note = "Animelib: сервер не отдал этот плеер (в ответе: \(list.isEmpty ? "пусто" : list))"
            }
        }
        variantNote = note

        let result = native + web
        if result.isEmpty { throw APIError.noVideo }
        return result
    }

    private func absolute(_ href: String, base: String) -> String {
        if href.hasPrefix("http") { return href }
        if href.hasPrefix("//") { return "https:" + href }
        let b = base.hasSuffix("/") ? String(base.dropLast()) : base
        let h = href.hasPrefix("/") ? href : "/" + href
        return b + "/" + h
    }
}

enum Haptics {
    private static var on: Bool { Settings.bool("set.haptics", true) }
    static func tap() { if on { UIImpactFeedbackGenerator(style: .light).impactOccurred() } }
    static func select() { if on { UISelectionFeedbackGenerator().selectionChanged() } }
    static func success() { if on { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    static func bump() { if on { UIImpactFeedbackGenerator(style: .medium).impactOccurred() } }
}

/// Адрес тайтла на сайте (для «Поделиться»).
func titleURL(_ a: Anime) -> URL? {
    guard let slug = a.slugUrl else { return nil }
    switch LibSite.current.key {
    case "ranobe": return URL(string: "https://ranobelib.me/ru/book/\(slug)")
    case "manga": return URL(string: "https://mangalib.me/ru/manga/\(slug)")
    case "hentai": return URL(string: "https://kz.hentailib.me/ru/manga/\(slug)")
    default: return URL(string: "https://animelib.org/ru/anime/\(slug)")
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

// MARK: - Images (с заголовком Referer)
final class ImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 260 * 1024 * 1024
        c.countLimit = 500
        return c
    }()

    static func key(_ url: URL, _ px: CGFloat) -> NSString { "\(url.absoluteString)#\(Int(px))" as NSString }

    static func store(_ img: UIImage, _ key: NSString) {
        let cost = Int(img.size.width * img.scale * img.size.height * img.scale * 4)
        shared.setObject(img, forKey: key, cost: cost)
    }
}

/// Загрузка картинок: общий дисковый кэш, один запрос на один адрес,
/// декодирование и уменьшение вне главного потока.
actor ImageLoader {
    static let shared = ImageLoader()
    private let session: URLSession
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 24 * 1024 * 1024, diskCapacity: 500 * 1024 * 1024, diskPath: "hehe-images")
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.httpMaximumConnectionsPerHost = 8
        cfg.timeoutIntervalForRequest = 20
        session = URLSession(configuration: cfg)
    }

    func clearDisk() { session.configuration.urlCache?.removeAllCachedResponses() }

    func image(_ url: URL, referer: String, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(url.absoluteString)#\(Int(maxPixel))"
        if let t = inflight[key] { return await t.value }
        let session = self.session
        let t = Task.detached(priority: .userInitiated) { () -> UIImage? in
            for attempt in 0..<3 {
                if Task.isCancelled { return nil }
                var req = URLRequest(url: url)
                req.setValue(referer, forHTTPHeaderField: "Referer")
                req.setValue("image/*", forHTTPHeaderField: "Accept")
                if let (data, resp) = try? await session.data(for: req),
                   (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                   let img = ImageLoader.downsample(data, maxPixel: maxPixel) {
                    return img
                }
                try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (attempt + 1)))
            }
            return nil
        }
        inflight[key] = t
        let r = await t.value
        inflight[key] = nil
        return r
    }

    /// Для страниц манги: уменьшаем по ширине (не больше width пикселей), а длинным лентам разрешаем большую высоту.
    nonisolated static func downsampleWidth(_ data: Data, width: CGFloat, maxSide: CGFloat) -> UIImage? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOpts) else { return nil }
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let pw = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let ph = props[kCGImagePropertyPixelHeight] as? CGFloat, pw > 0, ph > 0 else {
            return downsample(data, maxPixel: 4096)
        }
        // Обычные страницы держим крупнее, чтобы при зуме не мылились; длинные ленты — как было.
        let target = ph / pw <= 2.2 ? width * 1.7 : width
        let scale = min(1, target / pw)
        let side = min(max(pw, ph) * scale, maxSide)
        return downsample(data, maxPixel: max(side, 64))
    }

    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOpts) else { return nil }
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return nil }
        return UIImage(cgImage: cg)
    }
}

extension ImageLoader {
    /// Заранее подгружает обложки, которые ещё не показаны на экране.
    nonisolated static func prefetch(_ urls: [URL], maxPixel: CGFloat = 480) {
        let list = Array(urls.prefix(40))
        guard !list.isEmpty else { return }
        let referer = LibSite.current.referer
        Task.detached(priority: .utility) {
            var start = 0
            while start < list.count {
                let chunk = Array(list[start..<min(start + 4, list.count)])
                start += 4
                await withTaskGroup(of: Void.self) { group in
                    for u in chunk {
                        group.addTask {
                            let key = ImageCache.key(u, maxPixel)
                            if ImageCache.shared.object(forKey: key) != nil { return }
                            if let img = await ImageLoader.shared.image(u, referer: referer, maxPixel: maxPixel) {
                                ImageCache.store(img, key)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Анимированные картинки (GIF, WebP, APNG)
enum AnimatedLoader {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 60_000_000
        return c
    }()

    static func cached(_ url: URL, _ px: CGFloat) -> UIImage? {
        cache.object(forKey: "\(url.absoluteString)#\(Int(px))" as NSString)
    }

    static func load(_ url: URL, maxPixel: CGFloat, referer: String) async -> UIImage? {
        let key = "\(url.absoluteString)#\(Int(maxPixel))" as NSString
        if let c = cache.object(forKey: key) { return c }
        let img = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            var req = URLRequest(url: url)
            req.setValue(referer, forHTTPHeaderField: "Referer")
            req.setValue("image/*", forHTTPHeaderField: "Accept")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
            else { return nil }
            return AnimatedLoader.decode(data, maxPixel: maxPixel)
        }.value
        if let img {
            let frames = max(1, img.images?.count ?? 1)
            cache.setObject(img, forKey: key, cost: Int(img.size.width * img.size.height * 4) * frames)
        }
        return img
    }

    nonisolated static func decode(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let n = CGImageSourceGetCount(src)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        if n <= 1 {
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }
        // Ключи ImageIO для GIF, WebP и APNG записаны строками: так они есть во всех версиях SDK.
        let dicts = ["{GIF}", "{WebP}", "{PNG}"]
        func delay(_ i: Int) -> Double {
            guard let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [String: Any] else { return 0.1 }
            for name in dicts {
                if let d = props[name] as? [String: Any] {
                    let v = (d["UnclampedDelayTime"] as? Double) ?? (d["DelayTime"] as? Double) ?? 0
                    if v > 0 || d["DelayTime"] != nil || d["UnclampedDelayTime"] != nil {
                        return v < 0.02 ? 0.1 : v
                    }
                }
            }
            return 0.1
        }
        // Слишком длинные анимации прореживаем, чтобы не съесть память.
        let step = Int((Double(n) / 90).rounded(.up))
        var frames: [UIImage] = []
        var total = 0.0
        var i = 0
        while i < n {
            if let cg = CGImageSourceCreateThumbnailAtIndex(src, i, opts as CFDictionary) {
                frames.append(UIImage(cgImage: cg))
            }
            for j in i..<min(i + step, n) { total += delay(j) }
            i += step
        }
        if frames.isEmpty { return nil }
        if frames.count == 1 { return frames[0] }
        return UIImage.animatedImage(with: frames, duration: max(total, 0.4))
    }
}

struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFill
        v.clipsToBounds = true
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        v.image = image
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {
        if v.image !== image { v.image = image }
    }
}

/// Как RemoteImage, но GIF и другие анимации воспроизводятся.
struct AnimatedRemoteImage: View {
    let url: URL?
    var maxPixel: CGFloat = 400
    @State private var image: UIImage?

    var body: some View {
        Rectangle().fill(.quaternary)
            .overlay {
                if let image { AnimatedImageView(image: image).transition(.opacity) }
            }
            .clipped()
            .task(id: url) {
                guard let url else { return }
                if let c = AnimatedLoader.cached(url, maxPixel) { image = c; return }
                image = nil
                if let img = await AnimatedLoader.load(url, maxPixel: maxPixel, referer: LibSite.current.referer) {
                    withAnimation(.easeOut(duration: 0.25)) { image = img }
                }
            }
    }
}

struct RemoteImage: View {
    let url: URL?
    var maxPixel: CGFloat = 480
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Rectangle().fill(.quaternary)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().transition(.opacity).allowsHitTesting(false)
                } else if failed {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { failed = true; return }
        if url.isFileURL {
            // Скачанная обложка: читаем и уменьшаем в фоне, а не целиком на главном потоке.
            let key = ImageCache.key(url, maxPixel)
            if let cached = ImageCache.shared.object(forKey: key) { image = cached; return }
            let px = maxPixel
            let img = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let d = try? Data(contentsOf: url) else { return nil }
                return ImageLoader.downsample(d, maxPixel: px)
            }.value
            if let img { ImageCache.store(img, key); image = img } else { failed = true }
            return
        }
        let key = ImageCache.key(url, maxPixel)
        if let cached = ImageCache.shared.object(forKey: key) { image = cached; failed = false; return }
        image = nil
        failed = false
        if let img = await ImageLoader.shared.image(url, referer: LibSite.current.referer, maxPixel: maxPixel) {
            ImageCache.store(img, key)
            withAnimation(.easeOut(duration: 0.25)) { image = img }
        } else if !Task.isCancelled {
            failed = true
        }
    }
}

// MARK: - Favorites
@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore(key: "favorites.v1")
    static let novels = FavoritesStore(key: "favorites.novels.v1")
    static let manga = FavoritesStore(key: "favorites.manga.v1")
    static let hentai = FavoritesStore(key: "favorites.hentai.v1")
    static var current: FavoritesStore {
        let site = LibSite.current
        if site.isHentai { return hentai }
        return site.isManga ? manga : (site.isRanobe ? novels : shared)
    }
    @Published private(set) var items: [Anime] = []
    private let key: String

    init(key: String) {
        self.key = key
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
        Haptics.tap()
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

// MARK: - Списки избранного: статусы, сортировка, «Продолжить»
/// Свои названия для папок избранного («Читаю», «В планах»…): хранятся отдельно, уходят в бэкап.
enum FavNames {
    private static let key = "fav.names.v1"
    private static var cache: [String: String]?
    private static func all() -> [String: String] {
        if let c = cache { return c }
        var v: [String: String] = [:]
        if let d = UserDefaults.standard.string(forKey: key)?.data(using: .utf8),
           let dec = try? JSONDecoder().decode([String: String].self, from: d) { v = dec }
        cache = v
        return v
    }
    private static func k(_ st: ListStatus, _ book: Bool) -> String { st.rawValue + (book ? ".b" : ".a") }
    static func get(_ st: ListStatus, book: Bool) -> String? {
        let v = all()[k(st, book)]
        return (v?.isEmpty ?? true) ? nil : v
    }
    static func set(_ st: ListStatus, book: Bool, _ name: String?) {
        var v = all()
        let t = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if t.isEmpty { v.removeValue(forKey: k(st, book)) } else { v[k(st, book)] = String(t.prefix(24)) }
        cache = v
        if let d = try? JSONEncoder().encode(v), let str = String(data: d, encoding: .utf8) {
            UserDefaults.standard.set(str, forKey: key)
        }
    }
}

/// Главный цвет обложки: фон страницы и карточек слегка подкрашивается им.
enum CoverTint {
    @MainActor private static var cache: [String: Color] = [:]

    @MainActor
    static func color(_ url: URL?) async -> Color? {
        guard let url else { return nil }
        if let c = cache[url.absoluteString] { return c }
        guard let img = await ImageLoader.shared.image(url, referer: LibSite.current.referer, maxPixel: 40),
              let cg = img.cgImage else { return nil }
        let w = 8, h = 8
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for i in 0..<(w * h) {
            let rr = Double(px[i * 4]) / 255, gg = Double(px[i * 4 + 1]) / 255, bb = Double(px[i * 4 + 2]) / 255
            let mx = max(rr, gg, bb), mn = min(rr, gg, bb)
            let wgt = 0.15 + (mx - mn) * 2          // яркие, цветные пиксели весомее серых
            r += rr * wgt; g += gg * wgt; b += bb * wgt; n += wgt
        }
        guard n > 0 else { return nil }
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, al: CGFloat = 0
        UIColor(red: r / n, green: g / n, blue: b / n, alpha: 1).getHue(&hue, saturation: &sat, brightness: &bri, alpha: &al)
        let c = Color(hue: Double(hue), saturation: Double(min(1, max(sat, 0.4) * 1.15)), brightness: Double(min(0.85, max(bri, 0.55))))
        cache[url.absoluteString] = c
        return c
    }
}

struct CoverTintLayer: View {
    let url: URL?
    var strength: Double = 0.5
    var horizontal = false
    @State private var color: Color?

    var body: some View {
        LinearGradient(colors: [(color ?? .clear).opacity(strength), (color ?? .clear).opacity(0)],
                       startPoint: horizontal ? .leading : .top, endPoint: horizontal ? .trailing : .bottom)
            .opacity(color == nil ? 0 : 1)
            .animation(.easeOut(duration: 0.6), value: color != nil)
            .allowsHitTesting(false)
            .task(id: url) { color = await CoverTint.color(url) }
    }
}

enum ListStatus: String, CaseIterable, Codable {
    case active, planned, done, dropped

    func title(book: Bool) -> String {
        if let custom = FavNames.get(self, book: book) { return custom }
        return defaultTitle(book: book)
    }

    func defaultTitle(book: Bool) -> String {
        switch self {
        case .active: return book ? "Читаю" : "Смотрю"
        case .planned: return "В планах"
        case .done: return book ? "Прочитано" : "Просмотрено"
        case .dropped: return "Брошено"
        }
    }

    var icon: String {
        switch self {
        case .active: return "play.circle.fill"
        case .planned: return "clock.fill"
        case .done: return "checkmark.circle.fill"
        case .dropped: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .active: return .green
        case .planned: return .orange
        case .done: return .blue
        case .dropped: return .red
        }
    }
}

enum FavSort: String, CaseIterable {
    case added, updated, opened, title, rating

    var title: String {
        switch self {
        case .added: return "По добавлению"
        case .updated: return "По обновлению (новые серии и главы)"
        case .opened: return "Недавно открытые"
        case .title: return "По названию"
        case .rating: return "По рейтингу"
        }
    }
}

struct FavMeta: Codable {
    var status: String?
    var count: Int?
    var release: Date?
    var changed: Date?
    var checked: Date?
    var seen: Int?
}

enum FavUpdate {
    /// Достаёт из ответа сайта число серий/глав и дату последнего выхода (поля ищем по смыслу имени).
    static func parse(_ root: Any) -> (count: Int?, date: String?) {
        var count: Int?
        var date: String?
        func walk(_ v: Any, _ depth: Int) {
            guard depth < 3 else { return }
            if let o = v as? [String: Any] {
                for (k, x) in o {
                    let lk = k.lowercased()
                    if count == nil, ["episodes_count", "chapters_count", "items_count"].contains(lk), let n = J.int(x) {
                        count = n
                    }
                    if date == nil, lk.contains("last"), lk.contains("episode") || lk.contains("chapter"),
                       let str = x as? String, str.count >= 10, str.first?.isNumber == true {
                        date = str
                    }
                    if x is [String: Any] || x is [Any] { walk(x, depth + 1) }
                }
            } else if let arr = v as? [Any] {
                for x in arr.prefix(5) { walk(x, depth + 1) }
            }
        }
        walk(root, 0)
        return (count, date)
    }
}

private func makeLibFmt(_ pattern: String) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = pattern
    return f
}
private let libLongFmt = makeLibFmt("yyyy-MM-dd HH:mm:ss")
private let libShortFmt = makeLibFmt("yyyy-MM-dd")

func parseLibDate(_ s: String) -> Date? {
    let t = s.replacingOccurrences(of: "T", with: " ")
    let long = t.count >= 19
    let f = long ? libLongFmt : libShortFmt
    return f.date(from: String(t.prefix(long ? 19 : 10)))
}

@MainActor
final class FavMetaStore: ObservableObject {
    static let shared = FavMetaStore()
    @Published private(set) var items: [String: FavMeta] = [:]
    private let key = "favmeta.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let v = try? JSONDecoder().decode([String: FavMeta].self, from: d) { items = v }
    }

    static func key(_ a: Anime) -> String { "\(LibSite.current.key)-\(a.id)" }

    func status(_ a: Anime) -> ListStatus? {
        items[Self.key(a)]?.status.flatMap { ListStatus(rawValue: $0) }
    }

    func setStatus(_ a: Anime, _ s: ListStatus?) {
        var m = items[Self.key(a)] ?? FavMeta()
        m.status = s?.rawValue
        items[Self.key(a)] = m
        save()
    }

    func updateDate(_ a: Anime) -> Date? {
        guard let m = items[Self.key(a)] else { return nil }
        return m.release ?? m.changed
    }

    /// Сколько серий или глав вышло с тех пор, как ты в последний раз заглядывал в тайтл.
    func newCount(_ a: Anime) -> Int {
        guard let m = items[Self.key(a)], let c = m.count, let s = m.seen else { return 0 }
        return max(0, c - s)
    }

    func totalNew(_ list: [Anime]) -> Int { list.filter { newCount($0) > 0 }.count }

    func markSeen(_ a: Anime) {
        let k = Self.key(a)
        guard var m = items[k], let c = m.count, m.seen != c else { return }
        m.seen = c
        items[k] = m
        save()
    }

    func markAllSeen(_ list: [Anime]) {
        for a in list {
            let k = Self.key(a)
            if var m = items[k], let c = m.count { m.seen = c; items[k] = m }
        }
        UserDefaults.standard.set(Date(), forKey: "new.lastVisit")
        save()
    }

    func needsCheck(_ a: Anime) -> Bool {
        guard let c = items[Self.key(a)]?.checked else { return true }
        return Date().timeIntervalSince(c) > 1800
    }

    func apply(_ a: Anime, count: Int?, date: String?) {
        var m = items[Self.key(a)] ?? FavMeta()
        if m.seen == nil, let n = count { m.seen = m.count ?? n }
        if let old = m.count, let n = count, n > old { m.changed = Date() }
        if let n = count { m.count = n }
        if let d = date, let parsed = parseLibDate(d) { m.release = parsed }
        m.checked = Date()
        items[Self.key(a)] = m
        save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: key) }
    }
}

/// Плановая проверка обновлений избранного: при запуске и возвращении в приложение, не чаще раза в час.
@MainActor
enum FavUpdater {
    static func refresh(_ list: [Anime], force: Bool) async {
        let meta = FavMetaStore.shared
        let site = LibSite.current.key
        let todo = Array(list.prefix(80)).filter { force || meta.needsCheck($0) }
        var i = 0
        while i < todo.count {
            let chunk = Array(todo[i..<min(i + 4, todo.count)])
            await withTaskGroup(of: (Anime, Int?, String?).self) { group in
                for a in chunk {
                    group.addTask {
                        let r = await AnimelibAPI.shared.updateInfo(slug: a.slugUrl)
                        return (a, r.count, r.date)
                    }
                }
                for await (a, c, d) in group where LibSite.current.key == site { meta.apply(a, count: c, date: d) }
            }
            i += 4
        }
    }

    static func refreshIfDue() async {
        let last = UserDefaults.standard.object(forKey: "new.lastRun") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 3600 else { return }
        UserDefaults.standard.set(Date(), forKey: "new.lastRun")
        await refresh(FavoritesStore.current.items, force: false)
    }
}

struct NewInFavoritesView: View {
    @ObservedObject private var favorites: FavoritesStore = FavoritesStore.current
    @ObservedObject private var meta = FavMetaStore.shared
    @State private var refreshing = false
    private let unit = LibSite.current.isBook ? "гл." : "сер."

    private var fresh: [Anime] {
        favorites.items.filter { meta.newCount($0) > 0 }
            .sorted { (meta.updateDate($0) ?? .distantPast) > (meta.updateDate($1) ?? .distantPast) }
    }

    private var recent: [Anime] {
        favorites.items.filter { a in
            meta.newCount(a) == 0 && (meta.updateDate(a).map { Date().timeIntervalSince($0) < 14 * 86400 } ?? false)
        }
        .sorted { (meta.updateDate($0) ?? .distantPast) > (meta.updateDate($1) ?? .distantPast) }
    }

    private func row(_ a: Anime) -> some View {
        let n = meta.newCount(a)
        return TitleLink(anime: a) {
            HStack(spacing: 12) {
                RemoteImage(url: a.imageURL, maxPixel: 200)
                    .frame(width: 56, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    Text(a.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        if n > 0 {
                            Text("+\(n) \(unit)")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Theme.accent, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        if let d = meta.updateDate(a) {
                            Text(ChapterAge.ago(d)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.chip))
        }
        .buttonStyle(.pressable)
        .simultaneousGesture(TapGesture().onEnded { meta.markSeen(a) })
    }

    private func header(_ t: String) -> some View {
        Text(t.uppercased())
            .font(.caption.weight(.bold)).tracking(1.1)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                let f = fresh
                HStack(spacing: 12) {
                    Image(systemName: f.isEmpty ? "checkmark.seal.fill" : "bell.badge.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.isEmpty ? "Всё прочитано" : "Новое в \(f.count) тайтлах").font(.headline)
                        if let d = UserDefaults.standard.object(forKey: "new.lastVisit") as? Date {
                            Text("Отмечено: " + ChapterAge.ago(d)).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(refreshing ? "Проверяю…" : "Избранное проверяется само").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(14)
                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 20))

                if !f.isEmpty {
                    Button {
                        Haptics.success()
                        withAnimation { meta.markAllSeen(favorites.items) }
                    } label: {
                        Label("Отметить всё просмотренным", systemImage: "checkmark.circle")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.chip, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    header("Новое")
                    ForEach(f) { row($0) }
                }
                let r = recent
                if !r.isEmpty {
                    header("Недавно обновлялись")
                    ForEach(r) { row($0) }
                }
                if f.isEmpty && r.isEmpty {
                    Text("Пока ничего нового. Потяни вниз, чтобы проверить сейчас.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding(.top, 30)
                }
            }
            .padding(14)
        }
        .background(AppBackground())
        .navigationTitle("Новое")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            refreshing = true
            await FavUpdater.refresh(favorites.items, force: true)
            refreshing = false
        }
        .task {
            refreshing = true
            await FavUpdater.refresh(favorites.items, force: false)
            refreshing = false
        }
    }
}

struct FavCard: View {
    let anime: Anime
    let status: ListStatus?
    let book: Bool
    var newCount: Int = 0
    let onStatus: (ListStatus?) -> Void
    let onContinue: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            TitleLink(anime: anime) { AnimeCard(anime: anime) }
                .buttonStyle(.pressable)
            GeometryReader { geo in
                ZStack {
                    Menu {
                        ForEach(ListStatus.allCases, id: \.self) { st in
                            Button { onStatus(st) } label: { Label(st.title(book: book), systemImage: st.icon) }
                        }
                        if status != nil {
                            Button(role: .destructive) { onStatus(nil) } label: {
                                Label("Без статуса", systemImage: "tag.slash")
                            }
                        }
                    } label: {
                        Image(systemName: status?.icon ?? "tag")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(status?.color ?? Color.white)
                            .frame(width: 28, height: 28)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .position(x: 22, y: 22)

                    Button(action: onContinue) {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Theme.accent, in: Circle())
                            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                    .position(x: geo.size.width - 22, y: geo.size.width * 1.5 - 22)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if newCount > 0 {
                Text("+\(newCount)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.accent, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .padding(7)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct FavoritesView: View {
    @ObservedObject private var favorites: FavoritesStore = FavoritesStore.current
    @ObservedObject private var meta = FavMetaStore.shared
    @ObservedObject private var history: HistoryStore = HistoryStore.current
    @AppStorage("fav.sort") private var sortRaw = FavSort.added.rawValue
    @State private var filter: ListStatus?
    @State private var continueAnime: Anime?
    @State private var pushContinue = false
    @State private var refreshing = false
    @State private var showNew = false
    @State private var renaming: ListStatus?
    @State private var renameText = ""
    @State private var namesTick = 0
    private let book = LibSite.current.isBook
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    private var sort: FavSort { FavSort(rawValue: sortRaw) ?? .added }

    private func opened(_ a: Anime) -> Date {
        history.items.first(where: { $0.anime.id == a.id })?.updated ?? Date.distantPast
    }

    private var visible: [Anime] {
        var list = favorites.items
        if let f = filter { list = list.filter { meta.status($0) == f } }
        switch sort {
        case .added:
            break
        case .updated:
            list.sort { (meta.updateDate($0) ?? Date.distantPast) > (meta.updateDate($1) ?? Date.distantPast) }
        case .opened:
            list.sort { opened($0) > opened($1) }
        case .title:
            list.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .rating:
            list.sort { (Double($0.rateAvg ?? "") ?? 0) > (Double($1.rateAvg ?? "") ?? 0) }
        }
        return list
    }

    private func chip(_ title: String, _ count: Int, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("\(title) \(count)")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(on ? Theme.accent : Color.clear, in: Capsule())
                .background { if !on { Capsule().fill(.ultraThinMaterial) } }
                .foregroundStyle(on ? Color.white : Color.primary)
        }
        .buttonStyle(.pressable)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Все", favorites.items.count, filter == nil) { filter = nil }
                ForEach(ListStatus.allCases, id: \.self) { st in
                    chip(st.title(book: book), favorites.items.filter { meta.status($0) == st }.count, filter == st) {
                        filter = st
                    }
                    .contextMenu {
                        Button {
                            renameText = st.title(book: book)
                            renaming = st
                        } label: { Label("Переименовать", systemImage: "pencil") }
                        if FavNames.get(st, book: book) != nil {
                            Button {
                                FavNames.set(st, book: book, nil)
                                namesTick += 1
                            } label: { Label("Вернуть название", systemImage: "arrow.uturn.backward") }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func refresh(force: Bool) async {
        refreshing = true
        await FavUpdater.refresh(favorites.items, force: force)
        refreshing = false
    }

    @ViewBuilder
    private var continueDestination: some View {
        if let a = continueAnime {
            if book {
                NovelDetailView(novel: Novel(a), autoContinue: true)
            } else {
                DetailView(anime: a, autoContinue: true)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if !favorites.items.isEmpty { chips }
                    if sort == .updated, !favorites.items.isEmpty,
                       favorites.items.allSatisfy({ meta.updateDate($0) == nil }) {
                        Text(refreshing ? "Проверяю обновления…"
                             : "Сайт не сообщил даты выхода: порядок по обновлению появится, когда приложение заметит новые серии или главы.")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                    }
                    if favorites.items.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "heart.slash").font(.largeTitle).foregroundStyle(.secondary)
                            Text("Пока пусто.\nОткройте тайтл и нажмите сердечко.")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 100)
                    } else if visible.isEmpty {
                        Text("В этом списке пока пусто.\nНажми значок ярлыка на обложке, чтобы задать статус.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 60)
                    }
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(visible) { anime in
                            FavCard(anime: anime, status: meta.status(anime), book: book, newCount: meta.newCount(anime),
                                    onStatus: { st in
                                        meta.setStatus(anime, st)
                                        Haptics.select()
                                    },
                                    onContinue: {
                                        Haptics.tap()
                                        continueAnime = anime
                                        pushContinue = true
                                    })
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
            .refreshable { await refresh(force: true) }
            .task { await refresh(force: false) }
            .background(AppBackground())
            .alert("Название папки", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Название", text: $renameText)
                Button("Сохранить") {
                    if let st = renaming { FavNames.set(st, book: book, renameText); namesTick += 1 }
                    renaming = nil
                }
                Button("Отмена", role: .cancel) { renaming = nil }
            } message: {
                Text("Папка «\(renaming?.defaultTitle(book: book) ?? "")» будет называться так. Фильтр и статус не изменятся.")
            }
            .id(namesTick)
            .navigationTitle("Избранное")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showNew = true } label: {
                        Image(systemName: meta.totalNew(favorites.items) > 0 ? "bell.badge.fill" : "bell")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Сортировка", selection: $sortRaw) {
                            ForEach(FavSort.allCases, id: \.rawValue) { o in
                                Text(o.title).tag(o.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
            .navigationDestination(for: Anime.self) { DetailView(anime: $0) }
            .navigationDestination(for: Novel.self) { NovelDetailView(novel: $0) }
            .navigationDestination(isPresented: $pushContinue) { continueDestination }
            .navigationDestination(isPresented: $showNew) { NewInFavoritesView() }
        }
    }
}

// MARK: - Резервная копия (прогресс, избранное, история, настройки)
enum BackupManager {
    private static let prefixes = ["favorites", "history", "progress", "read", "search.", "set.",
                                   "accent.", "reader.", "manga.", "novel.", "off.",
                                   "activity", "bookmarks", "highlights", "favmeta", "fav.", "friends"]

    private static func allowed(_ key: String) -> Bool {
        if key.hasPrefix("friends.cache") { return false }   // кэш, подтянется заново
        return prefixes.contains { key.hasPrefix($0) }
    }

    static var autoURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Yume-backup.plist")
    }

    static func snapshot() -> [String: Any] {
        let all = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        return all.filter { allowed($0.key) }
    }

    static func data(date: Date = Date()) -> Data? {
        let root: [String: Any] = ["app": "Yume", "version": 1, "date": date, "defaults": snapshot()]
        return try? PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    // Копия живёт только в папке приложения (Файлы → На iPhone → Yume).
    private static let mineKey = "backup.mine"   // дата последней копии, записанной самим приложением
    /// После восстановления в работающем приложении копии не пишутся, чтобы старые данные в памяти не затёрли файл.
    private static var frozen = false

    private static func fileDate(_ d: Data) -> Date? {
        guard let root = (try? PropertyListSerialization.propertyList(from: d, format: nil)) as? [String: Any],
              (root["app"] as? String) == "Yume" else { return nil }
        return root["date"] as? Date
    }

    /// Дата копии в папке приложения, если её положил пользователь (а не записало само приложение).
    static func externalCopyDate() -> Date? {
        guard let d = try? Data(contentsOf: autoURL), !d.isEmpty, let fd = fileDate(d) else { return nil }
        if let m = UserDefaults.standard.object(forKey: mineKey) as? Date, abs(m.timeIntervalSince(fd)) < 1.5 { return nil }
        return fd
    }

    /// «Не нужно»: считаем лежащую копию своей, дальше она будет обычно обновляться.
    static func acceptExternal() {
        if let d = try? Data(contentsOf: autoURL), let fd = fileDate(d) {
            UserDefaults.standard.set(fd, forKey: mineKey)
        }
    }

    /// Вызывается до создания хранилищ: тихо подхватывает копию, которую положили в папку приложения.
    @discardableResult
    static func restoreOnLaunch() -> Bool {
        UserDefaults.standard.removeObject(forKey: "backup.folder.bookmark")
        guard externalCopyDate() != nil, let d = try? Data(contentsOf: autoURL), restore(d) != nil else { return false }
        acceptExternal()
        frozen = false
        return true
    }

    /// Пишет копию в папку приложения. Если там лежит чужая (новая) копия, не затирает её.
    @discardableResult
    static func writeAuto() -> URL? {
        if frozen || externalCopyDate() != nil { return nil }
        let stamp = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        guard let d = data(date: stamp) else { return nil }
        do {
            try d.write(to: autoURL, options: .atomic)
            UserDefaults.standard.set(stamp, forKey: mineKey)
            return autoURL
        } catch {
            return nil
        }
    }

    /// Файл для кнопки «Отправить»: свежая копия или та, что уже лежит.
    static func shareURL() -> URL? {
        if let u = writeAuto() { return u }
        return FileManager.default.fileExists(atPath: autoURL.path) ? autoURL : nil
    }

    static var lastAuto: Date? {
        (try? FileManager.default.attributesOfItem(atPath: autoURL.path))?[.modificationDate] as? Date
    }

    /// Читает копию из папки приложения.
    static func readAppFolderCopy() -> (Data?, String) {
        guard FileManager.default.fileExists(atPath: autoURL.path) else {
            return (nil, "в папке приложения нет файла Yume-backup.plist")
        }
        guard let d = try? Data(contentsOf: autoURL), !d.isEmpty else { return (nil, "файл пустой или не читается") }
        return (d, "")
    }

    /// Возвращает число восстановленных записей.
    static func restore(_ data: Data) -> Int? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              (root["app"] as? String) == "Yume",
              let defs = root["defaults"] as? [String: Any] else { return nil }
        var n = 0
        for (k, v) in defs where allowed(k) {
            UserDefaults.standard.set(v, forKey: k)
            n += 1
        }
        UserDefaults.standard.synchronize()
        frozen = true
        return n
    }

    /// Что лежит в копии: для сообщения после восстановления.
    static func summary(_ data: Data) -> String {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let defs = root["defaults"] as? [String: Any] else { return "" }
        func count(_ keys: [String]) -> Int {
            keys.reduce(0) { sum, k in
                guard let d = defs[k] as? Data, let a = (try? JSONSerialization.jsonObject(with: d)) as? [Any] else { return sum }
                return sum + a.count
            }
        }
        let fav = count(["favorites.v1", "favorites.novels.v1", "favorites.manga.v1", "favorites.hentai.v1"])
        let hist = count(["history.v1", "history.novels.v1", "history.manga.v1", "history.hentai.v1"])
        var s = "В копии: избранное \(fav), история \(hist)"
        if let d = root["date"] as? Date { s += ", сохранена \(d.formatted(date: .abbreviated, time: .shortened))" }
        return s + "."
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.propertyList] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}

// MARK: - Журнал запросов сайта (чтобы найти, как сайт хранит прогресс)
@MainActor
final class SiteLog: ObservableObject {
    @Published var lines: [String] = []

    func add(_ s: String) {
        if lines.count > 400 { lines.removeFirst(100) }
        lines.append(s)
    }
}

struct SiteWebView: UIViewRepresentable {
    let url: URL
    let log: SiteLog

    static let script = """
    (function(){
      if (window.__heheLog) return; window.__heheLog = true;
      function want(m, u){
        if (m !== 'GET') return true;
        return /cdnlibs\\.org|\\/api\\//i.test(String(u));
      }
      function send(m, u, b, s){
        try {
          window.webkit.messageHandlers.hlog.postMessage(JSON.stringify({
            m: m, u: String(u), b: b ? String(b).slice(0, 400) : '', s: s || 0
          }));
        } catch (e) {}
      }
      var of = window.fetch;
      if (of) window.fetch = function(a, o){
        var u = typeof a === 'string' ? a : (a && a.url);
        var m = ((o && o.method) || (a && a.method) || 'GET').toUpperCase();
        var b = o && o.body;
        var p = of.apply(this, arguments);
        p.then(function(r){ if (want(m, u)) send(m, u, b, r.status); }).catch(function(){});
        return p;
      };
      var oo = XMLHttpRequest.prototype.open, os = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(m, u){ this.__m = String(m).toUpperCase(); this.__u = u; return oo.apply(this, arguments); };
      XMLHttpRequest.prototype.send = function(b){
        var x = this;
        this.addEventListener('loadend', function(){ if (want(x.__m, x.__u)) send(x.__m, x.__u, b, x.status); });
        return os.apply(this, arguments);
      };
    })();
    """

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let log: SiteLog
        init(_ l: SiteLog) { log = l }
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            guard let t = m.body as? String,
                  let d = t.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
            let line = "\(o["m"] as? String ?? "?") \(o["u"] as? String ?? "") [\(o["s"] as? Int ?? 0)]"
                + ((o["b"] as? String).flatMap { $0.isEmpty ? nil : "\n    тело: " + $0 } ?? "")
            Task { @MainActor in self.log.add(line) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(log) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.userContentController.add(context.coordinator, name: "hlog")
        cfg.userContentController.addUserScript(
            WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.customUserAgent = Kodik.ua
        v.load(URLRequest(url: url))
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {}

    static func dismantleUIView(_ v: WKWebView, coordinator: Coordinator) {
        v.configuration.userContentController.removeScriptMessageHandler(forName: "hlog")
    }
}

struct SiteLogView: View {
    var path: String = ""
    @StateObject private var log = SiteLog()
    @State private var showLog = false

    private var start: URL {
        let base: String
        switch LibSite.current.key {
        case "ranobe": base = "https://ranobelib.me/ru/"
        case "manga": base = "https://mangalib.me/ru/"
        case "hentai": base = "https://kz.hentailib.me/ru/"
        default: base = "https://animelib.org/ru/"
        }
        return URL(string: base + path) ?? URL(string: base)!
    }

    var body: some View {
        VStack(spacing: 0) {
            SiteWebView(url: start, log: log)
            Button { showLog = true } label: {
                Label("Журнал запросов: \(log.lines.count)", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .padding(12)
            }
        }
        .navigationTitle("Сайт")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLog) {
            NavigationStack {
                ScrollView {
                    Text(log.lines.isEmpty ? "Пока пусто. Открой на сайте главу или серию, отметь прочитанное и вернись сюда." : log.lines.joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .navigationTitle("Журнал")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { showLog = false } }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack {
                            Button("Очистить") { log.lines = [] }
                            Button("Копировать") { UIPasteboard.general.string = log.lines.joined(separator: "\n") }
                        }
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @AppStorage("accent.hex") private var accentHex = Theme.defaultAccentHex
    @AppStorage("set.autoNative") private var autoNative = true
    @AppStorage("set.resume") private var resume = true
    @AppStorage("set.autoNext") private var autoNext = true
    @AppStorage("set.kodikDirect") private var kodikDirect = false
    @AppStorage("set.theme") private var appTheme = "system"
    @AppStorage("set.platform") private var platform = "anime"
    @AppStorage("set.haptics") private var haptics = true
    @AppStorage("set.keepAwake") private var keepAwake = true
    @AppStorage("manga.mode.default") private var mangaMode = "auto"
    @AppStorage("manga.tapzones") private var tapZones = true
    @AppStorage("manga.anim") private var mangaAnim = "slide"
    @AppStorage("manga.autobg") private var mangaAutoBG = false
    @AppStorage("novel.mode") private var novelMode = "pages"
    @AppStorage("novel.anim") private var novelAnim = "book"
    @AppStorage("off.wifi") private var offWifi = false
    @AppStorage("off.prefetch") private var offPrefetch = false
    @AppStorage("off.limitGB") private var offLimit = 0
    @AppStorage("off.overflow") private var offOverflow = "refuse"
    @ObservedObject private var offline = OfflineStore.current
    @State private var confirmOffline = false
    @ObservedObject private var auth = AuthStore.shared
    @State private var custom: Color = Theme.accent
    @State private var info: String?
    @State private var shareItem: ShareItem?
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var restored = false
    @State private var showRestartAlert = false
    @State private var showFolderImporter = false
    @State private var backupInfo = ""
    @State private var confirmSignOut = false
    @AppStorage("backup.sent") private var backupSent: Double = 0

    private func finishRestore(_ d: Data?, _ reason: String) {
        guard let d else {
            backupInfo = "Файл не прочитался: \(reason)."
            return
        }
        let sum = BackupManager.summary(d)
        if let n = BackupManager.restore(d) {
            backupInfo = "Восстановлено записей: \(n). \(sum)"
            restored = true
            showRestartAlert = true
            Haptics.success()
        } else {
            backupInfo = "Это не файл копии Yume (или он повреждён)."
        }
    }

    private let presets: [(String, String)] = [
        ("Фиолетовый", "A87AFF"), ("Розовый", "FF6FA8"), ("Синий", "4F9DFF"),
        ("Бирюзовый", "2EC4B6"), ("Зелёный", "5BD16A"), ("Оранжевый", "FF9F43"), ("Красный", "FF5A5F")
    ]
    private let platforms: [(String, String, String, Bool)] = [
        ("anime", "Аниме", "AnimeLib", true),
        ("ranobe", "Ранобэ", "RanobeLib", true),
        ("manga", "Манга", "MangaLib", true),
        ("hentai", "Hentai", "HentaiLib", true)
    ]

    private func platformIcon(_ id: String) -> String {
        switch id {
        case "ranobe": return "text.book.closed.fill"
        case "manga": return "books.vertical.fill"
        case "hentai": return "flame.fill"
        default: return "play.rectangle.fill"
        }
    }

    private var platformHint: String {
        switch platform {
        case "ranobe": return "Ранобэ: читалка с темами и шрифтами, скачивание глав для чтения без сети."
        case "manga": return "Манга: страницы или лента, комментарии к главам, прогресс чтения."
        case "hentai": return "HentaiLib (18+): та же читалка, что у манги; избранное и история отдельные."
        default: return "Аниме: плеер с озвучкой и субтитрами, комментарии к сериям, автопереход."
        }
    }

    private func choosePlatform(_ id: String) {
        guard platform != id else { return }
        Haptics.bump()
        let name = platforms.first { $0.0 == id }?.1 ?? ""
        AppRouter.shared.toast = "Платформа: \(name)"
        withAnimation(.easeInOut(duration: 0.3)) { platform = id }
    }

    private func card<Content: View>(_ title: String, icon: String = "gearshape.fill", tint: Color = Theme.accent,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func groupTitle(_ t: String) -> some View {
        Text(t.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.leading, 6)
    }

    private var heroSubtitle: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let pl = platforms.first { $0.0 == platform }?.2 ?? "AnimeLib"
        return "Версия \(v) · \(pl)"
    }

    private var hero: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(auth.user?.username ?? "Yume").font(.title3.weight(.bold)).lineLimit(1)
                    Text(heroSubtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                heroStat("heart.fill", "\(FavoritesStore.current.items.count)", "избранное")
                heroStat("arrow.down.circle.fill", "\(offline.allEntries.count)", "скачано")
                heroStat("internaldrive.fill", offline.totalBytes == 0 ? "0 МБ" : fmtBytes(offline.totalBytes), "занято")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 0.5))
    }

    private func heroStat(_ icon: String, _ value: String, _ title: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: ряды в стиле «Настроек» iOS

    private func iconBadge(_ name: String) -> some View {
        let palette: [Color] = [Color(hex: "0A84FF"), Color(hex: "30D158"), Color(hex: "FF9F0A"), Color(hex: "BF5AF2"),
                                Color(hex: "FF375F"), Color(hex: "64D2FF"), Color(hex: "5E5CE6"), Color(hex: "8E8E93")]
        let h = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(palette[h % palette.count].gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var rowDivider: some View { Divider().padding(.leading, 44) }

    private func listCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 0.5))
    }

    private func section<C: View>(_ title: String, footer: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase).padding(.horizontal, 18)
            listCard { content() }
            if let footer {
                Text(footer).font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toggleRow(_ icon: String, _ title: String, _ on: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            iconBadge(icon)
            Toggle(title, isOn: on).tint(Theme.accent)
        }
        .font(.body)
        .padding(.vertical, 9)
    }

    private func actionRow(_ icon: String, _ title: String, tint: Color = .primary, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 12) {
                iconBadge(icon)
                Text(title).font(.body).foregroundStyle(tint)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    private func linkRow<D: View>(_ icon: String, _ title: String, value: String? = nil,
                                  @ViewBuilder _ dest: @escaping () -> D) -> some View {
        NavigationLink {
            dest()
        } label: {
            HStack(spacing: 12) {
                iconBadge(icon)
                Text(title).font(.body).foregroundStyle(.primary)
                Spacer(minLength: 8)
                if let value { Text(value).font(.subheadline).foregroundStyle(.secondary) }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    private func textRow(_ t: String) -> some View {
        Text(t).font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
    }

    private func segRow(_ title: String, _ sel: Binding<String>, _ options: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Picker(title, selection: sel) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 12)
    }

    // MARK: внешний вид

    private func themePreview(_ id: String) -> some View {
        let darkBG = Color(white: 0.11), lightBG = Color(white: 0.96)
        func screen(_ bg: Color, _ fg: Color) -> some View {
            ZStack(alignment: .topLeading) {
                bg
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(fg.opacity(0.5)).frame(width: 22, height: 4)
                    RoundedRectangle(cornerRadius: 3).fill(fg.opacity(0.18)).frame(height: 10)
                    RoundedRectangle(cornerRadius: 3).fill(fg.opacity(0.18)).frame(height: 10)
                }
                .padding(7)
            }
        }
        return ZStack {
            if id == "dark" { screen(darkBG, .white) }
            else if id == "light" { screen(lightBG, .black) }
            else { HStack(spacing: 0) { screen(lightBG, .black); screen(darkBG, .white) } }
        }
        .frame(height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.18), lineWidth: 0.5))
    }

    private var platformSwitch: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(platforms, id: \.0) { pl in
                    let on = platform == pl.0
                    Button { choosePlatform(pl.0) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: platformIcon(pl.0)).font(.system(size: 19, weight: .semibold))
                            Text(pl.1).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background {
                            if on { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.accent) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 0.5))
            Text(platformHint)
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
        }
    }

    private var appearanceBlock: some View {
        section("Внешний вид") {
            HStack(spacing: 10) {
                ForEach([("system", "Системная"), ("dark", "Тёмная"), ("light", "Светлая")], id: \.0) { t in
                    let on = appTheme == t.0
                    Button { Haptics.select(); appTheme = t.0 } label: {
                        VStack(spacing: 8) {
                            themePreview(t.0)
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Theme.accent, lineWidth: on ? 2.5 : 0))
                            Text(t.1).font(.footnote.weight(on ? .semibold : .regular))
                                .foregroundStyle(on ? Theme.accent : Color.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 14)
            rowDivider
            HStack(spacing: 0) {
                ForEach(presets, id: \.1) { p in
                    let on = accentHex.uppercased() == p.1
                    Circle()
                        .fill(Color(hex: p.1))
                        .frame(width: 30, height: 30)
                        .overlay { if on { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white) } }
                        .padding(3)
                        .overlay(Circle().stroke(Color(hex: p.1), lineWidth: on ? 2 : 0))
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { Haptics.select(); accentHex = p.1 }
                }
                ColorPicker("Свой цвет", selection: $custom, supportsOpacity: false)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .onChange(of: custom) { c in accentHex = c.hexString }
            }
            .padding(.vertical, 14)
        }
    }

    // MARK: чтение и просмотр

    private var feelBlock: some View {
        section("Ощущения") {
            toggleRow("hand.tap.fill", "Вибрация при нажатиях", $haptics)
                .onChange(of: haptics) { on in if on { Haptics.bump() } }
            rowDivider
            toggleRow("sun.max.fill", "Не гасить экран при чтении", $keepAwake)
        }
    }

    private var ranobeBlock: some View {
        section("Чтение ранобэ",
                footer: "В режиме «Страницы» глава режется на страницы по размеру экрана. Размер шрифта и тему можно менять в самой читалке.") {
            segRow("Режим", $novelMode, [("pages", "Страницы"), ("scroll", "Прокрутка")])
            rowDivider
            segRow("Листание", $novelAnim, [("slide", "Сдвиг"), ("fade", "Плавно"), ("book", "Как в книге")])
        }
    }

    private var mangaBlock: some View {
        section("Чтение манги", footer: "Для каждого тайтла режим можно поменять прямо в читалке, он запомнится.") {
            segRow("Режим по умолчанию", $mangaMode, [("auto", "Авто"), ("pages", "Страницы"), ("scroll", "Лента")])
            rowDivider
            segRow("Листание", $mangaAnim, [("slide", "Сдвиг"), ("fade", "Плавно"), ("book", "Как в книге")])
            rowDivider
            toggleRow("hand.point.up.left.fill", "Листать тапом по краям экрана", $tapZones)
            rowDivider
            toggleRow("rectangle.inset.filled", "Фон под страницу (белый или чёрный по краям)", $mangaAutoBG)
        }
    }

    private var playbackBlock: some View {
        section("Воспроизведение",
                footer: "Kodik открывается в веб-плеере: выбери качество и нажми «на весь экран», тогда включится родной плеер iOS. Если выключить первый пункт, весь экран останется внутри веб-плеера.") {
            toggleRow("play.rectangle.fill", "Весь экран в родном плеере iOS", $autoNative)
            rowDivider
            toggleRow("bolt.fill", "Kodik: сразу родной плеер, без веб-плеера", $kodikDirect)
            rowDivider
            toggleRow("gobackward", "Продолжать с места остановки", $resume)
            rowDivider
            toggleRow("forward.end.fill", "Следующая серия сама после конца", $autoNext)
        }
    }

    // MARK: данные

    private var downloadsBlock: some View {
        section("Загрузки · ранобэ и манга") {
            if platform != "anime" {
                linkRow("arrow.down.circle.fill", "Скачанное",
                        value: "\(offline.allEntries.count) · \(fmtBytes(offline.totalBytes))") { OfflineLibraryView() }
            } else {
                textRow("Скачанные главы доступны на платформах «Ранобэ» и «Манга».")
            }
            rowDivider
            HStack(spacing: 12) {
                iconBadge("externaldrive.fill")
                Picker("Лимит места", selection: $offLimit) {
                    Text("Без лимита").tag(0)
                    ForEach([1, 2, 3, 5, 10, 20, 50], id: \.self) { Text("\($0) ГБ").tag($0) }
                }
            }
            .padding(.vertical, 6)
            if offLimit > 0 {
                rowDivider
                segRow("При превышении", $offOverflow, [("refuse", "Отказаться"), ("purge", "Удалять прочитанное")])
                textRow("Занято: \(fmtBytes(OfflineStore.usedBytes)) из \(offLimit) ГБ (ранобэ и манга вместе). «Отказаться»: загрузка останавливается на лимите. «Удалять прочитанное»: сначала стираются самые давние прочитанные главы.")
            }
            rowDivider
            toggleRow("wifi", "Скачивать только по Wi‑Fi", $offWifi)
            rowDivider
            toggleRow("arrow.down.to.line", "Докачивать 3 следующие главы при чтении", $offPrefetch)
            if offline.totalBytes > 0 {
                rowDivider
                actionRow("trash.fill", "Удалить все загрузки", tint: .red) { confirmOffline = true }
            }
        }
        .confirmationDialog("Удалить все скачанные главы?", isPresented: $confirmOffline, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { offline.removeAll() }
        }
    }

    private var dataBlock: some View {
        section("Данные", footer: info) {
            actionRow("photo.stack.fill", "Очистить кэш обложек") {
                ImageCache.shared.removeAllObjects(); Task { await ImageLoader.shared.clearDisk() }; info = "Кэш обложек очищен"
            }
            rowDivider
            actionRow("clock.arrow.circlepath", "Сбросить историю просмотра") {
                ProgressStore.shared.clear(); HistoryStore.shared.clear()
                HistoryStore.novels.clear(); HistoryStore.manga.clear(); HistoryStore.hentai.clear(); ReadStore.shared.clear(); ReadPosStore.shared.clear()
                info = "История просмотра и чтения сброшена"
            }
            rowDivider
            actionRow("heart.slash.fill", "Очистить избранное", tint: .red) {
                FavoritesStore.shared.clear(); FavoritesStore.novels.clear(); FavoritesStore.manga.clear(); FavoritesStore.hentai.clear(); info = "Избранное очищено"
            }
        }
    }

    private var statsBlock: some View {
        section("Статистика", footer: "Сколько просмотрено и прочитано, серия дней подряд.") {
            linkRow("chart.bar.xaxis", "Моя активность") { StatsView() }
        }
    }

    private var hasDataToLose: Bool {
        !(FavoritesStore.shared.items.isEmpty && FavoritesStore.novels.items.isEmpty
          && FavoritesStore.manga.items.isEmpty && FavoritesStore.hentai.items.isEmpty
          && HistoryStore.shared.items.isEmpty && HistoryStore.novels.items.isEmpty
          && HistoryStore.manga.items.isEmpty && HistoryStore.hentai.items.isEmpty)
    }

    @ViewBuilder
    private var backupWarning: some View {
        let days = backupSent == 0 ? nil : Int((Date().timeIntervalSince1970 - backupSent) / 86400)
        if hasDataToLose, days == nil || days! >= 7 {
            Button {
                if let u = BackupManager.shareURL() { backupSent = Date().timeIntervalSince1970; shareItem = ShareItem(url: u) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.icloud.fill").font(.title3).foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(days == nil ? "Копия ещё не отправлялась" : "Копия не отправлялась \(days!) дн.")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text("Отправь файл в Telegram или Файлы: при переустановке данные не пропадут.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "square.and.arrow.up").foregroundStyle(Theme.accent)
                }
                .padding(14)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.orange.opacity(0.35), lineWidth: 0.5))
            }
            .buttonStyle(.pressable)
        }
    }

    private var backupBlock: some View {
        section("Резервная копия") {
            textRow("Прогресс просмотра и чтения, избранное, история и настройки. Файл Yume-backup.plist сам создаётся и обновляется в папке приложения при каждом сворачивании.")
            rowDivider
            HStack(spacing: 12) {
                iconBadge("folder.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Файлы → На iPhone → Yume").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                    if let d = BackupManager.lastAuto {
                        Text("Обновлено: \(d.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            rowDivider
            textRow("Перед удалением приложения скопируй этот файл. После новой установки положи его в ту же папку и заново открой Yume: всё подхватится само.")
            rowDivider
            actionRow("arrow.down.doc.fill", "Загрузить из файла в папке приложения") {
                let r = BackupManager.readAppFolderCopy()
                BackupManager.acceptExternal()
                finishRestore(r.0, r.1)
            }
            rowDivider
            actionRow("square.and.arrow.up.fill", "Отправить копию (Telegram, Файлы…)") {
                if let u = BackupManager.shareURL() { backupSent = Date().timeIntervalSince1970; shareItem = ShareItem(url: u) }
                else { backupInfo = "Не удалось подготовить файл." }
            }
            if restored {
                rowDivider
                actionRow("power", "Закрыть приложение, чтобы применить") { exit(0) }
            }
            if !backupInfo.isEmpty {
                rowDivider
                textRow(backupInfo)
            }
        }
        .sheet(item: $shareItem) { item in ShareSheet(url: item.url) }
    }

    private var miscBlock: some View {
        section("Прочее") {
            linkRow("waveform.path.ecg", "Журнал запросов сайта") { SiteLogView() }
            rowDivider
            textRow("Открывает сайт внутри приложения и записывает, какие запросы он отправляет, когда ты отмечаешь серию или главу. Нужен, чтобы настроить синхронизацию с сайтом.")
            rowDivider
            if let u = auth.user {
                actionRow("rectangle.portrait.and.arrow.right", "Выйти из аккаунта · \(u.username)", tint: .red) {
                    confirmSignOut = true
                }
            } else {
                HStack(spacing: 12) {
                    iconBadge("person.crop.circle.fill")
                    Text("Вход выполняется во вкладке «Профиль».").font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            }
            rowDivider
            HStack(spacing: 12) {
                iconBadge("info.circle.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Yume · версия 1.0")
                    Text("Данные: animelib.org. Приложение неофициальное.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    backupWarning
                    hero
                    platformSwitch
                    appearanceBlock
                    feelBlock
                    if platform == "ranobe" { ranobeBlock }
                    if platform == "manga" || platform == "hentai" { mangaBlock }
                    playbackBlock
                    downloadsBlock
                    dataBlock
                    statsBlock
                    backupBlock
                    miscBlock
                }
                .padding(14)
                .padding(.bottom, 90)
            }
            .background(AppBackground())
            .navigationTitle("Настройки")
            .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { auth.signOut() }
                Button("Отмена", role: .cancel) {}
            }
            .alert("Данные восстановлены", isPresented: $showRestartAlert) {
                Button("Закрыть приложение") { UserDefaults.standard.synchronize(); exit(0) }
            } message: {
                Text("Чтобы всё подхватилось, приложение закроется. Открой Yume снова.")
            }
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Навигация между вкладками
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var tab = 0
    @Published var pendingQuery: String?
    @Published var pendingSort: CatalogFilter.SortOption?
    @Published var pendingGenres: Set<Int>?
    @Published var pendingTags: Set<Int>?
    @Published var toast: String?

    /// Каталог с одним выбранным жанром или тегом (по нажатию на него на странице тайтла).
    func openCatalog(genre: Int? = nil, tag: Int? = nil) {
        pendingQuery = ""
        pendingSort = .views
        pendingGenres = genre.map { [$0] } ?? []
        pendingTags = tag.map { [$0] } ?? []
        tab = 1
    }

    func openCatalog(query: String = "", sort: CatalogFilter.SortOption? = nil) {
        pendingQuery = query
        pendingSort = sort ?? .views
        tab = 1
    }
}

// MARK: - История просмотра («Продолжить смотреть»)
struct HistoryItem: Codable, Identifiable {
    let anime: Anime
    var episodeID: Int
    var episodeTitle: String
    var updated: Date
    var id: Int { anime.id }
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore(key: "history.v1")
    static let novels = HistoryStore(key: "history.novels.v1")
    static let manga = HistoryStore(key: "history.manga.v1")
    static let hentai = HistoryStore(key: "history.hentai.v1")
    static var current: HistoryStore {
        let site = LibSite.current
        if site.isHentai { return hentai }
        return site.isManga ? manga : (site.isRanobe ? novels : shared)
    }
    @Published private(set) var items: [HistoryItem] = []
    private let key: String

    init(key: String) {
        self.key = key
        if let d = UserDefaults.standard.data(forKey: key),
           let v = try? JSONDecoder().decode([HistoryItem].self, from: d) {
            items = v
        }
    }

    func recordChapter(anime: Anime, chapterID: Int, title: String) {
        FavMetaStore.shared.markSeen(anime)
        items.removeAll { $0.anime.id == anime.id }
        items.insert(HistoryItem(anime: anime, episodeID: chapterID, episodeTitle: title, updated: Date()), at: 0)
        if items.count > 30 { items = Array(items.prefix(30)) }
        save()
    }

    func record(anime: Anime, episode: EpisodeShort) {
        FavMetaStore.shared.markSeen(anime)
        items.removeAll { $0.anime.id == anime.id }
        items.insert(HistoryItem(anime: anime, episodeID: episode.id,
                                 episodeTitle: episode.title, updated: Date()), at: 0)
        if items.count > 30 { items = Array(items.prefix(30)) }
        save()
    }

    func remove(_ animeID: Int) {
        items.removeAll { $0.anime.id == animeID }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: key) }
    }
}

// MARK: - Главная
@MainActor
final class HomeViewModel: ObservableObject {
    @Published var fresh: [Anime] = []
    @Published var popular: [Anime] = []
    @Published var newest: [Anime] = []
    @Published var top: [Anime] = []
    @Published var isLoading = false
    @Published var loadingMore = false
    @Published var error: String?
    private var popularPage = 1
    private var popularHasNext = true

    var canLoadMorePopular: Bool { popularHasNext && !popular.isEmpty }

    private func fetch(_ sort: CatalogFilter.SortOption, page: Int = 1) async -> (items: [Anime], hasNext: Bool)? {
        var f = CatalogFilter()
        f.sortBy = sort
        if sort == .rating {
            guard let r = try? await AnimelibAPI.shared.catalogRated(filter: f, startPage: page) else { return nil }
            return (r.items, r.hasNext)
        }
        return try? await AnimelibAPI.shared.catalog(filter: f, page: page)
    }

    func load(force: Bool = false) async {
        guard !isLoading else { return }
        if !force && !fresh.isEmpty { return }
        isLoading = true
        defer { isLoading = false }
        func uniq(_ l: [Anime]) -> [Anime] { var seen = Set<Int>(); return l.filter { seen.insert($0.id).inserted } }
        // Каждая лента показывается, как только пришла: «Лучшее по рейтингу» перебирает много страниц
        // и раньше задерживало весь экран.
        enum Part { case fresh, popular, newest, top }
        var gotAny = false
        await withTaskGroup(of: (Part, (items: [Anime], hasNext: Bool)?).self) { group in
            group.addTask { (.fresh, await self.fetch(.lastEpisode)) }
            group.addTask { (.popular, await self.fetch(.views)) }
            group.addTask { (.newest, await self.fetch(.newest)) }
            group.addTask { (.top, await self.fetch(.rating)) }
            for await (part, res) in group {
                guard let r = res else { continue }
                gotAny = true
                let list = uniq(r.items)
                switch part {
                case .fresh: fresh = list
                case .popular: popular = list; popularPage = 1; popularHasNext = r.hasNext
                case .newest: newest = list
                case .top: top = list
                }
                // Обложки тех же размеров, что берут карточки, иначе подгрузка уходит впустую.
                ImageLoader.prefetch(list.prefix(14).compactMap { $0.posterURL }, maxPixel: 720)
            }
        }
        error = gotAny ? nil : "Не удалось загрузить данные. Проверьте соединение."
    }

    func morePopular() async {
        guard !loadingMore, popularHasNext else { return }
        loadingMore = true
        defer { loadingMore = false }
        if let r = await fetch(.views, page: popularPage + 1) {
            let known = Set(popular.map { $0.id })
            popular += r.items.filter { !known.contains($0.id) }
            popularPage += 1
            popularHasNext = r.hasNext && !r.items.isEmpty
        } else {
            popularHasNext = false
        }
    }
}

struct TopBlur: View {
    let inset: CGFloat
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(height: inset + 14)
            .mask(LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.75),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
            .offset(y: -inset)
    }
}

extension View {
    /// Маленькая стеклянная капсула для бейджей и кнопок (на iOS 26 настоящее стекло, ниже — блюр).
    @ViewBuilder func glassCapsule() -> some View {
        glassShape(Capsule())
    }

    /// Настоящее стекло iOS 26 (подчиняется системным настройкам прозрачности), ниже — обычный блюр.
    @ViewBuilder func glassShape<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionTitle: String? = nil

    var body: some View {
        HStack {
            if let action, actionTitle == nil {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(title).font(.title3.bold())
                        Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Theme.accent)
                    }
                }
                .buttonStyle(.pressable)
            } else {
                Text(title).font(.title3.bold())
            }
            Spacer()
            if let action, let t = actionTitle {
                Button(t, action: action).font(.footnote).foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 14)
    }
}

/// Компактная иконка-пометка на обложке: «НОВОЕ» — искра, «НОВАЯ ГЛАВА» — плюс главы. Почти не закрывает обложку.
struct UpdateMark: View {
    let text: String
    private var isNew: Bool { text == "НОВОЕ" }
    var body: some View {
        Image(systemName: isNew ? "sparkles" : "plus")
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background {
                if isNew {
                    Circle().fill(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    Circle().fill(Color.black.opacity(0.55))
                }
            }
            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.6))
            .padding(6)
            .accessibilityLabel(text)
    }
}

struct PosterCard: View {
    let anime: Anime
    var width: CGFloat = 124
    /// Необязательная пометка в правом верхнем углу («Новое» и т. п.)
    var mark: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: width > 140 ? anime.posterURL : anime.imageURL, maxPixel: width > 140 ? 720 : 480)
                .frame(width: width, height: width * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.chip, lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if let t = anime.type?.title, !t.isEmpty {
                        Text(t)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .foregroundStyle(.white)
                            .background(Color.black.opacity(0.5), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                            .padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let mark { UpdateMark(text: mark) }
                }
                .overlay(alignment: .bottomLeading) {
                    if let r = anime.rateAvg {
                        Label(r, systemImage: "star.fill")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .foregroundStyle(.white)
                            .background(Color.black.opacity(0.5), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                            .padding(6)
                    }
                }
            Text(anime.displayTitle)
                .font(width > 140 ? .subheadline.weight(.medium) : .footnote.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

struct AnimeRow: View {
    let anime: Anime
    var rank: Int? = nil
    /// Лёгкий вид без плашки: обложка, название, рейтинг.
    var light = false

    var body: some View {
        HStack(spacing: 12) {
            if let rank {
                if light {
                    Text("\(rank)")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(rank <= 3
                                         ? AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.accent2],
                                                                        startPoint: .top, endPoint: .bottom))
                                         : AnyShapeStyle(Color.secondary.opacity(0.55)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 46)
                } else {
                    Text("\(rank)")
                        .font(.headline.bold())
                        .foregroundStyle(rank <= 3 ? Theme.accent : Color.secondary)
                        .frame(width: 22)
                }
            }
            RemoteImage(url: light ? anime.posterURL : anime.imageURL, maxPixel: light ? 720 : 480)
                .frame(width: light ? 62 : 52, height: light ? 93 : 78)
                .clipShape(RoundedRectangle(cornerRadius: light ? 12 : 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(anime.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text([anime.type?.title, LibSite.current.isBook ? nil : anime.episodesCount.map { "\($0) эп." }]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let r = anime.rateAvg {
                RatingBadge(text: r)
            }
        }
        .padding(light ? EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0) : EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        .background {
            if !light { RoundedRectangle(cornerRadius: 16).fill(Theme.card) }
        }
        .overlay(alignment: .bottom) {
            if light { Divider().opacity(0.5).padding(.leading, 34) }
        }
        .contentShape(Rectangle())
    }
}

/// Первое место списка «Сейчас смотрят/читают»: крупная карточка с размытым фоном из обложки.
struct PopularHero: View {
    let anime: Anime

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: anime.posterURL, maxPixel: 720)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(1.4)
                .blur(radius: 28)
                .overlay(LinearGradient(colors: [.black.opacity(0.30), .black.opacity(0.72)],
                                        startPoint: .top, endPoint: .bottom))
            HStack(alignment: .bottom, spacing: 16) {
                RemoteImage(url: anime.posterURL, maxPixel: 720)
                    .frame(width: 112, height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                VStack(alignment: .leading, spacing: 8) {
                    Label("№1 сейчас", systemImage: "flame.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .glassCapsule()
                    Text(anime.displayTitle)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Text([anime.type?.title, LibSite.current.isBook ? nil : anime.episodesCount.map { "\($0) эп." }]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                    if let r = anime.rateAvg {
                        RatingBadge(text: r)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct ContinueCard: View {
    let item: HistoryItem
    @ObservedObject private var progress = ProgressStore.shared

    var body: some View {
        let p = LibSite.current.isBook ? nil : progress.get(item.episodeID)
        HStack(spacing: 12) {
            RemoteImage(url: item.anime.imageURL)
                .frame(width: 44, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.anime.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(item.episodeTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let p, p.position > 5 {
                    Text(p.duration > 0 ? "\(formatTime(p.position)) из \(formatTime(p.duration))" : formatTime(p.position))
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                    if p.duration > 0 {
                        ProgressView(value: min(p.position / p.duration, 1))
                            .tint(Theme.accent)
                    }
                }
                if LibSite.current.isBook, let rp = ReadPosStore.shared.get(item.anime.readKey),
                   rp.c == item.episodeID, rp.pct > 0 {
                    Text("Прочитано \(rp.pct)%").font(.caption2).foregroundStyle(Theme.accent)
                    ProgressView(value: Double(rp.pct) / 100).tint(Theme.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 240)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background {
            CoverTintLayer(url: item.anime.imageURL, strength: 0.4, horizontal: true)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

/// Единая плашка рейтинга: белая звезда на тёмной капсуле, как на обложках в каталоге.
struct RatingBadge: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "star.fill")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Color.black.opacity(0.5), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
    }
}

struct TodayHero: View {
    let anime: Anime

    var body: some View {
        ZStack {
            // размытый фон из той же обложки
            RemoteImage(url: anime.posterURL ?? anime.imageURL, maxPixel: 300)
                .scaleEffect(1.5)
                .blur(radius: 30)
                .allowsHitTesting(false)
            LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            HStack(spacing: 16) {
                // обложка целиком, без обрезки
                RemoteImage(url: anime.posterURL ?? anime.imageURL, maxPixel: 600)
                    .frame(width: 128, height: 192)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 0.6))
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                        Text("ВЫБОР ДНЯ").tracking(1.2)
                    }
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.5), Color(red: 1, green: 0.62, blue: 0.75)], startPoint: .leading, endPoint: .trailing))
                    Text(anime.displayTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(4)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        if let r = anime.rateAvg { RatingBadge(text: r) }
                        if let t = anime.type?.title { Text(t).foregroundStyle(.white.opacity(0.8)) }
                    }
                    .font(.footnote.weight(.semibold))
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Image(systemName: LibSite.current.isBook ? "book.fill" : "play.fill")
                        Text(LibSite.current.isBook ? "Читать" : "Смотреть")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .leading, endPoint: .trailing), in: Capsule())
                    .shadow(color: Theme.accent.opacity(0.5), radius: 8, y: 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 192)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
        .padding(.horizontal, 14)
    }
}

/// Последний тайтл крупно: прогресс и кнопка «Продолжить».
struct ContinueHero: View {
    let item: HistoryItem
    @ObservedObject private var progress = ProgressStore.shared

    var body: some View {
        let book = LibSite.current.isBook
        let p = book ? nil : progress.get(item.episodeID)
        let rp = book ? ReadPosStore.shared.get(item.anime.readKey) : nil
        let frac: Double? = {
            if let p, p.duration > 0, p.position > 5 { return min(p.position / p.duration, 1) }
            if let rp, rp.c == item.episodeID, rp.pct > 0 { return Double(rp.pct) / 100 }
            return nil
        }()
        HStack(spacing: 14) {
            RemoteImage(url: item.anime.posterURL ?? item.anime.imageURL, maxPixel: 480)
                .frame(width: 76, height: 114)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 8) {
                Text(item.anime.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(item.episodeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.white.opacity(0.12), in: Capsule())
                    .lineLimit(1)
                if let frac {
                    ProgressView(value: frac).tint(Theme.accent)
                    Text("\(Int(frac * 100))%").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: book ? "book.fill" : "play.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 0.8))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 138)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .background {
            CoverTintLayer(url: item.anime.imageURL, strength: 0.45, horizontal: true)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 0.5))
    }
}

/// Широкая карточка: обложка слева, данные справа.
struct WideCard: View {
    let anime: Anime
    var mark: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: anime.posterURL ?? anime.imageURL, maxPixel: 420)
                .frame(width: 92, height: 138)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(anime.displayTitle)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if let t = anime.type?.title {
                    Text(t).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if let r = anime.rateAvg { RatingBadge(text: r) }
                    if let mark {
                        Text(mark)
                            .font(.system(size: 10, weight: .heavy))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .foregroundStyle(.white)
                            .background(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .leading, endPoint: .trailing), in: Capsule())
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 290, height: 162)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background {
            CoverTintLayer(url: anime.imageURL, strength: 0.35, horizontal: true)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @ObservedObject private var history: HistoryStore = HistoryStore.current
    @ObservedObject private var router = AppRouter.shared
    @State private var query = ""
    @State private var confirmClear = false
    private let ranobe = LibSite.current.isBook

    /// «Выбор дня»: из лучших и популярных, один и тот же в течение суток.
    private var todayPick: Anime? {
        var seen = Set<Int>()
        let pool = (vm.top.prefix(12) + vm.popular.prefix(10)).filter { seen.insert($0.id).inserted }
        guard !pool.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return pool[day % pool.count]
    }

    private func wideRail(_ list: [Anime], newIDs: Set<Int>? = nil) -> some View {
        var seen = Set<Int>()
        let unique = list.filter { seen.insert($0.id).inserted }
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(unique) { a in
                    TitleLink(anime: a) { WideCard(anime: a, mark: newIDs.map { $0.contains(a.id) ? "НОВОЕ" : "НОВАЯ ГЛАВА" }) }
                        .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func poster(_ list: [Anime], newIDs: Set<Int> = []) -> some View {
        // повторяющиеся id ломают ленивую ленту: карточки перестают нажиматься и листаться
        var seen = Set<Int>()
        let unique = list.filter { seen.insert($0.id).inserted }
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(unique) { a in
                    TitleLink(anime: a) { PosterCard(anime: a, width: 154, mark: newIDs.contains(a.id) ? "НОВОЕ" : nil) }
                        .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {

                        if let e = vm.error, vm.fresh.isEmpty {
                            VStack(spacing: 12) {
                                Text(e).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                Button("Повторить") { Task { await vm.load(force: true) } }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        }

                        if let pick = todayPick {
                            TitleLink(anime: pick) { TodayHero(anime: pick) }
                                .buttonStyle(.pressable)
                        }

                        if let first = history.items.first {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: ranobe ? "Продолжить читать" : "Продолжить смотреть",
                                              action: { confirmClear = true }, actionTitle: "Очистить")
                                ZStack(alignment: .topTrailing) {
                                    TitleLink(anime: first.anime) { ContinueHero(item: first) }
                                        .buttonStyle(.pressable)
                                    Button {
                                        Haptics.tap()
                                        withAnimation(.easeInOut(duration: 0.25)) { history.remove(first.anime.id) }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Color.black.opacity(0.55))
                                            .padding(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                                    .padding(.horizontal, 14)
                                    .contextMenu {
                                        Button(role: .destructive) { history.remove(first.anime.id) } label: {
                                            Label("Убрать из списка", systemImage: "trash")
                                        }
                                    }
                                if history.items.count > 1 {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 12) {
                                        ForEach(Array(history.items.dropFirst())) { h in
                                            ZStack(alignment: .topTrailing) {
                                                TitleLink(anime: h.anime) { ContinueCard(item: h) }
                                                    .buttonStyle(.pressable)
                                                Button {
                                                    Haptics.tap()
                                                    withAnimation(.easeInOut(duration: 0.25)) { history.remove(h.anime.id) }
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.title3)
                                                        .symbolRenderingMode(.palette)
                                                        .foregroundStyle(.white, Color.black.opacity(0.55))
                                                        .padding(6)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                                            .contextMenu {
                                                Button(role: .destructive) { history.remove(h.anime.id) } label: {
                                                    Label("Убрать из списка", systemImage: "trash")
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                }
                                }
                            }
                            .confirmationDialog("Очистить список?", isPresented: $confirmClear, titleVisibility: .visible) {
                                Button("Очистить всё", role: .destructive) {
                                    withAnimation { history.clear() }
                                }
                                Button("Отмена", role: .cancel) {}
                            }
                        }

                        if !vm.fresh.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: ranobe ? "Свежие главы" : "Свежие серии") { router.openCatalog(sort: .lastEpisode) }
                                poster(Array(vm.fresh.prefix(14)))
                            }
                        }

                        if !vm.popular.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: ranobe ? "Сейчас читают" : "Сейчас смотрят") { router.openCatalog(sort: .views) }
                                LazyVStack(spacing: 0) {
                                    if let first = vm.popular.first {
                                        TitleLink(anime: first) { PopularHero(anime: first) }
                                            .buttonStyle(.pressable)
                                            .padding(.bottom, 8)
                                    }
                                    ForEach(Array(vm.popular.enumerated()).dropFirst(), id: \.element.id) { i, a in
                                        TitleLink(anime: a) { AnimeRow(anime: a, rank: i + 1, light: true) }
                                            .buttonStyle(.pressable)
                                    }
                                    if vm.canLoadMorePopular {
                                        Button { Task { await vm.morePopular() } } label: {
                                            Group {
                                                if vm.loadingMore { ProgressView() } else { Text("Показать ещё") }
                                            }
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                                        }
                                        .buttonStyle(.pressable)
                                    }
                                }
                                .padding(.horizontal, 14)
                            }
                        }

                        if !vm.newest.isEmpty {
                            if ranobe {
                                // «Последние обновления»: новые тайтлы вперемешку с тайтлами, где вышла новая глава
                                let newIDs = Set(vm.newest.map { $0.id })
                                let merged: [Anime] = {
                                    var out: [Anime] = []
                                    let a = vm.newest, b = vm.fresh
                                    for i in 0..<max(a.count, b.count) {
                                        if i < b.count { out.append(b[i]) }
                                        if i < a.count { out.append(a[i]) }
                                    }
                                    var seen = Set<Int>()
                                    return out.filter { seen.insert($0.id).inserted }
                                }()
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionHeader(title: "Последние обновления") { router.openCatalog(sort: .lastEpisode) }
                                    wideRail(Array(merged.prefix(24)), newIDs: newIDs)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionHeader(title: "Новинки") { router.openCatalog(sort: .newest) }
                                    wideRail(vm.newest)
                                }
                            }
                        }

                        if !vm.top.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Лучшее по рейтингу") { router.openCatalog(sort: .rating) }
                                VStack(spacing: 0) {
                                    ForEach(Array(vm.top.prefix(6).enumerated()), id: \.element.id) { i, a in
                                        TitleLink(anime: a) { AnimeRow(anime: a, rank: i + 1, light: true) }
                                            .buttonStyle(.pressable)
                                    }
                                }
                                .padding(.horizontal, 14)
                            }
                        }

                        if vm.isLoading && vm.fresh.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(.top, 30) }
                        Color.clear.frame(height: 120)
                    }
                    .padding(.top, 6)
                }
                .scrollDismissesKeyboard(.immediately)
                .refreshable { await vm.load(force: true) }
            }
            .background {
                ZStack(alignment: .top) {
                    AppBackground()
                    if let pick = todayPick {
                        CoverTintLayer(url: pick.posterURL ?? pick.imageURL, strength: 0.5)
                            .frame(height: 560)
                            .ignoresSafeArea()
                    }
                }
            }
            .navigationTitle(LibSite.current.title)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск по названию")
            .onSubmit(of: .search) {
                let q = query.trimmingCharacters(in: .whitespaces)
                guard !q.isEmpty else { return }
                SearchHistory.shared.add(q)
                router.openCatalog(query: q)
                query = ""
            }
            .navigationDestination(for: Anime.self) { DetailView(anime: $0) }
            .navigationDestination(for: Novel.self) { NovelDetailView(novel: $0) }
            .task { await vm.load() }
        }
    }
}

/// На iOS 26 таб-бар сворачивается в компактную капсулу при прокрутке вниз.
struct TabBarMinimize: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

struct RootView: View {
    @AppStorage("accent.hex") private var accentHex = Theme.defaultAccentHex
    @AppStorage("set.platform") private var platform = "anime"
    @AppStorage("set.theme") private var appTheme = "system"
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var router = AppRouter.shared
    @State private var newBadge = 0
    @State private var showFound = false
    @State private var showDone = false
    @State private var foundText = ""

    private func applyFound() {
        let r = BackupManager.readAppFolderCopy()
        if let d = r.0, BackupManager.restore(d) != nil {
            BackupManager.acceptExternal()
            Haptics.success()
            showDone = true
        }
    }

    private var scheme: ColorScheme? {
        switch appTheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        TabView(selection: $router.tab) {
            HomeView()
                .tabItem { Label("Главная", systemImage: "house.fill") }
                .tag(0)
            CatalogView()
                .tabItem { Label("Каталог", systemImage: "square.grid.2x2") }
                .tag(1)
            FavoritesView()
                .badge(newBadge)
                .tabItem { Label("Избранное", systemImage: "heart") }
                .tag(2)
            ProfileView()
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
                .tag(3)
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape") }
                .tag(4)
        }
        .id(accentHex + platform)
        .modifier(TabBarMinimize())
        .transition(.opacity)
        .tint(Color(hex: accentHex))
        .preferredColorScheme(scheme)
        .onChange(of: router.tab) { _ in Haptics.select() }
        .onChange(of: scenePhase) { phase in
            if phase != .active { ProgressStore.shared.flush(); ActivityStore.shared.flush() }
            if phase == .background { BackupManager.writeAuto() }
            if phase == .active { Task { await FavUpdater.refreshIfDue() } }
            if phase == .active, let d = BackupManager.externalCopyDate() {
                foundText = d.formatted(date: .abbreviated, time: .shortened)
                showFound = true
            }
        }
        .task {
            BackupManager.writeAuto()
            newBadge = FavMetaStore.shared.totalNew(FavoritesStore.current.items)
            await FavUpdater.refreshIfDue()
        }
        .onReceive(FavMetaStore.shared.$items.debounce(for: .seconds(1), scheduler: RunLoop.main)) { _ in
            newBadge = FavMetaStore.shared.totalNew(FavoritesStore.current.items)
        }
        .alert("Найдена копия в папке приложения", isPresented: $showFound) {
            Button("Загрузить") { applyFound() }
            Button("Не нужно", role: .cancel) { BackupManager.acceptExternal() }
        } message: {
            Text("Файл Yume-backup от \(foundText). Загрузить из него прогресс, избранное и настройки?")
        }
        .overlay {
            Color.clear.allowsHitTesting(false)
                .alert("Готово", isPresented: $showDone) {
                    Button("Закрыть приложение") { exit(0) }
                } message: {
                    Text("Открой Yume заново, чтобы всё применилось.")
                }
        }
        .overlay(alignment: .top) {
            if let t = router.toast {
                Text(t)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: t) {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        if router.toast == t { router.toast = nil }
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: router.toast)
    }
}

@MainActor
final class SearchHistory: ObservableObject {
    static let shared = SearchHistory()
    @Published private(set) var items: [String] = []

    init() { items = UserDefaults.standard.stringArray(forKey: "search.history") ?? [] }

    func add(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        items.removeAll { $0.lowercased() == t.lowercased() }
        items.insert(t, at: 0)
        items = Array(items.prefix(8))
        UserDefaults.standard.set(items, forKey: "search.history")
    }

    func clear() {
        items = []
        UserDefaults.standard.removeObject(forKey: "search.history")
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
    private(set) var loadedQuery = ""
    /// id недавно добавленных тайтлов: нужны только для пометок в списке «Последние обновления»
    @Published private(set) var newIDs: Set<Int> = []
    private var newIDsLoaded = false

    var showsUpdateMarks: Bool { LibSite.current.isBook && filter.sortBy == .lastEpisode }

    func loadNewIDs() async {
        guard showsUpdateMarks, !newIDsLoaded else { return }
        newIDsLoaded = true
        var f = CatalogFilter()
        f.sortBy = .newest
        var ids = Set<Int>()
        for pg in 1...3 {
            guard let r = try? await AnimelibAPI.shared.catalog(filter: f, page: pg) else { break }
            ids.formUnion(r.items.map { $0.id })
            if !r.hasNext { break }
        }
        newIDs = ids
    }

    func reload() async {
        generation += 1
        loadedQuery = filter.query
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
            let r: (items: [Anime], hasNext: Bool, next: Int)
            if filter.sortBy == .rating {
                r = try await AnimelibAPI.shared.catalogRated(filter: filter, startPage: page)
            } else {
                let x = try await AnimelibAPI.shared.catalog(filter: filter, page: page)
                r = (x.items, x.hasNext, page + 1)
            }
            guard gen == generation else { return }
            let known = Set(items.map(\.id))
            let fresh = r.items.filter { !known.contains($0.id) }
            items += fresh
            ImageLoader.prefetch(fresh.compactMap { $0.imageURL })
            hasNext = r.hasNext
            page = r.next
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
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassShape(Capsule())
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
                                Chip(title: opt.label(LibSite.current.isBook), selected: vm.filter.sortBy == opt) {
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
    @ObservedObject private var router = AppRouter.shared
    @State private var showFilters = false
    @ObservedObject private var searches = SearchHistory.shared
    @State private var randomTarget: Anime?
    @State private var showRandom = false
    @State private var rolling = false
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    private func roll() {
        guard !rolling else { return }
        rolling = true
        Haptics.tap()
        let filter = vm.filter
        Task { @MainActor in
            var pick: Anime?
            for _ in 0..<3 where pick == nil {
                if let r = try? await AnimelibAPI.shared.catalog(filter: filter, page: Int.random(in: 1...25)) {
                    pick = r.items.randomElement()
                }
            }
            if pick == nil, let r = try? await AnimelibAPI.shared.catalog(filter: filter, page: 1) {
                pick = r.items.randomElement()
            }
            rolling = false
            if let a = pick {
                randomTarget = a
                showRandom = true
                Haptics.success()
            }
        }
    }

    @ViewBuilder
    private var randomDestination: some View {
        if let a = randomTarget {
            if LibSite.current.isBook { NovelDetailView(novel: Novel(a)) } else { DetailView(anime: a) }
        }
    }

    private var randomButton: some View {
        Button { roll() } label: {
            Group {
                if rolling { ProgressView() } else { Image(systemName: "dice.fill").font(.headline) }
            }
            .frame(width: 44, height: 44)
            .glassShape(Circle())
        }
        .buttonStyle(.pressable)
    }

    private var filterButton: some View {
        Button { showFilters = true } label: {
            Group {
                if vm.filter.activeCount > 0 {
                    Image(systemName: "slider.horizontal.3").font(.headline)
                        .frame(width: 44, height: 44)
                        .background(Theme.accent, in: Circle())
                } else {
                    Image(systemName: "slider.horizontal.3").font(.headline)
                        .frame(width: 44, height: 44)
                        .glassShape(Circle())
                }
            }
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
        .buttonStyle(.pressable)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
            ScrollView {
                VStack(spacing: 10) {
                    HStack {
                        Text(LibSite.current.title)
                            .font(.largeTitle.bold())
                        Spacer()
                        randomButton
                        filterButton
                    }
                    SearchBar(text: $vm.filter.query) {
                        searches.add(vm.filter.query)
                        Task { await vm.reload() }
                    }
                    if vm.filter.query.isEmpty && !searches.items.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                                ForEach(searches.items, id: \.self) { q in
                                    Chip(title: q, selected: false) {
                                        vm.filter.query = q
                                        Task { await vm.reload() }
                                    }
                                }
                                Button { searches.clear() } label: {
                                    Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                    }
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
                        TitleLink(anime: anime) { AnimeCard(anime: anime, mark: vm.showsUpdateMarks ? (vm.newIDs.contains(anime.id) ? "НОВОЕ" : "НОВАЯ ГЛАВА") : nil) }
                            .buttonStyle(.pressable)
                            .task { await vm.loadNewIDs() }
                            .onAppear {
                                if vm.items.suffix(8).contains(where: { $0.id == anime.id }) { Task { await vm.loadMore() } }
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
            .navigationDestination(for: Novel.self) { NovelDetailView(novel: $0) }
            .navigationDestination(isPresented: $showRandom) { randomDestination }
            .sheet(isPresented: $showFilters) { FilterSheet(vm: vm) }
            .task { if vm.items.isEmpty { await vm.reload() } }
            .task(id: vm.filter.query) {
                // живой поиск: ждём, пока вы закончите печатать
                guard vm.filter.query != vm.loadedQuery else { return }
                try? await Task.sleep(nanoseconds: 450_000_000)
                if Task.isCancelled || vm.filter.query == vm.loadedQuery { return }
                await vm.reload()
            }
            .onAppear {
                var changed = false
                if let q = router.pendingQuery { vm.filter.query = q; router.pendingQuery = nil; changed = true }
                if let so = router.pendingSort { vm.filter.sortBy = so; router.pendingSort = nil; changed = true }
                if let g = router.pendingGenres, let t = router.pendingTags {
                    vm.filter.genres = g; vm.filter.tags = t; vm.filter.types = []; vm.filter.statuses = []
                    router.pendingGenres = nil; router.pendingTags = nil; changed = true
                }
                if changed { Task { await vm.reload() } }
            }
        }
    }
}

struct AnimeCard: View {
    let anime: Anime
    /// Пометка в правом верхнем углу («НОВОЕ» / «НОВАЯ ГЛАВА») — только в списке по последним обновлениям
    var mark: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: anime.posterURL ?? anime.imageURL, maxPixel: 520)
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                .overlay(alignment: .topTrailing) {
                    if let mark { UpdateMark(text: mark) }
                }
                .overlay(alignment: .bottomLeading) {
                    if let r = anime.rateAvg {
                        Label(r, systemImage: "star.fill")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(.white)
                            .background(Color.black.opacity(0.5), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                            .padding(7)
                    }
                }
            Text(anime.displayTitle)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}

// MARK: - Автор: все его тайтлы
struct AuthorRef: Hashable {
    let id: Int
    let name: String
    var slug: String? = nil
}

@MainActor
final class AuthorViewModel: ObservableObject {
    @Published var items: [Anime] = []
    @Published var isLoading = false
    @Published var error: String?
    private var page = 1
    private var finished = false
    let authorID: Int
    let slug: String?

    init(authorID: Int, slug: String?) {
        self.authorID = authorID
        self.slug = slug
    }

    func loadMore() async {
        guard !isLoading, !finished else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let r = try await AnimelibAPI.shared.byAuthor(authorID, slug: slug, page: page)
            let known = Set(items.map { $0.id })
            let fresh = r.items.filter { !known.contains($0.id) }
            items += fresh
            ImageLoader.prefetch(fresh.compactMap { $0.imageURL })
            page += 1
            if fresh.isEmpty || !r.hasNext { finished = true }
            error = nil
        } catch {
            if items.isEmpty { self.error = error.localizedDescription } else { finished = true }
        }
    }
}

struct AuthorView: View {
    let author: AuthorRef
    @StateObject private var vm: AuthorViewModel
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    init(author: AuthorRef) {
        self.author = author
        _vm = StateObject(wrappedValue: AuthorViewModel(authorID: author.id, slug: author.slug))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(author.name).font(.title3.bold())
                        Text("Все тайтлы автора").font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))

                if let e = vm.error {
                    Text(e).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                    HStack(spacing: 16) {
                        Button("Повторить") { Task { await vm.loadMore() } }
                        Button("Скопировать текст ошибки") { UIPasteboard.general.string = e }
                    }
                    .font(.footnote)
                    NavigationLink {
                        SiteLogView(path: "people/\(author.slug ?? String(author.id))")
                    } label: {
                        Label("Открыть страницу автора на сайте и записать запросы", systemImage: "waveform.path.ecg")
                            .font(.footnote.weight(.semibold))
                    }
                }
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(vm.items) { a in
                        TitleLink(anime: a) { AnimeCard(anime: a) }
                            .buttonStyle(.pressable)
                            .onAppear {
                                if vm.items.suffix(8).contains(where: { $0.id == a.id }) { Task { await vm.loadMore() } }
                            }
                    }
                }
                if vm.isLoading { ProgressView().frame(maxWidth: .infinity) }
                if vm.items.isEmpty && !vm.isLoading && vm.error == nil {
                    Text("Тайтлов не найдено").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .padding(14)
        }
        .background(AppBackground())
        .navigationTitle(author.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.loadMore() }
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
    private let autoContinue: Bool
    @State private var didAutoContinue = false

    init(anime: Anime, autoContinue: Bool = false) {
        _vm = StateObject(wrappedValue: DetailViewModel(anime: anime))
        self.autoContinue = autoContinue
    }

    /// Открывает серию, на которой остановились (или следующую, если она досмотрена).
    private func openContinue() {
        guard !vm.episodes.isEmpty else { return }
        var idx = 0
        if let h = HistoryStore.shared.items.first(where: { $0.anime.id == vm.anime.id }),
           let i = vm.episodes.firstIndex(where: { $0.id == h.episodeID }) {
            idx = i
            if progress.get(h.episodeID)?.finished == true, i + 1 < vm.episodes.count { idx = i + 1 }
        }
        selected = vm.episodes[idx]
    }

    private var animePills: [(String, String)] {
        var p: [(String, String)] = []
        if let r = vm.anime.rateAvg { p.append(("star.fill", r)) }
        if let s = vm.anime.status?.title, !s.isEmpty { p.append(("dot.radiowaves.left.and.right", s)) }
        if let t = vm.anime.type?.title, !t.isEmpty { p.append(("tv", t)) }
        if let a = vm.anime.ageRestriction?.title, !a.isEmpty { p.append(("exclamationmark.shield", a)) }
        if let n = vm.anime.episodesCount { p.append(("list.bullet", "\(n) эп.")) }
        return p
    }

    private var continueTitle: String {
        if let h = HistoryStore.shared.items.first(where: { $0.anime.id == vm.anime.id }),
           let i = vm.episodes.firstIndex(where: { $0.id == h.episodeID }) {
            let next = progress.get(h.episodeID)?.finished == true && i + 1 < vm.episodes.count ? i + 1 : i
            return "Продолжить: серия \(vm.episodes[next].number ?? "")"
        }
        return "Смотреть"
    }

    private var backdrop: some View {
        ZStack {
            Theme.base
            RemoteImage(url: vm.anime.imageURL, maxPixel: 96)
                .blur(radius: 16)
                .opacity(0.55)
            CoverTintLayer(url: vm.anime.imageURL, strength: 0.6)
            LinearGradient(colors: [.clear, Theme.base.opacity(0.85), Theme.base], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TitleHero(cover: vm.anime.largeImageURL ?? vm.anime.imageURL, title: vm.anime.displayTitle,
                          subtitle: (vm.anime.name != nil && vm.anime.name != vm.anime.displayTitle) ? vm.anime.name : nil,
                          pills: animePills)

                if !vm.episodes.isEmpty {
                    PrimaryActionButton(icon: "play.fill", title: continueTitle) { openContinue() }
                }

                if !(vm.anime.genres ?? []).isEmpty || !(vm.anime.tags ?? []).isEmpty {
                    GenreStrip(genres: vm.anime.genres ?? [], tags: vm.anime.tags ?? [])
                }

                if let s = vm.anime.summary, !s.isEmpty { SummaryCard(text: s, expanded: $expanded) }

                TitleActionsRow(anime: vm.anime) { showComments = true }

                HStack(alignment: .firstTextBaseline) {
                    Text("Серии").font(.title2.bold())
                    if !vm.episodes.isEmpty { Text("\(vm.episodes.count)").font(.subheadline).foregroundStyle(.secondary) }
                }
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
                                    .frame(width: 44, height: 44)
                                    .background(pr != nil ? Color.gray.opacity(0.22) : Theme.accent.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 0.5))
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
            .padding(16)
        }
        .background(backdrop)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationDestination(for: AuthorRef.self) { AuthorView(author: $0) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let u = titleURL(vm.anime) {
                    Link(destination: u) { Image(systemName: "safari") }
                    ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }
                }
                Button { showBookmark = true } label: { Image(systemName: "bookmark") }
                Button { favorites.toggle(vm.anime) } label: {
                    Image(systemName: favorites.contains(vm.anime) ? "heart.fill" : "heart")
                        .foregroundStyle(favorites.contains(vm.anime) ? Color.pink : Color.primary)
                }
            }
        }
        .task {
            await vm.load()
            if autoContinue, !didAutoContinue {
                didAutoContinue = true
                openContinue()
            }
        }
        .sheet(isPresented: $showComments) { CommentsView(anime: vm.anime) }
        .sheet(isPresented: $showBookmark) { BookmarkSheet(anime: vm.anime) }
        .fullScreenCover(item: $selected) { ep in
            PlayerScreen(episode: ep, animeTitle: vm.anime.displayTitle, anime: vm.anime, episodes: vm.episodes)
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
    private(set) var items: [String: WatchProgress] = [:]
    private let key = "progress.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let v = try? JSONDecoder().decode([String: WatchProgress].self, from: d) {
            items = v
        }
    }

    func clear() {
        objectWillChange.send()
        items = [:]
        UserDefaults.standard.removeObject(forKey: key)
    }

    func get(_ id: Int) -> WatchProgress? { items[String(id)] }
    func position(_ id: Int) -> Double { items[String(id)]?.position ?? 0 }

    func opened(_ id: Int) {
        if items[String(id)] == nil {
            objectWillChange.send()
            items[String(id)] = WatchProgress(position: 0, duration: 0, updated: Date())
            save()
        }
    }

    func update(_ id: Int, position: Double, duration: Double) {
        let new = WatchProgress(position: position, duration: duration, updated: Date())
        let old = items[String(id)]
        // перерисовываем экраны только при заметных изменениях, а не каждые 5 секунд
        if old == nil || old?.finished != new.finished || abs((old?.position ?? 0) - position) >= 30 {
            objectWillChange.send()
        }
        items[String(id)] = new
        if new.finished && !(old?.finished ?? false) { ActivityStore.shared.addEpisode() }
        save()
    }

    private var dirty = false
    private var lastSave = Date.distantPast

    private func save() {
        dirty = true
        if Date().timeIntervalSince(lastSave) >= 20 { flush() }
    }

    /// Записывает накопленное на диск (вызывается при сворачивании и выходе из плеера).
    func flush() {
        guard dirty else { return }
        dirty = false
        lastSave = Date()
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
    var onFullscreen: ((Double, URL?) -> Void)? = nil
    var interceptFS = false

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var loaded: URL?
        var onStream: ((URL) -> Void)?
        var onFullscreen: ((Double, URL?) -> Void)?
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            guard let t = m.body as? String else { return }
            if t.hasPrefix("FS|") {
                let parts = t.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
                let time = parts.count > 1 ? (Double(parts[1]) ?? 0) : 0
                var link: URL?
                if parts.count > 2, parts[2].hasPrefix("http") { link = URL(string: String(parts[2])) }
                DispatchQueue.main.async { self.onFullscreen?(time, link) }
                return
            }
            guard t.hasPrefix("http"), let u = URL(string: t) else { return }
            DispatchQueue.main.async { self.onStream?(u) }
        }
    }

    /// Кнопка «на весь экран» в веб-плеере вместо этого открывает родной плеер iOS.
    static let fsHook = """
    (function(){
      if (window.__heheFS) return; window.__heheFS = true;
      function fs(el){
        try {
          var v = (el && el.tagName === 'VIDEO') ? el : document.getElementsByTagName('video')[0];
          var u = v ? (v.currentSrc || v.src || '') : '';
          var t = v ? (v.currentTime || 0) : 0;
          if (v) { try { v.pause(); } catch (e) {} }
          window.webkit.messageHandlers.hehe.postMessage('FS|' + t + '|' + u);
        } catch (e) {}
      }
      try {
        HTMLVideoElement.prototype.webkitEnterFullscreen = function(){ fs(this); };
        HTMLVideoElement.prototype.webkitEnterFullScreen = function(){ fs(this); };
        var rf = function(){ fs(null); return Promise.resolve(); };
        Element.prototype.requestFullscreen = rf;
        Element.prototype.webkitRequestFullscreen = rf;
        Element.prototype.webkitRequestFullScreen = rf;
        Object.defineProperty(document, 'fullscreenEnabled', { get: function(){ return true; } });
        Object.defineProperty(document, 'webkitFullscreenEnabled', { get: function(){ return true; } });
      } catch (e) {}
    })();
    """

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIView(_ v: WKWebView, coordinator: Coordinator) {
        v.configuration.userContentController.removeScriptMessageHandler(forName: "hehe")
        v.stopLoading()
        v.loadHTMLString("", baseURL: nil)
    }

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
        if interceptFS {
            cfg.userContentController.addUserScript(
                WKUserScript(source: Self.fsHook, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.customUserAgent = Kodik.ua
        v.isOpaque = false
        v.backgroundColor = .black
        v.scrollView.isScrollEnabled = false
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {
        context.coordinator.onStream = onStream
        context.coordinator.onFullscreen = onFullscreen
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

struct FullscreenPlayer: UIViewControllerRepresentable {
    let player: AVPlayer?
    var onPiPStart: () -> Void = {}
    var onPiPStop: () -> Void = {}
    var onRestore: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var parent: FullscreenPlayer
        init(_ p: FullscreenPlayer) { parent = p }

        func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_ pvc: AVPlayerViewController) -> Bool {
            parent.onPiPStart()
            return true
        }

        func playerViewControllerWillStartPictureInPicture(_ pvc: AVPlayerViewController) {
            parent.onPiPStart()
        }

        func playerViewControllerDidStopPictureInPicture(_ pvc: AVPlayerViewController) {
            parent.onPiPStop()
        }

        func playerViewController(_ pvc: AVPlayerViewController,
                                  restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            parent.onRestore()
            completionHandler(true)
        }
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let c = AVPlayerViewController()
        c.player = player
        c.allowsPictureInPicturePlayback = true
        c.canStartPictureInPictureAutomaticallyFromInline = true
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ c: AVPlayerViewController, context: Context) {
        context.coordinator.parent = self
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
    @Published var sourceNote = ""
    @Published var playbackError: String?
    @Published var showNative = false
    var fsPlayer: AVPlayer?
    private var lastWebStream: URL?
    private var attempts: [(URL, [String: String])] = []
    private var attemptIndex = 0
    private var attemptLog: [String] = []
    private var statusObs: NSKeyValueObservation?
    private var lastQualityTitle: String?
    var autoNative = true
    var onEnd: (() -> Void)?
    var onWatched: (() -> Void)?
    private var watchedFired = false
    private var endObserver: NSObjectProtocol?
    var episodeID = 0
    var lastPosition: Double = 0
    private var timeObserver: Any?
    private var observedPlayer: AVPlayer?
    private var stopped = false

    var usesWeb: Bool {
        guard let v = current, v.isWeb else { return false }
        return !v.kodik || showWeb
    }

    func load(episodeID: Int) async {
        let prevTitle = current?.title
        isLoading = true; error = nil
        detachObserver(); player?.pause(); player = nil
        variants = []; current = nil; qualities = []; currentQuality = nil
        showWeb = false; note = nil; debug = ""; sourceNote = ""
        playbackError = nil; lastWebStream = nil; statusObs = nil
        stopped = false
        watchedFired = false
        self.episodeID = episodeID
        ProgressStore.shared.opened(episodeID)
        lastPosition = Settings.bool("set.resume", true) ? ProgressStore.shared.position(episodeID) : 0
        do {
            variants = try await AnimelibAPI.shared.variants(episodeID: episodeID)
            sourceNote = await AnimelibAPI.shared.variantNote
            if let first = variants.first { select(variants.first(where: { $0.title == prevTitle }) ?? first) }
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
            // Сначала веб-плеер Kodik: качество выбирается в нём, а родной плеер открывается по кнопке «на весь экран».
            if Settings.bool("set.kodikDirect", false) { Task { await playKodik(v) } } else { showWeb = true }
        } else if v.isWeb {
            savePosition(); detachObserver()
            player?.pause(); player = nil
            showWeb = true
        } else if !v.options.isEmpty {
            qualities = v.options
            // Сначала не выше 1080p: 2160p часто в формате, который iPhone не показывает (звук есть, картинки нет).
            let q = v.options.first(where: { $0.title == lastQualityTitle })
                ?? v.options.first(where: { (Int($0.title.dropLast()) ?? 0) <= 1080 })
                ?? v.options[0]
            pickQuality(q)
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
        lastQualityTitle = q.title
        if current?.isWeb == true {
            startAV(q.url, headers: ["Referer": "https://kodikplayer.com/", "Origin": "https://kodikplayer.com", "User-Agent": Kodik.ua])
        } else {
            playNative(q)
        }
    }

    /// Родной плеер Animelib: пробуем разные серверы и заголовки, пока видео не откроется.
    private func playNative(_ q: PlayableVariant) {
        let sets: [[String: String]] = [
            AnimelibAPI.shared.playbackHeaders,
            ["Referer": "https://animelib.org/", "Origin": "https://animelib.org"],
            [:]
        ]
        attempts = []
        for u in [q.url] + q.alts {
            for h in sets { attempts.append((u, h)) }
        }
        attemptIndex = 0
        attemptLog = []
        playbackError = nil
        runAttempt()
    }

    private func runAttempt() {
        guard attemptIndex < attempts.count else { return }
        let (u, h) = attempts[attemptIndex]
        startAV(u, headers: h)
        guard let item = player?.currentItem else { return }
        statusObs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            Task { @MainActor in self?.itemStatus(it) }
        }
    }

    private func itemStatus(_ item: AVPlayerItem) {
        guard item === player?.currentItem, attemptIndex < attempts.count else { return }
        if item.status == .readyToPlay {
            playbackError = nil
            checkVideo(item)
            return
        }
        guard item.status == .failed else { return }
        let code = item.errorLog()?.events.last?.errorStatusCode ?? 0
        let msg = item.error?.localizedDescription ?? "неизвестная ошибка"
        let host = attempts[attemptIndex].0.host ?? "?"
        attemptLog.append("\(host): \(code > 0 ? "HTTP \(code)" : msg)")
        attemptIndex += 1
        if attemptIndex < attempts.count {
            runAttempt()
        } else {
            var seen: [String] = []
            for l in attemptLog where !seen.contains(l) { seen.append(l) }
            playbackError = "Видео не открылось.\n" + seen.joined(separator: "\n")
        }
    }

    /// Звук идёт, а картинки нет (формат не поддерживается): переключаемся на качество ниже.
    private func checkVideo(_ item: AVPlayerItem) {
        Task { @MainActor [weak self, weak item] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, let item, item === self.player?.currentItem,
                  item.status == .readyToPlay, item.presentationSize == .zero else { return }
            self.lowerQuality()
        }
    }

    private func lowerQuality() {
        guard let i = qualities.firstIndex(where: { $0.id == currentQuality }), i + 1 < qualities.count else {
            playbackError = "Звук есть, но видео не показывается: этот формат не поддерживается устройством. Выбери другое качество или озвучку."
            return
        }
        let next = qualities[i + 1]
        note = "\(qualities[i].title) не показывает картинку на этом устройстве, включил \(next.title)."
        pickQuality(next)
    }

    /// Веб-плеер Kodik просит весь экран: открываем родной плеер с тем же потоком и временем.
    func webFullscreen(time: Double, url: URL?) {
        guard let stream = url ?? lastWebStream else {
            note = "Видео ещё не запущено. Нажми ▶ в плеере, затем «на весь экран»."
            return
        }
        let headers = ["Referer": "https://kodikplayer.com/", "Origin": "https://kodikplayer.com", "User-Agent": Kodik.ua]
        let asset = AVURLAsset(url: stream, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let p = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        if time > 1 { p.seek(to: CMTime(seconds: time, preferredTimescale: 600)) }
        fsPlayer = p
        showNative = true
        Haptics.tap()
        p.play()
    }

    /// Родной полноэкранный режим для уже играющего видео.
    func openFullscreen() {
        guard let p = player else { return }
        fsPlayer = p
        showNative = true
        Haptics.tap()
    }

    var pipActive = false

    func pipStarted() { pipActive = true }

    func pipRestored() {
        pipActive = false
        showNative = true
    }

    /// Окошко «картинка в картинке» закрыли: останавливаем видео, если экран плеера не открыт.
    func pipStopped() {
        pipActive = false
        guard !showNative else { return }
        if let p = fsPlayer {
            let t = p.currentTime().seconds
            let d = p.currentItem?.duration.seconds ?? 0
            if t.isFinite, d.isFinite, d > 0 { ProgressStore.shared.update(episodeID, position: t, duration: d) }
            if p !== player { p.pause() }
        }
        fsPlayer = nil
    }

    func closeNative() {
        if pipActive {
            showNative = false
            return
        }
        if let p = fsPlayer {
            let t = p.currentTime().seconds
            let d = p.currentItem?.duration.seconds ?? 0
            if t.isFinite, d.isFinite, d > 0 { ProgressStore.shared.update(episodeID, position: t, duration: d) }
            if t.isFinite { markWatched(t) }
            if p !== player { p.pause() }
        }
        fsPlayer = nil
        showNative = false
    }

    func forceWeb() { autoNative = false; showWeb = true; note = nil }

    /// Веб-плеер Kodik отдал адрес потока: запоминаем его для полноэкранного режима.
    func webStream(_ u: URL) {
        lastWebStream = u
    }

    private func startAV(_ url: URL, headers: [String: String]) {
        guard !stopped else { return }
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
                self?.markWatched(pos)
            }
        }
        observedPlayer = p
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.finishedPlaying() }
        }
        p.play()
    }

    private func finishedPlaying() {
        guard !stopped else { return }
        if let d = player?.currentItem?.duration.seconds, d.isFinite, d > 0 {
            ProgressStore.shared.update(episodeID, position: d, duration: d)
        }
        if Settings.bool("set.autoNext", true) { onEnd?() }
    }

    private func detachObserver() {
        if let o = timeObserver, let p = observedPlayer { p.removeTimeObserver(o) }
        timeObserver = nil; observedPlayer = nil
        if let o = endObserver { NotificationCenter.default.removeObserver(o); endObserver = nil }
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

    /// Серия считается начатой после 20 секунд просмотра, а не после простого открытия.
    func markWatched(_ pos: Double) {
        guard !watchedFired, pos >= 20 else { return }
        watchedFired = true
        onWatched?()
    }

    func stop() {
        savePosition(); stopped = true; detachObserver(); player?.pause(); player = nil
        ProgressStore.shared.flush()
    }
}

struct PlayerScreen: View {
    let animeTitle: String
    var anime: Anime? = nil
    let episodes: [EpisodeShort]
    @State private var current: EpisodeShort
    @StateObject private var vm = PlayerViewModel()
    @Environment(\.dismiss) private var dismiss

    init(episode: EpisodeShort, animeTitle: String, anime: Anime? = nil, episodes: [EpisodeShort] = []) {
        self.animeTitle = animeTitle
        self.anime = anime
        self.episodes = episodes
        _current = State(initialValue: episode)
    }

    private var index: Int? { episodes.firstIndex(where: { $0.id == current.id }) }
    private var prevEpisode: EpisodeShort? {
        guard let i = index, i > 0 else { return nil }
        return episodes[i - 1]
    }
    private var nextEpisode: EpisodeShort? {
        guard let i = index, i < episodes.count - 1 else { return nil }
        return episodes[i + 1]
    }

    private func go(_ ep: EpisodeShort?) {
        guard let ep = ep else { return }
        Haptics.tap()
        vm.stop()
        current = ep
    }

    private func pill(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text).font(.subheadline.weight(.medium)).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func arrow(_ name: String, _ ep: EpisodeShort?) -> some View {
        Button { go(ep) } label: {
            Image(systemName: name)
                .font(.headline)
                .frame(width: 42, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.pressable)
        .disabled(ep == nil)
        .opacity(ep == nil ? 0.35 : 1)
    }

    private var sourceNames: [String] {
        var out: [String] = []
        for v in vm.variants {
            let n = v.player.isEmpty ? "Другие" : v.player
            if !out.contains(n) { out.append(n) }
        }
        return out
    }

    private var controls: some View {
        VStack(spacing: 4) {
        HStack(spacing: 8) {
            arrow("chevron.left", prevEpisode)
            Menu {
                ForEach(sourceNames, id: \.self) { n in
                    Section(n) {
                        ForEach(vm.variants.filter { ($0.player.isEmpty ? "Другие" : $0.player) == n }) { v in
                            Button { vm.select(v) } label: {
                                if v.id == vm.current?.id { Label(v.title, systemImage: "checkmark") }
                                else { Text(v.title) }
                            }
                        }
                    }
                }
                if let v = vm.current, v.isWeb {
                    Divider()
                    if v.kodik && !vm.showWeb {
                        Button { vm.forceWeb() } label: { Label("Веб-плеер вместо прямого", systemImage: "globe") }
                    }
                    Link(destination: v.url) { Label("Открыть в Safari", systemImage: "safari") }
                }
            } label: {
                pill(vm.current?.title ?? (vm.isLoading ? "Загрузка…" : "Озвучка"))
            }
            .disabled(vm.variants.isEmpty)
            if vm.qualities.count > 1 {
                Menu {
                    ForEach(vm.qualities) { q in
                        Button { vm.pickQuality(q) } label: {
                            if q.id == vm.currentQuality { Label(q.title, systemImage: "checkmark") }
                            else { Text(q.title) }
                        }
                    }
                } label: {
                    pill(vm.qualities.first(where: { $0.id == vm.currentQuality })?.title ?? "Качество")
                        .frame(maxWidth: 110)
                }
            }
            arrow("chevron.right", nextEpisode)
        }
        if !vm.sourceNote.isEmpty {
            Text(vm.sourceNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    if vm.usesWeb, let v = vm.current {
                        WebPlayerView(url: v.url,
                                      onStream: v.kodik ? { vm.webStream($0) } : nil,
                                      onFullscreen: v.kodik ? { t, u in vm.webFullscreen(time: t, url: u) } : nil,
                                      interceptFS: v.kodik && Settings.bool("set.autoNative", true))
                    } else if let p = vm.player {
                        VideoPlayer(player: p)
                            .overlay(alignment: .topTrailing) {
                                Button { vm.openFullscreen() } label: {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 34, height: 34)
                                        .background(.ultraThinMaterial, in: Circle())
                                }
                                .padding(8)
                            }
                    } else if vm.isLoading || vm.isResolving {
                        ProgressView().tint(.white)
                    } else if let e = vm.error {
                        Text(e).foregroundStyle(.white).padding()
                    }
                }
                .overlay(alignment: .bottom) {
                    if let e = vm.playbackError {
                        Text(e)
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.black.opacity(0.75))
                            .textSelection(.enabled)
                    }
                }
                .aspectRatio(16/9, contentMode: .fit)

                controls

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !vm.debug.isEmpty {
                            Text(vm.debug)
                                .font(.system(size: 9, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        CommentsSection(postID: current.id, postType: "episode")
                            .id(current.id)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 20)
                }
            }
            .background(AppBackground())
            .navigationTitle(current.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { vm.stop(); dismiss() }
                }
            }
        }
        .task(id: current.id) {
            let ep = current
            vm.onWatched = { if let a = anime { HistoryStore.shared.record(anime: a, episode: ep) } }
            vm.onEnd = { go(nextEpisode) }
            await vm.load(episodeID: ep.id)
            // Веб-плеер не сообщает позицию: считаем просмотром 45 секунд на экране серии.
            if vm.player == nil, vm.error == nil, vm.current != nil {
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                if !Task.isCancelled, vm.player == nil { vm.onWatched?() }
            }
        }
        .fullScreenCover(isPresented: $vm.showNative, onDismiss: { vm.closeNative() }) {
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()
                FullscreenPlayer(player: vm.fsPlayer,
                                 onPiPStart: { vm.pipStarted() },
                                 onPiPStop: { vm.pipStopped() },
                                 onRestore: { vm.pipRestored() })
                    .ignoresSafeArea()
                if #unavailable(iOS 26) {
                    Button { vm.closeNative() } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(14)
                }
            }
        }
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

    /// Строка из числа или строки (номера глав приходят и так, и так).
    static func s(_ v: Any?) -> String? {
        if let x = v as? String { return x.isEmpty ? nil : x }
        if let i = v as? Int { return String(i) }
        if let d = v as? Double { return d == d.rounded() ? String(Int(d)) : String(d) }
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

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let outFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    static func date(_ s: String?) -> String {
        guard let s = s else { return "" }
        if let d = isoFrac.date(from: s) ?? isoPlain.date(from: s) { return outFmt.string(from: d) }
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
    let created: String
    let replyCount: Int
    let replies: [CommentItem]
    /// Номер страницы главы, к которой написан комментарий (если сайт его сообщает).
    let page: Int?

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
        created = J.str(d["created_at"]) ?? J.str(d["date"]) ?? ""
        page = J.int(d["post_page"]) ?? J.int(d["chapter_page"])
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

enum CommentSort: String, CaseIterable {
    case new = "Новые"
    case popular = "Популярные"
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
    @Published var sampleKeys = ""
    var postPage: Int?

    @Published var sort: CommentSort = .new
    let animeID: Int
    let slug: String
    private(set) var types: [String]
    var type: String { types.first ?? "anime" }
    private var page = 1
    private var finished = false

    init(animeID: Int, slug: String, postType: String? = nil, alternatives: [String] = []) {
        self.animeID = animeID
        self.slug = slug
        self.types = [postType ?? LibSite.current.postType] + alternatives
    }

    var sorted: [CommentItem] {
        switch sort {
        case .new:
            return items.sorted { $0.created == $1.created ? $0.id > $1.id : $0.created > $1.created }
        case .popular:
            return items.sorted { $0.up == $1.up ? $0.created > $1.created : $0.up > $1.up }
        }
    }

    func setSort(_ s: CommentSort) async {
        sort = s
        if s == .popular {
            var n = 0
            while !finished && n < 4 { await loadMore(); n += 1 }
        }
    }

    private func q(_ n: String, _ v: String) -> URLQueryItem { URLQueryItem(name: n, value: v) }

    private func firstPageQuery() -> [URLQueryItem] {
        [q("post_id", String(animeID)), q("post_type", type), q("page", "1")]
    }

    private func fetch(page: Int) async throws -> ([CommentItem], Bool?) {
        let attempts: [(String, [URLQueryItem])] = types.map {
            ("/comments", [q("post_id", String(animeID)), q("post_type", $0), q("page", String(page))])
        }
        var lastError: Error = APIError.badURL
        for (path, query) in attempts {
            do {
                let data = try await AnimelibAPI.shared.rawData(path, query: query, token: AuthStore.shared.token)
                guard let root = J.obj(data) else { continue }
                let list = CommentParser.parse(root)
                if sampleKeys.isEmpty {
                    var raw: [[String: Any]] = []
                    CommentParser.collect(root, into: &raw)
                    if let f = raw.first { sampleKeys = f.keys.sorted().joined(separator: ", ") }
                }
                let meta = (root as? [String: Any])?["meta"] as? [String: Any]
                if let used = query.first(where: { $0.name == "post_type" })?.value, types.count > 1 {
                    types = [used]
                }
                return (list, meta?["has_next_page"] as? Bool)
            } catch {
                lastError = error
            }
        }
        if types.count > 1 {
            throw NSError(domain: "comments", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Сайт не принял ни один тип комментариев (\(types.joined(separator: ", "))). Последняя ошибка: \(lastError.localizedDescription)"])
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

    func loadAll(max: Int = 10) async {
        var n = 0
        while !finished && n < max { await loadMore(); n += 1 }
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
        // сайт ждёт текст как документ (абзацы) и уровень вложенности
        let paragraphs: [[String: Any]] = text.components(separatedBy: "\n").map { line in
            line.isEmpty ? ["type": "paragraph"] : ["type": "paragraph", "content": [["type": "text", "text": line]]]
        }
        // формат точно как у сайта (по журналу запросов): документ, attachments, root_id, уровень 0
        let doc: [String: Any] = ["type": "doc", "content": paragraphs]
        func body(level: Int, root: Any, pp: Bool = true) -> [String: Any] {
            var b: [String: Any] = ["comment": doc, "attachments": [Any](), "post_type": type, "post_id": animeID,
                                    "parent_comment": parent ?? NSNull(), "root_id": root, "comment_level": level]
            if pp, let page = postPage { b["post_page"] = page }
            return b
        }
        var variants: [(String, [String: Any])] = []
        if parent == nil {
            variants.append(("A", body(level: 0, root: NSNull())))
            variants.append(("B", body(level: 0, root: NSNull(), pp: false)))
        } else {
            variants.append(("A", body(level: 1, root: parent!)))
            variants.append(("B", body(level: 1, root: NSNull())))
            variants.append(("C", body(level: 2, root: parent!)))
        }
        var errors: [String] = []
        for (name, b) in variants {
            do {
                _ = try await AnimelibAPI.shared.rawData("/comments", token: t, method: "POST", json: b)
                return nil
            } catch {
                errors.append("\(name): \(error.localizedDescription)")
            }
        }
        return errors.joined(separator: "\n")
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
            let query = [q("post_id", String(animeID)), q("post_type", type), q(key, String(c.id))]
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
                                if let e = await vm.like(c.id) { note = e } else { liked = true; note = nil; Haptics.tap() }
                            }
                        } label: {
                            Label("\(c.up + (liked ? 1 : 0))", systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.caption)
                                .foregroundStyle(liked ? Theme.accent : Color.secondary)
                        }
                        .buttonStyle(.pressable)
                        if c.down > 0 {
                            Label("\(c.down)", systemImage: "hand.thumbsdown").font(.caption)
                        }
                        if AuthStore.shared.token != nil {
                            Button { vm.replyTarget = c } label: {
                                Text("Ответить").font(.caption.bold()).foregroundStyle(Theme.accent)
                            }
                            .buttonStyle(.pressable)
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
                            .buttonStyle(.pressable)
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
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
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
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
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

struct CommentSortMenu: View {
    @ObservedObject var vm: CommentsViewModel

    var body: some View {
        Menu {
            Picker("Сортировка", selection: Binding(get: { vm.sort }, set: { s in Task { await vm.setSort(s) } })) {
                ForEach(CommentSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
        } label: {
            Label(vm.sort.rawValue, systemImage: "arrow.up.arrow.down")
                .font(.subheadline)
        }
    }
}

struct CommentsList: View {
    @ObservedObject var vm: CommentsViewModel
    var filter: ((CommentItem) -> Bool)? = nil

    var body: some View {
        LazyVStack(spacing: 10) {
            ForEach(filter.map { vm.sorted.filter($0) } ?? vm.sorted) { c in
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
    }
}

extension View {
    func commentSheets(_ vm: CommentsViewModel, showCompose: Binding<Bool>) -> some View {
        self
            .sheet(isPresented: showCompose) {
                ComposeSheet(title: "Новый комментарий",
                             send: { await vm.send($0, parent: nil) },
                             onSent: { Task { await vm.reload() } })
            }
            .sheet(item: Binding(get: { vm.replyTarget }, set: { vm.replyTarget = $0 })) { target in
                ComposeSheet(title: "Ответ для \(target.username)",
                             send: { await vm.send($0, parent: target.id) },
                             onSent: { Task { await vm.reload() } })
            }
    }
}

/// Комментарии к серии: встраиваются под плеером.
struct CommentsSection: View {
    @StateObject private var vm: CommentsViewModel
    @State private var showCompose = false

    init(postID: Int, postType: String) {
        _vm = StateObject(wrappedValue: CommentsViewModel(animeID: postID, slug: "", postType: postType,
                                                                alternatives: postType == "episode"
                                                                    ? ["episodes", "anime_episode", "animeEpisode", "anime-episode", "video", "chapter"] : []))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Комментарии").font(.headline)
                Spacer()
                CommentSortMenu(vm: vm)
                Button { showCompose = true } label: { Image(systemName: "square.and.pencil") }
                    .padding(.leading, 8)
            }
            CommentsList(vm: vm)
        }
        .padding(.top, 4)
        .commentSheets(vm, showCompose: $showCompose)
        .task { await vm.loadMore() }
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
                CommentsList(vm: vm).padding(14)
            }
            .background(AppBackground())
            .navigationTitle("Комментарии")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        CommentSortMenu(vm: vm)
                        Button { showCompose = true } label: { Image(systemName: "square.and.pencil") }
                    }
                }
            }
            .commentSheets(vm, showCompose: $showCompose)
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
    var cover: URL? = nil
}

@MainActor
final class AuthStore: ObservableObject {
    static let shared = AuthStore()
    @Published var token: String?
    @Published var user: ProfileUser?
    @Published var error: String?
    @Published var coverDebug = ""

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

    nonisolated static func coverURL(_ d: [String: Any]) -> URL? { deepCover(d, depth: 0) }

    /// Ищем баннер по любому ключу с «cover», «background» или «banner», в том числе во вложенных объектах.
    nonisolated private static func deepCover(_ d: [String: Any], depth: Int) -> URL? {
        let hints = ["cover", "background", "banner", "header", "bg"]
        for (k, v) in d where hints.contains(where: { k.lowercased().contains($0) }) {
            if let u = J.url(v) { return u }
        }
        if depth < 3 {
            for (_, v) in d {
                if let nested = v as? [String: Any], let u = deepCover(nested, depth: depth + 1) { return u }
            }
        }
        return nil
    }

    /// Баннер может прийти только в публичном профиле, поэтому спрашиваем его отдельно.
    private func loadCover(id: Int, token: String) async {
        var log: [String] = []
        let variants: [[String]] = [[], ["background"], ["cover"], ["banner"]]
        for fields in variants {
            let q = fields.map { URLQueryItem(name: "fields[]", value: $0) }
            let label = fields.first ?? "без полей"
            do {
                let data = try await AnimelibAPI.shared.rawData("/user/\(id)", query: q, token: token)
                guard let root = J.obj(data) as? [String: Any] else { log.append("\(label): не JSON"); continue }
                let d = (root["data"] as? [String: Any]) ?? root
                if let u = AuthStore.coverURL(d) { user?.cover = u; coverDebug = ""; return }
                log.append("\(label): ключи " + d.keys.sorted().joined(separator: ","))
            } catch APIError.http(let code, _) {
                log.append("\(label): HTTP \(code)")
            } catch {
                log.append("\(label): сбой")
            }
        }
        coverDebug = log.joined(separator: "\n")
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
                               premium: ((d["premium"] as? [String: Any])?["enabled"] as? Bool) ?? false,
                               cover: AuthStore.coverURL(d))
            error = nil
            if user?.cover == nil { await loadCover(id: id, token: t) }
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
            let nonEmpty = folders.filter { ($0.count ?? 1) > 0 }
            if !nonEmpty.isEmpty { folders = nonEmpty }
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
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.pressable)
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
        var bodies: [[String: Any]] = []
        // формат сайта (по журналу запросов)
        if let slug = anime.slugUrl {
            bodies.append(["media_type": LibSite.current.postType, "media_slug": slug, "bookmark": ["status": f.id], "meta": [String: Any]()])
        }
        bodies += [
            ["id": anime.id, "type": f.id, "model": LibSite.current.postType],
            ["bookmark": ["type": f.id], "id": anime.id, "model": LibSite.current.postType],
            ["type": f.id, "relation_id": anime.id, "relation_type": LibSite.current.postType]
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
        for q in [[URLQueryItem(name: "type", value: LibSite.current.postType)], []] {
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

// MARK: - Друзья
struct Friend: Identifiable, Hashable, Codable {
    let id: Int
    var username: String
    var avatar: URL?
    var cover: URL?
    var online: Bool?
    var lastSeen: Date?
    var level: Int?
    var streak: Int?
    var premium = false

    var statusText: String {
        if online == true { return "в сети" }
        if let d = lastSeen { return "был(а) " + Friend.relFmt.localizedString(for: d, relativeTo: Date()) }
        return ""
    }

    private static let relFmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.unitsStyle = .short
        return f
    }()

    /// Дополняем пустые поля данными из другой записи.
    mutating func merge(_ o: Friend) {
        if avatar == nil { avatar = o.avatar }
        if cover == nil { cover = o.cover }
        if online == nil { online = o.online }
        if lastSeen == nil { lastSeen = o.lastSeen }
        if level == nil { level = o.level }
        if streak == nil { streak = o.streak }
        premium = premium || o.premium
    }
}

enum FriendParser {
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(_ v: Any?) -> Date? {
        guard let s = v as? String, !s.isEmpty else { return nil }
        if let d = isoFrac.date(from: s) ?? isoPlain.date(from: s) { return d }
        return parseLibDate(s)
    }

    /// Запись о друге может быть самим пользователем или обёрткой с вложенным user.
    static func friend(_ d: [String: Any]) -> Friend? {
        var cands: [[String: Any]] = [d]
        for v in d.values { if let sub = v as? [String: Any] { cands.append(sub) } }
        for c in cands {
            guard let id = J.int(c["id"]), let name = J.str(c["username"]) ?? J.str(c["name"]) else { continue }
            var online = (c["is_online"] as? Bool) ?? (c["online"] as? Bool)
            var seen: Date?
            for k in ["last_online_at", "last_seen_at", "last_online", "last_activity_at", "last_seen"] {
                if let dt = date(c[k]) { seen = dt; break }
            }
            if online == nil, let sn = seen { online = Date().timeIntervalSince(sn) < 300 }
            let st = c["login_streak"] as? [String: Any]
            return Friend(id: id, username: name, avatar: J.url(c["avatar"]),
                          cover: AuthStore.coverURL(c), online: online, lastSeen: seen,
                          level: J.int(c["level"]) ?? J.int((c["user_level"] as? [String: Any])?["level"]),
                          streak: J.int(st?["login_streak"]) ?? J.int(c["login_streak"]),
                          premium: ((c["premium"] as? [String: Any])?["enabled"] as? Bool) ?? false)
        }
        return nil
    }

    static func detail(id: Int, token: String?) async -> Friend? {
        guard let data = try? await AnimelibAPI.shared.rawData("/user/\(id)", token: token),
              let root = J.obj(data) as? [String: Any] else { return nil }
        let d = (root["data"] as? [String: Any]) ?? root
        return friend(d)
    }

    /// Достаёт id из числа или ссылки вида …/user/123 или …/user/123-name.
    static func userID(from text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Int(t) { return n }
        guard let r = t.range(of: "/user/") else { return nil }
        let digits = t[r.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }
}

@MainActor
final class LocalFriends: ObservableObject {
    static let shared = LocalFriends()
    @Published private(set) var items: [Friend] = []
    private let key = "friends.local.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let v = try? JSONDecoder().decode([Friend].self, from: d) { items = v }
    }

    func contains(_ id: Int) -> Bool { items.contains { $0.id == id } }

    func toggle(_ f: Friend) {
        if let i = items.firstIndex(where: { $0.id == f.id }) { items.remove(at: i) } else { items.insert(f, at: 0) }
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: key) }
    }
}

@MainActor
final class FriendsViewModel: ObservableObject {
    @Published var friends: [Friend] = []
    @Published var isLoading = false
    @Published var loaded = false
    @Published var debug = ""
    private let cacheKey = "friends.cache.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: cacheKey),
           let v = try? JSONDecoder().decode([Friend].self, from: d) { friends = v }
    }

    private var syncReplaced = false
    private static let endpointKey = "friends.endpoint"

    func beginSync() { syncReplaced = false }

    /// Друзья, пойманные из запросов сайта. Адрес запроса запоминаем, чтобы дальше брать список напрямую.
    func absorb(_ list: [Friend], endpoint: String) {
        if !syncReplaced { friends = []; syncReplaced = true }
        for f in list {
            if let i = friends.firstIndex(where: { $0.id == f.id }) { friends[i].merge(f) } else { friends.append(f) }
        }
        UserDefaults.standard.set(endpoint, forKey: Self.endpointKey)
        debug = ""
        loaded = true
        if let d = try? JSONEncoder().encode(friends) { UserDefaults.standard.set(d, forKey: cacheKey) }
    }

    /// Превращает пойманный адрес вида https://api…/api/путь?параметры в путь и параметры для нашего клиента.
    private static func savedEndpoint() -> (String, [URLQueryItem])? {
        guard let e = UserDefaults.standard.string(forKey: endpointKey),
              let c = URLComponents(string: e),
              let r = c.path.range(of: "/api/") else { return nil }
        let path = "/" + c.path[r.upperBound...]
        let q = (c.queryItems ?? []).filter { $0.name != "page" }
        return (path, q)
    }

    /// Список с сайта плюс друзья, добавленные вручную, без повторов и в порядке «сначала в сети».
    static func merged(_ api: [Friend], _ local: [Friend]) -> [Friend] {
        var all = api
        for l in local where !all.contains(where: { $0.id == l.id }) { all.append(l) }
        return all.sorted { a, b in
            if (a.online == true) != (b.online == true) { return a.online == true }
            if let x = a.lastSeen, let y = b.lastSeen, x != y { return x > y }
            return a.username.localizedCaseInsensitiveCompare(b.username) == .orderedAscending
        }
    }

    func parseList(_ data: Data) -> [Friend]? {
        guard let root = J.obj(data) else { return nil }
        var arr: [[String: Any]]?
        if let o = root as? [String: Any] {
            arr = o["data"] as? [[String: Any]]
            if arr == nil, let inner = o["data"] as? [String: Any] {
                arr = (inner["items"] as? [[String: Any]]) ?? (inner["friends"] as? [[String: Any]])
                    ?? (inner["data"] as? [[String: Any]])
            }
            if arr == nil { arr = o["friends"] as? [[String: Any]] }
            if arr == nil { arr = o["items"] as? [[String: Any]] }
        } else if let a = root as? [[String: Any]] {
            arr = a
        }
        return arr?.compactMap { FriendParser.friend($0) }
    }

    func load(userID: Int, token: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; loaded = true }
        let uid = String(userID)
        let u = URLQueryItem(name: "user_id", value: uid)
        let p1 = URLQueryItem(name: "page", value: "1")
        var candidates: [(String, [URLQueryItem])] = [
            ("/user/friends", [p1]),
            ("/user/friends", [u]),
            ("/user/friends", [u, p1]),
            ("/user/friends", []),
            ("/user/\(uid)/friends", [p1]),
            ("/user/\(uid)/friends", []),
            ("/users/\(uid)/friends", []),
            ("/friends", [u]),
            ("/friends", []),
            ("/social/friends", [u]),
            ("/user/\(uid)/relations", []),
            ("/user/relations", [u]),
            ("/user/\(uid)/subscriptions", [])
        ]
        if let saved = Self.savedEndpoint() { candidates.insert(saved, at: 0) }
        var log: [String] = []
        var result: [Friend]?
        var usedPath: (String, [URLQueryItem])?
        for (path, q) in candidates {
            let tag = path + (q.isEmpty ? "" : "?" + q.map { $0.name }.joined(separator: "&"))
            do {
                let data = try await AnimelibAPI.shared.rawData(path, query: q, token: token)
                if let list = parseList(data) {
                    result = list
                    usedPath = (path, q)
                    break
                }
                log.append("\(tag): ответ без списка")
            } catch APIError.http(let code, let body) {
                let b = String("\(body)".replacingOccurrences(of: "\n", with: " ").prefix(70))
                log.append("\(tag): \(code) \(b)")
            } catch {
                log.append("\(tag): сбой")
            }
        }
        if let r = result {
            var all = r
            if let (path, q) = usedPath, !all.isEmpty {
                var page = 2
                while page <= 8 {
                    let base = q.filter { $0.name != "page" }
                    let qq = base + [URLQueryItem(name: "page", value: String(page))]
                    guard let data = try? await AnimelibAPI.shared.rawData(path, query: qq, token: token),
                          let more = parseList(data) else { break }
                    let known = Set(all.map { $0.id })
                    let fresh = more.filter { !known.contains($0.id) }
                    if fresh.isEmpty { break }
                    all += fresh
                    page += 1
                }
            }
            friends = all
            debug = ""
            await enrich(token: token)
            if let d = try? JSONEncoder().encode(friends) { UserDefaults.standard.set(d, forKey: cacheKey) }
        } else {
            debug = log.joined(separator: "\n")
        }
    }

    /// Если список не сообщил, кто в сети, спрашиваем профили по одному.
    func enrich(token: String) async {
        let need = friends.filter { $0.online == nil }.prefix(40).map { $0.id }
        var i = 0
        while i < need.count {
            let chunk = Array(need[i..<min(i + 4, need.count)])
            i += 4
            await withTaskGroup(of: Friend?.self) { group in
                for id in chunk { group.addTask { await FriendParser.detail(id: id, token: token) } }
                for await d in group {
                    guard let d, let idx = friends.firstIndex(where: { $0.id == d.id }) else { continue }
                    friends[idx].merge(d)
                }
            }
        }
    }
}

struct FriendsSniffWebView: UIViewRepresentable {
    let url: URL
    let onData: (String, String) -> Void

    static let script = """
    (function(){
      if (window.__hehe2) return; window.__hehe2 = true;
      function take(u, t){
        try {
          if (!/friend/i.test(String(u))) return;
          if (/request|invit|incoming|outgoing|sent/i.test(String(u))) return;
          window.webkit.messageHandlers.hfriends.postMessage({u: String(u), t: String(t).slice(0, 3000000)});
        } catch (e) {}
      }
      var of = window.fetch;
      if (of) window.fetch = function(a, o){
        var u = typeof a === 'string' ? a : (a && a.url);
        var p = of.apply(this, arguments);
        p.then(function(r){ try { r.clone().text().then(function(t){ take(u, t); }); } catch (e) {} }).catch(function(){});
        return p;
      };
      var oo = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(m, u){
        var x = this; x.__u = u;
        x.addEventListener('loadend', function(){
          try {
            var t = (x.responseType === '' || x.responseType === 'text') ? x.responseText : JSON.stringify(x.response);
            take(x.__u, t);
          } catch (e) {}
        });
        return oo.apply(this, arguments);
      };
      var tries = 0, clicked = false;
      var iv = setInterval(function(){
        tries++; if (tries > 30) { clearInterval(iv); return; }
        if (!clicked) {
          var el = document.querySelector('a[href*="friends"]');
          if (!el) {
            var all = document.querySelectorAll('a,button,li,[role=tab],span,div');
            for (var i = 0; i < all.length; i++) {
              var t = (all[i].children.length === 0 ? all[i].textContent : '').trim();
              if (t === 'Список друзей' || t === 'Друзья') { el = all[i]; break; }
            }
          }
          if (el) { el.click(); clicked = true; }
        } else {
          window.scrollTo(0, document.body.scrollHeight);
          var se = document.scrollingElement; if (se) se.scrollTop = se.scrollHeight;
        }
      }, 1000);
    })();
    """

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onData: (String, String) -> Void
        init(_ f: @escaping (String, String) -> Void) { onData = f }
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            guard let o = m.body as? [String: Any], let u = o["u"] as? String, let t = o["t"] as? String else { return }
            DispatchQueue.main.async { self.onData(u, t) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onData) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "hfriends")
        cfg.userContentController.addUserScript(
            WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.customUserAgent = Kodik.ua
        v.load(URLRequest(url: url))
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {}

    static func dismantleUIView(_ v: WKWebView, coordinator: Coordinator) {
        v.configuration.userContentController.removeScriptMessageHandler(forName: "hfriends")
    }
}

struct FriendsSyncView: View {
    let userID: Int
    @ObservedObject var vm: FriendsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var found = 0
    @State private var lastHit = Date()

    private var start: URL {
        let host: String
        switch LibSite.current.key {
        case "ranobe": host = "https://ranobelib.me"
        case "manga": host = "https://mangalib.me"
        case "hentai": host = "https://kz.hentailib.me"
        default: host = "https://animelib.org"
        }
        return URL(string: "\(host)/ru/user/\(userID)") ?? URL(string: host)!
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    if found == 0 { ProgressView() } else { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(found == 0 ? "Ищу список друзей на сайте…" : "Найдено друзей: \(found)")
                            .font(.subheadline.weight(.semibold))
                        Text(found == 0 ? "Если сайт попросит войти, войди. Если список сам не открылся, нажми на нём «Друзья»." : "Окно закроется само.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Theme.card)
                FriendsSniffWebView(url: start) { u, t in
                    guard let d = t.data(using: .utf8), let list = vm.parseList(d), !list.isEmpty else { return }
                    vm.absorb(list, endpoint: u)
                    found = vm.friends.count
                    lastHit = Date()
                }
            }
            .navigationTitle("Синхронизация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Готово") { dismiss() } }
            }
            .task {
                vm.beginSync()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if found > 0 && Date().timeIntervalSince(lastHit) > 5 { dismiss(); break }
                }
            }
        }
    }
}

struct StatusDot: View {
    let online: Bool?
    var size: CGFloat = 14

    var body: some View {
        if let o = online {
            Circle().fill(o ? Color.green : Color.gray.opacity(0.7))
                .frame(width: size, height: size)
                .overlay(Circle().stroke(Theme.base, lineWidth: 2.5))
        }
    }
}

struct FriendsView: View {
    let userID: Int
    @ObservedObject var vm: FriendsViewModel
    @ObservedObject private var auth = AuthStore.shared
    @ObservedObject private var local = LocalFriends.shared
    @State private var search = ""
    @State private var onlyOnline = false
    @State private var showAdd = false
    @State private var showSync = false
    @State private var manual = ""
    @State private var manualMsg = ""
    @State private var opened: Friend?
    @State private var pushOpened = false

    private var all: [Friend] { FriendsViewModel.merged(vm.friends, local.items) }
    private var onlineCount: Int { all.filter { $0.online == true }.count }

    private var shown: [Friend] {
        var list = all
        if onlyOnline { list = list.filter { $0.online == true } }
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? list : list.filter { $0.username.localizedCaseInsensitiveContains(q) }
    }

    private func statTile(_ icon: String, _ value: String, _ label: String, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.title3.bold())
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.chip))
    }

    private func pill(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.chip), in: Capsule())
        }
        .buttonStyle(.pressable)
    }

    private func row(_ f: Friend) -> some View {
        NavigationLink {
            FriendProfileView(friend: f)
        } label: {
            HStack(spacing: 14) {
                AnimatedRemoteImage(url: f.avatar, maxPixel: 200)
                    .frame(width: 54, height: 54)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(f.online == true ? Color.green.opacity(0.9) : Color.white.opacity(0.12), lineWidth: 2))
                    .overlay(alignment: .bottomTrailing) { StatusDot(online: f.online, size: 15).offset(x: 2, y: 2) }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(f.username).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if f.premium { Image(systemName: "crown.fill").font(.caption2).foregroundStyle(.yellow) }
                    }
                    if !f.statusText.isEmpty {
                        Text(f.statusText)
                            .font(.caption)
                            .foregroundStyle(f.online == true ? Color.green : Color.secondary)
                    }
                    HStack(spacing: 10) {
                        if let lv = f.level { Label("\(lv)", systemImage: "star.fill").foregroundStyle(.yellow) }
                        if let st = f.streak { Label("\(st)", systemImage: "flame.fill").foregroundStyle(.orange) }
                    }
                    .font(.caption2.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                LinearGradient(colors: [Theme.accent.opacity(f.online == true ? 0.20 : 0.08), Theme.card],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.chip))
        }
        .buttonStyle(.pressable)
    }

    private func openManual() async {
        guard let id = FriendParser.userID(from: manual) else {
            manualMsg = "Не понял. Вставь ссылку вида …/user/123 или просто число."
            return
        }
        manualMsg = "Ищу…"
        if let f = await FriendParser.detail(id: id, token: auth.token) {
            manualMsg = ""
            manual = ""
            showAdd = false
            try? await Task.sleep(nanoseconds: 400_000_000)
            opened = f
            pushOpened = true
        } else {
            manualMsg = "Пользователь не найден или профиль закрыт."
        }
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Добавить друга").font(.headline)
            Text("Вставь ссылку на профиль или номер пользователя. Профиль откроется, и его можно добавить в свой список.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                TextField("https://…/user/123", text: $manual)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 14))
                Button { Task { await openManual() } } label: {
                    Image(systemName: "arrow.right")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Theme.accent, in: Circle())
                }
                .buttonStyle(.pressable)
            }
            if !manualMsg.isEmpty { Text(manualMsg).font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(AppBackground())
        .presentationDetents([.height(270)])
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
                .frame(width: 76, height: 76)
                .background(Theme.accent.opacity(0.15), in: Circle())
            Text("Здесь пока никого").font(.headline)
            Text("Приложение может подтянуть список прямо с сайта, пока ты в нём вошёл. Или добавь друзей вручную по ссылке.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { showSync = true } label: {
                Label("Синхронизировать с сайтом", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.pressable)
            Button { showAdd = true } label: {
                Label("Добавить по ссылке", systemImage: "person.badge.plus")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.chip))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !all.isEmpty {
                    HStack(spacing: 10) {
                        statTile("person.2.fill", "\(all.count)", "друзей", Theme.accent)
                        statTile("dot.radiowaves.left.and.right", "\(onlineCount)", "в сети", .green)
                    }
                    HStack(spacing: 8) {
                        pill("Все", !onlyOnline) { onlyOnline = false }
                        pill("В сети", onlyOnline) { onlyOnline = true }
                        Spacer()
                    }
                    .padding(.top, 2)
                }
                if vm.isLoading && all.isEmpty { ProgressView().padding(.top, 30) }
                ForEach(shown) { row($0) }
                if vm.loaded && all.isEmpty && !vm.isLoading { emptyState.padding(.top, 8) }
                if !all.isEmpty && onlyOnline && shown.isEmpty {
                    Text("Сейчас никого нет в сети").font(.footnote).foregroundStyle(.secondary).padding(.top, 16)
                }

                if !vm.debug.isEmpty {
                    DisclosureGroup {
                        Text(vm.debug)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    } label: {
                        Text("Технические подробности").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 6)
                }
            }
            .padding(14)
        }
        .background(AppBackground())
        .navigationTitle("Друзья")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Поиск среди друзей")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    Button { showSync = true } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                    Button { showAdd = true } label: { Image(systemName: "person.badge.plus") }
                }
            }
        }
        .sheet(isPresented: $showAdd) { addSheet }
        .fullScreenCover(isPresented: $showSync, onDismiss: {
            if let t = auth.token { Task { await vm.enrich(token: t) } }
        }) { FriendsSyncView(userID: userID, vm: vm) }
        .refreshable { if let t = auth.token { await vm.load(userID: userID, token: t) } }
        .task {
            if !vm.loaded, let t = auth.token { await vm.load(userID: userID, token: t) }
        }
        .navigationDestination(isPresented: $pushOpened) {
            if let f = opened { FriendProfileView(friend: f) }
        }
    }
}

struct FriendProfileView: View {
    @State var friend: Friend
    @StateObject private var vm = ProfileViewModel()
    @ObservedObject private var auth = AuthStore.shared
    @ObservedObject private var local = LocalFriends.shared
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    private func folderIcon(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("любим") { return "heart.fill" }
        if n.contains("смотрю") || n.contains("читаю") { return "play.circle.fill" }
        if n.contains("план") { return "calendar" }
        if n.contains("просмотр") || n.contains("прочитан") { return "checkmark.circle.fill" }
        if n.contains("брош") { return "xmark.circle.fill" }
        if n.contains("отлож") { return "pause.circle.fill" }
        if n.contains("не нрав") { return "hand.thumbsdown.fill" }
        return "bookmark.fill"
    }

    private func stat(_ icon: String, _ tint: Color, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var header: some View {
        VStack(spacing: 0) {
            Group {
                if let c = friend.cover {
                    AnimatedRemoteImage(url: c, maxPixel: 900)
                } else {
                    LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.accent.opacity(0.15)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(height: 130)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, Theme.base.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 60)
            }

            AnimatedRemoteImage(url: friend.avatar, maxPixel: 360)
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.base, lineWidth: 4))
                .overlay(alignment: .topTrailing) { StatusDot(online: friend.online, size: 18).offset(x: 6, y: -6) }
                .padding(.top, -44)

            VStack(spacing: 10) {
                Text(friend.username).font(.title2.bold())
                if !friend.statusText.isEmpty {
                    Text(friend.statusText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(friend.online == true ? Color.green : Color.secondary)
                }
                if friend.premium {
                    Label("Premium", systemImage: "crown.fill").font(.caption.bold()).foregroundStyle(.yellow)
                }
                HStack(spacing: 8) {
                    if let st = friend.streak { stat("flame.fill", .orange, "Серия: \(st) дн.") }
                    if let lv = friend.level { stat("star.fill", .yellow, "Уровень \(lv)") }
                    if vm.totalTitles > 0 { stat("rectangle.stack.fill", Theme.accent, "\(vm.totalTitles) тайтлов") }
                }
                Button {
                    Haptics.tap()
                    local.toggle(friend)
                } label: {
                    Label(local.contains(friend.id) ? "В моём списке друзей" : "Добавить в свой список",
                          systemImage: local.contains(friend.id) ? "checkmark.circle.fill" : "person.badge.plus")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(local.contains(friend.id) ? AnyShapeStyle(Theme.chip) : AnyShapeStyle(Theme.accent), in: Capsule())
                        .foregroundStyle(local.contains(friend.id) ? Color.primary : Color.white)
                }
                .buttonStyle(.pressable)
            }
            .padding(.top, 10)
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.chip))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                if !vm.folders.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                        ForEach(vm.folders) { f in
                            Button { Task { await vm.select(f.id) } } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: folderIcon(f.name)).font(.subheadline)
                                        Spacer()
                                        Text(f.count.map(String.init) ?? "").font(.title3.bold())
                                    }
                                    Text(f.name).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(f.id == vm.selected ? Color.white : Color.primary)
                                .background(
                                    f.id == vm.selected
                                        ? AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.6)],
                                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                                        : AnyShapeStyle(Material.ultraThinMaterial),
                                    in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.chip))
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }

                if let e = vm.error {
                    Text("Списки недоступны: \(e)").font(.footnote).foregroundStyle(.orange)
                }
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(vm.items) { anime in
                        TitleLink(anime: anime) { AnimeCard(anime: anime) }
                            .buttonStyle(.pressable)
                            .onAppear {
                                if anime.id == vm.items.last?.id { Task { await vm.loadMore() } }
                            }
                    }
                }
                if vm.isLoading { ProgressView() }
                if vm.items.isEmpty && !vm.isLoading && vm.error == nil {
                    Text("В этом списке пока ничего нет или он скрыт").foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(14)
        }
        .background(AppBackground())
        .navigationTitle(friend.username)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let t = auth.token {
                if let d = await FriendParser.detail(id: friend.id, token: t) { friend.merge(d) }
                vm.configure(userID: friend.id, token: t)
                await vm.loadFolders()
            }
        }
    }
}

struct ProfileView: View {
    @ObservedObject private var auth = AuthStore.shared
    @ObservedObject private var localFriends = LocalFriends.shared
    @StateObject private var vm = ProfileViewModel()
    @StateObject private var friendsVM = FriendsViewModel()
    @State private var showLogin = false
    @State private var confirmSignOut = false
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    private func folderIcon(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("любим") { return "heart.fill" }
        if n.contains("смотрю") || n.contains("читаю") { return "play.circle.fill" }
        if n.contains("план") { return "calendar" }
        if n.contains("просмотр") || n.contains("прочитан") { return "checkmark.circle.fill" }
        if n.contains("брош") { return "xmark.circle.fill" }
        if n.contains("отлож") { return "pause.circle.fill" }
        if n.contains("не нрав") { return "hand.thumbsdown.fill" }
        return "bookmark.fill"
    }

    private func stat(_ icon: String, _ tint: Color, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glassCapsule()
    }

    private func folderTile(_ f: BookmarkFolder) -> some View {
        let on = f.id == vm.selected
        return Button { Haptics.select(); Task { await vm.select(f.id) } } label: {
            HStack(spacing: 10) {
                Image(systemName: folderIcon(f.name)).font(.system(size: 17, weight: .semibold)).frame(width: 24)
                Text(f.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(f.count.map(String.init) ?? "")
                    .font(.title3.bold().monospacedDigit())
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.card))
            }
        }
        .buttonStyle(.pressable)
    }

    private func friendsTile(userID: Int) -> some View {
        let list = FriendsViewModel.merged(friendsVM.friends, localFriends.items)
        let shownAv = Array(list.prefix(4))
        let online = list.filter { $0.online == true }.count
        return NavigationLink {
            FriendsView(userID: userID, vm: friendsVM)
        } label: {
            HStack(spacing: 14) {
                ZStack(alignment: .leading) {
                    if shownAv.isEmpty {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(Theme.accent)
                            .frame(width: 44, height: 44)
                            .background(Theme.accent.opacity(0.18), in: Circle())
                    }
                    ForEach(Array(shownAv.enumerated()), id: \.element.id) { i, f in
                        AnimatedRemoteImage(url: f.avatar, maxPixel: 120)
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Theme.base, lineWidth: 2.5))
                            .offset(x: CGFloat(i) * 26)
                    }
                }
                .frame(width: shownAv.isEmpty ? 44 : CGFloat(shownAv.count - 1) * 26 + 40, height: 44, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Друзья").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    if list.isEmpty {
                        Text("Профили и списки друзей").font(.caption).foregroundStyle(.secondary)
                    } else if online > 0 {
                        Text("\(list.count) · \(online) в сети").font(.caption).foregroundStyle(Color.green)
                    } else {
                        Text("\(list.count) друзей").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.pressable)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let u = auth.user {
                    VStack(spacing: 16) {
                        VStack(spacing: 0) {
                            Group {
                                if let c = u.cover {
                                    AnimatedRemoteImage(url: c, maxPixel: 900)
                                } else {
                                    LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.accent.opacity(0.15)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                }
                            }
                            .frame(height: 150)
                            .clipped()
                            .overlay(alignment: .bottom) {
                                LinearGradient(colors: [.clear, Theme.base.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                                    .frame(height: 70)
                            }

                            AnimatedRemoteImage(url: u.avatar, maxPixel: 360)
                                .frame(width: 92, height: 92)
                                .clipShape(RoundedRectangle(cornerRadius: 22))
                                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.base, lineWidth: 4))
                                .overlay(alignment: .topTrailing) {
                                    Circle().fill(Color.green)
                                        .frame(width: 18, height: 18)
                                        .overlay(Circle().stroke(Theme.base, lineWidth: 3))
                                        .offset(x: 6, y: -6)
                                }
                                .padding(.top, -46)

                            VStack(spacing: 10) {
                                Text(u.username).font(.title2.bold())
                                if u.premium {
                                    Label("Premium", systemImage: "crown.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(.yellow)
                                }
                                HStack(spacing: 8) {
                                    if let st = u.streak { stat("flame.fill", .orange, "Серия: \(st) дн.") }
                                    if let lv = u.level { stat("star.fill", .yellow, "Уровень \(lv)") }
                                    if vm.totalTitles > 0 { stat("rectangle.stack.fill", Theme.accent, "\(vm.totalTitles) тайтлов") }
                                }
                            }
                            .padding(.top, 10)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 16)
                        }
                        .frame(maxWidth: .infinity)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                        friendsTile(userID: u.id)

                        if u.cover == nil && !auth.coverDebug.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Баннер профиля не найден. Пришли этот текст разработчику:")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(auth.coverDebug)
                                    .font(.system(size: 9, design: .monospaced))
                                    .textSelection(.enabled)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !vm.folders.isEmpty {
                            let rows: [[BookmarkFolder]] = stride(from: 0, to: vm.folders.count, by: 2).map {
                                Array(vm.folders[$0..<min($0 + 2, vm.folders.count)])
                            }
                            VStack(spacing: 10) {
                                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                    HStack(spacing: 10) {
                                        ForEach(row) { folderTile($0) }
                                    }
                                }
                            }
                        }

                        if let e = vm.error {
                            Text(e).font(.footnote).foregroundStyle(.red)
                        }
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(vm.items) { anime in
                                TitleLink(anime: anime) { AnimeCard(anime: anime) }
                                    .buttonStyle(.pressable)
                                    .onAppear {
                                        if anime.id == vm.items.last?.id { Task { await vm.loadMore() } }
                                    }
                            }
                        }
                        if vm.isLoading { ProgressView() }
                        if vm.items.isEmpty && !vm.isLoading {
                            Text("В этом списке пока ничего нет").foregroundStyle(.secondary)
                            if !vm.debug.isEmpty && ((vm.folders.first { $0.id == vm.selected }?.count ?? 0) > 0) {
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
                        .buttonStyle(.pressable)
                    }
                    .padding(24)
                    .padding(.top, 40)
                }
            }
            .background(AppBackground())
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if auth.user != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { confirmSignOut = true } label: { Image(systemName: "rectangle.portrait.and.arrow.right") }
                    }
                }
            }
            .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { auth.signOut() }
                Button("Отмена", role: .cancel) {}
            }
            .navigationDestination(for: Anime.self) { DetailView(anime: $0) }
            .navigationDestination(for: Novel.self) { NovelDetailView(novel: $0) }
            .sheet(isPresented: $showLogin) { LoginSheet() }
            .task(id: auth.user?.id) {
                if let u = auth.user, let t = auth.token {
                    if !friendsVM.loaded { Task { await friendsVM.load(userID: u.id, token: t) } }
                    vm.configure(userID: u.id, token: t)
                    await vm.loadFolders()
                }
            }
        }
    }
}

// MARK: - Ранобэ: модели и сервис
struct Novel: Codable, Identifiable, Hashable {
    let anime: Anime
    var id: Int { anime.id }
    init(_ a: Anime) { anime = a }
    init(from decoder: Decoder) throws { anime = try Anime(from: decoder) }
    func encode(to encoder: Encoder) throws { try anime.encode(to: encoder) }
}

extension Anime {
    /// Ключ в хранилище прочитанного: у манги и ранобэ id тайтлов могут совпасть.
    var readKey: Int {
        let site = LibSite.current
        return site.isHentai ? -(id + 500_000_000) : (site.isManga ? -id : id)
    }
}

struct NovelChapter: Identifiable, Hashable {
    let id: Int
    let volume: String
    let number: String
    let name: String
    let date: Date?

    init(id: Int, volume: String, number: String, name: String, date: Date? = nil) {
        self.id = id; self.volume = volume; self.number = number; self.name = name; self.date = date
    }

    var saved: SavedChapter { SavedChapter(id: id, volume: volume, number: number, name: name, date: date) }

    init?(_ d: [String: Any]) {
        guard let cid = J.int(d["id"]) else { return nil }
        id = cid
        volume = J.s(d["volume"]) ?? "1"
        number = J.s(d["number"]) ?? "0"
        name = J.str(d["name"]) ?? ""
        // Дата выхода: самая ранняя загрузка среди переводов этой главы.
        var dates: [Date] = []
        for b in (d["branches"] as? [[String: Any]]) ?? [] {
            if let dt = FriendParser.date(b["created_at"]) { dates.append(dt) }
        }
        if dates.isEmpty, let dt = FriendParser.date(d["created_at"]) ?? FriendParser.date(d["date"]) { dates.append(dt) }
        date = dates.min()
    }

    var title: String { name.isEmpty ? "Глава \(number)" : "Глава \(number) · \(name)" }
}

enum ReaderBlock: Identifiable {
    case paragraph(Int, String)
    case heading(Int, String)
    case quote(Int, String)
    case image(Int, URL)
    case rule(Int)
    case rich(Int, AttributedString)

    var id: Int {
        switch self {
        case .paragraph(let i, _), .heading(let i, _), .quote(let i, _), .image(let i, _), .rich(let i, _): return i
        case .rule(let i): return i
        }
    }
}

/// Текст главы приходит как документ ProseMirror (или как HTML-строка).
enum ReaderParser {
    static func absolute(_ s: String?) -> URL? {
        guard var t = s, !t.isEmpty else { return nil }
        if t.hasPrefix("//") { t = "https:" + t }
        else if t.hasPrefix("/") { t = "https://ranobelib.me" + t }
        else if !t.hasPrefix("http") { t = "https://ranobelib.me/" + t }
        return URL(string: t)
    }

    static func parse(_ content: Any?, attachments: [[String: Any]]) -> [ReaderBlock] {
        var out: [ReaderBlock] = []
        var map: [String: URL] = [:]
        for a in attachments {
            guard let u = absolute(J.str(a["url"])) else { continue }
            for k in ["name", "filename", "id"] {
                if let key = J.s(a[k]) { map[key] = u }
            }
        }
        if let s = content as? String {
            out = parseHTML(s)
        } else if let d = content as? [String: Any] {
            walk(d, map: map, out: &out)
        }
        return out
    }

    private static func decode(_ s: String) -> String {
        var t = s
        let pairs = [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
                     ("&laquo;", "«"), ("&raquo;", "»"), ("&mdash;", "—"), ("&ndash;", "–"),
                     ("&hellip;", "…"), ("&amp;", "&")]
        for (a, b) in pairs { t = t.replacingOccurrences(of: a, with: b) }
        return t
    }

    /// Глава как HTML-строка: абзацы, заголовки, цитаты, <img>, курсив и жирный.
    static func parseHTML(_ html: String) -> [ReaderBlock] {
        var out: [ReaderBlock] = []
        if !html.contains("<") {
            for line in decode(html).components(separatedBy: "\n") {
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { out.append(.paragraph(out.count, t)) }
            }
            return out
        }
        var cur = AttributedString()
        var bold = 0, italic = 0, kind = 0
        func flush() {
            while let l = cur.characters.last, l.isWhitespace || l.isNewline { cur.characters.removeLast() }
            if !cur.characters.isEmpty {
                let plain = String(cur.characters)
                switch kind {
                case 1: out.append(.heading(out.count, plain))
                case 2: out.append(.quote(out.count, plain))
                default: out.append(.rich(out.count, cur))
                }
            }
            cur = AttributedString()
        }
        func addText(_ raw: String) {
            var t = decode(raw).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            if cur.characters.isEmpty { while t.hasPrefix(" ") { t.removeFirst() } }
            if t.isEmpty { return }
            var run = AttributedString(t)
            if bold > 0 && italic > 0 { run.inlinePresentationIntent = [.stronglyEmphasized, .emphasized] }
            else if bold > 0 { run.inlinePresentationIntent = .stronglyEmphasized }
            else if italic > 0 { run.inlinePresentationIntent = .emphasized }
            cur.append(run)
        }
        let ns = html as NSString
        guard let re = try? NSRegularExpression(pattern: "<[^>]*>"),
              let srcRe = try? NSRegularExpression(pattern: "(?:data-src|src)\\s*=\\s*[\"']([^\"']+)[\"']") else { return out }
        var pos = 0
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > pos {
                addText(ns.substring(with: NSRange(location: pos, length: m.range.location - pos)))
            }
            pos = m.range.location + m.range.length
            let tag = ns.substring(with: m.range)
            let low = tag.lowercased()
            let closing = low.hasPrefix("</")
            let name = String(low.dropFirst(closing ? 2 : 1).prefix { $0.isLetter || $0.isNumber })
            switch name {
            case "p", "div": flush()
            case "br": cur.append(AttributedString("\n"))
            case "h1", "h2", "h3", "h4", "h5", "h6": flush(); kind = closing ? 0 : 1
            case "blockquote": flush(); kind = closing ? 0 : 2
            case "strong", "b": bold = max(0, bold + (closing ? -1 : 1))
            case "em", "i": italic = max(0, italic + (closing ? -1 : 1))
            case "hr": flush(); out.append(.rule(out.count))
            case "img":
                flush()
                let r = NSRange(location: 0, length: (tag as NSString).length)
                if let sm = srcRe.firstMatch(in: tag, range: r) {
                    let src = (tag as NSString).substring(with: sm.range(at: 1))
                    if let u = absolute(decode(src)) { out.append(.image(out.count, u)) }
                }
            default: break
            }
        }
        if pos < ns.length { addText(ns.substring(from: pos)) }
        flush()
        return out
    }

    private static func inline(_ node: [String: Any]) -> String {
        let type = (node["type"] as? String) ?? ""
        if type == "text" { return (node["text"] as? String) ?? "" }
        if type == "hardBreak" { return "\n" }
        let ch = (node["content"] as? [[String: Any]]) ?? []
        return ch.map { inline($0) }.joined()
    }

    private static func walk(_ node: [String: Any], map: [String: URL], out: inout [ReaderBlock]) {
        let type = (node["type"] as? String) ?? ""
        let children = (node["content"] as? [[String: Any]]) ?? []
        switch type {
        case "paragraph":
            let t = inline(node).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(.paragraph(out.count, t)) }
        case "heading":
            let t = inline(node).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(.heading(out.count, t)) }
        case "blockquote":
            let t = children.map { inline($0) }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(.quote(out.count, t)) }
        case "listItem":
            let t = inline(node).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(.paragraph(out.count, "• " + t)) }
        case "horizontalRule":
            out.append(.rule(out.count))
        case "image":
            let attrs = node["attrs"] as? [String: Any]
            let imgs = (attrs?["images"] as? [[String: Any]]) ?? []
            for im in imgs {
                if let key = J.s(im["image"]), let u = map[key] { out.append(.image(out.count, u)) }
            }
            if imgs.isEmpty, let u = absolute(J.str(attrs?["src"])) { out.append(.image(out.count, u)) }
        default:
            for c in children { walk(c, map: map, out: &out) }
        }
    }
}

enum ChapterAge {
    private static let absFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    /// «сегодня», «вчера», «3 дн. назад», «2 нед. назад», «5 мес. назад», «год назад».
    static func ago(_ d: Date) -> String {
        let cal = Calendar.current
        let days = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 0)
        switch days {
        case 0: return "сегодня"
        case 1: return "вчера"
        case 2..<7: return "\(days) дн. назад"
        case 7..<30: return "\(days / 7) нед. назад"
        case 30..<365: return "\(max(1, days / 30)) мес. назад"
        default:
            let y = days / 365
            return y == 1 ? "год назад" : "\(y) г. назад"
        }
    }

    static func full(_ d: Date) -> String { absFmt.string(from: d) }
}

enum NovelService {
    static func chapters(slug: String) async throws -> [NovelChapter] {
        let data = try await AnimelibAPI.shared.rawData("/manga/\(slug)/chapters")
        guard let root = J.obj(data) as? [String: Any],
              let arr = root["data"] as? [[String: Any]] else { throw APIError.badURL }
        return arr.compactMap { NovelChapter($0) }
    }

    static func chapterPath(slug: String) -> String { "/manga/\(slug)/chapter" }

    static func chapterQuery(_ c: NovelChapter) -> [URLQueryItem] {
        [URLQueryItem(name: "number", value: c.number), URLQueryItem(name: "volume", value: c.volume)]
    }

    static func content(slug: String, chapter c: NovelChapter) async throws -> [ReaderBlock] {
        let data = try await AnimelibAPI.shared.rawData(chapterPath(slug: slug), query: chapterQuery(c))
        guard let root = J.obj(data) as? [String: Any],
              let d = root["data"] as? [String: Any] else { throw APIError.badURL }
        let att = (d["attachments"] as? [[String: Any]]) ?? []
        return ReaderParser.parse(d["content"], attachments: att)
    }
}

// MARK: - Ранобэ: что уже прочитано
/// Отправка прочитанных глав на сайт (как делает сайт: POST .../chapters/{id}/view). Только для вошедших в аккаунт.
enum SiteSync {
    private static var sent = Set<String>()

    static func view(novelID: Int, chapterID: Int) {
        guard let token = Keychain.get("lib.token"), !token.isEmpty else { return }
        let site = LibSite.current
        guard site.isBook else { return }
        let key = "\(site.key):\(novelID):\(chapterID)"
        guard sent.insert(key).inserted else { return }
        let path = "\(site.apiPath)/\(novelID)/chapters/\(chapterID)/view"
        Task.detached(priority: .utility) {
            do {
                _ = try await AnimelibAPI.shared.rawData(path, token: token, method: "POST", json: [:])
            } catch {
                await MainActor.run { _ = SiteSync.sent.remove(key) }
            }
        }
    }
}

@MainActor
final class ReadStore: ObservableObject {
    static let shared = ReadStore()
    @Published private(set) var read: [String: Set<Int>] = [:]
    @Published private(set) var last: [String: Int] = [:]

    init() {
        if let d = UserDefaults.standard.data(forKey: "read.v1"),
           let v = try? JSONDecoder().decode([String: Set<Int>].self, from: d) { read = v }
        if let d = UserDefaults.standard.data(forKey: "readlast.v1"),
           let v = try? JSONDecoder().decode([String: Int].self, from: d) { last = v }
    }

    func isRead(_ novel: Int, _ chapter: Int) -> Bool { read[String(novel)]?.contains(chapter) ?? false }
    func lastChapter(_ novel: Int) -> Int? { last[String(novel)] }

    func mark(_ novel: Int, _ chapter: Int) {
        var list = read[String(novel)] ?? []
        if list.insert(chapter).inserted {
            ActivityStore.shared.addChapter(manga: novel < 0)
        }
        read[String(novel)] = list
        last[String(novel)] = chapter
        if let d = try? JSONEncoder().encode(read) { UserDefaults.standard.set(d, forKey: "read.v1") }
        if let d = try? JSONEncoder().encode(last) { UserDefaults.standard.set(d, forKey: "readlast.v1") }
    }

    func clear() {
        read = [:]; last = [:]
        UserDefaults.standard.removeObject(forKey: "read.v1")
        UserDefaults.standard.removeObject(forKey: "readlast.v1")
    }
}

/// Где остановился читатель: глава и место внутри неё (страница манги или смещение в тексте ранобэ).
struct ReadPos: Codable {
    var c: Int      // id главы
    var p: Int      // манга: страница с нуля; ранобэ (страницы): смещение в тексте
    var b: Int      // ранобэ (прокрутка): номер блока
    var pct: Int    // прочитано в главе, %
    var t: Int      // когда, секунды
}

@MainActor
final class ReadPosStore {
    static let shared = ReadPosStore()
    private var items: [String: ReadPos] = [:]
    private let key = "readpos.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let v = try? JSONDecoder().decode([String: ReadPos].self, from: d) { items = v }
    }

    func get(_ k: Int) -> ReadPos? { items[String(k)] }

    private var saveTask: Task<Void, Never>?

    func set(_ k: Int, _ pos: ReadPos) {
        items[String(k)] = pos
        if items.count > 300 {
            let keep = items.sorted { $0.value.t > $1.value.t }.prefix(250)
            items = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        // на диск не чаще раза в секунду: при прокрутке позиция меняется десятки раз
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if let d = try? JSONEncoder().encode(self.items) { UserDefaults.standard.set(d, forKey: self.key) }
        }
    }

    func clear() {
        items = [:]
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Ссылка на тайтл: для аниме ведёт на экран аниме, для ранобэ на экран ранобэ.
struct TitleLink<Content: View>: View {
    let anime: Anime
    let label: () -> Content

    init(anime: Anime, @ViewBuilder label: @escaping () -> Content) {
        self.anime = anime
        self.label = label
    }

    var body: some View {
        Group {
            if LibSite.current.isBook {
                NavigationLink(value: Novel(anime)) { label() }
            } else {
                NavigationLink(value: anime) { label() }
            }
        }
        .contextMenu {
            let store = FavoritesStore.current
            Button { store.toggle(anime) } label: {
                SwiftUI.Label(store.contains(anime) ? "Убрать из избранного" : "В избранное",
                      systemImage: store.contains(anime) ? "heart.slash" : "heart")
            }
            if let u = titleURL(anime) {
                ShareLink(item: u) { SwiftUI.Label("Поделиться", systemImage: "square.and.arrow.up") }
            }
        }
    }
}

struct FitImage: View {
    let url: URL
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().transition(.opacity)
            } else if failed {
                Label("Иллюстрация не загрузилась", systemImage: "photo")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        if url.isFileURL {
            let key = ImageCache.key(url, 1600)
            if let c = ImageCache.shared.object(forKey: key) { image = c; return }
            let img = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let d = try? Data(contentsOf: url) else { return nil }
                return ImageLoader.downsample(d, maxPixel: 1600)
            }.value
            if let img { ImageCache.store(img, key); image = img } else { failed = true }
            return
        }
        let key = ImageCache.key(url, 1600)
        if let c = ImageCache.shared.object(forKey: key) { image = c; return }
        if let img = await ImageLoader.shared.image(url, referer: LibSite.ranobe.referer, maxPixel: 1600) {
            ImageCache.store(img, key)
            withAnimation(.easeOut(duration: 0.25)) { image = img }
        } else if !Task.isCancelled {
            failed = true
        }
    }
}


// MARK: - Ранобэ: офлайн-хранилище
struct SavedChapter: Codable {
    let id: Int
    let volume: String
    let number: String
    let name: String
    var date: Date? = nil
}

struct OfflineEntry: Codable {
    var novel: Anime
    var chapters: [SavedChapter]
    var files: [Int: Int]
    var updated: Date
}

func fmtBytes(_ n: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
}

/// Скачанные главы лежат в Application Support/Offline/<id тайтла>/:
/// <id главы>.json (ответ сайта как есть) и картинки <id главы>_<хэш>.img.
@MainActor
final class OfflineStore: ObservableObject {
    static let shared = OfflineStore()
    static let manga = OfflineStore(folder: "OfflineManga")
    static var current: OfflineStore { LibSite.current.isManga ? manga : shared }
    @Published private(set) var entries: [Int: OfflineEntry] = [:]
    nonisolated let root: URL

    init(folder: String = "Offline") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var dir = base.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        try? dir.setResourceValues(rv)
        root = dir
        if let d = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
           let v = try? JSONDecoder().decode([Int: OfflineEntry].self, from: d) { entries = v }
    }

    nonisolated func folder(_ novel: Int) -> URL { root.appendingPathComponent(String(novel), isDirectory: true) }
    nonisolated func chapterFile(_ novel: Int, _ chapter: Int) -> URL { folder(novel).appendingPathComponent("\(chapter).json") }
    nonisolated func mangaPageFile(_ novel: Int, _ chapter: Int, _ index: Int) -> URL {
        folder(novel).appendingPathComponent("\(chapter)_\(index).img")
    }
    nonisolated func coverFile(_ novel: Int) -> URL { folder(novel).appendingPathComponent("cover.img") }
    nonisolated func imageFile(novel: Int, chapter: Int, url: URL) -> URL {
        var h: UInt64 = 5381
        for b in url.absoluteString.utf8 { h = (h &* 33) &+ UInt64(b) }
        return folder(novel).appendingPathComponent("\(chapter)_\(String(h, radix: 36)).img")
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(entries) {
            try? d.write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
        }
    }

    static var usedBytes: Int { shared.totalBytes + manga.totalBytes }
    static var limitBytes: Int { UserDefaults.standard.integer(forKey: "off.limitGB") * 1_000_000_000 }
    static var purgeMode: Bool { UserDefaults.standard.string(forKey: "off.overflow") == "purge" }

    var avgChapterBytes: Int? {
        let n = entries.values.reduce(0) { $0 + $1.files.count }
        return n > 0 ? totalBytes / n : nil
    }

    var allEntries: [OfflineEntry] { entries.values.sorted { $0.updated > $1.updated } }
    var totalBytes: Int { entries.values.reduce(0) { $0 + $1.files.values.reduce(0, +) } }
    func isDownloaded(_ novel: Int, _ chapter: Int) -> Bool { entries[novel]?.files[chapter] != nil }
    func downloadedCount(_ novel: Int) -> Int { entries[novel]?.files.count ?? 0 }

    func coverURL(_ novel: Int) -> URL? {
        let f = coverFile(novel)
        return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }

    /// Список глав, сохранённый вместе с тайтлом, только скачанные.
    func savedChapters(_ novel: Int) -> [NovelChapter] {
        guard let e = entries[novel] else { return [] }
        return e.chapters
            .filter { e.files[$0.id] != nil }
            .map { NovelChapter(id: $0.id, volume: $0.volume, number: $0.number, name: $0.name, date: $0.date) }
    }

    /// Обновляем сохранённый список глав, пока есть сеть (чтобы офлайн было что показать).
    func refresh(novel: Anime, chapters: [NovelChapter]) {
        guard var e = entries[novel.id] else { return }
        e.novel = novel
        e.chapters = chapters.map { $0.saved }
        entries[novel.id] = e
        persist()
    }

    func record(novel: Anime, chapters: [NovelChapter], chapter: NovelChapter, raw: Data, extraBytes: Int) {
        try? FileManager.default.createDirectory(at: folder(novel.id), withIntermediateDirectories: true)
        try? raw.write(to: chapterFile(novel.id, chapter.id), options: .atomic)
        var e = entries[novel.id] ?? OfflineEntry(novel: novel, chapters: [], files: [:], updated: Date())
        e.novel = novel
        if !chapters.isEmpty { e.chapters = chapters.map { $0.saved } }
        e.files[chapter.id] = raw.count + extraBytes
        e.updated = Date()
        entries[novel.id] = e
        persist()
    }

    func remove(novel: Int, chapter: Int) {
        guard var e = entries[novel] else { return }
        try? FileManager.default.removeItem(at: chapterFile(novel, chapter))
        let prefix = "\(chapter)_"
        if let names = try? FileManager.default.contentsOfDirectory(atPath: folder(novel).path) {
            for n in names where n.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: folder(novel).appendingPathComponent(n))
            }
        }
        e.files[chapter] = nil
        if e.files.isEmpty {
            remove(novel: novel)
        } else {
            entries[novel] = e
            persist()
        }
    }

    func remove(novel: Int) {
        try? FileManager.default.removeItem(at: folder(novel))
        entries[novel] = nil
        persist()
    }

    func removeAll() {
        for id in Array(entries.keys) { try? FileManager.default.removeItem(at: folder(id)) }
        entries = [:]
        persist()
    }

    /// Глава с телефона: картинки подменяются локальными файлами.
    func blocks(novel: Int, chapter: Int) -> [ReaderBlock]? {
        guard isDownloaded(novel, chapter),
              let data = try? Data(contentsOf: chapterFile(novel, chapter)),
              let root = J.obj(data) as? [String: Any],
              let d = root["data"] as? [String: Any] else { return nil }
        let att = (d["attachments"] as? [[String: Any]]) ?? []
        let parsed = ReaderParser.parse(d["content"], attachments: att)
        if parsed.isEmpty { return nil }
        return parsed.map { (b: ReaderBlock) -> ReaderBlock in
            if case .image(let i, let u) = b {
                let f = imageFile(novel: novel, chapter: chapter, url: u)
                if FileManager.default.fileExists(atPath: f.path) { return .image(i, f) }
            }
            return b
        }
    }
}

// MARK: - Ранобэ: очередь загрузок
final class BackgroundBox {
    var id = UIBackgroundTaskIdentifier.invalid
}

@MainActor
final class DownloadProgress: ObservableObject {
    @Published var status = ""
}

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    struct Job {
        let novel: Anime
        let chapters: [NovelChapter]
        let chapter: NovelChapter
        let store: OfflineStore
    }

    @Published private(set) var pending: Set<Int> = []
    @Published private(set) var active: Set<Int> = []
    @Published private(set) var failed: [Int: String] = [:]
    @Published private(set) var total = 0
    @Published private(set) var done = 0
    /// Текст состояния живёт в отдельном объекте: его частые обновления не должны перерисовывать список глав.
    let progress = DownloadProgress()
    var status: String {
        get { progress.status }
        set { progress.status = newValue }
    }
    @Published var notice: String?

    private var jobs: [Job] = []
    private var worker: Task<Void, Never>?
    private let monitor = NWPathMonitor()
    private var expensive = false

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let exp = path.isExpensive
            Task { @MainActor in self?.expensive = exp }
        }
        monitor.start(queue: DispatchQueue(label: "hehe.netmonitor"))
    }

    /// Удаляет самые давние прочитанные главы, пока занято не больше target. Возвращает, получилось ли.
    private func purgeRead(target: Int) -> Bool {
        var list: [(OfflineStore, Int, Int, Date)] = []
        for st in [OfflineStore.shared, OfflineStore.manga] {
            for e in st.entries.values {
                let key = st === OfflineStore.manga ? -e.novel.id : e.novel.id
                for cid in e.files.keys where ReadStore.shared.isRead(key, cid) {
                    list.append((st, e.novel.id, cid, e.updated))
                }
            }
        }
        list.sort { $0.3 < $1.3 }
        for (st, nid, cid, _) in list {
            if OfflineStore.usedBytes <= target { break }
            st.remove(novel: nid, chapter: cid)
        }
        return OfflineStore.usedBytes <= target
    }

    func enqueue(novel: Anime, all: [NovelChapter], targets: [NovelChapter]) {
        notice = nil
        let store = OfflineStore.current
        // Всё накапливаем и публикуем один раз: иначе экран перерисовывается на каждую главу из сотни.
        var newPending = pending
        var newFailed = failed
        var added = 0
        for c in targets where !store.isDownloaded(novel.id, c.id) && !newPending.contains(c.id) {
            jobs.append(Job(novel: novel, chapters: all, chapter: c, store: store))
            newPending.insert(c.id)
            newFailed[c.id] = nil
            added += 1
        }
        if added > 0 {
            pending = newPending
            failed = newFailed
            total += added
        }
        startIfNeeded()
    }

    func cancel(chapter id: Int) {
        guard let i = jobs.firstIndex(where: { $0.chapter.id == id }) else { return }
        jobs.remove(at: i)
        pending.remove(id)
        total = max(0, total - 1)
    }

    func cancelAll() {
        jobs.removeAll()
        pending = []
        worker?.cancel()
        worker = nil
        active = []
        total = 0; done = 0; status = ""
    }

    private func startIfNeeded() {
        guard worker == nil, !jobs.isEmpty else { return }
        worker = Task { [weak self] in await self?.run() }
    }

    private func run() async {
        let box = BackgroundBox()
        box.id = UIApplication.shared.beginBackgroundTask(withName: "hehe.download") {
            let id = box.id
            box.id = .invalid
            if id != .invalid { UIApplication.shared.endBackgroundTask(id) }
        }
        // Несколько глав качаются одновременно: на мобильной сети две, на Wi‑Fi три.
        // Манга: главы по одной, иначе сервер картинок рвёт десятки одновременных соединений и всё встаёт.
        let lanes = (jobs.first?.store === OfflineStore.manga) ? 1 : (expensive ? 2 : 3)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<lanes { group.addTask { await self.lane() } }
        }
        if box.id != .invalid { UIApplication.shared.endBackgroundTask(box.id); box.id = .invalid }
        if Task.isCancelled { return }
        if done >= 3 { Haptics.success() }
        active = []
        status = ""
        total = 0
        done = 0
        worker = nil
    }

    /// Одна «полоса» загрузки: берёт следующую главу из очереди, пока очередь не опустеет.
    private func lane() async {
        while !Task.isCancelled, !jobs.isEmpty {
            let job = jobs.removeFirst()
            let limit = OfflineStore.limitBytes
            if limit > 0 && OfflineStore.usedBytes >= limit {
                var ok = false
                if OfflineStore.purgeMode { ok = purgeRead(target: Int(Double(limit) * 0.9)) }
                if !ok {
                    notice = "Достигнут лимит места (\(fmtBytes(limit))). Скачивание остановлено."
                    jobs.removeAll()
                    pending = []
                    return
                }
            }
            if Settings.bool("off.wifi", false) {
                while expensive && !Task.isCancelled {
                    status = "Ждём Wi‑Fi…"
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }
            if Task.isCancelled { return }
            active.insert(job.chapter.id)
            status = job.chapter.title
            do {
                try await download(job)
            } catch {
                if Task.isCancelled { return }
                failed[job.chapter.id] = error.localizedDescription
            }
            active.remove(job.chapter.id)
            if Task.isCancelled { return }
            done += 1
            pending.remove(job.chapter.id)
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
    }

    /// Качает элементы с «скользящим окном»: как только одна загрузка закончилась, стартует следующая.
    nonisolated static func pool<T>(_ items: [T], width: Int, _ work: @escaping (T) async -> Int) async -> [Int] {
        await withTaskGroup(of: Int.self) { group -> [Int] in
            var out: [Int] = []
            var it = items.makeIterator()
            for _ in 0..<min(width, items.count) {
                if let x = it.next() { group.addTask { await work(x) } }
            }
            while let n = await group.next() {
                out.append(n)
                if Task.isCancelled { group.cancelAll(); continue }
                if let x = it.next() { group.addTask { await work(x) } }
            }
            return out
        }
    }

    nonisolated static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpMaximumConnectionsPerHost = 12
        c.timeoutIntervalForRequest = 30
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        return URLSession(configuration: c)
    }()

    private func download(_ job: Job) async throws {
        guard let slug = job.novel.slugUrl else { throw APIError.badURL }
        let c = job.chapter
        var raw: Data?
        var lastError: Error = APIError.badURL
        for attempt in 0..<3 {
            do {
                raw = try await AnimelibAPI.shared.rawData(NovelService.chapterPath(slug: slug),
                                                           query: NovelService.chapterQuery(c))
                break
            } catch APIError.http(let code, let body) where code == 429 || code >= 500 {
                lastError = APIError.http(code, body)
                try await Task.sleep(nanoseconds: UInt64(3_000_000_000 * (attempt + 1)))
            }
        }
        guard let raw, let root = J.obj(raw) as? [String: Any],
              let d = root["data"] as? [String: Any] else { throw lastError }
        if job.store === OfflineStore.manga {
            try await downloadManga(job, raw: raw, data: d)
            return
        }
        let att = (d["attachments"] as? [[String: Any]]) ?? []
        let blocks = ReaderParser.parse(d["content"], attachments: att)
        if blocks.isEmpty {
            throw NSError(domain: "offline", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Текст главы пуст или недоступен"])
        }
        var urls: [URL] = []
        for b in blocks {
            if case .image(_, let u) = b, !urls.contains(u) { urls.append(u) }
        }
        let store = job.store
        let nid = job.novel.id
        try? FileManager.default.createDirectory(at: store.folder(nid), withIntermediateDirectories: true)
        let targets: [(URL, URL)] = urls.map { ($0, store.imageFile(novel: nid, chapter: c.id, url: $0)) }
        let imageBytes = await DownloadManager.pool(targets, width: 6) { t in
            await DownloadManager.fetchImage(t.0, to: t.1)
        }.reduce(0, +)
        if Task.isCancelled { throw CancellationError() }
        if let cover = job.novel.imageURL, store.coverURL(nid) == nil {
            _ = await DownloadManager.fetchImage(cover, to: store.coverFile(nid))
        }
        store.record(novel: job.novel, chapters: job.chapters, chapter: c, raw: raw, extraBytes: imageBytes)
    }

    /// Манга: все страницы главы кладём в файлы 〈глава〉_〈номер〉.img. Глава сохраняется, только если скачались все.
    private func downloadManga(_ job: Job, raw: Data, data d: [String: Any]) async throws {
        let c = job.chapter
        let bases = await MangaImageServers.shared.bases()
        let pages = MangaService.parse(d, bases: bases)
        if pages.isEmpty {
            throw NSError(domain: "offline", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "У главы нет страниц или она недоступна"])
        }
        let store = job.store
        let nid = job.novel.id
        try? FileManager.default.createDirectory(at: store.folder(nid), withIntermediateDirectories: true)
        var bytes = 0
        var failedPages = 0
        let targets: [([URL], URL)] = pages.map { ($0.urls, store.mangaPageFile(nid, c.id, $0.id)) }
        let titleText = c.title
        let totalPages = targets.count
        let counter = PageCounter()
        status = "\(titleText) · 0/\(totalPages)"
        let sizes = await DownloadManager.pool(targets, width: expensive ? 4 : 6) { t in
            let n = await DownloadManager.fetchMangaPage(t.0, to: t.1)
            let k = await counter.bump()
            await MainActor.run { DownloadManager.shared.status = "\(titleText) · \(k)/\(totalPages)" }
            return n
        }
        if Task.isCancelled { throw CancellationError() }
        for n in sizes { if n == 0 { failedPages += 1 } else { bytes += n } }
        if failedPages > 0 {
            throw NSError(domain: "offline", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Не скачалось страниц: \(failedPages). Попробуй ещё раз"])
        }
        if let cover = job.novel.imageURL, store.coverURL(nid) == nil {
            _ = await DownloadManager.fetchImage(cover, to: store.coverFile(nid))
        }
        store.record(novel: job.novel, chapters: job.chapters, chapter: c, raw: raw, extraBytes: bytes)
    }

    actor PageCounter {
        private var n = 0
        func bump() -> Int { n += 1; return n }
    }

    nonisolated static func fetchMangaPage(_ urls: [URL], to file: URL) async -> Int {
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 { return size }
        let agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        for round in 0..<2 {
            for u in urls {
                var req = URLRequest(url: u)
                req.timeoutInterval = 20
                req.setValue(LibSite.current.isManga ? LibSite.current.referer : LibSite.manga.referer, forHTTPHeaderField: "Referer")
                req.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
                req.setValue(agent, forHTTPHeaderField: "User-Agent")
                if let (data, resp) = try? await DownloadManager.session.data(for: req),
                   let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code),
                   !data.isEmpty,
                   let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) > 0 {
                    try? data.write(to: file, options: .atomic)
                    return data.count
                }
            }
            if round == 0 { try? await Task.sleep(nanoseconds: 700_000_000) }
        }
        return 0
    }

    nonisolated static func fetchImage(_ url: URL, to file: URL) async -> Int {
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 { return size }
        for attempt in 0..<3 {
            var req = URLRequest(url: url)
            req.timeoutInterval = 30
            req.setValue("https://ranobelib.me/", forHTTPHeaderField: "Referer")
            if let (data, resp) = try? await DownloadManager.session.data(for: req),
               (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
               !data.isEmpty, UIImage(data: data) != nil {
                try? data.write(to: file, options: .atomic)
                return data.count
            }
            try? await Task.sleep(nanoseconds: UInt64(600_000_000 * (attempt + 1)))
        }
        return 0
    }
}

struct ChapterDownloadButton: View {
    let novel: Anime
    let chapters: [NovelChapter]
    let chapter: NovelChapter
    @ObservedObject private var store = OfflineStore.current
    @ObservedObject private var dl = DownloadManager.shared

    var body: some View {
        let saved = store.isDownloaded(novel.id, chapter.id)
        let queued = dl.pending.contains(chapter.id)
        Button {
            if queued { dl.cancel(chapter: chapter.id) }
            else if !saved { dl.enqueue(novel: novel, all: chapters, targets: [chapter]) }
        } label: {
            Group {
                if saved {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.green)
                } else if queued {
                    if dl.active.contains(chapter.id) { ProgressView() }
                    else { Image(systemName: "clock").foregroundStyle(.secondary) }
                } else if dl.failed[chapter.id] != nil {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Color.orange)
                } else {
                    Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
                }
            }
            .font(.title3)
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.pressable)
    }
}

struct OfflineLibraryView: View {
    @ObservedObject private var store = OfflineStore.current
    @State private var confirmAll = false

    var body: some View {
        List {
            if store.allEntries.isEmpty {
                Text("Пока ничего не скачано. Откройте тайтл и нажмите «Скачать» над списком глав.")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(store.allEntries, id: \.novel.id) { e in
                NavigationLink(value: Novel(e.novel)) {
                    HStack(spacing: 12) {
                        RemoteImage(url: store.coverURL(e.novel.id) ?? e.novel.imageURL)
                            .frame(width: 50, height: 74)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.novel.displayTitle)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            Text("\(e.files.count) гл. · \(fmtBytes(e.files.values.reduce(0, +)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .swipeActions {
                    Button(role: .destructive) { store.remove(novel: e.novel.id) } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Скачанное")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Novel.self) { NovelDetailView(novel: $0) }
        .navigationDestination(for: AuthorRef.self) { AuthorView(author: $0) }
        .toolbar {
            if !store.allEntries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Удалить всё", role: .destructive) { confirmAll = true }
                }
            }
        }
        .confirmationDialog("Удалить все скачанные главы?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Удалить всё", role: .destructive) { store.removeAll() }
        }
    }
}

// MARK: - Ранобэ: экран тайтла
@MainActor
final class NovelDetailViewModel: ObservableObject {
    @Published var anime: Anime
    @Published var chapters: [NovelChapter] = []
    @Published var isLoading = true
    @Published var error: String?
    @Published var offline = false

    init(anime: Anime) { self.anime = anime }

    func load() async {
        isLoading = true
        error = nil
        guard let slug = anime.slugUrl else {
            error = "У тайтла нет адреса"
            isLoading = false
            return
        }
        async let d = AnimelibAPI.shared.details(slug: slug)
        async let c = NovelService.chapters(slug: slug)
        if let full = try? await d { anime = full }
        do {
            let list = try await c
            chapters = list
            offline = false
            OfflineStore.current.refresh(novel: anime, chapters: list)
        } catch {
            let saved = OfflineStore.current.savedChapters(anime.id)
            if saved.isEmpty {
                self.error = error.localizedDescription
            } else {
                chapters = saved
                offline = true
            }
        }
        isLoading = false
    }

    var volumeGroups: [(volume: String, indices: [Int])] {
        var order: [String] = []
        var map: [String: [Int]] = [:]
        for (i, c) in chapters.enumerated() {
            if map[c.volume] == nil { order.append(c.volume) }
            map[c.volume, default: []].append(i)
        }
        return order.map { ($0, map[$0] ?? []) }
    }
}

struct ReaderStart: Identifiable {
    let id: Int
}

/// Плашка загрузки: закреплена внизу экрана, поэтому не двигает список глав при появлении и исчезновении.
struct DownloadBannerView: View {
    @ObservedObject var dl: DownloadManager
    @ObservedObject var progress: DownloadProgress

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Загрузка: \(dl.done) из \(dl.total)" + (progress.status.isEmpty ? "" : " · " + progress.status))
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Button("Стоп") { dl.cancelAll() }
                .font(.caption.bold())
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
        .padding(.horizontal, 16).padding(.bottom, 8)
    }
}

struct NovelDetailView: View {
    @StateObject private var vm: NovelDetailViewModel
    @ObservedObject private var read = ReadStore.shared
    @ObservedObject private var favorites = FavoritesStore.current
    @State private var expanded = false
    @State private var reversed = false
    @State private var reader: ReaderStart?
    @State private var showComments = false
    @State private var showBookmark = false
    @ObservedObject private var store = OfflineStore.current
    @ObservedObject private var dl = DownloadManager.shared
    @State private var confirmRemove = false
    @State private var showEstimate = false
    @State private var estimateMsg = ""
    @State private var estimateIdx: [Int] = []
    private var isManga: Bool { LibSite.current.isManga }
    private let autoContinue: Bool
    @State private var didAutoContinue = false

    init(novel: Novel, autoContinue: Bool = false) {
        _vm = StateObject(wrappedValue: NovelDetailViewModel(anime: novel.anime))
        self.autoContinue = autoContinue
    }

    private var backdrop: some View {
        ZStack {
            Theme.base
            RemoteImage(url: vm.anime.imageURL, maxPixel: 96).blur(radius: 16).opacity(0.55)
            CoverTintLayer(url: vm.anime.imageURL, strength: 0.6)
            LinearGradient(colors: [.clear, Theme.base.opacity(0.85), Theme.base], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var resumePctText: String {
        if let rp = ReadPosStore.shared.get(vm.anime.readKey), rp.pct > 0,
           vm.chapters.indices.contains(resumeIndex), vm.chapters[resumeIndex].id == rp.c {
            return " · \(rp.pct)%"
        }
        return ""
    }

    private var resumeIndex: Int {
        if let last = read.lastChapter(vm.anime.readKey),
           let i = vm.chapters.firstIndex(where: { $0.id == last }) { return i }
        return 0
    }

    private func doQueue(_ idx: [Int]) {
        dl.enqueue(novel: vm.anime, all: vm.chapters, targets: idx.map { vm.chapters[$0] })
    }

    private func queue(_ idx: [Int]) {
        let todo = idx.filter { !store.isDownloaded(vm.anime.id, vm.chapters[$0].id) }
        guard !todo.isEmpty else { return }
        let avg = store.avgChapterBytes ?? (isManga ? 20_000_000 : 800_000)
        let est = avg * todo.count
        let used = OfflineStore.usedBytes
        let limit = OfflineStore.limitBytes
        let over = limit > 0 && used + est > limit
        if over || todo.count >= 10 {
            var m = "Примерно \(fmtBytes(est))"
            m += store.avgChapterBytes == nil ? " (грубая оценка, пока нет скачанных глав). " : " (по среднему размеру ваших глав). "
            m += "Сейчас занято \(fmtBytes(used))" + (limit > 0 ? " из \(fmtBytes(limit))." : ".")
            if over { m += OfflineStore.purgeMode ? " Лимит превышен: удалю самые старые прочитанные главы." : " Лимит будет превышен, скачивание остановится на нём." }
            estimateMsg = m
            estimateIdx = todo
            showEstimate = true
        } else {
            doQueue(todo)
        }
    }

    private func nextIndices(_ n: Int) -> [Int] {
        let start = read.lastChapter(vm.anime.readKey) == nil ? 0 : resumeIndex
        return Array(vm.chapters.indices.dropFirst(start).prefix(n))
    }

    private var downloadMenu: some View {
        Menu {
            Button { queue(Array(vm.chapters.indices)) } label: {
                Label("Скачать все главы", systemImage: "arrow.down.circle")
            }
            Button {
                queue(vm.chapters.indices.filter { !read.isRead(vm.anime.readKey, vm.chapters[$0].id) })
            } label: {
                Label("Скачать непрочитанные", systemImage: "book.closed")
            }
            Menu {
                ForEach([5, 10, 25, 50], id: \.self) { n in
                    Button("\(n) глав") { queue(nextIndices(n)) }
                }
            } label: {
                Label("Следующие главы…", systemImage: "forward.end")
            }
            if store.downloadedCount(vm.anime.id) > 0 {
                Divider()
                Button(role: .destructive) { confirmRemove = true } label: {
                    Label("Удалить загруженные", systemImage: "trash")
                }
            }
        } label: {
            let n = store.downloadedCount(vm.anime.id)
            Label(n > 0 ? "Скачано: \(n)" : "Скачать", systemImage: "arrow.down.circle")
                .font(.footnote)
        }
    }

    @ViewBuilder
    private func volumeButton(_ idx: [Int]) -> some View {
        let all = idx.allSatisfy { store.isDownloaded(vm.anime.id, vm.chapters[$0].id) }
        if all {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green).font(.footnote)
        } else {
            Button { queue(idx) } label: {
                Label("Скачать том", systemImage: "arrow.down.circle").font(.caption)
            }
            .buttonStyle(.pressable)
            .foregroundStyle(Theme.accent)
        }
    }

    private var novelPills: [(String, String)] {
        var p: [(String, String)] = []
        if let r = vm.anime.rateAvg { p.append(("star.fill", r)) }
        if let s = vm.anime.status?.title, !s.isEmpty { p.append(("dot.radiowaves.left.and.right", s)) }
        if let t = vm.anime.type?.title, !t.isEmpty { p.append(("book", t)) }
        if let a = vm.anime.ageRestriction?.title, !a.isEmpty { p.append(("exclamationmark.shield", a)) }
        if !vm.chapters.isEmpty { p.append(("list.bullet", "\(vm.chapters.count) гл.")) }
        if let last = vm.chapters.compactMap({ $0.date }).max() { p.append(("clock", ChapterAge.ago(last))) }
        return p
    }

    private func row(_ i: Int) -> some View {
        let c = vm.chapters[i]
        let isRead = read.isRead(vm.anime.readKey, c.id)
        let saved = store.isDownloaded(vm.anime.id, c.id)
        return HStack(spacing: 8) {
            Button { reader = ReaderStart(id: i) } label: {
                HStack(spacing: 12) {
                    Text(c.number)
                        .font(.footnote.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(isRead ? Color.secondary : Color.primary)
                        .frame(width: 46, height: 46)
                        .background(isRead ? Color.gray.opacity(0.22) : Theme.accent.opacity(0.28), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name.isEmpty ? "Глава \(c.number)" : c.name)
                            .font(.subheadline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let f = dl.failed[c.id] {
                            Text(f).font(.caption2).foregroundStyle(Color.orange).lineLimit(1)
                        } else if let dt = c.date {
                            Text((isRead ? "Прочитано · " : "") + ChapterAge.ago(dt) + " · " + ChapterAge.full(dt))
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        } else if isRead {
                            Text("Прочитано").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(isRead ? Color.secondary : Color.primary)
                    Spacer()
                    Image(systemName: isRead ? "checkmark.circle.fill" : "book.fill")
                        .foregroundStyle(isRead ? Color.gray : Theme.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            ChapterDownloadButton(novel: vm.anime, chapters: vm.chapters, chapter: c)
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 0.5))
        .contextMenu {
            if saved {
                Button(role: .destructive) { store.remove(novel: vm.anime.id, chapter: c.id) } label: {
                    Label("Удалить загрузку", systemImage: "trash")
                }
            } else {
                Button { queue([i]) } label: { Label("Скачать главу", systemImage: "arrow.down.circle") }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TitleHero(cover: vm.anime.largeImageURL, title: vm.anime.displayTitle,
                          subtitle: (vm.anime.name != nil && vm.anime.name != vm.anime.displayTitle) ? vm.anime.name : nil,
                          pills: novelPills)

                if !vm.chapters.isEmpty {
                    PrimaryActionButton(icon: "book.fill",
                                        title: read.lastChapter(vm.anime.readKey) == nil
                                            ? "Начать читать"
                                            : "Продолжить: Глава \(vm.chapters[resumeIndex].number)" + resumePctText) {
                        reader = ReaderStart(id: resumeIndex)
                    }
                }

                if !(vm.anime.genres ?? []).isEmpty || !(vm.anime.tags ?? []).isEmpty {
                    GenreStrip(genres: vm.anime.genres ?? [], tags: vm.anime.tags ?? [])
                }

                if let s = vm.anime.summary, !s.isEmpty { SummaryCard(text: s, expanded: $expanded) }

                TitleActionsRow(anime: vm.anime) { showComments = true }

                HStack {
                    Text("Главы").font(.title2.bold())
                    Spacer()
                    if !vm.chapters.isEmpty { downloadMenu }
                    if vm.chapters.count > 1 {
                        Button { withAnimation { reversed.toggle() } } label: {
                            Label(reversed ? "Сначала новые" : "Сначала старые", systemImage: "arrow.up.arrow.down")
                                .font(.footnote)
                        }
                        .padding(.leading, 6)
                    }
                }
                if let n = dl.notice {
                    Text(n).font(.footnote).foregroundStyle(Color.orange)
                }
                if vm.offline {
                    Text("Нет сети: показаны только скачанные главы.")
                        .font(.footnote).foregroundStyle(Color.orange)
                }
                if vm.isLoading { ProgressView() }
                if let e = vm.error { Text(e).foregroundStyle(.red).font(.footnote) }
                if !vm.isLoading && vm.chapters.isEmpty && vm.error == nil {
                    Text("Глав пока нет").foregroundStyle(.secondary)
                }
                LazyVStack(alignment: .leading, spacing: 8) {
                    let groups = reversed ? Array(vm.volumeGroups.reversed()) : vm.volumeGroups
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                        HStack {
                            Text("Том \(g.volume)")
                                .font(.footnote.weight(.bold))
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .glassCapsule()
                            Spacer()
                            volumeButton(g.indices)
                        }
                        .padding(.top, 12)
                        ForEach(reversed ? Array(g.indices.reversed()) : g.indices, id: \.self) { i in
                            row(i)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(backdrop)
        .safeAreaInset(edge: .bottom) {
            if dl.total > 0 { DownloadBannerView(dl: dl, progress: dl.progress) }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationDestination(for: AuthorRef.self) { AuthorView(author: $0) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let u = titleURL(vm.anime) {
                    Link(destination: u) { Image(systemName: "safari") }
                    ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }
                }
                Button { showBookmark = true } label: { Image(systemName: "bookmark") }
                Button { favorites.toggle(vm.anime) } label: {
                    Image(systemName: favorites.contains(vm.anime) ? "heart.fill" : "heart")
                        .foregroundStyle(favorites.contains(vm.anime) ? Color.pink : Color.primary)
                }
            }
        }
        .task {
            await vm.load()
            if autoContinue, !didAutoContinue, !vm.chapters.isEmpty {
                didAutoContinue = true
                reader = ReaderStart(id: resumeIndex)
            }
        }
        .sheet(isPresented: $showComments) { CommentsView(anime: vm.anime) }
        .sheet(isPresented: $showBookmark) { BookmarkSheet(anime: vm.anime) }
        .confirmationDialog("Скачать \(estimateIdx.count) гл.?", isPresented: $showEstimate, titleVisibility: .visible) {
            Button("Скачать") { doQueue(estimateIdx) }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(estimateMsg)
        }
        .confirmationDialog("Удалить загруженные главы этого тайтла?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                store.remove(novel: vm.anime.id)
                if vm.offline { vm.chapters = [] }
            }
        }
        .fullScreenCover(item: $reader) { r in
            if isManga {
                MangaReaderView(novel: vm.anime, chapters: vm.chapters, start: r.id)
            } else {
                NovelReaderView(novel: vm.anime, chapters: vm.chapters, start: r.id)
            }
        }
    }
}

// MARK: - Манга: страницы и читалка
struct MangaPage: Identifiable, Hashable {
    let id: Int
    let urls: [URL]
    let width: CGFloat
    let height: CGFloat

    var url: URL { urls[0] }
    var ratio: CGFloat { width > 0 && height > 0 ? height / width : 0 }
    /// Страница должна занять по ширине экран, поэтому длинным полосам разрешаем больше пикселей.
    var maxPixel: CGFloat { min(4096, max(1300, 1300 * (ratio > 0 ? ratio : 1.5))) }
}

actor MangaImageServers {
    static let shared = MangaImageServers()
    private var cachedBy: [String: [String]] = [:]
    private let fallback = "https://img3.cdnlibs.org"

    func bases() async -> [String] {
        let siteID = LibSite.current.id
        if let c = cachedBy[siteID] { return c }
        var list: [String] = []
        let q = [URLQueryItem(name: "fields[]", value: "imageServers")]
        if let data = try? await AnimelibAPI.shared.rawData("/constants", query: q),
           let root = J.obj(data) as? [String: Any],
           let d = root["data"] as? [String: Any],
           let arr = d["imageServers"] as? [[String: Any]] {
            let matched = arr.filter { srv in
                guard let ids = srv["site_ids"] as? [Any], !ids.isEmpty else { return true }
                return ids.contains { J.int($0) == Int(siteID) }
            }
            let mine = matched.isEmpty ? arr : matched
            let main = mine.filter { ($0["id"] as? String) == "main" }
            let rest = mine.filter { ($0["id"] as? String) != "main" }
            list = (main + rest).compactMap { J.str($0["url"]) }
            if !list.isEmpty { cachedBy[siteID] = list + (list.contains(fallback) ? [] : [fallback]) }
        }
        if !list.contains(fallback) { list.append(fallback) }
        return list
    }

    /// Адрес «как есть»: сервер + путь без правок (так делают сайт и сторонние клиенты).
    static func raw(_ path: String, base: String) -> URL? {
        if path.hasPrefix("http") { return nil }
        return URL(string: base + (path.hasPrefix("/") ? path : "/" + path))
    }

    static func resolve(_ path: String, base: String) -> URL? {
        // Путь страницы приходит как «//manga/…»: это часть адреса на сервере картинок, а не хост.
        if path.hasPrefix("http") { return URL(string: path) }
        var b = base
        while b.hasSuffix("/") { b.removeLast() }
        var p = path
        while p.hasPrefix("/") { p.removeFirst() }
        return URL(string: b + "/" + p)
    }
}

enum MangaService {
    private static func num(_ v: Any?) -> CGFloat {
        if let x = v as? Double { return CGFloat(x) }
        return CGFloat(J.int(v) ?? 0)
    }

    /// Скачанная глава: страницы лежат файлами на телефоне, сеть не нужна.
    @MainActor
    static func localPages(novel: Int, chapter: Int) -> [MangaPage]? {
        let store = OfflineStore.manga
        guard store.isDownloaded(novel, chapter),
              let data = try? Data(contentsOf: store.chapterFile(novel, chapter)),
              let root = J.obj(data) as? [String: Any],
              let d = root["data"] as? [String: Any] else { return nil }
        let raw = (d["pages"] as? [[String: Any]]) ?? []
        var out: [MangaPage] = []
        for p in raw {
            guard J.str(p["url"]) ?? J.str(p["image"]) != nil else { continue }
            let f = store.mangaPageFile(novel, chapter, out.count)
            guard FileManager.default.fileExists(atPath: f.path) else { return nil }
            out.append(MangaPage(id: out.count, urls: [f], width: num(p["width"]), height: num(p["height"])))
        }
        return out.isEmpty ? nil : out
    }

    static func pages(slug: String, chapter c: NovelChapter, novelID: Int? = nil) async throws -> [MangaPage] {
        if let n = novelID, let local = await localPages(novel: n, chapter: c.id) { return local }
        let data = try await AnimelibAPI.shared.rawData(NovelService.chapterPath(slug: slug),
                                                        query: NovelService.chapterQuery(c))
        guard let root = J.obj(data) as? [String: Any],
              let d = root["data"] as? [String: Any] else { throw APIError.badURL }
        let bases = await MangaImageServers.shared.bases()
        return parse(d, bases: bases)
    }

    static func parse(_ d: [String: Any], bases: [String]) -> [MangaPage] {
        let raw = (d["pages"] as? [[String: Any]]) ?? []
        var out: [MangaPage] = []
        for p in raw {
            guard let path = J.str(p["url"]) ?? J.str(p["image"]) else { continue }
            var urls: [URL] = []
            for b in bases {
                for u in [MangaImageServers.resolve(path, base: b), MangaImageServers.raw(path, base: b)] {
                    if let u = u, !urls.contains(u) { urls.append(u) }
                }
            }
            if urls.isEmpty { continue }
            out.append(MangaPage(id: out.count, urls: urls, width: num(p["width"]), height: num(p["height"])))
        }
        return out
    }
}

/// Загрузка страниц манги: по одной попытке на каждый адрес, повтор кругом, без дублей.
actor MangaImageStore {
    static let shared = MangaImageStore()
    private var inflight: [String: Task<(UIImage?, String), Never>] = [:]
    private(set) var lastNote = ""

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 25
        cfg.httpMaximumConnectionsPerHost = 4
        cfg.urlCache = URLCache(memoryCapacity: 30_000_000, diskCapacity: 400_000_000)
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: cfg)
    }()

    private static let agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    func image(for page: MangaPage) async -> UIImage? {
        let key = ImageCache.key(page.url, page.maxPixel)
        if let c = ImageCache.shared.object(forKey: key) { return c }
        let id = key as String
        if let t = inflight[id] { return await t.value.0 }
        let urls = page.urls
        let px = page.maxPixel
        let t = Task.detached(priority: .userInitiated) { () -> (UIImage?, String) in
            var note = ""
            for round in 0..<2 {
                for u in urls {
                    if u.isFileURL {
                        if let data = try? Data(contentsOf: u),
                           let img = ImageLoader.downsampleWidth(data, width: 1300, maxSide: 16000) {
                            ImageCache.store(img, key)
                            return (img, "")
                        }
                        note = "файл страницы не читается"
                        continue
                    }
                    var req = URLRequest(url: u)
                    req.setValue(LibSite.current.isManga ? LibSite.current.referer : LibSite.manga.referer, forHTTPHeaderField: "Referer")
                    req.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
                    req.setValue(MangaImageStore.agent, forHTTPHeaderField: "User-Agent")
                    do {
                        let (data, resp) = try await MangaImageStore.session.data(for: req)
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        if (200..<300).contains(code) {
                            if let img = ImageLoader.downsampleWidth(data, width: 1300, maxSide: 16000) {
                                ImageCache.store(img, key)
                                return (img, "")
                            }
                            note = "не удалось разобрать картинку (\(data.count) байт, \(resp.mimeType ?? "?"))"
                        } else {
                            note = "HTTP \(code) · \(u.host ?? "")"
                        }
                    } catch {
                        note = error.localizedDescription
                    }
                }
                if round == 0 { try? await Task.sleep(nanoseconds: 700_000_000) }
            }
            return (nil, note + "\n" + (urls.first?.absoluteString ?? ""))
        }
        inflight[id] = t
        let r = await t.value
        inflight[id] = nil
        if r.0 == nil { lastNote = r.1 }
        return r.0
    }

    /// Только скачивает страницу в дисковый кэш, не декодируя её: память не занимается,
    /// а когда до страницы дойдёт очередь, она откроется из кэша без сети.
    nonisolated func warm(_ page: MangaPage) async {
        if ImageCache.shared.object(forKey: ImageCache.key(page.url, page.maxPixel)) != nil { return }
        for u in page.urls {
            if Task.isCancelled || u.isFileURL { return }
            var req = URLRequest(url: u)
            req.setValue(LibSite.current.isManga ? LibSite.current.referer : LibSite.manga.referer, forHTTPHeaderField: "Referer")
            req.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            req.setValue(MangaImageStore.agent, forHTTPHeaderField: "User-Agent")
            if let (_, resp) = try? await MangaImageStore.session.data(for: req),
               let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) { return }
        }
    }
}

struct MangaPageView: View {
    let page: MangaPage
    var vertical = false
    var dim: CGFloat = 1
    var autoBG = false
    let onTap: (CGFloat) -> Void
    @State private var image: UIImage?
    @State private var failed = false
    @State private var note = ""
    @State private var attempt = 0
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var bg: Color?

    /// Белое или чёрное поле по краям самой страницы.
    nonisolated static func edgeColor(_ img: UIImage) -> Color? {
        guard let cg = img.cgImage else { return nil }
        let n = 24
        var px = [UInt8](repeating: 0, count: n * n * 4)
        var ok = false
        px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8,
                                      bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            ok = true
        }
        guard ok else { return nil }
        var sum = 0.0
        var cnt = 0.0
        for y in 0..<n {
            for x in 0..<n where x < 2 || y < 2 || x >= n - 2 || y >= n - 2 {
                let i = (y * n + x) * 4
                sum += 0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2])
                cnt += 1
            }
        }
        return sum / max(cnt, 1) / 255 > 0.5 ? Color.white : Color.black
    }

    private func resetZoom() {
        scale = 1; base = 1; offset = .zero; lastOffset = .zero
    }

    var body: some View {
        Group {
            if vertical {
                flow
            } else {
                GeometryReader { geo in content(geo.size) }
            }
        }
        .background(autoBG ? (bg ?? Color.clear) : Color.clear)
        .task(id: "\(page.id)-\(attempt)") { await load() }
    }

    /// Режим ленты: страницы идут одна под другой, высота по картинке.
    @ViewBuilder
    private var flow: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { onTap(0.5) }
        } else if failed {
            Button { failed = false; attempt += 1 } label: {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise").font(.title3)
                    Text("Страница \(page.id + 1) не загрузилась. Нажми, чтобы повторить.")
                        .font(.footnote).multilineTextAlignment(.center)
                    if !note.isEmpty {
                        Text(note).font(.caption2).opacity(0.6).multilineTextAlignment(.center)
                    }
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        } else {
            ZStack {
                Color.white.opacity(0.04)
                ProgressView().tint(.white)
            }
            .aspectRatio(page.ratio > 0 ? 1 / page.ratio : 0.7, contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func content(_ size: CGSize) -> some View {
        if let image {
            if page.ratio > 2.2 {
                ScrollView(.vertical, showsIndicators: false) {
                    Image(uiImage: image).resizable().scaledToFit().frame(width: size.width)
                }
                .simultaneousGesture(SpatialTapGesture().onEnded { v in onTap(v.location.x / max(size.width, 1)) })
            } else {
                ZoomableImageView(image: image, dim: dim, onTap: onTap)
                    .frame(width: size.width, height: size.height)
            }
        } else if failed {
            Button { failed = false; attempt += 1 } label: {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise").font(.title2)
                    Text("Страница \(page.id + 1) не загрузилась. Нажми, чтобы повторить.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    if !note.isEmpty {
                        Text(note).font(.caption2).opacity(0.6).multilineTextAlignment(.center)
                    }
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(24)
                .frame(width: size.width, height: size.height)
            }
        } else {
            ProgressView().tint(.white).frame(width: size.width, height: size.height)
        }
    }

    private func load() async {
        if let img = await MangaImageStore.shared.image(for: page) {
            withAnimation(.easeOut(duration: 0.15)) { image = img }
            // Цвет полей считается в фоне: для длинной страницы это заметная работа.
            bg = await Task.detached(priority: .utility) { MangaPageView.edgeColor(img) }.value
            return
        }
        if Task.isCancelled { return }
        note = await MangaImageStore.shared.lastNote
        failed = true
    }
}

/// Страница манги с настоящим зумом: щипок приближает к точке между пальцами, палец двигает приближенную страницу
/// по всем краям, двойное касание приближает к месту касания и возвращает обратно.
final class FitScrollView: UIScrollView {
    let imageView = UIImageView()
    private var lastSize: CGSize = .zero
    private weak var lastImage: UIImage?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let img = imageView.image, bounds.width > 1, bounds.height > 1,
              img.size.width > 0, img.size.height > 0 else { return }
        let relayout = bounds.size != lastSize || lastImage !== img
        if relayout {
            lastSize = bounds.size
            lastImage = img
            zoomScale = 1
            let r = min(bounds.width / img.size.width, bounds.height / img.size.height)
            let fit = CGSize(width: img.size.width * r, height: img.size.height * r)
            imageView.frame = CGRect(origin: .zero, size: fit)
            contentSize = fit
        }
        let ix = max((bounds.width - contentSize.width) / 2, 0)
        let iy = max((bounds.height - contentSize.height) / 2, 0)
        let inset = UIEdgeInsets(top: iy, left: ix, bottom: iy, right: ix)
        if contentInset != inset { contentInset = inset }
        if relayout { contentOffset = CGPoint(x: -ix, y: -iy) }
    }
}

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    var dim: CGFloat = 1
    let onTap: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onTap: ((CGFloat) -> Void)?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? FitScrollView)?.imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { scrollView.setNeedsLayout() }

        @objc func single(_ g: UITapGestureRecognizer) {
            guard let s = g.view as? UIScrollView else { return }
            let x = g.location(in: s).x - s.contentOffset.x
            onTap?(x / max(s.bounds.width, 1))
        }

        @objc func double(_ g: UITapGestureRecognizer) {
            guard let s = g.view as? FitScrollView else { return }
            if s.zoomScale > s.minimumZoomScale + 0.05 {
                s.setZoomScale(s.minimumZoomScale, animated: true)
            } else {
                let target: CGFloat = 2.6
                let p = g.location(in: s.imageView)
                let w = s.bounds.width / target
                let h = s.bounds.height / target
                s.zoom(to: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), animated: true)
            }
        }
    }

    func makeUIView(context: Context) -> FitScrollView {
        let s = FitScrollView()
        s.delegate = context.coordinator
        s.minimumZoomScale = 1
        s.maximumZoomScale = 5
        s.bouncesZoom = true
        s.showsVerticalScrollIndicator = false
        s.showsHorizontalScrollIndicator = false
        s.contentInsetAdjustmentBehavior = .never
        s.decelerationRate = .fast
        s.backgroundColor = .clear
        s.imageView.contentMode = .scaleToFill
        s.addSubview(s.imageView)
        let dbl = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.double(_:)))
        dbl.numberOfTapsRequired = 2
        let one = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.single(_:)))
        one.require(toFail: dbl)
        s.addGestureRecognizer(dbl)
        s.addGestureRecognizer(one)
        return s
    }

    func updateUIView(_ s: FitScrollView, context: Context) {
        context.coordinator.onTap = onTap
        if s.imageView.image !== image {
            s.imageView.image = image
            s.setNeedsLayout()
        }
        s.imageView.alpha = dim
    }
}

struct ChapterCommentsView: View {
    let novel: Anime
    let chapter: NovelChapter
    let pageCount: Int
    @State private var page: Int
    @State private var wholeChapter = false
    @StateObject private var vm: CommentsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCompose = false

    init(novel: Anime, chapter: NovelChapter, page: Int = 1, pageCount: Int = 0) {
        self.novel = novel
        self.chapter = chapter
        self.pageCount = pageCount
        _page = State(initialValue: max(page, 1))
        _vm = StateObject(wrappedValue: CommentsViewModel(animeID: chapter.id, slug: novel.slugUrl ?? String(novel.id),
                                                          postType: "chapter"))
    }

    private var hasPages: Bool { vm.items.contains { $0.page != nil } }
    private var perPage: Bool { !wholeChapter && hasPages }
    private var onPage: [CommentItem] { vm.items.filter { $0.page == page } }

    private func syncPostPage() { vm.postPage = perPage ? page : nil }

    private var pageBar: some View {
        VStack(spacing: 8) {
            Picker("", selection: $wholeChapter) {
                Text("Эта страница").tag(false)
                Text("Вся глава").tag(true)
            }
            .pickerStyle(.segmented)
            if !wholeChapter && hasPages {
                HStack {
                    Button { page = max(1, page - 1) } label: { Image(systemName: "chevron.left") }
                        .disabled(page <= 1)
                    Spacer()
                    Text("Страница \(page)" + (pageCount > 0 ? " из \(pageCount)" : "") + " · комментариев: \(onPage.count)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button { page = pageCount > 0 ? min(pageCount, page + 1) : page + 1 } label: { Image(systemName: "chevron.right") }
                        .disabled(pageCount > 0 && page >= pageCount)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pageBar
                ScrollView {
                    VStack(spacing: 10) {
                        if perPage {
                            CommentsList(vm: vm, filter: { $0.page == page })
                            if onPage.isEmpty && !vm.isLoading {
                                Text("К этой странице комментариев нет").foregroundStyle(.secondary).padding(.top, 30)
                            }
                        } else {
                            CommentsList(vm: vm)
                            if !vm.items.isEmpty && !hasPages && !vm.isLoading {
                                Text("Сайт не передаёт номера страниц у комментариев, поэтому показана вся глава. Поля комментария: \(vm.sampleKeys)")
                                    .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                    .padding(14)
                }
            }
            .background(AppBackground())
            .navigationTitle("Глава \(chapter.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        CommentSortMenu(vm: vm)
                        Button { syncPostPage(); showCompose = true } label: { Image(systemName: "square.and.pencil") }
                    }
                }
            }
            .commentSheets(vm, showCompose: $showCompose)
            .task { await vm.loadAll(); syncPostPage() }
            .onChange(of: page) { _ in syncPostPage() }
            .onChange(of: wholeChapter) { _ in syncPostPage() }
        }
    }
}

/// Перелистывание как в Apple Books: страница загибается и переворачивается за край.
struct BookPager: UIViewControllerRepresentable {
    let count: Int
    @Binding var current: Int
    var backColor: UIColor = .black
    var themedBack = false
    let content: (Int) -> AnyView

    final class Host: UIHostingController<AnyView> {
        var index = 0
        var isBack = false
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: BookPager
        var shown = 0
        init(_ p: BookPager) { parent = p }

        func host(_ i: Int) -> Host? {
            guard i >= 0, i < parent.count else { return nil }
            let h = Host(rootView: parent.content(i))
            h.index = i
            h.view.backgroundColor = .black
            return h
        }

        // Оборот листа: однотонный экран цвета темы, чтобы не светился белым.
        func back(_ i: Int) -> Host? {
            guard i >= 0, i < parent.count else { return nil }
            let page = parent.content(i)
            let h = Host(rootView: AnyView(
                ZStack {
                    Color(parent.backColor)
                    page.scaleEffect(x: -1, y: 1).opacity(0.16)
                }.clipped()
            ))
            h.index = i
            h.isBack = true
            h.view.backgroundColor = parent.backColor
            return h
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
            guard let h = vc as? Host else { return nil }
            if !parent.themedBack { return host(h.index - 1) }
            return h.isBack ? host(h.index) : back(h.index - 1)
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
            guard let h = vc as? Host else { return nil }
            if !parent.themedBack { return host(h.index + 1) }
            return h.isBack ? host(h.index + 1) : back(h.index)
        }

        func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let h = pvc.viewControllers?.first as? Host, !h.isBack else { return }
            shown = h.index
            if parent.current != h.index { parent.current = h.index }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal)
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.isDoubleSided = themedBack
        pvc.view.backgroundColor = backColor
        // Свои зоны касаний у нас есть, встроенные отключаем, чтобы страницы не листались дважды.
        for g in pvc.gestureRecognizers where g is UITapGestureRecognizer { g.isEnabled = false }
        if let h = context.coordinator.host(current) {
            pvc.setViewControllers([h], direction: .forward, animated: false)
            context.coordinator.shown = current
        }
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        let c = context.coordinator
        c.parent = self
        pvc.view.backgroundColor = backColor
        if pvc.isDoubleSided != themedBack { pvc.isDoubleSided = themedBack }
        if c.shown != current, let h = c.host(current) {
            let dir: UIPageViewController.NavigationDirection = current > c.shown ? .forward : .reverse
            c.shown = current
            pvc.setViewControllers([h], direction: dir, animated: true)
        }
    }
}

/// Свои настройки читалки для одного тайтла (как в Mihon). Пока «enabled» выключено, работают общие.
struct MangaTitlePrefs: Codable, Equatable {
    var enabled = false
    var anim = "slide"
    var autoBG = false
    var autoNext = true
    var speed = 60.0
    var dim = 0.0
    var warm = 0.0
    var gray = false
}

struct GrayIf: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.saturation(0) } else { content }
    }
}

struct MangaReaderSettings: View {
    @Binding var titleMode: String
    @Binding var defaultMode: String
    @Binding var own: Bool
    @Binding var anim: String
    @Binding var autoBG: Bool
    @Binding var autoNext: Bool
    @Binding var speed: Double
    @Binding var dim: Double
    @Binding var warm: Double
    @Binding var gray: Bool
    let detected: String
    @Environment(\.dismiss) private var dismiss

    // MARK: кирпичики
    private func header(_ icon: String, _ t: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(color)
            Text(t.uppercased()).font(.footnote.weight(.bold)).tracking(0.6).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 0.5))
    }

    private func note(_ t: String) -> some View {
        Text(t).font(.footnote).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }

    /// Плитки с иконкой: выбранная заливается акцентным градиентом.
    private func tiles(_ options: [(String, String, String)], _ sel: Binding<String>) -> some View {
        HStack(spacing: 10) {
            ForEach(options, id: \.0) { o in
                let on = sel.wrappedValue == o.0
                Button {
                    Haptics.select()
                    withAnimation(.easeOut(duration: 0.18)) { sel.wrappedValue = o.0 }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: o.2).font(.system(size: 22, weight: .semibold))
                        Text(o.1).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(on ? Color.white : Color.primary.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .shadow(color: Theme.accent.opacity(0.45), radius: 10, y: 4)
                        } else {
                            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.primary.opacity(0.08))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 14)
    }

    private func iconBox(_ icon: String, _ color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func slider(_ icon: String, _ color: Color, _ title: String, _ v: Binding<Double>, _ range: ClosedRange<Double>, _ fmt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                iconBox(icon, color)
                Text(title).font(.system(size: 17))
                Spacer()
                Text(fmt).font(.system(size: 15, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: v, in: range).tint(Theme.accent)
        }
        .padding(.vertical, 12)
    }

    private func toggle(_ icon: String, _ color: Color, _ title: String, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) {
            HStack(spacing: 12) {
                iconBox(icon, color)
                Text(title).font(.system(size: 17))
            }
        }
        .tint(Theme.accent)
        .frame(minHeight: 54)
    }

    private func str(_ b: Binding<Bool>) -> Binding<String> {
        Binding(get: { b.wrappedValue ? "own" : "all" }, set: { b.wrappedValue = ($0 == "own") })
    }

    /// Выбор режима: для этого тайтла пишет его режим, для всех — ещё и общий по умолчанию (отдельный блок больше не нужен).
    private var modeBinding: Binding<String> {
        Binding(get: { titleMode },
                set: { v in
                    titleMode = v
                    if !own { defaultMode = v }
                })
    }

    // MARK: экран
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Настройки читалки").font(.headline)
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 46, height: 46)
                            .glassShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 18) {
                    // для кого настройки
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            ForEach([("all", "Для всех"), ("own", "Для этого тайтла")], id: \.0) { o in
                                let on = str($own).wrappedValue == o.0
                                Button {
                                    Haptics.select()
                                    withAnimation(.easeOut(duration: 0.2)) { str($own).wrappedValue = o.0 }
                                } label: {
                                    Text(o.1)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(on ? Color.white : Color.primary.opacity(0.8))
                                        .frame(maxWidth: .infinity, minHeight: 42)
                                        .background {
                                            if on {
                                                Capsule().fill(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .leading, endPoint: .trailing))
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(4)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                        Text(own ? "Эти настройки действуют только в этом тайтле, остальные не меняются."
                                 : "Изменения касаются всех тайтлов, у которых нет своих настроек.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                    }

                    header("rectangle.split.1x2", "Режим чтения", Theme.accent)
                    card {
                        tiles([("auto", "Авто", "wand.and.stars"), ("pages", "Страницы", "book"), ("scroll", "Лента", "arrow.up.and.down.text.horizontal")], modeBinding)
                        Divider()
                        note("«Страницы» для манги: листаешь свайпом. «Лента» для манхвы: прокручиваешь вниз. «Авто»: сейчас выбрано «\(detected)». Режим запоминается для тайтла\(own ? "." : ", а выбранный здесь станет режимом по умолчанию для остальных.")")
                    }

                    header("hand.draw", "Листание", .orange)
                    card {
                        tiles([("slide", "Сдвиг", "arrow.left.and.right"), ("fade", "Плавно", "circle.lefthalf.filled"), ("book", "Как в книге", "book.pages")], $anim)
                        Divider()
                        note("Работает в режиме «Страницы».")
                    }

                    header("play.circle", "Автопрокрутка", .green)
                    card {
                        slider("speedometer", .green, "Скорость", $speed, 15...240, "\(Int(speed))")
                        Divider()
                        toggle("forward.end.fill", .blue, "Сама переходить к следующей главе", $autoNext)
                        Divider()
                        note("Кнопка ▶ внизу в режиме «Лента». Касание ставит прокрутку на паузу.")
                    }

                    header("sun.max", "Экран", .yellow)
                    card {
                        slider("moon.fill", .indigo, "Затемнение", $dim, 0...0.7, "\(Int(dim * 100))%")
                        Divider()
                        slider("flame.fill", .orange, "Тёплый свет", $warm, 0...0.5, "\(Int(warm * 200))%")
                        Divider()
                        toggle("circle.lefthalf.striped.horizontal", .gray, "Чёрно-белый режим", $gray)
                        Divider()
                        toggle("rectangle.inset.filled", .teal, "Фон под страницу", $autoBG)
                        Divider()
                        note("Фон под страницу делает поля вокруг белыми или чёрными, чтобы не было тёмных полос у светлых страниц.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}

/// Список глав внутри читалки: поиск, сортировка, группы по томам, отметки прочитанного, быстрый переход.
struct MangaChapterPicker: View {
    let chapters: [NovelChapter]
    let current: Int
    let readKey: Int
    let onPick: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var read = ReadStore.shared
    @State private var query = ""
    @State private var newestFirst = true

    private var entries: [(i: Int, ch: NovelChapter)] {
        var list = chapters.enumerated().map { (i: $0.offset, ch: $0.element) }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.ch.number.lowercased().contains(q) || $0.ch.name.lowercased().contains(q) || "том \($0.ch.volume)".contains(q) }
        }
        return newestFirst ? Array(list.reversed()) : list
    }

    private var groups: [(vol: String, items: [(i: Int, ch: NovelChapter)])] {
        var out: [(vol: String, items: [(i: Int, ch: NovelChapter)])] = []
        for e in entries {
            if let last = out.last, last.vol == e.ch.volume { out[out.count - 1].items.append(e) }
            else { out.append((vol: e.ch.volume, items: [e])) }
        }
        return out
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateStyle = .medium; return f
    }()

    private func row(_ e: (i: Int, ch: NovelChapter)) -> some View {
        let isCur = e.i == current
        let isRead = read.isRead(readKey, e.ch.id)
        return Button {
            onPick(e.i)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Text(e.ch.number)
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .minimumScaleFactor(0.6).lineLimit(1)
                    .foregroundStyle(isCur ? Color.white : Color.primary)
                    .frame(width: 52, height: 44)
                    .background {
                        if isCur {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .topLeading, endPoint: .bottomTrailing))
                        } else {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.08))
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(e.ch.name.isEmpty ? "Глава \(e.ch.number)" : e.ch.name)
                        .font(.system(size: 16, weight: isCur ? .semibold : .regular))
                        .foregroundStyle(isRead && !isCur ? Color.secondary : Color.primary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    if let d = e.ch.date {
                        Text(Self.dateFmt.string(from: d)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if isCur {
                    Image(systemName: "book.fill").foregroundStyle(Theme.accent)
                } else if isRead {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent.opacity(0.7))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(isCur ? Theme.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(e.i)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 2) {
                    Text("Главы").font(.headline)
                    Text("\(chapters.count) всего · прочитано \(chapters.filter { read.isRead(readKey, $0.id) }.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary).frame(width: 46, height: 46).glassShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Номер или название", text: $query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).frame(height: 44)
                .background(Color.primary.opacity(0.08), in: Capsule())
                Button {
                    Haptics.select()
                    newestFirst.toggle()
                } label: {
                    Image(systemName: newestFirst ? "arrow.down" : "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups, id: \.vol) { g in
                            Section {
                                ForEach(g.items, id: \.i) { row($0) }
                            } header: {
                                Text("Том \(g.vol)")
                                    .font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(.ultraThinMaterial)
                            }
                        }
                        if groups.isEmpty {
                            Text("Ничего не найдено").foregroundStyle(.secondary).padding(.top, 40)
                        }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 24)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { proxy.scrollTo(current, anchor: .center) }
                }
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        query = ""
                        withAnimation { proxy.scrollTo(current, anchor: .center) }
                    } label: {
                        Label("К текущей", systemImage: "scope")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .glassShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }
}

extension View {
    /// Стекло в духе iOS: размытие, лёгкая светлая подложка, блик по краю и мягкая тень.
    @ViewBuilder func liquidGlass<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            legacyGlass(shape)
        }
    }

    func legacyGlass<S: Shape>(_ shape: S) -> some View {
        self
            .background(shape.fill(.ultraThinMaterial))
            .background(shape.fill(Color.white.opacity(0.10)))
            .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.06), .white.opacity(0.25)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.9))
            .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
    }
}

/// Группа стеклянных элементов: на iOS 26 они делят одну область и не «просвечивают» друг сквозь друга.
struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

/// Верхняя панель читалки: на iOS 26 системная стеклянная, ниже — размытая.
struct ReaderBarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

/// Мягкое размытие у края экрана под панелями читалки: текст не наезжает на кнопки.
struct EdgeBlur: View {
    let top: Bool
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(height: height)
            .mask(LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black.opacity(0.8), location: 0.55),
                .init(color: .clear, location: 1)
            ], startPoint: top ? .top : .bottom, endPoint: top ? .bottom : .top))
            .allowsHitTesting(false)
    }
}

struct SolidSheetBackground: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackground(color)
        } else {
            content
        }
    }
}

/// Находит UIScrollView, внутри которого лежит SwiftUI-лента. Ищет, как только вид попал в окно и при каждой раскладке.
struct ScrollFinder: UIViewRepresentable {
    let onFound: (UIScrollView) -> Void

    final class Finder: UIView {
        var onFound: (UIScrollView) -> Void = { _ in }
        private weak var last: UIScrollView?

        private func find() {
            var p: UIView? = superview
            while let x = p {
                if let sv = x as? UIScrollView {
                    if sv !== last { last = sv; onFound(sv) }
                    return
                }
                p = x.superview
            }
        }

        override func didMoveToWindow() { super.didMoveToWindow(); find() }
        override func layoutSubviews() { super.layoutSubviews(); find() }
    }

    func makeUIView(context: Context) -> Finder {
        let v = Finder()
        v.isUserInteractionEnabled = false
        v.onFound = onFound
        return v
    }

    func updateUIView(_ v: Finder, context: Context) {
        v.onFound = onFound
    }
}

/// Плавная прокрутка ленты по таймеру кадров. Стоит на паузе, пока палец на экране,
/// и ждёт, если следующие страницы ещё не загрузились.
final class AutoScroller {
    weak var scrollView: UIScrollView? {
        didSet {
            if scrollView !== oldValue { atEnd = false; pos = scrollView?.contentOffset.y ?? 0 }
        }
    }
    var speed: CGFloat = 60
    var canAdvance: () -> Bool = { true }
    /// Возвращает true, если конец главы обработан; иначе проверка повторится.
    var onEnd: () -> Bool = { true }
    var onBlocked: (Bool) -> Void = { _ in }
    private var blocked = false
    private var ticks = 0
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var blockedSince: CFTimeInterval = 0
    private var atEnd = false
    private var pos: CGFloat = 0

    func start() {
        guard link == nil else { return }
        atEnd = false
        last = 0
        blockedSince = 0
        pos = scrollView?.contentOffset.y ?? 0
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    /// Запасной поиск ленты по всем окнам, если привязка через SwiftUI не сработала.
    private func locate() {
        var best: UIScrollView?
        func walk(_ v: UIView) {
            if let sv = v as? UIScrollView, !sv.isHidden, sv.alpha > 0.01, sv.bounds.width > 200, sv.bounds.height > 300,
               sv.contentSize.height > sv.bounds.height * 1.05 {
                if best == nil || sv.contentSize.height > best!.contentSize.height { best = sv }
            }
            for c in v.subviews { walk(c) }
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for w in ws.windows where !w.isHidden { walk(w) }
        }
        if let b = best { scrollView = b }
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        let dt = last == 0 ? 0 : min(now - last, 0.1)
        last = now
        ticks += 1
        if let cur = scrollView, cur.window == nil { scrollView = nil }
        if scrollView == nil, ticks % 20 == 0 { locate() }
        guard dt > 0, let sv = scrollView else { return }
        if sv.isTracking || sv.isDragging || sv.isDecelerating {
            pos = sv.contentOffset.y
            return
        }
        if canAdvance() {
            blockedSince = 0
            if blocked { blocked = false; onBlocked(false) }
        } else {
            if blockedSince == 0 { blockedSince = now }
            if !blocked { blocked = true; onBlocked(true) }
            if now - blockedSince < 3 { return }
        }
        let maxY = sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom
        if sv.contentSize.height > sv.bounds.height, sv.contentOffset.y >= maxY - 1 {
            if !atEnd, onEnd() { atEnd = true }
            return
        }
        atEnd = false
        if abs(sv.contentOffset.y - pos) > 3 { pos = sv.contentOffset.y }
        pos = min(pos + speed * CGFloat(dt), max(maxY, 0))
        sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: pos), animated: false)
    }
}

struct MangaReaderView: View {
    let novel: Anime
    let chapters: [NovelChapter]
    @State private var index: Int
    @State private var pages: [MangaPage] = []
    @State private var loading = true
    @State private var error: String?
    @State private var chromeHidden = false
    @State private var current = 0
    @State private var scrollPage = 0
    @State private var historyTask: Task<Void, Never>?
    @State private var showBookmarks = false
    @State private var showChapters = false
    @State private var pendingPage: Int?
    @State private var jumpTick = 0
    @ObservedObject private var bms = BookmarkStore.shared
    @State private var showComments = false
    @State private var preloadTask: Task<Void, Never>?
    @State private var titleMode: String
    @State private var prefs: MangaTitlePrefs
    @State private var showSettings = false
    @State private var sliding = false
    @State private var sliderValue = 0.0
    @State private var scroller = AutoScroller()
    @State private var autoOn = false
    @State private var reachedEnd = false
    @State private var autoNote = ""
    @AppStorage("manga.auto.speed") private var autoSpeed = 60.0
    @AppStorage("manga.auto.next") private var autoNext = true
    @AppStorage("manga.mode.default") private var defaultMode = "auto"
    @AppStorage("manga.anim") private var anim = "slide"
    @AppStorage("manga.autobg") private var gAutoBG = false
    @AppStorage("manga.f.dim") private var gDim = 0.0
    @AppStorage("manga.f.warm") private var gWarm = 0.0
    @AppStorage("manga.f.gray") private var gGray = false
    @Environment(\.dismiss) private var dismiss

    init(novel: Anime, chapters: [NovelChapter], start: Int) {
        self.novel = novel
        self.chapters = chapters
        _titleMode = State(initialValue: UserDefaults.standard.string(forKey: "manga.mode.\(novel.id)") ?? "auto")
        let saved = UserDefaults.standard.data(forKey: "manga.tprefs.\(novel.id)")
            .flatMap { try? JSONDecoder().decode(MangaTitlePrefs.self, from: $0) }
        _prefs = State(initialValue: saved ?? MangaTitlePrefs())
        _index = State(initialValue: min(max(start, 0), max(chapters.count - 1, 0)))
    }

    private var own: Bool { prefs.enabled }
    private var effAnim: String { own ? prefs.anim : anim }
    private var effAutoBG: Bool { own ? prefs.autoBG : gAutoBG }
    private var effAutoNext: Bool { own ? prefs.autoNext : autoNext }
    private var effSpeed: Double { own ? prefs.speed : autoSpeed }
    private var effDim: Double { own ? prefs.dim : gDim }
    private var effWarm: Double { own ? prefs.warm : gWarm }
    private var effGray: Bool { own ? prefs.gray : gGray }

    /// Значение читается и пишется либо в свои настройки тайтла, либо в общие.
    private func bind<T>(_ path: WritableKeyPath<MangaTitlePrefs, T>, _ global: Binding<T>) -> Binding<T> {
        Binding(get: { own ? prefs[keyPath: path] : global.wrappedValue },
                set: { v in if own { prefs[keyPath: path] = v } else { global.wrappedValue = v } })
    }

    private var ownBinding: Binding<Bool> {
        Binding(get: { prefs.enabled },
                set: { on in
                    if on && !prefs.enabled {
                        prefs.anim = anim; prefs.autoBG = gAutoBG; prefs.autoNext = autoNext
                        prefs.speed = autoSpeed; prefs.dim = gDim; prefs.warm = gWarm; prefs.gray = gGray
                    }
                    prefs.enabled = on
                })
    }

    private var chapter: NovelChapter? { chapters.indices.contains(index) ? chapters[index] : nil }

    /// Манхву, маньхуа и длинные полосы читаем лентой, обычную мангу листаем.
    private var autoVertical: Bool {
        let t = (novel.type?.title ?? "").lowercased()
        if t.contains("манхв") || t.contains("маньхуа") || t.contains("веб") { return true }
        let r = pages.map { $0.ratio }.filter { $0 > 0 }.sorted()
        if r.isEmpty { return false }
        return r[r.count / 2] > 1.9
    }

    private var shown: Int { vertical ? scrollPage : current }

    private func persistPos() {
        guard let ch = chapter, !loading, !pages.isEmpty, pendingPage == nil else { return }
        let n = min(shown, pages.count)
        let pct = pages.count > 1 ? min(100, n * 100 / (pages.count - 1)) : 0
        ReadPosStore.shared.set(novel.readKey, ReadPos(c: ch.id, p: n, b: 0, pct: pct, t: Int(Date().timeIntervalSince1970)))
    }

    private var vertical: Bool {
        switch titleMode == "auto" ? defaultMode : titleMode {
        case "scroll": return true
        case "pages": return false
        default: return autoVertical
        }
    }

    private func go(_ delta: Int) {
        let n = index + delta
        guard chapters.indices.contains(n) else { return }
        Haptics.tap()
        index = n
    }

    private func turn(_ delta: Int) {
        let n = current + delta
        if n < 0 { return }
        if n > pages.count { return }
        withAnimation(.easeOut(duration: 0.2)) { current = n }
    }

    private func pagesReady() -> Bool {
        guard !pages.isEmpty else { return false }
        let lo = min(max(scrollPage, 0), pages.count - 1)
        let hi = min(lo + 1, pages.count - 1)
        for k in lo...hi {
            let p = pages[k]
            if ImageCache.shared.object(forKey: ImageCache.key(p.url, p.maxPixel)) == nil { return false }
        }
        return true
    }

    private func setAuto(_ on: Bool) {
        autoOn = on
        if on {
            scroller.speed = CGFloat(effSpeed)
            scroller.canAdvance = { !showSettings && !showComments && !showBookmarks && !showChapters && pagesReady() }
            scroller.onEnd = {
                guard reachedEnd else { return false }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    guard autoOn else { return }
                    if effAutoNext && index + 1 < chapters.count {
                        go(1)
                    } else {
                        setAuto(false)
                        chromeHidden = false
                    }
                }
                return true
            }
            scroller.onBlocked = { b in autoNote = b ? "Жду загрузки страниц…" : "" }
            autoNote = ""
            withAnimation(.easeInOut(duration: 0.2)) { chromeHidden = true }
            scroller.start()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if autoOn && scroller.scrollView == nil { autoNote = "Не нашёл ленту для прокрутки" }
            }
        } else {
            scroller.stop()
            autoNote = ""
        }
    }

    private func handleTap(_ x: CGFloat) {
        if vertical && autoOn {
            setAuto(false)
            withAnimation(.easeInOut(duration: 0.2)) { chromeHidden = false }
            return
        }
        if vertical || !Settings.bool("manga.tapzones", true) {
            withAnimation(.easeInOut(duration: 0.2)) { chromeHidden.toggle() }
            return
        }
        if x < 0.3 { turn(-1) }
        else if x > 0.7 { turn(1) }
        else { withAnimation(.easeInOut(duration: 0.2)) { chromeHidden.toggle() } }
    }

    /// Фоновая подгрузка. Декодируются (занимают память) только страницы рядом с текущей:
    /// одна назад и три вперёд. Остальные страницы главы лишь скачиваются в дисковый кэш.
    private func preload(from start: Int) {
        preloadTask?.cancel()
        let list = pages
        guard !list.isEmpty else { return }
        let first = min(max(start, 0), list.count - 1)
        preloadTask = Task {
            // 1. Текущая страница, затем соседние: готовые картинки в памяти.
            _ = await MangaImageStore.shared.image(for: list[first])
            var near: [Int] = []
            for k in 1...3 where first + k < list.count { near.append(first + k) }
            if first > 0 { near.append(first - 1) }
            await withTaskGroup(of: Void.self) { group in
                for id in near { group.addTask { _ = await MangaImageStore.shared.image(for: list[id]) } }
            }
            // 2. Дальше по главе только скачиваем, по три за раз: сначала вперёд, потом назад.
            var rest = Array((first + 4)..<max(first + 4, list.count))
            rest += Array((0..<max(first - 1, 0)).reversed())
            var i = 0
            while i < rest.count {
                if Task.isCancelled { return }
                let chunk = Array(rest[i..<min(i + 3, rest.count)])
                i += 3
                await withTaskGroup(of: Void.self) { group in
                    for id in chunk { group.addTask { await MangaImageStore.shared.warm(list[id]) } }
                }
            }
        }
    }

    @ViewBuilder
    private var pagedView: some View {
        switch effAnim {
        case "book":
            GeometryReader { geo in
                let ref = pages[min(current, max(pages.count - 1, 0))]
                let ratio = ref.ratio > 0 ? ref.ratio : 1.5
                let w0 = geo.size.width
                let h0 = w0 * ratio
                let fitH = min(h0, geo.size.height)
                let fitW = h0 > geo.size.height ? fitH / ratio : w0
                ZStack {
                    Color.black
                        .contentShape(Rectangle())
                        .onTapGesture { handleTap(0.5) }
                    BookPager(count: pages.count + 1, current: $current) { i in
                        i < pages.count
                            ? AnyView(MangaPageView(page: pages[i], dim: 0.9, autoBG: effAutoBG, onTap: handleTap))
                            : AnyView(endCard)
                    }
                    .frame(width: fitW, height: fitH)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        case "fade":
            ZStack {
                if current < pages.count {
                    MangaPageView(page: pages[current], autoBG: effAutoBG, onTap: handleTap)
                        .id(current)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)),
                                                removal: .opacity))
                } else {
                    endCard.id(current).transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: current)
            .gesture(
                DragGesture(minimumDistance: 30).onEnded { v in
                    let dx = v.translation.width
                    guard abs(dx) > 60, abs(dx) > abs(v.translation.height) else { return }
                    turn(dx < 0 ? 1 : -1)
                }
            )
        default:
            TabView(selection: $current) {
                ForEach(pages) { p in
                    MangaPageView(page: p, autoBG: effAutoBG, onTap: handleTap).tag(p.id)
                }
                endCard.tag(pages.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private var endCard: some View {
        VStack(spacing: 14) {
            Text(index + 1 < chapters.count ? "Глава закончилась" : "Это последняя глава")
                .font(.subheadline).foregroundStyle(.white.opacity(0.7))
            if index + 1 < chapters.count {
                Button { go(1) } label: {
                    Label("Следующая глава", systemImage: "chevron.right.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.pressable)
            }
            Button { showComments = true } label: {
                Label("Комментарии к главе", systemImage: "bubble.left.and.bubble.right")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topBar: some View {
        GlassGroup(spacing: 10) {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .liquidGlass(Circle())
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(novel.displayTitle).font(.footnote.bold()).lineLimit(1)
                if let c = chapter {
                    Text("Том \(c.volume) · Глава \(c.number)").font(.caption2).opacity(0.7)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .liquidGlass(Capsule())
            HStack(spacing: 0) {
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 42, height: 46)
                }
                Button { showChapters = true } label: {
                    Image(systemName: "list.bullet").frame(width: 42, height: 46)
                }
                Button { showComments = true } label: {
                    Image(systemName: "bubble.left.and.bubble.right").frame(width: 42, height: 46)
                }
            }
            .padding(.horizontal, 4)
            .liquidGlass(Capsule())
        }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private func seek(_ p: Int) {
        let n = min(max(p, 0), max(pages.count - 1, 0))
        if vertical {
            current = n
            scrollPage = n
            jumpTick += 1
        } else {
            withAnimation(.easeOut(duration: 0.2)) { current = n }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 4) {
            if vertical {
                HStack(spacing: 10) {
                    Button { setAuto(!autoOn) } label: {
                        Image(systemName: autoOn ? "pause.circle.fill" : "play.circle.fill").font(.title2)
                    }
                    Image(systemName: "tortoise.fill").font(.caption)
                    Slider(value: bind(\.speed, $autoSpeed), in: 15...240, step: 5).tint(Theme.accent)
                    Image(systemName: "hare.fill").font(.caption)
                    Text("\(Int(effSpeed))").font(.caption2.monospacedDigit()).frame(width: 28)
                }
                .padding(.horizontal, 16)
                if !autoNote.isEmpty {
                    Text(autoNote).font(.caption2).opacity(0.7)
                }
            }
            if pages.count > 1 {
                Slider(value: $sliderValue, in: 0...Double(pages.count - 1), step: 1) { editing in
                    sliding = editing
                    if !editing { seek(Int(sliderValue)) }
                }
                .tint(Theme.accent)
                .padding(.horizontal, 16)
                .onChange(of: shown) { v in
                    if !sliding { sliderValue = Double(min(v, pages.count - 1)) }
                }
                .onChange(of: pages.count) { _ in
                    sliderValue = Double(min(shown, max(pages.count - 1, 0)))
                }
                .onChange(of: sliderValue) { v in
                    if sliding { Haptics.select() }
                }
            }
            HStack {
                Button { go(-1) } label: { Image(systemName: "backward.end").frame(width: 48, height: 40) }
                    .disabled(index == 0)
                Spacer()
                Text(pages.isEmpty ? "…" : "\(sliding ? Int(sliderValue) + 1 : min(shown + 1, pages.count)) / \(pages.count)")
                    .font(.footnote.monospacedDigit())
                Spacer()
                Button { go(1) } label: { Image(systemName: "forward.end").frame(width: 48, height: 40) }
                    .disabled(index + 1 >= chapters.count)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 6)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .liquidGlass(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
            if !pages.isEmpty {
                if vertical {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(pages) { p in
                                    MangaPageView(page: p, vertical: true, autoBG: effAutoBG, onTap: handleTap)
                                        .id(p.id)
                                        .onAppear { scrollPage = p.id }
                                }
                                endCard.frame(height: 360).id(pages.count)
                                    .onAppear { reachedEnd = true }
                            }
                            .background(ScrollFinder { scroller.scrollView = $0 })
                        }
                        .onAppear {
                            if current > 0 { proxy.scrollTo(current, anchor: .top) }
                        }
                    }
                    .id("v\(index)-\(jumpTick)")
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    pagedView
                        .id("p\(index)-\(effAnim)")
                        .ignoresSafeArea()
                }
            }
            }
            .modifier(GrayIf(on: effGray))
            if effDim > 0.001 {
                Color.black.opacity(effDim).ignoresSafeArea().allowsHitTesting(false)
            }
            if effWarm > 0.001 {
                Color(red: 1, green: 0.6, blue: 0.2).opacity(effWarm * 0.5).ignoresSafeArea().allowsHitTesting(false)
            }
            if loading {
                ProgressView().tint(.white)
            }
            if let e = error {
                VStack(spacing: 10) {
                    Text(e).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                    Button("Повторить") { Task { await load() } }
                }
                .padding(24)
            }

            VStack {
                if !chromeHidden { topBar.transition(.move(edge: .top).combined(with: .opacity)) }
                Spacer()
                if !chromeHidden { bottomBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            if chromeHidden, autoOn, !autoNote.isEmpty {
                VStack {
                    Spacer()
                    Text(autoNote)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.black.opacity(0.5), in: Capsule())
                        .padding(.bottom, 44)
                }
                .allowsHitTesting(false)
            }
            // маленький счётчик страниц, пока меню скрыто
            if chromeHidden, !vertical, !pages.isEmpty, !loading {
                VStack {
                    Spacer()
                    Text("\(min(shown + 1, pages.count)) / \(pages.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Color.black.opacity(0.45), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                        .padding(.bottom, 10)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .onChange(of: shown) { _ in persistPos() }
        .statusBarHidden(chromeHidden)
        .preferredColorScheme(.dark)
        .task(id: index) { await load() }
        .onChange(of: current) { v in
            Haptics.select()
            if !vertical && v < pages.count { preload(from: v) }
        }
        .onChange(of: scrollPage) { v in
            if vertical && v < pages.count { preload(from: v) }
        }
        .onChange(of: vertical) { v in
            if v { scrollPage = current } else { current = min(scrollPage, pages.count) }
            if !v && autoOn { setAuto(false) }
        }
        .onChange(of: effSpeed) { v in scroller.speed = CGFloat(v) }
        .onChange(of: prefs) { v in
            if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: "manga.tprefs.\(novel.id)") }
        }
        .onChange(of: titleMode) { v in
            UserDefaults.standard.set(v, forKey: "manga.mode.\(novel.id)")
        }
        .sheet(isPresented: $showSettings) {
            MangaReaderSettings(titleMode: $titleMode, defaultMode: $defaultMode, own: ownBinding,
                                anim: bind(\.anim, $anim), autoBG: bind(\.autoBG, $gAutoBG),
                                autoNext: bind(\.autoNext, $autoNext), speed: bind(\.speed, $autoSpeed),
                                dim: bind(\.dim, $gDim), warm: bind(\.warm, $gWarm), gray: bind(\.gray, $gGray),
                                detected: autoVertical ? "лента" : "страницы")
        }
        .sheet(isPresented: $showChapters) {
            MangaChapterPicker(chapters: chapters, current: index, readKey: novel.readKey) { i in
                guard i != index else { return }
                Haptics.tap()
                pendingPage = nil
                index = i
            }
        }
        .sheet(isPresented: $showComments) {
            if let c = chapter {
                ChapterCommentsView(novel: novel, chapter: c,
                                    page: min(shown + 1, max(pages.count, 1)), pageCount: pages.count)
            }
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksSheet(titleKey: novel.readKey, titleName: novel.displayTitle, showHighlights: false,
                           onBookmark: { openBookmark($0) }, onHighlight: { _ in })
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = Settings.bool("set.keepAwake", true) }
        .onDisappear {
            persistPos()
            UIApplication.shared.isIdleTimerDisabled = false
            preloadTask?.cancel()
            historyTask?.cancel()
            scroller.stop()
        }
    }

    private var chapterLabel: String {
        chapter.map { "Том \($0.volume) · \($0.title)" } ?? ""
    }

    private var pageBookmark: Bookmark? {
        guard let c = chapter, !pages.isEmpty else { return nil }
        let p = min(shown, pages.count - 1)
        return bms.find(titleKey: novel.readKey, chapterID: c.id, from: p, to: p + 1)
    }

    private func toggleBookmark() {
        guard let c = chapter, !pages.isEmpty else { return }
        if let b = pageBookmark {
            bms.remove(b.id)
            Haptics.tap()
            return
        }
        let p = min(shown, pages.count - 1)
        bms.add(Bookmark(titleKey: novel.readKey, chapterID: c.id, chapterLabel: chapterLabel,
                         position: p, isText: false, snippet: "", note: "", created: Date()))
        Haptics.success()
    }

    private func openBookmark(_ b: Bookmark) {
        guard let ci = chapters.firstIndex(where: { $0.id == b.chapterID }) else { return }
        if ci == index {
            let p = min(max(b.position, 0), max(pages.count - 1, 0))
            if vertical {
                current = p
                scrollPage = p
                jumpTick += 1
            } else {
                withAnimation { current = p }
            }
        } else {
            pendingPage = b.position
            index = ci
        }
    }

    private func scheduleHistory(_ ch: NovelChapter) {
        historyTask?.cancel()
        HistoryStore.current.recordChapter(anime: novel, chapterID: ch.id, title: ch.title)
    }

    private func load() async {
        guard let ch = chapter, let slug = novel.slugUrl else { return }
        preloadTask?.cancel()
        loading = true
        error = nil
        pages = []
        current = 0
        scrollPage = 0
        reachedEnd = false
        if pendingPage == nil, let pos = ReadPosStore.shared.get(novel.readKey), pos.c == ch.id, pos.p > 0 {
            pendingPage = pos.p
        }
        ReadStore.shared.mark(novel.readKey, ch.id)
        SiteSync.view(novelID: novel.id, chapterID: ch.id)
        scheduleHistory(ch)
        do {
            let result = try await MangaService.pages(slug: slug, chapter: ch, novelID: novel.id)
            if Task.isCancelled { return }
            pages = result
            if result.isEmpty {
                error = "У главы нет страниц или она недоступна."
            } else {
                if let pp = pendingPage {
                    current = min(max(pp, 0), result.count - 1)
                    scrollPage = current
                    pendingPage = nil
                }
                preload(from: current)
            }
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Ранобэ: постраничное чтение
enum NovelPage: Identifiable {
    case text(Int, NSAttributedString)
    case image(Int, URL)

    var id: Int {
        switch self {
        case .text(let i, _), .image(let i, _): return i
        }
    }
}

/// Режет текст главы на страницы по размеру экрана средствами TextKit.
enum NovelPaginator {
    static func font(_ size: CGFloat, serif: Bool, bold: Bool = false, italic: Bool = false) -> UIFont {
        var d = UIFont.systemFont(ofSize: size).fontDescriptor
        if serif, let s = d.withDesign(.serif) { d = s }
        var traits = d.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if let t = d.withSymbolicTraits(traits) { d = t }
        return UIFont(descriptor: d, size: size)
    }

    static func split(_ text: NSAttributedString, size: CGSize) -> [NSRange] {
        let storage = NSTextStorage(attributedString: text)
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let ns = text.string as NSString
        var ranges: [NSRange] = []
        var loc = 0
        while loc < text.length && ranges.count < 3000 {
            let tc = NSTextContainer(size: size)
            tc.lineFragmentPadding = 0
            lm.addTextContainer(tc)
            let glyphs = lm.glyphRange(for: tc)
            if glyphs.length == 0 { break }
            var r = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            loc = NSMaxRange(r)
            while r.length > 0 && ns.character(at: r.location) == 10 {
                r.location += 1
                r.length -= 1
            }
            if r.length > 0 { ranges.append(r) }
        }
        return ranges
    }

    static func paginate(blocks: [ReaderBlock], title: String, size: CGSize, fontSize: CGFloat,
                         serif: Bool, lineGap: CGFloat, color: UIColor,
                         bodyAlign: NSTextAlignment = .natural, firstIndent: CGFloat = 0,
                         family: String = "", allBold: Bool = false) -> [NovelPage] {
        let fam = family, ab = allBold
        func font(_ size: CGFloat, serif: Bool, bold: Bool = false, italic: Bool = false) -> UIFont {
            let b = bold || ab
            if !fam.isEmpty, let base = UIFont(name: fam, size: size) {
                var traits = base.fontDescriptor.symbolicTraits
                if b { traits.insert(.traitBold) }
                if italic { traits.insert(.traitItalic) }
                if let d = base.fontDescriptor.withSymbolicTraits(traits) { return UIFont(descriptor: d, size: size) }
                return base
            }
            return NovelPaginator.font(size, serif: serif, bold: b, italic: italic)
        }
        var pages: [NovelPage] = []
        let text = NSMutableAttributedString()

        func style(spacing: CGFloat, before: CGFloat = 0, indent: CGFloat = 0,
                   align: NSTextAlignment = .natural, first: CGFloat = 0) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.lineSpacing = fontSize * lineGap
            p.paragraphSpacing = spacing
            p.paragraphSpacingBefore = before
            p.headIndent = indent
            p.firstLineHeadIndent = indent + first
            p.alignment = align
            p.lineBreakMode = .byWordWrapping
            return p
        }
        func add(_ s: String, _ f: UIFont, _ st: NSParagraphStyle) {
            text.append(NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color, .paragraphStyle: st]))
        }
        var globalBase = 0
        func flush() {
            guard text.length > 0 else { return }
            for r in split(text, size: size) {
                let sub = NSMutableAttributedString(attributedString: text.attributedSubstring(from: r))
                sub.addAttribute(.heheBase, value: globalBase + r.location, range: NSRange(location: 0, length: sub.length))
                pages.append(.text(pages.count, sub))
            }
            globalBase += text.length
            text.deleteCharacters(in: NSRange(location: 0, length: text.length))
        }

        let body = font(fontSize, serif: serif)
        add(title + "\n", font(fontSize + 6, serif: serif, bold: true), style(spacing: fontSize))
        for b in blocks {
            switch b {
            case .paragraph(_, let t):
                add(t + "\n", body, style(spacing: fontSize * 0.6, align: bodyAlign, first: firstIndent))
            case .rich(_, let a):
                let st = style(spacing: fontSize * 0.6, align: bodyAlign, first: firstIndent)
                for run in a.runs {
                    let piece = String(a[run.range].characters)
                    let intent = run.inlinePresentationIntent ?? []
                    let f = font(fontSize, serif: serif, bold: intent.contains(.stronglyEmphasized),
                                 italic: intent.contains(.emphasized))
                    add(piece, f, st)
                }
                add("\n", body, st)
            case .heading(_, let t):
                add(t + "\n", font(fontSize + 4, serif: serif, bold: true),
                    style(spacing: fontSize * 0.6, before: fontSize * 0.6))
            case .quote(_, let t):
                add(t + "\n", font(fontSize, serif: serif, italic: true),
                    style(spacing: fontSize * 0.6, indent: 14))
            case .rule:
                add("* * *\n", body, style(spacing: fontSize * 0.6, align: .center))
            case .image(_, let u):
                flush()
                pages.append(.image(pages.count, u))
            }
        }
        flush()
        return pages
    }
}

extension NSAttributedString.Key {
    /// Смещение первого символа страницы в тексте всей главы (нужно для выделений и закладок).
    static let heheBase = NSAttributedString.Key("hehe.base")
}

/// Накладывает цветные выделения на текст страницы.
func applyHighlights(_ t: NSAttributedString, _ list: [Highlight]) -> NSAttributedString {
    guard !list.isEmpty, t.length > 0,
          let base = t.attribute(.heheBase, at: 0, effectiveRange: nil) as? Int else { return t }
    let m = NSMutableAttributedString(attributedString: t)
    let page = NSRange(location: base, length: t.length)
    for h in list {
        let r = NSIntersectionRange(page, NSRange(location: h.start, length: h.length))
        guard r.length > 0 else { continue }
        let local = NSRange(location: r.location - base, length: r.length)
        m.addAttribute(.backgroundColor, value: h.uiColor, range: local)
        if !h.note.isEmpty {
            m.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: local)
        }
    }
    return m
}

extension NovelPage {
    var plainText: String {
        if case .text(_, let t) = self { return t.string }
        return ""
    }
}

final class PageTextUIView: UIView {
    var text = NSAttributedString() {
        didSet { setNeedsDisplay() }
    }
    /// Долгое нажатие: диапазон абзаца внутри страницы и его текст.
    var onLongPress: ((NSRange, String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        let g = UILongPressGestureRecognizer(target: self, action: #selector(handleLong(_:)))
        g.minimumPressDuration = 0.5
        addGestureRecognizer(g)
    }

    @objc private func handleLong(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let cb = onLongPress, text.length > 0 else { return }
        let storage = NSTextStorage(attributedString: text)
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let tc = NSTextContainer(size: CGSize(width: bounds.width, height: 100_000))
        tc.lineFragmentPadding = 0
        lm.addTextContainer(tc)
        lm.ensureLayout(for: tc)
        let idx = lm.characterIndex(for: g.location(in: self), in: tc, fractionOfDistanceBetweenInsertionPoints: nil)
        let ns = text.string as NSString
        guard idx < ns.length else { return }
        var r = ns.paragraphRange(for: NSRange(location: idx, length: 0))
        while r.length > 0, ns.character(at: NSMaxRange(r) - 1) == 10 { r.length -= 1 }
        guard r.length > 0 else { return }
        cb(r, ns.substring(with: r))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let storage = NSTextStorage(attributedString: text)
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let tc = NSTextContainer(size: CGSize(width: bounds.width, height: 100_000))
        tc.lineFragmentPadding = 0
        lm.addTextContainer(tc)
        let r = lm.glyphRange(for: tc)
        lm.drawBackground(forGlyphRange: r, at: .zero)
        lm.drawGlyphs(forGlyphRange: r, at: .zero)
    }
}

struct PageText: UIViewRepresentable {
    let text: NSAttributedString
    var onLongPress: ((NSRange, String) -> Void)? = nil

    func makeUIView(context: Context) -> PageTextUIView {
        let v = PageTextUIView()
        v.text = text
        v.onLongPress = onLongPress
        return v
    }

    func updateUIView(_ v: PageTextUIView, context: Context) {
        v.onLongPress = onLongPress
        if !v.text.isEqual(to: text) { v.text = text }
    }
}

/// Одна страница книги: текст или иллюстрация на фоне темы, с номером внизу.
struct NovelPageCard: View {
    let page: NovelPage
    let number: Int
    let total: Int
    let bg: Color
    let fg: Color
    let margins: UIEdgeInsets
    let onTap: (CGFloat) -> Void
    var highlights: [Highlight] = []
    var onLongPress: ((NSRange, String) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width - margins.left - margins.right
            let h = geo.size.height - margins.top - margins.bottom
            ZStack {
                bg
                Group {
                    switch page {
                    case .text(_, let t):
                        PageText(text: applyHighlights(t, highlights), onLongPress: { local, str in
                            let base = (t.attribute(.heheBase, at: 0, effectiveRange: nil) as? Int) ?? 0
                            onLongPress?(NSRange(location: base + local.location, length: local.length), str)
                        })
                    case .image(_, let u):
                        FitImage(url: u)
                    }
                }
                .frame(width: w, height: h, alignment: .topLeading)
                .position(x: margins.left + w / 2, y: margins.top + h / 2)

                Text("\(number) / \(total)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(fg.opacity(0.45))
                    .position(x: geo.size.width / 2, y: geo.size.height - max(margins.bottom / 2 - 12, 20))
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { v in onTap(v.location.x / max(geo.size.width, 1)) })
        }
        .ignoresSafeArea()
    }
}

// MARK: - Ранобэ: читалка
func readerPalette(_ id: String) -> (bg: UIColor, fg: UIColor) {
    switch id {
    case "sepia": return (UIColor(red: 0.96, green: 0.93, blue: 0.85, alpha: 1), UIColor(red: 0.23, green: 0.18, blue: 0.18, alpha: 1))
    case "light": return (.white, UIColor(white: 0.1, alpha: 1))
    case "black": return (.black, UIColor(white: 0.85, alpha: 1))
    case "quiet": return (UIColor(white: 0.27, alpha: 1), UIColor(white: 0.72, alpha: 1))
    case "paper": return (UIColor(white: 0.93, alpha: 1), UIColor(white: 0.12, alpha: 1))
    case "accent": return (.white, .black)
    case "focus": return (UIColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1), UIColor(white: 0.1, alpha: 1))
    default: return (UIColor(white: 0.07, alpha: 1), UIColor(white: 0.9, alpha: 1))
    }
}

func readerThemeIsDark(_ id: String) -> Bool { id == "dark" || id == "black" || id == "quiet" }

/// Панель «Темы и настройки» в стиле Apple Books.
struct NovelReaderSettings: View {
    @Binding var fontSize: Double
    @Binding var lineGap: Double
    @Binding var serif: Bool
    @Binding var family: String
    @Binding var bold: Bool
    @Binding var theme: String
    @Binding var margin: Double
    @Binding var justify: Bool
    @Binding var indent: Bool
    @Binding var dim: Double
    @Binding var warm: Double
    @Binding var mode: String
    @Binding var anim: String
    let activeTheme: String
    let canSearch: Bool
    let downloaded: Bool
    let onSearch: () -> Void
    let onBookmarks: () -> Void
    let onDownload: () -> Void

    struct Snap {
        var fs = 18.0, lg = 0.4, serif = true, family = "", bold = false, margin = 24.0
        var justify = false, indent = false, theme = "dark", mode = "pages", anim = "book"
        var dim = 0.0, warm = 0.0
    }

    @State private var lg = 0.4
    @State private var mg = 24.0
    @State private var brightness = Double(UIScreen.main.brightness)
    @State private var showCustom = false
    @State private var layoutOn = false
    @State private var snap = Snap()
    @Environment(\.dismiss) private var dismiss

    private var isDark: Bool { readerThemeIsDark(activeTheme) }
    private var boldOn: Bool { bold || activeTheme == "accent" }
    private let glass = Color.primary.opacity(0.08)

    private let tiles: [(id: String, title: String, serif: Bool, bold: Bool)] = [
        ("light", "Оригинал", false, false), ("quiet", "Тишина", true, false), ("paper", "Бумага", false, false),
        ("accent", "Акцент", false, true), ("sepia", "Покой", true, false), ("focus", "Фокус", true, false)
    ]

    private let fonts: [(id: String, title: String)] = [
        ("orig", "Исходный"), ("sans", "Без засечек"), ("Georgia", "Georgia"), ("Palatino-Roman", "Palatino"),
        ("IowanOldStyle-Roman", "Iowan Old Style"), ("Charter-Roman", "Charter"), ("AvenirNext-Regular", "Avenir Next")
    ]

    // MARK: главная панель

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Button { dismiss() } label: { roundIcon("xmark") }.buttonStyle(.plain)
                Text("Темы и настройки").font(.headline)
                Spacer()
            }

            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    Button { step(-1) } label: {
                        Text("A").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    Divider().frame(height: 28)
                    Button { step(1) } label: {
                        Text("A").font(.system(size: 28, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 50)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .background(glass, in: Capsule())

                HStack(spacing: 0) {
                    modeMenu
                    appearanceMenu
                }
                .frame(width: 150)
                .background(glass, in: Capsule())
            }

            HStack(spacing: 12) {
                Image(systemName: "sun.min").font(.system(size: 15))
                Slider(value: $brightness, in: 0.02...1).tint(.primary)
                Image(systemName: "sun.max").font(.system(size: 21))
            }
            .foregroundStyle(.primary)
            .onChange(of: brightness) { v in UIScreen.main.brightness = CGFloat(v) }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(tiles, id: \.id) { tile($0) }
            }

            Button {
                snap = Snap(fs: fontSize, lg: lineGap, serif: serif, family: family, bold: bold, margin: margin,
                            justify: justify, indent: indent, theme: theme, mode: mode, anim: anim,
                            dim: dim, warm: warm)
                showCustom = true
            } label: {
                Label("Настроить", systemImage: "gearshape")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(.primary)
                    .background(glass, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(isDark ? .dark : .light)
        .presentationDetents([.height(610)])
        .presentationDragIndicator(.hidden)
        .onAppear { lg = lineGap; mg = margin }
        .sheet(isPresented: $showCustom) { customize }
    }

    private func roundIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 46, height: 46)
            .glassShape(Circle())
    }

    private func step(_ d: Double) {
        let v = min(34, max(12, fontSize + d))
        if v != fontSize { fontSize = v; Haptics.select() }
    }

    private func tile(_ t: (id: String, title: String, serif: Bool, bold: Bool)) -> some View {
        let p = readerPalette(t.id)
        let on = activeTheme == t.id
        return Button {
            Haptics.select()
            theme = t.id
        } label: {
            VStack(spacing: 4) {
                Text("Aa").font(.system(size: 40, weight: t.bold ? .bold : .regular, design: t.serif ? .serif : .default))
                Text(t.title).font(.system(size: 15, weight: .medium, design: t.serif ? .serif : .default))
            }
            .foregroundStyle(Color(p.fg))
            .frame(maxWidth: .infinity, minHeight: 112)
            .background(Color(p.bg), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary, lineWidth: on ? 3.5 : 0))
        }
        .buttonStyle(.plain)
    }

    private var modeMenu: some View {
        Menu {
            Picker("Режим чтения", selection: $mode) {
                Label("Горизонтально", systemImage: "rectangle.split.2x1").tag("pages")
                Label("Вертикально", systemImage: "rectangle.split.1x2").tag("scroll")
            }
            if mode == "pages" {
                Menu {
                    Picker("Листание", selection: $anim) {
                        Text("Сдвиг").tag("slide")
                        Text("Плавно").tag("fade")
                        Text("Как в книге").tag("book")
                    }
                } label: {
                    Label("Анимация листания", systemImage: "book")
                }
            }
        } label: {
            Image(systemName: "doc.plaintext")
                .font(.system(size: 22))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
    }

    private var appearance: String {
        switch theme {
        case "auto", "ambient", "black": return theme
        case "dark", "quiet": return "dark"
        default: return "light"
        }
    }

    private var appearanceIcon: String {
        switch appearance {
        case "dark", "black": return "moon.stars"
        case "auto": return "circle.lefthalf.filled"
        case "ambient": return "sun.max"
        default: return "sunrise"
        }
    }

    private var appearanceMenu: some View {
        Menu {
            Picker("Оформление", selection: Binding(get: { appearance }, set: { v in
                switch v {
                case "light":
                    if readerThemeIsDark(theme) || theme == "auto" || theme == "ambient" { theme = "light" }
                case "dark":
                    if theme != "quiet" { theme = "dark" }
                default:
                    theme = v
                }
            })) {
                Label("Светлая", systemImage: "sunrise").tag("light")
                Label("Тёмная", systemImage: "moon.stars").tag("dark")
                Label("Чёрная (AMOLED)", systemImage: "moon.fill").tag("black")
                Label("Как на устройстве", systemImage: "circle.lefthalf.filled").tag("auto")
                Label("Как вокруг", systemImage: "sun.max").tag("ambient")
            }
        } label: {
            Image(systemName: appearanceIcon)
                .font(.system(size: 22))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
    }

    // MARK: экран «Настройка темы»

    private var fontChoice: Binding<String> {
        Binding(get: { family.isEmpty ? (serif ? "orig" : "sans") : family },
                set: { v in
                    switch v {
                    case "orig": serif = true; family = ""
                    case "sans": serif = false; family = ""
                    default: family = v
                    }
                })
    }

    private var fontTitle: String { fonts.first { $0.id == fontChoice.wrappedValue }?.title ?? "Исходный" }

    private func previewFont(_ size: CGFloat) -> Font {
        let w: Font.Weight = boldOn ? .semibold : .regular
        if !family.isEmpty { return Font.custom(family, size: size).weight(w) }
        return .system(size: size, weight: w, design: serif ? .serif : .default)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.title3.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func toggleRow(_ title: String, icon: String? = nil, _ on: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            if let icon { Image(systemName: icon).font(.system(size: 18, weight: .semibold)).frame(width: 26) }
            Toggle(title, isOn: on).tint(Theme.accent)
        }
        .font(.system(size: 17))
        .frame(minHeight: 54)
    }

    private func sliderRow(_ title: String, _ v: Binding<Double>, _ range: ClosedRange<Double>, step: Double? = nil,
                           _ fmt: String, commit: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 16))
                Spacer()
                Text(fmt).font(.system(size: 15).monospacedDigit()).foregroundStyle(.secondary)
            }
            if let step {
                Slider(value: v, in: range, step: step) { if !$0 { commit?() } }.tint(Theme.accent)
            } else {
                Slider(value: v, in: range) { if !$0 { commit?() } }.tint(Theme.accent)
            }
        }
        .padding(.vertical, 10)
    }

    private func actionRow(_ title: String, _ icon: String, enabled: Bool = true, tint: Color = .primary,
                           _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).frame(width: 26)
                Text(title).font(.system(size: 17))
                Spacer()
            }
            .foregroundStyle(enabled ? tint : Color.secondary)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func restore() {
        fontSize = snap.fs; lineGap = snap.lg; serif = snap.serif; family = snap.family; bold = snap.bold
        margin = snap.margin; justify = snap.justify; indent = snap.indent; theme = snap.theme
        mode = snap.mode; anim = snap.anim; dim = snap.dim; warm = snap.warm
        lg = snap.lg; mg = snap.margin
    }

    private func reset() {
        fontSize = 18; lineGap = 0.4; serif = true; family = ""; bold = false
        margin = 24; justify = false; indent = false; theme = "auto"
        dim = 0; warm = 0
        lg = 0.4; mg = 24
    }

    private var customize: some View {
        let p = readerPalette(activeTheme)
        return VStack(spacing: 0) {
            ZStack {
                Text("Настройка темы").font(.headline)
                HStack {
                    Button { restore(); showCustom = false } label: { roundIcon("xmark") }.buttonStyle(.plain)
                    Spacer()
                    Button { showCustom = false } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(Color(.systemBackground))
                            .frame(width: 46, height: 46)
                            .background(Color.primary, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aa").font(.system(size: 46, weight: .bold)).padding(.leading, 4)
                        Text("Жизнь — странная штука, однако: никогда не знаешь, чего от нее ждать… Достаточно подружиться с одной красавицей, как все твои лучшие друзья в одночасье")
                            .font(previewFont(min(CGFloat(fontSize), 24)))
                            .lineSpacing(min(CGFloat(fontSize), 24) * CGFloat(lg))
                            .foregroundStyle(Color(p.fg))
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .topLeading)
                            .background(Color(p.bg), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .clipped()
                    }

                    sectionTitle("Текст")
                    card {
                        Menu {
                            Picker("Шрифт", selection: fontChoice) {
                                ForEach(fonts, id: \.id) { Text($0.title).tag($0.id) }
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Text("Aa").font(.system(size: 18, weight: .semibold)).frame(width: 26)
                                Text("Шрифт").font(.system(size: 17))
                                Spacer()
                                Text(fontTitle).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.primary)
                            .frame(minHeight: 54)
                        }
                        Divider().padding(.leading, 40)
                        toggleRow("Жирный шрифт", icon: "bold", $bold)
                    }

                    sectionTitle("Универсальный доступ и макет")
                    card {
                        toggleRow("Настроить", $layoutOn.animation())
                        if layoutOn {
                            Divider()
                            sliderRow("Межстрочный интервал", $lg, 0.15...0.9, "\(Int(lg * 100))%") { lineGap = lg }
                            Divider()
                            sliderRow("Поля", $mg, 8...48, step: 2, "\(Int(mg))") { margin = mg }
                            Divider()
                            toggleRow("Выравнивание по ширине", $justify)
                            Divider()
                            toggleRow("Красная строка", $indent)
                        }
                    }
                    if layoutOn {
                        Text("Выравнивание и красная строка работают при горизонтальном чтении.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                            .offset(y: -10)
                    }

                    sectionTitle("Режим чтения")
                    card {
                        VStack(spacing: 12) {
                            Picker("", selection: $mode) {
                                Text("Горизонтально").tag("pages")
                                Text("Вертикально").tag("scroll")
                            }
                            .pickerStyle(.segmented)
                            if mode == "pages" {
                                Picker("", selection: $anim) {
                                    Text("Сдвиг").tag("slide")
                                    Text("Плавно").tag("fade")
                                    Text("Как в книге").tag("book")
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        .padding(.vertical, 14)
                    }

                    sectionTitle("Экран")
                    card {
                        sliderRow("Затемнение", $dim, 0...0.7, "\(Int(dim * 100))%")
                        Divider()
                        sliderRow("Тёплый свет", $warm, 0...0.5, "\(Int(warm * 200))%")
                    }

                    sectionTitle("Глава")
                    card {
                        actionRow("Поиск по главе", "magnifyingglass", enabled: canSearch) {
                            showCustom = false
                            onSearch()
                        }
                        Divider().padding(.leading, 40)
                        actionRow("Закладки и заметки", "bookmark") {
                            showCustom = false
                            onBookmarks()
                        }
                        Divider().padding(.leading, 40)
                        actionRow(downloaded ? "Удалить главу с телефона" : "Скачать главу",
                                  downloaded ? "trash" : "arrow.down.circle",
                                  tint: downloaded ? .red : .primary) {
                            onDownload()
                            Haptics.tap()
                        }
                    }

                    Button(role: .destructive) { reset() } label: {
                        Text("Сбросить тему")
                            .font(.system(size: 17))
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 16)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .preferredColorScheme(isDark ? .dark : .light)
        .presentationDetents([.large])
    }
}

/// Номер видимого абзаца в ленте ранобэ (ссылочный тип, чтобы не вызывать перерисовку).
final class BlockTracker {
    var value = -1
    var pending: DispatchWorkItem?
    func reset() { pending?.cancel(); pending = nil; value = -1 }
}

struct NovelReaderView: View {
    let novel: Anime
    let chapters: [NovelChapter]
    @State private var index: Int
    @State private var blocks: [ReaderBlock] = []
    @State private var loading = true
    @State private var error: String?
    @State private var debug = ""
    @AppStorage("reader.font") private var fontSize = 18.0
    @AppStorage("reader.theme") private var theme = "dark"
    @AppStorage("reader.serif") private var serif = true
    @AppStorage("reader.family") private var family = ""
    @AppStorage("reader.bold") private var bold = false
    @AppStorage("reader.lh") private var lineGap = 0.4
    @AppStorage("reader.margin") private var margin = 24.0
    @AppStorage("reader.justify") private var justify = false
    @AppStorage("reader.indent") private var indentOn = false
    @AppStorage("reader.dim") private var dimV = 0.0
    @AppStorage("reader.warm") private var warmV = 0.0
    @State private var showReaderSettings = false
    @AppStorage("novel.mode") private var mode = "pages"
    @State private var historyTask: Task<Void, Never>?
    @State private var showBookmarks = false
    @State private var showSearch = false
    @State private var pendingSel: ReaderSelection?
    @State private var noteFor: NoteRequest?
    @State private var lastLongPress = Date.distantPast
    @State private var pendingOffset: Int?
    @State private var restoreBlock: Int?
    /// Видимый абзац хранится вне состояния экрана: его смена не пересчитывает всю читалку.
    @State private var blockTracker = BlockTracker()
    private var visibleBlock: Int { blockTracker.value }
    @State private var hlRev = 0
    @ObservedObject private var bms = BookmarkStore.shared
    @ObservedObject private var hls = HighlightStore.shared
    @AppStorage("novel.anim") private var novelAnim = "book"
    @State private var pages: [NovelPage] = []
    @State private var pageIndex = 0
    @State private var paginating = false
    @State private var chromeHidden = false
    @ObservedObject private var store = OfflineStore.shared
    @Environment(\.dismiss) private var dismiss

    init(novel: Anime, chapters: [NovelChapter], start: Int) {
        self.novel = novel
        self.chapters = chapters
        _index = State(initialValue: min(max(start, 0), max(chapters.count - 1, 0)))
    }

    private var activeTheme: String {
        if theme == "ambient" { return UIScreen.main.brightness < 0.35 ? "dark" : "light" }
        if theme == "auto" {
            switch UserDefaults.standard.string(forKey: "set.theme") ?? "system" {
            case "light": return "light"
            case "dark": return "dark"
            default: return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
            }
        }
        return theme
    }

    private var bg: Color { Color(readerPalette(activeTheme).bg) }
    private var fg: Color { Color(readerPalette(activeTheme).fg) }

    private var readMinutes: Int {
        var n = 0
        for b in blocks {
            switch b {
            case .paragraph(_, let t), .heading(_, let t), .quote(_, let t):
                n += t.split(separator: " ").count
            case .rich(_, let t):
                n += String(t.characters).split(separator: " ").count
            default:
                break
            }
        }
        return max(1, Int((Double(n) / 180).rounded()))
    }

    private var boldOn: Bool { bold || activeTheme == "accent" }
    private func rf(_ size: CGFloat, heavy: Bool = false) -> Font {
        let w: Font.Weight = heavy ? .bold : (boldOn ? .semibold : .regular)
        if !family.isEmpty { return Font.custom(family, size: size).weight(w) }
        return .system(size: size, weight: w, design: serif ? .serif : .default)
    }
    private var bodyFont: Font { rf(fontSize) }

    private var fgUI: UIColor { readerPalette(activeTheme).fg }

    private var windowInsets: UIEdgeInsets {
        let w = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        return w?.safeAreaInsets ?? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
    }

    private func pageMargins() -> UIEdgeInsets {
        let ins = windowInsets
        return UIEdgeInsets(top: ins.top + 58, left: CGFloat(margin), bottom: ins.bottom + 76, right: CGFloat(margin))
    }

    private func textSize(_ full: CGSize, _ m: UIEdgeInsets) -> CGSize {
        CGSize(width: max(full.width - m.left - m.right, 50), height: max(full.height - m.top - m.bottom, 50))
    }

    private func turn(_ delta: Int) {
        let n = pageIndex + delta
        guard n >= 0, n <= pages.count else { return }
        withAnimation(.easeOut(duration: 0.2)) { pageIndex = n }
    }

    private func handleTap(_ x: CGFloat) {
        // после долгого нажатия палец отпускается: этот «тап» игнорируем
        if Date().timeIntervalSince(lastLongPress) < 0.8 { return }
        if x < 0.3 { turn(-1) }
        else if x > 0.7 { turn(1) }
        else { withAnimation(.easeInOut(duration: 0.2)) { chromeHidden.toggle() } }
    }

    private var chapterID: Int { chapters.indices.contains(index) ? chapters[index].id : 0 }

    /// Абзац показался на экране: запоминаем его и сохраняем позицию с небольшой паузой.
    private func blockSeen(_ id: Int) {
        guard blockTracker.value != id else { return }
        blockTracker.value = id
        blockTracker.pending?.cancel()
        let work = DispatchWorkItem { persistPos() }
        blockTracker.pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Запоминает место в главе: страницы (смещение в тексте) или прокрутка (номер блока).
    private func persistPos() {
        guard chapters.indices.contains(index), !loading, !paginating else { return }
        let now = Int(Date().timeIntervalSince1970)
        if mode == "pages" {
            guard pendingOffset == nil, !pages.isEmpty, let r = pageRange(pageIndex) else { return }
            let pct = pages.count > 1 ? min(100, pageIndex * 100 / (pages.count - 1)) : 0
            ReadPosStore.shared.set(novel.readKey, ReadPos(c: chapterID, p: r.0, b: 0, pct: pct, t: now))
        } else {
            guard restoreBlock == nil, visibleBlock >= 0, !blocks.isEmpty else { return }
            let b = max(visibleBlock - 3, 0)
            let pct = min(100, b * 100 / max(blocks.count - 1, 1))
            ReadPosStore.shared.set(novel.readKey, ReadPos(c: chapterID, p: 0, b: b, pct: pct, t: now))
        }
    }

    private var chapterLabel: String {
        chapters.indices.contains(index) ? "Том \(chapters[index].volume) · \(chapters[index].title)" : ""
    }

    /// Диапазон символов главы, который занимает страница.
    private func pageRange(_ i: Int) -> (Int, Int)? {
        guard i >= 0, i < pages.count, case .text(_, let t) = pages[i], t.length > 0,
              let b = t.attribute(.heheBase, at: 0, effectiveRange: nil) as? Int else { return nil }
        return (b, b + t.length)
    }

    private func pageFor(offset: Int) -> Int? {
        for i in 0..<pages.count {
            if let r = pageRange(i), offset >= r.0, offset < r.1 { return i }
        }
        return nil
    }

    private var currentBookmark: Bookmark? {
        guard let r = pageRange(pageIndex) else { return nil }
        return bms.find(titleKey: novel.readKey, chapterID: chapterID, from: r.0, to: r.1)
    }

    private func toggleBookmark() {
        guard let r = pageRange(pageIndex), case .text(_, let t) = pages[pageIndex] else {
            Haptics.tap()
            return
        }
        if let b = currentBookmark {
            bms.remove(b.id)
            Haptics.tap()
            return
        }
        let snip = String(t.string.trimmingCharacters(in: .whitespacesAndNewlines).prefix(110))
        bms.add(Bookmark(titleKey: novel.readKey, chapterID: chapterID, chapterLabel: chapterLabel,
                         position: r.0, isText: true, snippet: snip, note: "", created: Date()))
        Haptics.success()
    }

    private func jumpTo(offset: Int, chapterID cid: Int) {
        guard let ci = chapters.firstIndex(where: { $0.id == cid }) else { return }
        if mode != "pages" { mode = "pages" }
        if ci == index {
            if let p = pageFor(offset: offset) { withAnimation { pageIndex = p } }
        } else {
            pendingOffset = offset
            index = ci
        }
    }

    private func handleLong(_ r: NSRange, _ text: String) {
        lastLongPress = Date()
        Haptics.bump()
        pendingSel = ReaderSelection(range: r, text: text)
    }

    private func applyHighlight(_ sel: ReaderSelection, color: Int) {
        hls.set(titleKey: novel.readKey, chapterID: chapterID, label: chapterLabel,
                range: sel.range, snippet: sel.text, color: color, note: nil)
        hlRev += 1
        Haptics.success()
    }

    private func removeHighlight(_ sel: ReaderSelection) {
        if let h = hls.exact(novel.readKey, chapterID, sel.range) {
            hls.remove(h.id)
            hlRev += 1
        }
    }

    private func openNote(_ sel: ReaderSelection) {
        let existing = hls.exact(novel.readKey, chapterID, sel.range)
        let key = novel.readKey, cid = chapterID, label = chapterLabel
        noteFor = NoteRequest(title: String(sel.text.prefix(140)), initial: existing?.note ?? "") { text in
            hls.set(titleKey: key, chapterID: cid, label: label, range: sel.range, snippet: sel.text,
                    color: existing?.color ?? 0, note: text)
            hlRev += 1
        }
    }

    private func paginate(_ full: CGSize) async {
        guard !loading, !blocks.isEmpty, chapters.indices.contains(index), full.width > 100 else {
            pages = []
            return
        }
        paginating = true
        let m = pageMargins()
        let size = textSize(full, m)
        let list = blocks
        let title = chapters[index].title
        let fs = CGFloat(fontSize), sf = serif, lg = CGFloat(lineGap), col = fgUI
        let al: NSTextAlignment = justify ? .justified : .natural
        let ind: CGFloat = indentOn ? CGFloat(fontSize) * 1.4 : 0
        let fam = family, ab = boldOn
        let result = await Task.detached(priority: .userInitiated) {
            NovelPaginator.paginate(blocks: list, title: title, size: size, fontSize: fs,
                                    serif: sf, lineGap: lg, color: col, bodyAlign: al, firstIndent: ind,
                                    family: fam, allBold: ab)
        }.value
        if Task.isCancelled { return }
        let old = pages.count
        pages = result
        pageIndex = old > 0 ? min(Int(Double(pageIndex) / Double(old) * Double(result.count)), max(result.count - 1, 0)) : 0
        if let off = pendingOffset {
            if let p = pageFor(offset: off) { pageIndex = p }
            pendingOffset = nil
        }
        paginating = false
    }

    private var endPage: some View {
        VStack(spacing: 16) {
            Text(index + 1 < chapters.count ? "Глава закончилась" : "Это последняя глава")
                .font(.subheadline).opacity(0.7)
            if index + 1 < chapters.count {
                Button { Haptics.tap(); index += 1 } label: {
                    Text("Следующая глава")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.pressable)
            }
        }
        .foregroundStyle(fg)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg.ignoresSafeArea())
    }

    @ViewBuilder
    private func pageContent(_ i: Int, margins m: UIEdgeInsets) -> some View {
        if i < pages.count {
            NovelPageCard(page: pages[i], number: i + 1, total: pages.count, bg: bg, fg: fg,
                          margins: m, onTap: handleTap,
                          highlights: hls.forChapter(novel.readKey, chapterID),
                          onLongPress: { r, s in handleLong(r, s) })
        } else {
            endPage
        }
    }

    @ViewBuilder
    private var pagedBody: some View {
        GeometryReader { geo in
            let m = pageMargins()
            ZStack {
                bg
                if loading || paginating {
                    ProgressView()
                } else if let e = error {
                    Text(e).font(.footnote).foregroundStyle(.orange).padding(24)
                } else if !pages.isEmpty {
                    let count = pages.count + 1
                    switch novelAnim {
                    case "book":
                        BookPager(count: count, current: $pageIndex, backColor: UIColor(bg),
                                  themedBack: true) { i in AnyView(pageContent(i, margins: m)) }
                    case "fade":
                        ZStack {
                            pageContent(pageIndex, margins: m)
                                .id(pageIndex)
                                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.03)),
                                                        removal: .opacity))
                        }
                        .animation(.easeInOut(duration: 0.25), value: pageIndex)
                        .gesture(
                            DragGesture(minimumDistance: 30).onEnded { v in
                                let dx = v.translation.width
                                guard abs(dx) > 60, abs(dx) > abs(v.translation.height) else { return }
                                turn(dx < 0 ? 1 : -1)
                            }
                        )
                    default:
                        TabView(selection: $pageIndex) {
                            ForEach(0..<count, id: \.self) { i in
                                pageContent(i, margins: m).tag(i)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .id("\(index)-\(novelAnim)-\(activeTheme)-\(hlRev)")
            .task(id: "\(index)-\(loading)-\(blocks.count)-\(fontSize)-\(serif)-\(family)-\(boldOn)-\(lineGap)-\(margin)-\(justify)-\(indentOn)-\(activeTheme)-\(Int(geo.size.width))x\(Int(geo.size.height))") {
                await paginate(geo.size)
            }
        }
        .ignoresSafeArea()
        .onAppear { if mode == "pages" { chromeHidden = true } }
    }

    @ViewBuilder
    private func blockView(_ b: ReaderBlock) -> some View {
        switch b {
        case .paragraph(_, let t):
            Text(t).font(bodyFont).lineSpacing(fontSize * lineGap)
        case .rich(_, let t):
            Text(t).font(bodyFont).lineSpacing(fontSize * lineGap)
        case .heading(_, let t):
            Text(t).font(rf(fontSize + 4, heavy: true))
        case .quote(_, let t):
            Text(t).font(bodyFont.italic()).lineSpacing(fontSize * lineGap)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.accent).frame(width: 3) }
        case .image(_, let u):
            FitImage(url: u).frame(maxWidth: .infinity)
        case .rule:
            Divider()
        }
    }

    var body: some View {
        NavigationStack {
            Group {
            if mode == "scroll" {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: fontSize * (0.5 + lineGap)) {
                        Color.clear.frame(height: 1).id("top")
                        if chapters.indices.contains(index) {
                            Text(chapters[index].title)
                                .font(rf(fontSize + 6, heavy: true))
                        }
                        if !loading && !blocks.isEmpty {
                            Text("≈ \(readMinutes) мин чтения")
                                .font(.caption)
                                .opacity(0.55)
                        }
                        if loading { ProgressView().frame(maxWidth: .infinity).padding(.top, 40) }
                        ForEach(blocks) { b in blockView(b).id(b.id).onAppear { blockSeen(b.id) } }
                        if let e = error {
                            Text(e).font(.footnote).foregroundStyle(.orange)
                        }
                        if !debug.isEmpty {
                            Text(debug)
                                .font(.system(size: 9, design: .monospaced))
                                .textSelection(.enabled)
                                .opacity(0.6)
                        }
                        if !loading, index < chapters.count - 1 {
                            Button {
                                index += 1
                            } label: {
                                Text("Следующая глава")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Theme.accent.opacity(0.25), in: Capsule())
                            }
                            .padding(.top, 16)
                        }
                        Color.clear.frame(height: 90)
                    }
                    .frame(maxWidth: 700, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, CGFloat(margin))
                    .padding(.top, 8)
                    .foregroundStyle(fg)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { chromeHidden.toggle() } }
                }
                .background(bg.ignoresSafeArea())
                .onChange(of: index) { _ in proxy.scrollTo("top", anchor: .top) }
                .onChange(of: loading) { l in
                    if !l, let b = restoreBlock {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            proxy.scrollTo(b, anchor: .top)
                            restoreBlock = nil
                        }
                    }
                }
            }
            } else {
                pagedBody
            }
            }
            .task(id: index) { await load() }
            .overlay {
                if !chromeHidden {
                    VStack(spacing: 0) {
                        EdgeBlur(top: true, height: windowInsets.top + 64)
                        Spacer(minLength: 0)
                        EdgeBlur(top: false, height: windowInsets.bottom + 84)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !chromeHidden {
                HStack {
                    Button { Haptics.tap(); index -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 40) }
                        .disabled(index <= 0)
                    Spacer()
                    Text("\(index + 1) из \(chapters.count)").font(.footnote.weight(.semibold))
                    Spacer()
                    Button { Haptics.tap(); index += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 40) }
                        .disabled(index >= chapters.count - 1)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .liquidGlass(Capsule())
                .foregroundStyle(fg)
                .padding(.horizontal, 24).padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .toolbar(chromeHidden ? .hidden : .visible, for: .navigationBar)
            .onChange(of: pageIndex) { _ in persistPos() }
            .statusBarHidden(chromeHidden)
            .navigationTitle(novel.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(readerThemeIsDark(activeTheme) ? .dark : .light, for: .navigationBar)
            .modifier(ReaderBarBackground())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if mode == "pages" {
                        Button { toggleBookmark() } label: {
                            Image(systemName: currentBookmark == nil ? "bookmark" : "bookmark.fill")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showReaderSettings = true } label: { Image(systemName: "textformat.size") }
                }
            }
        }
        .preferredColorScheme(readerThemeIsDark(activeTheme) ? .dark : .light)
        .overlay {
            ZStack {
                if dimV > 0.001 { Color.black.opacity(dimV).ignoresSafeArea() }
                if warmV > 0.001 { Color(red: 1, green: 0.6, blue: 0.2).opacity(warmV * 0.5).ignoresSafeArea() }
            }
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $showReaderSettings) {
            NovelReaderSettings(fontSize: $fontSize, lineGap: $lineGap, serif: $serif, family: $family,
                                bold: $bold, theme: $theme, margin: $margin, justify: $justify,
                                indent: $indentOn, dim: $dimV, warm: $warmV, mode: $mode, anim: $novelAnim,
                                activeTheme: activeTheme,
                                canSearch: mode == "pages",
                                downloaded: chapters.indices.contains(index) && store.isDownloaded(novel.id, chapters[index].id),
                                onSearch: {
                                    showReaderSettings = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showSearch = true }
                                },
                                onBookmarks: {
                                    showReaderSettings = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showBookmarks = true }
                                },
                                onDownload: {
                                    guard chapters.indices.contains(index) else { return }
                                    let cur = chapters[index]
                                    if store.isDownloaded(novel.id, cur.id) {
                                        store.remove(novel: novel.id, chapter: cur.id)
                                    } else {
                                        DownloadManager.shared.enqueue(novel: novel, all: chapters, targets: [cur])
                                    }
                                })
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksSheet(titleKey: novel.readKey, titleName: novel.displayTitle, showHighlights: true,
                           onBookmark: { jumpTo(offset: $0.position, chapterID: $0.chapterID) },
                           onHighlight: { jumpTo(offset: $0.start, chapterID: $0.chapterID) })
        }
        .sheet(isPresented: $showSearch) {
            ChapterSearchSheet(pages: pages) { p in withAnimation { pageIndex = p } }
        }
        .sheet(item: $noteFor) { r in
            NoteSheet(title: r.title, initial: r.initial, onSave: r.save)
        }
        .confirmationDialog("Выделение", isPresented: Binding(get: { pendingSel != nil },
                                                              set: { if !$0 { pendingSel = nil } }),
                            titleVisibility: .visible, presenting: pendingSel) { sel in
            Button("Выделить жёлтым") { applyHighlight(sel, color: 0) }
            Button("Выделить зелёным") { applyHighlight(sel, color: 1) }
            Button("Выделить синим") { applyHighlight(sel, color: 2) }
            Button("Выделить розовым") { applyHighlight(sel, color: 3) }
            Button("Заметка…") { openNote(sel) }
            if hls.exact(novel.readKey, chapterID, sel.range) != nil {
                Button("Убрать выделение", role: .destructive) { removeHighlight(sel) }
            }
            Button("Копировать текст") { UIPasteboard.general.string = sel.text }
            Button("Отмена", role: .cancel) {}
        } message: { sel in
            Text(String(sel.text.prefix(120)))
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = Settings.bool("set.keepAwake", true) }
        .onDisappear {
            persistPos()
            UIApplication.shared.isIdleTimerDisabled = false
            historyTask?.cancel()
        }
    }

    private func scheduleHistory(_ ch: NovelChapter) {
        historyTask?.cancel()
        HistoryStore.current.recordChapter(anime: novel, chapterID: ch.id, title: ch.title)
    }

    private func load() async {
        guard chapters.indices.contains(index), let slug = novel.slugUrl else { return }
        let ch = chapters[index]
        loading = true
        error = nil
        debug = ""
        blocks = []
        pages = []
        pageIndex = 0
        blockTracker.reset()
        if pendingOffset == nil, restoreBlock == nil, let pos = ReadPosStore.shared.get(novel.readKey), pos.c == ch.id {
            if mode == "pages" { if pos.p > 0 { pendingOffset = pos.p } }
            else if pos.b > 0 { restoreBlock = pos.b }
        }
        ReadStore.shared.mark(novel.readKey, ch.id)
        SiteSync.view(novelID: novel.id, chapterID: ch.id)
        scheduleHistory(ch)
        if let local = store.blocks(novel: novel.id, chapter: ch.id) {
            blocks = local
            loading = false
            return
        }
        do {
            let result = try await NovelService.content(slug: slug, chapter: ch)
            if Task.isCancelled { return }
            blocks = result
            if !result.isEmpty, Settings.bool("off.prefetch", false), index + 1 < chapters.count {
                DownloadManager.shared.enqueue(novel: novel, all: chapters,
                                               targets: Array(chapters[(index + 1)..<min(index + 4, chapters.count)]))
            }
            if result.isEmpty {
                error = "Текст главы пуст или недоступен."
                debug = await AnimelibAPI.shared.rawText(NovelService.chapterPath(slug: slug),
                                                         query: NovelService.chapterQuery(ch))
            }
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Закладки, выделения и заметки
struct ReaderSelection: Identifiable {
    let id = UUID()
    let range: NSRange
    let text: String
}

struct NoteRequest: Identifiable {
    let id = UUID()
    let title: String
    let initial: String
    let save: (String) -> Void
}

struct Bookmark: Codable, Identifiable {
    var id = UUID()
    let titleKey: Int
    let chapterID: Int
    let chapterLabel: String
    /// Манга: номер страницы (с нуля). Ранобэ: смещение в тексте главы.
    let position: Int
    let isText: Bool
    let snippet: String
    var note: String
    let created: Date
}

@MainActor
final class BookmarkStore: ObservableObject {
    static let shared = BookmarkStore()
    @Published private(set) var items: [Bookmark] = []
    private let key = "bookmarks.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let v = try? JSONDecoder().decode([Bookmark].self, from: d) { items = v }
    }

    func forTitle(_ k: Int) -> [Bookmark] {
        items.filter { $0.titleKey == k }.sorted { $0.created > $1.created }
    }

    func find(titleKey: Int, chapterID: Int, from: Int, to: Int) -> Bookmark? {
        items.first { $0.titleKey == titleKey && $0.chapterID == chapterID && $0.position >= from && $0.position < to }
    }

    func add(_ b: Bookmark) {
        items.append(b)
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func setNote(_ id: UUID, _ note: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].note = note
        save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: key) }
    }
}

struct Highlight: Codable, Identifiable {
    var id = UUID()
    let titleKey: Int
    let chapterID: Int
    let chapterLabel: String
    let start: Int
    let length: Int
    var color: Int
    var note: String
    let snippet: String
    let created: Date

    static let palette: [UIColor] = [
        UIColor(red: 1.0, green: 0.84, blue: 0.2, alpha: 0.5),
        UIColor(red: 0.35, green: 0.85, blue: 0.45, alpha: 0.45),
        UIColor(red: 0.3, green: 0.65, blue: 1.0, alpha: 0.45),
        UIColor(red: 1.0, green: 0.45, blue: 0.7, alpha: 0.45)
    ]

    var uiColor: UIColor { Highlight.palette[min(max(color, 0), Highlight.palette.count - 1)] }
    var swiftUIColor: Color { Color(uiColor.withAlphaComponent(1)) }
}

@MainActor
final class HighlightStore: ObservableObject {
    static let shared = HighlightStore()
    @Published private(set) var items: [Highlight] = []
    private let key = "highlights.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let v = try? JSONDecoder().decode([Highlight].self, from: d) { items = v }
    }

    func forChapter(_ k: Int, _ chapter: Int) -> [Highlight] {
        items.filter { $0.titleKey == k && $0.chapterID == chapter }
    }

    func forTitle(_ k: Int) -> [Highlight] {
        items.filter { $0.titleKey == k }.sorted { $0.created > $1.created }
    }

    func exact(_ k: Int, _ chapter: Int, _ r: NSRange) -> Highlight? {
        items.first { $0.titleKey == k && $0.chapterID == chapter && $0.start == r.location && $0.length == r.length }
    }

    @discardableResult
    func set(titleKey: Int, chapterID: Int, label: String, range: NSRange, snippet: String,
             color: Int?, note: String?) -> Highlight {
        if let i = items.firstIndex(where: {
            $0.titleKey == titleKey && $0.chapterID == chapterID && $0.start == range.location && $0.length == range.length
        }) {
            if let c = color { items[i].color = c }
            if let n = note { items[i].note = n }
            save()
            return items[i]
        }
        let h = Highlight(titleKey: titleKey, chapterID: chapterID, chapterLabel: label,
                          start: range.location, length: range.length, color: color ?? 0,
                          note: note ?? "", snippet: String(snippet.prefix(160)), created: Date())
        items.append(h)
        save()
        return h
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func setNote(_ id: UUID, _ note: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].note = note
        save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: key) }
    }
}

struct NoteSheet: View {
    let title: String
    let onSave: (String) -> Void
    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(title: String, initial: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.onSave = onSave
        _text = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.footnote).foregroundStyle(.secondary).lineLimit(4)
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    .frame(minHeight: 160)
                Spacer()
            }
            .padding(14)
            .background(AppBackground())
            .navigationTitle("Заметка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Список закладок, выделений и заметок одного тайтла.
struct BookmarksSheet: View {
    let titleKey: Int
    let titleName: String
    let showHighlights: Bool
    let onBookmark: (Bookmark) -> Void
    let onHighlight: (Highlight) -> Void
    @ObservedObject private var bms = BookmarkStore.shared
    @ObservedObject private var hls = HighlightStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var noteFor: NoteRequest?

    var body: some View {
        let marks = bms.forTitle(titleKey)
        let lights = hls.forTitle(titleKey)
        NavigationStack {
            List {
                Section("Закладки") {
                    if marks.isEmpty {
                        Text("Пока нет закладок. Нажми значок закладки в читалке.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(marks) { b in
                        Button {
                            dismiss()
                            onBookmark(b)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(b.chapterLabel).font(.subheadline.weight(.semibold))
                                Text(b.isText ? b.snippet : "Страница \(b.position + 1)")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                if !b.note.isEmpty {
                                    Text(b.note).font(.caption).foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { bms.remove(b.id) } label: { Label("Удалить", systemImage: "trash") }
                            Button {
                                noteFor = NoteRequest(title: b.chapterLabel, initial: b.note) { bms.setNote(b.id, $0) }
                            } label: { Label("Заметка", systemImage: "note.text") }
                            .tint(.orange)
                        }
                    }
                }
                if showHighlights {
                    Section("Выделения и заметки") {
                        if lights.isEmpty {
                            Text("Удерживай палец на абзаце в читалке, чтобы выделить его или добавить заметку.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(lights) { h in
                            Button {
                                dismiss()
                                onHighlight(h)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    RoundedRectangle(cornerRadius: 2).fill(h.swiftUIColor).frame(width: 4)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(h.chapterLabel).font(.caption).foregroundStyle(.secondary)
                                        Text(h.snippet).font(.subheadline).lineLimit(3)
                                        if !h.note.isEmpty {
                                            Text(h.note).font(.caption).foregroundStyle(Theme.accent)
                                        }
                                    }
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) { hls.remove(h.id) } label: { Label("Удалить", systemImage: "trash") }
                                Button {
                                    noteFor = NoteRequest(title: h.snippet, initial: h.note) { hls.setNote(h.id, $0) }
                                } label: { Label("Заметка", systemImage: "note.text") }
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle(titleName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
            }
            .sheet(item: $noteFor) { r in
                NoteSheet(title: r.title, initial: r.initial, onSave: r.save)
            }
        }
    }
}

/// Поиск по тексту открытой главы (ранобэ, постраничный режим).
struct ChapterSearchSheet: View {
    let pages: [NovelPage]
    let onPick: (Int) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    struct Hit: Identifiable {
        let id: Int
        let page: Int
        let snippet: String
    }

    private func search(_ q: String) -> [Hit] {
        let needle = q.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { return [] }
        var out: [Hit] = []
        for (i, p) in pages.enumerated() {
            let s = p.plainText as NSString
            guard s.length > 0 else { continue }
            var from = 0
            while from < s.length, out.count < 300 {
                let r = s.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive],
                                range: NSRange(location: from, length: s.length - from))
                if r.location == NSNotFound { break }
                let a = max(0, r.location - 30)
                let b = min(s.length, NSMaxRange(r) + 50)
                let snip = s.substring(with: NSRange(location: a, length: b - a))
                    .replacingOccurrences(of: "\n", with: " ")
                out.append(Hit(id: out.count, page: i,
                               snippet: (a > 0 ? "…" : "") + snip + (b < s.length ? "…" : "")))
                from = NSMaxRange(r)
            }
        }
        return out
    }

    var body: some View {
        let hits = search(query)
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    Text("Введи слово или фразу (от 2 букв).").foregroundStyle(.secondary)
                } else if hits.isEmpty {
                    Text("В этой главе ничего не найдено.").foregroundStyle(.secondary)
                }
                ForEach(hits) { h in
                    Button {
                        dismiss()
                        onPick(h.page)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Страница \(h.page + 1)").font(.caption).foregroundStyle(Theme.accent)
                            Text(h.snippet).font(.subheadline).lineLimit(3)
                        }
                    }
                }
            }
            .navigationTitle("Поиск по главе")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Слово или фраза")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
            }
        }
    }
}

// MARK: - Похожие тайтлы
@MainActor
final class SimilarViewModel: ObservableObject {
    @Published var similar: [Anime] = []
    @Published var related: [Anime] = []
    @Published var adapt: [Anime] = []
    @Published var note = ""
    @Published var loaded = false
    private var loadedFor: Int?

    func load(_ a: Anime) async {
        guard loadedFor != a.id, let slug = a.slugUrl else { return }
        loadedFor = a.id
        let r = await AnimelibAPI.shared.similarTitles(slug: slug)
        similar = r.similar
        related = r.related
        adapt = r.adapt
        note = r.note
        loaded = true
        ImageLoader.prefetch((r.similar + r.related).compactMap { $0.imageURL })
        ImageLoader.prefetch(r.adapt.compactMap { $0.imageURL })
    }
}

/// Ряд кнопок под описанием: комментарии, связанное, похожие. Списки открываются снизу, а не лежат на странице.
struct TitleActionsRow: View {
    let anime: Anime
    let onComments: () -> Void
    @StateObject private var vm = SimilarViewModel()
    @State private var showSheet = false
    @State private var startTab = 0
    @State private var pushed: Anime?
    @State private var pushActive = false

    private func chipLabel(_ icon: String, _ title: String, _ count: Int?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
            if let c = count {
                Text("\(c)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Theme.accent.opacity(0.22), in: Capsule())
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Theme.chip, in: Capsule())
    }

    private func chip(_ icon: String, _ title: String, _ count: Int?, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(icon, title, count) }
            .buttonStyle(.pressable)
    }

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array((anime.authors ?? []).enumerated()), id: \.offset) { _, a in
                if let aid = a.id {
                    NavigationLink(value: AuthorRef(id: aid, name: a.title, slug: a.slug)) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                            Text(a.title)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.chip, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                } else {
                    Text(a.title)
                        .font(.subheadline)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.chip, in: Capsule())
                }
            }
            chip("bubble.left.and.bubble.right.fill", "Комментарии", nil, onComments)
            if !vm.related.isEmpty || !vm.similar.isEmpty || !vm.adapt.isEmpty {
                let relEmpty = vm.related.isEmpty && vm.adapt.isEmpty
                let both = !relEmpty && !vm.similar.isEmpty
                chip(both ? "square.stack.3d.up.fill" : (relEmpty ? "sparkles" : "link"),
                     both ? "Похожее" : (relEmpty ? "Похожие" : "Связанное"),
                     vm.related.count + vm.similar.count + vm.adapt.count) { showSheet = true }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: anime.id) { await vm.load(anime) }
        .sheet(isPresented: $showSheet) {
            SimilarSheet(related: vm.related, similar: vm.similar, adapt: vm.adapt, start: startTab) { a, isAdapt in
                showSheet = false
                if isAdapt {
                    // экранизация живёт на сайте аниме: переключаем платформу и ищем её в каталоге
                    UserDefaults.standard.set("anime", forKey: "set.platform")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        AppRouter.shared.openCatalog(query: a.displayTitle)
                        AppRouter.shared.toast = "Платформа: Аниме"
                    }
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    pushed = a
                    pushActive = true
                }
            }
        }
        .navigationDestination(isPresented: $pushActive) {
            if let a = pushed {
                if LibSite.current.isBook { NovelDetailView(novel: Novel(a)) } else { DetailView(anime: a) }
            }
        }
    }
}

struct SimilarCell: View {
    let anime: Anime

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: anime.imageURL, maxPixel: 320)
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomLeading) {
                    if let r = anime.rateAvg {
                        Text("★ " + r)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.black.opacity(0.55), in: Capsule())
                            .padding(5)
                    }
                }
            Text(anime.displayTitle)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}

struct SimilarSheet: View {
    let related: [Anime]
    let similar: [Anime]
    var adapt: [Anime] = []
    let start: Int
    let onPick: (Anime, Bool) -> Void
    @State private var tab = 0
    @State private var limit = 18
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    private var tabs: [(title: String, icon: String, list: [Anime])] {
        var t: [(title: String, icon: String, list: [Anime])] = []
        if !related.isEmpty { t.append(("Связанное", "link", related)) }
        if !adapt.isEmpty { t.append(("Экранизации", "tv", adapt)) }
        if !similar.isEmpty { t.append(("Похожие", "sparkles", similar)) }
        return t
    }

    private func tabButton(_ i: Int, _ t: (title: String, icon: String, list: [Anime])) -> some View {
        let on = i == tab
        return Button {
            Haptics.select()
            tab = i
            limit = 18
        } label: {
            HStack(spacing: 6) {
                Image(systemName: t.icon)
                Text(t.title)
                Text("\(t.list.count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background((on ? Color.white : Theme.accent).opacity(0.25), in: Capsule())
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.chip), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        let all = tabs
        let cur = all.indices.contains(tab) ? all[tab].list : []
        let shown = Array(cur.prefix(limit))
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if all.count > 1 {
                        HStack(spacing: 8) {
                            ForEach(Array(all.enumerated()), id: \.offset) { i, t in tabButton(i, t) }
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(shown) { a in
                            Button { Haptics.tap(); onPick(a, all.indices.contains(tab) && all[tab].title == "Экранизации") } label: { SimilarCell(anime: a) }
                                .buttonStyle(.plain)
                        }
                    }
                    if cur.count > shown.count {
                        Button {
                            limit += 24
                        } label: {
                            Text("Показать ещё · \(cur.count - shown.count)")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .background(Theme.chip, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
            .background(AppBackground())
            .navigationTitle(all.count == 1 ? all[0].title : "Связанное и похожее")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
        }
        .onAppear { tab = min(start, max(all.count - 1, 0)) }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct SimilarSection: View {
    let anime: Anime
    @StateObject private var vm = SimilarViewModel()

    private func row(_ title: String, _ list: [Anime]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(Array(list.prefix(20))) { a in
                        TitleLink(anime: a) { PosterCard(anime: a) }
                            .buttonStyle(.pressable)
                    }
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !vm.related.isEmpty { row("Связанное", vm.related) }
            if !vm.similar.isEmpty { row("Похожие", vm.similar) }
            if vm.loaded, vm.related.isEmpty, vm.similar.isEmpty, !vm.note.isEmpty {
                Text("Похожие: сайт не вернул список (\(vm.note))")
                    .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .task(id: anime.id) { await vm.load(anime) }
    }
}

// MARK: - Статистика
struct DayActivity: Codable {
    var watch: Double = 0
    var episodes = 0
    var novels = 0
    var manga = 0
    /// Время чтения (манга, хентай, ранобэ) в секундах
    var read: Double = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        watch = (try? c.decode(Double.self, forKey: .watch)) ?? 0
        episodes = (try? c.decode(Int.self, forKey: .episodes)) ?? 0
        novels = (try? c.decode(Int.self, forKey: .novels)) ?? 0
        manga = (try? c.decode(Int.self, forKey: .manga)) ?? 0
        read = (try? c.decode(Double.self, forKey: .read)) ?? 0
    }
}

@MainActor
final class ActivityStore: ObservableObject {
    static let shared = ActivityStore()
    @Published private(set) var days: [String: DayActivity] = [:]
    private let key = "activity.v1"
    private var dirty = false
    private var lastSave = Date.distantPast

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func dayKey(_ d: Date = Date()) -> String { fmt.string(from: d) }

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let v = try? JSONDecoder().decode([String: DayActivity].self, from: d) { days = v }
    }

    private func mutate(_ f: (inout DayActivity) -> Void) {
        let k = Self.dayKey()
        var d = days[k] ?? DayActivity()
        f(&d)
        days[k] = d
        dirty = true
        if Date().timeIntervalSince(lastSave) > 30 { flush() }
    }

    func addEpisode() { mutate { $0.episodes += 1 } }
    func addChapter(manga: Bool) {
        mutate { if manga { $0.manga += 1 } else { $0.novels += 1 } }
    }

    func flush() {
        guard dirty else { return }
        dirty = false
        lastSave = Date()
        if let d = try? JSONEncoder().encode(days) { UserDefaults.standard.set(d, forKey: key) }
    }
}

struct StatsView: View {
    @ObservedObject private var act = ActivityStore.shared
    @ObservedObject private var prog = ProgressStore.shared
    @ObservedObject private var reads = ReadStore.shared
    @State private var chart = 0

    private struct Bar: Identifiable {
        let id: String
        let label: String
        let value: Double
    }

    private func lastDays(_ n: Int) -> [(String, Date)] {
        let cal = Calendar.current
        var out: [(String, Date)] = []
        for i in (0..<n).reversed() {
            if let d = cal.date(byAdding: .day, value: -i, to: Date()) { out.append((ActivityStore.dayKey(d), d)) }
        }
        return out
    }

    private func total(_ n: Int, _ f: (DayActivity) -> Double) -> Double {
        var t = 0.0
        for (k, _) in lastDays(n) { t += f(act.days[k] ?? DayActivity()) }
        return t
    }

    private var streak: Int {
        let cal = Calendar.current
        func active(_ d: Date) -> Bool {
            guard let a = act.days[ActivityStore.dayKey(d)] else { return false }
            return a.episodes > 0 || a.novels > 0 || a.manga > 0
        }
        var day = Date()
        if !active(day) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var n = 0
        while active(day), n < 3650 {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }

    private var episodesFinished: Int { prog.items.values.filter { $0.finished }.count }
    private var mangaChapters: Int {
        reads.read.filter { (Int($0.key) ?? 0) < 0 }.values.reduce(0) { $0 + $1.count }
    }
    private var novelChapters: Int {
        reads.read.filter { (Int($0.key) ?? 0) >= 0 }.values.reduce(0) { $0 + $1.count }
    }

    private func chaptersIn(_ n: Int) -> Int {
        Int(total(n) { Double($0.novels + $0.manga) })
    }

    private var bars: [Bar] {
        let f = DateFormatter()
        f.dateFormat = "d"
        var out: [Bar] = []
        for (k, d) in lastDays(14) {
            let a = act.days[k] ?? DayActivity()
            let v = chart == 0 ? Double(a.novels + a.manga) : Double(a.episodes)
            out.append(Bar(id: k, label: f.string(from: d), value: v))
        }
        return out
    }

    private func tile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(Theme.accent)
            Text(value).font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    var body: some View {
        let list = bars
        let maxV = max(list.map { $0.value }.max() ?? 1, 1)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    tile("Дней подряд", "\(streak)", "flame.fill")
                    tile("Серий досмотрено", "\(episodesFinished)", "checkmark.circle.fill")
                    tile("Глав за неделю", "\(chaptersIn(7))", "book.fill")
                    tile("Глав за месяц", "\(chaptersIn(30))", "books.vertical.fill")
                    tile("Глав манги прочитано", "\(mangaChapters)", "photo.on.rectangle")
                    tile("Глав ранобэ прочитано", "\(novelChapters)", "text.book.closed.fill")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $chart) {
                        Text("Чтение, глав").tag(0)
                        Text("Просмотр, серий").tag(1)
                    }
                    .pickerStyle(.segmented)
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(list) { b in
                            VStack(spacing: 4) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(b.value > 0 ? Theme.accent : Theme.chip)
                                    .frame(height: max(4, CGFloat(b.value / maxV) * 90))
                                Text(b.label).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 118)
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))

                Text("Считаются прочитанные главы, досмотренные серии и дни подряд. Время не отслеживается.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .background(AppBackground())
        .navigationTitle("Статистика")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - App
@main
struct HeheApp: App {
    init() {
        BackupManager.restoreOnLaunch()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
