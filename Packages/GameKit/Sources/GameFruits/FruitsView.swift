import Core
import SpriteKit
import SwiftUI

/// おじさんの盆栽のプレイ画面（#2361。もとは くっつきフルーツ #1319）。
///
/// SpriteKit（`FruitsScene`）が描くのは庭（盤）の中だけで、その上の縁側とおじさん（`BonsaiEngawaBoards` /
/// `BonsaiOjisanLayer`）・ヘッダー・終局の幕・遊び方・レコメンド・バナーは SwiftUI で描く
/// （アクション枠の基盤規約「メニュー・リザルトは SwiftUI」）。
public struct FruitsView: View {
    private let services: GameServices
    @State private var model: FruitsModel
    @State private var scene: FruitsScene
    /// コンティニューのリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var continueRescue = RewardedRescue()
    @State private var showConfirmNewGame = false
    @Environment(\.scenePhase) private var scenePhase

    /// VoiceOver のアクションで 1 回に動かす幅（盤の抽象単位）。
    static let accessibilityNudge: Double = 10

    public init(services: GameServices) {
        self.services = services
        let model = FruitsModel(services: services)
        _model = State(initialValue: model)
        _scene = State(initialValue: FruitsScene(model: model))
    }

    public var body: some View {
        VStack(spacing: 12) {
            header
            playfield
            HowToPlayHint(.fruits, playLog: services.playLog)
            RecommendationArea(services: services, isFinished: model.phase == .gameOver)
            BannerSlot(ads: services.ads)
        }
        .padding()
        .gameChrome(title: tr("おじさんの盆栽"), review: services.review,
                    newGame: GameChromeNewGame(.restart) {
                        startNewGame()
                    })
        .howToPlay(HowToPlayGuide.fruits.illustrated(FruitsHowToFigures.items).onboarding(FruitsOnboarding.guide)) { FruitsRuleSheet() }
        .onAppear {
            #if DEBUG
            // 撮影・動作確認用: `-simulateFruits <stack|kinmatsu|gameover>`（#1319）。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-simulateFruits"), i + 1 < args.count {
                model.applyDebugScenario(args[i + 1])
            }
            #endif
        }
        .onChange(of: model.phase) { _, _ in syncRenderLoop() }
        .onChange(of: scenePhase) { _, _ in syncRenderLoop() }
        .rewardedRescueAlerts(
            continueRescue,
            notEarned: tr("コンティニューできませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("コンティニューできませんでした"),
                message: tr("広告を見ているあいだに新しいゲームが始まったため、コンティニューできませんでした。")
            )
        )
        .dialogs { anchor in
            anchor.confirmationDialog(
                tr("はじめからやり直しますか？"),
                isPresented: $showConfirmNewGame,
                titleVisibility: .visible
            ) {
                Button(tr("終了してはじめから"), role: .destructive) {
                    withGameAnimation { model.newGame() }
                }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("途中で終了すると今のスコアが失われます。"))
            }
        }
    }

    /// 進行中は確認を挟んでからやり直す（#515）。盆栽は勝手に動かないので止める必要は無い。
    private func startNewGame() {
        guard model.hasProgressToLose else {
            withGameAnimation { model.newGame() }
            return
        }
        showConfirmNewGame = true
    }

    /// 描画ループを局面に合わせる（#522）。終局の幕の裏と、背面に回ったあいだは止める。
    ///
    /// **止めるのは `SKView` で、`SpriteView` の引数ではない**（`isPaused` は生成時にしか効かない）。
    /// 呼ぶのは局面が変わったときと、1 フレーム描き終えたとき（一度も描かないうちに止めると盤が出ない）。
    private func syncRenderLoop() {
        // 開いた直後に終局へ入る経路（撮影用の `-simulateFruits gameover`）で、一度も描かないまま止めると
        // 盤が暗い矩形のまま出る。最初の 1 フレームが描かれたら `onFrameRendered` がここへ戻ってくる。
        guard scene.hasRenderedFrame else { return }
        scene.view?.isPaused = model.phase == .gameOver || scenePhase != .active
    }

    // MARK: - ヘッダー

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("スコア"))
                    .scaledFont(12, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.inkSubText)
                Text(verbatim: RecordFormat.number(model.score))
                    .scaledFont(28, weight: .heavy, design: .rounded).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if let best = model.liveBestScore {
                HeaderBestStat(title: tr("ベスト"), value: RecordFormat.number(best))
            }
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(tr("つぎ"))
                        .scaledFont(12, weight: .bold, design: .rounded)
                        .foregroundStyle(Theme.inkSubText)
                    Text(model.nextKind.name)
                        .scaledFont(13, weight: .bold, design: .rounded)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                BonsaiIcon(model.nextKind)
                    .frame(width: 40, height: 40)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tr("つぎ、%@", model.nextKind.name))
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
        // 「つぎ」が変わった瞬間だけふわっと切り替える（数字は `numericText` が担う）。
        .gameAnimation(.easeInOut(duration: 0.15), value: model.nextKind)
    }

    // MARK: - 縁側と庭

    /// 縁側（おじさんが立つ板）と庭（盤）を縦に積んだ 1 枚の枠（#2361）。
    private var playfield: some View {
        GeometryReader { geo in
            let unit = geo.size.width / FruitField.Metrics.width
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    BonsaiEngawaBoards()
                        .frame(height: BonsaiEngawaLayout.height * unit)
                    // 操作はすべて下の透明レイヤーの `DragGesture` で受ける。SpriteView 自身に
                    // 当たり判定を残すと、機種によってはドラッグが SKView に吸われる（ブロック崩し）。
                    SpriteView(scene: scene, preferredFramesPerSecond: 60)
                        .allowsHitTesting(false)
                        // 描いたら止めてよいか見直す。画面を開き直して SKView が作り直された
                        // ときも、次の 1 フレームでここに戻ってくる（#522）。
                        .onAppear { scene.onFrameRendered = { syncRenderLoop() } }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                // おじさんと手元の盆栽は枠で切らない（大きい盆栽の木は縁側の上へ少しはみ出す）。
                BonsaiOjisanLayer(
                    cursorX: model.field.cursorX, heldKind: model.heldKind,
                    isNearLine: model.isNearLine, unit: unit
                )
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dropGesture(width: geo.size.width))
                    .accessibilityElement()
                    .accessibilityLabel(tr("庭"))
                    .accessibilityValue(accessibilityValue)
                    // 実行しても何も起きない局面（終局中・果物を持っていない待機中）では出さない（#2688）。
                    .accessibilityActions {
                        if model.phase == .playing {
                            Button(tr("左へ")) { nudge(-Self.accessibilityNudge) }
                            Button(tr("右へ")) { nudge(Self.accessibilityNudge) }
                        }
                        if model.canDrop {
                            Button(tr("落とす")) { model.drop() }
                        }
                    }
                if model.phase == .gameOver {
                    gameOverOverlay
                }
            }
        }
        // シーンは `.aspectFit` なので、庭の枠の縦横比を盤と必ず一致させる（縁側の高さは盤の単位で決まっているので、
        // 縁側と庭を合わせた比で切れば庭は盤と同じ比になる）。
        .aspectRatio(BonsaiEngawaLayout.aspectRatio, contentMode: .fit)
        // 余った縦を**先に**箱へ渡す（ブロック崩し #597）。付けないと下の余白と山分けになり、
        // 箱は使える高さの手前で止まって横幅が余る。
        .layoutPriority(1)
    }

    private var accessibilityValue: String {
        var parts = [tr("盆栽 %lld 鉢", model.fruitCount)]
        if let held = model.heldKind {
            parts.append(tr("手に%@", held.name))
        } else {
            parts.append(tr("つぎを待っています"))
        }
        if model.isOverLine { parts.append(tr("危険線に掛かっています")) }
        return parts.joined(separator: tr("、"))
    }

    private func nudge(_ delta: Double) {
        model.moveCursor(to: model.field.cursorX + delta)
    }

    /// 指の x におじさん（と手元の盆栽）が付いてきて、離した位置へ落ちる。タップなら、その位置へ移ってすぐ落ちる。
    private func dropGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                model.moveCursor(to: FruitField.Metrics.fieldX(viewX: Double(value.location.x), viewWidth: Double(width)))
            }
            .onEnded { value in
                model.moveCursor(to: FruitField.Metrics.fieldX(viewX: Double(value.location.x), viewWidth: Double(width)))
                model.drop()
            }
    }

    // MARK: - 終局の幕

    private var gameOverOverlay: some View {
        RewardedContinueOverlay(
            title: tr("ゲームオーバー"),
            cornerRadius: Theme.cornerSmall,
            detail: VStack(spacing: 6) {
                RecordLabel(model.recordResult, textColor: .white.opacity(0.85))
                if let highest = model.highestKind {
                    Text(tr("最高の段: %@", highest.name))
                        .scaledFont(14, weight: .bold, design: .rounded)
                        .foregroundStyle(.white)
                }
                if !model.continueUsed {
                    Text(tr("広告を見ると、小さい盆栽と線より上の盆栽を片づけて続けられます"))
                        .scaledFont(12, weight: .medium, design: .rounded)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
            },
            rescueLabel: tr("広告を見てコンティニュー"),
            canContinue: !model.continueUsed,
            rescue: continueRescue, services: services, gameID: FruitsModel.gameID,
            serial: model.gameSerial,
            grant: { game in model.continueAfterAd(forGame: game) },
            secondaryTitle: tr("もう一回"),
            secondaryAction: { withGameAnimation { model.newGame() } }
        )
    }
}

// MARK: - くわしいルール

/// 「くわしいルール」（盆栽の段と得点）。対局画面の `?` から 1 タップで開ける。
struct FruitsRuleSheet: View {
    var body: some View {
        RuleListSheet(rules: [
            (tr("盆栽の段"), FruitKind.allCases.map(\.name).joined(separator: " → ")),
            (tr("落とす盆栽"), tr("%@の 5 種だけが出てきます。大きい盆栽はくっつけて育てます。",
                               FruitKind.dropPool.map(\.name).joined(separator: tr("・")))),
            (tr("得点"), tr("%1$@。金の松どうしがくっつくと 2 つとも消えて %2$lld 点。",
                          FruitKind.allCases.dropFirst().map { "\($0.name) \($0.points)" }.joined(separator: tr("・")),
                          FruitKind.kinmatsuVanishPoints)),
            (tr("ゲームオーバー"), tr("上の点線より上に盆栽が 3 秒以上とどまると終わりです。落としている途中で線をまたぐぶんは数えません。")),
            (tr("コンティニュー"), tr("ゲームオーバー後に広告を見ると、1 回だけ小さい盆栽（%@）と線より上の盆栽を片づけて続けられます。スコアはそのままです。",
                                 FruitKind.allCases.prefix(FruitField.Metrics.continueRemovedKinds).map(\.name).joined(separator: tr("・")))),
        ])
    }
}
