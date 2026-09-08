import Testing
import Foundation
import Core
@testable import GameBlockPuzzle

/// 再起動をまたぐ挙動を、ファイルを触らずに再現するための中断データ置き場。
private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var store: [String: Data] = [:]
    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
    /// 壊れた中断データを流し込むための入口。
    func inject(_ data: Data, for gameID: String) { store[gameID] = data }
    func raw(for gameID: String) -> Data? { store[gameID] }
}

private func makeServices(_ store: MemorySnapshotStore = MemorySnapshotStore()) -> (GameServices, MemorySnapshotStore) {
    (GameServices(snapshots: store, ads: NoopAdService()), store)
}

/// カタログの添字。並びを変えると中断データが化けるので、テスト側でも位置を固定しておく。
private enum Catalog {
    static let single = BlockPuzzlePiece.catalog[0]        // 1×1
    static let bar3 = BlockPuzzlePiece.catalog[3]          // 横 3 マス
    static let column3 = BlockPuzzlePiece.catalog[4]       // 縦 3 マス
    static let square2 = BlockPuzzlePiece.catalog[9]       // 2×2
    static let square3 = BlockPuzzlePiece.catalog[10]      // 3×3
}

@Suite("ブロックならべ: カタログの位置（他のテストの前提）")
struct BlockPuzzleCatalogAssumptionTests {
    @Test("テストが名指ししている形が、その添字に入っている")
    func shapes() {
        #expect(Catalog.single.size == 1)
        #expect(Catalog.bar3.width == 3 && Catalog.bar3.height == 1)
        #expect(Catalog.column3.width == 1 && Catalog.column3.height == 3)
        #expect(Catalog.square2.width == 2 && Catalog.square2.height == 2)
        #expect(Catalog.square3.size == 9)
    }
}

@Suite("ブロックならべ: 1 手の進行")
@MainActor
struct BlockPuzzlePlacementTests {

    @Test("置くとマス数ぶんの点が入り、そのスロットが空く")
    func placementScores() {
        let (services, _) = makeServices()
        let model = BlockPuzzleModel(
            services: services,
            board: BlockPuzzleBoard.emptyBoard(),
            hand: [Catalog.square3, Catalog.single, Catalog.single]
        )
        #expect(model.place(pieceIndex: 0, row: 0, col: 0))
        #expect(model.score == 9)
        #expect(model.hand[0] == nil)
        #expect(model.hand[1] != nil, "他のスロットは残る")
        #expect(model.board[0][0] != 0 && model.board[2][2] != 0)
    }

    @Test("置けない位置は拒否され、盤もスコアも動かない")
    func rejectsInvalidPlacement() {
        let (services, _) = makeServices()
        let model = BlockPuzzleModel(
            services: services,
            board: BlockPuzzleBoard.emptyBoard(),
            hand: [Catalog.bar3, nil, nil]
        )
        #expect(!model.place(pieceIndex: 0, row: 0, col: 8), "右へはみ出す")
        #expect(!model.place(pieceIndex: 1, row: 0, col: 0), "使用済みスロット")
        #expect(!model.place(pieceIndex: 9, row: 0, col: 0), "存在しないスロット")
        #expect(model.score == 0)
        #expect(model.board.allSatisfy { $0.allSatisfy { $0 == 0 } })
    }

    @Test("行が揃うと消えて、消去点が加算される")
    func clearingRowScores() {
        var board = BlockPuzzleBoard.emptyBoard()
        for c in 3..<10 { board[4][c] = 1 }
        let (services, _) = makeServices()
        let model = BlockPuzzleModel(services: services, board: board, hand: [Catalog.bar3, Catalog.single, Catalog.single])

        #expect(model.place(pieceIndex: 0, row: 4, col: 0))
        #expect(model.board[4].allSatisfy { $0 == 0 }, "揃った行は消える")
        #expect(model.lastClearedLines == 1)
        // 配置点 3 + 消去点 10 × 連鎖 1。
        #expect(model.score == 13)
        #expect(model.combo == 1)
    }

    @Test("連鎖は消し続ける間だけ伸び、消さない手で 0 に戻る")
    func comboResets() {
        var board = BlockPuzzleBoard.emptyBoard()
        for c in 3..<10 { board[4][c] = 1 }
        for c in 3..<10 { board[5][c] = 1 }
        let (services, _) = makeServices()
        let model = BlockPuzzleModel(
            services: services, board: board,
            hand: [Catalog.bar3, Catalog.bar3, Catalog.single]
        )

        #expect(model.place(pieceIndex: 0, row: 4, col: 0))
        #expect(model.combo == 1)
        #expect(model.place(pieceIndex: 1, row: 5, col: 0))
        #expect(model.combo == 2)
        // 2 手目: 配置点 3 + 消去点 10 × 連鎖 2 = 23。1 手目の 13 と合わせて 36。
        #expect(model.score == 36)

        #expect(model.place(pieceIndex: 2, row: 0, col: 0), "何も消さない手")
        #expect(model.combo == 0)
        #expect(model.lastClearedLines == 0)
    }

    @Test("3 つ置くと次の 3 つが配られる")
    func refillsHand() {
        let (services, _) = makeServices()
        let model = BlockPuzzleModel(
            services: services,
            board: BlockPuzzleBoard.emptyBoard(),
            hand: [Catalog.single, Catalog.single, Catalog.single]
        )
        #expect(model.place(pieceIndex: 0, row: 0, col: 0))
        #expect(model.place(pieceIndex: 1, row: 0, col: 2))
        #expect(model.hand.compactMap { $0 }.count == 1, "まだ配り直さない")
        #expect(model.place(pieceIndex: 2, row: 0, col: 4))
        #expect(model.hand.compactMap { $0 }.count == 3, "3 つとも置いたら配り直す")
    }
}

@Suite("ブロックならべ: 決着とコンティニュー")
@MainActor
struct BlockPuzzleEndgameTests {

    /// あと 1 手で詰む盤。
    ///
    /// 空きは対角線上の 10 マスと (0, 2) の計 11 マスで、**どれも隣り合っていない**ので
    /// 1×1 しか置けない。(0, 2) に置いても 0 行目には (0, 0) が、2 列目には (2, 2) が残るため
    /// 行も列も揃わない（揃うと消えてしまい「詰み」の検証にならない）。
    private func makeAboutToLose() -> (BlockPuzzleModel, MemorySnapshotStore) {
        var board = Array(repeating: Array(repeating: 1, count: 10), count: 10)
        for i in 0..<10 { board[i][i] = 0 }
        board[0][2] = 0
        let (services, store) = makeServices()
        let model = BlockPuzzleModel(
            services: services, board: board,
            hand: [Catalog.single, Catalog.square3, Catalog.square3], score: 500
        )
        #expect(!model.gameOver, "前提: まだ 1×1 が置ける")
        return (model, store)
    }

    @Test("置ける形が無くなったらゲームオーバーになる")
    func gameOver() {
        let (model, store) = makeAboutToLose()
        #expect(model.place(pieceIndex: 0, row: 0, col: 2))
        #expect(model.lastClearedLines == 0, "前提: この手では何も消えない")
        #expect(model.gameOver)
        #expect(model.score == 501)
        #expect(!store.exists(for: "blockpuzzle"), "終局で中断データは破棄する")
    }

    @Test("終局後は置けない")
    func rejectsAfterGameOver() {
        let (model, _) = makeAboutToLose()
        model.place(pieceIndex: 0, row: 0, col: 2)
        let before = model.board
        #expect(!model.place(pieceIndex: 1, row: 3, col: 3))
        #expect(model.board == before)
    }

    @Test("コンティニューは中央を空けてスコアを保ち、1 局 1 回だけ使える")
    func continueOnce() {
        let (model, _) = makeAboutToLose()
        model.place(pieceIndex: 0, row: 0, col: 2)
        #expect(model.gameOver)

        model.continueAfterAd()
        #expect(!model.gameOver)
        #expect(model.continueUsed)
        #expect(model.score == 501, "スコアは引き継ぐ")
        for r in 2..<7 {
            for c in 2..<7 { #expect(model.board[r][c] == 0, "中央 5×5 が空いていない") }
        }
        #expect(model.hand.compactMap { $0 }.contains { BlockPuzzleBoard.canPlaceAnywhere(model.board, $0) },
                "復活直後は必ず置ける")
        #expect(model.hand.compactMap { $0 }.count == 2, "手元は配り直さずそのまま続ける")
    }

    /// 使い切ったあとに詰んだ局面を、中断データ経由で直接組み立てて確かめる。
    /// 盤を指し進めて 2 度目の詰みを作ると手順が長くなり、何を検証しているのか分からなくなるため。
    @Test("コンティニューは 1 局に 1 回だけ（使い切ったあとは効かない）")
    func continueOnlyOnce() {
        var stuck = Array(repeating: Array(repeating: 1, count: 10), count: 10)
        for i in 0..<10 { stuck[i][i] = 0 }   // 対角線だけ空き = 3×3 は置けない
        let store = MemorySnapshotStore()
        try? store.save(
            BlockPuzzleSnapshot(board: stuck, hand: [Catalog.square3.id, nil, nil],
                                score: 700, combo: 0, continueUsed: true),
            for: "blockpuzzle"
        )
        let model = BlockPuzzleModel(services: GameServices(snapshots: store, ads: NoopAdService()),
                                     seed: 5, restoring: true)
        #expect(model.gameOver, "詰んだ盤を読んだら操作を受け付けない")

        let before = model.board
        model.continueAfterAd()
        #expect(model.gameOver, "使い切っているので復活しない")
        #expect(model.board == before)
    }

    @Test("コンティニュー権は中断・再開をまたいでも復活しない")
    func continueSurvivesRestart() {
        var board = BlockPuzzleBoard.emptyBoard()
        board[0][0] = 1
        let (services, store) = makeServices()
        let model = BlockPuzzleModel(services: services, board: board, hand: [Catalog.single, nil, nil])
        model.place(pieceIndex: 0, row: 5, col: 5)
        // 使用済みの旗を立てた状態で保存し直す。
        let snapshot = store.load(BlockPuzzleSnapshot.self, for: "blockpuzzle")
        #expect(snapshot != nil)
        var used = snapshot!
        used.continueUsed = true
        try? store.save(used, for: "blockpuzzle")

        let reopened = BlockPuzzleModel(services: GameServices(snapshots: store, ads: NoopAdService()),
                                        seed: 1, restoring: true)
        #expect(reopened.continueUsed)
    }

    @Test("もう一度で盤も手元もスコアもやり直す")
    func newGame() {
        let (model, _) = makeAboutToLose()
        model.place(pieceIndex: 0, row: 9, col: 9)
        model.newGame()
        #expect(!model.gameOver)
        #expect(model.score == 0)
        #expect(!model.continueUsed)
        #expect(model.board.allSatisfy { $0.allSatisfy { $0 == 0 } })
        #expect(model.hand.compactMap { $0 }.count == 3)
    }
}

@Suite("ブロックならべ: 中断と復元")
@MainActor
struct BlockPuzzleSnapshotTests {

    @Test("盤・手元・スコア・連鎖が中断をまたいで戻る")
    func roundTrip() {
        var board = BlockPuzzleBoard.emptyBoard()
        for c in 3..<10 { board[4][c] = 1 }
        let (services, store) = makeServices()
        let model = BlockPuzzleModel(services: services, board: board,
                                     hand: [Catalog.bar3, Catalog.square2, Catalog.column3])
        model.place(pieceIndex: 0, row: 4, col: 0)

        let reopened = BlockPuzzleModel(services: GameServices(snapshots: store, ads: NoopAdService()),
                                        seed: 1, restoring: true)
        #expect(reopened.board == model.board)
        #expect(reopened.score == model.score)
        #expect(reopened.combo == model.combo)
        #expect(reopened.hand == model.hand)
    }

    @Test("壊れた中断データは捨てて新規開始に倒す")
    func rejectsCorruptSnapshot() {
        for broken in [
            #"{"board":[[0,0]],"hand":[0,null,null],"score":0,"combo":0,"continueUsed":false}"#,   // 盤が小さい
            #"{"board":BOARD,"hand":[999,null,null],"score":0,"combo":0,"continueUsed":false}"#,   // 存在しない形
            #"{"board":BOARD,"hand":[null,null,null],"score":0,"combo":0,"continueUsed":false}"#,  // 手元が空
            #"{"board":BOARD,"hand":[0,null,null],"score":-5,"combo":0,"continueUsed":false}"#,    // 負のスコア
        ] {
            let full = broken.replacingOccurrences(
                of: "BOARD",
                with: "[" + Array(repeating: "[0,0,0,0,0,0,0,0,0,0]", count: 10).joined(separator: ",") + "]"
            )
            let store = MemorySnapshotStore()
            store.inject(Data(full.utf8), for: "blockpuzzle")
            let model = BlockPuzzleModel(services: GameServices(snapshots: store, ads: NoopAdService()),
                                         seed: 3, restoring: true)
            #expect(model.score == 0)
            #expect(model.hand.compactMap { $0 }.count == 3, "新規開始なら 3 つ配られている")
        }
    }

    @Test("色番号の範囲外が書かれた盤は復元しない")
    func rejectsOutOfRangeColor() {
        var board = BlockPuzzleBoard.emptyBoard()
        board[0][0] = 99
        let snapshot = BlockPuzzleSnapshot(board: board, hand: [0, nil, nil], score: 10)
        #expect(snapshot.validated() == nil)
    }

    @Test("中断データにはピースの形ではなくカタログ番号だけを書く")
    func storesCatalogIDs() {
        let (services, store) = makeServices()
        let model = BlockPuzzleModel(services: services, board: BlockPuzzleBoard.emptyBoard(),
                                     hand: [Catalog.bar3, Catalog.square2, nil])
        _ = model
        let snapshot = store.load(BlockPuzzleSnapshot.self, for: "blockpuzzle")
        #expect(snapshot?.hand == [Catalog.bar3.id, Catalog.square2.id, nil])
    }
}

@Suite("ブロックならべ: 読み上げ文")
struct BlockPuzzleAccessibilityTests {

    @Test("マスは位置と埋まっているかを読む")
    func cell() {
        #expect(BlockPuzzleAccessibility.cellLabel(row: 2, col: 4, value: 0) == "3行5列、空きマス")
        #expect(BlockPuzzleAccessibility.cellLabel(row: 0, col: 0, value: 3) == "1行1列、ブロック")
    }

    @Test("形は外接矩形とマス数から呼び名を作る")
    func shapes() {
        #expect(BlockPuzzleAccessibility.shapeLabel(BlockPuzzlePiece.catalog[0]) == "1マス")
        #expect(BlockPuzzleAccessibility.shapeLabel(BlockPuzzlePiece.catalog[3]) == "横3マスの棒")
        #expect(BlockPuzzleAccessibility.shapeLabel(BlockPuzzlePiece.catalog[4]) == "縦3マスの棒")
        #expect(BlockPuzzleAccessibility.shapeLabel(BlockPuzzlePiece.catalog[9]) == "2×2の四角")
        #expect(BlockPuzzleAccessibility.shapeLabel(BlockPuzzlePiece.catalog[11]) == "L字3マス")
        #expect(BlockPuzzleAccessibility.shapeLabel(BlockPuzzlePiece.catalog[15]) == "L字5マス")
    }

    @Test("手元は置けるかどうかまで読む")
    func hand() {
        #expect(BlockPuzzleAccessibility.handLabel(index: 1, piece: BlockPuzzlePiece.catalog[0], canPlace: true)
                == "手元2つ目、1マス、置けます")
        #expect(BlockPuzzleAccessibility.handLabel(index: 0, piece: BlockPuzzlePiece.catalog[0], canPlace: false)
                == "手元1つ目、1マス、置ける場所がありません")
        #expect(BlockPuzzleAccessibility.handLabel(index: 2, piece: nil, canPlace: false) == "手元3つ目、使用済み")
    }

    @Test("連鎖中だけ連鎖数を読む")
    func status() {
        #expect(BlockPuzzleAccessibility.statusLabel(score: 120, combo: 0) == "スコア120")
        #expect(BlockPuzzleAccessibility.statusLabel(score: 120, combo: 1) == "スコア120")
        #expect(BlockPuzzleAccessibility.statusLabel(score: 120, combo: 2) == "スコア120、2連鎖中")
    }
}
