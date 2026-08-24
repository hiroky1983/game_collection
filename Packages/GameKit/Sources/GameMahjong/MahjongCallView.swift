import SwiftUI
import Core
import MahjongTiles

/// 副露（鳴いた面子）の並び。手牌の外に晒すものなので、手牌とは別の行に置く。
///
/// 実物の麻雀は「鳴いた相手の方向へ牌を横向きにする」が、画面上の 13〜24pt の牌では
/// 向きの違いが読み取れないため、代わりに種類（ポン / チー / カン）を小さく添える。
struct MahjongMeldRow: View {
    let melds: [MahjongCall]
    let tileWidth: CGFloat
    /// 種類の見出しを出すか（他家の小さい表示では省く）。
    var showsBadge: Bool = true

    var body: some View {
        if !melds.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(melds.enumerated()), id: \.offset) { _, meld in
                    VStack(spacing: 1) {
                        HStack(spacing: 1) {
                            ForEach(Array(meld.tiles.enumerated()), id: \.offset) { _, tile in
                                MahjongTileView(
                                    tile: tile, width: tileWidth, height: tileWidth * 1.34
                                )
                            }
                        }
                        if showsBadge {
                            Text(Self.badge(meld))
                                .font(.system(size: 8, weight: .black, design: .rounded))
                                .foregroundStyle(Theme.inkSub)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(MahjongAccessibility.meldLabel(meld))
                }
                Spacer(minLength: 0)
            }
        }
    }

    static func badge(_ meld: MahjongCall) -> String {
        switch meld.kind {
        case .pon:       return "ポン"
        case .chi:       return "チー"
        case .openKan:   return "カン"
        case .addedKan:  return "加槓"
        case .closedKan: return "暗槓"
        }
    }
}

/// 鳴くかスルーかを選ぶ操作列。
struct MahjongCallBar: View {
    let offer: MahjongModel.CallOffer
    let onAccept: (MahjongCall) -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text("\(offer.tile.displayName) を")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                MahjongTileView(tile: offer.tile, width: 20, height: 27)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(offer.tile.displayName)が出ました。鳴きますか")
            // 選択肢はチーの取り方違いで 3 つまで増えるので、折り返せる並びにする。
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons }
                VStack(spacing: 6) { buttons }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    @ViewBuilder
    private var buttons: some View {
        ForEach(Array(offer.options.enumerated()), id: \.offset) { _, option in
            callButton(option)
        }
        Button(action: onDecline) {
            Text("スルー")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.fillMuted)
        .accessibilityLabel("鳴かずに進める")
    }

    private func callButton(_ option: MahjongCall) -> some View {
        Button { onAccept(option) } label: {
            VStack(spacing: 0) {
                Text(option.actionName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                // 同じチーでも取り方が複数あるので、手牌から使う牌を添えて選び分けられるようにする。
                if offer.options.filter({ $0.kind == option.kind }).count > 1 {
                    Text(option.optionDetail)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.borderedProminent)
        .tint(option.isKan ? Theme.purple : Theme.coral)
        .accessibilityLabel(MahjongAccessibility.callOptionLabel(option))
    }
}

/// 自分の手番でのカン（暗槓・加槓）ボタン。候補が複数あるときはメニューで選ばせる。
struct MahjongKanButton: View {
    let options: [MahjongCall]
    let onSelect: (MahjongCall) -> Void

    var body: some View {
        if options.count > 1 {
            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button("\(MahjongMeldRow.badge(option)) \(option.tile.displayName)") {
                        onSelect(option)
                    }
                }
            } label: {
                label
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.purple)
            .accessibilityLabel("カンする牌を選ぶ")
        } else {
            Button {
                if let option = options.first { onSelect(option) }
            } label: {
                label
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.purple)
            .disabled(options.isEmpty)
            .accessibilityLabel(options.first.map(MahjongAccessibility.callOptionLabel) ?? "カン")
        }
    }

    private var label: some View {
        Text("カン")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 40)
    }
}
