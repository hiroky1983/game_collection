import SwiftUI
import Core

/// サイコロ役づくり（#1752）のプレイ画面。上に得点表、下にサイコロ 5 個と「振る」。
///
/// 1 ターンの流れ: 「振る」→ 残したい目をタップでキープ →（あと 2 回まで振り直し）→ 得点表の役をタップで記入。
public struct DiceComboView: View {
    private let services: GameServices
    @State private var model: DiceComboModel
    @State private var showConfirmReset = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: DiceComboModel(services: services, rollInterval: DiceComboMotion.rollInterval))
    }

    public var body: some View {
        VStack(spacing: 10) {
            header
            scoreSheet
                .layoutPriority(1)
                .overlay {
                    // 結果はフェードで出す。修飾子は 1 つのビューに 1 つだけ（入れ子にすると打ち消し合う・#199）。
                    ZStack {
                        if model.isFinished {
                            resultOverlay
                                .transition(.opacity)
                        }
                    }
                    .gameAnimation(.easeOut(duration: 0.25), value: model.isFinished)
                }
            diceRow
            rollButton
            // 初回だけ出す 1 行（以降は `?` ボタンからいつでも読める）。
            HowToPlayHint(.diceCombo, playLog: services.playLog)
            RecommendationArea(services: services, isFinished: model.isFinished)
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .padding()
        .gameChrome(title: tr("サイコロ役づくり"), review: services.review,
                    newGame: GameChromeNewGame(.solo) {
                        if model.hasProgressToLose {
                            showConfirmReset = true
                        } else {
                            withGameAnimation { model.newGame() }
                        }
                    })
        .howToPlay(HowToPlayGuide.diceCombo.illustrated(DiceComboHowToFigures.items))
        .dialogs { anchor in
            anchor.confirmationDialog(tr("新規ゲームを始めますか？"), isPresented: $showConfirmReset, titleVisibility: .visible) {
                Button(tr("終了して新規ゲーム"), role: .destructive) { withGameAnimation { model.newGame() } }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("途中で終了すると、いまの得点表が失われます。"))
            }
        }
        .task {
            #if DEBUG
            // 撮影・動作確認用: `-dicecomboScenario rolled|late|result` で局面を差し替える。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-dicecomboScenario"), i + 1 < args.count {
                model.applyDebugScenario(args[i + 1])
            }
            #endif
        }
    }

    // MARK: - ヘッダー

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("ターン"))
                    .scaledFont(12, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.inkSub)
                Text(verbatim: "\(model.turn) / \(DiceComboCategory.allCases.count)")
                    .scaledFont(22, weight: .heavy, design: .rounded, maxScale: 1.2).monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tr("%1$lldターン目、全%2$lldターン", model.turn, DiceComboCategory.allCases.count))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(tr("合計"))
                    .scaledFont(12, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.inkSub)
                Text(verbatim: "\(model.total)")
                    .scaledFont(30, weight: .heavy, design: .rounded, maxScale: 1.2).monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tr("合計%lld点", model.total))
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - 得点表

    /// 左に上段（1〜6 の目・小計・ボーナス）、右に下段（6 役）。
    private var scoreSheet: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 4) {
                ForEach(DiceComboCategory.upper, id: \.self) { row($0) }
                bonusRow
            }
            VStack(spacing: 4) {
                ForEach(Self.lower, id: \.self) { row($0) }
            }
        }
        .padding(8)
        .popCard(corner: Theme.cornerSmall)
    }

    private static let lower: [DiceComboCategory] = [
        .choice, .fourDice, .fullHouse, .smallStraight, .bigStraight, .fiveDice,
    ]

    private func row(_ category: DiceComboCategory) -> some View {
        let scored = model.scores[category]
        let preview = model.preview(category)
        return Button {
            withGameAnimation { model.choose(category) }
        } label: {
            DiceComboScoreRow(
                name: DiceComboText.name(category),
                rule: DiceComboText.rule(category),
                scored: scored,
                preview: preview,
                isJustFilled: model.lastFilled == category
            )
        }
        .buttonStyle(.plain)
        .disabled(!model.canChoose(category))
        .accessibilityLabel(DiceComboAccessibility.categoryLabel(category, scored: scored, preview: preview))
        .accessibilityHint(preview != nil ? tr("この役に点を入れます") : "")
    }

    /// 上段の小計とボーナス（63 点以上で +35）。
    private var bonusRow: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(tr("ボーナス"))
                    .scaledFont(13, weight: .bold, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.ink)
                Text(tr("小計 %1$lld / %2$lld", model.upperSubtotal, DiceComboLogic.upperBonusThreshold))
                    .scaledFont(10, weight: .semibold, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.inkSub)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            Text(verbatim: model.bonus > 0 ? "+\(model.bonus)" : "0")
                .scaledFont(17, weight: .heavy, design: .rounded, maxScale: 1.15).monospacedDigit()
                .foregroundStyle(model.bonus > 0 ? Theme.coral : Theme.inkSub)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: DiceComboScoreRow.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("ボーナス%1$lld点、上段の小計%2$lld、%3$lld点以上で%4$lld点",
                               model.bonus, model.upperSubtotal,
                               DiceComboLogic.upperBonusThreshold, DiceComboLogic.upperBonus))
    }

    // MARK: - サイコロ

    /// 振ると、キープしていないサイコロが目をパラパラ変えながら跳ねて立体に転がり、止まる（#2365・#2389）。
    /// 出目は Model が振った瞬間に確定済みで、ここは止まるまで途中の目を描くだけ。
    /// 「視差効果を減らす」がオンなら跳ねる・転がるは止め、目の切り替えだけにする。
    private var diceRow: some View {
        TimelineView(AnimationTimelineSchedule(minimumInterval: DiceComboMotion.flickerStep, paused: !model.isRolling)) { timeline in
            diceButtons(tick: DiceComboMotion.tick(at: timeline.date))
        }
        .onChange(of: model.isRolling) { wasRolling, isRolling in
            // 止まってから目を読み上げる（転がっている途中の目は読まない）。
            guard wasRolling, !isRolling, !model.dice.isEmpty else { return }
            AccessibilityNotification.Announcement(
                DiceComboAccessibility.diceLabel(dice: model.dice, held: model.held)
            ).post()
        }
    }

    private func diceButtons(tick: Int) -> some View {
        HStack(spacing: 10) {
            ForEach(0..<DiceComboLogic.diceCount, id: \.self) { index in
                let value = model.dice.indices.contains(index) ? model.dice[index] : nil
                let isHeld = model.held.indices.contains(index) && model.held[index]
                let shown = DiceComboMotion.displayedFace(final: value, isRolling: model.isRolling,
                                                          isHeld: isHeld, index: index, tick: tick)
                let tumbles = !isHeld && !reduceMotion && value != nil  // 転がり中に新しいゲームにしたら振る前の目は跳ねない
                Button {
                    model.toggleHold(index)
                } label: {
                    VStack(spacing: 3) {
                        // 転がる向きはキーフレームの値から毎コマ描く（`KeyframeAnimator` は値を中身へ渡せる形）。
                        KeyframeAnimator(initialValue: DiceComboTumble(), trigger: model.rollSerial) { tumble in
                            // まだ振っていなければ固定の目を薄く出す（役の計算には使わない・#2389）。
                            DiceComboDieFace(value: shown ?? DiceComboMotion.idleFace(index: index),
                                             isHeld: isHeld, isUnrolled: value == nil,
                                             rotation: tumbles
                                                ? tumble.rotation(direction: DiceComboMotion.spinDirection(index: index))
                                                : .identity)
                                // 目の切り替えは補間しない（ばねが掛かると点が滑って見える）。動かすのは傾き・跳ね・転がりだけ。
                                .transaction { $0.animation = nil }
                                // 止まったあとの少しの傾き。転がっている間は 0 にして、止まるときにばねで傾ける。
                                .rotationEffect(.degrees(isHeld || value == nil || model.isRolling
                                    ? 0 : Double((model.rollSerial * 37 + index * 53) % 21 - 10)))
                                .offset(y: tumbles ? tumble.lift : 0)
                        } keyframes: { _ in
                            DiceComboMotion.tumbleKeyframes()
                        }
                        Text(tr("キープ"))
                            .scaledFont(10, weight: .black, design: .rounded, maxScale: 1.1)
                            .foregroundStyle(Theme.coralText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .opacity(isHeld ? 1 : 0)
                    }
                }
                .buttonStyle(.plain)
                // 転がっている間は押しても何も起きない（Model が弾く）が、見た目は薄くしない（0.8 秒ごとに点滅して見えるため）。
                .disabled(!model.canHold && !model.isRolling)
                // 読み上げは常に確定した目（`value`）。途中の目（`shown`）は読まない。
                .accessibilityLabel(value.map { DiceComboAccessibility.dieLabel(index: index, value: $0, isHeld: isHeld) }
                    ?? tr("サイコロ%lld、まだ振っていません", index + 1))
                .accessibilityHint(model.canHold ? tr("タップでキープを切り替えます") : "")
            }
        }
        .frame(maxWidth: 360)
        .gameAnimation(.spring(response: 0.3, dampingFraction: 0.6), value: model.rollSerial)
        .gameAnimation(.spring(response: 0.3, dampingFraction: 0.6), value: model.isRolling)
        .accessibilityElement(children: .contain)
    }

    private var rollButton: some View {
        Button {
            withGameAnimation { model.roll() }
        } label: {
            Label(rollTitle, systemImage: "dice.fill")
                .scaledFont(17, weight: .heavy, design: .rounded, maxScale: 1.2)
        }
        .buttonStyle(.game(.primary, shape: .block))
        // 転がっている間の連打は Model が黙って捨てる。ボタンは薄くしない（振るたびに点滅して見えるため）。
        .disabled(!model.canRoll && !model.isRolling)
        .accessibilityLabel(DiceComboAccessibility.rollLabel(remaining: model.rollsRemaining))
    }

    private var rollTitle: String {
        if model.rollsUsed == 0 { return tr("振る") }
        if model.canRoll { return tr("振り直す（あと%lld回）", model.rollsRemaining) }
        return tr("役を選んでください")
    }

    // MARK: - 結果

    private var resultOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous).fill(.black.opacity(0.6))
            VStack(spacing: 12) {
                Text(tr("ゲーム終了")).font(.title2.bold()).foregroundStyle(.white)
                Text(tr("合計%lld点", model.total))
                    .scaledFont(28, weight: .heavy, design: .rounded, maxScale: 1.2)
                    .foregroundStyle(.white)
                RecordLabel(model.recordResult, textColor: .white.opacity(0.85))
                Button(tr("もう一度")) { withGameAnimation { model.newGame() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Fill.coral)
            }
            .padding()
        }
    }
}

/// 得点表の 1 行。記入済みは濃く、入れられる役はいまの出目での点を差し色で出す。
struct DiceComboScoreRow: View {
    static let height: CGFloat = 40

    let name: String
    let rule: String
    let scored: Int?
    let preview: Int?
    var isJustFilled = false

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .scaledFont(13, weight: .bold, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.ink)
                Text(rule)
                    .scaledFont(9, weight: .semibold, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.inkSub)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Spacer(minLength: 2)
            valueText
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: Self.height)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous)
                .fill(background)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var valueText: some View {
        if let scored {
            Text(verbatim: "\(scored)")
                .scaledFont(17, weight: .heavy, design: .rounded, maxScale: 1.15).monospacedDigit()
                .foregroundStyle(Theme.ink)
        } else if let preview {
            Text(verbatim: "\(preview)")
                .scaledFont(17, weight: .heavy, design: .rounded, maxScale: 1.15).monospacedDigit()
                .foregroundStyle(preview > 0 ? Theme.coral : Theme.inkSub)
        } else {
            Text(verbatim: "–")
                .scaledFont(15, weight: .bold, design: .rounded, maxScale: 1.15)
                .foregroundStyle(Theme.inkSub.opacity(0.6))
        }
    }

    private var background: Color {
        if isJustFilled { return Theme.yellow.opacity(0.35) }
        if scored != nil { return Theme.inkSub.opacity(0.12) }
        if let preview, preview > 0 { return Theme.coral.opacity(0.12) }
        return Theme.inkSub.opacity(0.05)
    }
}

/// サイコロ 1 個（コードで描く立方体・#2389）。`rotation` が 0 なら前面 1 枚の平らなサイコロ、
/// 転がっている間は見える面を `DiceComboCube` の投影で描く。キープ中は差し色の枠。
/// まだ振っていないときは目を薄く描く（「？」は出さない）。
struct DiceComboDieFace: View {
    let value: Int
    var isHeld = false
    /// まだ振っていない（固定の目を薄く見せる）。
    var isUnrolled = false
    /// 立方体の向き。
    var rotation: DiceComboCube.Rotation = .identity

    /// 転がる途中は横の面が正方形の外へはみ出す（45° で辺の √2 倍）。描く領域をその分広く取り、
    /// レイアウト上の大きさは変えない。
    static let drawingScale: CGFloat = 1.8

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            let pad = s * (Self.drawingScale - 1) / 2
            Canvas(rendersAsynchronously: false) { context, _ in
                context.translateBy(x: pad, y: pad)
                Self.draw(into: &context, side: s, value: value, isHeld: isHeld,
                          isUnrolled: isUnrolled, rotation: rotation)
            }
            .frame(width: s * Self.drawingScale, height: s * Self.drawingScale)
            .offset(x: -pad, y: -pad)
        }
        .aspectRatio(1, contentMode: .fit)
        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
        .accessibilityHidden(true)
    }

    /// 辺 `side` のサイコロを `(0,0)-(side,side)` に描く。面の中身は単位正方形の座標で作り、
    /// `DiceComboCube` の変換で画面へ写す（回転 0 の前面は正方形そのもの）。
    static func draw(into context: inout GraphicsContext, side s: CGFloat, value: Int,
                     isHeld: Bool, isUnrolled: Bool, rotation: DiceComboCube.Rotation) {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let corner: CGFloat = 0.2
        let borderWidth: CGFloat = isHeld ? max(3, s * 0.07) : 1
        let borderColor = isHeld ? Theme.coral : Color.black.opacity(0.25)
        // 枠は面の内側に引く（`strokeBorder` と同じ）。線の幅は画面の pt なので、単位座標では 1/s にする。
        let inset = borderWidth / 2 / s
        for face in DiceComboCube.visibleFaces(front: value, rotation: rotation, side: s) {
            let shape = Path(roundedRect: unit, cornerRadius: corner, style: .continuous).applying(face.transform)
            context.fill(shape, with: .color(Color(white: face.brightness)))
            let border = Path(roundedRect: unit.insetBy(dx: inset, dy: inset), cornerRadius: corner - inset, style: .continuous)
                .applying(face.transform)
            context.stroke(border, with: .color(borderColor), lineWidth: borderWidth)
            let pipColor = isUnrolled ? Color.black.opacity(0.22)
                : (face.value == 1 ? Theme.coral : Color(hex: 0x2B2624))
            let diameter: CGFloat = face.value == 1 ? 0.26 : 0.18
            for p in pips(face.value) {
                let rect = CGRect(x: p.x - diameter / 2, y: p.y - diameter / 2, width: diameter, height: diameter)
                context.fill(Path(ellipseIn: rect).applying(face.transform), with: .color(pipColor))
            }
        }
    }

    /// 目 1〜6 の点の位置（0〜1 の座標）。
    static func pips(_ value: Int) -> [CGPoint] {
        let l: CGFloat = 0.27, c: CGFloat = 0.5, r: CGFloat = 0.73
        switch value {
        case 1: return [CGPoint(x: c, y: c)]
        case 2: return [CGPoint(x: l, y: l), CGPoint(x: r, y: r)]
        case 3: return [CGPoint(x: l, y: l), CGPoint(x: c, y: c), CGPoint(x: r, y: r)]
        case 4: return [CGPoint(x: l, y: l), CGPoint(x: r, y: l), CGPoint(x: l, y: r), CGPoint(x: r, y: r)]
        case 5: return [CGPoint(x: l, y: l), CGPoint(x: r, y: l), CGPoint(x: c, y: c), CGPoint(x: l, y: r), CGPoint(x: r, y: r)]
        case 6: return [CGPoint(x: l, y: l), CGPoint(x: r, y: l), CGPoint(x: l, y: c), CGPoint(x: r, y: c), CGPoint(x: l, y: r), CGPoint(x: r, y: r)]
        default: return []
        }
    }
}
