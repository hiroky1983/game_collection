// #2432 のレイアウト検討モック（いろリレー・今 vs A）の生成器。**アプリのコードではない**（docs に置くだけ）。
// 使い方: このファイルを `Packages/GameKit/Tests/GameColorRelayTests/` にコピーし（release/v1.1.13 以降・#2369 案 B 反映後の
//   コードで）、
//   DUTY_SCRATCH_DIR=<出力先> swift test --package-path Packages/GameKit --filter LayoutMock2432
// で `<出力先>/mock2432/` に PNG 4 枚と寸法の JSON が出る（シミュレータ不要。macOS の ImageRenderer で描く）。
// 実物の部品（ColorRelayCardView・ColorRelayCardBack・ColorRelayBackFan・ColorRelayOpponentIcon・ColorRelayHandLayout・
// cardTable・GameButtonStyle・popCard）をそのまま使い、ナビバー・ステータスバー・バナーだけ見た目を写して描いている。
// 画面は `ColorRelayView.body` の写し（手札が少ない局面と多い局面の 2 局面）。#2428（フリーセル）・#2430（花札）の生成器と同じ型。
// 終わったらコピーは消す（コミットしない）。
import Foundation
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
import Core
import CoreTestSupport
@testable import GameColorRelay

private struct Phone {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let safeTop: CGFloat
    let safeBottom: CGFloat
    let scale: CGFloat
    /// iOS 26 のナビバーの高さ（実スクショ ip17_spiderzoom_v2cur.png の実測: コンテンツ開始 = 62 + 54 = 116pt）。
    static let navBarHeight: CGFloat = 54
}

private let phones = [
    Phone(name: "ip17", width: 402, height: 874, safeTop: 62, safeBottom: 34, scale: 3),
    Phone(name: "se3", width: 375, height: 667, safeTop: 20, safeBottom: 0, scale: 2),
]

/// 描画中に GeometryReader から寸法を書き留める器。
private final class Measure: @unchecked Sendable {
    var values: [String: Double] = [:]
    func set(_ key: String, _ value: CGFloat) { values[key] = (Double(value) * 100).rounded() / 100 }
}

// MARK: - 卓の中身（ColorRelayView.tableArea の写し）

@MainActor
private func turnLabel(_ model: ColorRelayModel) -> String {
    switch model.phase {
    case .idle:    return "開始待ち"
    case .result:  return "決着"
    case .playing: return model.isPlayerTurn ? "あなたの番" : "\(model.playerName(model.currentPlayer))の番"
    }
}

/// 卓の見出し（何ゲーム目・回る向き）。`tableHeader` の写し。
private struct TableHeader: View {
    let model: ColorRelayModel
    let measure: Measure
    let prefix: String
    var body: some View {
        CardTableInkReader { ink in
            HStack(spacing: 4) {
                Text(verbatim: "\(max(model.gameNumber, 1))ゲーム目")
                Spacer()
                Image(systemName: model.isClockwise ? "arrow.clockwise" : "arrow.counterclockwise")
                Text(model.isClockwise ? "順回り" : "逆回り")
            }
            .scaledFont(11, weight: .bold, design: .rounded)
            .foregroundStyle(ink.labelSub)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
        }
        .background(GeometryReader { geo in
            let _ = measure.set("\(prefix).header_h_pt", geo.size.height)
            Color.clear
        })
    }
}

/// 相手 3 人を横並び。`seatsRow` / `seat` / `seatCount` の写し。
private struct SeatsRow: View {
    let model: ColorRelayModel
    let metrics: ColorRelayHandLayout.Metrics
    let measure: Measure
    let prefix: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(1..<ColorRelayModel.playerCount, id: \.self) { index in
                seat(index)
                if index < ColorRelayModel.playerCount - 1 {
                    CardTableInkReader { ink in
                        Image(systemName: model.isClockwise ? "chevron.right.2" : "chevron.left.2")
                            .scaledFont(15, weight: .black)
                            .foregroundStyle(ink.labelSub)
                    }
                    .frame(height: metrics.seatDiameter)
                }
            }
        }
        .background(GeometryReader { geo in
            let _ = measure.set("\(prefix).seats_h_pt", geo.size.height)
            Color.clear
        })
    }

    private func seat(_ index: Int) -> some View {
        let isCurrent = model.currentPlayer == index && model.phase == .playing
        let count = model.hands[index].count
        let action = model.lastActions[index]
        return VStack(spacing: 4) {
            ColorRelayOpponentIcon(index: index, diameter: metrics.seatDiameter, isCurrent: isCurrent)
            ColorRelayBackFan(count: count, cardWidth: metrics.opponentCardWidth)
            seatCount(count)
            Text(verbatim: action.isEmpty ? " " : action)
                .scaledFont(10, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.Fixed.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(Color.white))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .opacity(action.isEmpty ? 0 : 1)
        }
        .frame(maxWidth: .infinity)
    }

    private func seatCount(_ count: Int) -> some View {
        CardTableInkReader { ink in
            Text(verbatim: "残り\(count)枚")
                .scaledFont(11, weight: .black, design: .rounded)
                .foregroundStyle(count == 1 ? Theme.onAccent : ink.labelSub)
                .padding(.horizontal, count == 1 ? 8 : 0)
                .padding(.vertical, count == 1 ? 2 : 0)
                .background(Capsule().fill(count == 1 ? Theme.Fill.yellow : Color.clear))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// 山札と場札。`fieldArea` / `drawPileView` / `discardView` の写し。大きさは卓の残りの高さから決まる。
private struct FieldArea: View {
    let model: ColorRelayModel
    let metrics: ColorRelayHandLayout.Metrics
    let measure: Measure
    let prefix: String

    var body: some View {
        GeometryReader { proxy in
            let field = ColorRelayHandLayout.field(size: proxy.size, maxTopWidth: metrics.maxTopCardWidth)
            // 上限（iPhone 17 幅 96pt・SE 幅 76pt）を外したら場札がどこまで大きくなれるか（寸法の比較用）。
            let uncapped = ColorRelayHandLayout.field(size: proxy.size, maxTopWidth: .greatestFiniteMagnitude)
            let frame = proxy.frame(in: .named("phone"))
            let _ = {
                measure.set("\(prefix).field_w_pt", proxy.size.width)
                measure.set("\(prefix).field_h_pt", proxy.size.height)
                measure.set("\(prefix).field_top_pt", frame.minY)
                measure.set("\(prefix).top_w_pt", field.topWidth)
                measure.set("\(prefix).top_h_pt", ColorRelayCardSize(width: field.topWidth).height)
                measure.set("\(prefix).pile_w_pt", field.pileWidth)
                measure.set("\(prefix).plate_pt", field.topWidth * ColorRelayHandLayout.plateRatio)
                measure.set("\(prefix).top_w_cap_pt", metrics.maxTopCardWidth)
                measure.set("\(prefix).top_w_uncapped_pt", uncapped.topWidth)
            }()
            HStack(alignment: .center, spacing: field.spacing) {
                drawPile(width: field.pileWidth)
                discard(width: field.topWidth)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func drawPile(width: CGFloat) -> some View {
        VStack(spacing: 4) {
            ZStack {
                ColorRelayCardBack(width: width).offset(x: 4, y: 4).opacity(0.7)
                ColorRelayCardBack(width: width).offset(x: 2, y: 2).opacity(0.85)
                ColorRelayCardBack(width: width)
            }
            .padding(.trailing, 4).padding(.bottom, 4)
            CardTableInkReader { ink in
                Text(verbatim: "山 \(model.drawPile.count)枚")
                    .scaledFont(11, weight: .bold, design: .rounded)
                    .foregroundStyle(ink.labelSub)
                    .lineLimit(1)
            }
        }
    }

    private func discard(width: CGFloat) -> some View {
        let plate = width * ColorRelayHandLayout.plateRatio
        let under = model.discardPile.count >= 2 ? model.discardPile[model.discardPile.count - 2] : nil
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(model.activeColor.color.opacity(0.35))
                    .overlay(Circle().strokeBorder(model.activeColor.color, lineWidth: max(3, width * 0.05)))
                    .frame(width: plate, height: plate)
                if let under {
                    ColorRelayCardView(card: under, width: width)
                        .rotationEffect(.degrees(8))
                        .opacity(0.85)
                }
                if let top = model.topCard {
                    ColorRelayCardView(card: top, width: width)
                        .rotationEffect(.degrees(-5))
                }
            }
            .frame(width: plate, height: plate)
            CardTableInkReader { ink in
                HStack(spacing: 4) {
                    Text(verbatim: "いまの色")
                    Text(verbatim: model.activeColor.name)
                }
                .scaledFont(11, weight: .bold, design: .rounded)
                .foregroundStyle(ink.labelSub)
                .lineLimit(1)
            }
        }
    }
}

/// 卓の中身（見出し・相手の段・山札と場札）。`tableArea` から `.cardTable()` を外したもの。
private struct TableContent: View {
    let model: ColorRelayModel
    let metrics: ColorRelayHandLayout.Metrics
    let measure: Measure
    let prefix: String
    var body: some View {
        VStack(spacing: 0) {
            TableHeader(model: model, measure: measure, prefix: prefix)
                .fixedSize(horizontal: false, vertical: true)
            SeatsRow(model: model, metrics: metrics, measure: measure, prefix: prefix)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            FieldArea(model: model, metrics: metrics, measure: measure, prefix: prefix)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 手札（ColorRelayView.handArea の写し）

private struct YouPill: View {
    let model: ColorRelayModel
    var body: some View {
        let isTurn = model.isPlayerTurn
        let action = model.lastActions[ColorRelayModel.humanIndex]
        HStack(spacing: 6) {
            Text(verbatim: isTurn ? "あなたの番" : "あなた")
                .scaledFont(12, weight: .black, design: .rounded)
            Text(verbatim: "残り\(model.playerHand.count)枚")
                .scaledFont(11, weight: .bold, design: .rounded)
            if !action.isEmpty {
                Text(verbatim: action)
                    .scaledFont(11, weight: .bold, design: .rounded)
            }
        }
        .foregroundStyle(isTurn ? Theme.onAccent : Theme.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Capsule().fill(isTurn ? Theme.Fill.yellow : Theme.surface))
        .shadow(color: Theme.cardShadow, radius: 3, y: 1)
    }
}

/// 手札の帯。実物は横の `ScrollView` だが ImageRenderer では白紙になるので、同じ並べ方を先頭から `clipped` で見せる
/// （スクロールの初期位置と同じ見え方）。
private struct HandStrip: View {
    let model: ColorRelayModel
    let metrics: ColorRelayHandLayout.Metrics
    /// 画面の余白へはみ出させる量（左右それぞれ）。今は `ColorRelayHandLayout.bleed`（8pt）。
    let bleed: CGFloat
    let measure: Measure
    let prefix: String

    var body: some View {
        let handHint = model.handHint
        let cardWidth = metrics.handCardWidth
        let cardHeight = ColorRelayCardSize(width: cardWidth).height
        GeometryReader { proxy in
            let available = max(0, proxy.size.width)
            let count = model.playerHand.count
            let exposure = ColorRelayHandLayout.exposure(count: count, cardWidth: cardWidth, available: available)
            let total = ColorRelayHandLayout.totalWidth(count: count, cardWidth: cardWidth, exposure: exposure)
            let _ = {
                measure.set("\(prefix).hand_count", CGFloat(count))
                measure.set("\(prefix).hand_card_w_pt", cardWidth)
                measure.set("\(prefix).hand_card_h_pt", cardHeight)
                measure.set("\(prefix).strip_w_pt", available)
                measure.set("\(prefix).exposure_pt", exposure)
                measure.set("\(prefix).hand_total_w_pt", total)
                // スクロール無しで全体が見える枚数（左端から）。
                let full = count == 0 ? 0 : min(count, 1 + Int(((available - cardWidth) / exposure).rounded(.down)))
                measure.set("\(prefix).visible_full_cards", CGFloat(full))
                measure.set("\(prefix).max_cards_no_scroll",
                            CGFloat(available >= cardWidth
                                    ? 1 + Int(((available - cardWidth) / ColorRelayHandLayout.minimumTapTarget).rounded(.down)) : 0))
            }()
            HStack(alignment: .top, spacing: exposure - cardWidth) {
                ForEach(model.playerHand) { card in
                    let isSelected = model.selectedID == card.id
                    ColorRelayCardView(card: card, width: cardWidth, selected: isSelected,
                                       hint: handHint?.state(for: card.id) ?? .none)
                        .offset(y: isSelected ? -ColorRelayHandLayout.lift : 0)
                }
            }
            .padding(.top, ColorRelayHandLayout.lift)
            .frame(width: max(total, available), height: cardHeight + ColorRelayHandLayout.lift, alignment: .leading)
            .frame(width: available, alignment: .leading)
            .clipped()
        }
        .frame(height: cardHeight + ColorRelayHandLayout.lift)
        .padding(.horizontal, -bleed)
    }
}

private struct HintLine: View {
    let model: ColorRelayModel
    var body: some View {
        let playable = model.playableCardIDs
        let message: String? = {
            if model.isPlayerPenalized { return "\(model.pendingDraw)枚引いて、番は飛ばされます" }
            if model.canEndTurn, !playable.isEmpty { return "引いた札は出せます。出さずに次へ回すこともできます" }
            if model.isPlayerTurn, model.handHint?.playable.isEmpty == true, model.canDraw { return "出せる札がありません。山から1枚引いてください" }
            return nil
        }()
        if let message {
            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill")
                    .scaledFont(11, weight: .bold)
                Text(verbatim: message)
                    .scaledFont(11, weight: .bold, design: .rounded)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(Theme.coralText)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HandArea: View {
    let model: ColorRelayModel
    let metrics: ColorRelayHandLayout.Metrics
    let bleed: CGFloat
    let measure: Measure
    let prefix: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            YouPill(model: model)
            HandStrip(model: model, metrics: metrics, bleed: bleed, measure: measure, prefix: prefix)
            HintLine(model: model)
        }
        .background(GeometryReader { geo in
            let _ = measure.set("\(prefix).hand_area_h_pt", geo.size.height)
            Color.clear
        })
    }
}

/// 操作の段（`actionArea` の `.playing` の写し: 1枚引く / 出す）。
private struct ActionRow: View {
    let model: ColorRelayModel
    let measure: Measure
    let prefix: String
    var body: some View {
        HStack(spacing: 12) {
            if model.canEndTurn {
                actionButton("出さずに次へ", role: .skip)
            } else {
                actionButton("1枚引く", role: .skip, disabled: !model.canDraw)
            }
            actionButton(model.selectedID == nil ? "札を選ぶ" : "出す", role: .primary, disabled: !model.canPlaySelection)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
        .background(GeometryReader { geo in
            let _ = measure.set("\(prefix).action_h_pt", geo.size.height)
            Color.clear
        })
    }

    private func actionButton(_ title: String, role: GameButtonRole, disabled: Bool = false) -> some View {
        Button {} label: {
            Text(verbatim: title)
                .themeBody(14)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .buttonStyle(GameButtonStyle(role: role, shape: .block))
        .disabled(disabled)
    }
}

// MARK: - 共通部品（ステータスバー・ナビバー・バナー）

private struct StatusStrip: View {
    let phone: Phone
    let onFelt: Bool
    var body: some View {
        HStack {
            Text("9:41").font(.system(size: 17, weight: .semibold))
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
            }
            .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(onFelt ? Color.white : Theme.ink)
        .padding(.horizontal, phone.safeTop > 30 ? 40 : 16)
        .frame(height: phone.safeTop, alignment: phone.safeTop > 30 ? .center : .bottom)
    }
}

private struct GlassCircle<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .frame(width: 44, height: 44)
            .background(Circle().fill(Theme.surface).shadow(color: Theme.cardShadow, radius: 8, y: 3))
    }
}

/// iOS 26 の「戻る ＋ ゲーム名 ＋ 右のアイコン群（？・＋）」。いろリレーは `gameChrome` に newGame を渡している（#2370）。
private struct NavHeader: View {
    let title: String
    let onFelt: Bool
    var body: some View {
        HStack(spacing: 8) {
            GlassCircle { Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.coral) }
            Spacer(minLength: 0)
            Text(verbatim: title)
                .themeBody(20, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(onFelt ? Color.white : Theme.ink)
                .shadow(color: onFelt ? .black.opacity(0.35) : .clear, radius: 2, y: 1)
            Spacer(minLength: 0)
            HStack(spacing: 24) {
                Image(systemName: "questionmark.circle")
                Image(systemName: "plus.circle.fill")
            }
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Theme.coral)
            .padding(.horizontal, 20)
            .frame(height: 44)
            .background(Capsule().fill(Theme.surface).shadow(color: Theme.cardShadow, radius: 8, y: 3))
        }
        .padding(.horizontal, 16)
        .frame(height: Phone.navBarHeight)
    }
}

private struct BannerPlaceholder: View {
    var body: some View {
        Text("バナー広告（50pt・そのまま残す）")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color(white: 0.3))
            .frame(maxWidth: .infinity)
            .frame(height: BannerSlot.height)
            .background(Color(white: 0.82))
    }
}

// MARK: - 今の画面（ColorRelayView.body の写し・v1.1.13 #2369 案 B）

private struct CurrentScreen: View {
    let phone: Phone
    let model: ColorRelayModel
    let measure: Measure
    let prefix: String

    var body: some View {
        let metrics = ColorRelayHandLayout.metrics(screenWidth: phone.width)
        let _ = {
            measure.set("\(prefix).seat_diameter_pt", metrics.seatDiameter)
            measure.set("\(prefix).opp_card_w_pt", metrics.opponentCardWidth)
        }()
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone, onFelt: false)
                NavHeader(title: "いろリレー", onFelt: false)
                VStack(spacing: 8) {
                    TableContent(model: model, metrics: metrics, measure: measure, prefix: prefix)
                        .cardTable()
                        .background(GeometryReader { geo in
                            let f = geo.frame(in: .named("phone"))
                            let rim = CardTableFrame.standard.insets(width: f.width)
                            let _ = {
                                measure.set("\(prefix).table_w_pt", f.width)
                                measure.set("\(prefix).table_h_pt", f.height)
                                measure.set("\(prefix).table_top_pt", f.minY)
                                measure.set("\(prefix).felt_w_pt", f.width - rim.leading - rim.trailing)
                                measure.set("\(prefix).felt_h_pt", f.height - rim.top - rim.bottom)
                                measure.set("\(prefix).felt_top_pt", f.minY + rim.top)
                            }()
                            Color.clear
                        })
                    HandArea(model: model, metrics: metrics, bleed: ColorRelayHandLayout.bleed, measure: measure, prefix: prefix)
                    // HowToPlayHint は初回だけ・RecommendationSlot は対局中は空。
                    ActionRow(model: model, measure: measure, prefix: prefix)
                    BannerPlaceholder()
                }
                .padding(Theme.pad)
                Color.clear.frame(height: phone.safeBottom)
            }
        }
        .frame(width: phone.width, height: phone.height)
    }
}

// MARK: - A（全画面）

private struct FullScreenA: View {
    let phone: Phone
    let model: ColorRelayModel
    let measure: Measure
    let prefix: String

    /// 木枠なし・角丸なしのフェルトだけ（画面全体を卓にする）。
    private static let feltOnly = CardTableFrame(
        top: .points(0), leading: .points(0), bottom: .points(0), trailing: .points(0),
        innerShadow: nil, aspectRatio: nil, cornerRadius: 0, dropShadow: false)

    /// 左右の余白。今の 16pt（＋木枠 12pt ＋ 内側 6pt）から、フェルトの上は 8pt だけ残す。
    /// 手札の帯は今 8pt はみ出して 16pt の余白に入り込むが、A では余白が 8pt なのではみ出させない（帯の幅は今と同じ）。
    static let sideInset: CGFloat = 8

    var body: some View {
        let metrics = ColorRelayHandLayout.metrics(screenWidth: phone.width)
        let _ = {
            measure.set("\(prefix).seat_diameter_pt", metrics.seatDiameter)
            measure.set("\(prefix).opp_card_w_pt", metrics.opponentCardWidth)
            measure.set("\(prefix).banner_band_pt", BannerSlot.height + 8 + phone.safeBottom)
        }()
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                CardTableSurface(frame: Self.feltOnly)
                    .background(GeometryReader { geo in
                        let f = geo.frame(in: .named("phone"))
                        let _ = {
                            measure.set("\(prefix).felt_w_pt", f.width)
                            measure.set("\(prefix).felt_h_pt", f.height)
                            measure.set("\(prefix).felt_top_pt", f.minY)
                        }()
                        Color.clear
                    })
                // 画面最下部のバナー（会長の方針: A のバナーは下）。地の色の帯に置く。
                VStack(spacing: 0) {
                    BannerPlaceholder().padding(.horizontal, Theme.pad).padding(.top, 8)
                    Color.clear.frame(height: phone.safeBottom)
                }
            }
            VStack(spacing: 0) {
                StatusStrip(phone: phone, onFelt: true)
                NavHeader(title: "いろリレー", onFelt: true)
                VStack(spacing: 8) {
                    // いろリレーには手数・点数が無く、卓の見出し（何ゲーム目・回る向き）が既に 1 行なので、
                    // 白い札は足さずそのままフェルトの上に置く。
                    TableContent(model: model, metrics: metrics, measure: measure, prefix: prefix)
                        .environment(\.cardTableInk, .felt)
                        .background(GeometryReader { geo in
                            let f = geo.frame(in: .named("phone"))
                            let _ = {
                                measure.set("\(prefix).table_w_pt", f.width)
                                measure.set("\(prefix).table_h_pt", f.height)
                                measure.set("\(prefix).table_top_pt", f.minY)
                            }()
                            Color.clear
                        })
                    HandArea(model: model, metrics: metrics, bleed: 0, measure: measure, prefix: prefix)
                    ActionRow(model: model, measure: measure, prefix: prefix)
                }
                .padding(.horizontal, Self.sideInset)
                .padding(.top, 8)
                .padding(.bottom, BannerSlot.height + 8 + phone.safeBottom)
            }
        }
        .frame(width: phone.width, height: phone.height)
    }
}

// MARK: - 並べて 1 枚に

private struct SideBySide<Left: View, Right: View>: View {
    let leftCaption: String
    let rightCaption: String
    let left: Left
    let right: Right
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 10) {
                Text(verbatim: leftCaption).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                left.clipShape(RoundedRectangle(cornerRadius: 28)).overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            }
            VStack(spacing: 10) {
                Text(verbatim: rightCaption).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                right.clipShape(RoundedRectangle(cornerRadius: 28)).overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            }
        }
        .padding(24)
        .background(Color(white: 0.94))
        .environment(\.colorScheme, .light)
    }
}

// MARK: - 局面を作る

private enum Moment: String { case few, many }

/// 人間の番を方針 `policy` で消化しながら進め、`stop` を満たしたら止める。決着したら false。
@MainActor
private func autoplay(_ model: ColorRelayModel, maxTurns: Int = 400,
                      policy: @MainActor (ColorRelayModel) -> Void,
                      until stop: @MainActor (ColorRelayModel) -> Bool) async -> Bool {
    var turns = 0
    while model.phase == .playing, turns < maxTurns {
        turns += 1
        await model.runCPUTurnsIfNeeded()
        guard model.phase == .playing, model.isPlayerTurn else { continue }
        if stop(model) { return true }
        policy(model)
    }
    return false
}

/// 出せる札があれば番号の小さい順に出す（既存の `ColorRelayModelTests` の方針）。
@MainActor
private func playLowest(_ model: ColorRelayModel) {
    if model.isPlayerPenalized {
        model.takePenalty()
    } else if let id = model.playableCardIDs.sorted().first,
              let card = model.playerHand.first(where: { $0.id == id }) {
        model.toggleSelection(card)
        model.playSelected(color: card.isWild ? ColorRelayRules.dominantColor(in: model.playerHand) : nil)
    } else if model.canDraw {
        model.drawCard()
    } else {
        model.endTurn()
    }
}

/// 一度も出さず、引けるだけ引いて番を回す（手札を増やすため）。
@MainActor
private func neverPlay(_ model: ColorRelayModel) {
    if model.isPlayerPenalized {
        model.takePenalty()
    } else if model.canDraw {
        model.drawCard()
    } else if model.canEndTurn {
        model.endTurn()
    }
}

/// 手札が少ない局面: 1 ゲーム目の途中・自分の番・手札 6〜8 枚・出せる札あり・相手の吹き出しが 2 つ以上見えている。
@MainActor
private func isFew(_ m: ColorRelayModel) -> Bool {
    m.isPlayerTurn && m.pendingDraw == 0 && !m.hasDrawnThisTurn && (6...8).contains(m.playerHand.count)
        && m.discardPile.count >= 4 && !m.playableCardIDs.isEmpty
        && m.lastActions[1...].filter { !$0.isEmpty }.count >= 2
        && m.hands[1...].allSatisfy { $0.count >= 3 }
}

/// 手札が多い局面: 自分の番・手札 14 枚以上・出せる札あり（引き札の免除や色選びのボタンは出ていない）。
@MainActor
private func isMany(_ m: ColorRelayModel) -> Bool {
    m.isPlayerTurn && m.pendingDraw == 0 && !m.hasDrawnThisTurn && m.playerHand.count >= 14
        && !m.playableCardIDs.isEmpty
}

@MainActor
private func makeModel(seed: UInt64, scene: Moment) async -> ColorRelayModel? {
    let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
    let model = ColorRelayModel(services: services, cpuDelay: .zero, seed: seed)
    model.startGame()
    let ok: Bool
    switch scene {
    case .few:
        ok = await autoplay(model, policy: playLowest, until: isFew)
        // 出せる札を 1 枚選んだ状態（持ち上がり・「出す」ボタンが有効）にする。
        if ok, let id = model.playableCardIDs.sorted().first, let card = model.playerHand.first(where: { $0.id == id }) {
            model.toggleSelection(card)
        }
    case .many:
        ok = await autoplay(model, policy: neverPlay, until: isMany)
    }
    return ok ? model : nil
}

@Suite("#2432 レイアウト検討モック（一時）")
struct LayoutMock2432Tests {
    private static var outDir: URL {
        let base = ProcessInfo.processInfo.environment["DUTY_SCRATCH_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: base).appendingPathComponent("mock2432", isDirectory: true)
    }

    @MainActor
    private static func write(_ view: some View, scale: CGFloat, name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent(name)
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        print("wrote \(url.path) \(image.width)x\(image.height)")
    }

    @Test("今 vs A を描いて寸法を書き出す")
    @MainActor
    func render() async throws {
        NSApp?.appearance = NSAppearance(named: .aqua)
        var seeds: [Moment: UInt64] = [:]
        for scene in [Moment.few, .many] {
            var seed: UInt64 = 2432
            while seeds[scene] == nil, seed < 2432 + 2000 {
                if await makeModel(seed: seed, scene: scene) != nil { seeds[scene] = seed }
                seed += 1
            }
        }
        let fewSeed = try #require(seeds[.few], "手札が少ない局面が作れる種が見つからない")
        let manySeed = try #require(seeds[.many], "手札が多い局面が作れる種が見つからない")
        print("seeds few \(fewSeed) many \(manySeed)")
        var all: [String: [String: Double]] = [:]
        all["seed"] = ["few": Double(fewSeed), "many": Double(manySeed)]
        for phone in phones {
            for scene in [Moment.few, .many] {
                let model = try #require(await makeModel(seed: scene == .few ? fewSeed : manySeed, scene: scene))
                print("\(scene): game \(model.gameNumber) hand \(model.playerHand.count) cpu \(model.hands[1...].map(\.count)) " +
                      "pile \(model.drawPile.count) discard \(model.discardPile.count) top \(String(describing: model.topCard)) " +
                      "active \(model.activeColor) actions \(model.lastActions) selected \(String(describing: model.selectedID))")
                let measure = Measure()
                let cur = "\(phone.name)_\(scene.rawValue)_cur", a = "\(phone.name)_\(scene.rawValue)_a"
                let view = SideBySide(
                    leftCaption: "今（v1.1.13・#2369 案 B）",
                    rightCaption: "A 全画面",
                    left: CurrentScreen(phone: phone, model: model, measure: measure, prefix: cur)
                        .coordinateSpace(name: "phone"),
                    right: FullScreenA(phone: phone, model: model, measure: measure, prefix: a)
                        .coordinateSpace(name: "phone")
                )
                try Self.write(view, scale: phone.scale, name: "\(phone.name)_colorrelay_\(scene.rawValue)_cur_vs_a.png")
                for (k, v) in measure.values {
                    let parts = k.split(separator: ".", maxSplits: 1).map(String.init)
                    all[parts[0], default: [:]][parts[1]] = v
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: Self.outDir.appendingPathComponent("measure_colorrelay.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
