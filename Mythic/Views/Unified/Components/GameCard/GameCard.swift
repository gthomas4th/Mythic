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
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hubTheme") private var theme = "lcars"
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
                Text(game.sourceLabel).font(.system(size: 14, weight: .semibold))
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(theme == "lcars" ? HubTheme.canvas : Color.secondary.opacity(0.12), in: .capsule)
                Divider()
                GameCard.ButtonsView(game: $game, withLabel: true, cardLayout: true)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, alignment: .leading)

            }.padding(18)
        }
        .background(theme == "lcars" ? HubTheme.panel : Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(hovered ? HubTheme.blue : Color.primary.opacity(0.08), lineWidth: hovered ? 2 : 1))
        .shadow(color: .black.opacity(hovered ? 0.12 : 0.05), radius: hovered ? 14 : 6, y: 4)
        .offset(y: hovered && !reduceMotion ? -3 : 0)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
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
