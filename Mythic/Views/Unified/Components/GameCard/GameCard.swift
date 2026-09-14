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
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                titleAndBadges.frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
                controls
            }
            VStack(alignment: .leading, spacing: 14) {
                titleAndBadges
                controls
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Divider() }
    }
    private var titleAndBadges: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(game.title).font(.system(size: 20, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if game.isFavourited {
                    Image(systemName: "star.fill").foregroundStyle(HubTheme.yellow)
                        .accessibilityLabel("Favourite")
                }
            }
            HubGameBadges(game: game)
        }
    }
    private var controls: some View {
        HStack(spacing: 14) {
            GameCard.ButtonsView(game: $game, withLabel: true)
        }.controlSize(.large).fixedSize(horizontal: true, vertical: false)
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
        }.fixedSize(horizontal: true, vertical: false)
    }
}
