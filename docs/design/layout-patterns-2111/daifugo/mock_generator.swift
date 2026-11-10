// #2431 のレイアウト検討モック（大富豪・今 vs A）の生成器。**アプリのコードではない**（docs に置くだけ）。
// 使い方: このファイルを `Packages/GameKit/Tests/GameDaifugoTests/` にコピーし、
//   DUTY_SCRATCH_DIR=<出力先> swift test --package-path Packages/GameKit --filter LayoutMock2431
// で `<出力先>/mock2431/` に PNG 4 枚（2 局面 × 2 端末）と寸法の JSON が出る（シミュレータ不要。macOS の ImageRenderer で描く）。
// 「今」は `DaifugoView.body` の写し（実物の `DaifugoCardView`・`GameStatusBar`・`TurnBadge`・`GameButtonStyle`・`popCard` を
// そのまま使い、ナビバー・ステータスバー・バナーだけ見た目を写して描く）。A は同じ中身を全画面の卓（フェルト）に
// 置き直し、手札を 7 列の列幅いっぱいに拡大したもの。局面は中断データ（`DaifugoSnapshot`）を流し込んで作る
// （`lastActions` まで入るので CPU の席の「直近の動き」も写る）。#2427〜#2429 の生成器と同じ型。
// 終わったらコピーは消す（コミットしない）。
import Foundation
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
import Core
import CoreTestSupport
@testable import GameDaifugo

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

/// A の寸法。手札は 7 列（`DaifugoHandLayout.columns`）のまま、列幅いっぱいまで札を大きくする。
private enum LayoutA {
    /// 画面の左右の余白（卓の縁から中身まで）。
    static let sideInset: CGFloat = 8
    /// 手札の列のあいだに残す隙間（札の幅 = 列幅 − これ）。
    static let handGap: CGFloat = 4
    /// 手札の札の寸法（`.compact` 42×60 を列幅から相似拡大）。
    static func handMetrics(width: CGFloat) -> PlayingCardMetrics {
        let column = width / CGFloat(DaifugoHandLayout.columns)
        return PlayingCardMetrics.compact.scaled(by: (column - handGap) / PlayingCardMetrics.compact.width)
    }
    /// 場の札の寸法（`.medium` 56×78 を手札と同じ倍率で拡大）。
    static func fieldMetrics(width: CGFloat) -> PlayingCardMetrics {
        PlayingCardMetrics.medium.scaled(by: handMetrics(width: width).width / PlayingCardMetrics.compact.width)
    }
}

// MARK: - 札（A 用。`DaifugoCardView` と同じ描き方で寸法だけ受け取る）

private struct ScaledCard: View {
    let card: DaifugoCard
    let metrics: PlayingCardMetrics
    var selected = false
    var hint: DaifugoCardHint = .none

    private var isDimmed: Bool { hint == .unplayable && !selected }
    private var borderColor: Color {
        if selected { return Theme.coral }
        if hint == .playable { return Theme.teal }
        return Color.gray.opacity(0.2)
    }
    private var borderWidth: CGFloat {
        if selected { return 2 }
        return hint == .playable ? 1.5 : 0.5
    }

    var body: some View {
        ZStack {
            PlayingCardSurface(
                cornerRadius: metrics.cornerRadius,
                border: borderColor,
                borderWidth: borderWidth,
                shadowColor: selected ? Theme.coral.opacity(0.6) : .black.opacity(0.15),
                shadowRadius: selected ? 6 : 3
            )
            PlayingCardFace(figure: card.figure, metrics: metrics)
        }
        .frame(width: metrics.width, height: metrics.height)
        .opacity(isDimmed ? 0.4 : 1)
    }
}

// MARK: - 共通部品（ヘッダー・バナー）

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

/// iOS 26 の「戻る ＋ ゲーム名 ＋ 右のアイコン」。大富豪のヘッダー右は「？」だけ（役の早見表・新規ボタンは無い）。
private struct NavHeader: View {
    let title: String
    let onFelt: Bool
    var body: some View {
        HStack(spacing: 8) {
            GlassCircle { Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.coral) }
            Spacer(minLength: 0)
            Text(title)
                .themeBody(20, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(onFelt ? Color.white : Theme.ink)
                .shadow(color: onFelt ? .black.opacity(0.35) : .clear, radius: 2, y: 1)
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

// MARK: - 中身（今と A で共有する部品。`DaifugoView` の写し）

/// CPU の席・場のラベルが文字サイズ設定で拡大する上限倍率（`DaifugoView.seatTextMaxScale`）。
private let seatTextMaxScale: CGFloat = 1.6

/// 手番の文言・色（`DaifugoView.turnLabel` / `turnKind`）。
@MainActor
private func turnBadge(_ model: DaifugoModel) -> TurnBadge {
    switch model.phase {
    case .idle:    return TurnBadge(tr("開始待ち"), kind: .finished)
    case .result:  return TurnBadge(tr("決着"), kind: .finished)
    case .playing:
        return model.isPlayerTurn
            ? TurnBadge(tr("あなたの番"), kind: .you)
            : TurnBadge(tr("%@の番", model.playerName(model.currentPlayer)), kind: .cpu)
    }
}

/// ステータスの左側（ゲーム数・革命中）。
private struct GameCountLabel: View {
    let model: DaifugoModel
    let onFelt: Bool
    var body: some View {
        Label(tr("%lldゲーム目", max(model.gameNumber, 1)), systemImage: "number")
            .themeBody(13)
            .foregroundStyle(Theme.inkSub)
        if model.isRevolution {
            Text(tr("革命中"))
                .scaledFont(12, weight: .black, design: .rounded)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.Fill.coral))
        }
    }
}

/// CPU 3 人の席（`DaifugoView.cpuRow` / `cpuCard` の写し）。今も A も同じ。
private struct CPURow: View {
    let model: DaifugoModel
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1..<DaifugoModel.playerCount, id: \.self) { index in
                seat(index)
            }
        }
    }

    private func seat(_ index: Int) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .themeCaption(12, maxScale: seatTextMaxScale)
                    .foregroundStyle(model.currentPlayer == index && model.phase == .playing ? Theme.coral : Theme.inkSub)
                Text(model.playerName(index))
                    .themeCaption(12, maxScale: seatTextMaxScale)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Text(tr("残り%lld枚", model.hands[index].count))
                .themeCaption(11, weight: .semibold, maxScale: seatTextMaxScale)
                .foregroundStyle(Theme.inkSub)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(model.lastActions[index].isEmpty ? " " : model.actionLabel(index))
                .themeCaption(10, maxScale: seatTextMaxScale)
                .foregroundStyle(Theme.onAccent)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(model.lastActions[index].isEmpty ? Color.clear : Theme.Fill.purple))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10).padding(.horizontal, 6)
        .popCard(corner: Theme.cornerSmall)
    }
}

/// 場の見出し（`DaifugoView.fieldHeader` の写し）。フェルトの上では地の文を白にする。
private struct FieldHeader: View {
    let model: DaifugoModel
    let onFelt: Bool

    private var fieldOwnerName: String? {
        guard !model.field.isEmpty, let owner = model.fieldOwner else { return nil }
        return model.playerName(owner)
    }

    var body: some View {
        if let ownerName = fieldOwnerName {
            let isHuman = model.fieldOwner == DaifugoModel.humanIndex
            HStack(spacing: 4) {
                Image(systemName: isHuman ? "person.fill" : "cpu")
                    .themeCaption(10, maxScale: seatTextMaxScale)
                Text(isHuman ? tr("あなたが出した") : tr("%@が出した", ownerName))
                    .themeCaption(11, maxScale: seatTextMaxScale)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(isHuman ? Theme.Fill.teal : Theme.Fill.purple))
        } else {
            Text(model.field.isEmpty ? tr("場は流れています（好きな組を出せます）") : tr("場"))
                .themeCaption(11, weight: .semibold, maxScale: seatTextMaxScale)
                .foregroundStyle(onFelt ? Color.white.opacity(0.9) : Theme.inkSub)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

/// 手札の見出し（「あなた（残りN枚）」と直近の動き）。
private struct HandHeader: View {
    let model: DaifugoModel
    let onFelt: Bool
    var body: some View {
        HStack {
            Text(tr("あなた（残り%lld枚）", model.playerHand.count))
                .themeBody(13)
                .foregroundStyle(onFelt ? Color.white : Theme.ink)
            Spacer()
            if !model.lastActions[DaifugoModel.humanIndex].isEmpty {
                Text(model.actionLabel(DaifugoModel.humanIndex))
                    .scaledFont(11, weight: .bold, design: .rounded)
                    .foregroundStyle(onFelt ? Color.white : Theme.tealText)
            }
        }
    }
}

/// 手札の下の 1 行の案内（`DaifugoView.hintLine` の写し）。
private struct HintLine: View {
    let model: DaifugoModel
    let handHint: DaifugoHandHint?
    let onFelt: Bool
    var body: some View {
        let message = model.selectionIssue
            ?? (handHint?.playable.isEmpty == true ? tr("出せる組がありません。パスしてください") : nil)
        if let message {
            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill").scaledFont(11, weight: .bold)
                Text(message).scaledFont(11, weight: .bold, design: .rounded).lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(onFelt ? Color.white : Theme.coralText)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 役割で色が決まる横いっぱいのボタン（`DaifugoView.actionButton` の写し）。
@MainActor
private func actionButton(_ title: String, role: GameButtonRole, disabled: Bool) -> some View {
    Button {} label: {
        Text(title).themeBody(14).lineLimit(1).minimumScaleFactor(0.6)
    }
    .buttonStyle(GameButtonStyle(role: role, shape: .block))
    .disabled(disabled)
}

@MainActor
private func playButtonTitle(_ model: DaifugoModel) -> String {
    model.selected.isEmpty ? tr("カードを選ぶ") : tr("%lld枚出す", model.selected.count)
}

/// 対局中の操作（パス・出す・⋯）。`Menu` は macOS で見た目が変わるので「⋯」だけ自前で描く（幅 44・縦 8 は同じ）。
private struct ActionButtons: View {
    let model: DaifugoModel
    let onFelt: Bool
    var body: some View {
        HStack(spacing: 12) {
            actionButton(tr("パス"), role: .skip, disabled: !model.canPass)
            actionButton(playButtonTitle(model), role: .primary, disabled: !model.canPlaySelection)
            Image(systemName: "ellipsis.circle")
                .scaledFont(17, weight: .semibold)
                .foregroundStyle(onFelt ? Color.white : Theme.coral)
                .frame(width: 44)
                .padding(.vertical, 8)
        }
    }
}

// MARK: - 今の画面（DaifugoView.body の写し）

private struct CurrentScreen: View {
    let phone: Phone
    let model: DaifugoModel
    let measure: Measure
    let prefix: String

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone, onFelt: false)
                NavHeader(title: daifugoGameName(), onFelt: false)
                content
                    .padding(Theme.pad)
                    .background(FrameProbe(measure: measure, prefix: prefix, key: "content"))
                Color.clear.frame(height: phone.safeBottom)
            }
        }
        .frame(width: phone.width, height: phone.height)
        .clipped()
    }

    private var content: some View {
        let handHint = model.handHint
        let handMetrics = DaifugoCardView.Size.small.metrics
        let fieldMetrics = DaifugoCardView.Size.large.metrics
        let _ = {
            measure.set("\(prefix).avail_top_pt", phone.safeTop + Phone.navBarHeight)
            measure.set("\(prefix).avail_bottom_pt", phone.height - phone.safeBottom)
            measure.set("\(prefix).hand_card_w_pt", handMetrics.width)
            measure.set("\(prefix).hand_card_h_pt", handMetrics.height)
            measure.set("\(prefix).hand_col_w_pt", DaifugoHandLayout.tapWidth(screenWidth: phone.width))
            measure.set("\(prefix).field_card_w_pt", fieldMetrics.width)
            measure.set("\(prefix).field_card_h_pt", fieldMetrics.height)
        }()
        return VStack(spacing: 8) {
            GameStatusBar {
                GameCountLabel(model: model, onFelt: false)
            } trailing: {
                turnBadge(model)
            }
            .background(FrameProbe(measure: measure, prefix: prefix, key: "status"))
            CPURow(model: model)
                .background(FrameProbe(measure: measure, prefix: prefix, key: "seats"))
            // 場（`fieldArea`）。縦の余りをここで吸う（#193）。
            VStack(spacing: 6) {
                FieldHeader(model: model, onFelt: false)
                HStack(spacing: 6) {
                    if model.field.isEmpty {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.inkSub.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .frame(width: 56, height: 78)
                    } else {
                        ForEach(model.field) { card in
                            DaifugoCardView(card: card, size: .large)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 22)
            .popCard(corner: Theme.cornerSmall)
            .background(FrameProbe(measure: measure, prefix: prefix, key: "field"))
            // 手札（`handArea`）。
            VStack(spacing: 6) {
                HandHeader(model: model, onFelt: false)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: DaifugoHandLayout.columnSpacing),
                                   count: DaifugoHandLayout.columns),
                    spacing: DaifugoHandLayout.rowSpacing
                ) {
                    ForEach(model.playerHand) { card in
                        let isSelected = model.selected.contains(card.id)
                        DaifugoCardView(card: card, size: .small, selected: isSelected,
                                        hint: handHint?.state(for: card.id) ?? .none)
                            .offset(y: isSelected ? -6 : 0)
                            .frame(maxWidth: .infinity, minHeight: DaifugoHandLayout.minimumTapTarget)
                    }
                }
                .background(FrameProbe(measure: measure, prefix: prefix, key: "hand_grid"))
                HintLine(model: model, handHint: handHint, onFelt: false)
            }
            .padding(.horizontal, DaifugoHandLayout.horizontalPadding).padding(.vertical, 12)
            .popCard(corner: Theme.cornerSmall)
            .background(FrameProbe(measure: measure, prefix: prefix, key: "hand"))
            // HowToPlayHint は初回だけ出る（2 回目以降は無い）ので描かない。
            ActionButtons(model: model, onFelt: false)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .popCard(corner: Theme.cornerSmall)
                .background(FrameProbe(measure: measure, prefix: prefix, key: "actions"))
            // RecommendationSlot は対局中は何も出さない。
            BannerPlaceholder()
                .background(FrameProbe(measure: measure, prefix: prefix, key: "banner"))
        }
    }
}

// MARK: - A（全画面の卓）

private struct FullScreenA: View {
    let phone: Phone
    let model: DaifugoModel
    let measure: Measure
    let prefix: String

    /// 木枠なし・角丸なしのフェルトだけ（画面全体を卓にする）。
    private static let feltOnly = CardTableFrame(
        top: .points(0), leading: .points(0), bottom: .points(0), trailing: .points(0),
        innerShadow: nil, aspectRatio: nil, cornerRadius: 0, dropShadow: false)

    var body: some View {
        let bannerBand = BannerSlot.height + 8 + phone.safeBottom
        let width = phone.width - LayoutA.sideInset * 2
        let handMetrics = LayoutA.handMetrics(width: width)
        let fieldMetrics = LayoutA.fieldMetrics(width: width)
        let handHint = model.handHint
        let _ = {
            measure.set("\(prefix).felt_w_pt", phone.width)
            measure.set("\(prefix).felt_h_pt", phone.height - bannerBand)
            measure.set("\(prefix).avail_top_pt", phone.safeTop + Phone.navBarHeight)
            measure.set("\(prefix).avail_bottom_pt", phone.height - bannerBand)
            measure.set("\(prefix).hand_card_w_pt", handMetrics.width)
            measure.set("\(prefix).hand_card_h_pt", handMetrics.height)
            measure.set("\(prefix).hand_col_w_pt", width / CGFloat(DaifugoHandLayout.columns))
            measure.set("\(prefix).field_card_w_pt", fieldMetrics.width)
            measure.set("\(prefix).field_card_h_pt", fieldMetrics.height)
        }()
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                CardTableSurface(frame: Self.feltOnly)
                // 画面最下部のバナー（会長の方針: A のバナーは下）。地の色の帯に置く。
                VStack(spacing: 0) {
                    BannerPlaceholder().padding(.horizontal, Theme.pad).padding(.top, 8)
                        .background(FrameProbe(measure: measure, prefix: prefix, key: "banner"))
                    Color.clear.frame(height: phone.safeBottom)
                }
            }
            VStack(spacing: 0) {
                StatusStrip(phone: phone, onFelt: true)
                NavHeader(title: daifugoGameName(), onFelt: true)
                VStack(spacing: 8) {
                    // ゲーム数・革命中・手番は 1 行の札にまとめる（今の 44pt の帯より低い）。
                    HStack(spacing: 8) {
                        GameCountLabel(model: model, onFelt: true)
                        Spacer(minLength: 8)
                        turnBadge(model)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .popCard(corner: 10)
                    .background(FrameProbe(measure: measure, prefix: prefix, key: "status"))
                    CPURow(model: model)
                        .background(FrameProbe(measure: measure, prefix: prefix, key: "seats"))
                    // 場はフェルトに直に置く（札だけ。見出しは上）。縦の余りはここが吸う。
                    VStack(spacing: 6) {
                        FieldHeader(model: model, onFelt: true)
                        HStack(spacing: 6) {
                            if model.field.isEmpty {
                                RoundedRectangle(cornerRadius: fieldMetrics.cornerRadius + 2, style: .continuous)
                                    .strokeBorder(Color.white.opacity(CardTableStyle.feltSlotAlpha),
                                                  style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                    .frame(width: fieldMetrics.width, height: fieldMetrics.height)
                            } else {
                                ForEach(model.field) { card in
                                    ScaledCard(card: card, metrics: fieldMetrics)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(FrameProbe(measure: measure, prefix: prefix, key: "field"))
                    // 手札もフェルトに直に置く。7 列は今と同じで、札を列幅いっぱいまで大きくする。
                    VStack(spacing: 6) {
                        HandHeader(model: model, onFelt: true)
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 0),
                                           count: DaifugoHandLayout.columns),
                            spacing: DaifugoHandLayout.rowSpacing
                        ) {
                            ForEach(model.playerHand) { card in
                                let isSelected = model.selected.contains(card.id)
                                ScaledCard(card: card, metrics: handMetrics, selected: isSelected,
                                           hint: handHint?.state(for: card.id) ?? .none)
                                    .offset(y: isSelected ? -6 : 0)
                                    .frame(maxWidth: .infinity, minHeight: DaifugoHandLayout.minimumTapTarget)
                            }
                        }
                        .background(FrameProbe(measure: measure, prefix: prefix, key: "hand_grid"))
                        HintLine(model: model, handHint: handHint, onFelt: true)
                    }
                    .background(FrameProbe(measure: measure, prefix: prefix, key: "hand"))
                    ActionButtons(model: model, onFelt: true)
                        .padding(.horizontal, 8)
                        .background(FrameProbe(measure: measure, prefix: prefix, key: "actions"))
                }
                .padding(.horizontal, LayoutA.sideInset)
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

// MARK: - 局面

private enum Situation: String, CaseIterable {
    /// 2 ゲーム目の途中: 場に CPU2 の 9 のペア、手札 8 枚、J のペアを選んで「2枚出す」が押せる。
    case mid
    /// 配った直後: 手札 14 枚（7 列 × 2 段）、場は流れている。人間が ♦3 を持っていて親（1 ゲーム目の最初の手番）。
    case deal
}

private func card(_ suit: DaifugoSuit?, _ rank: Int) -> DaifugoCard {
    guard let suit else { return DaifugoCard(id: 52, suit: nil, rank: DaifugoRules.jokerRank) }
    return DaifugoCard(id: suit.rawValue * 13 + rank - 1, suit: suit, rank: rank)
}

@Suite("#2431 レイアウト検討モック（一時）")
struct LayoutMock2431Tests {
    private static var outDir: URL {
        let base = ProcessInfo.processInfo.environment["DUTY_SCRATCH_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: base).appendingPathComponent("mock2431", isDirectory: true)
    }

    /// 中断データを流し込んで局面を作る（`lastActions` まで入るので席の「直近の動き」も写る）。
    @MainActor
    private static func makeModel(_ scene: Situation) throws -> DaifugoModel {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let snapshot: DaifugoSnapshot
        var selected: [DaifugoCard] = []
        switch scene {
        case .mid:
            let human = [card(.spades, 3), card(.hearts, 5), card(.diamonds, 7), card(.clubs, 10),
                         card(.spades, 11), card(.hearts, 11), card(.diamonds, 13), card(.clubs, 2)]
            let cpu1 = [card(.spades, 4), card(.hearts, 6), card(.diamonds, 8), card(.clubs, 12), card(.spades, 1), card(nil, 0)]
            let cpu2 = [card(.hearts, 3), card(.diamonds, 4), card(.clubs, 6), card(.spades, 7), card(.hearts, 8),
                        card(.spades, 10), card(.diamonds, 12), card(.spades, 13), card(.hearts, 1)]
            let cpu3 = [card(.diamonds, 5), card(.clubs, 9), card(.hearts, 12), card(.spades, 2)]
            snapshot = DaifugoSnapshot(
                hands: [human, cpu1, cpu2, cpu3].map { $0.sorted { $0.sortKey < $1.sortKey } },
                field: [card(.spades, 9), card(.hearts, 9)], fieldOwner: 2,
                currentPlayer: DaifugoModel.humanIndex, passedPlayers: [3], isRevolution: false,
                finishOrder: [], fouls: [], gameNumber: 2, lastRanking: [1, 0, 3, 2],
                lastActions: ["5", "6", "9 9", "パス"])
            selected = [card(.spades, 11), card(.hearts, 11)]
        case .deal:
            // 1 ゲーム目の親は ♦3 の持ち主（`DaifugoModel.openingPlayer()`）。人間が親になる配りを、
            // 2431 から順に試して最初に見つかった種で固定する（人間は最初に配られるので常に 14 枚）。
            var hands: [[DaifugoCard]] = []
            var seed: UInt64 = 2431
            while true {
                var rng = SeededGenerator(seed: seed)
                let deck = DaifugoCard.makeDeck().shuffled(using: &rng)
                hands = Array(repeating: [DaifugoCard](), count: DaifugoModel.playerCount)
                for (i, c) in deck.enumerated() { hands[i % DaifugoModel.playerCount].append(c) }
                if hands[DaifugoModel.humanIndex].contains(card(.diamonds, 3)) { break }
                seed += 1
            }
            print("deal seed: \(seed)")
            snapshot = DaifugoSnapshot(
                hands: hands.map { $0.sorted { $0.sortKey < $1.sortKey } },
                field: [], fieldOwner: nil,
                currentPlayer: DaifugoModel.humanIndex, passedPlayers: [], isRevolution: false,
                finishOrder: [], fouls: [], gameNumber: 1, lastRanking: [],
                lastActions: ["", "", "", ""])
        }
        try store.save(snapshot, for: "daifugo")
        let model = DaifugoModel(services: services)
        #expect(model.phase == .playing)
        for c in selected { model.toggleSelection(c) }
        return model
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
                let model = try Self.makeModel(scene)
                #expect(model.playerHand.count >= (scene == .deal ? 13 : 8))
                let measure = Measure()
                let cur = "\(phone.name)_\(scene.rawValue)_cur", a = "\(phone.name)_\(scene.rawValue)_a"
                let view = SideBySide(
                    leftCaption: "今",
                    rightCaption: "A 全画面",
                    left: CurrentScreen(phone: phone, model: model, measure: measure, prefix: cur)
                        .coordinateSpace(name: "phone"),
                    right: FullScreenA(phone: phone, model: model, measure: measure, prefix: a)
                        .coordinateSpace(name: "phone")
                )
                try Self.write(view, scale: phone.scale, name: "\(phone.name)_daifugo_\(scene.rawValue)_cur_vs_a.png")
                for (k, v) in measure.values {
                    let parts = k.split(separator: ".", maxSplits: 1).map(String.init)
                    all[parts[0], default: [:]][parts[1]] = v
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: Self.outDir.appendingPathComponent("measure_daifugo.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
