import Core
import Observation

/// 15 パズルのゲーム状態。盤面と手数を保持し、永続化サービスへ中断スナップショットを書く。
/// 純粋ロジックは `FifteenLogic` に委譲し、ここは乱数生成・永続化・決着管理のみ担う。
@MainActor
@Observable
public final class FifteenModel {
    public private(set) var tiles: [Int]
    /// 動かしたタイルの枚数。まとめて寄せたときは枚数ぶん増える。
    public private(set) var moves: Int
    public private(set) var isSolved: Bool
    /// 直近の決着で確定した自己ベスト。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?

    private let services: GameServices?
    /// 同じモジュールの View も参照する。
    let gameID = "fifteen"
    private var generator: SplitMix64?

    /// services を渡すと、中断スナップショットがあれば復元、無ければ新規開始する。
    /// `seed` を渡すと配置を種から決める（テスト用。省略時はシステム乱数）。
    public init(services: GameServices? = nil, seed: UInt64? = nil) {
        self.services = services
        generator = seed.map { SplitMix64(seed: $0) }
        if let snap = services?.snapshots.load(FifteenSnapshot.self, for: gameID),
           FifteenLogic.isSolvable(snap.tiles), !FifteenLogic.isSolved(snap.tiles), snap.moves >= 0 {
            tiles = snap.tiles
            moves = snap.moves
            isSolved = false
        } else {
            tiles = []
            moves = 0
            isSolved = false
            tiles = makeBoard()
            // 中断からの復元は「新しいプレイ」ではないので開始は数えない。
            services?.gameDidStart(gameID: gameID)
        }
        persist()
    }

    /// 盤面を直接与えて開始する。狙った局面（あと 1 手で揃う盤など）から検証するためのテスト用の経路。
    public init(services: GameServices? = nil, tiles: [Int], moves: Int = 0) {
        self.services = services
        self.tiles = tiles
        self.moves = moves
        isSolved = FifteenLogic.isSolved(tiles)
        persist()
    }

    /// `index` のタイルをタップする。空白と同じ行・列になければ何も動かさない。
    public func tap(at index: Int) {
        guard !isSolved else { return }
        guard let result = FifteenLogic.slide(tiles, at: index) else {
            services?.feedback.notify(.warning)
            return
        }
        tiles = result.tiles
        moves += result.distance
        // 盤が動いた = 捨てたら途中離脱として数える盤面。
        services?.gameDidProgress(gameID: gameID)
        if FifteenLogic.isSolved(tiles) {
            isSolved = true
            services?.feedback.notify(.success)
            // 決着 1 回につき `gameDidFinish` は 1 回だけ呼ぶ。
            recordResult = services?.gameDidFinish(
                gameID: gameID,
                outcome: .win,
                score: GameScore(metric: .fewestMoves, moves: moves)
            )
            services?.snapshots.clear(for: gameID)
        } else {
            services?.feedback.impact(.light)
            persist()
        }
    }

    /// 「リセット」で失われる進行があるか（#1011）。1 手も動かしていない盤と解き終えた盤は捨てて構わない。
    public var hasProgressToLose: Bool { moves > 0 && !isSolved }

    /// 新規ゲーム。
    public func newGame() {
        tiles = makeBoard()
        moves = 0
        isSolved = false
        recordResult = nil
        persist()
        services?.gameDidRestart(gameID: gameID)
    }

    private func makeBoard() -> [Int] {
        if var seeded = generator {
            defer { generator = seeded }
            return FifteenLogic.shuffled(using: &seeded)
        }
        var system = SystemRandomNumberGenerator()
        return FifteenLogic.shuffled(using: &system)
    }

    private func persist() {
        guard !isSolved else { return }
        try? services?.snapshots.save(FifteenSnapshot(tiles: tiles, moves: moves), for: gameID)
    }
}
