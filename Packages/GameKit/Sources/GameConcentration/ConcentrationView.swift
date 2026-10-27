import SwiftUI
import Core

public struct ConcentrationView: View {
    @State private var model: ConcentrationModel
    private let services: GameServices
    @State private var showNewGame = false
    @State private var showConfirmNewGame = false
    @State private var showMattaConfirm = false
    /// 「待った」のリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var undoRescue = RewardedRescue()
    /// ヒントの広告の段取り（#2026）。「待った」とは別の救済として持つ。
    @State private var hintRescue = RewardedRescue()

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: ConcentrationModel(services: services))
    }

    /// 勝ちが続いたら一段上の強さを勧める（#722）。枚数は今の対局のものを引き継ぐ。
    private var ladder: DifficultyLadderPrompt? {
        let levels = ConcentrationCPULevel.allCases
        return DifficultyLadderPrompt(result: model.recordResult, currentLevel: levels.firstIndex(of: model.cpuLevel),
                                      levelLabels: levels.map(\.displayName)) { level in
            model.newGame(pairCount: model.pairCount, cpuLevel: levels[level])
        }
    }

    public var body: some View {
        // レイアウトパターン A（全画面・会長決裁 2026-10-23・#2531）: ほかのトランプと同じく、フェルトを画面全体に敷き、
        // ヘッダーは 1 行（戻る・神経衰弱・得点と手番の札・？・＋）、バナーは画面最下部（枠が置く）。
        // ヘッダー下の得点の帯はやめてヘッダーの行へ移し、札の並びに縦をできるだけ回す。
        VStack(spacing: Self.stackSpacing) {
            // 札の並びと「⋯」の行は `cardGrid` の中で置き、余りの高さは「⋯」の行の下に残す
            // （盤→「⋯」→余白→広告・#1485）。
            cardGrid
            HowToPlayHint(.concentration, playLog: services.playLog)
            // レコメンド・階段の枠は結果の暗幕の中に置く（`resultOverlay`）。ここに置くと
            // 決着後は暗幕の下になり、透けて見えるのに押せない（#847）。
        }
        // 左右 8pt（全画面の枠の値）。上下はヘッダーの余白 4 とバナーの帯の余白 8 に足す分。
        .padding(.horizontal, FullScreenGameLayoutMetrics.sideInset)
        .padding(.vertical, Self.verticalInset)
        // 得点（あなた・CPU）と手番は、ヘッダー下の帯ではなくヘッダーの行の札に置く（A の「1 行のヘッダー」）。
        .gameChrome(title: tr("神経衰弱"), review: services.review, fullScreen: .felt, ads: services.ads,
                    condition: GameChromeCondition([model.cpuLevel.displayName, model.pairCount.displayName]),
                    newGame: GameChromeNewGame(.match) { requestNewGame() }) {
            scoreChips
        }
        .howToPlay(HowToPlayGuide.concentration.illustrated(ConcentrationHowToFigures.items).onboarding(ConcentrationOnboarding.guide))
        .dialogs { anchor in
            anchor.confirmationDialog(tr("新規対局を始めますか？"), isPresented: $showConfirmNewGame, titleVisibility: .visible) {
                Button(tr("終了して新規対局"), role: .destructive) { showNewGame = true }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("途中で終了すると、いまの対戦が失われます。"))
            }
        }
        .sheet(isPresented: $showNewGame) {
            ConcentrationNewGameSheet(
                pairCount: model.pairCount,
                cpuLevel: model.cpuLevel
            ) { pairs, level in
                model.newGame(pairCount: pairs, cpuLevel: level)
                showNewGame = false
            } onCancel: { showNewGame = false }
        }
        .overlay {
            // 終局はフェードで出す（#208）。オセロ（#205）と同じく `.gameAnimation` は
            // オーバーレイの ZStack にだけ置く。ここより外に置くと「待った」欄や
            // レコメンド枠の入れ替えまで animate され、決着の瞬間に盤が伸び縮みする。
            // 修飾子は1つのビューに1つだけ置くこと（入れ子にすると打ち消し合う・#199）。
            ZStack {
                if model.isGameOver {
                    resultOverlay
                        .transition(.opacity)
                }
            }
            .gameAnimation(ConcentrationMotion.resultOverlayFade, value: model.isGameOver)
        }
        .dialogs { anchor in
            anchor.alert(tr("待った確認"), isPresented: $showMattaConfirm) {
                Button(model.mattaUsed ? tr("広告を見て戻す") : tr("戻す（無料）")) {
                    guard model.mattaUsed else {
                        // 無料の待ったは #526 の前と同じく、アラートを閉じる処理とは別の
                        // 手番で盤を動かす（同じ transaction に乗せると札の変化が
                        // アラートの終了アニメーションに巻き込まれる）。
                        Task { model.useMatta() }
                        return
                    }
                    // 視聴完了（報酬獲得）したときだけ待ったを許可する。どの局に対する待ったかを
                    // 広告を出す前に控え、ロード中に入れ替わった局へは乗せない（#729）。
                    let game = model.gameSerial
                    undoRescue.request(
                        services, gameID: model.gameID, purpose: .undo,
                        guardedBy: .checkedByGrant,
                        // 待ったの確認中は自動めくりを止めてあるので、見なかったときは再開させる。
                        whenNotEarned: { model.resumeAutoTurn() }
                    ) {
                        guard model.useMatta(forGame: game) else {
                            // 戻せなかったときも、止めてあった自動めくりは再開させる（再開すべき状況が無ければ何もしない）。
                            model.resumeAutoTurn()
                            return false
                        }
                        return true
                    }
                }
                Button(tr("キャンセル"), role: .cancel) { model.resumeAutoTurn() }
            } message: {
                Text(model.mattaUsed
                     ? tr("無料の待ったは使い切りました。\n広告を視聴すると1手戻せます。")
                     : tr("ミスマッチを取り消してもう一度選べます。\n無料で使えるのは1回だけです。"))
            }
        }
        // 無料の待ったの確認は広告の提示ではないので数えない（#780）。
        .rewardOffer(undoRescue, for: .undo, isPresented: showMattaConfirm && model.mattaUsed,
                     services: services, gameID: model.gameID)
        .rewardedRescueAlerts(
            undoRescue,
            notEarned: tr("待ったは使えませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("待ったは使えませんでした"),
                message: tr("広告を見ているあいだに新しいゲームが始まったか、手番が変わったため、戻せませんでした。")
            )
        )
        .rewardedRescueAlerts(
            hintRescue,
            notEarned: tr("ヒントを表示できませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("ヒントを出せませんでした"),
                message: tr("広告を見ているあいだに新しいゲームが始まったか、札の状況が変わったため、ヒントを出せませんでした。\nヒントの残り回数は減っていません。")
            )
        )
        #if DEBUG
        .task {
            // 撮影・動作確認用: `-concentrationScenario mid|result` で局面を差し替える。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-concentrationScenario"), i + 1 < args.count {
                model.applyDebugScenario(args[i + 1])
            }
        }
        #endif
        .task(id: model.turnID) {
            await model.performCPUMoveIfNeeded()
        }
        // 相方の札を光らせる時間は Model が返し、ここは待って消すだけ（スピードの待ちと同じ形）。
        .task(id: model.hintRun) {
            guard let wait = model.hintGlowDuration else { return }
            let run = model.hintRun
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            model.finishHint(run: run)
        }
        // CPUのミスマッチは doCPUTurn が自前でクリアするため onChange 不要
    }

    /// 新規対局の入口（ヘッダーの「新規」と条件のチップが共通で呼ぶ・#1690）。
    private func requestNewGame() {
        if model.hasProgressToLose {
            showConfirmNewGame = true
        } else {
            showNewGame = true
        }
    }

    // MARK: - 得点と手番（ヘッダーの行の札）

    /// あなた・CPU の得点。手番の側の札を塗って手番を示す（以前のヘッダー下の帯と同じ見せ方）。
    /// 文字色は札が自分で持つ（白い面の上に墨・塗った面の上に白）。
    /// ヘッダーの残りの幅に「あなた」「CPU」の文字が収まらないとき（iPhone SE など）は、文字を人とコンピュータの印に替える。
    private var scoreChips: some View {
        ViewThatFits(in: .horizontal) {
            scoreChipPair(compact: false)
            scoreChipPair(compact: true)
        }
    }

    private func scoreChipPair(compact: Bool) -> some View {
        HStack(spacing: 6) {
            scoreChip(label: tr("あなた"), symbol: compact ? "person.fill" : nil, score: model.playerScore,
                      color: Theme.Fill.teal, isActive: model.isHumanTurn && !model.isGameOver,
                      turnText: tr("あなたの番"))
            scoreChip(label: "CPU", symbol: compact ? "desktopcomputer" : nil, score: model.cpuScore,
                      color: Theme.Fill.coral, isActive: !model.isHumanTurn && !model.isGameOver,
                      turnText: tr("CPUの番"))
                // 思考中の印は CPU の札の角に重ねる（場所を取らないので、出入りで札が左右に動かない）。
                .overlay(alignment: .topTrailing) {
                    ProgressView().controlSize(.mini)
                        .tint(.white)
                        .offset(x: 4, y: -6)
                        .opacity(model.isThinking ? 1 : 0)
                        .accessibilityHidden(true)
                }
        }
    }

    /// - Parameter symbol: 狭い幅で文字の代わりに出す印。nil なら文字（`label`）を出す。読み上げはどちらも `label`。
    private func scoreChip(label: String, symbol: String? = nil, score: Int, color: Color, isActive: Bool,
                           turnText: String) -> some View {
        HStack(spacing: 5) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .scaledFont(12, weight: .bold, maxScale: Self.headerTextMaxScale)
                        .accessibilityLabel(label)
                } else {
                    Text(label)
                        .scaledFont(12, weight: .bold, design: .rounded, maxScale: Self.headerTextMaxScale)
                }
            }
            .foregroundStyle(isActive ? Theme.onAccent : Theme.inkSubText)
            // 幅はこの盤の最高点の桁数ぶん先に取る。点が 9 → 10 に増えたときに札の幅が変わり、
            // 文字 ↔ 印の切り替え（`scoreChips`）が局の途中で起きないようにする。
            ZStack {
                Text(String(repeating: "8", count: String(model.pairCount.rawValue).count))
                    .hidden()
                Text("\(score)")
            }
            .monospacedDigit()
            .scaledFont(18, weight: .black, design: .rounded, maxScale: Self.headerTextMaxScale)
            .foregroundStyle(isActive ? Theme.onAccent : Theme.ink)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(isActive ? color : Theme.surface))
        // 手番が移ったことを色の変化で見せる（#208）。文字色（白 ↔ inkSub）も同じ値で
        // 切り替わるため、この1つで chip 全体が一緒に馴染む。
        .gameAnimation(ConcentrationMotion.turnHighlight, value: isActive)
        // 手番は面の色でしか示さないので、読み上げには値として足す（#2495）。
        .accessibilityElement(children: .combine)
        .accessibilityValue(isActive ? turnText : "")
    }

    // MARK: - Matta Controls

    private var mattaControls: some View {
        // 待ったは盤の下の段のカプセル（#1856・案A）。「⋯」に残る項目は無いので「⋯」は出ず、待ったが横いっぱいになる
        // （会長決裁 2026-10-06「問題なし」）。押せる間（ミスマッチの猶予中）だけ有効になる。
        // ミスマッチは自動で裏返るため「次へ」ボタンは無い（#137）。待っている間だけ押せることは、
        // 面がグレー → ティールに変わるのに加えて 2 行目の「今だけ！」で知らせる（以前は行の左端の文字）。
        GameOverflowBar(
            actions: [
                hintAction,
                GameActionItem(
                    id: "matta", title: tr("待った"),
                    systemImage: "arrow.uturn.backward", role: .undo,
                    badge: model.mattaUsed ? .ad() : .count(1),
                    note: model.canMatta ? tr("今だけ！") : nil,
                    isEnabled: model.canMatta,
                    accessibilityHint: model.canMatta ? tr("ミスマッチの札が裏返る前なら、直前のめくりをやり直せます") : tr("ミスマッチの直後だけ使えます")
                ) {
                    // 確認ダイアログを開いている間に自動でターンが移ると「戻す」が空振りするため止める
                    model.pauseAutoTurn()
                    showMattaConfirm = true
                }
            ],
            verticalPadding: Self.controlRowPadding,
            nudge: HintNudge(
                isEligible: model.canUseHint && !hintRescue.isWatching,
                game: model.gameSerial,
                activity: [model.hints.used, model.firstFlippedIndex ?? -1]
            )
        )
    }

    /// 盤の下の段のヒント（#2026）。数字は「いま使える回数」で、無料を使い切ったら「▶ 広告を見て」（#1897）。
    private var hintAction: GameActionItem {
        let free = model.hints.freeRemaining
        return GameActionItem(
            id: "hint", title: tr("ヒント"), systemImage: "lightbulb.fill", role: .hint,
            badge: model.needsAdForHint ? .ad() : .count(free),
            isEnabled: model.canUseHint && !hintRescue.isWatching,
            accessibilityLabel: model.needsAdForHint
                ? tr("ヒント（広告を見て表示）")
                : tr("ヒント（残り%lld回）", free),
            accessibilityHint: model.firstFlippedIndex == nil
                ? tr("自分の番で1枚目をめくると使えます")
                : tr("1枚目の札の相方を、少しのあいだ光らせます")
        ) { requestHint() }
    }

    /// ヒントの入口。無料の残りがあればそのまま出し、使い切っていたら広告を見終えてから出す（広告は押下起点）。
    private func requestHint() {
        guard !hintRescue.isWatching, model.canUseHint else { return }
        guard model.needsAdForHint else {
            if model.requestHint() {
                AccessibilityNotification.Announcement(tr("ヒント、光っている札が相方です")).post()
            }
            return
        }
        // どの局のどの札に対する広告かを出す前に控え、見ているあいだに状況が変わったら適用しない。
        let game = model.gameSerial
        let first = model.firstFlippedIndex
        hintRescue.request(
            services, gameID: model.gameID, purpose: .hint,
            guardedBy: .checkedByGrant
        ) {
            model.grantAdHint(forGame: game, first: first)
        }
    }

    // MARK: - Card Grid

    private var cardGrid: some View {
        // 幅だけでカードの大きさを決めると縦に大きな空白が残る。与えられた高さも見て、
        // 余っていればカードを縦に伸ばす（伸ばしすぎて不自然にならないよう上限を設ける）。
        // 「⋯」の行（対局中だけ）も同じ枠の中で札のすぐ下に置くので、その高さを先に引いておく（#1485）。
        GeometryReader { geo in
            let spacing = ConcentrationGridLayout.spacing
            let controlRow = Self.controlRowHeight + Self.stackSpacing
            // 列の数は「⋯」の行を引いた高さで決める（決着で「⋯」の行が消えても並びが組み替わらない）。
            let cols = ConcentrationGridLayout.columns(
                pairCount: model.pairCount, width: geo.size.width, height: max(0, geo.size.height - controlRow))
            let controls = model.isGameOver ? 0 : controlRow
            let gridHeight = max(0, geo.size.height - controls)
            let size = ConcentrationGridLayout.cardSize(
                cardCount: model.cards.count, columns: cols, width: geo.size.width, height: gridHeight)
            let cardWidth = size.width
            let cardHeight = size.height
            let columns = Array(repeating: GridItem(.fixed(cardWidth), spacing: spacing), count: cols)

            VStack(spacing: Self.stackSpacing) {
                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(model.cards) { card in
                        CardView(
                            card: card,
                            isLastMatched: model.lastMatchedIndices.contains(card.id),
                            isMismatched: model.mismatchedIndices.contains(card.id),
                            isHint: model.hintIndex == card.id
                        )
                        .onTapGesture { tapCard(card.id) }
                        .accessibilityAddTraits(model.isHumanTurn ? .isButton : [])
                        .accessibilityAction { tapCard(card.id) }
                        .frame(width: cardWidth, height: cardHeight)
                    }
                }
                if !model.isGameOver {
                    mattaControls
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    /// 札を開く。タップと VoiceOver の操作で同じ条件を通す。
    private func tapCard(_ index: Int) {
        guard model.isHumanTurn, model.mismatchedIndices.isEmpty else { return }
        model.tap(index: index)
    }

    /// 画面の縦の並びの間隔。
    private static let stackSpacing: CGFloat = 10
    /// 中身の上下の余白（ヘッダーの余白 4 / バナーの帯の余白 8 に足す分。ババ抜き・ハーツと同じ）。
    private static let verticalInset: CGFloat = 2
    /// ヘッダーの得点の札が文字サイズ設定で拡大する上限（ヘッダーの 44pt の行に収める）。
    private static let headerTextMaxScale: CGFloat = 1.3
    /// 「⋯」の行の上下の余白と、それを含めた行の高さ（`GameOverflowBar` は 44pt の枠 + 上下の余白）。
    private static let controlRowPadding: CGFloat = 8
    private static let controlRowHeight: CGFloat = BoardGameControlMetrics.minTapTarget + 2 * controlRowPadding

    // MARK: - Result Overlay

    private var resultOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            // 結果カードの直下にレコメンド・階段の枠を並べ、暗幕の前面で押せるようにする（#847）。
            // カードの内側に入れると内寸が狭く（SE で約 255pt）段名が切れるので、外に並べて幅を揃える。
            VStack(spacing: 12) {
                resultCard
                RecommendationSlot(services: services, isFinished: true, ladder: ladder)
            }
            .padding(.horizontal, 32)
        }
    }

    private var resultCard: some View {
        VStack(spacing: 16) {
            Group {
                if let winner = model.winner {
                    let isWin = winner == .human
                    Image(systemName: isWin ? "trophy.fill" : "flag.fill")
                        .scaledFont(52, maxScale: 1.2)
                        .foregroundStyle(isWin ? Theme.yellowText : Theme.coralText)
                    Text(isWin ? tr("あなたの勝ち！") : tr("CPUの勝ち"))
                        .scaledFont(26, weight: .black, design: .rounded)
                        .foregroundStyle(isWin ? Theme.tealText : Theme.coralText)
                } else {
                    Image(systemName: "equal.circle.fill")
                        .scaledFont(52, maxScale: 1.2)
                        .foregroundStyle(Theme.inkSubText)
                    Text(tr("引き分け"))
                        .scaledFont(26, weight: .black, design: .rounded)
                        .foregroundStyle(Theme.inkSubText)
                }
            }

            HStack(spacing: 20) {
                VStack {
                    Text(tr("あなた")).themeBody(13).foregroundStyle(Theme.inkSubText)
                    Text("\(model.playerScore)").themeTitle(36).foregroundStyle(Theme.tealText)
                }
                Text("–").themeTitle(24).foregroundStyle(Theme.inkSubText)
                VStack {
                    Text("CPU").themeBody(13).foregroundStyle(Theme.inkSubText)
                    Text("\(model.cpuScore)").themeTitle(36).foregroundStyle(Theme.coralText)
                }
            }

            // ヒントは 0 回でも省かず出す（#2613・#2801）。
            Text(tr("ヒント %lld回", model.hints.used))
                .themeBody(14).foregroundStyle(Theme.inkSubText)

            RecordLabel(model.recordResult)

            GameReplayBar(
                onReplay: { model.newGame(pairCount: model.pairCount, cpuLevel: model.cpuLevel) },
                onChangeSettings: { showNewGame = true }
            )
        }
        .padding(28)
        .popCard()
    }
}

// MARK: - Card View

private struct CardView: View {
    let card: ConcentrationCard
    let isLastMatched: Bool
    let isMismatched: Bool
    /// ヒントが示している相方の札（#2026）。
    var isHint = false

    private var isFaceUp: Bool { card.isFaceUp || card.isMatched }

    /// 札の角丸。ヒントの枠と表の面で同じ形を使う（数字の角丸を増やさない・#1413）。
    private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    /// 図案の一辺。札の短い辺に対する比で置き、盤面サイズに追従させる
    /// （絵文字は 28pt 固定だったため、8ペアの大きい札では小さく、18ペアでは詰まって見えた）。
    private static let figureRatio: CGFloat = 0.56

    var body: some View {
        GeometryReader { geo in
            face(side: min(geo.size.width, geo.size.height) * Self.figureRatio)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        // 大きさは呼び出し側（cardGrid）が画面の空きに合わせて決める
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .gameAnimation(ConcentrationMotion.cardFlip, value: isFaceUp)
        .opacity(card.isMatched ? 0.6 : 1.0)
        .overlay {
            if isHint {
                // 裏は紫なので、白の縁を挟んだ紫の二重枠にして背景に沈ませない。
                cardShape
                    .strokeBorder(.white, lineWidth: 5)
                    .overlay(
                        cardShape
                            .strokeBorder(BoardGameHintColor.color, lineWidth: 2.5)
                    )
                    .shadow(color: BoardGameHintColor.color.opacity(0.6), radius: 6)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    /// 絵文字をやめると読み上げも消えるため、札の状態を言葉で持ち直す（#601）。
    private var accessibilityText: String {
        if isHint { return tr("裏向きの札、ヒント（1枚目の相方）") }
        guard isFaceUp, let name = card.figure?.displayName else { return tr("裏向きの札") }
        if card.isMatched { return tr("%@（獲得済み）", name) }
        // 不一致は coral の枠だけで示していたので、読み上げにも出す（#2322）。
        return isMismatched ? tr("%@（一致しませんでした）", name) : name
    }

    @ViewBuilder
    private func face(side: CGFloat) -> some View {
        ZStack {
            if isFaceUp {
                // 表は紙の淡い縦グラデーション（CardStyle #366）。マッチ済みのティール地は維持。
                // 獲得済みの淡いティールは紙の上に重ねる（素の半透明だとフェルトの緑が透けて沈む・#2531）。
                cardShape
                    .fill(CardStyle.faceFill)
                    .overlay(cardShape.fill(Theme.teal.opacity(card.isMatched ? 0.15 : 0)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                isLastMatched ? Theme.teal :
                                isMismatched ? Theme.coral :
                                Color.clear,
                                lineWidth: 2
                            )
                    )
                // 図案はどれも同じ正方形に描くので、札ごとに大きさと余白がずれない。
                if let figure = card.figure {
                    ConcentrationFigureView(figure: figure)
                        .frame(width: side, height: side)
                }
            } else {
                // 裏は神経衰弱の顔である紫を保ちつつ、白の内枠で「カードの裏」に寄せる（#366）。
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.purple, Theme.purple.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                CardStyle.backFrame(cornerRadius: 10)
                Image(systemName: "questionmark")
                    .scaledFont(18, weight: .bold)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - 札の並びの寸法

/// 札の並び（列の数と札の大きさ）。View を組まずに大きさを確かめられるよう純関数にする（`ConcentrationGridLayoutTests`）。
///
/// レイアウトパターン A（#2531）で縦が伸びたので、札の並びが画面にいちばん大きく見える列の数を選ぶ:
/// 12 ペア（24 枚）は 6 列 × 4 段が既定で、縦長の画面（iPhone 17）では 4 列 × 6 段のほうが札が大きくなるのでそちらにする。
/// 札は基準比（幅 : 高さ = 0.75）より横長にはせず、縦は基準比の `maxStretch` 倍まで伸ばす。
enum ConcentrationGridLayout {
    /// カードの基準の幅 : 高さ
    static let cardAspect: CGFloat = 0.75
    /// 縦に余ったときにカードを引き伸ばしてよい上限（基準比に対する倍率）
    static let maxStretch: CGFloat = 1.3
    /// 札のあいだの間隔。
    static let spacing: CGFloat = 6
    /// 既定の列の数より札がこれ以上大きくなるときだけ、別の列の数に替える（ほぼ同じなら既定の並びのまま）。
    static let switchThreshold: CGFloat = 2

    /// 試す列の数。先頭が既定（以前の固定の列の数）。
    static func candidateColumns(pairCount: ConcentrationPairCount) -> [Int] {
        switch pairCount {
        case .small: return [4]
        case .medium: return [6, 4]
        case .large: return [6]
        }
    }

    /// 札の大きさ。高さが足りないときは基準比を保ったまま縮め、余っているときは縦を `maxStretch` 倍まで伸ばす。
    static func cardSize(cardCount: Int, columns: Int, width: CGFloat, height: CGFloat) -> CGSize {
        let cols = max(1, columns)
        let rows = Int((Double(cardCount) / Double(cols)).rounded(.up))
        let widthLimit = (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        let heightLimit = rows > 0
            ? (height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            : widthLimit / cardAspect
        let cardWidth = max(1, min(widthLimit, heightLimit * cardAspect))
        let cardHeight = max(1, min(heightLimit, cardWidth / cardAspect * maxStretch))
        return CGSize(width: cardWidth, height: cardHeight)
    }

    /// 札の幅（＝図案の大きさ）がいちばん大きくなる列の数。差が `switchThreshold` 未満なら既定の列の数。
    static func columns(pairCount: ConcentrationPairCount, width: CGFloat, height: CGFloat) -> Int {
        let candidates = candidateColumns(pairCount: pairCount)
        let cardCount = pairCount.rawValue * 2
        var best = candidates[0]
        var bestWidth = cardSize(cardCount: cardCount, columns: best, width: width, height: height).width
        for cols in candidates.dropFirst() {
            let w = cardSize(cardCount: cardCount, columns: cols, width: width, height: height).width
            if w >= bestWidth + switchThreshold {
                best = cols
                bestWidth = w
            }
        }
        return best
    }
}

// MARK: - New Game Sheet

struct ConcentrationNewGameSheet: View {
    @State private var selectedPairCount: ConcentrationPairCount
    @State private var selectedCPULevel: ConcentrationCPULevel
    let onStart: (ConcentrationPairCount, ConcentrationCPULevel) -> Void
    let onCancel: () -> Void

    init(pairCount: ConcentrationPairCount,
         cpuLevel: ConcentrationCPULevel,
         onStart: @escaping (ConcentrationPairCount, ConcentrationCPULevel) -> Void,
         onCancel: @escaping () -> Void) {
        _selectedPairCount = State(initialValue: pairCount)
        _selectedCPULevel = State(initialValue: cpuLevel)
        self.onStart = onStart
        self.onCancel = onCancel
    }

    /// 題名が「4×4」「みならい」のような語なので、見出し書体ではなく本文書体で並べる。
    private static let metrics = GameSetupChooser.Metrics(title: .body(16))

    var body: some View {
        GameSetupSheet(
            kind: .versus, startTint: Theme.Fill.purple,
            onboarding: ConcentrationOnboarding.guide,
            onStart: { onStart(selectedPairCount, selectedCPULevel) }, onCancel: onCancel
        ) {
            GameSetupSection(tr("盤面サイズ")) {
                HStack(spacing: 12) {
                    ForEach(ConcentrationPairCount.allCases, id: \.rawValue) { p in
                        GameSetupChooser(
                            title: p.displayName,
                            subtitle: p.subtitle,
                            selected: selectedPairCount == p,
                            accent: Theme.Fill.teal,
                            metrics: Self.metrics
                        ) { selectedPairCount = p }
                    }
                }
            }

            GameSetupSection(tr("CPUの強さ")) {
                HStack(spacing: 6) {
                    ForEach(Array(ConcentrationCPULevel.allCases.enumerated()), id: \.element) { step, l in
                        GameSetupChooser(
                            title: l.displayName,
                            subtitle: l.subtitle,
                            selected: selectedCPULevel == l,
                            accent: DifficultyTile.accent(step: step, of: ConcentrationCPULevel.allCases.count),
                            metrics: DifficultyTile.metrics
                        ) { selectedCPULevel = l }
                    }
                }
            }
        }
    }
}
