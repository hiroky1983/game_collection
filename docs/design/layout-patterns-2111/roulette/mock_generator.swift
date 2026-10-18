// #2433 のレイアウト検討モック（ルーレット・今 vs A）の生成器。**アプリのコードではない**（docs に置くだけ）。
// 使い方: このファイルを `Packages/GameKit/Tests/GameRouletteTests/` にコピーし、`release/v1.1.13`（#2364 のホイール主役の画面）の上で
//   DUTY_SCRATCH_DIR=<出力先> swift test --package-path Packages/GameKit --filter LayoutMock2433
// で `<出力先>/mock2433/` に PNG 4 枚（2 状態 × 2 端末）と寸法の JSON が出る（シミュレータ不要。macOS の ImageRenderer で描く）。
// 「今」は `RouletteView.body` の写し（実物の `RouletteWheelView`・`RouletteMetrics`・`RecordLabel`・`HowToPlayHint`・
// `RecommendationSlot`・`popCard` をそのまま使い、ナビバー・ステータスバー・バナーだけ見た目を写して描く）。
// A は同じ中身を「外周 8pt・白い札なし・チップ/ベット/出目を 1 行の札」に置き直したもの（ホイールが余りを吸う規則は今のまま）。
// 局面は実物の `RouletteModel` を種から回して作る（赤に 6 回賭けて出目の履歴を作り、7 回目で 17 に当たる種を探す）。
// #2427〜#2431 の生成器と同じ型。終わったらコピーは消す（コミットしない）。
import Foundation
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
import Core
import CoreEngine
import CoreTestSupport
@testable import GameRoulette

private struct Phone {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let safeTop: CGFloat
    let safeBottom: CGFloat
    let scale: CGFloat
    /// iOS 26 のナビバーの高さ（実スクショ ip17_spiderzoom_v2cur.png の実測: コンテンツ開始 = 62 + 54 = 116pt）。
    static let navBarHeight: CGFloat = 54
    /// 今の画面で中身に使える高さ（`GeometryReader` が受け取る高さ）。
    var contentHeight: CGFloat { height - safeTop - Self.navBarHeight - safeBottom }
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

/// A の寸法。
private enum LayoutA {
    /// 画面の左右の余白（今の `Theme.pad` 16 から詰める。卓の無いゲームなので端いっぱいにはしない）。
    static let sideInset: CGFloat = 8
    /// 部品のあいだの縦の間隔。
    static let spacing: CGFloat = 8
}

// MARK: - 共通部品（ステータスバー・ヘッダー・バナー・プローブ）

private struct StatusStrip: View {
    let phone: Phone
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
        .foregroundStyle(Theme.ink)
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

/// iOS 26 の「戻る ＋ ゲーム名 ＋ 右のアイコン」。ルーレットのヘッダー右は「？」だけ（役の早見表・新規ボタンは無い）。
private struct NavHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            GlassCircle { Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.coral) }
            Spacer(minLength: 0)
            Text(tr("ルーレット"))
                .themeBody(20, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            GlassCircle { Image(systemName: "questionmark.circle").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.coral) }
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

// MARK: - 中身（今と A で共有する部品。`RouletteView` の写し）

/// チップの残り・今の賭けの札（`RouletteView.statPill`）。
private struct StatPill: View {
    let text: String
    let systemImage: String
    let color: Color
    var body: some View {
        Label(text, systemImage: systemImage)
            .scaledFont(13, weight: .bold, design: .rounded)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().strokeBorder(Theme.inkSub.opacity(0.35), lineWidth: 1))
    }
}

@MainActor
private func chipsText(_ model: RouletteModel) -> String { tr("チップ: %@枚", model.chips.formatted()) }
@MainActor
private func betText(_ model: RouletteModel) -> String { tr("ベット: %@枚", model.totalBet.formatted()) }
@MainActor
private func betColor(_ model: RouletteModel) -> Color { model.totalBet > 0 ? Theme.yellowText : Theme.inkSub }

@MainActor
private func chipsPill(_ model: RouletteModel) -> some View {
    StatPill(text: chipsText(model), systemImage: "circle.hexagongrid.fill", color: Theme.ink)
}
@MainActor
private func betPill(_ model: RouletteModel) -> some View {
    StatPill(text: betText(model), systemImage: "dollarsign.circle.fill", color: betColor(model))
}

/// 出目のバッジ（`RouletteView.numberBadge`）。
private struct NumberBadge: View {
    let number: Int
    let size: CGFloat
    var body: some View {
        Text(verbatim: "\(number)")
            .font(.system(size: size * 0.5, weight: .black, design: .rounded))
            .foregroundStyle(RouletteWheelView.textColor(for: number))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: size, height: size)
            .background(Circle().fill(RouletteWheelView.fill(for: number)))
    }
}

/// マスに置いた額（`RouletteView.chipBadge`）。
private struct ChipBadge: View {
    let amount: Int
    var body: some View {
        Text(verbatim: "\(amount)")
            .scaledFont(9, weight: .black, design: .rounded)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Capsule().fill(Color.white))
            .overlay(Capsule().strokeBorder(Theme.onAccent, lineWidth: 1))
    }
}

/// 直近の出目（`RouletteView.historyStrip`）。
private struct HistoryStrip: View {
    let history: [Int]
    var limit = 6
    var body: some View {
        if !history.isEmpty {
            HStack(spacing: 4) {
                Text(tr("出目"))
                    .scaledFont(11, weight: .semibold, design: .rounded)
                    .foregroundStyle(Theme.inkSub)
                    .fixedSize()
                ForEach(Array(history.prefix(limit).enumerated()), id: \.offset) { _, number in
                    NumberBadge(number: number, size: 20)
                }
            }
        }
    }
}

@MainActor
private func cellFill(_ kind: RouletteBetKind) -> Color {
    switch kind {
    case .straight(let number): return RouletteWheelView.fill(for: number)
    case .red:                  return Theme.Fill.coral
    case .black:                return Theme.fillStrong
    case .dozen:                return Theme.Fill.purple
    case .odd, .even, .low, .high: return Theme.Fill.yellow
    }
}

@MainActor
private func cellTextColor(_ kind: RouletteBetKind) -> Color {
    switch kind {
    case .straight(let number): return RouletteWheelView.textColor(for: number)
    case .black:                return .white
    default:                    return Theme.onAccent
    }
}

private func netLabel(_ net: Int) -> String {
    if net > 0 { return tr("+%lld枚", net) }
    if net == 0 { return tr("±0枚") }
    return tr("%lld枚", net)
}

private func netColor(_ net: Int) -> Color {
    net > 0 ? Theme.tealText : (net < 0 ? Theme.coralText : Theme.inkSub)
}

/// 余った枠いっぱいのホイール（`RouletteView.flexibleWheel` + `hubOverlay`）。直径と枠を書き留める。
private struct FlexibleWheel: View {
    let model: RouletteModel
    let rotation: Double
    let measure: Measure
    let prefix: String

    var body: some View {
        GeometryReader { proxy in
            let diameter = RouletteMetrics.wheelDiameter(fitting: proxy.size)
            let f = proxy.frame(in: .named("phone"))
            let _ = {
                measure.set("\(prefix).wheel_d_pt", diameter)
                measure.set("\(prefix).wheel_area_w_pt", proxy.size.width)
                measure.set("\(prefix).wheel_area_h_pt", proxy.size.height)
                measure.set("\(prefix).wheel_area_top_pt", f.minY)
                measure.set("\(prefix).wheel_area_bottom_pt", f.maxY)
            }()
            ZStack {
                RouletteWheelView(rotation: rotation, highlighted: model.phase == .result ? model.winningNumber : nil)
                    .frame(width: diameter, height: diameter)
                hub(diameter: diameter)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// ホイールの中心に出す答え（結果のときだけ）。
    @ViewBuilder
    private func hub(diameter: CGFloat) -> some View {
        if model.phase == .result, let number = model.winningNumber, let settlement = model.lastSettlement {
            VStack(spacing: 2) {
                NumberBadge(number: number, size: diameter * 0.17)
                Text(netLabel(settlement.net))
                    .font(.system(size: max(12, diameter * 0.065), weight: .black, design: .rounded))
                    .foregroundStyle(netColor(settlement.net))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(10)
            .background(Circle().fill(Theme.surface).shadow(color: Theme.cardShadow, radius: 6, y: 3))
            .frame(maxWidth: diameter * 0.5)
        }
    }
}

/// 賭けのマス 1 つ（`RouletteView.betCell`）。
private struct BetCell: View {
    let kind: RouletteBetKind
    let staked: Int
    let height: CGFloat
    var body: some View {
        Button {} label: {
            Text(kind.label)
                .scaledFont(12, weight: .bold, design: .rounded)
                .foregroundStyle(cellTextColor(kind))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(cellFill(kind), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if staked > 0 {
                        ChipBadge(amount: staked).offset(x: 3, y: -5)
                    }
                }
        }
        .buttonStyle(.pop)
    }
}

/// 「数字」タブ（`RouletteView.numberGrid`）。0 の右に 1〜36 を 4 段 × 9 列。17 と 0 のマスの枠を書き留める。
private struct NumberGrid: View {
    let model: RouletteModel
    let sizing: RouletteMetrics.Sizing
    let measure: Measure
    let prefix: String
    var body: some View {
        let spacing = RouletteMetrics.cellSpacing
        HStack(spacing: spacing) {
            BetCell(kind: .straight(0), staked: model.amount(on: .straight(0)), height: sizing.tableContentHeight)
                .frame(width: sizing.numberCellHeight)
                .background(FrameProbe(measure: measure, prefix: prefix, key: "zero"))
            VStack(spacing: spacing) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(1...9, id: \.self) { column in
                            let number = row * 9 + column
                            BetCell(kind: .straight(number), staked: model.amount(on: .straight(number)),
                                    height: sizing.numberCellHeight)
                                .background(number == 17 ? FrameProbe(measure: measure, prefix: prefix, key: "cell") : nil)
                        }
                    }
                }
            }
        }
    }
}

/// タブの見出し（`RouletteView.betTabs`）。「数字」を開いている状態。
private struct BetTabs: View {
    let model: RouletteModel
    let measure: Measure
    let prefix: String
    var body: some View {
        let inset = RouletteMetrics.tabTrackInset
        HStack(spacing: 4) {
            ForEach(RouletteBetTab.allCases, id: \.self) { tab in
                let selected = tab == .numbers
                let staked = model.bets.filter { tab.contains($0.kind) }.reduce(0) { $0 + $1.amount }
                Button {} label: {
                    HStack(spacing: 4) {
                        Text(tab == .numbers ? tr("数字（0〜36）") : tr("赤黒・奇偶・区分"))
                            .scaledFont(13, weight: .bold, design: .rounded)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if staked > 0 {
                            ChipBadge(amount: staked)
                        }
                    }
                    .foregroundStyle(selected ? Theme.onAccent : Theme.inkSub)
                    .frame(maxWidth: .infinity, minHeight: RouletteMetrics.tabButtonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerSmall - inset, style: .continuous)
                            .fill(selected ? Theme.Fill.yellow : Color.clear)
                    )
                }
                .buttonStyle(.pop)
            }
        }
        .padding(inset)
        .background(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous).fill(Theme.background))
        .background(FrameProbe(measure: measure, prefix: prefix, key: "tabs"))
    }
}

/// 置くチップの額を選ぶ丸ボタン（`RouletteView.chipButton`）。
private struct ChipButton: View {
    let amount: Int
    let selected: Bool
    let affordable: Bool
    var body: some View {
        Button {} label: {
            Text(verbatim: "\(amount)")
                .scaledFont(13, weight: .black, design: .rounded)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: RouletteMetrics.chipButtonSize, height: RouletteMetrics.chipButtonSize)
                .background(Circle().fill(selected ? Theme.Fill.yellow : Theme.surface))
                .overlay(
                    Circle().strokeBorder(selected ? Theme.yellow : Theme.inkSub.opacity(0.5),
                                          style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                )
                .foregroundStyle(affordable ? (selected ? Theme.onAccent : Theme.ink) : Theme.inkSub)
        }
        .buttonStyle(.pop)
    }
}

/// 横いっぱいの操作ボタン（`RouletteView.actionButton`）。
@MainActor
private func actionButton(_ title: String, color: Color, foreground: Color = Theme.onAccent, disabled: Bool = false) -> some View {
    Button {} label: {
        Text(title)
            .themeBody(14)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: RouletteMetrics.actionButtonMinHeight)
            .background(disabled ? Theme.inkSub.opacity(0.3) : color, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(disabled ? Theme.inkSub : foreground)
    }
    .buttonStyle(.pop)
}

/// 賭け中の操作欄（`RouletteView.bettingView`）。1 段目にチップ額 4 つ + 戻す、2 段目にスピン。
private struct BettingActions: View {
    let model: RouletteModel
    let sizing: RouletteMetrics.Sizing
    /// 今は白い札に載せる。A は地の上に直に置く。
    let card: Bool
    var body: some View {
        let rows = VStack(spacing: RouletteMetrics.actionRowSpacing) {
            HStack(spacing: 8) {
                Text(tr("チップ"))
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSub)
                    .fixedSize()
                ForEach(RouletteModel.chipOptions, id: \.self) { amount in
                    ChipButton(amount: amount, selected: model.selectedChip == amount,
                               affordable: model.availableChips >= amount)
                }
                actionButton(tr("戻す"), color: Theme.fillMuted, foreground: .white, disabled: model.bets.isEmpty)
            }
            actionButton(tr("スピン"), color: Theme.Fill.coral, disabled: !model.canSpin)
        }
        if card {
            rows.padding(.horizontal, 14).padding(.vertical, sizing.cardVerticalPadding)
                .popCard(corner: Theme.cornerSmall)
        } else {
            rows
        }
    }
}

/// 結果の操作欄（`RouletteView.resultView`）。
private struct ResultActions: View {
    let model: RouletteModel
    let sizing: RouletteMetrics.Sizing
    let card: Bool
    var body: some View {
        let rows = VStack(spacing: 8) {
            RecordLabel(model.recordResult)
            HStack(spacing: 12) {
                actionButton(tr("同じ賭けでもう一度"), color: Theme.Fill.yellow)
                actionButton(tr("次のゲーム"), color: Theme.Fill.coral)
            }
        }
        if card {
            rows.padding(.horizontal, 14).padding(.vertical, sizing.cardVerticalPadding)
                .popCard(corner: Theme.cornerSmall)
        } else {
            rows
        }
    }
}

/// 置いた口を 1 行に（`RouletteView.placedBetsRow`）。
private struct PlacedBetsRow: View {
    let model: RouletteModel

    private var placedKinds: [RouletteBetKind] {
        var seen = Set<RouletteBetKind>()
        return model.bets.map(\.kind).filter { seen.insert($0).inserted }
    }

    var body: some View {
        let kinds = placedKinds
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: kinds.count, through: 1, by: -1)), id: \.self) { shown in
                HStack(spacing: 8) {
                    ForEach(kinds.prefix(shown), id: \.self) { kind in
                        placedBet(kind)
                    }
                    if shown < kinds.count {
                        Text(tr("ほか%lld口", kinds.count - shown))
                            .scaledFont(12, weight: .bold, design: .rounded)
                            .foregroundStyle(Theme.inkSub)
                            .lineLimit(1)
                    }
                }
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func placedBet(_ kind: RouletteBetKind) -> some View {
        let amount = model.amount(on: kind)
        let settled = model.phase == .result
        let hit = settled && model.winningNumber.map(kind.covers) == true
        return HStack(spacing: 4) {
            Text(kind.label)
                .scaledFont(12, weight: .bold, design: .rounded)
                .foregroundStyle(cellTextColor(kind))
                .lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(cellFill(kind)))
            Text(hit ? tr("+%lld枚", amount * kind.payout) : tr("%lld枚", amount))
                .scaledFont(12, weight: .black, design: .rounded)
                .foregroundStyle(hit ? Theme.tealText : Theme.ink)
                .lineLimit(1)
        }
        .opacity(settled && !hit ? 0.4 : 1)
    }
}

/// 置いた口の一覧のカード（`RouletteView.betSummaryCard`）。A では出目の履歴を 1 行の札へ移すので `showsHistory` を落とす。
private struct BetSummary: View {
    let model: RouletteModel
    let showsHistory: Bool
    let minHeight: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.phase == .result ? tr("結果") : tr("あなたの賭け"))
                    .scaledFont(13, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.inkSub)
                Spacer(minLength: 0)
                if model.phase == .result, let settlement = model.lastSettlement {
                    Text(netLabel(settlement.net))
                        .scaledFont(18, weight: .black, design: .rounded)
                        .foregroundStyle(netColor(settlement.net))
                } else {
                    Text(tr("回転中…")).themeBody(13).foregroundStyle(Theme.inkSub)
                }
            }
            PlacedBetsRow(model: model)
                .frame(height: 26)
            if showsHistory {
                HistoryStrip(history: model.history)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .popCard(corner: Theme.cornerSmall)
    }
}

/// A の 1 行の札（チップ・ベット・出目の履歴）。今の「ホイールの角に重ねた 2 つの札 + 下の 1 行（履歴と案内）」をここへまとめる。
/// 出目は幅に合わせて iPhone 17 で 5 件・SE で 4 件（今の 6 件より少ない。SE は 5 件だと「ベット」の文字が切れる）。
private struct StatusLineA: View {
    let model: RouletteModel
    let phone: Phone
    let measure: Measure
    let prefix: String
    var body: some View {
        HStack(spacing: 8) {
            Label(chipsText(model), systemImage: "circle.hexagongrid.fill")
                .scaledFont(13, weight: .bold, design: .rounded)
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(Theme.ink)
            Label(betText(model), systemImage: "dollarsign.circle.fill")
                .scaledFont(13, weight: .bold, design: .rounded)
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(betColor(model))
            Spacer(minLength: 4)
            HistoryStrip(history: model.history, limit: phone.width >= 400 ? 5 : 4)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .popCard(corner: 10)
        .background(FrameProbe(measure: measure, prefix: prefix, key: "status"))
    }
}

// MARK: - 局面

private enum Situation: String, CaseIterable {
    /// 賭けの画面（「数字」タブ）: 赤 50・1〜12 50・17 に 100・0 に 50 を置き、「スピン」が押せる。出目の履歴 6 件。
    case betting
    /// ホイールの画面（結果）: 同じ口で回して 17 が出た直後（17 は黒なので当たりは 17 の 100 枚だけ。+3,350 枚）。
    case result
}

// MARK: - 今の画面（RouletteView.body の写し）

private struct CurrentScreen: View {
    let phone: Phone
    let model: RouletteModel
    let services: GameServices
    let rotation: Double
    let scene: Situation
    let measure: Measure
    let prefix: String

    var body: some View {
        let sizing = RouletteMetrics.sizing(forHeight: phone.contentHeight)
        let _ = {
            measure.set("\(prefix).avail_top_pt", phone.safeTop + Phone.navBarHeight)
            measure.set("\(prefix).avail_bottom_pt", phone.height - phone.safeBottom)
            measure.set("\(prefix).cell_h_pt", sizing.numberCellHeight)
            measure.set("\(prefix).table_content_h_pt", sizing.tableContentHeight)
            measure.set("\(prefix).outside_cell_h_pt", sizing.outsideCellHeight)
            measure.set("\(prefix).stack_spacing_pt", sizing.stackSpacing)
        }()
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone)
                NavHeader()
                VStack(spacing: sizing.stackSpacing) {
                    switch scene {
                    case .betting:
                        bettingWheelCard
                        tableCard(sizing)
                    case .result:
                        wheelScreen
                    }
                    // 初回だけ出る 1 行のミニガイド（2 回目以降は無い）。実物と同じ位置に置いて間隔の扱いもそろえる。
                    HowToPlayHint(.roulette, isVisible: false)
                    switch scene {
                    case .betting:
                        BettingActions(model: model, sizing: sizing, card: true)
                            .background(FrameProbe(measure: measure, prefix: prefix, key: "actions"))
                    case .result:
                        ResultActions(model: model, sizing: sizing, card: true)
                            .background(FrameProbe(measure: measure, prefix: prefix, key: "actions"))
                    }
                    RecommendationSlot(services: services, isFinished: model.phase == .result || model.sessionOver)
                    BannerPlaceholder()
                        .background(FrameProbe(measure: measure, prefix: prefix, key: "banner"))
                }
                .padding(Theme.pad)
                .frame(width: phone.width, height: phone.contentHeight, alignment: .top)
                .background(FrameProbe(measure: measure, prefix: prefix, key: "content"))
                Color.clear.frame(height: phone.safeBottom)
            }
        }
        .frame(width: phone.width, height: phone.height)
        .clipped()
    }

    /// 賭けの画面のホイールのカード（`RouletteView.bettingWheelCard`）。
    private var bettingWheelCard: some View {
        VStack(spacing: RouletteMetrics.wheelCardFooterSpacing) {
            FlexibleWheel(model: model, rotation: rotation, measure: measure, prefix: prefix)
                .overlay(alignment: .topLeading) {
                    chipsPill(model).background(FrameProbe(measure: measure, prefix: prefix, key: "status"))
                }
                .overlay(alignment: .topTrailing) { betPill(model) }
            HStack(spacing: 8) {
                HistoryStrip(history: model.history)
                Spacer(minLength: 0)
                Text(model.bets.isEmpty ? tr("賭ける場所をタップ") : tr("「スピン」で回します"))
                    .themeBody(12)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Theme.inkSub)
            }
            .frame(height: RouletteMetrics.wheelCardFooterHeight)
            .background(FrameProbe(measure: measure, prefix: prefix, key: "footer"))
        }
        .padding(RouletteMetrics.wheelCardPadding)
        .popCard(corner: Theme.cornerSmall)
        .background(FrameProbe(measure: measure, prefix: prefix, key: "wheel_card"))
    }

    /// 賭けの表（`RouletteView.tableCard`）。
    private func tableCard(_ sizing: RouletteMetrics.Sizing) -> some View {
        VStack(spacing: RouletteMetrics.tableTabSpacing) {
            BetTabs(model: model, measure: measure, prefix: prefix)
            NumberGrid(model: model, sizing: sizing, measure: measure, prefix: prefix)
                .frame(height: sizing.tableContentHeight)
        }
        .padding(RouletteMetrics.boardPadding)
        .popCard(corner: Theme.cornerSmall)
        .background(FrameProbe(measure: measure, prefix: prefix, key: "table"))
    }

    /// ホイールが主役の画面（`RouletteView.wheelScreen`）。
    private var wheelScreen: some View {
        VStack(spacing: 8) {
            HStack {
                chipsPill(model)
                Spacer(minLength: 8)
                betPill(model)
            }
            .frame(height: RouletteMetrics.wheelScreenStatsHeight)
            .background(FrameProbe(measure: measure, prefix: prefix, key: "status"))
            FlexibleWheel(model: model, rotation: rotation, measure: measure, prefix: prefix)
            BetSummary(model: model, showsHistory: true, minHeight: RouletteMetrics.betSummaryHeight)
                .background(FrameProbe(measure: measure, prefix: prefix, key: "summary"))
        }
    }
}

// MARK: - A（全画面）

private struct FullScreenA: View {
    let phone: Phone
    let model: RouletteModel
    let rotation: Double
    let scene: Situation
    let measure: Measure
    let prefix: String

    var body: some View {
        let bannerBand = BannerSlot.height + 8 + phone.safeBottom
        // 通常 / 詰める の切り替えは今と同じ端末判定にそろえる（境目 690pt は今の組み方の中身の高さで決めた値なので、
        // A の中身の高さ（バナーの帯を除く）で判定すると iPhone 17 まで「詰める」側に落ちる）。
        let sizing = RouletteMetrics.sizing(forHeight: phone.contentHeight)
        let _ = {
            measure.set("\(prefix).avail_top_pt", phone.safeTop + Phone.navBarHeight)
            measure.set("\(prefix).avail_bottom_pt", phone.height - bannerBand)
            measure.set("\(prefix).banner_band_pt", bannerBand)
            measure.set("\(prefix).cell_h_pt", sizing.numberCellHeight)
            measure.set("\(prefix).table_content_h_pt", sizing.tableContentHeight)
            measure.set("\(prefix).outside_cell_h_pt", sizing.outsideCellHeight)
            measure.set("\(prefix).stack_spacing_pt", LayoutA.spacing)
            // 計算値: 余りをホイールではなく表に回して数字のマスを 44pt にした場合の表の高さ（4 段 + 間隔 3 つ）。
            measure.set("\(prefix).calc_table44_content_h_pt", 44 * 4 + RouletteMetrics.cellSpacing * 3)
        }()
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone)
                NavHeader()
                VStack(spacing: LayoutA.spacing) {
                    StatusLineA(model: model, phone: phone, measure: measure, prefix: prefix)
                    FlexibleWheel(model: model, rotation: rotation, measure: measure, prefix: prefix)
                    switch scene {
                    case .betting:
                        VStack(spacing: RouletteMetrics.tableTabSpacing) {
                            BetTabs(model: model, measure: measure, prefix: prefix)
                            NumberGrid(model: model, sizing: sizing, measure: measure, prefix: prefix)
                                .frame(height: sizing.tableContentHeight)
                        }
                        .background(FrameProbe(measure: measure, prefix: prefix, key: "table"))
                        BettingActions(model: model, sizing: sizing, card: false)
                            .background(FrameProbe(measure: measure, prefix: prefix, key: "actions"))
                    case .result:
                        BetSummary(model: model, showsHistory: false, minHeight: 0)
                            .background(FrameProbe(measure: measure, prefix: prefix, key: "summary"))
                        ResultActions(model: model, sizing: sizing, card: false)
                            .background(FrameProbe(measure: measure, prefix: prefix, key: "actions"))
                    }
                }
                .padding(.horizontal, LayoutA.sideInset)
                .padding(.top, LayoutA.spacing)
                .background(FrameProbe(measure: measure, prefix: prefix, key: "content"))
                // 画面最下部のバナー（会長の方針: A のバナーは下）。
                BannerPlaceholder().padding(.horizontal, Theme.pad).padding(.top, 8)
                    .background(FrameProbe(measure: measure, prefix: prefix, key: "banner"))
                Color.clear.frame(height: phone.safeBottom)
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
                Text(leftCaption).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                left.clipShape(RoundedRectangle(cornerRadius: 28)).overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            }
            VStack(spacing: 10) {
                Text(rightCaption).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                right.clipShape(RoundedRectangle(cornerRadius: 28)).overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            }
        }
        .padding(24)
        .background(Color(white: 0.94))
        .environment(\.colorScheme, .light)
    }
}

// MARK: - 生成

@Suite("#2433 レイアウト検討モック（一時）")
struct LayoutMock2433Tests {
    private static var outDir: URL {
        let base = ProcessInfo.processInfo.environment["DUTY_SCRATCH_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: base).appendingPathComponent("mock2433", isDirectory: true)
    }

    /// 最後のスピンで当てる数字。17 は黒・2 番目の区分なので、数字 1 点だけ当たり・赤・1〜12・0 は外れ（当たりと外れが混ざる）。
    private static let targetNumber = 17

    /// 実物の `RouletteModel` を種から回して局面を作る。赤に 50 を 6 回賭けて出目の履歴を作り、
    /// 赤 50・1〜12 50・17 に 100・0 に 50 を置く。`result` ならそのまま回して 17 が出た直後にする。
    /// 7 回目の出目が 17 になる種を 2433 から順に探して固定する。
    @MainActor
    private static func makeModel(_ scene: Situation) throws -> (RouletteModel, GameServices, UInt64) {
        var seed: UInt64 = 2433
        while true {
            let defaults = try #require(UserDefaults(suiteName: "mock2433.\(seed)"))
            defaults.removePersistentDomain(forName: "mock2433.\(seed)")
            let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(),
                                        playLog: PlayLog(defaults: defaults))
            let model = RouletteModel(services: services, seed: seed, spinInterval: .zero)
            for _ in 0..<6 {
                model.selectedChip = 50
                model.placeBet(.red)
                model.spin()
                #expect(model.phase == .result)
                guard !model.sessionOver else { break }
                model.nextRound()
            }
            guard !model.sessionOver, model.history.count == 6 else { seed += 1; continue }
            model.selectedChip = 50
            model.placeBet(.red)
            model.placeBet(.dozen(1))
            model.placeBet(.straight(targetNumber))
            model.placeBet(.straight(targetNumber))
            model.placeBet(.straight(0))
            #expect(model.totalBet == 250)
            if scene == .betting {
                // 同じ種で 7 回目が 17 になるかだけ別のモデルで確かめる。
                let probe = try makeModel(.result)
                if probe.2 == seed { return (model, services, seed) }
                seed = probe.2
                continue
            }
            model.spin()
            if model.winningNumber == targetNumber {
                #expect(model.phase == .result)
                // 17 の 100 枚 × (1 + 35) が戻り、置いた 250 枚を引く（赤・1〜12・0 は外れ）。
                #expect(model.lastSettlement?.net == 100 * 36 - 250)
                #expect(model.lastSettlement == rouletteSettlement(bets: model.bets, winningNumber: targetNumber))
                return (model, services, seed)
            }
            seed += 1
        }
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
    func render() throws {
        NSApp?.appearance = NSAppearance(named: .aqua)
        var all: [String: [String: Double]] = [:]
        for phone in phones {
            for scene in Situation.allCases {
                let (model, services, seed) = try Self.makeModel(scene)
                print("scene \(scene) seed \(seed) chips \(model.chips) history \(model.history) winning \(String(describing: model.winningNumber))")
                // 止まった位置: 出目のポケットが 12 時の玉の真下に来る角度（`RouletteView.spinWheel` と同じ）。
                let rotation = model.winningNumber.map {
                    RouletteMotion.targetRotation(from: 0, toPocket: RouletteWheel.pocketIndex(of: $0))
                } ?? 0
                let measure = Measure()
                let cur = "\(phone.name)_\(scene.rawValue)_cur", a = "\(phone.name)_\(scene.rawValue)_a"
                let view = SideBySide(
                    leftCaption: "今",
                    rightCaption: "A 全画面",
                    left: CurrentScreen(phone: phone, model: model, services: services, rotation: rotation,
                                        scene: scene, measure: measure, prefix: cur)
                        .coordinateSpace(name: "phone"),
                    right: FullScreenA(phone: phone, model: model, rotation: rotation, scene: scene,
                                       measure: measure, prefix: a)
                        .coordinateSpace(name: "phone")
                )
                try Self.write(view, scale: phone.scale, name: "\(phone.name)_roulette_\(scene.rawValue)_cur_vs_a.png")
                for (k, v) in measure.values {
                    let parts = k.split(separator: ".", maxSplits: 1).map(String.init)
                    all[parts[0], default: [:]][parts[1]] = v
                }
            }
        }
        // 計算値: A で余りを表に回して数字のマスを 44pt にしたときに残るホイールの直径。
        for (key, var values) in all where key.hasSuffix("_a") {
            if let d = values["wheel_d_pt"], let t = values["table_content_h_pt"], let t44 = values["calc_table44_content_h_pt"],
               key.contains("betting") {
                values["calc_wheel_if_table44_d_pt"] = ((d - (t44 - t)) * 100).rounded() / 100
                all[key] = values
            }
        }
        let data = try JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: Self.outDir.appendingPathComponent("measure_roulette.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
