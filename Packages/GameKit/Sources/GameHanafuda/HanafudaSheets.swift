import SwiftUI
import Core

// MARK: - 開始前の設定

/// 局数・酒の役・CPU の強さを選ぶシート（#495）。
///
/// **ここで選んだ値は試合の開始時に焼き込まれ、途中で変えられない**（1 局 = 1 RuleSet 原則）。
/// 月見酒・花見酒はローカルルールなので、採用するかを最初に決めさせる。
/// 見た目は他ゲームと同じ共通枠（`GameSetupSheet`・#527）に揃える。節が3つあるが、共通枠は常に `.large` で開くので収まる（#1415）。
public struct HanafudaSetupSheet: View {
    @Binding var draft: HanafudaOptions
    let onStart: () -> Void
    let onCancel: () -> Void

    public init(draft: Binding<HanafudaOptions>, onStart: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self._draft = draft
        self.onStart = onStart
        self.onCancel = onCancel
    }

    public var body: some View {
        GameSetupSheet(
            kind: .versus,
            onboarding: HanafudaOnboarding.guide,
            onStart: onStart, onCancel: onCancel
        ) {
            GameSetupSection(tr("何局戦うか")) {
                HStack(spacing: 12) {
                    ForEach(HanafudaOptions.allowedRounds, id: \.self) { count in
                        GameSetupChooser(title: tr("%lld局", count), subtitle: "",
                                          selected: draft.rounds == count,
                                          accent: Theme.Fill.purple) { draft.rounds = count }
                    }
                }
                Text(tr("全局が終わった時点で、合計の文数が多いほうの勝ちです。"))
                    .themeBody(12).foregroundStyle(Theme.inkSubText)
            }
            GameSetupSection(tr("CPUの強さ")) {
                HStack(spacing: 6) {
                    ForEach(Array(HanafudaDifficulty.allCases.enumerated()), id: \.element) { step, value in
                        difficultyTile(value, accent: DifficultyTile.accent(step: step, of: HanafudaDifficulty.allCases.count))
                    }
                }
                // 段を選び直してもシートが伸び縮みしないよう 1 行に固定する（`CPUStrengthPicker` と同じ）。
                Text(draft.difficulty.detail)
                    .themeBody(13).foregroundStyle(Theme.inkSubText)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GameSetupSection(tr("ローカルルール")) {
                Toggle(isOn: $draft.sakeYakuEnabled) {
                    Label(tr("月見酒・花見酒"), systemImage: "moon.stars")
                        .foregroundStyle(Theme.ink)
                }
                Text(tr("「芒に月＋菊に盃」「桜に幕＋菊に盃」を役として数えます。オフにすると菊に盃はタネ札としてだけ働きます。"))
                    .themeBody(12).foregroundStyle(Theme.inkSubText)
            }
        }
    }

    private func difficultyTile(_ value: HanafudaDifficulty, accent: Color) -> some View {
        GameSetupChooser(title: value.label, subtitle: "",
                          selected: draft.difficulty == value, accent: accent,
                          metrics: DifficultyTile.metrics) {
            draft.difficulty = value
        }
    }
}

// MARK: - 役の早見表

/// 対局中 1 タップで開ける役の早見表（#495 の仕様）。
///
/// 役は 12 種あり、覚えていないと「こいこいするか」を決められない。全役を 1 画面に
/// 収めて、成立条件と文数をその場で引けるようにする。
public struct HanafudaYakuSheet: View {
    let options: HanafudaOptions

    public init(options: HanafudaOptions) {
        self.options = options
    }

    public var body: some View {
        YakuTableSheet(title: tr("役の早見表"), standalone: true) {
            YakuTableSection(
                header: tr("出来役"),
                footer: options.sakeYakuEnabled
                    ? tr("この試合は月見酒・花見酒を採用しています。")
                    : tr("この試合は月見酒・花見酒を採用していません（灰色の行は数えません）。")
            ) {
                ForEach(HanafudaYaku.displayOrder, id: \.self) { yaku in
                    row(yaku)
                }
            }
            YakuTableSection(header: tr("倍率")) {
                labeled(tr("7文以上"), tr("合計が7文以上のとき2倍"))
                labeled(tr("こいこい返し"), tr("相手がこいこいを宣言したあとにあがると2倍"))
                labeled(tr("両方"), tr("重なると4倍（掛け算）"))
            }
        }
    }

    private func row(_ yaku: HanafudaYaku) -> some View {
        let isDisabled = !options.sakeYakuEnabled
            && (yaku == .tsukimizake || yaku == .hanamizake)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // 名前は短い名前（英語はローマ字だけ）。英語の説明は成立条件の文の頭に入れてある（#2166）。
                Text(yaku.shortName)
                    .scaledFont(15, weight: .bold, design: .rounded)
                    .foregroundStyle(isDisabled ? Theme.inkSubText : Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 6)
                Text(tr("%lld文", yaku.basePoints))
                    .scaledFont(14, weight: .heavy, design: .rounded)
                    .foregroundStyle(isDisabled ? Theme.inkSubText : Theme.coralText)
            }
            HanafudaYakuCardsFigure(figure: .init(yaku), isDisabled: isDisabled)
                // 札の絵は読み上げない。行の読み上げは下の accessibilityLabel（今までと同じ文）だけにする。
                .accessibilityHidden(true)
            Text(yaku.requirement)
                .scaledFont(13, design: .rounded)
                .foregroundStyle(Theme.inkSubText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isDisabled
            ? tr("%1$@。%2$@。%3$lld文。この試合では数えません", yaku.shortName, yaku.requirement, yaku.basePoints)
            : tr("%1$@。%2$@。%3$lld文", yaku.shortName, yaku.requirement, yaku.basePoints))
    }

    private func labeled(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .scaledFont(15, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.7)
                .frame(width: 96, alignment: .leading)
            Text(detail)
                .scaledFont(13, design: .rounded)
                .foregroundStyle(Theme.inkSubText)
        }
    }
}

// MARK: 早見表の札の絵

/// 早見表の 1 行に並べる札の絵（どの札で役になるか）。札そのものは盤面と同じ `HanafudaCardFace`。
struct HanafudaYakuFigure: Equatable {
    /// 並べる札。`isExcluded` は「この札は入らない」（四光・三光の柳。暗くして斜線）、`isKey` は「この札が要る」（雨四光の柳。枠で強調）。
    struct Slot: Equatable {
        let id: Int
        var isExcluded = false
        var isKey = false
    }

    let slots: [Slot]
    /// 札と札のあいだに「＋」を挟む（月見酒・花見酒の 2 枚組）。
    let joinsWithPlus: Bool
    /// 札の右（狭いときは下）に添える注記。
    let caption: String?
    /// 代表の札だけを並べたので「…」を添える（カスは 10 枚から）。
    let trailingEllipsis: Bool

    init(_ yaku: HanafudaYaku) {
        let deck = HanafudaCard.fullDeck
        let lights = deck.filter { $0.kind == .hikari }.map(\.id)
        let lightsWithoutRain = lights.filter { $0 != HanafudaCard.rainManID }
        var slots: [Slot] = []
        var joinsWithPlus = false
        var caption: String?
        var trailingEllipsis = false
        switch yaku {
        case .goko:
            slots = lights.map { Slot(id: $0) }
        case .shiko:
            slots = lightsWithoutRain.map { Slot(id: $0) } + [Slot(id: HanafudaCard.rainManID, isExcluded: true)]
            caption = tr("このうち4枚")
        case .ameShiko:
            slots = [Slot(id: HanafudaCard.rainManID, isKey: true)] + lightsWithoutRain.map { Slot(id: $0) }
            caption = tr("柳＋ほか3枚")
        case .sanko:
            slots = lightsWithoutRain.map { Slot(id: $0) } + [Slot(id: HanafudaCard.rainManID, isExcluded: true)]
            caption = tr("このうち3枚")
        case .inoshikacho:
            slots = [HanafudaCard.boarID, HanafudaCard.deerID, HanafudaCard.butterflyID].map { Slot(id: $0) }
        case .akatan:
            slots = deck.filter { $0.ribbon == .redPoem }.map { Slot(id: $0.id) }
        case .aotan:
            slots = deck.filter { $0.ribbon == .blue }.map { Slot(id: $0.id) }
        case .tsukimizake:
            slots = [HanafudaCard.moonID, HanafudaCard.sakeCupID].map { Slot(id: $0) }
            joinsWithPlus = true
        case .hanamizake:
            slots = [HanafudaCard.curtainID, HanafudaCard.sakeCupID].map { Slot(id: $0) }
            joinsWithPlus = true
        case .tane, .tan, .kasu:
            let kind: HanafudaKind = yaku == .tane ? .tane : (yaku == .tan ? .tanzaku : .kasu)
            // 代表の札は月がばらけるように選ぶ（同じ月の札が続くと「同じ月を集める役」に見える）。
            var picked: [Int] = []
            var months: Set<Int> = []
            for card in deck where card.kind == kind && !months.contains(card.month) {
                picked.append(card.id)
                months.insert(card.month)
            }
            let threshold = yaku.countThreshold ?? 0
            let shown = min(threshold, Self.maxCountSamples)
            // 短冊は赤短・青短・無地が混ざるよう、月を飛ばして拾う。
            let stride = yaku == .tan ? max(1, picked.count / shown) : 1
            slots = Swift.stride(from: 0, to: picked.count, by: stride).prefix(shown).map { Slot(id: picked[$0]) }
            trailingEllipsis = threshold > shown
            // 「1枚ごとに＋1文」は下の成立条件の文が言うので、ここは成立する枚数だけにする。
            caption = tr("%lld枚から", threshold)
        }
        self.slots = slots
        self.joinsWithPlus = joinsWithPlus
        self.caption = caption
        self.trailingEllipsis = trailingEllipsis
    }

    /// 枚数で決まる役に並べる代表の札の上限（SE の幅に収まる枚数）。
    static let maxCountSamples = 5
}

/// `HanafudaYakuFigure` を描く。札は固定幅で並べ、注記が横に入らない幅（SE・文字サイズ大）では札の下へ回す。
struct HanafudaYakuCardsFigure: View {
    let figure: HanafudaYakuFigure
    let isDisabled: Bool

    /// 札 1 枚の幅。5 枚と注記を並べても SE のカードの内側に収まる大きさ。
    static let cardWidth: CGFloat = 30

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                cards
                captionView
            }
            VStack(alignment: .leading, spacing: 4) {
                cards
                captionView
            }
        }
    }

    private var cards: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(figure.slots.enumerated()), id: \.offset) { index, slot in
                if index > 0 && figure.joinsWithPlus {
                    Text(verbatim: "＋")  // i18n-keep: 札をつなぐ記号（言語によらず同じ）
                        .scaledFont(14, weight: .heavy, design: .rounded)
                        .foregroundStyle(Theme.inkSubText)
                }
                card(slot)
            }
            if figure.trailingEllipsis {
                Text(verbatim: "…")
                    .scaledFont(14, weight: .heavy, design: .rounded)
                    .foregroundStyle(Theme.inkSubText)
            }
        }
        .fixedSize()
    }

    private func card(_ slot: HanafudaYakuFigure.Slot) -> some View {
        HanafudaCardFace(card: HanafudaCard(id: slot.id),
                         isDimmed: isDisabled || slot.isExcluded,
                         isHighlighted: slot.isKey && !isDisabled,
                         fixedWidth: Self.cardWidth)
            .overlay {
                if slot.isExcluded {
                    // 入らない札は暗くしたうえで斜線を引き、「この札は数えない」と分かるようにする。
                    // 札の大きさは固定なので GeometryReader を使わずに引く（#2905 と同じ作法）。
                    Path { path in
                        path.move(to: CGPoint(x: Self.cardWidth, y: 0))
                        path.addLine(to: CGPoint(x: 0, y: Self.cardWidth * HanafudaCardArt.aspectRatio))
                    }
                    .stroke(Theme.coral, lineWidth: 2)
                }
            }
    }

    @ViewBuilder
    private var captionView: some View {
        if let caption = figure.caption {
            Text(caption)
                .scaledFont(12, weight: .bold, design: .rounded)
                .foregroundStyle(isDisabled ? Theme.inkSubText : Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - くわしいルール

/// 遊び方ガイド（#118）から開く詳細ルール。3 行の要約に収まらない進行を説明する。
public struct HanafudaRuleSheet: View {
    public init() {}

    public var body: some View {
        RuleListSheet(rules: Self.sections.map { title, lines in
            (title, lines.map { tr("・%@", $0) }.joined(separator: "\n"))
        })
    }

    /// 表示言語で引くので `static let` にしない（起動時の言語で固まるため・#2166）。
    private static var sections: [(String, [String])] { [
        (tr("札の見かた"), [
            tr("札の上の帯に、左が月・右が種別（光・タネ・短・カス）を出しています。"),
            tr("合わせられるのは月が同じ札どうしです。"),
            tr("タネ・タン・カスの役は種別ごとの枚数で決まります。帯の色も種別に対応しています。"),
            tr("光・猪鹿蝶・赤短・青短は枚数だけでは決まりません。どの札がそろったかで変わるので、役の早見表で確かめてください。"),
            tr("短冊の帯は、赤短が赤・青短が青です。"),
        ]),
        (tr("進行"), [
            tr("手札8枚・場札8枚で始まります。親から順に打ちます。"),
            tr("手札を1枚出し、場の同じ月の札と合わせて取ります。合う札が無ければ場に置きます。"),
            tr("続けて山札を1枚めくり、同じように合わせます。ここまでで1手番です。"),
            tr("場に同じ月が3枚あるときは、4枚まとめて取れます。"),
        ]),
        (tr("こいこい"), [
            tr("役ができたら「あがり」か「こいこい」を選びます。"),
            tr("あがるとその場で得点が確定し、局が終わります。"),
            tr("こいこいを選ぶと局が続き、役を伸ばせます。ただし相手にあがられると相手の得点が2倍になります。"),
            tr("こいこいのあとは、宣言したときより文数が増えないとあがれません。"),
        ]),
        (tr("得点"), [
            tr("合計が7文以上のとき2倍になります。"),
            tr("相手のこいこいのあとにあがると2倍（両方重なると4倍）。"),
            tr("だれもあがれずに手札が尽きたら流局で、その局は0文です。"),
            tr("あがった人が次の局の親になります。流局のときは親が続きます。"),
        ]),
    ] }
}
