import Foundation
import Testing
@testable import GameBlocks

/// 金庫ブロック（#1250）。
///
/// 固定するのは契約そのもの: 1〜3 面は変えない / 4 面以降に金庫がある / 中身を壊すごとに壁が
/// 段階的に開く / 開くたびに球が 1 個増える（上限内）/ 空にすると一斉ダメージ / 詰みが無い。
@Suite("ブロック崩しの金庫ブロック")
struct VaultTests {

    /// 5 幅の金庫（中身 3 個・壁 11 枚・入り口は下段中央）を左に置き、右に通常ブロックを並べた盤。
    private static let smallVault = [
        "nnwwwwwnn",
        "nnwnnnwnn",
        "n.ww.wwn.",
    ]

    private func field(_ rows: [String]) -> BlocksField {
        BlocksField(stage: BlocksStage(number: 1, rows: rows, ballSpeed: 70), speed: 70)
    }

    private func wallCount(_ f: BlocksField) -> Int {
        f.blocks.flatMap { $0 }.filter { $0?.kind == .vaultWall }.count
    }

    // MARK: - ステージ定義

    @Test("1〜3 面には金庫が無く、4 面以降のすべてに 1 つ以上ある")
    func vaultsAppearFromStageFour() {
        for stage in BlocksStage.all {
            let vaults = BlocksField(stage: stage, speed: stage.ballSpeed).vaults
            if stage.number <= 3 {
                #expect(vaults.isEmpty, "ステージ\(stage.number) に金庫がある")
                #expect(!stage.rows.joined().contains("w"))
            } else {
                #expect(!vaults.isEmpty, "ステージ\(stage.number) に金庫が無い")
            }
        }
    }

    /// 入り口が無い金庫は中身に球が届かず、そのステージが詰む。壁の外接矩形の最下段に
    /// 壁でないマス（空き or 壊せるブロック）が 1 つ以上あることを全面で確かめる。
    @Test("どの金庫にも中身があり、下向きの入り口がある")
    func everyVaultHasContentsAndAnEntrance() {
        for stage in BlocksStage.all {
            let f = BlocksField(stage: stage, speed: stage.ballSpeed)
            for vault in f.vaults {
                #expect(!vault.contentCells.isEmpty, "ステージ\(stage.number) に中身の無い金庫がある")
                let rows = vault.wallCells.map(\.row)
                let columns = vault.wallCells.map(\.column)
                let bottom = rows.max()!
                let entrances = (columns.min()!...columns.max()!).filter { column in
                    f.block(row: bottom, column: column)?.kind != .vaultWall
                }
                #expect(entrances.count == 1, "ステージ\(stage.number) の入り口が \(entrances.count) 個")
                // 入り口の下に壁が無い（下から球が入れる）。
                for column in entrances {
                    #expect(f.block(row: bottom + 1, column: column)?.kind != .vaultWall)
                }
            }
        }
    }

    @Test("金庫の壁は壊せるブロックに数えず、得点も無い")
    func wallsAreNotBreakable() {
        #expect(BlockKind.vaultWall.hitPoints == nil)
        #expect(!Block(kind: .vaultWall).isBreakable)
        #expect(BlocksScoring.blockPoints(kind: .vaultWall, destroyed: false, stage: 5) == 0)
        #expect(BlockKind.from(symbol: "w") == .vaultWall)
    }

    // MARK: - 挙動

    @Test("金庫はレイアウトから検出され、壁と中身に分かれる")
    func detectsWallsAndContents() {
        let f = field(Self.smallVault)
        #expect(f.vaults.count == 1)
        #expect(f.vaults[0].wallCells.count == 11)
        #expect(f.vaults[0].contentCells.count == 3)
    }

    @Test("中身を壊すごとに壁が段階的に開く（下の段から）")
    func wallsOpenGradually() {
        var f = field(Self.smallVault)
        var remaining: [Int] = []
        for column in 3...5 {
            f.destroyBlockForTesting(row: 1, column: column)
            remaining.append(wallCount(f))
        }
        // 11 枚 ÷ 中身 3 個 = 1 個壊すごとに 3 → 7 → 11 枚が開く。
        #expect(remaining == [8, 4, 0])
        #expect(f.block(row: 2, column: 3) == nil, "下の段が先に開く")
    }

    @Test("壁が開くたびに球が 1 個増え、上限 maxBalls を超えない")
    func wallOpeningAddsBallsWithinTheCap() {
        var f = field(Self.smallVault)
        f.placeBall(x: 50, y: 40, vx: 20, vy: 60)
        let events = f.destroyBlockForTesting(row: 1, column: 3)
        let opened = events.filter { if case .vaultWallOpened = $0 { return true } else { return false } }
        #expect(opened.count == 3)
        #expect(f.balls.count == BlocksRules.maxBalls, "3 枚開いても上限の 3 個まで")
        #expect(f.balls.allSatisfy { $0.isMoving })
    }

    @Test("壁が 1 枚開くたびに球がちょうど 1 個増える")
    func oneBallPerOpenedWall() {
        // 壁 15 枚・中身 9 個: 1 個目を壊すと 15 / 9 = 1 枚だけ開く。
        var f = field(["wwwww....", "wnnnw....", "wnnnw....", "wnnnw....", "ww.ww...."])
        #expect(f.vaults[0].wallCells.count == 15)
        #expect(f.vaults[0].contentCells.count == 9)
        f.placeBall(x: 50, y: 40, vx: 20, vy: 60)
        let events = f.destroyBlockForTesting(row: 1, column: 1)
        #expect(events.filter { if case .vaultWallOpened = $0 { return true } else { return false } }.count == 1)
        #expect(f.balls.count == 2)
    }

    @Test("空にすると残りの壁が消え、外のブロックへ一斉に 1 ダメージが入る")
    func clearingTheVaultShockwavesTheBoard() {
        // 左に金庫 A（中身 1 個）、中央に通常 / 硬いブロック、右に閉じたままの金庫 B（中身 1 個）。
        let rows = [
            "www.nhn..",
            "wnw..www.",
            "w.w..wnw.",
            ".....w.w.",
        ]
        var f = field(rows)
        #expect(f.vaults.count == 2)
        f.placeBall(x: 50, y: 40, vx: 20, vy: 60)
        let events = f.destroyBlockForTesting(row: 1, column: 1)

        guard case .vaultCleared(_, let hits)? = events.first(where: {
            if case .vaultCleared = $0 { return true } else { return false }
        }) else {
            Issue.record("vaultCleared が出ていない")
            return
        }
        #expect(hits.contains(BlocksBlockHit(row: 0, column: 4, kind: .normal, destroyed: true)))
        #expect(hits.contains(BlocksBlockHit(row: 0, column: 5, kind: .hard, destroyed: false)))
        #expect(hits.contains(BlocksBlockHit(row: 0, column: 6, kind: .normal, destroyed: true)))
        #expect(!hits.contains { $0.row == 2 && $0.column == 6 }, "閉じた別の金庫の中身は巻き込まない")
        #expect(f.block(row: 0, column: 5)?.remaining == 1)
        #expect(f.block(row: 2, column: 6) != nil)
        #expect(f.vaultsClearedCount == 1)
        #expect(f.block(row: 0, column: 0) == nil, "空にした金庫の壁は残らない")
    }

    @Test("金庫のできごとは、壊した 1 個の blockHit より前に並ぶ")
    func vaultEventsPrecedeTheBlockHit() {
        var f = field(Self.smallVault)
        f.placeBall(x: 50, y: 40, vx: 20, vy: 60)
        let events = f.destroyBlockForTesting(row: 1, column: 3)
        let hitIndex = events.firstIndex { if case .blockHit = $0 { return true } else { return false } }!
        let lastVault = events.lastIndex { if case .vaultWallOpened = $0 { return true } else { return false } }!
        #expect(lastVault < hitIndex)
    }

    @Test("実際の衝突でも中身を壊すと壁が開く")
    func realCollisionOpensTheVault() {
        // 中身 1 個の金庫。入り口の真下から球を撃ち上げる。
        var f = field(["www......", "wnw......", "w.w......"])
        let entrance = BlocksField.blockRect(row: 2, column: 1)
        f.placeBall(x: entrance.midX, y: entrance.midY, vx: 0, vy: 70)
        var events: [BlocksEvent] = []
        for _ in 0..<30 { events += f.step(dt: 1.0 / 60) }
        #expect(events.contains { if case .vaultWallOpened = $0 { return true } else { return false } })
        #expect(events.contains { if case .vaultCleared = $0 { return true } else { return false } })
        #expect(wallCount(f) == 0)
        #expect(f.isCleared)
    }

    @Test("壁は球を跳ね返す（壊れないブロックと同じ）")
    func wallsBounceTheBall() {
        var f = field(["www......", "wnw......", "w.w......"])
        // 壁の真下（(2,0) の下）から撃ち上げる。
        let wall = BlocksField.blockRect(row: 2, column: 0)
        f.placeBall(x: wall.midX, y: wall.minY - 3, vx: 0, vy: 70)
        var events: [BlocksEvent] = []
        for _ in 0..<10 { events += f.step(dt: 1.0 / 60) }
        #expect(events.contains {
            if case .blockHit(_, _, .vaultWall, false) = $0 { return true } else { return false }
        })
        #expect(f.block(row: 2, column: 0)?.kind == .vaultWall)
    }
}
