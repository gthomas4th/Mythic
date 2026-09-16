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
    @AppStorage("gameImageCardBlur") private var imageCardBlur: Double = 0.0
    
    /// - Note: `game` must be passed as a parameter in order to include fallback image URLs.
    init(game: Game? = nil, url: URL?, isImageEmpty: Binding<Bool>, withBlur: Bool = true, contentMode: ContentMode = .fill) {
        self.game = game
        self.url = url
        self._isImageEmpty = isImageEmpty
        self.withBlur = withBlur
        self.contentMode = contentMode
    }
    
    var body: some View {
        GeometryReader { geometry in
            if url == nil, let game = game as? ROMGame {
                ROMCoverArtwork(title: game.title, system: game.source?.system ?? "Games", contentMode: contentMode)
            } else if let url, url.isFileURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .onAppear { isImageEmpty = false }
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
    static let canvas = Color(red: 0.62, green: 0.62, blue: 0.60)
    static let panel = Color(red: 0.73, green: 0.73, blue: 0.71)
    static let ink = Color(red: 0.12, green: 0.17, blue: 0.24)
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
            .preferredColorScheme(theme == "lcars" ? .light : nil)
    }
}
struct HubSectionBanner: View {
    var title: String
    var subtitle: String
    @AppStorage("hubTheme") private var theme = "lcars"
    var body: some View {
        HStack(spacing: 18) {
            if theme == "lcars" {
                UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 8)
                    .fill(HubTheme.blue).frame(width: 72)
                    .overlay(alignment: .bottom) { Capsule().fill(HubTheme.yellow).frame(height: 12).padding(8) }
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased()).font(HubTheme.heading(28)).lineLimit(1).minimumScaleFactor(0.7)
                Text(subtitle).font(.system(size: 16)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if theme == "lcars" {
                HStack(spacing: 6) {
                    Capsule().fill(HubTheme.green).frame(width: 44)
                    Capsule().fill(HubTheme.red).frame(width: 32)
                    Capsule().fill(HubTheme.purple).frame(width: 44)
                }.frame(height: 12).accessibilityHidden(true)
            }
        }.frame(height: 80).foregroundStyle(theme == "lcars" ? HubTheme.ink : Color.primary)
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
                    Text(system.uppercased()).font(HubTheme.heading(18)).tracking(2)
                    Spacer(minLength: 0)
                    Image(systemName: "gamecontroller.fill").font(.system(size: 38, weight: .light)).foregroundStyle(HubTheme.blue)
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

private struct ROMCoverArtwork: View {
    let title: String
    let system: String
    let contentMode: ContentMode
    @State private var artworkURL: URL?

    var body: some View {
        Group {
            if let artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: contentMode)
                    default:
                        HubPlaceholderArtwork(title: title, system: system)
                    }
                }
            } else {
                HubPlaceholderArtwork(title: title, system: system)
            }
        }
        .task(id: "\\(system)|\\(title)") {
            artworkURL = await ROMArtworkResolver.shared.artworkURL(system: system, title: title)
        }
    }
}

private actor ROMArtworkResolver {
    static let shared = ROMArtworkResolver()

    private let repositories = [
        "gc": "Nintendo_-_GameCube",
        "n64": "Nintendo_-_Nintendo_64",
        "ps1": "Sony_-_PlayStation",
        "ps2": "Sony_-_PlayStation_2"
    ]
    private var indexes: [String: [String: URL]] = [:]

    func artworkURL(system: String, title: String) async -> URL? {
        guard let repository = repositories[system] else { return nil }
        let normalizedTitle = normalize(title)
        guard !normalizedTitle.isEmpty else { return nil }
        let index: [String: URL]
        if let cached = indexes[repository] {
            index = cached
        } else {
            guard let fetched = await fetchIndex(repository: repository) else { return nil }
            indexes[repository] = fetched
            index = fetched
        }
        if let exact = index[normalizedTitle] { return exact }
        return index.first(where: { key, _ in key.hasPrefix(normalizedTitle) || normalizedTitle.hasPrefix(key) })?.value
    }

    private func fetchIndex(repository: String) async -> [String: URL]? {
        guard let endpoint = URL(string: "https://api.github.com/repos/libretro-thumbnails/\\(repository)/git/trees/master?recursive=1") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let tree = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = tree["tree"] as? [[String: Any]] else { return nil }
            var result: [String: URL] = [:]
            for entry in entries {
                guard let path = entry["path"] as? String,
                      path.hasPrefix("Named_Boxarts/"),
                      ["png", "jpg", "jpeg", "webp"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) else { continue }
                let filename = URL(fileURLWithPath: path).lastPathComponent
                let key = normalize(URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent)
                guard !key.isEmpty,
                      let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let imageURL = URL(string: "https://thumbnails.libretro.com/\\(repository)/\\(encoded)") else { continue }
                // Prefer the first repository match; the index order favors the canonical regional art.
                if result[key] == nil { result[key] = imageURL }
            }
            return result
        } catch {
            return nil
        }
    }

    private func normalize(_ value: String) -> String {
        var result = ""
        var depth = 0
        for scalar in value.unicodeScalars {
            if scalar == "(" { depth += 1; continue }
            if scalar == ")" { depth = max(0, depth - 1); continue }
            guard depth == 0 else { continue }
            if CharacterSet.alphanumerics.contains(scalar) { result.unicodeScalars.append(scalar) }
        }
        return result.lowercased()
    }
}
