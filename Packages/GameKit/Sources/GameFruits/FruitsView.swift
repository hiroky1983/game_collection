import Core
import SpriteKit
import SwiftUI

/// くっつきフルーツのプレイ画面（#1319）。
///
/// SpriteKit（`FruitsScene`）が描くのは箱の中だけで、ヘッダー・終局の幕・遊び方・レコメンド・バナーは
/// これまでのゲームと同じ SwiftUI 部品を使う（アクション枠の基盤規約「メニュー・リザルトは SwiftUI」）。
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
        .gameChrome(title: "くっつきフルーツ", review: services.review) {
            ToolbarItem(placement: .primaryAction) {
                Button { startNewGame() } label: {
                    Label("はじめから", systemImage: "arrow.clockwise")
                }
            }
        }
        .howToPlay(.fruits) { FruitsRuleSheet() }
        .onAppear {
            #if DEBUG
            // 撮影・動作確認用: `-simulateFruits <stack|melon|gameover>`（#1319）。
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
            notEarned: "コンティニューできませんでした",
            unavailable: RewardUnavailableAlert(
                title: "コンティニューできませんでした",
                message: "広告を見ているあいだに新しいゲームが始まったため、コンティニューできませんでした。"
            )
        )
        .confirmationDialog(
            "はじめからやり直しますか？",
            isPresented: $showConfirmNewGame,
            titleVisibility: .visible
        ) {
            Button("終了してはじめから", role: .destructive) {
                withGameAnimation { model.newGame() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("途中で終了すると今のスコアが失われます。")
        }
    }

    /// 進行中は確認を挟んでからやり直す（#515）。果物は勝手に動かないので止める必要は無い。
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
                Text("スコア")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                Text(verbatim: RecordFormat.number(model.score))
                    .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("つぎ")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                    Text(model.nextKind.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                FruitIcon(model.nextKind)
                    .frame(width: 40, height: 40)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("つぎ、\(model.nextKind.name)")
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
        // 「つぎ」が変わった瞬間だけふわっと切り替える（数字は `numericText` が担う）。
        .gameAnimation(.easeInOut(duration: 0.15), value: model.nextKind)
    }

    // MARK: - 箱

    private var playfield: some View {
        GeometryReader { geo in
            ZStack {
                // 操作はすべて下の透明レイヤーの `DragGesture` で受ける。SpriteView 自身に
                // 当たり判定を残すと、機種によってはドラッグが SKView に吸われる（ブロック崩し）。
                SpriteView(scene: scene, preferredFramesPerSecond: 60)
                    .allowsHitTesting(false)
                    // 描いたら止めてよいか見直す。画面を開き直して SKView が作り直された
                    // ときも、次の 1 フレームでここに戻ってくる（#522）。
                    .onAppear { scene.onFrameRendered = { syncRenderLoop() } }
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dropGesture(width: geo.size.width))
                    .accessibilityElement()
                    .accessibilityLabel("箱")
                    .accessibilityValue(accessibilityValue)
                    .accessibilityAction(named: "左へ") { nudge(-Self.accessibilityNudge) }
                    .accessibilityAction(named: "右へ") { nudge(Self.accessibilityNudge) }
                    .accessibilityAction(named: "落とす") { model.drop() }
                if model.phase == .gameOver {
                    gameOverOverlay
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
        }
        // シーンは `.aspectFit` なので、枠の縦横比を盤と必ず一致させる。
        .aspectRatio(FruitField.Metrics.aspectRatio, contentMode: .fit)
        // 余った縦を**先に**箱へ渡す（ブロック崩し #597）。付けないと下の余白と山分けになり、
        // 箱は使える高さの手前で止まって横幅が余る。
        .layoutPriority(1)
    }

    private var accessibilityValue: String {
        var parts = ["果物 \(model.fruitCount) 個"]
        if let held = model.heldKind {
            parts.append("手に\(held.name)")
        } else {
            parts.append("つぎを待っています")
        }
        if model.isOverLine { parts.append("危険線に掛かっています") }
        return parts.joined(separator: "、")
    }

    private func nudge(_ delta: Double) {
        model.moveCursor(to: model.field.cursorX + delta)
    }

    /// 指の x に果物が付いてきて、離した位置へ落ちる。タップなら、その位置へ移ってすぐ落ちる。
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
            title: "ゲームオーバー",
            cornerRadius: Theme.cornerSmall,
            contentPadding: 16,
            detail: VStack(spacing: 6) {
                RecordLabel(model.recordResult, textColor: .white.opacity(0.85))
                if !model.continueUsed {
                    Text("広告を見ると、小さい果物と線より上の果物を片づけて続けられます")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
            },
            rescueLabel: "広告を見てコンティニュー",
            canContinue: !model.continueUsed,
            rescue: continueRescue, services: services, gameID: FruitsModel.gameID,
            serial: model.gameSerial,
            grant: { game in model.continueAfterAd(forGame: game) },
            secondaryTitle: "もう一度",
            secondaryAction: { withGameAnimation { model.newGame() } }
        )
    }
}

// MARK: - くわしいルール

/// 「くわしいルール」（果物の順番と得点）。対局画面の `?` から 1 タップで開ける。
struct FruitsRuleSheet: View {
    var body: some View {
        RuleListSheet(rules: [
            ("果物の順番", FruitKind.allCases.map(\.name).joined(separator: " → ")),
            ("落とす果物", "\(FruitKind.dropPool.map(\.name).joined(separator: "・"))の 5 種だけが出てきます。大きい果物はくっつけて作ります。"),
            ("得点", FruitKind.allCases.dropFirst().map { "\($0.name) \($0.points)" }.joined(separator: "・") + "。メロンどうしがくっつくと 2 つとも消えて \(FruitKind.melonVanishPoints) 点。"),
            ("ゲームオーバー", "上の点線より上に果物が 1 秒以上とどまると終わりです。落としている途中で線をまたぐぶんは数えません。"),
            ("コンティニュー", "ゲームオーバー後に広告を見ると、1 回だけ小さい果物（\(FruitKind.allCases.prefix(FruitField.Metrics.continueRemovedKinds).map(\.name).joined(separator: "・"))）と線より上の果物を片づけて続けられます。スコアはそのままです。"),
        ])
    }
}
