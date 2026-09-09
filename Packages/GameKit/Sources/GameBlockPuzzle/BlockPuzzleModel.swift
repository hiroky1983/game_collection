import Core
import Observation

/// ブロックならべ（#493）のゲーム状態。
///
/// 盤の判定・得点・手札生成は `BlockPuzzleBoard` / `BlockPuzzleScoring` の純粋ロジックに委譲し、
/// ここは乱数・永続化・終局管理と、横断サービス（記録・解析・レコメンド）への通知だけを担う。
/// 2048 と同じハイスコア型で、決着は「置ける形が無くなった 1 回」だけ。
@MainActor
@Observable
public final class BlockPuzzleModel {
    /// 盤（0 = 空きマス、1...5 = 色番号）。
    public private(set) var board: [[Int]]
    /// 手元の 3 スロット。置いたスロットは nil になり、3 つとも空くと配り直す。
    public private(set) var hand: [BlockPuzzlePiece?]
    public private(set) var score: Int
    /// 連続で消している回数（消さない手を指すと 0 に戻る）。次に消したときの倍率になる。
    public private(set) var combo: Int
    public private(set) var gameOver: Bool
    /// コンティニュー（リワード広告による復活）を使い切っているか。1 局につき 1 回まで。
    public private(set) var continueUsed: Bool
    /// 直前の 1 手で消えた本数。0 なら消えていない。消えた瞬間の表示にだけ使う。
    public private(set) var lastClearedLines: Int = 0
    /// 消すたびに 1 増える通し番号。**表示側のトランジションを毎回再生させるため**の nonce。
    ///
    /// `lastClearedLines` は「2本消し」が連続すると値が変わらず、`if lastClearedLines > 0 { … }`
    /// の分岐は真のまま保たれるので SwiftUI の `.transition` は初回しか飛び出さない
    /// （将棋の `checkBannerID` と同じ理由・同じ対処）。
    public private(set) var clearEventID: Int = 0
    /// 直近の終局で確定した自己ベスト（#115）。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?

    private let services: GameServices?
    private var rng: BlockPuzzleRandom
    static let gameID = "blockpuzzle"

    /// 通常の入口。中断スナップショットがあれば復元し、無ければ新規開始する。
    public convenience init(services: GameServices? = nil) {
        self.init(services: services, seed: UInt64.random(in: UInt64.min...UInt64.max), restoring: true)
    }

    /// 種を固定して開始する。ピースの並びが再現できるのでテスト・プレビューから使う。
    /// `restoring` を false にすると中断スナップショットを読まず、必ず新規開始になる。
    public init(services: GameServices? = nil, seed: UInt64, restoring: Bool = false) {
        self.services = services
        // 全プロパティが埋まるまで `self` には触れないので、初期化中はローカルの乱数を回す。
        var generator = BlockPuzzleRandom(seed: seed)

        var restored: (board: [[Int]], hand: [BlockPuzzlePiece?])?
        var restoredScore = 0
        var restoredCombo = 0
        var restoredContinueUsed = false
        if restoring, let snap = services?.snapshots.load(BlockPuzzleSnapshot.self, for: Self.gameID) {
            // 壊れた中断データは黙って捨てて新規開始に倒す（存在しない形を盤に戻さない）。
            restored = snap.validated()
            if restored != nil {
                restoredScore = snap.score
                restoredCombo = snap.combo
                restoredContinueUsed = snap.continueUsed
            }
        }

        if let restored {
            board = restored.board
            hand = restored.hand
            score = restoredScore
            combo = restoredCombo
            continueUsed = restoredContinueUsed
            // 詰んだ局面は保存されない（終局でスナップショットを消すため）が、外から書き換えられた
            // データを読んだときに「詰んでいるのに操作を受け付ける」状態にしないよう盤から確かめる。
            gameOver = BlockPuzzleBoard.isGameOver(restored.board, hand: restored.hand)
        } else {
            let newBoard = BlockPuzzleBoard.emptyBoard()
            board = newBoard
            hand = BlockPuzzleBoard.makeHand(board: newBoard, using: &generator).map { Optional($0) }
            score = 0
            combo = 0
            continueUsed = false
            gameOver = false
        }
        self.rng = generator

        persist()
        // 中断からの復元は「新しいプレイ」ではないので解析の開始は数えない（#158）。
        // 再描画で init が何度走っても `gameDidStart` は冪等なので増えない。
        if restored == nil { services?.gameDidStart(gameID: Self.gameID) }
    }

    /// 盤と手元を直接与えて開始する。狙った局面（あと 1 手で消える・詰み寸前）から検証するための入口。
    ///
    /// 中断スナップショットは読まないので、解析（#158）の上では**新しいプレイの開始**として数える
    /// （ブロック崩しの `init(startingAt:)` と同じ扱い）。
    public init(services: GameServices? = nil, board: [[Int]], hand: [BlockPuzzlePiece?], score: Int = 0, seed: UInt64 = 1) {
        self.services = services
        self.rng = BlockPuzzleRandom(seed: seed)
        self.board = board
        self.hand = hand
        self.score = score
        self.combo = 0
        self.continueUsed = false
        self.gameOver = BlockPuzzleBoard.isGameOver(board, hand: hand)
        persist()
        services?.gameDidStart(gameID: Self.gameID)
    }

    /// 手元 `index` のピースを、左上が (row, col) に来るように置く。
    ///
    /// - Returns: 置けたら true。置けない位置・使用済みスロット・終局後は false（拒否として鳴らす）。
    @discardableResult
    public func place(pieceIndex index: Int, row: Int, col: Int) -> Bool {
        guard !gameOver, hand.indices.contains(index), let piece = hand[index],
              let placed = BlockPuzzleBoard.place(board, piece, row: row, col: col) else {
            services?.feedback.notify(.warning)
            return false
        }

        score += BlockPuzzleScoring.placementPoints(piece)
        hand[index] = nil

        let cleared = BlockPuzzleBoard.clearLines(placed)
        board = cleared.board
        lastClearedLines = cleared.lines
        if cleared.lines > 0 {
            clearEventID += 1
            combo += 1
            score += BlockPuzzleScoring.clearPoints(lines: cleared.lines, combo: combo)
            services?.feedback.impact(.medium)
        } else {
            combo = 0
            services?.feedback.impact(.light)
        }

        // 3 つとも置いたら配り直す。**消去のあとに配る**ので、空いた盤に合わせた救済が効く。
        if hand.allSatisfy({ $0 == nil }) {
            hand = BlockPuzzleBoard.makeHand(board: board, using: &rng).map { Optional($0) }
        }

        if BlockPuzzleBoard.isGameOver(board, hand: hand) {
            finish()
        } else {
            persist()
        }
        return true
    }

    /// リワード広告視聴後のコンティニュー。盤の中央を空けて、同じスコアのまま続ける。1 局 1 回のみ。
    public func continueAfterAd() {
        guard gameOver, !continueUsed else { return }
        // 同じ局の続きなので、直前に記録した「負け」は無かったことにする
        // （そのままだと 1 回のプレイが 2 回分として数えられる）。
        services?.playLog?.cancelLoss(gameID: Self.gameID)
        recordResult = nil
        gameOver = false
        continueUsed = true
        // 中央 5×5 を空けるとカタログのどの形も置けるので、手元は配り直さずそのまま続けられる。
        board = BlockPuzzleBoard.revive(board)
        combo = 0
        lastClearedLines = 0
        persist()
        // `game_end` はもう送信済みなので、続きは次の 1 プレイとして数える（#158）。
        services?.gameDidRestart(gameID: Self.gameID)
    }

    /// 新規ゲーム。
    public func newGame() {
        board = BlockPuzzleBoard.emptyBoard()
        hand = BlockPuzzleBoard.makeHand(board: board, using: &rng).map { Optional($0) }
        score = 0
        combo = 0
        lastClearedLines = 0
        gameOver = false
        continueUsed = false
        recordResult = nil
        persist()
        services?.gameDidRestart(gameID: Self.gameID)
    }

    private func finish() {
        gameOver = true
        services?.feedback.notify(.error)
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: .loss,
            score: GameScore(
                metric: .points,
                points: score,
                // コンティニューを使った回は世界の順位表へ送らない（#406 と同じ考え方）。
                // 広告を見た回数で順位が決まる表にしないため。手元の自己ベストには残す。
                isLeaderboardEligible: !continueUsed
            )
        )
        services?.snapshots.clear(for: Self.gameID)
    }

    private func persist() {
        guard !gameOver else { return }
        try? services?.snapshots.save(
            BlockPuzzleSnapshot(
                board: board,
                hand: hand.map { $0?.id },
                score: score,
                combo: combo,
                continueUsed: continueUsed
            ),
            for: Self.gameID
        )
    }
}
