import SwiftUI

struct ListGameCard: View {
    @Binding var game: Game
    static let defaultHeight: CGFloat = 120
    var body: some View { GameCard(game: $game) }
}
