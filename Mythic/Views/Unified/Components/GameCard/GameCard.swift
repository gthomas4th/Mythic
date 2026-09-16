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

    private var icon: String {
        switch system.lowercased() {
        case "gc", "wii": return "gamecontroller.fill"
        case "ps1", "ps2", "ps3": return "circle.grid.3x3.fill"
        case "n64": return "rectangle.3.group.fill"
        case "switch": return "rectangle.split.2x1.fill"
        default: return "gamecontroller.fill"
        }
    }

    var body: some View {
        Label(system.uppercased(), systemImage: icon)
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(HubTheme.ink)
            .background(HubTheme.blue.opacity(0.20), in: .capsule)
            .help("System: \(system.uppercased())")
            .accessibilityLabel("System: \(system.uppercased())")
    }
}
