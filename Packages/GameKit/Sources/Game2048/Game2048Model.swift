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

    /// 指定方向へスライド。動いたときのみ新タイルを生成し、終局判定・永続化する。
    public func move(_ direction: Direction) {
        guard !gameOver else { return }
        let result = Game2048Logic.slide(board, direction)
        guard result.moved else { return }

        board = result.board
        score += result.gained
        Self.spawn(into: &board)

        if Game2048Logic.isGameOver(board) {
            gameOver = true
            services?.snapshots.clear(for: gameID) // 終局でスナップショット破棄
        } else {
            persist()
        }
    }

    /// リワード広告視聴後にコンティニュー。盤面・スコアを保持したまま再開。1回のみ使用可。
    public func continueAfterAd() {
        guard gameOver, !continueUsed else { return }
        gameOver = false
        continueUsed = true
        Self.spawn(into: &board)
        persist()
    }

    /// 新規ゲーム。
    public func newGame() {
        board = Game2048Logic.emptyBoard()
        score = 0
        gameOver = false
        continueUsed = false
        Self.spawn(into: &board)
        Self.spawn(into: &board)
        persist()
    }

    private func persist() {
        guard !gameOver else { return }
        try? services?.snapshots.save(Game2048Snapshot(board: board, score: score), for: gameID)
    }

    /// 空きマスへランダムに 2(90%)/4(10%) を 1 個置く。
    private static func spawn(into board: inout [[Int]]) {
        let cells = Game2048Logic.emptyCells(board)
        guard let cell = cells.randomElement() else { return }
        board[cell.row][cell.col] = Int.random(in: 0..<10) == 0 ? 4 : 2
    }
}
