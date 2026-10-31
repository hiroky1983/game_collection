import Foundation
import Observation
import Core

// MARK: - Phase

public enum OldMaidPhase: String, Equatable, Sendable, Codable {
    /// 開始前。
    case idle
    /// 対局中。
    case playing
    /// 1 ゲームの決着。
    case result
}

// MARK: - Snapshot

/// 中断データ。局面（`OldMaidGame`）をそのまま持つ。CPU の強さも局面の中（`aiLevel`）にある。
struct OldMaidSnapshot: Codable {
    let game: OldMaidGame
    let gameNumber: Int
}

// MARK: - Model

/// ババ抜き（あなた 1 人 対 CPU 3 人・#1577）。あなたは常に番号 0。
///
/// 配り・合法な引き方・終局判定・CPU の選び方・顔の出方は `OldMaidGame`（純粋な値）に寄せ、
/// この型は**進行・永続化・演出・計測**だけを持つ。CPU の手番の回し方はいろリレー・大富豪と同じ定石
/// （`AITurnGuarded`・#531）。
@MainActor
@Observable
public final class OldMaidModel: AITurnGuarded {
    /// あなたの番号。
    public static let humanIndex = OldMaidGame.humanIndex
    /// 参加人数（あなた 1 + CPU 3）。
    public static let playerCount = OldMaidGame.playerCount
    /// `GameModule.id` と同じ値。`OldMaidModuleTests` が一致を確かめる。
    public static let gameID = "oldmaid"

    /// いまの局面。開始前は nil。
    public private(set) var game: OldMaidGame?
    public private(set) var phase: OldMaidPhase = .idle
    /// 何ゲーム目か（1 始まり）。最初に引く人がゲームごとに 1 人ずつ回る。
    public private(set) var gameNumber = 0
    /// CPU の強さ（`CPUStrength.rawValue`）。次に配るゲームから効く。
    public private(set) var aiLevel: Int = CPUStrength.standard.rawValue
    /// あなたが指をかけている（引こうとしている）相手の札の ID。
    public private(set) var selectedID: Int?
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// 配ったばかりで 1 枚も動いていない局か（#240）。配ったばかりの局は保存しない。
    private var isUntouchedDeal = false

    private let services: GameServices?
    let gameID = OldMaidModel.gameID
    private let cpuDelay: Duration
    /// 配り・CPU の引き方・混ぜ方の乱数。種を渡すと再現できる（テスト用）。画面の再描画には関わらない。
    @ObservationIgnored private var generator: SplitMix64
    /// CPU の連続手番が二重に走らないようにする門番。テストが同期ゲートに使うので `internal`。
    var isRunningCPUTurns = false

    public init(
        services: GameServices? = nil,
        cpuDelay: Duration = .milliseconds(700),
        seed: UInt64? = nil
    ) {
        self.services = services
        self.cpuDelay = cpuDelay
        generator = SplitMix64(seed: seed ?? UInt64.random(in: .min ... .max))
        // 手書き・壊れた中断データで落ちないよう、札の数・番号の範囲を見てから戻す。
        if let snap = services?.snapshots.load(OldMaidSnapshot.self, for: gameID),
           snap.game.isConsistent, !snap.game.isOver {
            game = snap.game
            gameNumber = max(snap.gameNumber, 1)
            aiLevel = CPUStrength.strength(for: snap.game.aiLevel).rawValue
            phase = .playing
        }
    }

    // MARK: - 公開状態

    /// 各プレイヤーの手札（開始前は空）。
    public var hands: [[OldMaidCard]] { game?.hands ?? Array(repeating: [], count: Self.playerCount) }

    /// あなたの手札（表示順）。
    public var playerHand: [OldMaidCard] { hands[Self.humanIndex] }

    /// いまの番の人。
    public var currentPlayer: Int { game?.currentPlayer ?? Self.humanIndex }

    /// あなたが引く番か。
    public var isPlayerTurn: Bool {
        phase == .playing && game?.isOver == false && currentPlayer == Self.humanIndex
    }

    /// あなたが引く相手（あなたの番のときだけ）。
    public var humanTarget: Int? { isPlayerTurn ? game?.currentTarget : nil }

    /// あなたから引く人（ジョーカーの置き場所を見ている CPU）。決着後・あなたが抜けたあとは nil。
    public var humanDrawer: Int? {
        guard let game, !game.isOver, !game.hands[Self.humanIndex].isEmpty else { return nil }
        return (1..<Self.playerCount).map { (Self.humanIndex - $0 + Self.playerCount) % Self.playerCount }
            .first { !game.hands[$0].isEmpty }
    }

    /// いま引こうとしている札を選べているか。
    public var canDraw: Bool {
        guard isPlayerTurn, let selectedID, let target = humanTarget else { return false }
        return hands[target].contains { $0.id == selectedID }
    }

    /// 手札を混ぜられるか（対局中で 2 枚以上あるとき。CPU の番でもよい）。
    public var canShuffle: Bool { phase == .playing && playerHand.count > 1 }

    /// `player` の顔。あなたが札に指をかけている相手だけが顔に出ることがある。
    public func face(of player: Int) -> OldMaidFace {
        guard let game, player == humanTarget else { return .neutral }
        return game.face(of: player, touching: selectedID)
    }

    /// あなたが直前に引いて手札に入れた札（ペアで捨てた札は除く）。手札で目印を付ける。
    public var lastDrawnCardID: Int? {
        guard let transfer = game?.lastTransfer, transfer.to == Self.humanIndex, !transfer.paired else { return nil }
        return playerHand.contains(transfer.card) ? transfer.card.id : nil
    }

    /// あなたがジョーカーを持っていて、その場所が見られているか（「シャッフル」を勧める）。
    public var isJokerWatched: Bool {
        phase == .playing && game?.humanJokerWatched == true && playerHand.contains(where: \.isJoker)
    }

    /// あなたの順位（0 始まり）。抜けていなければ nil。
    public var playerPlace: Int? { game?.ranking.firstIndex(of: Self.humanIndex) }

    /// 負けた人（ジョーカーを持って残った人）。決着前は nil。
    public var loser: Int? { game?.loser }

    /// 評価リクエスト（#53）・記録の判定用。最後にジョーカーを持って残ったら負け、それ以外は勝ち。
    public var reviewOutcome: GameOutcome { loser == Self.humanIndex ? .loss : .win }

    public func playerName(_ index: Int) -> String {
        index == Self.humanIndex ? tr("あなた") : "CPU\(index)"
    }

    // MARK: - ゲーム開始

    /// 新しい 1 ゲームを始める。`aiLevel` を渡すとその強さで配る（開始シート・難易度の階段）。
    public func startGame(aiLevel newLevel: Int? = nil) {
        if let newLevel { aiLevel = CPUStrength.strength(for: newLevel).rawValue }
        var deck = OldMaidCard.makeDeck()
        deck.shuffle(using: &generator)
        gameNumber += 1
        // 最初に配られ、最初に引く人はゲームごとに 1 人ずつ回す（1 ゲーム目はあなた）。
        let first = (gameNumber - 1) % Self.playerCount
        game = OldMaidGame(deck: deck, firstPlayer: first, aiLevel: aiLevel, tellSeed: generator.next())
        selectedID = nil
        recordResult = nil
        isUntouchedDeal = true
        phase = .playing

        services?.feedback.impact(.card(.shuffle))   // 札が切られて配られた
        // 1 ゲーム = 1 プレイ。中断からの復元は init が状態を戻すだけでここを通らないので数えない（#158）。
        services?.gameDidRestart(gameID: gameID, level: CPUStrength.analyticsLevel(forLevel: aiLevel))
        // 配っただけで決着・あなたが抜けた（ペアだけで手札が尽きた）ときは、そのまま決着まで進める。
        settleIfHumanOut()
        persist()
    }

    // MARK: - あなたの操作

    /// 引く相手の札に指をかける。同じ札をもう一度タップすると指を離す。
    public func toggleSelection(_ cardID: Int) {
        guard isPlayerTurn, let target = humanTarget, hands[target].contains(where: { $0.id == cardID }) else { return }
        selectedID = selectedID == cardID ? nil : cardID
        services?.feedback.impact(.rigid)
    }

    /// 指をかけている札を引く。ペアができれば捨てる。
    public func drawSelected() {
        guard canDraw, let selectedID, var next = game else {
            services?.feedback.notify(.warning)
            return
        }
        guard next.draw(cardID: selectedID) else { return }
        game = next
        self.selectedID = nil
        isUntouchedDeal = false
        // あなたが札を引いた = 盤面が動いた。配っただけの局面を捨てても離脱には数えない境目（#500）。
        services?.gameDidProgress(gameID: gameID)
        if let transfer = next.lastTransfer {
            if transfer.card.isJoker {
                services?.feedback.notify(.warning)   // ジョーカーを引いてしまった
            } else {
                services?.feedback.impact(transfer.paired ? .card(.place) : .card(.deal))
            }
        }
        settleIfHumanOut()
        persist()
    }

    /// あなたの手札の並びを混ぜる。ジョーカーの置き場所を CPU に覚えられなくなる。
    public func shuffleHand() {
        guard canShuffle, var next = game else { return }
        next.shuffleHand(of: Self.humanIndex, using: &generator)
        game = next
        services?.feedback.impact(.card(.shuffle))
        persist()
    }

    /// 決着していれば締め、あなたが抜けていれば残りの CPU だけで決着まで進めて締める。
    ///
    /// あなたが抜けたあとの CPU 同士の引き合いを 1 枚ずつ見せても待たされるだけなので、その場で済ませて
    /// 順位を出す（負けた CPU はリザルトに出る）。
    private func settleIfHumanOut() {
        guard var next = game else { return }
        if !next.isOver, next.hands[Self.humanIndex].isEmpty {
            // 合法な手しか指さず必ず 1 枚ずつ進む。万一の無限ループを避ける上限（実測で 1 局 200 回程度）。
            var steps = 0
            while !next.isOver, steps < 10_000, next.performCPUTurn(using: &generator) { steps += 1 }
            game = next
        }
        if next.isOver { concludeGame() }
    }

    // MARK: - CPU

    /// CPU の手番を起こす `.task(id:)` の識別子（#3146）。あなたの操作・CPU の着手・新しいゲームのたびに必ず変わる
    /// （`turnSerial` は引くたびに増える手数。配り直しは `gameNumber` で区別する）。
    public var cpuTurnKey: AITurnKey { AITurnKey(gameSerial: gameNumber, ply: game?.turnSerial ?? 0) }

    /// CPU の手番が続く限り進める。あなたの番になるか決着したら止まる。
    /// View から複数の契機で呼ばれても内部で 1 本に制限する（`withAITurnRunner`・#531）。
    public func runCPUTurnsIfNeeded() async {
        await withAITurnRunner(running: \.isRunningCPUTurns) {
            while phase == .playing, let game, !game.isOver, game.currentPlayer != Self.humanIndex {
                // 間合いが 0 の手番には suspend が無く、下の sleep 後の判定を通らない。ループ先頭でも見る（#287）。
                guard !Task.isCancelled else { return }
                if cpuDelay > .zero {
                    // sleep の直後にキャンセルを見る。見ないと画面を離れた瞬間に残りの手番が間合いゼロで走り抜ける（#287）。
                    guard await pauseCPUTurn(for: cpuDelay) else { return }
                    guard phase == .playing, self.game?.isOver == false,
                          self.game?.currentPlayer != Self.humanIndex else { return }
                }
                performCPUTurn()
            }
        }
    }

    /// CPU の 1 手。CPU の着手では触覚を鳴らさない（あなたの操作と区別するため）。
    /// ただし、あなたの手札から引かれたときだけは知らせる（何かが手から抜けたことに気づけるように）。
    private func performCPUTurn() {
        guard var next = game, next.performCPUTurn(using: &generator) else { return }
        game = next
        isUntouchedDeal = false   // 保存はする（CPU の初手も復元できるように）。続き扱いにはならない（#3000）
        if next.lastTransfer?.from == Self.humanIndex {
            services?.feedback.impact(.light)
        }
        settleIfHumanOut()
        persist()
    }

    /// 決着で記録に渡す点。**「ふつう」は区分なし**（それまでの記録をそのまま引き継ぐ）で、
    /// それ以外の強さは強さ別の区分に分ける（大富豪と同じ作法・#2604、#2716）。
    var recordScore: GameScore {
        let strength = CPUStrength.strength(for: aiLevel)
        guard strength != .standard else { return GameScore(metric: .winLoss) }
        let variant = strength.recordVariantKey
        return GameScore(
            metric: .winLoss, variant: variant,
            variantLabel: RecordVariantLabels.stored(gameID: gameID, variant: variant)
        )
    }

    private func concludeGame() {
        guard phase == .playing else { return }
        selectedID = nil
        phase = .result
        switch reviewOutcome {
        case .win:  services?.feedback.notify(.success)
        case .loss: services?.feedback.notify(.error)
        case .draw: services?.feedback.notify(.warning)
        }
        recordResult = services?.gameDidFinish(
            gameID: gameID, outcome: reviewOutcome, score: recordScore,
            // 「入門」「かんたん」に勝っても評価を頼むほどの手応えとは言えない（#1471）。
            isReviewHighlight: CPUStrength.isReviewWorthy(level: aiLevel)
        )
        services?.snapshots.clear(for: gameID)
    }

    // MARK: - テスト用

    /// テスト専用: 配りの乱数に依存せず任意の局面から検証するための組み立て口。
    /// `internal` なのでアプリからは呼べない（`@testable import` からのみ見える）。
    func configureForTesting(_ configured: OldMaidGame, gameNumber: Int = 1) {
        game = configured
        aiLevel = configured.aiLevel
        self.gameNumber = gameNumber
        selectedID = nil
        recordResult = nil
        isUntouchedDeal = false
        phase = configured.isOver ? .result : .playing
        persist()
    }

    #if DEBUG
    /// 撮影・動作確認用（Release には残らない）。`-oldMaidScenario <name>` で局面を差し替える。
    ///
    /// - `tell`: あなたの番。CPU1 がジョーカーを持ち、入門の強さでジョーカーに指をかけている（にやり顔）
    /// - `watched`: あなたが引いたジョーカーが右端にあり、見られている（シャッフルの案内が出る）
    /// - `result`: あなたが 1 位で抜け、CPU3 が負けたリザルト
    public func applyDebugScenario(_ name: String) {
        func card(_ suit: OldMaidSuit, _ rank: Int) -> OldMaidCard {
            OldMaidCard(id: suit.rawValue * 13 + rank - 1, suit: suit, rank: rank)
        }
        // 53 枚の整合を取るため、手札に出さない札はペアで捨て札に入れる（手札の各数字は 2 枚ずつにしてある）。
        func scenario(_ hands: [[OldMaidCard]], currentPlayer: Int, level: CPUStrength,
                      watched: Bool = false) -> OldMaidGame {
            let used = Set(hands.flatMap { $0 })
            let rest = OldMaidCard.makeDeck().filter { !used.contains($0) && !$0.isJoker }
            let pairs = (1...13).flatMap { rank -> [[OldMaidCard]] in
                let same = rest.filter { $0.rank == rank }
                return stride(from: 0, to: same.count - 1, by: 2).map { [same[$0], same[$0 + 1]] }
            }
            return OldMaidGame(hands: hands, discardedPairs: pairs, currentPlayer: currentPlayer,
                               aiLevel: level.rawValue, tellSeed: 3, humanJokerWatched: watched)
        }
        switch name {
        case "tell":
            configureForTesting(scenario([
                [card(.spades, 2), card(.hearts, 5), card(.clubs, 9), card(.diamonds, 12)],
                [card(.hearts, 2), OldMaidCard.joker, card(.spades, 9), card(.clubs, 7)],
                [card(.clubs, 5), card(.spades, 7), card(.hearts, 11)],
                [card(.diamonds, 11), card(.clubs, 12)],
            ], currentPlayer: Self.humanIndex, level: .novice))
            selectedID = OldMaidCard.jokerID
        case "watched":
            configureForTesting(scenario([
                [card(.spades, 2), card(.hearts, 5), card(.clubs, 9), OldMaidCard.joker],
                [card(.hearts, 2), card(.spades, 9), card(.clubs, 7)],
                [card(.clubs, 5), card(.spades, 7), card(.hearts, 11)],
                [card(.diamonds, 11)],
            ], currentPlayer: 1, level: .hard, watched: true))
        case "result":
            configureForTesting(scenario([
                [card(.spades, 4)],
                [card(.hearts, 4)],
                [card(.clubs, 6)],
                [card(.spades, 6), OldMaidCard.joker],
            ], currentPlayer: Self.humanIndex, level: .normal))
            selectedID = card(.hearts, 4).id
            drawSelected()
        case "crowded":
            // 縦の短い画面の確認用: あなたの手札 14 枚（ジョーカー込み）と、引く相手の伏せ札 13 枚（2 段）。
            configureForTesting(scenario([
                (1...13).map { card(.spades, $0) } + [OldMaidCard.joker],
                (1...13).map { card(.hearts, $0) },
                [card(.clubs, 1), card(.clubs, 2)],
                [card(.diamonds, 1), card(.diamonds, 2)],
            ], currentPlayer: Self.humanIndex, level: .normal))
        default:
            break
        }
    }
    #endif

    // MARK: - 永続化

    private func persist() {
        // 配ったばかりの盤面は保存しない（#240）。開始してすぐ閉じただけでハブに「続きから」が付くと、
        // バッジが「途中の対局がある」という意味を持たなくなる。
        guard phase == .playing, !isUntouchedDeal, let game, !game.isOver else {
            services?.snapshots.clear(for: gameID)
            return
        }
        try? services?.snapshots.save(OldMaidSnapshot(game: game, gameNumber: gameNumber), for: gameID)
    }
}
