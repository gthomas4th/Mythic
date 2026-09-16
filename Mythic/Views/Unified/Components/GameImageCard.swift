//
//  GameImageCard.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 1/12/2025.
//

// Copyright © 2023-2025 vapidinfinity

import Foundation
import SwiftUI
import Shimmer
import CoreText

struct GameImageCard: View {
    var game: Game?
    var url: URL?
    @Binding var isImageEmpty: Bool
    
    var contentMode: ContentMode
    var withBlur: Bool
    var romArtworkKind: ROMArtworkKind
    @AppStorage("gameImageCardBlur") private var imageCardBlur: Double = 0.0
    
    /// - Note: `game` must be passed as a parameter in order to include fallback image URLs.
    init(game: Game? = nil, url: URL?, isImageEmpty: Binding<Bool>, withBlur: Bool = true,
         contentMode: ContentMode = .fill, romArtworkKind: ROMArtworkKind = .boxart) {
        self.game = game
        self.url = url
        self._isImageEmpty = isImageEmpty
        self.withBlur = withBlur
        self.contentMode = contentMode
        self.romArtworkKind = romArtworkKind
    }
    
    var body: some View {
        GeometryReader { geometry in
            if url == nil, let game = game as? ConnectionGame {
                ZStack {
                    HubTheme.blue.opacity(0.14)
                    Image(game.artworkAssetName)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .onAppear { isImageEmpty = false }
            } else if url == nil, let game = game as? ROMGame {
                ROMArtwork(title: game.title, system: game.source?.system ?? "Games",
                           kind: romArtworkKind, contentMode: contentMode)
            } else if let url, url.isFileURL {
                HubLocalArtworkImage(url: url, contentMode: contentMode, isImageEmpty: $isImageEmpty)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else if let url = url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .onAppear {
                                withAnimation { isImageEmpty = true }
                            }
                            .foregroundStyle(.quinary)
                    case .success(let image):
                        ZStack {
                            // blurred image as background
                            // save resources by only create this image if it'll be used for blur
                            if withBlur && (imageCardBlur > 0) {
                                // save resources by decreasing resolution scale of blurred image
                                let renderer: ImageRenderer = {
                                    let renderer = ImageRenderer(content: image)
                                    renderer.scale = 0.2
                                    return renderer
                                }()
                                
                                if let image = renderer.cgImage {
                                    Image(image, scale: 1, label: .init(""))
                                        .resizable()
                                        .blur(radius: imageCardBlur)
                                }
                            }
                            
                            image
                                .resizable()
                                .aspectRatio(contentMode: contentMode)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .modifier(FadeInModifier())
                                .onAppear {
                                    withAnimation { isImageEmpty = false }
                                }
                        }
                        .frame(width: geometry.size.width,
                               height: geometry.size.height)
                    case .failure(let error):
                        ContentUnavailableView(
                            "Unable to load the image.",
                            systemImage: "photo.badge.exclamationmark",
                            description: .init(error.localizedDescription)
                        )
                        .onAppear {
                            withAnimation { isImageEmpty = true }
                        }
                    @unknown default:
                        ContentUnavailableView(
                            "Unable to load the image.",
                            systemImage: "photo.badge.exclamationmark",
                            description: .init("Please check your internet connection, and try again.")
                        )
                        .onAppear {
                            withAnimation { isImageEmpty = true }
                        }
                    }
                }
                .frame(width: geometry.size.width,
                       height: geometry.size.height)
            } else if let game, game.isFallbackImageAvailable {
                GameImageCard.FallbackGameImageCard(game: .constant(game), withBlur: withBlur)
                    .padding()
                    .frame(width: geometry.size.width,
                           height: geometry.size.height)
            } else {
                ContentUnavailableView(
                    "Image Unavailable",
                    systemImage: "photo.badge.exclamationmark",
                    description: .init("""
                    This game doesn't have an image that Mythic can display in this style.
                    """)
                )
                .frame(width: geometry.size.width,
                       height: geometry.size.height)
            }
        }
        .clipShape(.rect(cornerRadius: 20))
    }
}

private struct HubLocalArtworkImage: View {
    let url: URL
    let contentMode: ContentMode
    @Binding var isImageEmpty: Bool
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().foregroundStyle(.quinary)
            }
        }
        .task(id: url) {
            image = await ROMArtworkImageLoader.shared.image(at: url)
            isImageEmpty = image == nil
        }
    }
}

extension GameImageCard {
    // TODO: implement for windows .exes by implementing PEFile
    struct FallbackGameImageCard: View {
        @Binding var game: Game
        @AppStorage("gameImageCardBlur") private var imageCardBlur: Double = 0.0
        var withBlur: Bool = true
        
        var body: some View {
            if case .installed(let location, _) = game.installationState {
                
                let image = Image(nsImage: NSWorkspace.shared.icon(forFile: location.path))
                
                ZStack {
                    // blurred image as background
                    // save resources by only create this image if it'll be used for blur
                    if withBlur && (imageCardBlur > 0) {
                        // save resources by decreasing resolution scale of blurred image
                        let renderer: ImageRenderer = {
                            let renderer = ImageRenderer(content: image)
                            renderer.scale = 0.2
                            return renderer
                        }()
                        
                        if let image = renderer.cgImage {
                            Image(image, scale: 1, label: .init(""))
                                .resizable()
                                .clipShape(.rect(cornerRadius: 20))
                                .blur(radius: imageCardBlur)
                        }
                    }
                    
                    image
                        .resizable()
                        .scaledToFit()
                        .modifier(FadeInModifier())
                }
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.windowBackground)
            }
        }
    }
}

#Preview {
    HStack {
        GameImageCard(game: placeholderGame(type: LocalGame.self) as Game,
                      url: placeholderGame(type: LocalGame.self).horizontalImageURL,
                      isImageEmpty: .constant(false),
                      withBlur: true)
        .aspectRatio(16/9, contentMode: .fill)
        
        GameImageCard(game: placeholderGame(type: Game.self),
                      url: placeholderGame(type: Game.self).verticalImageURL,
                      isImageEmpty: .constant(false),
                      withBlur: true)
        .aspectRatio(3/4, contentMode: .fill)
    }
    .aspectRatio(contentMode: .fit)
    .padding()
}

// Shared presentation tokens. Game Boy casing-inspired grey surfaces retain LCARS accents and generous type.
enum HubTheme {
    // VS Code-inspired neutral surfaces keep artwork dominant while the LCARS colors carry navigation and actions.
    static let canvas = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let panel = Color(red: 0.15, green: 0.15, blue: 0.16)
    static let ink = Color(red: 0.91, green: 0.92, blue: 0.94)
    static let blue = Color(red: 0.16, green: 0.31, blue: 0.48)
    static let yellow = Color(red: 0.92, green: 0.77, blue: 0.34)
    static let green = Color(red: 0.43, green: 0.64, blue: 0.51)
    static let purple = Color(red: 0.57, green: 0.49, blue: 0.70)
    static let red = Color(red: 0.79, green: 0.32, blue: 0.30)
    static let displayFontName: String = {
        guard let url = Bundle.main.url(forResource: "Finalnew", withExtension: "ttf", subdirectory: "Fonts") else { return "AvenirNextCondensed-DemiBold" }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return "AvenirNextCondensed-DemiBold" }
        return CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String ?? "AvenirNextCondensed-DemiBold"
    }()
    static func heading(_ size: CGFloat) -> Font { .custom(displayFontName, size: size, relativeTo: .title) }
}
struct HubThemeModifier: ViewModifier {
    @AppStorage("hubTheme") private var theme = "lcars"
    func body(content: Content) -> some View {
        content
            .font(theme == "lcars" ? .system(size: 17) : .body)
            .tint(theme == "lcars" ? HubTheme.blue : .accentColor)
            .preferredColorScheme(theme == "lcars" ? .dark : nil)
    }
}
struct HubSectionBanner: View {
    var title: String
    @AppStorage("hubTheme") private var theme = "lcars"
    var body: some View {
        HStack(spacing: 18) {
            if theme == "lcars" {
                UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 8)
                    .fill(HubTheme.blue).frame(width: 72)
                    .overlay(alignment: .bottom) { Capsule().fill(HubTheme.yellow).frame(height: 12).padding(8) }
                    .accessibilityHidden(true)
            }
            Text(title.uppercased()).font(HubTheme.heading(28)).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            if theme == "lcars" {
                HStack(spacing: 6) {
                    Capsule().fill(HubTheme.green).frame(width: 44)
                    Capsule().fill(HubTheme.red).frame(width: 32)
                    Capsule().fill(HubTheme.purple).frame(width: 44)
                }.frame(height: 12).accessibilityHidden(true)
            }
        }.frame(height: 64).foregroundStyle(theme == "lcars" ? HubTheme.ink : Color.primary)
    }
}
struct HubPlaceholderArtwork: View {
    var title: String
    var system: String
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                HubTheme.canvas
                RoundedRectangle(cornerRadius: 65)
                    .stroke(HubTheme.blue.opacity(0.16), lineWidth: 30)
                    .frame(width: proxy.size.width * 0.85, height: proxy.size.height * 0.9)
                    .offset(x: proxy.size.width * 0.42, y: proxy.size.height * 0.24)
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 6) {
                        Capsule().fill(HubTheme.blue).frame(width: 48, height: 10)
                        Capsule().fill(HubTheme.yellow).frame(width: 28, height: 10)
                        Capsule().fill(HubTheme.green).frame(width: 20, height: 10)
                    }
                    Text(HubSystemMark.shortName(for: system).uppercased()).font(HubTheme.heading(18)).tracking(2)
                    Spacer(minLength: 0)
                    HubSystemMark(system: system, size: 42)
                    Text("GAME LIBRARY").font(.system(size: 13, weight: .semibold)).tracking(2)
                    Spacer(minLength: 0)
                }.padding(24)
            }.foregroundStyle(HubTheme.ink).clipped()
        }
    }
}

struct HubLaunchButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.white : HubTheme.ink.opacity(0.6))
            .padding(.horizontal, 18).frame(minHeight: 36)
            .background(isEnabled ? HubTheme.blue.opacity(configuration.isPressed ? 0.75 : 1) : HubTheme.canvas, in: .capsule)
    }
}

struct HubOptionsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 36)
            .background(HubTheme.purple.opacity(configuration.isPressed ? 0.72 : 1), in: .capsule)
    }
}

enum ROMArtworkKind: String, Hashable {
    case boxart
    case scene

    var directories: [String] {
        switch self {
        case .boxart: ["Named_Boxarts"]
        case .scene: ["Named_Snaps", "Named_Titles"]
        }
    }
}

private struct ROMArtwork: View {
    let title: String
    let system: String
    let kind: ROMArtworkKind
    let contentMode: ContentMode
    @State private var artworkURL: URL?
    @State private var localImage: NSImage?
    @State private var resolvedKind: ROMArtworkKind?

    var body: some View {
        Group {
            if let artworkURL {
                if artworkURL.isFileURL, let image = localImage {
                    let ratio = image.size.height > 0 ? image.size.width / image.size.height : 2
                    resolvedImage(Image(nsImage: image), preserveWholeImage: kind == .scene && ratio < 1.25)
                } else {
                    AsyncImage(url: artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            resolvedImage(image)
                        default:
                            HubPlaceholderArtwork(title: title, system: system)
                        }
                    }
                }
            } else {
                HubPlaceholderArtwork(title: title, system: system)
            }
        }
        .task(id: "\(system)|\(title)|\(kind.rawValue)") {
            artworkURL = nil
            localImage = nil
            resolvedKind = nil
            if let primary = await ROMArtworkResolver.shared.artworkURL(system: system, title: title, kind: kind) {
                artworkURL = primary
                resolvedKind = kind
            } else {
                let fallback: ROMArtworkKind = kind == .boxart ? .scene : .boxart
                artworkURL = await ROMArtworkResolver.shared.artworkURL(system: system, title: title, kind: fallback)
                resolvedKind = artworkURL == nil ? nil : fallback
            }
            if let artworkURL, artworkURL.isFileURL {
                localImage = await ROMArtworkImageLoader.shared.image(at: artworkURL)
            }
        }
    }

    @ViewBuilder private func resolvedImage(_ image: Image, preserveWholeImage: Bool = false) -> some View {
        if kind == .scene, resolvedKind == .boxart || preserveWholeImage {
            ZStack {
                image.resizable().scaledToFill().blur(radius: 26).opacity(0.7)
                Color.black.opacity(0.24)
                image.resizable().scaledToFit().padding(.vertical, 18)
                    .shadow(color: .black.opacity(0.55), radius: 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        } else {
            image.resizable()
                .aspectRatio(contentMode: contentMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }
}

private actor ROMArtworkImageLoader {
    static let shared = ROMArtworkImageLoader()
    private let cache = NSCache<NSURL, NSImage>()

    init() {
        cache.countLimit = 160
        cache.totalCostLimit = 192 * 1_000_000
    }

    func image(at url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        let cost = max(1, Int(image.size.width * image.size.height * 4))
        cache.setObject(image, forKey: url as NSURL, cost: cost)
        return image
    }
}

private struct SwitchArtworkRecord: Codable, Sendable {
    let boxart: URL?
    let scene: URL?

    func url(for kind: ROMArtworkKind) -> URL? {
        kind == .boxart ? boxart : scene
    }
}

private actor ROMArtworkResolver {
    static let shared = ROMArtworkResolver()

    private let repositories = [
        "gc": "Nintendo_-_GameCube",
        "n64": "Nintendo_-_Nintendo_64",
        "ps1": "Sony_-_PlayStation",
        "ps2": "Sony_-_PlayStation_2",
        "dreamcast": "Sega_-_Dreamcast",
        "megadrive": "Sega_-_Mega_Drive_-_Genesis",
        "sega32x": "Sega_-_32X"
    ]
    private var indexes: [String: [String: URL]] = [:]
    private var switchIndex: [String: SwitchArtworkRecord]?
    private var switchIndexTask: Task<[String: SwitchArtworkRecord]?, Never>?
    private let curatedSwitchArtwork: [String: SwitchArtworkRecord] = [
        "thelegendofzeldabreathofthewild": .init(
            boxart: URL(string: "https://img-eshop.cdn.nintendo.net/i/d3c210e61e8487200fc4c344987243a60257838187a69a6a81c42d7447d5d192.jpg"),
            scene: URL(string: "https://img-eshop.cdn.nintendo.net/i/37559b8fa80cf0708c8dcef23ef4fea9af26d997a7c6f981565bc50eeaa3cc0f.jpg")),
        "newsupermariobrosudeluxe": .init(
            boxart: URL(string: "https://img-eshop.cdn.nintendo.net/i/658a846bafd5446bbdfc163c46937152887c6c39eb5f1e6b2337ddec3352b524.jpg"),
            scene: URL(string: "https://img-eshop.cdn.nintendo.net/i/5e1ca57f22a388d696dd0883ea3b5453c7c9e59ff0fea05dd912a2fcb88d1985.jpg")),
        "sonicmania": .init(
            boxart: URL(string: "https://img-eshop.cdn.nintendo.net/i/687ff984dcffc714fdef6b8684028c3039a3ea8e1630bb8898aa9583d8161771.jpg"),
            scene: URL(string: "https://img-eshop.cdn.nintendo.net/i/061ad13a1e1d42bec3270dce388bc73ef1d8b3fdf095790cbcdf0a186a945034.jpg")),
        "sonicxshadowgenerations": .init(
            boxart: URL(string: "https://img-eshop.cdn.nintendo.net/i/88d19ed59cac8faa44abcc45d54a5c10fec4fae57a2932aa0a6034d0e4f3a5e5.jpg"),
            scene: URL(string: "https://img-eshop.cdn.nintendo.net/i/a238b93d4e1ec89433dbcff71b9ea3da41ed478eeb96576f752f4ffb0bcbd74a.jpg")),
        "supermariobroswonder": .init(
            boxart: URL(string: "https://img-eshop.cdn.nintendo.net/i/bf2fca7eed5ad7ec96d03025907ea52c3efe168e02c8be96e868d8430a247a57.jpg"),
            scene: URL(string: "https://img-eshop.cdn.nintendo.net/i/e3024df668cdead60e62865924652c811323b0e7c46f51567fe80907f2637cc4.jpg")),
        "supermarioodyssey": .init(
            boxart: URL(string: "https://img-eshop.cdn.nintendo.net/i/ad4d31f664a1ce704f0219da2805f8459595bc3c01c3f04df2e32ba34a05b8c6.jpg"),
            scene: URL(string: "https://img-eshop.cdn.nintendo.net/i/1839d571921e3fb19ef48da64c145cb8ce573b07d7390c6350f15291b3905048.jpg")),
        "supersmashbrosultimate": .init(
            boxart: URL(string: "https://img-eshop.cdn.nintendo.net/i/08af58551a19df2a73ccb36f720388434a1965776b34675c6f69af3f93280330.jpg"),
            scene: URL(string: "https://img-eshop.cdn.nintendo.net/i/245420c78ce40337bdca7ce9c2dd819bd4ae33b022da9b922c0710b8420b59dd.jpg"))
    ]

    func artworkURL(system: String, title: String, kind: ROMArtworkKind) async -> URL? {
        let cacheURL = cachedArtworkURL(system: system, title: title, kind: kind)
        if isValidImage(at: cacheURL) { return cacheURL }
        let remoteURL: URL?
        if system == "switch" {
            remoteURL = await switchArtworkURL(title: title, kind: kind)
        } else {
            remoteURL = await libretroArtworkURL(system: system, title: title, kind: kind)
        }
        guard let remoteURL else { return nil }
        return await download(remoteURL, to: cacheURL)
    }

    private func libretroArtworkURL(system: String, title: String, kind: ROMArtworkKind) async -> URL? {
        guard let repository = repositories[system] else { return nil }
        let normalizedTitles = normalizedKeys(system: system, title: title)
        guard !normalizedTitles.isEmpty else { return nil }
        let cacheKey = repository + "|" + kind.rawValue
        let index: [String: URL]
        if let cached = indexes[cacheKey] {
            index = cached
        } else {
            guard let fetched = await fetchIndex(repository: repository, kind: kind) else {
                return await directArtworkURL(repository: repository, title: title, kind: kind)
            }
            indexes[cacheKey] = fetched
            index = fetched
        }
        for normalizedTitle in normalizedTitles {
            if let exact = index[normalizedTitle] { return exact }
        }
        for normalizedTitle in normalizedTitles {
            if let close = index.first(where: { key, _ in key.hasPrefix(normalizedTitle) || normalizedTitle.hasPrefix(key) })?.value {
                return close
            }
        }
        return await directArtworkURL(repository: repository, title: title, kind: kind)
    }

    private func directArtworkURL(repository: String, title: String, kind: ROMArtworkKind) async -> URL? {
        let cleaned = title
            .replacingOccurrences(of: #"\s*[\[(].*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+v\d+(?:\.\d+)*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for name in ROMTitle.lookupNames(cleaned) {
            for directory in kind.directories {
                for stem in [name + " (USA)", name + " (World)", name, name + " (Europe)"] {
                    guard let url = rawURL(repository: repository, path: "\(directory)/\(stem).png") else { continue }
                    var request = URLRequest(url: url)
                    request.httpMethod = "HEAD"
                    if let (_, response) = try? await URLSession.shared.data(for: request),
                       (response as? HTTPURLResponse)?.statusCode == 200 { return url }
                }
            }
        }
        return nil
    }

    private func switchArtworkURL(title: String, kind: ROMArtworkKind) async -> URL? {
        let normalizedTitle = normalize(title)
        if let exact = curatedSwitchArtwork[normalizedTitle]?.url(for: kind) { return exact }
        if switchIndex == nil { switchIndex = loadSwitchIndex() }
        if switchIndex == nil {
            let task: Task<[String: SwitchArtworkRecord]?, Never>
            if let current = switchIndexTask {
                task = current
            } else {
                let created = Task { await fetchSwitchIndex() }
                switchIndexTask = created
                task = created
            }
            switchIndex = await task.value
            switchIndexTask = nil
            if let switchIndex { persistSwitchIndex(switchIndex) }
        }
        guard let index = switchIndex else { return nil }
        let titleID = title.range(of: #"[0-9A-Fa-f]{16}"#, options: .regularExpression).map {
            String(title[$0]).uppercased()
        }
        if let titleID, let exact = index[titleID]?.url(for: kind) { return exact }
        return index[normalizedTitle]?.url(for: kind)
    }

    private func fetchSwitchIndex() async -> [String: SwitchArtworkRecord]? {
        guard let endpoint = URL(string: "https://raw.githubusercontent.com/blawar/titledb/master/US.en.json") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let records = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return nil }
            var result: [String: SwitchArtworkRecord] = [:]
            for record in records.values {
                let id = record["id"] as? String ?? ""
                let screenshots = record["screenshots"] as? [String] ?? []
                let boxart = (record["frontBoxArt"] as? String ?? record["iconUrl"] as? String).flatMap(URL.init(string:))
                let scene = (screenshots.dropFirst().first ?? screenshots.first ?? record["bannerUrl"] as? String).flatMap(URL.init(string:))
                guard boxart != nil || scene != nil else { continue }
                let artwork = SwitchArtworkRecord(boxart: boxart, scene: scene)
                if !id.isEmpty { result[id.uppercased()] = artwork }
                if let name = record["name"] as? String { result[normalize(name)] = artwork }
            }
            return result
        } catch { return nil }
    }

    private var switchIndexFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GameHub/Artwork/switch-index-v2.json")
    }

    private func loadSwitchIndex() -> [String: SwitchArtworkRecord]? {
        guard let data = try? Data(contentsOf: switchIndexFile) else { return nil }
        return try? JSONDecoder().decode([String: SwitchArtworkRecord].self, from: data)
    }

    private func persistSwitchIndex(_ index: [String: SwitchArtworkRecord]) {
        let file = switchIndexFile
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(index) { try? data.write(to: file, options: .atomic) }
    }

    private func fetchIndex(repository: String, kind: ROMArtworkKind) async -> [String: URL]? {
        var result: [String: URL] = [:]
        var scores: [String: Int] = [:]
        for (directoryRank, directory) in kind.directories.enumerated() {
            guard let directoryURL = rawURL(repository: repository, path: directory + "/") else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: directoryURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let html = String(data: data, encoding: .utf8),
                      let expression = try? NSRegularExpression(pattern: #"href="([^"]+\.(?:png|jpe?g|webp))""#, options: .caseInsensitive) else { continue }
                let range = NSRange(html.startIndex..., in: html)
                for match in expression.matches(in: html, range: range) {
                    guard let linkRange = Range(match.range(at: 1), in: html) else { continue }
                    let link = String(html[linkRange])
                    guard let imageURL = URL(string: link, relativeTo: directoryURL)?.absoluteURL else { continue }
                    let filename = imageURL.lastPathComponent.removingPercentEncoding ?? imageURL.lastPathComponent
                    let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
                    let key = normalize(stem)
                    guard !key.isEmpty else { continue }
                    let score = regionalScore(stem) + (kind.directories.count - directoryRank) * 10
                    if score > scores[key, default: Int.min] {
                        scores[key] = score
                        result[key] = imageURL
                    }
                }
            } catch {
                continue
            }
        }
        return result.isEmpty ? nil : result
    }

    private func normalize(_ value: String) -> String {
        var result = ""
        var depth = 0
        for scalar in ROMTitle.displayName(value).unicodeScalars {
            if scalar == "(" { depth += 1; continue }
            if scalar == ")" { depth = max(0, depth - 1); continue }
            guard depth == 0 else { continue }
            if CharacterSet.alphanumerics.contains(scalar) { result.unicodeScalars.append(scalar) }
        }
        return result.lowercased()
    }

    private func normalizedKeys(system: String, title: String) -> [String] {
        let key = normalize(title)
        let aliases: [String: [String: String]] = [
            "n64": [
                "fifa98roadtoworldcup": "fifaroadtoworldcup98",
                "masters98harukanaruaugust": "harukanaruaugustamasters98",
                "puyopuyo4puyopuyonparty": "puyopuyoonparty",
                "ridgeracer64": "rr64ridgeracer64",
                "wonderprojectj2koruronomorinojosette": "wonderprojectj2koruronomorinojozet"
            ],
            "megadrive": [
                "bonanzabrothers": "bonanzabros",
                "galahad": "thelegendofgalahad",
                "magicalhatnobuttobitabodaibouken": "magicalhatnobuttobiturbodaibouken",
                "mightandmagiciigatestoanotherworld": "mightandmagicgatestoanotherworld",
                "puzzleactionichidantr": "puzzleactionichidantor",
                "puzzleactiontantr": "puzzleactiontantor",
                "sslucifermanoverboard": "manoverboard",
                "superbattletankwarinthegulf": "garrykitchenssuperbattletankwarinthegulf",
                "terminator2judgmentday": "t2terminator2judgmentday",
                "watermarginataleofcloudsandwind": "watermarginthetalesofcloudsandwinds"
            ]
        ]
        if let alias = aliases[system]?[key] { return [key, alias] }
        return key.isEmpty ? [] : [key]
    }

    private func rawURL(repository: String, path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "thumbnails.libretro.com"
        let system = repository.replacingOccurrences(of: "_-_", with: " - ")
            .replacingOccurrences(of: "_", with: " ")
        components.path = "/\(system)/\(path)"
        return components.url
    }

    private func regionalScore(_ path: String) -> Int {
        if path.localizedCaseInsensitiveContains("(USA)") { return 4 }
        if path.localizedCaseInsensitiveContains("(World)") { return 3 }
        if path.localizedCaseInsensitiveContains("(Europe)") { return 2 }
        return 1
    }

    private func cachedArtworkURL(system: String, title: String, kind: ROMArtworkKind) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // The original Switch cache may contain art from an early fuzzy matcher.
        // Keep it untouched and use a clean, exact-title cache namespace.
        let cacheSystem: String
        if system == "switch" {
            cacheSystem = kind == .scene ? "switch-scene-v2" : "switch-v2"
        } else {
            cacheSystem = system
        }
        let directory = base.appendingPathComponent("GameHub/Artwork/\(kind.rawValue)/\(cacheSystem)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = normalize(title).prefix(180)
        return directory.appendingPathComponent(String(key) + ".image")
    }

    private func isValidImage(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) && NSImage(contentsOf: url) != nil
    }

    private func download(_ remoteURL: URL, to cacheURL: URL) async -> URL? {
        do {
            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  NSImage(data: data) != nil else { return nil }
            try data.write(to: cacheURL, options: .atomic)
            return cacheURL
        } catch {
            return nil
        }
    }
}
