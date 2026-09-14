import SwiftUI

struct ListGameCard: View {
    @Binding var game: Game
    @State private var isImageEmpty = true
    static let defaultHeight: CGFloat = 120
    var body: some View {
        HStack(spacing: 20) {
            GameImageCard(game: game, url: game.verticalImageURL, isImageEmpty: $isImageEmpty, withBlur: false, contentMode: .fit)
                .frame(width: 90, height: 120)
            VStack(alignment: .leading, spacing: 12) {
                Text(game.title).font(.system(size: 20, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                HubGameBadges(game: game)
                HStack(spacing: 14) {
                    GameCard.ButtonsView(game: $game, withLabel: true)
                }.controlSize(.large)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 12)
    }
}
