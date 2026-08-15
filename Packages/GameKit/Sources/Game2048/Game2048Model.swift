import Core
import Observation

/// 2048 のゲーム状態。盤面・スコア・終局を保持し、永続化サービスへ中断スナップショットを書く。
/// 純粋ロジックは `Game2048Logic` に委譲し、ここは乱数生成・永続化・終局管理のみ担う。
@MainActor
@Observable
public final class Game2048Model {
    public private(set) var board: [[Int]]
    public private(set) var score: Int
    public private(set) var gameOver: Bool
    public private(set) var continueUsed: Bool = false
    /// 直近の終局で確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?

    private let services: GameServices?
    private let gameID = "2048"

    /// services を渡すと、中断スナップショットがあれば復元、無ければ新規開始する。
    public init(services: GameServices? = nil) {
        self.services = services
        var initialBoard: [[Int]]
        var initialScore: Int
        if let snap = services?.snapshots.load(Game2048Snapshot.self, for: gameID) {
            initialBoard = snap.board
            initialScore = snap.score
            // 再起動でコンティニュー権が復活しないよう、使用済みフラグも復元する。
            continueUsed = snap.continueUsed
        } else {
            initialBoard = Game2048Logic.emptyBoard()
            initialScore = 0
            // 初期タイル 2 個。
            Self.spawn(into: &initialBoard)
            Self.spawn(into: &initialBoard)
        }
        board = initialBoard
        score = initialScore
        gameOver = Game2048Logic.isGameOver(initialBoard)
        persist()
    }

    /// 盤面を直接与えて開始する。初期タイルの乱数生成と中断スナップショットの復元を
    /// 経由しないので、狙った局面（1マスも動かない方向がある盤面など）から検証できる。
    /// テスト用の経路で、`init(services:)` の挙動には影響しない。
    public init(services: GameServices? = nil, board: [[Int]], score: Int = 0) {
        self.services = services
        self.board = board
        self.score = score
        gameOver = Game2048Logic.isGameOver(board)
        persist()
    }

    /// 指定方向へスライド。動いたときのみ新タイルを生成し、終局判定・永続化する。
    public func move(_ direction: Direction) {
        guard !gameOver else { return }
        let result = Game2048Logic.slide(board, direction)
        guard result.moved else {
            services?.feedback.notify(.warning) // 1マスも動かない方向へのスワイプ
            return
        }

        board = result.board
        score += result.gained
        Self.spawn(into: &board)

        if Game2048Logic.isGameOver(board) {
            gameOver = true
            services?.feedback.notify(.error)
            // 2048 に勝ちは無いので、記録するのはスコアと到達した最大タイル。
            let highestTile: Int? = board.flatMap { $0 }.max()
            recordResult = services?.gameDidFinish(
                gameID: gameID,
                outcome: .loss,
                score: GameScore(metric: .points, points: score, highestValue: highestTile)
            )
            services?.snapshots.clear(for: gameID) // 終局でスナップショット破棄
        } else {
            services?.feedback.impact(result.gained > 0 ? .medium : .light)
            persist()
        }
    }

    /// リワード広告視聴後にコンティニュー。盤面・スコアを保持したまま再開。1回のみ使用可。
    public func continueAfterAd() {
        guard gameOver, !continueUsed else { return }
        // 同じ盤面・同じスコアの続きなので、直前に記録した「負け」は無かったことにする
        // （そのままだと1回のプレイが2回分として数えられる）。到達済みのスコアは取り消さない。
        services?.playLog?.cancelLoss(gameID: gameID)
        recordResult = nil
        gameOver = false
        continueUsed = true
        // 終局盤面は必ず全埋まりなので、ここで新タイルを置こうとしても空振りする（それが #122 の不具合）。
        // 最小値のタイルを消して空きマスを確保し、確実に続きを遊べる盤面で再開する。新タイルは置かない
        // （コンティニューは手番ではないうえ、せっかく確保した空きマスを潰して続行手数を削るだけのため）。
        board = Game2048Logic.revive(board)
        persist()
    }

    /// 新規ゲーム。
    public func newGame() {
        board = Game2048Logic.emptyBoard()
        score = 0
        gameOver = false
        continueUsed = false
        recordResult = nil
        Self.spawn(into: &board)
        Self.spawn(into: &board)
        persist()
    }

    private func persist() {
        guard !gameOver else { return }
        try? services?.snapshots.save(
            Game2048Snapshot(board: board, score: score, continueUsed: continueUsed),
            for: gameID
        )
    }

    /// 空きマスへランダムに 2(90%)/4(10%) を 1 個置く。
    private static func spawn(into board: inout [[Int]]) {
        let cells = Game2048Logic.emptyCells(board)
        guard let cell = cells.randomElement() else { return }
        board[cell.row][cell.col] = Int.random(in: 0..<10) == 0 ? 4 : 2
    }
}
