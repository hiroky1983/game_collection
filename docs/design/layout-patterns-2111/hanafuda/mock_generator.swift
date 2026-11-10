// #2430 のレイアウト検討モック（花札こいこい・今 vs A）の生成器。**アプリのコードではない**（docs に置くだけ）。
// 使い方: このファイルを `Packages/GameKit/Tests/GameHanafudaTests/` にコピーし（release/v1.1.13 以降・#2336 反映後の
//   コードで）、
//   DUTY_SCRATCH_DIR=<出力先> swift test --package-path Packages/GameKit --filter LayoutMock2430
// で `<出力先>/mock2430/` に PNG 4 枚と寸法の JSON が出る（シミュレータ不要。macOS の ImageRenderer で描く）。
// 実物の部品（HanafudaCardFace・HanafudaFit・HanafudaCapturedGroup・GameStatusBar・TurnBadge・popCard）をそのまま使い、
// ナビバー・ステータスバー・バナー・「⋯」だけ見た目を写して描いている。
// 画面は `HanafudaView.body` の写し（局の途中と配り直後の 2 局面）。#2427（麻雀ソリティア）・#2429（ソリティア）の生成器と同じ型。
// 終わったらコピーは消す（コミットしない）。
import Foundation
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
import Core
import CoreTestSupport
@testable import GameHanafuda

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

// MARK: - 得点・見出し（HanafudaView の写し）

private struct ScoreChip: View {
    let title: String
    let value: Int
    let fill: Color
    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .themeCaption(12, weight: .bold, maxScale: 1.5)
                .lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(fill))
            Text(verbatim: "\(value)文")
                .themeBody(16, weight: .heavy, maxScale: 1.5)
                .lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(Theme.ink)
        }
    }
}

@MainActor
private func roundText(_ model: HanafudaModel) -> String {
    model.round > model.options.rounds ? "延長戦" : "\(model.round) / \(model.options.rounds)局"
}

@MainActor
private func yakuLine(_ model: HanafudaModel, _ player: HanafudaPlayer) -> String {
    let hits = model.yaku(of: player)
    guard !hits.isEmpty else { return "役なし" }
    let total = hits.reduce(0) { $0 + $1.points }
    return "\(hits.map(\.yaku.shortName).joined(separator: "・"))（\(total)文）"
}

/// 今の「状態の帯 ＋ メッセージの行」（`HanafudaView.scoreBar` の写し）。
private struct ScoreBar: View {
    let model: HanafudaModel
    let measure: Measure
    let prefix: String
    var body: some View {
        VStack(spacing: 6) {
            GameStatusBar {
                TurnBadge(isYourTurn: model.turn == .human)
            } trailing: {
                ScoreChip(title: "あなた", value: model.humanTotal, fill: Theme.Fill.teal)
                ScoreChip(title: "CPU", value: model.cpuTotal, fill: Theme.Fill.coral)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.message)
                    .themeCaption(13, weight: .semibold, maxScale: 1.5)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                Text(roundText(model))
                    .themeCaption(13, weight: .bold, maxScale: 1.5)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(Theme.inkSub)
            }
            .padding(.horizontal, GameStatusBarStyle.horizontalPadding)
        }
        .background(GeometryReader { geo in
            let _ = measure.set("\(prefix).status_h_pt", geo.size.height)
            Color.clear
        })
    }
}

/// A の 1 行の札（手番・得点・局数）。メッセージは「⋯」の行のキャプションへ移す。
private struct StatusLineA: View {
    let model: HanafudaModel
    let measure: Measure
    let prefix: String
    var body: some View {
        HStack(spacing: 8) {
            TurnBadge(isYourTurn: model.turn == .human)
            Spacer(minLength: 8)
            ScoreChip(title: "あなた", value: model.humanTotal, fill: Theme.Fill.teal)
            ScoreChip(title: "CPU", value: model.cpuTotal, fill: Theme.Fill.coral)
            Text(roundText(model))
                .themeCaption(13, weight: .bold, maxScale: 1.5)
                .lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(Theme.inkSub)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .popCard(corner: 10)
        .background(GeometryReader { geo in
            let _ = measure.set("\(prefix).status_h_pt", geo.size.height)
            Color.clear
        })
    }
}

// MARK: - 札の 3 つのカード（HanafudaView の opponentArea / fieldArea / handArea の写し）

private struct CapturedGroups: View {
    let cards: [HanafudaCard]
    let height: CGFloat
    let measure: Measure?
    let prefix: String
    var body: some View {
        let groups = HanafudaCapturedGroup.groups(of: cards)
        GeometryReader { geo in
            let cardWidth = height / HanafudaCardArt.aspectRatio
            let widths = HanafudaFit.groupWidths(total: geo.size.width, cardWidth: cardWidth, counts: groups.map(\.cards.count))
            let _ = {
                guard let measure else { return }
                measure.set("\(prefix).strip_card_w_pt", cardWidth)
                measure.set("\(prefix).kasu_col_w_pt", widths[3])
                measure.set("\(prefix).kasu_overlap_step_pt",
                            HanafudaFit.overlapStep(groupWidth: widths[3], cardWidth: cardWidth, count: groups[3].cards.count))
            }()
            HStack(alignment: .top, spacing: HanafudaFit.groupSpacing) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    column(group, width: widths[index], cardWidth: cardWidth)
                }
            }
        }
        .frame(height: HanafudaFit.groupHeaderHeight + HanafudaFit.groupHeaderSpacing + height)
    }

    private func column(_ group: HanafudaCapturedGroup, width: CGFloat, cardWidth: CGFloat) -> some View {
        let hex = HanafudaCardArt.kindHex(for: group.kind)
        let step = HanafudaFit.overlapStep(groupWidth: width, cardWidth: cardWidth, count: group.cards.count)
        return VStack(alignment: .leading, spacing: HanafudaFit.groupHeaderSpacing) {
            Text(verbatim: "\(group.kind.label) \(group.cards.count)/\(group.goal)")
                .themeCaption(11, weight: .heavy, maxScale: 1.3)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Color(hex: HanafudaCardArt.bandLabelHex(on: hex)))
                .padding(.horizontal, 5)
                .frame(height: HanafudaFit.groupHeaderHeight)
                .background(Capsule().fill(Color(hex: hex).opacity(group.isComplete ? 1 : 0.8)))
            ZStack(alignment: .leading) {
                if group.cards.isEmpty {
                    RoundedRectangle(cornerRadius: cardWidth * 0.12, style: .continuous)
                        .strokeBorder(Theme.inkSub.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(width: cardWidth, height: height)
                }
                ForEach(Array(group.cards.enumerated()), id: \.element.id) { index, card in
                    HanafudaCardFace(card: card, showsKindLabel: index == group.cards.count - 1)
                        .frame(width: cardWidth, height: height)
                        .offset(x: CGFloat(index) * step)
                }
            }
            .frame(width: width, height: height, alignment: .leading)
        }
        .frame(width: width, alignment: .leading)
    }
}

private struct Caption: View {
    let text: String
    var weight: Font.Weight = .bold
    var color: Color = Theme.inkSub
    var size: CGFloat = 13
    var body: some View {
        Text(verbatim: text)
            .themeCaption(size, weight: weight, maxScale: 1.5)
            .lineLimit(1).minimumScaleFactor(0.5)
            .foregroundStyle(color)
    }
}

private struct OpponentArea: View {
    let model: HanafudaModel
    let fit: HanafudaFit.Metrics
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Caption(text: "CPUの取り札", color: model.turn == .cpu ? Theme.coralText : Theme.inkSub)
                Caption(text: yakuLine(model, .cpu), weight: .semibold).minimumScaleFactor(0.7)
                Spacer()
                Caption(text: "手札\(model.cpuHand.count)枚", weight: .semibold)
            }
            CapturedGroups(cards: model.cpuCaptured, height: fit.stripHeight, measure: nil, prefix: "")
        }
        .padding(10)
        .popCard(corner: Theme.cornerSmall)
    }
}

private struct CardGrid: View {
    let cards: [HanafudaCard]
    let fit: HanafudaFit.Metrics
    let dimmed: (HanafudaCard) -> Bool
    let highlighted: (HanafudaCard) -> Bool
    var body: some View {
        LazyVGrid(columns: fit.columns, spacing: HanafudaFit.gap) {
            ForEach(cards) { card in
                HanafudaCardFace(card: card, isDimmed: dimmed(card), isHighlighted: highlighted(card))
            }
        }
    }
}

private struct FieldArea: View {
    let model: HanafudaModel
    let fit: HanafudaFit.Metrics
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Caption(text: "場")
                Spacer()
                if let drawn = model.drawnCard {
                    HStack(spacing: 4) {
                        Caption(text: "めくり札", color: Theme.coralText)
                        HanafudaCardFace(card: drawn, isHighlighted: true)
                            .frame(height: HanafudaFit.drawnCardHeight)
                    }
                }
                Caption(text: "山札\(model.deck.count)枚", weight: .heavy, size: 14)
            }
            CardGrid(cards: model.field, fit: fit,
                     dimmed: { model.selection != nil && !(model.selection?.candidates.contains($0) ?? false) },
                     highlighted: { model.selection?.candidates.contains($0) ?? false })
        }
        .padding(HanafudaFit.cardPadding)
        .frame(maxWidth: .infinity)
        .popCard(corner: Theme.cornerSmall)
    }
}

private struct HandArea: View {
    let model: HanafudaModel
    let fit: HanafudaFit.Metrics
    let measure: Measure
    let prefix: String
    var body: some View {
        // ヒント ON（既定）で自分の手番なら「取れる札」を強調する（`hintedHandCards` の写し）。
        let hinted = model.isPlayerTurn ? model.capturableHandCards() : []
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Caption(text: "あなたの取り札", color: model.isPlayerTurn ? Theme.tealText : Theme.inkSub)
                Caption(text: yakuLine(model, .human), weight: .semibold).minimumScaleFactor(0.7)
                Spacer()
            }
            CapturedGroups(cards: model.humanCaptured, height: fit.stripHeight, measure: measure, prefix: prefix)
            CardGrid(cards: model.humanHand, fit: fit,
                     dimmed: { _ in model.selection != nil },
                     highlighted: { hinted.contains($0.id) })
                .frame(maxWidth: .infinity)
        }
        .padding(10)
        .popCard(corner: Theme.cornerSmall)
    }
}

private struct EllipsisButton: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Theme.fillMuted))
    }
}

/// 札のすぐ下の「⋯」の行（`GameOverflowBar(menuItems:verticalPadding:)` の写し。Menu は macOS で見た目が変わるので
/// 「⋯」だけ自前で描く。寸法は同じ）。A ではメッセージをこの行のキャプション（`GameOverflowCaption` の位置）に置く。
private struct OverflowRow: View {
    var caption: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let caption {
                Text(verbatim: caption)
                    .themeCaption(12, maxScale: 1.3)
                    .foregroundStyle(Theme.inkSub)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
            }
            Spacer(minLength: 0)
            EllipsisButton()
        }
        .frame(minHeight: BoardGameControlMetrics.minTapTarget)
        .padding(.vertical, HanafudaFit.overflowRowPadding)
    }
}

/// 3 つのカード ＋「⋯」の行（`HanafudaView.body` の GeometryReader の中身の写し）。寸法を書き留める。
private struct Area: View {
    let model: HanafudaModel
    let measure: Measure
    let prefix: String
    var captionInRow: String? = nil

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let fit = HanafudaFit.metrics(
                availableWidth: size.width,
                availableHeight: size.height - (HanafudaFit.overflowRowHeight + HanafudaFit.sectionSpacing),
                stripHeight: HanafudaFit.baseStripHeight,
                fieldCount: model.field.count, handCount: model.humanHand.count
            )
            // 配り直後（8 枚ずつ・取り札なし）の札の大きさも同じ枠で数えておく。
            let startFit = HanafudaFit.metrics(
                availableWidth: size.width,
                availableHeight: size.height - (HanafudaFit.overflowRowHeight + HanafudaFit.sectionSpacing),
                stripHeight: HanafudaFit.baseStripHeight, fieldCount: 8, handCount: 8
            )
            let frame = geo.frame(in: .named("phone"))
            let cardH = fit.cardWidth * HanafudaCardArt.aspectRatio
            let _ = {
                measure.set("\(prefix).area_w_pt", size.width)
                measure.set("\(prefix).area_h_pt", size.height)
                measure.set("\(prefix).area_top_pt", frame.minY)
                measure.set("\(prefix).card_w_pt", fit.cardWidth)
                measure.set("\(prefix).card_h_pt", cardH)
                measure.set("\(prefix).columns", CGFloat(fit.columnCount))
                measure.set("\(prefix).field_rows", CGFloat((model.field.count + fit.columnCount - 1) / fit.columnCount))
                measure.set("\(prefix).hand_rows", CGFloat((model.humanHand.count + fit.columnCount - 1) / fit.columnCount))
                measure.set("\(prefix).strip_h_pt", fit.stripHeight)
                // 帯の月の数字の大きさ（`HanafudaCardFace.drawBand`: min(幅 × 0.30, 帯の高さ × 0.85)。帯は札の高さの 20%）。
                measure.set("\(prefix).band_font_pt", min(fit.cardWidth * 0.30, cardH * 0.20 * 0.85))
                let stripW = fit.stripHeight / HanafudaCardArt.aspectRatio
                measure.set("\(prefix).strip_band_font_pt", min(stripW * 0.30, fit.stripHeight * 0.20 * 0.85))
                measure.set("\(prefix).start8_card_w_pt", startFit.cardWidth)
                measure.set("\(prefix).start8_columns", CGFloat(startFit.columnCount))
                measure.set("\(prefix).start8_strip_h_pt", startFit.stripHeight)
            }()
            VStack(spacing: HanafudaFit.sectionSpacing) {
                OpponentArea(model: model, fit: fit)
                FieldArea(model: model, fit: fit)
                HandArea(model: model, fit: fit, measure: measure, prefix: prefix)
                OverflowRow(caption: captionInRow)
            }
            .background(GeometryReader { inner in
                let _ = {
                    measure.set("\(prefix).used_h_pt", inner.size.height)
                    measure.set("\(prefix).slack_pt", size.height - inner.size.height)
                }()
                Color.clear
            })
            .frame(width: size.width, height: size.height, alignment: .top)
        }
    }
}

// MARK: - 共通部品（ステータスバー・ナビバー・バナー）

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

/// iOS 26 の「戻る ＋ ゲーム名 ＋ 右のアイコン群（役の早見表・？）」。花札には「新規」ボタンは無い（`gameChrome` に newGame を渡していない）。
private struct NavHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            GlassCircle { Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.coral) }
            Spacer(minLength: 0)
            Text("花札こいこい")
                .themeBody(20, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            HStack(spacing: 24) {
                Image(systemName: "list.bullet.rectangle")
                Image(systemName: "questionmark.circle")
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

// MARK: - 今の画面（HanafudaView.body の写し）

private struct CurrentScreen: View {
    let phone: Phone
    let model: HanafudaModel
    let measure: Measure
    let prefix: String

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone)
                NavHeader()
                VStack(spacing: 8) {
                    ScoreBar(model: model, measure: measure, prefix: prefix)
                    Area(model: model, measure: measure, prefix: prefix)
                    // HowToPlayHint は初回だけ・actionArea と RecommendationSlot は対局中は空。
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
    let model: HanafudaModel
    let measure: Measure
    let prefix: String

    /// 左右の余白。今の 16pt から詰める（卓の無いゲームなので、カードを画面の端いっぱいにはせず 8pt だけ残す）。
    static let sideInset: CGFloat = 8

    var body: some View {
        let _ = measure.set("\(prefix).banner_band_pt", BannerSlot.height + 8 + phone.safeBottom)
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone)
                NavHeader()
                VStack(spacing: 8) {
                    // 手番・得点・局数を 1 行の札にまとめる（今の 44pt の帯 ＋ メッセージの行より低い）。
                    StatusLineA(model: model, measure: measure, prefix: prefix)
                    Area(model: model, measure: measure, prefix: prefix, captionInRow: model.message)
                }
                .padding(.horizontal, Self.sideInset)
                .padding(.top, 8)
                // 画面最下部のバナー（会長の方針: A のバナーは下）。
                BannerPlaceholder().padding(.horizontal, Theme.pad).padding(.top, 8)
                Color.clear.frame(height: phone.safeBottom)
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

// MARK: - 局面を作る

private enum Moment: String { case mid, start }

@MainActor
private func autoplay(_ model: HanafudaModel, maxSteps: Int = 400, until stop: @MainActor (HanafudaModel) -> Bool) -> Bool {
    for _ in 0..<maxSteps {
        if stop(model) { return true }
        switch model.phase {
        case .playing:
            if let selection = model.selection {
                model.chooseFieldCard(selection.candidates[0])
            } else if model.turn == .human {
                let capturable = model.capturableHandCards()
                guard let card = model.humanHand.first(where: { capturable.contains($0.id) }) ?? model.humanHand.first else { return false }
                model.play(card)
            } else {
                model.stepCPU()
            }
        case .koiKoiPrompt:
            if model.canStop { model.declareStop() } else { model.declareKoiKoi() }
        case .roundResult:
            model.advanceAfterRound()
        case .idle, .matchResult:
            return false
        }
    }
    return false
}

/// 2 局目の途中（手札 5 枚・あなたの番・取り札が両者に 4 枚以上）になる種を探す。
@MainActor
private func isMid(_ m: HanafudaModel) -> Bool {
    m.round == 2 && m.phase == .playing && m.turn == .human && m.selection == nil
        && m.humanHand.count == 5 && (6...9).contains(m.field.count)
        && m.humanCaptured.count >= 4 && m.cpuCaptured.count >= 4
        && m.humanCaptured.contains { $0.kind == .hikari } && m.cpuCaptured.contains { $0.kind == .hikari }
        && !m.capturableHandCards().isEmpty
}

@MainActor
private func isStart(_ m: HanafudaModel) -> Bool {
    m.round == 2 && m.phase == .playing && m.turnCount == 0 && m.selection == nil
}

@MainActor
private func makeModel(seed: UInt64, scene: Moment) -> HanafudaModel? {
    let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
    let model = HanafudaModel(services: services, cpuDelay: .zero, seed: seed)
    model.startMatch(options: HanafudaOptions())
    let ok = autoplay(model) { scene == .mid ? isMid($0) : isStart($0) }
    return ok ? model : nil
}

@Suite("#2430 レイアウト検討モック（一時）")
struct LayoutMock2430Tests {
    private static var outDir: URL {
        let base = ProcessInfo.processInfo.environment["DUTY_SCRATCH_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: base).appendingPathComponent("mock2430", isDirectory: true)
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
        // 同じ種で「局の途中」と「配り直後」の両方が作れる種を使う（配りは種で決まる）。
        var seed: UInt64 = 2430
        var found: UInt64?
        while found == nil, seed < 2430 + 3000 {
            if makeModel(seed: seed, scene: .mid) != nil { found = seed }
            seed += 1
        }
        let useSeed = try #require(found, "局面が作れる種が見つからない")
        print("seed \(useSeed)")
        var all: [String: [String: Double]] = [:]
        all["seed"] = ["value": Double(useSeed)]
        for phone in phones {
            for scene in [Moment.mid, .start] {
                let model = try #require(makeModel(seed: useSeed, scene: scene))
                print("\(scene): round \(model.round) turn \(model.turn) hand \(model.humanHand.count) field \(model.field.count) " +
                      "captured \(model.humanCaptured.count)/\(model.cpuCaptured.count) deck \(model.deck.count) msg \(model.message)")
                let measure = Measure()
                let cur = "\(phone.name)_\(scene.rawValue)_cur", a = "\(phone.name)_\(scene.rawValue)_a"
                let view = SideBySide(
                    leftCaption: "今（v1.1.13・#2336 反映後）",
                    rightCaption: "A 全画面",
                    left: CurrentScreen(phone: phone, model: model, measure: measure, prefix: cur)
                        .coordinateSpace(name: "phone"),
                    right: FullScreenA(phone: phone, model: model, measure: measure, prefix: a)
                        .coordinateSpace(name: "phone")
                )
                try Self.write(view, scale: phone.scale, name: "\(phone.name)_hanafuda_\(scene.rawValue)_cur_vs_a.png")
                for (k, v) in measure.values {
                    let parts = k.split(separator: ".", maxSplits: 1).map(String.init)
                    all[parts[0], default: [:]][parts[1]] = v
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: Self.outDir.appendingPathComponent("measure_hanafuda.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
