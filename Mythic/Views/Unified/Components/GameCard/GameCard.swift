//
//  GameCard.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 5/3/2024.
//

// Copyright © 2023-2025 vapidinfinity

import SwiftUI
import SwiftyJSON
import Glur
import OSLog

struct GameCard: View {
    @Binding var game: Game
    var artworkURL: URL? = nil
    @State private var isImageEmpty = true
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GameImageCard(game: game, url: artworkURL ?? game.verticalImageURL, isImageEmpty: $isImageEmpty, withBlur: false, contentMode: .fit)
                .frame(height: 210)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    if game.isFavourited {
                        Image(systemName: "star.fill").foregroundStyle(HubTheme.ink)
                            .padding(10).background(HubTheme.yellow, in: .circle).padding(12)
                            .accessibilityLabel("Favorite")
                    }
                }
            VStack(alignment: .leading, spacing: 12) {
                Text(game.title).font(.system(size: 20, weight: .semibold))
                    .lineLimit(2).frame(height: 50, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HubGameBadges(game: game)
                GameCard.ButtonsView(game: $game, withLabel: true, cardLayout: true)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, alignment: .leading)

            }.padding(.top, 16)
        }

    }
}

/// ViewModifier that enables views to have a fade in effect.
struct FadeInModifier: ViewModifier {
    @State private var opacity: Double = 0

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5)) {
                    opacity = 1
                }
            }
    }
}

#Preview {
    GameCard(game: .constant(placeholderGame(type: Game.self)))
        .environmentObject(NetworkMonitor.shared)
}


struct HubTagBadge: View {
    var title: String
    var category: String
    @AppStorage("hubTheme") private var theme = "lcars"
    var body: some View {
        Text(title).font(.system(size: 14, weight: .semibold))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(theme == "lcars" ? HubTheme.ink : Color.primary)
            .background(theme == "lcars" ? (category == "Type" ? HubTheme.purple.opacity(0.22) : HubTheme.canvas) : Color.secondary.opacity(0.12), in: .capsule)
            .help("\(category): \(title)")
            .accessibilityLabel("\(category): \(title)")
    }
}
struct HubGameBadges: View {
    var game: Game
    var body: some View {
        HStack(spacing: 8) {
            if let location = game.locationLabel { HubTagBadge(title: location, category: "Location") }
            if let type = game.typeLabel { HubTagBadge(title: type, category: "Type") }
            if let rom = game as? ROMGame, let system = rom.source?.system {
                HubSystemBadge(system: system)
            }
        }.fixedSize(horizontal: true, vertical: false)
    }
}

struct HubSystemBadge: View {
    let system: String

    var body: some View {
        HubSystemMark(system: system, size: 18)
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .foregroundStyle(HubTheme.ink)
            .background(HubTheme.blue.opacity(0.20), in: .capsule)
            .help("System: \(HubSystemMark.shortName(for: system))")
            .accessibilityLabel("System: \(HubSystemMark.shortName(for: system))")
    }
}

/// Official platform marks used wherever a ROM system is shown. The logos are
/// bundled in the app so they remain visible without a network connection.
struct HubSystemMark: View {
    let system: String
    var size: CGFloat = 20

    static func shortName(for system: String) -> String {
        switch system.lowercased() {
        case "gc", "gamecube": return "GC"
        case "n64", "nintendo 64": return "N64"
        case "ps1", "playstation": return "PS"
        case "ps2", "playstation 2": return "PS2"
        case "ps3", "playstation 3": return "PS3"
        case "switch", "nintendo switch": return "SWITCH"
        case "dreamcast": return "DC"
        case "megadrive", "mega drive", "mega drive / genesis", "genesis", "sega": return "Sega"
        case "wii": return "Wii"
        case "pc & mac", "pc", "mac": return "PC"
        case "connections": return "LINK"
        default: return system.uppercased()
        }
    }

    private var assetName: String? {
        switch system.lowercased() {
        case "gc", "gamecube": return "SystemGameCube"
        case "n64", "nintendo 64": return "SystemNintendo64"
        case "ps1", "playstation", "ps3", "playstation 3": return "SystemPlayStation"
        case "ps2", "playstation 2": return "SystemPS2"
        case "switch", "nintendo switch": return "SystemSwitch"
        case "dreamcast": return "SystemDreamcast"
        case "megadrive", "mega drive", "mega drive / genesis", "genesis", "sega": return "SystemSega"
        default: return nil
        }
    }

    var body: some View {
        Group {
            if let assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            } else if system.lowercased() == "connections" {
                Image(systemName: "network")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(HubTheme.ink)
            } else if ["pc & mac", "pc", "mac"].contains(system.lowercased()) {
                Image(systemName: "desktopcomputer")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(HubTheme.ink)
            }
        }
        .frame(width: size * 1.6, height: size)
        .accessibilityHidden(true)
    }
}
