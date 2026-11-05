import SwiftUI
import Core
import CoreOjisanPixel

// MARK: - 遊び方の選択

/// 入口で選ぶ遊び方（#3048）。`rawValue` は最後に選んだ遊び方の保存に使う。
enum CatPuzzlePlayMode: String, CaseIterable {
    /// 1 面ずつ難しくなる連番のステージ。クリアしたら次の面へ進むだけで、前の面には戻らない。
    case stage
    /// 盤の大きさを選び、毎回新しい問題（これまでの遊び方）。
    case free

    var label: String {
        switch self {
        case .stage: tr("ステージ")
        case .free: tr("自由に遊ぶ")
        }
    }
}

/// ステージのクリア後に盤の下へ出す段。「次のステージへ」と「設定を変える」（`GameReplayBar` と同じ形・寸法）。
struct CatPuzzleNextStageBar: View {
    let next: Int
    let onNext: () -> Void
    let onChangeSettings: () -> Void

    var body: some View {
        HStack(spacing: GameReplayBarMetrics.buttonSpacing) {
            Button(action: onNext) {
                capsule(tr("次のステージへ"), fill: Theme.Fill.coral, foreground: Theme.onAccent)
            }
            .accessibilityHint(tr("ステージ %lld を始めます", next))
            Button(action: onChangeSettings) {
                capsule(GameReplayBarText.changeSettings, fill: Theme.fillMuted, foreground: .white)
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, GameReplayBarMetrics.verticalPadding)
        .popCard(corner: Theme.cornerSmall)
    }

    private func capsule(_ title: String, fill: Color, foreground: Color) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: GameReplayBarMetrics.buttonHeight)
            .background(Capsule().fill(fill))
            .contentShape(Rectangle())
    }
}

// MARK: - 開始シート

/// 遊び方（ステージ／自由に遊ぶ）と、自由に遊ぶときの難易度（盤の大きさ）を選んで始めるシート。
/// 他のゲームと同じ共通の枠（`GameSetupSheet`）。
struct CatPuzzleNewGameSheet: View {
    let nextStage: Int
    /// ノーミス連続の最高（#3244）。0 なら出さない。
    let noMissBest: Int
    /// 今日貯めた合計 pt（今日のランキングの欄に出す。常設・#3298）。
    let eventTotal: Int
    /// Game Center 本体の画面を開く入口。アプリ内のランキング画面（`makeRanking`）の中のボタンから使う（無ければボタンを出さない）。
    let onOpenRanking: (@MainActor () -> Void)?
    /// アプリ内のランキング画面（#3236）のモデルを作る。無ければ「ランキングを見る」ボタンを出さない。
    let makeRanking: (@MainActor () -> CatPuzzleRankingModel)?
    let onStart: (CatPuzzlePlayMode, CatPuzzleSize) -> Void
    let onCancel: () -> Void
    @State private var mode: CatPuzzlePlayMode
    @State private var size: CatPuzzleSize
    @State private var showRanking = false
    /// 開始シートの順位の読み込み（#3312）。シートを開いたときに 1 度だけ読む。
    @State private var rankModel: CatPuzzleRankingModel?

    init(initialMode: CatPuzzlePlayMode, initial: CatPuzzleSize, nextStage: Int, noMissBest: Int = 0,
         eventTotal: Int = 0, onOpenRanking: (@MainActor () -> Void)? = nil,
         makeRanking: (@MainActor () -> CatPuzzleRankingModel)? = nil,
         onStart: @escaping (CatPuzzlePlayMode, CatPuzzleSize) -> Void,
         onCancel: @escaping () -> Void) {
        self.nextStage = nextStage
        self.noMissBest = noMissBest
        self.eventTotal = eventTotal
        self.onOpenRanking = onOpenRanking
        self.makeRanking = makeRanking
        self.onStart = onStart
        self.onCancel = onCancel
        _mode = State(initialValue: initialMode)
        _size = State(initialValue: initial.freePlaySize)
    }

    var body: some View {
        GameSetupSheet(
            kind: .solo,
            onboarding: CatPuzzleOnboarding.guide,
            onStart: { onStart(mode, size) }, onCancel: onCancel
        ) {
            Self.modeSection(selection: $mode, nextStage: nextStage)
            if mode == .stage {
                CatPuzzleStageProgressView(progress: CatPuzzleStage(nextStage).progress)
            }
            if mode == .stage, noMissBest >= CatPuzzleNoMiss.showsFrom {
                Text(tr("ノーミス連続の最高 %lld 面", noMissBest))
                    .themeCaption(12).foregroundStyle(Theme.inkSubText)
            }
            if mode == .stage {
                Self.eventSection(total: eventTotal, rank: rankModel?.state,
                                  onOpenRanking: makeRanking == nil ? nil : { showRanking = true })
            }
            if mode == .free {
                Self.sizeSection(selection: $size)
            }
        }
        .task {
            // 順位は後から差し込む。読み込み中・読めないときは合計 pt だけを出す（待たせない）。
            guard rankModel == nil, let makeRanking else { return }
            let model = makeRanking()
            rankModel = model
            await model.load()
        }
        .sheet(isPresented: $showRanking) {
            if let makeRanking {
                CatPuzzleRankingView(model: makeRanking(), onOpenGameCenter: onOpenRanking) { showRanking = false }
            }
        }
    }

    /// 遊び方の節。ステージは次に遊ぶ面の番号を添える。
    static func modeSection(selection: Binding<CatPuzzlePlayMode>, nextStage: Int) -> some View {
        GameSetupSection(tr("遊び方")) {
            HStack(spacing: 6) {
                let modes = CatPuzzlePlayMode.allCases
                ForEach(Array(modes.enumerated()), id: \.element) { step, value in
                    GameSetupChooser(title: value.label,
                                     subtitle: value == .stage ? tr("ステージ %lld から", nextStage) : tr("盤の大きさを選ぶ"),
                                     selected: selection.wrappedValue == value,
                                     accent: DifficultyTile.accent(step: step, of: modes.count),
                                     metrics: DifficultyTile.metrics) {
                        selection.wrappedValue = value
                    }
                }
            }
        }
    }

    /// 今日のランキングの節（ステージだけ・常設・#3204・#3298）。ポイントのつき方、貯めた合計、アプリ内のランキング画面を開く導線（#3236）。
    static func eventSection(total: Int, rank: CatPuzzleRankingState? = nil,
                             onOpenRanking: (@MainActor () -> Void)?) -> some View {
        GameSetupSection(tr("今日のランキング")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("ステージをクリアして今日の pt を貯めよう（毎日 日本時間の 0 時にリセット）。残りライフ 3 で 3pt・2 で 2pt・1 で 1pt（鍵の面は 2 倍）"))
                    .themeBody(13).foregroundStyle(Theme.inkSubText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(Self.totalText(total: total, rank: rank))
                        .themeBody(15).monospacedDigit()
                    Spacer(minLength: 8)
                    if let onOpenRanking {
                        Button { onOpenRanking() } label: {
                            Text(tr("今日のランキングを見る"))
                                .themeBody(14)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// 今日のランキングの欄の合計行（#3312）。順位が読めていれば「今日 n 位 / m 人・合計 xx pt」、
    /// 読み込み中・未サインイン・読めなかった・今日まだ記録が無いときは合計 pt だけ。
    static func totalText(total: Int, rank: CatPuzzleRankingState?) -> String {
        guard case .ready(let content)? = rank, let myRank = content.myRank else {
            return tr("今日の合計 %lldpt", total)
        }
        return content.participants >= myRank
            ? tr("今日 %1$lld位 / %2$lld人・合計 %3$lldpt", myRank, content.participants, total)
            : tr("今日 %1$lld位・合計 %2$lldpt", myRank, total)
    }

    /// 難易度の節（静止画の確認でも中身だけ描けるよう切り出している）。
    static func sizeSection(selection: Binding<CatPuzzleSize>) -> some View {
        GameSetupSection(tr("難易度")) {
            HStack(spacing: 6) {
                let levels = CatPuzzleSize.allCases
                ForEach(Array(levels.enumerated()), id: \.element) { step, value in
                    GameSetupChooser(title: value.label, subtitle: value.sizeLabel,
                                     selected: selection.wrappedValue == value,
                                     accent: DifficultyTile.accent(step: step, of: levels.count),
                                     metrics: DifficultyTile.metrics) {
                        selection.wrappedValue = value
                    }
                }
            }
        }
    }
}
