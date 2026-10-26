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

    /// この局のヒントの残り（#1975）。回数と順位表の扱いは Core の `BoardHintBudget`（将棋・チェス・五目並べ・オセロと共通）。
    public private(set) var hints = BoardHintBudget()
    /// ヒントが示している升（動かすタイルがいま居る位置）。盤が動けば消える。**永続化しない**。
    public private(set) var hintIndex: Int?
    /// 局の番号。広告を見ているあいだに新規ゲームが始まったら、報酬を新しい局へ乗せない。
    public private(set) var gameSerial = 0

    private let services: GameServices?
    /// 同じモジュールの View も参照する。
    let gameID = "fifteen"
    private var generator: SplitMix64?

    /// 盤の一辺のマス数（3・4・5）。盤の長さから決まる。
    public var size: Int { FifteenLogic.size(ofCellCount: tiles.count) ?? FifteenLogic.defaultSize }

    /// 記録の区分キー（#2869）。4×4 は従来の保存先（区分なし）、3×3 と 5×5 は大きさで分ける（`RecordVariantLabels` の `fifteen`）。
    public static func recordVariant(size: Int) -> String? {
        size == FifteenLogic.defaultSize ? nil : "\(size)x\(size)"
    }

    /// ヘッダーに出す保存済みの自己ベスト手数（#2615）。盤の大きさごとの記録を引く。記録が無いときは nil（出さない）。
    var savedBestMoves: Int? {
        services?.playLog?.record(gameID: gameID, variant: Self.recordVariant(size: size))?.fewestMoves
    }

    /// services を渡すと、中断スナップショットがあれば復元、無ければ新規開始する。
    /// `seed` を渡すと配置を種から決める（テスト用。省略時はシステム乱数）。
    /// `size` は新規開始する盤の一辺（3〜5。範囲外は 4）。中断データがあればその大きさで復元する。
    public init(services: GameServices? = nil, seed: UInt64? = nil, size: Int = FifteenLogic.defaultSize) {
        self.services = services
        generator = seed.map { SplitMix64(seed: $0) }
        if let snap = services?.snapshots.load(FifteenSnapshot.self, for: gameID),
           FifteenLogic.isSolvable(snap.tiles), !FifteenLogic.isSolved(snap.tiles), snap.moves >= 0 {
            tiles = snap.tiles
            moves = snap.moves
            isSolved = false
            hints = BoardHintBudget(used: snap.hintsUsed ?? 0)
        } else {
            tiles = []
            moves = 0
            isSolved = false
            tiles = makeBoard(size: FifteenLogic.sizes.contains(size) ? size : FifteenLogic.defaultSize)
            // 中断からの復元は「新しいプレイ」ではないので開始は数えない。
            services?.gameDidStart(gameID: gameID)
        }
        persist()
    }

    /// 盤面を直接与えて開始する。狙った局面（あと 1 手で揃う盤など）から検証するためのテスト用の経路。
    public init(services: GameServices? = nil, tiles: [Int], moves: Int = 0, hintsUsed: Int = 0) {
        self.services = services
        self.tiles = tiles
        self.moves = moves
        hints = BoardHintBudget(used: hintsUsed)
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
        hintIndex = nil
        // 盤が動いた = 捨てたら途中離脱として数える盤面。
        services?.gameDidProgress(gameID: gameID)
        if FifteenLogic.isSolved(tiles) {
            isSolved = true
            services?.feedback.notify(.success)
            // 決着 1 回につき `gameDidFinish` は 1 回だけ呼ぶ。
            recordResult = services?.gameDidFinish(
                gameID: gameID,
                outcome: .win,
                score: GameScore(
                    metric: .fewestMoves, moves: moves,
                    variant: Self.recordVariant(size: size),
                    variantLabel: Self.recordVariant(size: size).map { RecordVariantLabels.stored(gameID: gameID, variant: $0) },
                    isLeaderboardEligible: !hints.wasUsed
                )
            )
            services?.snapshots.clear(for: gameID)
        } else {
            services?.feedback.impact(.light)
            persist()
        }
    }

    /// 「リセット」で失われる進行があるか（#1011）。1 手も動かしていない盤と解き終えた盤は捨てて構わない。
    public var hasProgressToLose: Bool { moves > 0 && !isSolved }

    /// 新規ゲーム。`size` を渡すとその大きさで始める（盤の大きさの切り替え・#2869）。
    public func newGame(size newSize: Int? = nil) {
        tiles = makeBoard(size: newSize.flatMap { FifteenLogic.sizes.contains($0) ? $0 : nil } ?? size)
        moves = 0
        isSolved = false
        recordResult = nil
        hints.reset()
        hintIndex = nil
        gameSerial += 1
        persist()
        services?.gameDidRestart(gameID: gameID)
    }

    // MARK: - ヒント（#1975）

    /// 残り回数（無料 + 広告の合計）。
    public var hintsRemaining: Int { hints.remaining }

    /// いまヒントを押せるか。決着前で、合計の残りがあるときだけ。
    public var canUseHint: Bool { !isSolved && !hints.isExhausted }

    /// 無料枠を使い切っていて、次の 1 回に広告が要るか。
    public var needsAdForHint: Bool { !hints.hasFreeRemaining && !hints.isExhausted }

    /// 無料のヒントを 1 回使い、次に動かすタイルを盤の上に示す。求まらなければ**回数を減らさない**。
    public func requestHint() {
        guard canUseHint, !needsAdForHint, let index = FifteenHintSolver.nextIndex(tiles), hints.consume() else { return }
        didUseHint(at: index)
    }

    /// 広告を最後まで見たあとの 1 回。`game` は広告を出す前に控えた `gameSerial`（局が入れ替わっていたら適用せず false）。
    public func grantAdHint(forGame game: Int) -> Bool {
        guard game == gameSerial, canUseHint, needsAdForHint,
              let index = FifteenHintSolver.nextIndex(tiles), hints.consumeAd() else { return false }
        didUseHint(at: index)
        return true
    }

    private func didUseHint(at index: Int) {
        services?.gameDidUseHint(gameID: gameID)
        hintIndex = index
        services?.feedback.impact(.light)
        // 残り回数は中断データに持ち回る（再開でヒントが戻らないように）。
        persist()
    }

    private func makeBoard(size: Int) -> [Int] {
        if var seeded = generator {
            defer { generator = seeded }
            return FifteenLogic.shuffled(size: size, using: &seeded)
        }
        var system = SystemRandomNumberGenerator()
        return FifteenLogic.shuffled(size: size, using: &system)
    }

    private func persist() {
        guard !isSolved else { return }
        try? services?.snapshots.save(FifteenSnapshot(tiles: tiles, moves: moves, hintsUsed: hints.used), for: gameID)
    }
}
