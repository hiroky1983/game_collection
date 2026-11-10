// #2426 のレイアウト検討モック（ブラックジャック・今 vs C vs A）の生成器。**アプリのコードではない**（docs に置くだけ）。
// 使い方: このファイルを `Packages/GameKit/Tests/GameBlackjackTests/` にコピーし、
//   DUTY_SCRATCH_DIR=<出力先> swift test --package-path Packages/GameKit --filter LayoutMock2426
// で `<出力先>/mock2426/` に PNG と寸法の JSON が出る（シミュレータ不要。macOS の ImageRenderer で描く）。
// 実物の部品（`BJCardView`・`BJCardPlaceholder`・`GameButtonStyle`・`RecordLabel`・`popCard`・`themeBody` / `themeCaption`・
// `CardTableSurface`）をそのまま使い、`BlackjackView` の private な部分（チップの帯・ディーラー／あなたの札・スプリットの行・
// 操作欄・勝敗のバッジ）は同じ寸法・色で組み直した。ナビバー・ステータスバー・バナーは見た目を写して描いている。
// 配りの演出（`BJDealtCardView`）は `onAppear` で置かれるまで透明なので使わず、札は `BJCardView` を直接置く。
// 「今」は release/v1.1.14（= v1.1.13 の #2377 反映後）の `BlackjackView.body`。#2427（麻雀ソリティア）・#2431（大富豪）・
// #2439（2048）以降の兄弟 Issue の生成器と同じ型。終わったらコピーは消す（コミットしない）。
import Foundation
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
import Core
import CoreTestSupport
@testable import GameBlackjack

private struct Phone {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let safeTop: CGFloat
    let safeBottom: CGFloat
    let scale: CGFloat
    /// iOS 26 のナビバーの高さ。iPhone 17 は 54pt（実スクショ ip17_spiderzoom_v2cur.png の実測）、
    /// iPhone SE は 44pt（#2435 のブロック崩しで実機プローブに合わせた値。非ノッチ端末の標準）。
    let navBarHeight: CGFloat
}

private let phones = [
    Phone(name: "ip17", width: 402, height: 874, safeTop: 62, safeBottom: 34, scale: 3, navBarHeight: 54),
    Phone(name: "se3", width: 375, height: 667, safeTop: 20, safeBottom: 0, scale: 2, navBarHeight: 44),
]

/// 描画中に GeometryReader から寸法を書き留める器。
private final class Measure: @unchecked Sendable {
    var values: [String: Double] = [:]
    func set(_ key: String, _ value: CGFloat) { values[key] = (Double(value) * 100).rounded() / 100 }
}

/// C の「大きいバナー」の仮の枠。大きさは会長決裁待ち（#2111「C のバナーの大きさ」）なので、AdMob の 2 つの定型を描く。
private enum BannerKind {
    /// 今のアダプティブバナー（枠 50pt）。
    case standard
    /// ラージバナー 320×100（枠 100pt）。
    case large
    /// ミディアムレクタングル 300×250（枠 250pt。柵越えおじさんの記録ページで既に使っている寸法・`MediumRectangleSlot`）。
    case mrec

    var slotHeight: CGFloat {
        switch self {
        case .standard: return 50   // BannerSlot.height（View の static は MainActor 隔離なのでここでは値を書く）
        case .large: return 100
        case .mrec: return 250
        }
    }
    var adSize: CGSize? {
        switch self {
        case .standard: return nil
        case .large: return CGSize(width: 320, height: 100)
        case .mrec: return CGSize(width: 300, height: 250)
        }
    }
    var label: String {
        switch self {
        case .standard: return "バナー広告（50pt・そのまま残す）"
        case .large: return "大きいバナー（仮・ラージバナー 320×100）"
        case .mrec: return "大きいバナー（仮・MREC 300×250）"
        }
    }
    var suffix: String {
        switch self {
        case .standard: return "cur"
        case .large: return "c100"
        case .mrec: return "c250"
        }
    }
}

// MARK: - 共通部品（ステータスバー・ナビバー・バナー・枠の計測）

private struct StatusStrip: View {
    let phone: Phone
    var onFelt = false
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

/// iOS 26 の「戻る ＋ ゲーム名 ＋ 右のアイコン」。ブラックジャックのヘッダー右は「？」だけ（新規ボタン・早見表は無い）。
/// 色は `Theme.coralText`（#2377）。
private struct NavHeader: View {
    let phone: Phone
    let title: String
    var onFelt = false
    var body: some View {
        HStack(spacing: 8) {
            GlassCircle { Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.coralText) }
            Spacer(minLength: 0)
            Text(verbatim: title)
                .themeBody(20, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(onFelt ? Color.white : Theme.ink)
                .shadow(color: onFelt ? .black.opacity(0.35) : .clear, radius: 2, y: 1)
            Spacer(minLength: 0)
            GlassCircle { Image(systemName: "questionmark.circle").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.coralText) }
        }
        .padding(.horizontal, 16)
        .frame(height: phone.navBarHeight)
    }
}

/// バナーの仮の枠。C の大きいバナーは、枠（幅いっぱい・薄い灰）の中に広告そのものの寸法（濃い灰・中央）を描いて大きさが分かるようにする。
private struct BannerPlaceholder: View {
    let kind: BannerKind
    let measure: Measure
    let prefix: String
    var body: some View {
        ZStack {
            Color(white: 0.86)
            if let ad = kind.adSize {
                Color(white: 0.76).frame(width: ad.width, height: ad.height)
            }
            Text(verbatim: kind.label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(white: 0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: kind.slotHeight)
        .background(FrameProbe(measure: measure, prefix: prefix, key: "banner"))
    }
}

/// 枠の位置と大きさを `phone` 座標で書き留める。
private struct FrameProbe: View {
    let measure: Measure
    let prefix: String
    let key: String
    var body: some View {
        GeometryReader { geo in
            let f = geo.frame(in: .named("phone"))
            let _ = {
                measure.set("\(prefix).\(key)_w_pt", f.width)
                measure.set("\(prefix).\(key)_h_pt", f.height)
                measure.set("\(prefix).\(key)_top_pt", f.minY)
                measure.set("\(prefix).\(key)_bottom_pt", f.maxY)
            }()
            Color.clear
        }
    }
}

// MARK: - 札の行

/// 1 手ぶんの札の行。「今」は `BlackjackView` と同じ `HStack`（固定 62×90 の札を 8pt 間隔で並べるだけなので、
/// 枚数が増えると枠から溢れる）。A は `overlapToFit` で、幅に収まらないときだけ札を重ねて（段差を詰めて）収める。
/// 必要な幅・溢れる量を書き留める。
private struct CardRow: View {
    let cards: [BlackjackCard]
    /// 伏せる札の位置（ディーラーの 2 枚目・あなたの番のあいだだけ）。
    var hiddenIndex: Int? = nil
    var metrics: PlayingCardMetrics = .standard
    var spacing: CGFloat = 8
    /// 行に使える幅（計測用。A では収まらないときに重ねる幅）。
    let available: CGFloat
    var overlapToFit = false
    /// 行の中身を左に寄せる（スプリットの行は左寄せ・`Spacer(minLength: 0)`）。
    var leading = false
    let measure: Measure
    let key: String

    var body: some View {
        let n = cards.count
        let needed = CGFloat(n) * metrics.width + CGFloat(max(0, n - 1)) * spacing
        let _ = {
            measure.set("\(key)_count", CGFloat(n))
            measure.set("\(key)_needed_w_pt", needed)
            measure.set("\(key)_overflow_pt", max(0, needed - available))
            measure.set("\(key)_card_w_pt", metrics.width)
            measure.set("\(key)_card_h_pt", metrics.height)
        }()
        if overlapToFit, needed > available, n > 1 {
            // 収まらないので重ねる。左端の札は全部見え、以降は `step` ずつ右へずらす（右端の札も全部見える）。
            let step = (available - metrics.width) / CGFloat(n - 1)
            let _ = measure.set("\(key)_step_pt", step)
            ZStack(alignment: .leading) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                    BJCardView(card: card, faceUp: idx != hiddenIndex, metrics: metrics)
                        .offset(x: CGFloat(idx) * step)
                }
            }
            .frame(width: available, height: metrics.height, alignment: .leading)
        } else {
            HStack(spacing: spacing) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                    BJCardView(card: card, faceUp: idx != hiddenIndex, metrics: metrics)
                }
                if leading { Spacer(minLength: 0) }
            }
        }
    }
}

// MARK: - 中身の部品（`BlackjackView` の private な部分の写し）

/// 勝敗のバッジ（`BlackjackView.outcomeBadge` の写し）。
@MainActor @ViewBuilder
private func outcomeBadge(_ outcome: BlackjackOutcome) -> some View {
    switch outcome {
    case .playerBlackjack:
        badgeText(tr("ブラックジャック！"), fill: Theme.Fill.yellow, ink: Theme.onAccent)
    case .win:
        badgeText(tr("勝ち！"), fill: Theme.Fill.teal, ink: Theme.onAccent)
    case .push:
        badgeText(tr("引き分け"), fill: Theme.fillMuted, ink: .white)
    case .lose:
        badgeText(tr("負け"), fill: Theme.Fill.coral, ink: Theme.onAccent)
    case .bust:
        badgeText(tr("バスト"), fill: Theme.Fill.coral, ink: Theme.onAccent)
    }
}

@MainActor
private func badgeText(_ text: String, fill: Color, ink: Color) -> some View {
    Text(verbatim: text)
        .themeCaption(12, weight: .black, maxScale: 1.5)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(ink)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(fill))
}

/// 役割で色が決まる横いっぱいのボタン（`BlackjackView.actionButton` の写し）。
@MainActor
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

/// 合計の数字（14pt・黒）。
@MainActor
private func valueText(_ value: Int, color: Color) -> some View {
    Text(verbatim: "\(value)")
        .themeBody(14, weight: .black, maxScale: 1.5)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(color)
}

/// チップ・ベットの帯（`BlackjackView.chipsBar` の写し）。今は `popCard` の帯（縦 8）、A は 1 行の札（縦 5）。
private struct ChipsBar: View {
    let model: BlackjackModel
    var pill = false
    let measure: Measure
    let prefix: String
    var body: some View {
        HStack {
            Label(tr("チップ: %@枚", model.chips.formatted()), systemImage: "circle.hexagongrid.fill")
                .themeBody(14)
                .foregroundStyle(Theme.ink)
            Spacer()
            if model.bet > 0 {
                Label(tr("ベット: %@枚", model.bet.formatted()), systemImage: "dollarsign.circle.fill")
                    .themeBody(14)
                    .foregroundStyle(Theme.yellowText)
            }
        }
        .padding(.horizontal, pill ? 12 : 14).padding(.vertical, pill ? 5 : 8)
        .popCard(corner: pill ? 10 : Theme.cornerSmall)
        .background(FrameProbe(measure: measure, prefix: prefix, key: "chips"))
    }
}

/// ディーラーの札（`BlackjackView.dealerArea` の中身）。`onFelt` ならフェルトの上に直に置く（白い札を外し、文字を白にする）。
private struct DealerArea: View {
    let model: BlackjackModel
    let onFelt: Bool
    let rowAvailable: CGFloat
    let measure: Measure
    let prefix: String

    var body: some View {
        let showsTotal = model.phase == .result || model.phase == .dealerTurn
        VStack(spacing: 10) {
            HStack {
                Text(tr("ディーラー"))
                    .themeBody(13)
                    .foregroundStyle(onFelt ? Color.white.opacity(0.9) : Theme.inkSub)
                Spacer()
                if showsTotal {
                    valueText(model.dealerValue, color: onFelt ? .white : (model.dealerValue > 21 ? Theme.coralText : Theme.purple))
                } else if !model.dealerHand.isEmpty {
                    Text(verbatim: "\(model.dealerVisibleValue) + ?")
                        .themeBody(14, weight: .black, maxScale: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(onFelt ? Color.white : Theme.inkSub)
                }
            }
            CardRow(cards: model.dealerHand, hiddenIndex: model.phase == .playerTurn ? 1 : nil,
                    available: rowAvailable, overlapToFit: onFelt, measure: measure, key: "\(prefix).dealer_row")
                .frame(minHeight: 90)
        }
        .padding(.horizontal, onFelt ? 0 : 14).padding(.vertical, onFelt ? 0 : 14)
        .modifier(CardOrFelt(onFelt: onFelt))
        .background(FrameProbe(measure: measure, prefix: prefix, key: "dealer"))
    }
}

/// 白い札（`popCard`）に載せるか、フェルトに直に置くか。
private struct CardOrFelt: ViewModifier {
    let onFelt: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if onFelt { content } else { content.popCard(corner: Theme.cornerSmall) }
    }
}

/// あなたの札（`BlackjackView.playerArea` の中身。手が 1 つなら `singleHandArea`、スプリットなら `splitHandRow` × 2）。
private struct PlayerArea: View {
    let model: BlackjackModel
    let onFelt: Bool
    let rowAvailable: CGFloat
    let measure: Measure
    let prefix: String

    var body: some View {
        VStack(spacing: 10) {
            if model.hands.count > 1 {
                ForEach(Array(model.hands.enumerated()), id: \.element.id) { idx, hand in
                    splitHandRow(index: idx, hand: hand)
                }
            } else {
                singleHand
            }
        }
        .padding(.horizontal, onFelt ? 0 : 14).padding(.vertical, onFelt ? 0 : 14)
        .modifier(CardOrFelt(onFelt: onFelt))
        .background(FrameProbe(measure: measure, prefix: prefix, key: "player"))
    }

    private var singleHand: some View {
        VStack(spacing: 10) {
            HStack {
                Text(tr("あなた"))
                    .themeBody(13)
                    .foregroundStyle(onFelt ? Color.white : Theme.ink)
                Spacer()
                if !model.playerHand.isEmpty {
                    valueText(model.playerValue, color: onFelt ? .white : (model.playerValue > 21 ? Theme.coralText : Theme.tealText))
                }
                if let outcome = model.outcome {
                    outcomeBadge(outcome)
                }
            }
            CardRow(cards: model.playerHand, available: rowAvailable, overlapToFit: onFelt,
                    measure: measure, key: "\(prefix).player_row")
                .frame(minHeight: 90)
        }
    }

    /// スプリットで分かれた手 1 つぶん（札は `compact`・行の高さ 60）。
    private func splitHandRow(index: Int, hand: BlackjackHand) -> some View {
        let isActive = model.phase == .playerTurn && index == model.activeHandIndex
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(tr("ハンド%lld", index + 1))
                    .themeBody(13)
                    .foregroundStyle(onFelt ? Color.white : (isActive ? Theme.ink : Theme.inkSub))
                Text(hand.isDoubled ? tr("%@枚（ダブル）", hand.bet.formatted()) : tr("%@枚", hand.bet.formatted()))
                    .themeCaption(11, weight: .bold, maxScale: 1.5)
                    .foregroundStyle(onFelt ? Color.white.opacity(0.85) : Theme.inkSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if isActive {
                    Text(tr("操作中"))
                        .themeCaption(10, weight: .black, maxScale: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.Fill.teal))
                }
                Spacer(minLength: 0)
                valueText(hand.value, color: onFelt ? .white : (hand.isBusted ? Theme.coralText : Theme.tealText))
                if let outcome = hand.outcome {
                    outcomeBadge(outcome)
                }
            }
            CardRow(cards: hand.cards, metrics: .compact, spacing: 6, available: rowAvailable - 16, overlapToFit: onFelt,
                    leading: true, measure: measure, key: "\(prefix).hand\(index + 1)_row")
                .frame(minHeight: 60)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isActive ? (onFelt ? Color.white : Theme.teal) : Color.clear, lineWidth: 2)
        )
    }
}

/// 操作欄（`BlackjackView.actionArea` の写し。あなたの番は `playerActionView`、決着は `resultView`）。
private struct ActionArea: View {
    let model: BlackjackModel
    let onFelt: Bool
    let measure: Measure
    let prefix: String

    var body: some View {
        Group {
            switch model.phase {
            case .playerTurn:
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        actionButton(tr("スタンド"), role: .skip)
                        actionButton(tr("ヒット"), role: .primary)
                    }
                    if model.isDoubleDownApplicable || model.isSplitApplicable {
                        HStack(spacing: 12) {
                            if model.isDoubleDownApplicable {
                                actionButton(tr("ダブルダウン"), role: .declaration, disabled: !model.canDoubleDown)
                            }
                            if model.isSplitApplicable {
                                actionButton(tr("スプリット"), role: .declaration, disabled: !model.canSplit)
                            }
                        }
                    }
                }
            case .result:
                VStack(spacing: 8) {
                    RecordLabel(model.recordResult, textColor: onFelt ? .white : Theme.inkSub)
                    actionButton(tr("次のゲーム"), role: .primary)
                }
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, onFelt ? 0 : 14).padding(.vertical, onFelt ? 0 : 10)
        .modifier(CardOrFelt(onFelt: onFelt))
        .background(FrameProbe(measure: measure, prefix: prefix, key: "actions"))
    }
}

/// ディーラーとあなたのあいだの余り（`Spacer(minLength: 4)`・卓の中央）。
private struct Slack: View {
    let measure: Measure
    let prefix: String
    var body: some View {
        Spacer(minLength: 4)
            .background(GeometryReader { geo in
                let _ = measure.set("\(prefix).slack_pt", geo.size.height)
                Color.clear
            })
    }
}

// MARK: - 今の画面（BlackjackView.body の写し）／C（バナーだけ大きい）

private struct CurrentScreen: View {
    let phone: Phone
    let model: BlackjackModel
    let banner: BannerKind
    let measure: Measure
    let prefix: String

    var body: some View {
        // 札の行に使える幅 = 画面 − 外周 16×2 − 白い札の内側 14×2。
        let rowAvailable = phone.width - Theme.pad * 2 - 14 * 2
        let _ = {
            measure.set("\(prefix).avail_top_pt", phone.safeTop + phone.navBarHeight)
            measure.set("\(prefix).avail_bottom_pt", phone.height - phone.safeBottom)
            measure.set("\(prefix).row_avail_w_pt", rowAvailable)
        }()
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                // ステータスバー・ナビバーの分（中身は別の層に描く。下を見よ）。
                Color.clear.frame(height: phone.safeTop + phone.navBarHeight)
                VStack(spacing: 10) {
                    ChipsBar(model: model, measure: measure, prefix: prefix)
                    VStack(spacing: 10) {
                        DealerArea(model: model, onFelt: false, rowAvailable: rowAvailable, measure: measure, prefix: prefix)
                        Slack(measure: measure, prefix: prefix)
                        PlayerArea(model: model, onFelt: false, rowAvailable: rowAvailable, measure: measure, prefix: prefix)
                    }
                    // HowToPlayHint（初回だけの 1 行のミニガイド）は 2 回目以降は出ないので描かない。
                    ActionArea(model: model, onFelt: false, measure: measure, prefix: prefix)
                    // RecommendationSlot は対局中は何も出さない（決着後もレコメンドが無ければ空）。
                    BannerPlaceholder(kind: banner, measure: measure, prefix: prefix)
                }
                .padding(Theme.pad)
                .background(FrameProbe(measure: measure, prefix: prefix, key: "content"))
                // 札の行が幅に収まらないと VStack ごと広がる。実機ではナビバーは別物（画面幅のまま）なので、
                // 中身だけを画面幅の枠に収めて、溢れた分が左右に等しくはみ出す実機の見え方にする。
                .frame(width: phone.width)
                // 中身の枠の高さを使える高さに固定する。固定しないと溢れた分だけ画面全体（ナビバーごと）が上へずれて写る。
                // 実機と同じく、溢れた中身はこの枠の上下に等しくはみ出す（上はナビバーの下へ潜る）。
                .frame(height: phone.height - phone.safeTop - phone.navBarHeight - phone.safeBottom)
                Color.clear.frame(height: phone.safeBottom)
            }
            // 実機ではステータスバー・ナビバーは中身と別の層で、中身が縦に溢れても動かない（溢れた中身は上下に等しく
            // はみ出し、上はナビバーの下に潜る）。同じ見え方にするため、中身とは別にいちばん上の層へ描く。
            VStack(spacing: 0) {
                StatusStrip(phone: phone)
                NavHeader(phone: phone, title: tr("ブラックジャック"))
            }
        }
        .frame(width: phone.width, height: phone.height)
        .clipped()
    }
}

// MARK: - A（全画面の卓）

private struct FullScreenA: View {
    let phone: Phone
    let model: BlackjackModel
    /// 画面最下部のバナー。A は 50pt のまま。「A の詰め方に大きいバナーを足したら」の計算のために .large でも測る（画像は作らない）。
    var banner: BannerKind = .standard
    let measure: Measure
    let prefix: String

    /// 左右の余白。今の 16pt（＋白い札の内側 14pt）から 8pt に詰める（兄弟 Issue の A と同じ）。
    static let sideInset: CGFloat = 8

    /// 木枠なし・角丸なしのフェルトだけ（画面全体を卓にする）。
    private static let feltOnly = CardTableFrame(
        top: .points(0), leading: .points(0), bottom: .points(0), trailing: .points(0),
        innerShadow: nil, aspectRatio: nil, cornerRadius: 0, dropShadow: false)

    var body: some View {
        let bannerBand = banner.slotHeight + 8 + phone.safeBottom
        let rowAvailable = phone.width - Self.sideInset * 2
        let _ = {
            measure.set("\(prefix).felt_w_pt", phone.width)
            measure.set("\(prefix).felt_h_pt", phone.height - bannerBand)
            measure.set("\(prefix).avail_top_pt", phone.safeTop + phone.navBarHeight)
            measure.set("\(prefix).avail_bottom_pt", phone.height - bannerBand)
            measure.set("\(prefix).row_avail_w_pt", rowAvailable)
        }()
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                CardTableSurface(frame: Self.feltOnly)
                // 画面最下部のバナー（会長の方針: A のバナーは下）。地の色の帯に置く。
                VStack(spacing: 0) {
                    BannerPlaceholder(kind: banner, measure: measure, prefix: prefix)
                        .padding(.horizontal, Theme.pad).padding(.top, 8)
                    Color.clear.frame(height: phone.safeBottom)
                }
            }
            VStack(spacing: 0) {
                StatusStrip(phone: phone, onFelt: true)
                NavHeader(phone: phone, title: tr("ブラックジャック"), onFelt: true)
                VStack(spacing: 8) {
                    // チップ・ベットは 1 行の札に（今の帯より低い）。
                    ChipsBar(model: model, pill: true, measure: measure, prefix: prefix)
                    DealerArea(model: model, onFelt: true, rowAvailable: rowAvailable, measure: measure, prefix: prefix)
                    Slack(measure: measure, prefix: prefix)
                    PlayerArea(model: model, onFelt: true, rowAvailable: rowAvailable, measure: measure, prefix: prefix)
                    ActionArea(model: model, onFelt: true, measure: measure, prefix: prefix)
                        .padding(.top, 2)
                }
                .padding(.horizontal, Self.sideInset)
                .padding(.top, 8)
                .padding(.bottom, bannerBand)
                .background(FrameProbe(measure: measure, prefix: prefix, key: "content"))
            }
        }
        .frame(width: phone.width, height: phone.height)
        .clipped()
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

private func card(_ suit: BlackjackSuit, _ rank: Int) -> BlackjackCard {
    // `BlackjackModel.makeDeck` と同じ id の付け方（スート順 × 13 ＋ ランク − 1）。
    BlackjackCard(id: suit.rawValue * 13 + rank - 1, suit: suit, rank: rank)
}

private struct SceneSpec {
    let name: String
    let caption: String
    let chips: Int
    let hands: [BlackjackHand]
    let activeHandIndex: Int
    let dealer: [BlackjackCard]
    /// 復元したあと「スタンド」を押して決着まで進める（ディーラーの引きは `.zero` なので即精算）。
    let standAfterRestore: Bool
}

/// 局面は中断データ（`BlackjackSnapshot`・あなたの番で保存される形）を `MemorySnapshotStore` に入れて `init(services:)` で復元する。
private let scenes = [
    // 配った直後・8 のペア: 「スタンド／ヒット」と「ダブルダウン／スプリット」の 2 段が出る（操作欄がいちばん高い局面）。
    SceneSpec(
        name: "pair", caption: "配った直後（8 のペア・ダブルダウン／スプリットの段あり）", chips: 1000,
        hands: [BlackjackHand(id: 0, cards: [card(.spades, 8), card(.diamonds, 8)], bet: 100)],
        activeHandIndex: 0, dealer: [card(.clubs, 13), card(.hearts, 6)], standAfterRestore: false),
    // 手札が多いとき: あなた 6 枚（17）でスタンド → ディーラーは 5 枚目で 24 のバスト → 勝ち（決着の画面）。
    SceneSpec(
        name: "many", caption: "決着（あなた 6 枚・ディーラー 5 枚でバスト・勝ち）", chips: 1000,
        hands: [BlackjackHand(id: 0, cards: [card(.spades, 2), card(.hearts, 3), card(.diamonds, 2), card(.clubs, 4), card(.spades, 1), card(.hearts, 5)], bet: 100)],
        activeHandIndex: 0, dealer: [card(.clubs, 2), card(.diamonds, 3), card(.hearts, 4), card(.spades, 6), card(.diamonds, 9)], standAfterRestore: true),
    // スプリット後: ハンド 1（8・5・6 = 19）はスタンド済み、ハンド 2（8・10 = 18）を操作中（ダブルダウンの段あり）。
    SceneSpec(
        name: "split", caption: "スプリット後（ハンド 1 はスタンド済み・ハンド 2 を操作中）", chips: 1000,
        hands: [
            BlackjackHand(id: 0, cards: [card(.spades, 8), card(.clubs, 5), card(.diamonds, 6)], bet: 100, isFromSplit: true, isDone: true),
            BlackjackHand(id: 1, cards: [card(.diamonds, 8), card(.hearts, 10)], bet: 100, isFromSplit: true),
        ],
        activeHandIndex: 1, dealer: [card(.clubs, 13), card(.spades, 7)], standAfterRestore: false),
]

@MainActor
private func makeModel(_ scene: SceneSpec) throws -> BlackjackModel {
    let store = MemorySnapshotStore()
    let suite = "mock2426.\(scene.name)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    let totalBet = scene.hands.reduce(0) { $0 + $1.bet }
    try store.save(
        BlackjackSnapshot(
            playerHand: scene.hands[scene.activeHandIndex].cards, dealerHand: scene.dealer,
            // 山札は使わない局面（スタンドしてもディーラーが引かない）だが、空だと切り直すので残りを少し入れておく。
            deck: [card(.clubs, 9), card(.hearts, 12), card(.spades, 4)],
            chips: scene.chips, bet: totalBet, phase: .playerTurn,
            hands: scene.hands, activeHandIndex: scene.activeHandIndex),
        for: "blackjack")
    let services = GameServices(snapshots: store, ads: NoopAdService(), playLog: PlayLog(defaults: defaults))
    let model = BlackjackModel(services: services)
    #expect(model.phase == .playerTurn)
    #expect(model.hands.count == scene.hands.count)
    if scene.standAfterRestore {
        model.stand()
        #expect(model.phase == .result)
    }
    return model
}

@Suite("#2426 レイアウト検討モック（一時）")
struct LayoutMock2426Tests {
    private static var outDir: URL {
        let base = ProcessInfo.processInfo.environment["DUTY_SCRATCH_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: base).appendingPathComponent("mock2426", isDirectory: true)
    }

    /// 描く（寸法を書き留めるのが目的なので `save` が false なら PNG は書かない）。
    @MainActor
    private static func render(_ view: some View, scale: CGFloat, name: String, save: Bool) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        guard save else { return }
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent(name)
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        print("wrote \(url.path) \(image.width)x\(image.height)")
    }

    @Test("今 vs C vs A を描いて寸法を書き出す")
    @MainActor
    func render() throws {
        NSApp?.appearance = NSAppearance(named: .aqua)
        var all: [String: [String: Double]] = [:]
        for scene in scenes {
            let model = try makeModel(scene)
            print("\(scene.name): phase \(model.phase) chips \(model.chips) bet \(model.bet) hands \(model.hands.map { $0.cards.count }) dealer \(model.dealerHand.count) outcome \(String(describing: model.outcome)) player \(model.playerValue) dealerValue \(model.dealerValue)")
            all["scene_\(scene.name)"] = [
                "chips": Double(model.chips), "bet": Double(model.bet),
                "hands": Double(model.hands.count),
                "player_cards": Double(model.hands.map { $0.cards.count }.max() ?? 0),
                "dealer_cards": Double(model.dealerHand.count),
                "player_value": Double(model.playerValue), "dealer_value": Double(model.dealerValue),
                "is_result": model.phase == .result ? 1 : 0,
            ]
            for phone in phones {
                let measure = Measure()
                let base = "\(phone.name)_\(scene.name)"
                let cur = "\(base)_cur"
                let fileBase = "\(phone.name)_blackjack_\(scene.name)"
                // 今 vs C（ラージバナー 100pt）・今 vs C（MREC 250pt・画像は pair だけ）・今 vs A。
                for kind in [BannerKind.large, .mrec] {
                    let view = SideBySide(
                        leftCaption: "今（v1.1.14）",
                        rightCaption: "C 盤＋大きいバナー（仮 \(Int(kind.slotHeight))pt）",
                        left: CurrentScreen(phone: phone, model: model, banner: .standard, measure: measure, prefix: cur)
                            .coordinateSpace(name: "phone"),
                        right: CurrentScreen(phone: phone, model: model, banner: kind, measure: measure, prefix: "\(base)_\(kind.suffix)")
                            .coordinateSpace(name: "phone")
                    )
                    let name = kind == .large ? "\(fileBase)_cur_vs_c.png" : "\(fileBase)_cur_vs_c250.png"
                    try Self.render(view, scale: phone.scale, name: name, save: kind == .large || scene.name == "pair")
                }
                let viewA = SideBySide(
                    leftCaption: "今（v1.1.14）",
                    rightCaption: "A 全画面",
                    left: CurrentScreen(phone: phone, model: model, banner: .standard, measure: measure, prefix: cur)
                        .coordinateSpace(name: "phone"),
                    right: FullScreenA(phone: phone, model: model, measure: measure, prefix: "\(base)_a")
                        .coordinateSpace(name: "phone")
                )
                try Self.render(viewA, scale: phone.scale, name: "\(fileBase)_cur_vs_a.png", save: true)
                // 計算用: A の詰め方のままバナーだけ 100pt にしたらどうなるか（画像は作らない）。
                try Self.render(
                    FullScreenA(phone: phone, model: model, banner: .large, measure: measure, prefix: "\(base)_a100").coordinateSpace(name: "phone"),
                    scale: 1, name: "", save: false)

                for (k, v) in measure.values {
                    let parts = k.split(separator: ".", maxSplits: 1).map(String.init)
                    all[parts[0], default: [:]][parts[1]] = v
                }
                // 派生値: 使える高さ・中身の溢れ・盤を縮めずに入るバナーの枠・5 枚／6 枚が収まる札の幅。
                for prefix in [cur, "\(base)_c100", "\(base)_c250", "\(base)_a", "\(base)_a100"] {
                    guard var m = all[prefix] else { continue }
                    if let top = m["avail_top_pt"], let bottom = m["avail_bottom_pt"] {
                        m["avail_h_pt"] = bottom - top
                        if let ch = m["content_h_pt"] {
                            // 今・C の `content_h_pt` は外周 16 込み。A は下の余白にバナーの帯（50 + 8 + 下の安全域）を含むので、
                            // 溢れは「中身の下端 − 使える下端」で見る。
                            let overflow = prefix.hasSuffix("_a") || prefix.hasSuffix("_a100")
                                ? max(0, (m["content_bottom_pt"] ?? 0) - Double(phone.height))
                                : max(0, ch - (bottom - top))
                            m["content_overflow_h_pt"] = (overflow * 100).rounded() / 100
                        }
                    }
                    if let slack = m["slack_pt"], let banner = m["banner_h_pt"] {
                        // 余り（卓の中央の `Spacer(minLength: 4)`）をバナーに回したときの枠の高さ。最小の 4pt は回せないので差し引く。
                        m["max_banner_without_shrink_pt"] = ((banner + max(0, slack - 4)) * 100).rounded() / 100
                    }
                    if let w = m["row_avail_w_pt"] {
                        m["calc_card_w_fit5_pt"] = (((w - 8 * 4) / 5) * 100).rounded() / 100
                        m["calc_card_w_fit6_pt"] = (((w - 8 * 5) / 6) * 100).rounded() / 100
                    }
                    all[prefix] = m
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        try data.write(to: Self.outDir.appendingPathComponent("measure_blackjack.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
