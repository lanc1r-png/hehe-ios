import SwiftUI
import WebKit
import AVKit
import Combine

// MARK: - Кино (kinomig.tv): модели

/// Фильм, сериал, мультфильм, аниме или ТВ-шоу с kinomig.tv
struct KinoItem: Codable, Hashable, Identifiable {
    var id: Int
    /// Путь страницы на сайте: /film/583-obitel-zla-2026.html
    var path: String
    var title: String
    var orig: String? = nil
    /// Постер как на сайте: /uploads/posters/7378605_xs.webp
    var poster: String? = nil
    /// Год, страна, жанр, длительность…
    var meta: [String] = []
    var desc: String? = nil
    var quality: String? = nil
    var rating: String? = nil
    /// «2 сез. 10 серия» — для новых серий
    var badge: String? = nil

    /// film / serial / multfilm / anime / tv-shou
    var kind: String { path.split(separator: "/").first.map(String.init) ?? "film" }

    var kindTitle: String {
        switch kind {
        case "serial": return "Сериал"
        case "multfilm": return "Мультфильм"
        case "anime": return "Аниме"
        case "tv-shou": return "ТВ-шоу"
        default: return "Фильм"
        }
    }

    var pageURL: URL? { URL(string: KinoNet.base + path) }

    /// Карточки — средний размер (_s), страница — большой (без суффикса)
    func posterURL(big: Bool = false) -> URL? {
        guard var p = poster, !p.isEmpty else { return nil }
        if big { p = p.replacingOccurrences(of: "_xs.", with: ".").replacingOccurrences(of: "_s.", with: ".") }
        else { p = p.replacingOccurrences(of: "_xs.", with: "_s.") }
        if p.hasPrefix("http") { return URL(string: p) }
        return URL(string: KinoNet.base + p)
    }

    static func id(fromPath p: String) -> Int? {
        guard let r = p.range(of: #"/(\d+)-"#, options: .regularExpression) else { return nil }
        return Int(p[r].dropFirst().dropLast())
    }
}

/// Источник плеера на странице (одна озвучка)
struct KinoSource: Hashable {
    /// alloha — родной плеер; остальные (collaps…) — веб-плеер сайта
    var balancer: String = "alloha"
    var isNative: Bool { balancer == "alloha" }
    let translation: String
    let url: URL
    let quality: String?
    /// сезон → номера серий
    let seasons: [Int: [Int]]
}

struct KinoDetail {
    var item: KinoItem
    var info: [(String, String)] = []
    var genres: [String] = []
    var actors: [String] = []
    var director: String?
    var sources: [KinoSource] = []
    /// сезон → серия → дата выхода
    var dates: [Int: [Int: String]] = [:]
    /// Что нашли на странице про плееры — показываем, если смотреть не получается
    var playersNote: String?

    var isSerial: Bool { sources.contains { $0.isNative && !$0.seasons.isEmpty } }
    var seasons: [Int] {
        Array(Set(sources.flatMap { $0.seasons.keys })).sorted()
    }
    func episodes(_ season: Int, source: KinoSource?) -> [Int] {
        if let s = source?.seasons[season], !s.isEmpty { return s.sorted() }
        return Array(Set(sources.flatMap { $0.seasons[season] ?? [] })).sorted()
    }
}

/// Готовый поток для плеера
struct KinoStream {
    struct Track: Hashable {
        let label: String
        /// качество (1080, 720…) → ссылка (и запасная)
        let qualities: [(Int, [URL])]
        static func == (a: Track, b: Track) -> Bool { a.label == b.label }
        func hash(into h: inout Hasher) { h.combine(label) }
    }
    var tracks: [Track]
    var skip: ClosedRange<Double>?
    var origin: String
    var referer: String
}

enum KinoError: LocalizedError {
    case blocked, empty, player(String)
    var errorDescription: String? {
        switch self {
        case .blocked: return "Сайт не пустил (защита Cloudflare). Попробуй ещё раз через минуту."
        case .empty: return "Сайт ничего не вернул"
        case .player(let s): return "Плеер: " + s
        }
    }
}

// MARK: - Сеть: обычные запросы, а если мешает Cloudflare — через невидимый браузер

@MainActor
final class KinoNet: NSObject, WKNavigationDelegate {
    static let shared = KinoNet()
    nonisolated static let base = "https://kinomig.tv"
    nonisolated static let ua = Kodik.ua

    let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared
        c.httpAdditionalHeaders = ["User-Agent": KinoNet.ua, "Accept-Language": "ru-RU,ru;q=0.9"]
        c.timeoutIntervalForRequest = 25
        return URLSession(configuration: c)
    }()

    private var web: WKWebView?
    private var ready = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var loadingWeb = false

    static func isChallenge(_ status: Int, _ body: String) -> Bool {
        if body.contains("<title>Just a moment") || body.contains("cf_chl_opt") || body.contains("cf-chl-") { return true }
        return (status == 403 || status == 503) && body.lowercased().contains("cloudflare")
    }

    /// Текст страницы или API сайта (путь от корня или полный адрес)
    func text(_ pathOrURL: String, ajax: Bool = false) async throws -> String {
        let urlStr = pathOrURL.hasPrefix("http") ? pathOrURL : Self.base + pathOrURL
        guard let url = URL(string: urlStr) else { throw KinoError.empty }
        if let t = try? await plain(url, ajax: ajax) { return t }
        // Cloudflare: проходим проверку браузером, забираем «пропуск» и пробуем снова
        await warmUp()
        if let t = try? await plain(url, ajax: ajax) { return t }
        if let t = try await viaWeb(url, ajax: ajax) { return t }
        throw KinoError.blocked
    }

    private func plain(_ url: URL, ajax: Bool) async throws -> String {
        var r = URLRequest(url: url)
        r.setValue(Self.base + "/", forHTTPHeaderField: "Referer")
        r.setValue(ajax ? "application/json, text/javascript, */*; q=0.01" : "text/html,application/xhtml+xml,*/*;q=0.8",
                   forHTTPHeaderField: "Accept")
        if ajax { r.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With") }
        let (d, resp) = try await session.data(for: r)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let t = String(data: d, encoding: .utf8) ?? ""
        if Self.isChallenge(status, t) || !(200..<300).contains(status) { throw KinoError.blocked }
        return t
    }

    /// Невидимый браузер открывает сайт, проходит проверку и отдаёт cookie обычным запросам
    func warmUp() async {
        if ready { return }
        if loadingWeb {
            await withCheckedContinuation { waiting.append($0) }
            return
        }
        loadingWeb = true
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let v = WKWebView(frame: CGRect(x: 0, y: 0, width: 2, height: 2), configuration: cfg)
        v.customUserAgent = Self.ua
        v.navigationDelegate = self
        v.alpha = 0.01
        v.isUserInteractionEnabled = false
        if let w = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            w.addSubview(v)
        }
        web = v
        v.load(URLRequest(url: URL(string: Self.base + "/")!))
        // ждём, пока страница перестанет быть проверкой (до 25 с)
        for _ in 0..<50 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let title = (try? await v.evaluateJavaScript("document.title") as? String) ?? ""
            let done = (try? await v.evaluateJavaScript("document.readyState") as? String) == "complete"
            if done, !title.isEmpty, !title.contains("Just a moment"), !title.contains("Подождите") { break }
        }
        await copyCookies()
        ready = true
        loadingWeb = false
        waiting.forEach { $0.resume() }
        waiting = []
    }

    private func copyCookies() async {
        guard let store = web?.configuration.websiteDataStore.httpCookieStore else { return }
        let cookies = await withCheckedContinuation { (c: CheckedContinuation<[HTTPCookie], Never>) in
            store.getAllCookies { c.resume(returning: $0) }
        }
        for ck in cookies where ck.domain.contains("kinomig") { HTTPCookieStorage.shared.setCookie(ck) }
    }

    private func viaWeb(_ url: URL, ajax: Bool) async throws -> String? {
        guard let v = web else { return nil }
        let js = """
        const r = await fetch(u, { credentials: 'include', headers: ajax ? { 'X-Requested-With': 'XMLHttpRequest' } : {} });
        return await r.text();
        """
        let res = try? await v.callAsyncJavaScript(js, arguments: ["u": url.absoluteString, "ajax": ajax], contentWorld: .page)
        guard let t = res as? String, !Self.isChallenge(200, t) else { return nil }
        return t
    }

    /// Картинка с сайта (с тем же «пропуском»)
    func image(_ url: URL, maxPixel: CGFloat) async -> UIImage? {
        var r = URLRequest(url: url)
        r.setValue(Self.base + "/", forHTTPHeaderField: "Referer")
        r.setValue("image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let px = maxPixel
        if !webImages, let (d, resp) = try? await session.data(for: r),
           ((resp as? HTTPURLResponse)?.statusCode ?? 200) < 300,
           let img = await Task.detached(priority: .userInitiated, operation: { ImageLoader.downsample(d, maxPixel: px) }).value {
            return img
        }
        // Cloudflare не отдал картинку обычному запросу: берём её браузером, который прошёл проверку
        webImages = true
        await warmUp()
        guard let v = web else { return nil }
        let js = """
        const r = await fetch(u, { credentials: 'include' });
        if (!r.ok) return '';
        const b = await r.blob();
        return await new Promise(res => { const f = new FileReader(); f.onloadend = () => res(String(f.result || '')); f.readAsDataURL(b); });
        """
        guard let res = try? await v.callAsyncJavaScript(js, arguments: ["u": url.absoluteString], contentWorld: .page) as? String,
              let comma = res.firstIndex(of: ","),
              let data = Data(base64Encoded: String(res[res.index(after: comma)...])) else { return nil }
        return await Task.detached(priority: .userInitiated, operation: { ImageLoader.downsample(data, maxPixel: px) }).value
    }

    /// Картинки обычными запросами не идут — сразу через браузер
    private var webImages = false
}

// MARK: - Разбор страниц сайта

enum KinoParse {
    static func unescapeHTML(_ s: String) -> String {
        var t = s
        let map = ["&quot;": "\"", "&#39;": "'", "&#039;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&laquo;": "«", "&raquo;": "»", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…"]
        for (k, v) in map { t = t.replacingOccurrences(of: k, with: v) }
        // числовые &#1234;
        if t.contains("&#") {
            let re = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")
            let ns = t as NSString
            var out = ""
            var last = 0
            for m in re?.matches(in: t, range: NSRange(location: 0, length: ns.length)) ?? [] {
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let hex = ns.substring(with: m.range(at: 1)) == "x"
                let num = ns.substring(with: m.range(at: 2))
                if let n = UInt32(num, radix: hex ? 16 : 10), let u = Unicode.Scalar(n) { out += String(Character(u)) }
                last = m.range.location + m.range.length
            }
            out += ns.substring(from: last)
            t = out
        }
        return t.replacingOccurrences(of: "&amp;", with: "&")
    }

    static func strip(_ s: String) -> String {
        let noTags = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return unescapeHTML(noTags).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func first(_ pattern: String, _ s: String, group: Int = 1) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > group, m.range(at: group).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: group))
    }

    static func all(_ pattern: String, _ s: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i))
            }
        }
    }

    /// Путь без домена: https://kinomig.tv/film/1-x.html?season=2 → /film/1-x.html
    static func path(_ href: String) -> String {
        var p = unescapeHTML(href)
        if let r = p.range(of: "kinomig.tv") { p = String(p[r.upperBound...]) }
        if let q = p.firstIndex(of: "?") { p = String(p[..<q]) }
        return p
    }

    static func query(_ href: String, _ name: String) -> Int? {
        let h = unescapeHTML(href)
        guard let c = URLComponents(string: h.hasPrefix("http") ? h : KinoNet.base + h) else { return nil }
        return c.queryItems?.first { $0.name == name }?.value.flatMap(Int.init)
    }

    /// Карточки каталога (<article class="card">)
    static func cards(_ html: String) -> [KinoItem] {
        var out: [KinoItem] = []
        for block in html.components(separatedBy: "<article class=\"card").dropFirst() {
            let b = block.components(separatedBy: "</article>").first ?? block
            guard let href = first(#"<a class="go" href="([^"]+)""#, b) ?? first(#"href="([^"]+\.html)""#, b) else { continue }
            let p = path(href)
            guard let id = KinoItem.id(fromPath: p) else { continue }
            let title = first(#"<a class="go"[^>]*>(.*?)</a>"#, b).map(strip) ?? first(#"alt="([^"]*)""#, b).map(unescapeHTML) ?? ""
            var it = KinoItem(id: id, path: p, title: title)
            it.poster = first(#"<img src="([^"]+)""#, b)
            it.orig = first(#"<div class="orig">(.*?)</div>"#, b).map(strip).flatMap { $0.isEmpty ? nil : $0 }
            it.meta = all(#"<span class="mi">(.*?)</span>"#, b).map { strip($0[1]) }.filter { !$0.isEmpty }
            it.badge = first(#"<span class="ep">(.*?)</span>"#, b).map(strip)
            it.desc = first(#"<p>(.*?)</p>"#, b).map(strip)
            it.quality = first(#"<span class="q">(.*?)</span>"#, b).map(strip)
            it.rating = first(#"class="(?:rt|rating)[^"]*"[^>]*>(.*?)</"#, b).map(strip).flatMap { $0.isEmpty ? nil : $0 }
            out.append(it)
        }
        return out
    }

    /// Плитки главной (<a class="tile">)
    static func tiles(_ html: String) -> [KinoItem] {
        all(#"<a class="tile" href="([^"]+)"[^>]*title="([^"]*)"(.*?)</a>"#, html).compactMap { m in
            let p = path(m[1])
            guard let id = KinoItem.id(fromPath: p) else { return nil }
            var it = KinoItem(id: id, path: p, title: unescapeHTML(m[2]))
            it.poster = first(#"<img src="([^"]+)""#, m[3])
            return it
        }
    }

    /// Новые серии (<a class="ucard">)
    static func updates(_ html: String) -> [(KinoItem, Int?, Int?)] {
        all(#"<a class="ucard" href="([^"]+)"[^>]*title="([^"]*)"(.*?)</a>"#, html).compactMap { m in
            let p = path(m[1])
            guard let id = KinoItem.id(fromPath: p) else { return nil }
            var it = KinoItem(id: id, path: p, title: unescapeHTML(m[2]))
            it.poster = first(#"<img src="([^"]+)""#, m[3])
            it.badge = first(#"<span class="ep">(.*?)</span>"#, m[3]).map(strip)
            return (it, query(m[1], "season"), query(m[1], "episode"))
        }
    }

    /// Подсказки поиска
    static func suggest(_ html: String) -> [KinoItem] {
        all(#"<a class="row" href="([^"]+)">(.*?)</a>"#, html).compactMap { m in
            let p = path(m[1])
            guard let id = KinoItem.id(fromPath: p) else { return nil }
            let b = m[2]
            var it = KinoItem(id: id, path: p, title: first(#"<span class="nm">(.*?)</span>"#, b).map(strip) ?? "")
            it.poster = first(#"<img class="po" src="([^"]+)""#, b)
            if let mt = first(#"<span class="mt">(.*?)</span>"#, b).map(strip) {
                it.meta = mt.components(separatedBy: " · ").filter { !$0.isEmpty }
            }
            it.rating = first(#"<span class="rt"><b>(.*?)</b>"#, b).map(strip)
            return it
        }
    }

    /// Значение атрибута: сайт пишет его и в "двойных" (&quot; внутри), и в 'одинарных' кавычках (сырой JSON)
    static func attr(_ name: String, _ html: String) -> String? {
        if let v = first(name + #"\s*=\s*"([^"]*)""#, html) { return v }
        if let v = first(name + #"\s*=\s*'([^']*)'"#, html) { return v }
        return nil
    }

    static func attrJSON(_ name: String, _ html: String) -> Any? {
        guard let raw = attr(name, html) else { return nil }
        for candidate in [raw, unescapeHTML(raw)] {
            if let o = try? JSONSerialization.jsonObject(with: Data(candidate.utf8)) { return o }
        }
        return nil
    }

    /// Страница фильма или сериала
    static func detail(_ html: String, base: KinoItem) -> KinoDetail {
        var it = base
        if let h1 = first(#"<h1[^>]*>(.*?)</h1>"#, html).map(strip), !h1.isEmpty { it.title = h1 }
        if let o = first(#"<div class="film-titles">.*?<div class="orig">(.*?)</div>"#, html).map(strip), !o.isEmpty { it.orig = o }
        if let p = attr("data-poster", html), !p.isEmpty { it.poster = unescapeHTML(p) }
        var d = KinoDetail(item: it)

        // сведения: год, страна, жанр…
        if let dl = first(#"<dl class="kv">(.*?)</dl>"#, html) {
            d.info = all(#"<dt>(.*?)</dt>\s*<dd[^>]*>(.*?)</dd>"#, dl).map { (strip($0[1]), strip($0[2])) }.filter { !$0.1.isEmpty }
        }
        // ld+json: описание, жанры, актёры, режиссёр
        for m in all(#"<script type="application/ld\+json">(.*?)</script>"#, html) {
            guard let o = try? JSONSerialization.jsonObject(with: Data(m[1].utf8)) as? [String: Any] else { continue }
            let graph = (o["@graph"] as? [[String: Any]]) ?? [o]
            for g in graph where ["Movie", "TVSeries"].contains(g["@type"] as? String ?? "") {
                if d.item.desc == nil || (d.item.desc ?? "").isEmpty, var desc = g["description"] as? String {
                    if let r = desc.range(of: "⭐") { desc = String(desc[..<r.lowerBound]) }
                    d.item.desc = desc.trimmingCharacters(in: .whitespaces)
                }
                d.genres = (g["genre"] as? [String]) ?? []
                d.actors = ((g["actor"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
                d.director = ((g["director"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }.first
                if d.item.poster == nil, let img = g["image"] as? String { d.item.poster = img }
                if let r = g["aggregateRating"] as? [String: Any], let v = r["ratingValue"] {
                    d.item.rating = "\(v)"
                }
            }
        }
        if d.item.meta.isEmpty {
            d.item.meta = d.info.filter { ["Год", "Страна", "Жанр", "Длительность"].contains($0.0) }.map { $0.1 }
        }
        // источники плеера (берём Alloha — его поток умеем открывать в родном плеере)
        if let arr = attrJSON("data-players", html) as? [[String: Any]] {
            let names = arr.compactMap { $0["balancer"] as? String }
            d.playersNote = names.isEmpty ? "на странице пустой список плееров" : "плееры на странице: " + names.joined(separator: ", ")
            // сначала Alloha (родной плеер), потом остальные (веб-плеер)
            let sorted = arr.filter { ($0["balancer"] as? String) == "alloha" } + arr.filter { ($0["balancer"] as? String) != "alloha" }
            for p in sorted {
                let bal = (p["balancer"] as? String) ?? "web"
                guard let u = (p["url"] as? String).flatMap({ URL(string: $0.hasPrefix("//") ? "https:" + $0 : $0) }) else { continue }
                var seasons: [Int: [Int]] = [:]
                if let s = p["seasons"] as? [String: Any] {
                    for (k, v) in s { if let n = Int(k) { seasons[n] = (v as? [Any])?.compactMap { ($0 as? Int) ?? Int("\($0)") } ?? [] } }
                }
                var name = (p["translation"] as? String) ?? "Озвучка"
                if bal != "alloha" { name += " (\(bal.capitalized), веб-плеер)" }
                d.sources.append(KinoSource(balancer: bal, translation: name, url: u,
                                            quality: p["quality"] as? String, seasons: bal == "alloha" ? seasons : [:]))
            }
        } else {
            if let r = html.range(of: "data-players") {
                let snippet = html[r.lowerBound...].prefix(160)
                d.playersNote = "не разобрал список плееров (" + String(snippet) + "…)"
            } else {
                d.playersNote = "на странице нет списка плееров"
            }
            // запасной вариант: любой iframe плеера на странице
            if let src = first(#"<iframe[^>]+src="([^"]+)""#, html), let u = URL(string: src.hasPrefix("//") ? "https:" + src : src) {
                d.sources.append(KinoSource(balancer: "web", translation: "Плеер сайта", url: u, quality: nil, seasons: [:]))
            }
        }
        if let eps = attrJSON("data-episodes", html) as? [String: [String: Any]] {
            for (s, m) in eps {
                guard let sn = Int(s) else { continue }
                var e: [Int: String] = [:]
                for (k, v) in m { if let en = Int(k) { e[en] = ((v as? [Any])?.last as? String) ?? "" } }
                d.dates[sn] = e
            }
        }
        return d
    }

    /// Строковый литерал JavaScript ('...') → текст
    static func jsUnescape(_ s: String) -> String {
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            guard c == "\\" else { out.append(c); continue }
            guard let n = it.next() else { break }
            switch n {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "u":
                var hex = ""
                for _ in 0..<4 { if let h = it.next() { hex.append(h) } }
                if let v = UInt32(hex, radix: 16), let u = Unicode.Scalar(v) {
                    // экранируем, если внутри строки JSON это кавычка или слэш
                    let ch = Character(u)
                    if ch == "\"" { out += "\\\"" } else if ch == "\\" { out += "\\\\" } else { out.append(ch) }
                }
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            default: out.append(n)
            }
        }
        return out
    }
}

// MARK: - Сервис

@MainActor
enum KinoAPI {
    enum Sort: String, CaseIterable {
        case popular = "news_read", new = "new", rating = "rating"
        var title: String {
            switch self { case .popular: return "Популярные"; case .new: return "Новые"; case .rating: return "По рейтингу" }
        }
    }

    struct Home {
        var decks: [(String, [KinoItem])] = []
        var updates: [(String, [(KinoItem, Int?, Int?)])] = []
    }

    static func home() async throws -> Home {
        let html = try await KinoNet.shared.text("/")
        var h = Home()
        let deckNames = [("deck-new", "Популярное"), ("deck-f", "Фильмы"), ("deck-s", "Сериалы"),
                         ("deck-c", "Мультфильмы"), ("deck-a", "Аниме"), ("deck-t", "ТВ-шоу")]
        for (id, name) in deckNames {
            guard let r = html.range(of: "id=\"\(id)\"") else { continue }
            let rest = html[r.upperBound...]
            let end = rest.range(of: "<div class=\"deck\"")?.lowerBound ?? rest.range(of: "</section>")?.lowerBound ?? rest.endIndex
            let items = KinoParse.tiles(String(rest[..<end]))
            if !items.isEmpty { h.decks.append((name, items)) }
        }
        for sec in html.components(separatedBy: "<section class=\"upd\"").dropFirst() {
            let s = sec.components(separatedBy: "</section>").first ?? sec
            let name = KinoParse.first(#"<div class="uhead">(.*?)</div>"#, s).map(KinoParse.strip) ?? "Новые серии"
            let list = KinoParse.updates(s)
            if !list.isEmpty { h.updates.append((name, list)) }
        }
        if h.decks.isEmpty && h.updates.isEmpty {
            // запасной вариант: первая страница каталога
            let l = try await list(path: "/", sort: .popular, page: 1)
            if !l.items.isEmpty { h.decks.append(("Популярное", l.items)) }
        }
        return h
    }

    /// Список: раздел (/film/), жанр (/genre/komedii/), подборка (/podborki/…/), год, страна
    static func list(path: String, sort: Sort, page: Int) async throws -> (items: [KinoItem], pages: Int) {
        let types = ["film", "serial", "multfilm", "anime", "tv-shou"]
        var q = [URLQueryItem(name: "sort", value: sort.rawValue)]
        let seg = path.split(separator: "/").map(String.init)
        if seg.count == 1, types.contains(seg[0]) { q.append(URLQueryItem(name: "type", value: seg[0])) }
        if page > 1 { q.append(URLQueryItem(name: "page", value: String(page))) }
        q.append(URLQueryItem(name: "path", value: path))
        q.append(URLQueryItem(name: "part", value: "list"))
        var c = URLComponents(string: KinoNet.base + "/api/filter.php")!
        c.queryItems = q
        if let t = try? await KinoNet.shared.text(c.url!.absoluteString, ajax: true),
           let o = try? JSONSerialization.jsonObject(with: Data(t.utf8)) as? [String: Any],
           let html = o["html"] as? String {
            let items = KinoParse.cards(html)
            if !items.isEmpty { return (items, (o["pages"] as? Int) ?? Int("\(o["pages"] ?? 1)") ?? 1) }
        }
        // запасной путь: обычная страница сайта
        var pc = URLComponents(string: KinoNet.base + path)!
        pc.queryItems = [URLQueryItem(name: "sort", value: sort.rawValue)] + (page > 1 ? [URLQueryItem(name: "page", value: String(page))] : [])
        let html = try await KinoNet.shared.text(pc.url!.absoluteString)
        let items = KinoParse.cards(html)
        let maxPage = KinoParse.all(#"/page/(\d+)/"#, html).compactMap { Int($0[1]) }.max() ?? (items.isEmpty ? page : page + 1)
        return (items, maxPage)
    }

    static func search(_ q: String) async throws -> [KinoItem] {
        var c = URLComponents(string: KinoNet.base + "/api/suggest.php")!
        c.queryItems = [URLQueryItem(name: "q", value: q)]
        let t = try await KinoNet.shared.text(c.url!.absoluteString, ajax: true)
        guard let o = try? JSONSerialization.jsonObject(with: Data(t.utf8)) as? [String: Any],
              let html = o["html"] as? String else { return [] }
        return KinoParse.suggest(html)
    }

    static func detail(_ item: KinoItem) async throws -> KinoDetail {
        let html = try await KinoNet.shared.text(item.path)
        return KinoParse.detail(html, base: item)
    }

    /// Плеер Alloha: страница плеера → номер файла → ссылки на поток
    static func stream(_ source: KinoSource, season: Int?, episode: Int?) async throws -> KinoStream {
        var c = URLComponents(url: source.url, resolvingAgainstBaseURL: false)!
        var items = (c.queryItems ?? []).filter { $0.name != "season" && $0.name != "episode" }
        if let season { items.append(URLQueryItem(name: "season", value: String(season))) }
        if let episode { items.append(URLQueryItem(name: "episode", value: String(episode))) }
        c.queryItems = items
        guard let pageURL = c.url, let host = pageURL.host else { throw KinoError.player("нет адреса") }
        let origin = "\(pageURL.scheme ?? "https")://\(host)"
        let token = items.first { $0.name == "token" }?.value ?? ""
        var note = ""
        if let s = try? await direct(pageURL: pageURL, origin: origin, token: token, note: &note) { return s }
        // прямой путь не сработал — открываем плеер браузером и берём его собственный ответ
        let sniffed: String
        do { sniffed = try await KinoSniffer.capture(pageURL) } catch {
            throw KinoError.player(note.isEmpty ? "плеер не ответил" : note)
        }
        if sniffed.hasPrefix("M3U8 "), let u = URL(string: String(sniffed.dropFirst(5))) {
            return KinoStream(tracks: [.init(label: source.translation ?? "Озвучка", qualities: [(720, [u])])],
                              skip: nil, origin: origin, referer: pageURL.absoluteString)
        }
        do {
            return try parseStream(Data(sniffed.utf8), origin: origin, referer: pageURL.absoluteString)
        } catch {
            throw KinoError.player("нет ссылок на видео (\(note.isEmpty ? String(sniffed.prefix(160)) : note))")
        }
    }

    private static func direct(pageURL: URL, origin: String, token: String, note: inout String) async throws -> KinoStream {
        var r = URLRequest(url: pageURL)
        r.setValue(KinoNet.base + "/", forHTTPHeaderField: "Referer")
        r.setValue("text/html,*/*", forHTTPHeaderField: "Accept")
        let (d, _) = try await KinoNet.shared.session.data(for: r)
        let html = String(data: d, encoding: .utf8) ?? ""
        guard let lit = KinoParse.first(#"fileList\s*=\s*JSON\.parse\(\s*['"](.*?)['"]\s*\)"#, html) else {
            note = "страница плеера: " + String(KinoParse.strip(html).prefix(120))
            throw KinoError.player("не нашёл список файлов")
        }
        let json = KinoParse.jsUnescape(lit)
        guard let fl = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            throw KinoError.player("не разобрал список файлов")
        }
        guard let active = fl["active"] as? [String: Any],
              let fileID = (active["id"] as? Int) ?? Int("\(active["id"] ?? "")") else {
            throw KinoError.player("нет этой серии")
        }

        var post = URLRequest(url: URL(string: origin + "/bnsi/movies/\(fileID)")!)
        post.httpMethod = "POST"
        post.httpBody = "token=\(token)&av1=false&autoplay=0&audio=&subtitle=".data(using: .utf8)
        post.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        post.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        post.setValue(pageURL.absoluteString, forHTTPHeaderField: "Referer")
        post.setValue(origin, forHTTPHeaderField: "Origin")
        post.setValue("application/json, */*", forHTTPHeaderField: "Accept")
        let (pd, _) = try await KinoNet.shared.session.data(for: post)
        do { return try parseStream(pd, origin: origin, referer: pageURL.absoluteString) } catch {
            note = "ответ: " + (String(data: pd.prefix(120), encoding: .utf8) ?? "")
            throw error
        }
    }

    static func parseStream(_ pd: Data, origin: String, referer: String) throws -> KinoStream {
        guard let o = try? JSONSerialization.jsonObject(with: pd) as? [String: Any] else {
            throw KinoError.player("непонятный ответ")
        }
        var tracks: [KinoStream.Track] = []
        for s in (o["hlsSource"] as? [[String: Any]]) ?? [] {
            let label = (s["label"] as? String) ?? "Озвучка"
            var qs: [(Int, [URL])] = []
            func urls(_ v: Any) -> [URL] {
                if let str = v as? String {
                    return str.components(separatedBy: " or ").compactMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
                }
                if let arr = v as? [Any] { return arr.flatMap(urls) }
                if let d = v as? [String: Any] { return ["url", "file", "src", "hls"].compactMap { d[$0] }.flatMap(urls) }
                return []
            }
            for (k, v) in (s["quality"] as? [String: Any]) ?? [:] {
                guard let qn = Int(k.filter(\.isNumber)) else { continue }
                let u = urls(v)
                if !u.isEmpty { qs.append((qn, u)) }
            }
            if qs.isEmpty, let one = (s["file"] ?? s["url"] ?? s["src"]) { let u = urls(one); if !u.isEmpty { qs.append((720, u)) } }
            qs.sort { $0.0 > $1.0 }
            if !qs.isEmpty { tracks.append(.init(label: label, qualities: qs)) }
        }
        guard !tracks.isEmpty else { throw KinoError.player("нет ссылок на видео") }
        var skip: ClosedRange<Double>?
        if let st = o["skipTime"] as? String {
            let p = st.split(separator: "-").compactMap { Double($0) }
            if p.count == 2, p[1] > p[0] { skip = p[0]...p[1] }
        }
        return KinoStream(tracks: tracks, skip: skip, origin: origin, referer: referer)
    }
}

// MARK: - Своё избранное, история и прогресс (у kinomig нет аккаунта)

@MainActor
final class KinoStore: ObservableObject {
    static let shared = KinoStore()

    struct Watch: Codable, Identifiable, Hashable {
        var item: KinoItem
        var season: Int?
        var episode: Int?
        var translation: String?
        var updated: Date
        var id: Int { item.id }
    }
    struct Pos: Codable { var t: Double; var d: Double }

    @Published private(set) var favorites: [KinoItem] = []
    @Published private(set) var history: [Watch] = []
    @Published private(set) var positions: [String: Pos] = [:]

    private init() {
        let ud = UserDefaults.standard
        if let d = ud.data(forKey: "kino.fav.v1"), let v = try? JSONDecoder().decode([KinoItem].self, from: d) { favorites = v }
        if let d = ud.data(forKey: "kino.history.v1"), let v = try? JSONDecoder().decode([Watch].self, from: d) { history = v }
        if let d = ud.data(forKey: "kino.pos.v1"), let v = try? JSONDecoder().decode([String: Pos].self, from: d) { positions = v }
    }

    private func save<T: Encodable>(_ v: T, _ key: String) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
    }

    func isFavorite(_ i: KinoItem) -> Bool { favorites.contains { $0.id == i.id } }
    func toggleFavorite(_ i: KinoItem) {
        if isFavorite(i) { favorites.removeAll { $0.id == i.id } } else { favorites.insert(i, at: 0) }
        save(favorites, "kino.fav.v1")
        Haptics.tap()
    }

    func watch(_ i: KinoItem) -> Watch? { history.first { $0.item.id == i.id } }

    func record(_ i: KinoItem, season: Int?, episode: Int?, translation: String?) {
        var h = history.filter { $0.item.id != i.id }
        var item = i
        if let old = history.first(where: { $0.item.id == i.id }) {
            // не теряем описание и постер, если пришли из короткой карточки
            if item.desc == nil { item.desc = old.item.desc }
            if item.poster == nil { item.poster = old.item.poster }
        }
        h.insert(Watch(item: item, season: season, episode: episode, translation: translation, updated: Date()), at: 0)
        history = Array(h.prefix(200))
        save(history, "kino.history.v1")
    }

    func removeHistory(_ i: KinoItem) {
        history.removeAll { $0.item.id == i.id }
        save(history, "kino.history.v1")
    }

    static func posKey(_ id: Int, _ s: Int?, _ e: Int?) -> String { "\(id)-\(s ?? 0)-\(e ?? 0)" }
    func position(_ id: Int, _ s: Int?, _ e: Int?) -> Pos? { positions[Self.posKey(id, s, e)] }
    func setPosition(_ id: Int, _ s: Int?, _ e: Int?, t: Double, d: Double) {
        positions[Self.posKey(id, s, e)] = Pos(t: t, d: d)
        save(positions, "kino.pos.v1")
    }
    func watched(_ id: Int, _ s: Int?, _ e: Int?) -> Bool {
        guard let p = position(id, s, e), p.d > 0 else { return false }
        return p.t / p.d > 0.9
    }
}

// MARK: - Мелкие виды

struct KinoImage: View {
    let url: URL?
    var maxPixel: CGFloat = 480
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Rectangle().fill(.quaternary)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().allowsHitTesting(false)
                } else if failed {
                    Image(systemName: "film").foregroundStyle(.secondary)
                }
            }
            .clipped()
            .task(id: url) {
                guard let url else { failed = true; return }
                let key = ImageCache.key(url, maxPixel)
                if let c = ImageCache.shared.object(forKey: key) { image = c; return }
                if let img = await KinoNet.shared.image(url, maxPixel: maxPixel) {
                    ImageCache.store(img, key)
                    withAnimation(.easeOut(duration: 0.2)) { image = img }
                } else if !Task.isCancelled { failed = true }
            }
    }
}

struct KinoPoster: View {
    let item: KinoItem
    var width: CGFloat = 118
    var subtitle: String? = nil
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            KinoImage(url: item.posterURL(), maxPixel: width * 3)
                .frame(width: width, height: width * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if let r = item.rating, !r.isEmpty { RatingBadge(text: r, compact: true).padding(6) }
                }
                .overlay(alignment: .topTrailing) {
                    if let q = item.quality, q.contains("4K") || q.contains("2160") {
                        Text("4K").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Theme.accent, in: Capsule()).padding(6)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let progress {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.black.opacity(0.45))
                                Capsule().fill(Theme.accent).frame(width: max(4, g.size.width * min(progress, 1)))
                            }
                        }
                        .frame(height: 4).padding(8)
                    }
                }
            Text(item.title.noHyphens)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .leading)
            let sub = subtitle ?? item.badge ?? item.meta.prefix(2).joined(separator: " · ")
            if !sub.isEmpty {
                Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Переход на страницу тайтла
struct KinoLink<Label: View>: View {
    let item: KinoItem
    var season: Int? = nil
    var episode: Int? = nil
    @ViewBuilder let label: () -> Label
    @ObservedObject private var store = KinoStore.shared

    var body: some View {
        NavigationLink {
            KinoDetailView(item: item, startSeason: season, startEpisode: episode)
        } label: { label() }
        .buttonStyle(.pressable)
        .contextMenu {
            Button { store.toggleFavorite(item) } label: {
                SwiftUI.Label(store.isFavorite(item) ? "Убрать из избранного" : "В избранное",
                              systemImage: store.isFavorite(item) ? "heart.slash" : "heart")
            }
            if let u = item.pageURL {
                ShareLink(item: u) { SwiftUI.Label("Поделиться", systemImage: "square.and.arrow.up") }
            }
        }
    }
}

private struct KinoRail: View {
    let title: String
    let items: [KinoItem]
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, action: action).padding(.horizontal, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { it in KinoLink(item: it) { KinoPoster(item: it) } }
                }
                .padding(.horizontal, 14)
            }
        }
    }
}

private struct KinoSearchField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Фильмы и сериалы", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .glassShape(Capsule())
    }
}

/// Результаты поиска списком
private struct KinoSearchResults: View {
    let query: String
    @State private var items: [KinoItem] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            if loading && items.isEmpty { ProgressView().padding(30) }
            if let error, items.isEmpty { Text(error).font(.footnote).foregroundStyle(.secondary).padding(20) }
            if !loading && error == nil && items.isEmpty && query.count >= 2 {
                Text("Ничего не нашлось").foregroundStyle(.secondary).padding(30)
            }
            ForEach(items) { it in
                KinoLink(item: it) {
                    HStack(spacing: 12) {
                        KinoImage(url: it.posterURL(), maxPixel: 200)
                            .frame(width: 50, height: 75)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(it.title.noHyphens).font(.subheadline.weight(.semibold)).lineLimit(2)
                                .multilineTextAlignment(.leading).foregroundStyle(.primary)
                            Text(it.meta.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        if let r = it.rating, !r.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.accent)
                                Text(r).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(.primary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                }
                Divider().padding(.leading, 76)
            }
        }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { items = []; return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            loading = true
            defer { loading = false }
            do { items = try await KinoAPI.search(q); error = nil }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

// MARK: - Главная

@MainActor
final class KinoHomeModel: ObservableObject {
    @Published var home = KinoAPI.Home()
    @Published var loading = false
    @Published var error: String?

    func load(force: Bool = false) async {
        if loading || (!force && (!home.decks.isEmpty || !home.updates.isEmpty)) { return }
        loading = true
        defer { loading = false }
        do { home = try await KinoAPI.home(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct KinoHomeView: View {
    @StateObject private var vm = KinoHomeModel()
    @ObservedObject private var store = KinoStore.shared
    @State private var query = ""

    static let collections: [(String, String)] = [
        ("Топ-100 фильмов", "/podborki/top-100-filmov/"), ("Топ-100 сериалов", "/podborki/top-100-serialov/"),
        ("Лучшие фильмы 2026", "/podborki/luchshie-filmy-2026/"), ("Лучшие сериалы 2026", "/podborki/luchshie-serialy-2026/"),
        ("Топ-100 мультфильмов", "/podborki/top-100-multfilmov/"), ("Топ-100 аниме", "/podborki/top-100-anime/"),
        ("Лучшие русские фильмы", "/podborki/luchshie-russkie-filmy/"), ("Лучшие русские сериалы", "/podborki/luchshie-russkie-serialy/"),
        ("В 4K", "/podborki/4k/"), ("Про космос", "/podborki/kosmos/"), ("Зомби", "/podborki/zombi/"),
        ("Вампиры", "/podborki/vampiry/"), ("Катастрофы", "/podborki/katastrofy/"), ("Хакеры", "/podborki/hakery/"),
        ("Маньяки", "/podborki/manyaki/"), ("Реальные события", "/podborki/realnye-sobytiya/"),
        ("Про любовь", "/podborki/pro-lyubov/"), ("Подростки", "/podborki/podrostki/"),
        ("Новый год", "/podborki/novyj-god/"), ("Хеллоуин", "/podborki/hellouin/"),
        ("Про роботов", "/podborki/pro-robotov/"), ("Про инопланетян", "/podborki/pro-inoplanetyan/"),
        ("Про динозавров", "/podborki/pro-dinozavrov/"), ("Про собак", "/podborki/pro-sobak/"),
        ("Про врачей", "/podborki/pro-vrachej/"), ("Про полицию", "/podborki/pro-policiyu/"),
        ("Про тюрьму", "/podborki/pro-tyurmu/"), ("Акулы", "/podborki/akuly/"), ("Танцы", "/podborki/tancy/"),
        ("Великая Отечественная", "/podborki/velikaya-otechestvennaya/"), ("Для слабослышащих", "/podborki/dlya-slaboslyshashchih/")
    ]

    private var continueItems: [KinoStore.Watch] { Array(store.history.prefix(12)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Кино").font(.largeTitle.bold())
                        KinoSearchField(text: $query)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        KinoSearchResults(query: query)
                    } else {
                        if !continueItems.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Продолжить смотреть").padding(.horizontal, 14)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(alignment: .top, spacing: 12) {
                                        ForEach(continueItems) { w in
                                            KinoLink(item: w.item, season: w.season, episode: w.episode) {
                                                KinoPoster(item: w.item, width: 128,
                                                           subtitle: w.season.map { "\($0) сез. \(w.episode ?? 1) серия" } ?? w.item.kindTitle,
                                                           progress: store.position(w.item.id, w.season, w.episode).flatMap { $0.d > 0 ? $0.t / $0.d : nil })
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                }
                            }
                        }

                        if vm.loading && vm.home.decks.isEmpty {
                            ProgressView().frame(maxWidth: .infinity).padding(40)
                        }
                        if let e = vm.error, vm.home.decks.isEmpty {
                            VStack(spacing: 10) {
                                Text(e).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                Button("Повторить") { Task { await vm.load(force: true) } }.foregroundStyle(Theme.accent)
                            }
                            .frame(maxWidth: .infinity).padding(30)
                        }

                        ForEach(Array(vm.home.decks.enumerated()), id: \.offset) { i, deck in
                            KinoRail(title: deck.0, items: deck.1) {
                                let path: String
                                switch deck.0 {
                                case "Фильмы": path = "/film/"
                                case "Сериалы": path = "/serial/"
                                case "Мультфильмы": path = "/multfilm/"
                                case "Аниме": path = "/anime/"
                                case "ТВ-шоу": path = "/tv-shou/"
                                default: path = "/"
                                }
                                KinoRouter.shared.open(path: path, title: deck.0)
                            }
                            if i == 0, !vm.home.updates.isEmpty { updatesBlock }
                        }

                        if !vm.home.decks.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Подборки").padding(.horizontal, 14)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(Self.collections, id: \.1) { c in
                                            NavigationLink {
                                                KinoListView(title: c.0, path: c.1, sort: .popular)
                                            } label: {
                                                Text(c.0).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                                    .background(Theme.chip, in: Capsule())
                                            }
                                            .buttonStyle(.pressable)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                }
                            }
                        }
                    }
                    Color.clear.frame(height: 100)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await vm.load(force: true) }
            .statusBarBlur()
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .task { await vm.load() }
        }
    }

    @ViewBuilder
    private var updatesBlock: some View {
        ForEach(Array(vm.home.updates.enumerated()), id: \.offset) { _, sec in
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: sec.0).padding(.horizontal, 14)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(sec.1.enumerated()), id: \.offset) { _, u in
                            KinoLink(item: u.0, season: u.1, episode: u.2) { KinoPoster(item: u.0, width: 110) }
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
    }
}

/// Переход из Главной в Каталог с нужным разделом
@MainActor
final class KinoRouter: ObservableObject {
    static let shared = KinoRouter()
    @Published var pending: (path: String, title: String)?
    func open(path: String, title: String) {
        pending = (path, title)
        AppRouter.shared.tab = 1
    }
}

// MARK: - Список (раздел, жанр, подборка)

struct KinoListView: View {
    let title: String
    let path: String
    @State var sort: KinoAPI.Sort
    @State private var items: [KinoItem] = []
    @State private var page = 0
    @State private var pages = 1
    @State private var loading = false
    @State private var error: String?
    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 14, alignment: .top)]

    private func reload() async {
        items = []; page = 0; pages = 1; error = nil
        await more()
    }

    private func more() async {
        guard !loading, page < pages else { return }
        loading = true
        defer { loading = false }
        do {
            let r = try await KinoAPI.list(path: path, sort: sort, page: page + 1)
            var seen = Set(items.map(\.id))
            items += r.items.filter { seen.insert($0.id).inserted }
            page += 1
            pages = max(r.pages, r.items.isEmpty ? page : page)
            if r.items.isEmpty { pages = page }
        } catch { self.error = error.localizedDescription }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(items) { it in
                    KinoLink(item: it) {
                        GeometryReader { g in KinoPoster(item: it, width: g.size.width) }
                            .aspectRatio(0.5, contentMode: .fit)
                    }
                    .onAppear { if it.id == items.last?.id { Task { await more() } } }
                }
            }
            .padding(14)
            if loading { ProgressView().padding() }
            if let error, items.isEmpty {
                VStack(spacing: 10) {
                    Text(error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Повторить") { Task { await reload() } }.foregroundStyle(Theme.accent)
                }
                .padding(30)
            }
            Color.clear.frame(height: 90)
        }
        .background(AppBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Сортировка", selection: $sort) {
                        ForEach(KinoAPI.Sort.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
            }
        }
        .onChange(of: sort) { _ in Task { await reload() } }
        .task { if items.isEmpty { await more() } }
    }
}

// MARK: - Каталог

struct KinoCatalogView: View {
    @ObservedObject private var router = KinoRouter.shared
    @State private var query = ""
    @State private var type = "/"
    @State private var filterPath: String?
    @State private var filterTitle: String?
    @State private var sort: KinoAPI.Sort = .popular
    @State private var reloadKey = 0

    static let types: [(String, String)] = [("Всё", "/"), ("Фильмы", "/film/"), ("Сериалы", "/serial/"),
                                            ("Мультфильмы", "/multfilm/"), ("Аниме", "/anime/"), ("ТВ-шоу", "/tv-shou/")]
    static let genres: [(String, String)] = [
        ("Биографии", "biografii"), ("Боевики", "boeviki"), ("Вестерны", "vesterny"), ("Военные", "voennoe-kino"),
        ("Детективы", "detektivy"), ("Документальные", "dokumentalnoe-kino"), ("Драмы", "dramy"),
        ("Исторические", "istoricheskie-filmy"), ("Комедии", "komedii"), ("Криминал", "kriminalnye-filmy"),
        ("Мелодрамы", "melodramy"), ("Музыкальные", "muzykalnye-filmy"), ("Мюзиклы", "myuzikly"),
        ("Приключения", "priklyucheniya"), ("Семейные", "semeynoe-kino"), ("Спорт", "sport"),
        ("Триллеры", "trillery"), ("Ужасы", "uzhasy"), ("Фантастика", "fantastika"), ("Фэнтези", "fentezi")
    ]
    static let countries: [(String, String)] = [
        ("США", "ssha"), ("Россия", "rossiya"), ("СССР", "sssr"), ("Великобритания", "velikobritaniya"),
        ("Франция", "franciya"), ("Германия", "germaniya"), ("Италия", "italiya"), ("Южная Корея", "koreya-yuzhnaya"),
        ("Индия", "indiya"), ("Турция", "turciya")
    ]
    static let voices: [(String, String)] = [
        ("LostFilm", "lostfilm"), ("HDrezka Studio", "hdrezka-studio"), ("Кубик в Кубе", "kubik-v-kube"),
        ("NewStudio", "newstudio"), ("TVShows", "tvshows"), ("AlexFilm", "alexfilm"), ("BaibaKo", "baibako"),
        ("ColdFilm", "coldfilm"), ("Jaskier", "jaskier"), ("Goblin", "goblin"), ("AniLibria", "anilibria"),
        ("AniDub", "anidub"), ("Animaunt", "animaunt"), ("SHIZA Project", "shiza-project"),
        ("Red Head Sound", "red-head-sound"), ("Кураж-Бамбей", "kurazh-bambey"), ("NewComers", "newcomers")
    ]

    private var path: String { filterPath ?? type }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Каталог").font(.largeTitle.bold()).padding(.horizontal, 14).padding(.top, 10)
                    KinoSearchField(text: $query).padding(.horizontal, 14)
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        KinoSearchResults(query: query)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.types, id: \.1) { t in
                                    chip(t.0, on: filterPath == nil && type == t.1) {
                                        type = t.1; filterPath = nil; filterTitle = nil
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                        HStack(spacing: 8) {
                            Menu {
                                Picker("Сортировка", selection: $sort) {
                                    ForEach(KinoAPI.Sort.allCases, id: \.self) { Text($0.title).tag($0) }
                                }
                            } label: { menuPill(sort.title, icon: "arrow.up.arrow.down") }
                            Menu {
                                Menu("Жанр") {
                                    ForEach(Self.genres, id: \.1) { g in
                                        Button(g.0) { setFilter("/genre/\(g.1)/", g.0) }
                                    }
                                }
                                Menu("Страна") {
                                    ForEach(Self.countries, id: \.1) { c in
                                        Button(c.0) { setFilter("/country/\(c.1)/", c.0) }
                                    }
                                }
                                Menu("Год") {
                                    ForEach((2000...2026).reversed(), id: \.self) { y in
                                        Button("\(y)") { setFilter("/year/\(y)/", "\(y)") }
                                    }
                                }
                                Menu("Озвучка") {
                                    ForEach(Self.voices, id: \.1) { v in
                                        Button(v.0) { setFilter("/ozvucheno/\(v.1)/", v.0) }
                                    }
                                }
                                Menu("Подборка") {
                                    ForEach(KinoHomeView.collections, id: \.1) { c in
                                        Button(c.0) { setFilter(c.1, c.0) }
                                    }
                                }
                                if filterPath != nil {
                                    Button("Сбросить", role: .destructive) { filterPath = nil; filterTitle = nil }
                                }
                            } label: { menuPill(filterTitle ?? "Фильтр", icon: "line.3.horizontal.decrease") }
                            Spacer()
                        }
                        .padding(.horizontal, 14)

                        KinoGrid(path: path, sort: sort)
                            .id("\(path)|\(sort.rawValue)|\(reloadKey)")
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { reloadKey += 1 }
            .statusBarBlur()
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: applyPending)
            .onChange(of: router.pending?.path) { _ in applyPending() }
        }
    }

    private func applyPending() {
        guard let p = router.pending else { return }
        router.pending = nil
        if Self.types.contains(where: { $0.1 == p.path }) { type = p.path; filterPath = nil; filterTitle = nil }
        else { filterPath = p.path; filterTitle = p.title }
    }

    private func setFilter(_ p: String, _ t: String) { filterPath = p; filterTitle = t }

    private func chip(_ t: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.select(); action() } label: {
            Text(t).font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? Color.white : Color.primary)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.chip), in: Capsule())
        }
        .buttonStyle(.pressable)
    }

    private func menuPill(_ t: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption.weight(.bold))
            Text(t).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.accent.opacity(0.12), in: Capsule())
    }
}

/// Сетка с бесконечной прокруткой
private struct KinoGrid: View {
    let path: String
    let sort: KinoAPI.Sort
    @State private var items: [KinoItem] = []
    @State private var page = 0
    @State private var pages = 1
    @State private var loading = false
    @State private var error: String?
    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 14, alignment: .top)]

    private func more() async {
        guard !loading, page < pages else { return }
        loading = true
        defer { loading = false }
        do {
            let r = try await KinoAPI.list(path: path, sort: sort, page: page + 1)
            var seen = Set(items.map(\.id))
            items += r.items.filter { seen.insert($0.id).inserted }
            page += 1
            pages = r.items.isEmpty ? page : max(r.pages, page)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    var body: some View {
        VStack {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(items) { it in
                    KinoLink(item: it) {
                        GeometryReader { g in KinoPoster(item: it, width: g.size.width) }
                            .aspectRatio(0.5, contentMode: .fit)
                    }
                    .onAppear { if it.id == items.last?.id { Task { await more() } } }
                }
            }
            .padding(.horizontal, 14)
            if loading { ProgressView().padding() }
            if let error, items.isEmpty {
                VStack(spacing: 10) {
                    Text(error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Повторить") { Task { await more() } }.foregroundStyle(Theme.accent)
                }
                .padding(30)
            }
            Color.clear.frame(height: 100)
        }
        .task { if items.isEmpty { await more() } }
    }
}

// MARK: - Избранное

struct KinoFavoritesView: View {
    @ObservedObject private var store = KinoStore.shared
    @State private var tab = 0
    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 14, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Избранное").font(.largeTitle.bold()).padding(.horizontal, 14).padding(.top, 10)
                    Picker("", selection: $tab) {
                        Text("Избранное \(store.favorites.count)").tag(0)
                        Text("История \(store.history.count)").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 14)

                    if tab == 0 {
                        if store.favorites.isEmpty {
                            empty("Пока пусто. Открой фильм и нажми сердечко.", icon: "heart.slash")
                        }
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(store.favorites) { it in
                                let w = store.watch(it)
                                KinoLink(item: it, season: w?.season, episode: w?.episode) {
                                    GeometryReader { g in
                                        KinoPoster(item: it, width: g.size.width,
                                                   subtitle: w?.season.map { "\($0) сез. \(w?.episode ?? 1) серия" })
                                    }
                                    .aspectRatio(0.5, contentMode: .fit)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                    } else {
                        if store.history.isEmpty { empty("Здесь будет то, что ты смотрел.", icon: "clock") }
                        ForEach(store.history) { w in
                            KinoLink(item: w.item, season: w.season, episode: w.episode) {
                                HStack(spacing: 12) {
                                    KinoImage(url: w.item.posterURL(), maxPixel: 200)
                                        .frame(width: 50, height: 75)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(w.item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                            .foregroundStyle(.primary).multilineTextAlignment(.leading)
                                        Text([w.season.map { "\($0) сезон, \(w.episode ?? 1) серия" }, w.translation]
                                            .compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        Text(w.updated.formatted(.relative(presentation: .named)))
                                            .font(.caption2).foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 14).padding(.vertical, 4)
                            }
                            .swipeActions { Button("Убрать", role: .destructive) { store.removeHistory(w.item) } }
                            .contextMenu { Button("Убрать из истории", role: .destructive) { store.removeHistory(w.item) } }
                        }
                    }
                    Color.clear.frame(height: 100)
                }
            }
            .statusBarBlur()
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func empty(_ t: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(t).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
    }
}

// MARK: - Страница тайтла

struct KinoDetailView: View {
    let item: KinoItem
    var startSeason: Int? = nil
    var startEpisode: Int? = nil
    @ObservedObject private var store = KinoStore.shared
    @State private var detail: KinoDetail?
    @State private var error: String?
    @State private var season = 1
    @State private var sourceIndex = 0
    @State private var playing: KinoPlayRequest?
    @State private var webPlayer: KinoWebTarget?
    @State private var showAllInfo = false
    @AppStorage("kino.pref.translation") private var prefTranslation = ""

    private var shown: KinoItem { detail?.item ?? item }
    private var source: KinoSource? {
        guard let d = detail, !d.sources.isEmpty else { return nil }
        return d.sources[min(sourceIndex, d.sources.count - 1)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let error, detail == nil {
                    VStack(spacing: 10) {
                        Text(error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Повторить") { Task { await load() } }.foregroundStyle(Theme.accent)
                    }
                    .frame(maxWidth: .infinity)
                }
                if detail == nil && error == nil { ProgressView().frame(maxWidth: .infinity).padding(20) }
                if let d = detail {
                    playBlock(d)
                    if d.isSerial { episodesBlock(d) }
                    infoBlock(d)
                }
                Color.clear.frame(height: 90)
            }
        }
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    if let u = shown.pageURL { ShareLink(item: u) { Image(systemName: "square.and.arrow.up") } }
                    Button { store.toggleFavorite(shown) } label: {
                        Image(systemName: store.isFavorite(shown) ? "heart.fill" : "heart")
                            .foregroundStyle(store.isFavorite(shown) ? Color.pink : Theme.accent)
                    }
                }
            }
        }
        .fullScreenCover(item: $playing) { req in KinoPlayerScreen(request: req) }
        .fullScreenCover(item: $webPlayer) { t in KinoWebPlayerScreen(url: t.url, title: shown.title) }
        .task { if detail == nil { await load() } }
    }

    private func load() async {
        error = nil
        do {
            let d = try await KinoAPI.detail(item)
            detail = d
            let w = store.watch(item)
            if let t = w?.translation ?? (prefTranslation.isEmpty ? nil : prefTranslation),
               let i = d.sources.firstIndex(where: { $0.translation == t }) { sourceIndex = i }
            if let s = startSeason ?? w?.season, d.seasons.contains(s) { season = s }
            else { season = d.seasons.first ?? 1 }
        } catch { self.error = error.localizedDescription }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            KinoImage(url: shown.posterURL(big: true), maxPixel: 600)
                .frame(width: 130, height: 195)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
            VStack(alignment: .leading, spacing: 6) {
                Text(shown.title.noHyphens).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                if let o = shown.orig { Text(o).font(.subheadline).foregroundStyle(.secondary) }
                Text(([shown.kindTitle] + shown.meta.prefix(3)).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let r = shown.rating, !r.isEmpty { RatingBadge(text: r) }
                    if let q = detail?.info.first(where: { $0.0 == "Качество" })?.1 ?? shown.quality {
                        Text(q).font(.caption.bold()).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Theme.accent.opacity(0.14), in: Capsule())
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .background(alignment: .top) {
            KinoImage(url: shown.posterURL(), maxPixel: 300)
                .frame(height: 260)
                .blur(radius: 40)
                .opacity(0.45)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .offset(y: -60)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func playBlock(_ d: KinoDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if d.sources.isEmpty {
                Text("Плеер не найден" + (d.playersNote.map { ": " + $0 } ?? "") + ".")
                    .font(.footnote).foregroundStyle(.secondary)
                if let u = shown.pageURL {
                    Button { webPlayer = KinoWebTarget(url: u) } label: {
                        Label("Открыть страницу сайта", systemImage: "safari")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                }
            } else {
                let w = store.watch(shown)
                let s = d.isSerial ? (w?.season ?? startSeason ?? d.seasons.first) : nil
                let e = d.isSerial ? (w?.episode ?? startEpisode ?? d.episodes(s ?? 1, source: source).first) : nil
                if let src = source, !src.isNative {
                    Text("Этот плеер откроется как на сайте: озвучку и серии выбирай внутри него.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    play(d, season: startSeason ?? s, episode: startEpisode ?? e)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        if let s = startSeason ?? s, let e = startEpisode ?? e {
                            Text(w != nil ? "Продолжить · \(s) сезон, \(e) серия" : "Смотреть · \(s) сезон, \(e) серия")
                        } else {
                            Text(w != nil ? "Продолжить" : "Смотреть")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressable)

                if d.sources.count > 1 {
                    Menu {
                        ForEach(Array(d.sources.enumerated()), id: \.offset) { i, src in
                            Button {
                                sourceIndex = i
                                prefTranslation = src.translation
                            } label: {
                                if i == sourceIndex { SwiftUI.Label(src.translation, systemImage: "checkmark") }
                                else { Text([src.translation, src.quality].compactMap { $0 }.joined(separator: " · ")) }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "waveform")
                            Text("Озвучка: \(source?.translation ?? "")").lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.caption)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func episodesBlock(_ d: KinoDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Серии").font(.title3.bold())
                Spacer()
                if d.seasons.count > 1 {
                    Menu {
                        ForEach(d.seasons, id: \.self) { s in Button("\(s) сезон") { season = s } }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(season) сезон")
                            Image(systemName: "chevron.down").font(.caption.bold())
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
            let eps = d.episodes(season, source: source)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                ForEach(eps, id: \.self) { e in
                    let seen = store.watched(shown.id, season, e)
                    let last = store.watch(shown).map { $0.season == season && $0.episode == e } ?? false
                    Button { play(d, season: season, episode: e) } label: {
                        VStack(spacing: 2) {
                            Text("\(e)").font(.headline.monospacedDigit())
                            if let date = d.dates[season]?[e], !date.isEmpty {
                                Text(shortDate(date)).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(last ? Color.white : (seen ? Color.secondary : Color.primary))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(last ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.card),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            if seen && !last {
                                Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy))
                                    .foregroundStyle(Theme.accent).padding(5)
                            }
                        }
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private func shortDate(_ s: String) -> String {
        let p = s.split(separator: "-")
        guard p.count == 3 else { return s }
        return "\(p[2]).\(p[1]).\(p[0].suffix(2))"
    }

    @ViewBuilder
    private func infoBlock(_ d: KinoDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let desc = d.item.desc, !desc.isEmpty {
                Text(desc.noHyphens).font(.subheadline).foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(showAllInfo ? nil : 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !d.genres.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(d.genres, id: \.self) { g in
                        Text(g).font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.chip, in: Capsule())
                    }
                }
            }
            let rows = showAllInfo ? d.info : Array(d.info.prefix(6))
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    HStack(alignment: .top) {
                        Text(r.0).font(.subheadline).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
                        Text(r.1).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 7)
                    Divider().opacity(0.4)
                }
                if !d.actors.isEmpty && showAllInfo {
                    HStack(alignment: .top) {
                        Text("В ролях").font(.subheadline).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
                        Text(d.actors.joined(separator: ", ")).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 7)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if d.info.count > 6 || !d.actors.isEmpty || (d.item.desc?.count ?? 0) > 300 {
                Button(showAllInfo ? "Свернуть" : "Подробнее") { withAnimation { showAllInfo.toggle() } }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 14)
    }

    private func play(_ d: KinoDetail, season: Int?, episode: Int?) {
        guard let src = source else { return }
        Haptics.tap()
        if !src.isNative {
            store.record(shown, season: nil, episode: nil, translation: src.translation)
            webPlayer = KinoWebTarget(url: src.url)
            return
        }
        var eps: [(Int, Int)] = []
        if d.isSerial {
            for s in d.seasons { for e in d.episodes(s, source: src) { eps.append((s, e)) } }
        }
        playing = KinoPlayRequest(item: shown, sources: d.sources, sourceIndex: min(sourceIndex, d.sources.count - 1),
                                  season: d.isSerial ? season : nil, episode: d.isSerial ? episode : nil,
                                  episodes: eps.map { KinoPlayRequest.Ep(season: $0.0, episode: $0.1) })
    }
}

// MARK: - Плеер

struct KinoPlayRequest: Identifiable {
    struct Ep: Hashable { let season: Int; let episode: Int }
    let id = UUID()
    let item: KinoItem
    let sources: [KinoSource]
    var sourceIndex: Int
    var season: Int?
    var episode: Int?
    var episodes: [Ep]
}

@MainActor
final class KinoPlayerModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var stream: KinoStream?
    @Published var track = 0
    @Published var quality = 0
    @Published var loading = false
    @Published var error: String?
    @Published var time: Double = 0
    @Published var duration: Double = 0
    @Published var ended = false

    private var observer: Any?
    private var endObs: NSObjectProtocol?
    private var key: (Int, Int?, Int?) = (0, nil, nil)

    func load(_ src: KinoSource, item: KinoItem, season: Int?, episode: Int?, keepTrack: String?) async {
        stop()
        loading = true
        error = nil
        ended = false
        key = (item.id, season, episode)
        defer { loading = false }
        do {
            let s = try await KinoAPI.stream(src, season: season, episode: episode)
            stream = s
            track = keepTrack.flatMap { t in s.tracks.firstIndex { $0.label == t } } ?? 0
            quality = 0
            let resume = KinoStore.shared.position(item.id, season, episode).flatMap { $0.d > 0 && $0.t / $0.d < 0.95 ? $0.t : nil }
            start(at: resume ?? 0)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func start(at t: Double) {
        guard let s = stream, s.tracks.indices.contains(track) else { return }
        let tr = s.tracks[track]
        guard tr.qualities.indices.contains(quality), let url = tr.qualities[quality].1.first else { return }
        let headers = ["Referer": s.origin + "/", "Origin": s.origin, "User-Agent": KinoNet.ua]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let itemAV = AVPlayerItem(asset: asset)
        if let p = player {
            p.replaceCurrentItem(with: itemAV)
        } else {
            player = AVPlayer(playerItem: itemAV)
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        if t > 1 { player?.seek(to: CMTime(seconds: t, preferredTimescale: 600)) }
        player?.play()
        observe(itemAV)
    }

    /// Смена дорожки или качества с того же места
    func switchTo(track: Int? = nil, quality: Int? = nil) {
        let t = player?.currentTime().seconds ?? 0
        if let track { self.track = track; self.quality = 0 }
        if let quality { self.quality = quality }
        start(at: t.isFinite ? t : 0)
    }

    private func observe(_ it: AVPlayerItem) {
        if let o = observer { player?.removeTimeObserver(o) }
        observer = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 2), queue: .main) { [weak self] tm in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.time = tm.seconds.isFinite ? tm.seconds : 0
                let d = self.player?.currentItem?.duration.seconds ?? 0
                self.duration = d.isFinite ? d : 0
                if Int(self.time) % 5 == 0, self.duration > 0 {
                    KinoStore.shared.setPosition(self.key.0, self.key.1, self.key.2, t: self.time, d: self.duration)
                }
            }
        }
        if let e = endObs { NotificationCenter.default.removeObserver(e) }
        endObs = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: it, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.duration > 0 {
                    KinoStore.shared.setPosition(self.key.0, self.key.1, self.key.2, t: self.duration, d: self.duration)
                }
                self.ended = true
            }
        }
    }

    func stop() {
        if duration > 0, time > 0 {
            KinoStore.shared.setPosition(key.0, key.1, key.2, t: time, d: duration)
        }
        if let o = observer { player?.removeTimeObserver(o); observer = nil }
        if let e = endObs { NotificationCenter.default.removeObserver(e); endObs = nil }
        player?.pause()
    }

    func skipIntro() {
        guard let r = stream?.skip else { return }
        player?.seek(to: CMTime(seconds: r.upperBound, preferredTimescale: 600))
    }
}

struct KinoPlayerScreen: View {
    @State var request: KinoPlayRequest
    @StateObject private var vm = KinoPlayerModel()
    @ObservedObject private var store = KinoStore.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("set.autoNext") private var autoNext = true
    @AppStorage("kino.pref.translation") private var prefTranslation = ""

    private var source: KinoSource { request.sources[min(request.sourceIndex, request.sources.count - 1)] }
    private var index: Int? {
        guard let s = request.season, let e = request.episode else { return nil }
        return request.episodes.firstIndex(of: .init(season: s, episode: e))
    }
    private var next: KinoPlayRequest.Ep? {
        guard let i = index, i + 1 < request.episodes.count else { return nil }
        return request.episodes[i + 1]
    }
    private var prev: KinoPlayRequest.Ep? {
        guard let i = index, i > 0 else { return nil }
        return request.episodes[i - 1]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { vm.stop(); dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Color.white.opacity(0.12), in: Circle())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.item.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                    if let s = request.season, let e = request.episode {
                        Text("\(s) сезон, \(e) серия").font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            ZStack {
                Color.black
                if let p = vm.player {
                    FullscreenPlayer(player: p)
                }
                if vm.loading { ProgressView().tint(.white) }
                if let e = vm.error {
                    VStack(spacing: 10) {
                        Text(e).font(.footnote).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                        Button("Повторить") { Task { await reload() } }.foregroundStyle(Theme.accent)
                    }
                    .padding()
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    controls
                    if !request.episodes.isEmpty { episodesStrip }
                }
                .padding(14)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { await reload() }
        .onChange(of: vm.ended) { e in
            if e, autoNext, let n = next { go(n) }
        }
        .onDisappear { vm.stop() }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if request.sources.count > 1 {
                    Menu {
                        ForEach(Array(request.sources.enumerated()), id: \.offset) { i, s in
                            Button {
                                request.sourceIndex = i
                                prefTranslation = s.translation
                                Task { await reload() }
                            } label: {
                                if i == request.sourceIndex { SwiftUI.Label(s.translation, systemImage: "checkmark") }
                                else { Text(s.translation) }
                            }
                        }
                    } label: { pill(source.translation, icon: "person.wave.2") }
                }
                if let s = vm.stream, s.tracks.count > 1 {
                    Menu {
                        ForEach(Array(s.tracks.enumerated()), id: \.offset) { i, t in
                            Button { vm.switchTo(track: i) } label: {
                                if i == vm.track { SwiftUI.Label(t.label, systemImage: "checkmark") } else { Text(t.label) }
                            }
                        }
                    } label: { pill(s.tracks[vm.track].label, icon: "waveform") }
                }
                if let s = vm.stream, s.tracks.indices.contains(vm.track) {
                    let qs = s.tracks[vm.track].qualities
                    Menu {
                        ForEach(Array(qs.enumerated()), id: \.offset) { i, q in
                            Button { vm.switchTo(quality: i) } label: {
                                if i == vm.quality { SwiftUI.Label("\(q.0)p", systemImage: "checkmark") } else { Text("\(q.0)p") }
                            }
                        }
                    } label: { pill(qs.indices.contains(vm.quality) ? "\(qs[vm.quality].0)p" : "Качество", icon: "sparkles.tv") }
                }
            }
            if request.season != nil {
                HStack(spacing: 10) {
                    Button { if let p = prev { go(p) } } label: { pill("Предыдущая", icon: "backward.end.fill") }
                        .disabled(prev == nil).opacity(prev == nil ? 0.4 : 1)
                    Button { if let n = next { go(n) } } label: { pill("Следующая", icon: "forward.end.fill") }
                        .disabled(next == nil).opacity(next == nil ? 0.4 : 1)
                }
            }
        }
    }

    private var episodesStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Серии").font(.headline).foregroundStyle(.white)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(request.episodes, id: \.self) { ep in
                            let on = ep.season == request.season && ep.episode == request.episode
                            let seen = store.watched(request.item.id, ep.season, ep.episode)
                            Button { go(ep) } label: {
                                VStack(spacing: 1) {
                                    Text("\(ep.episode)").font(.headline.monospacedDigit())
                                    Text("\(ep.season) сез.").font(.system(size: 9))
                                }
                                .foregroundStyle(on ? Color.white : (seen ? Color.white.opacity(0.45) : Color.white))
                                .frame(width: 58, height: 50)
                                .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.1)),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .id(ep)
                        }
                    }
                }
                .onAppear {
                    if let s = request.season, let e = request.episode { proxy.scrollTo(KinoPlayRequest.Ep(season: s, episode: e), anchor: .center) }
                }
            }
        }
    }

    private func pill(_ t: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption.weight(.bold))
            Text(t).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.12), in: Capsule())
    }

    private func go(_ ep: KinoPlayRequest.Ep) {
        Haptics.tap()
        request.season = ep.season
        request.episode = ep.episode
        Task { await reload() }
    }

    private func reload() async {
        let keep = vm.stream.flatMap { $0.tracks.indices.contains(vm.track) ? $0.tracks[vm.track].label : nil }
        store.record(request.item, season: request.season, episode: request.episode, translation: source.translation)
        await vm.load(source, item: request.item, season: request.season, episode: request.episode, keepTrack: keep)
    }
}


// MARK: - Веб-плеер (для плееров, которые не открываются в родном)

struct KinoWebTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct KinoWebPlayerScreen: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Color.white.opacity(0.12), in: Circle())
                }
                Text(title).font(.headline).foregroundStyle(.white).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            KinoWebPlayer(url: url)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

struct KinoWebPlayer: UIViewRepresentable {
    let url: URL

    final class Coordinator: NSObject, WKUIDelegate {
        // реклама любит открывать новые окна — не пускаем
        func webView(_ v: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.allowsPictureInPictureMediaPlayback = true
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.customUserAgent = KinoNet.ua
        v.uiDelegate = context.coordinator
        v.isOpaque = false
        v.backgroundColor = .black
        v.scrollView.isScrollEnabled = url.host?.contains("kinomig") == true
        if url.host?.contains("kinomig") == true {
            v.load(URLRequest(url: url))
        } else {
            let html = """
            <!doctype html><html><head>
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
            <style>html,body{margin:0;height:100%;background:#000}
            iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style>
            </head><body>
            <iframe src="\(url.absoluteString)" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen referrerpolicy="origin"></iframe>
            </body></html>
            """
            v.loadHTMLString(html, baseURL: URL(string: KinoNet.base + "/"))
        }
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {}
}


// MARK: - Перехват ответа плеера в невидимом браузере

@MainActor
final class KinoSniffer: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var cont: CheckedContinuation<String, Error>?
    private var web: WKWebView?
    private static var live: KinoSniffer?

    static let script = """
    (function(){
      if (window.__kinoSniff) return; window.__kinoSniff = true;
      function hit(u){ return /\\/bnsi\\/movies\\//.test(String(u)); }
      function post(t){ try { window.webkit.messageHandlers.kinosniff.postMessage(String(t)); } catch (e) {} }
      function m3(u){ u = String(u || ''); if (/\\.m3u8/.test(u)) post('M3U8 ' + new URL(u, location.href).href); }
      var of = window.fetch;
      if (of) window.fetch = function(a, o){
        var u = typeof a === 'string' ? a : (a && a.url);
        m3(u);
        var p = of.apply(this, arguments);
        if (hit(u)) p.then(function(r){ r.clone().text().then(post); }).catch(function(){});
        return p;
      };
      var oo = XMLHttpRequest.prototype.open, os = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(m, u){ this.__u = u; m3(u); return oo.apply(this, arguments); };
      XMLHttpRequest.prototype.send = function(b){
        var x = this;
        if (hit(x.__u)) this.addEventListener('loadend', function(){ try { post(x.responseText); } catch (e) {} });
        return os.apply(this, arguments);
      };
    })();
    """

    /// Открывает страницу плеера и ждёт его ответ со ссылками (до 25 с)
    static func capture(_ url: URL) async throws -> String {
        let s = KinoSniffer()
        live = s
        defer { live = nil }
        return try await s.run(url)
    }

    private func run(_ url: URL) async throws -> String {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.userContentController.add(self, name: "kinosniff")
        cfg.userContentController.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let v = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 180), configuration: cfg)
        v.customUserAgent = KinoNet.ua
        v.navigationDelegate = self
        v.alpha = 0.01
        v.isUserInteractionEnabled = false
        if let w = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first { w.addSubview(v) }
        web = v
        // плеер открываем внутри страницы с адресом kinomig — как на сайте
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="margin:0;background:#000">
        <iframe src="\(url.absoluteString)" style="border:0;width:100%;height:100%;position:absolute" allow="autoplay; fullscreen"></iframe>
        </body></html>
        """
        v.loadHTMLString(html, baseURL: URL(string: KinoNet.base + "/"))
        defer { cleanup() }
        return try await withThrowingTaskGroup(of: String.self) { g in
            g.addTask { @MainActor in
                try await withCheckedThrowingContinuation { c in self.cont = c }
            }
            g.addTask {
                try await Task.sleep(nanoseconds: 25_000_000_000)
                throw KinoError.player("плеер не ответил")
            }
            let r = try await g.next()!
            g.cancelAll()
            return r
        }
    }

    private func cleanup() {
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "kinosniff")
        web?.stopLoading()
        web?.removeFromSuperview()
        web = nil
        if let c = cont { cont = nil; c.resume(throwing: KinoError.player("плеер не ответил")) }
    }

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        let body = m.body as? String ?? ""
        guard body.contains("hlsSource") || body.contains("m3u8"), let c = cont else { return }
        cont = nil
        c.resume(returning: body)
    }
}
