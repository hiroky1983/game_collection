import Testing
import Foundation
@testable import GameShogi

/// 駒の移動アニメーション（#200）の土台。
///
/// 補間が成り立つ条件は「**動いた駒のビューの同一性が変わらない**」ことに尽きる。
/// 見た目そのものはシミュレータでしか確かめられないが、同一性の対応付けは純粋な値の計算なので
/// ここで固定する。ここが崩れると、ビルドもテストも通ったまま演出だけが静かに瞬間移動へ戻る。
@Suite("駒の同一性（移動アニメーションの土台）")
struct ShogiPieceLayoutTests {

    private func sq(_ usi: String) -> Int { Sq.fromUSI(Substring(usi))! }

    @Test("盤の初期配置は 40 枚ぶんの駒に重複しない ID が付く")
    func startingPositionHasUniqueIDs() {
        let layout = ShogiPieceLayout(Position.start())
        #expect(layout.placements.count == 40)
        #expect(Set(layout.placements.map(\.id)).count == 40)
        // 駒が居るマスと過不足なく一致する（マスの側と二重に描かないための前提）。
        let occupied = Set((0..<Sq.count).filter { Position.start().squares[$0] != nil })
        #expect(Set(layout.placements.map(\.square)) == occupied)
    }

    @Test("ID は昇順に並ぶ（重なり順が着手のたびに入れ替わらない）")
    func placementsAreSortedByID() {
        var layout = ShogiPieceLayout(Position.start())
        var position = Position.start()
        for usi in ["7g7f", "3c3d", "8h2b+", "3a2b", "B*4e"] {
            position.make(Move.fromUSI(usi)!)
            layout.update(to: position)
            #expect(layout.placements.map(\.id) == layout.placements.map(\.id).sorted())
        }
    }

    @Test("駒を動かしても同じ ID が移動先へ引き継がれる")
    func movingPieceKeepsItsIdentity() {
        var position = Position.start()
        var layout = ShogiPieceLayout(position)
        let pawn = layout.id(at: sq("7g"))
        #expect(pawn != nil)

        position.make(.board(from: sq("7g"), to: sq("7f"), promote: false))
        layout.update(to: position)

        #expect(layout.id(at: sq("7f")) == pawn)
        #expect(layout.id(at: sq("7g")) == nil)
    }

    @Test("成っても同じ ID のまま（見た目だけが変わる）")
    func promotionKeepsItsIdentity() {
        // 途中の駒をどけていないので合法手ではないが、`make` は合法性を見ない。
        // ここで確かめたいのは「成りで駒種の表示が変わっても対応付けが切れないこと」だけ。
        var position = Position.start()
        var layout = ShogiPieceLayout(position)
        let bishop = layout.id(at: sq("8h"))

        position.make(.board(from: sq("8h"), to: sq("2b"), promote: true))
        layout.update(to: position)

        #expect(layout.id(at: sq("2b")) == bishop)
        #expect(layout.placements.first { $0.id == bishop }?.piece.promoted == true)
    }

    @Test("取った駒の ID は盤から消え、取った側の ID は生き残る")
    func capturedPieceDisappears() {
        var position = Position.start()
        var layout = ShogiPieceLayout(position)
        let attacker = layout.id(at: sq("8h"))
        let victim = layout.id(at: sq("2b"))
        #expect(attacker != victim)

        position.make(.board(from: sq("8h"), to: sq("2b"), promote: false))
        layout.update(to: position)

        #expect(layout.id(at: sq("2b")) == attacker)
        #expect(layout.placements.contains { $0.id == victim } == false)
        #expect(layout.placements.count == 39)
    }

    @Test("打った駒には新しい ID が振られる（他の駒から横取りしない）")
    func droppedPieceGetsFreshIdentity() {
        var position = Position.start()
        var layout = ShogiPieceLayout(position)
        position.make(.board(from: sq("8h"), to: sq("2b"), promote: false)) // 角を持ち駒にする
        layout.update(to: position)
        let before = Dictionary(uniqueKeysWithValues: layout.placements.map { ($0.id, $0.square) })

        position.make(.drop(type: .bishop, to: sq("4e")))
        layout.update(to: position)

        let dropped = layout.id(at: sq("4e"))
        #expect(dropped != nil)
        #expect(before[dropped!] == nil, "盤に居た駒の ID を打ち駒が奪っている")
        // 既にあった駒は 1 枚も動いていない。
        for (id, square) in before {
            #expect(layout.placements.first { $0.id == id }?.square == square)
        }
    }

    @Test("検討ナビで局面を戻しても ID が戻る（行きと帰りで対応が一致する）")
    func steppingBackRestoresIdentities() {
        let start = Position.start()
        var layout = ShogiPieceLayout(start)
        let before = layout.placements

        var moved = start
        moved.make(.board(from: sq("7g"), to: sq("7f"), promote: false))
        layout.update(to: moved)
        layout.update(to: start)

        #expect(layout.placements == before)
    }

    @Test("連続した着手でも ID の重複・取り違えが起きない")
    func staysConsistentOverASequenceOfMoves() {
        var position = Position.start()
        var layout = ShogiPieceLayout(position)
        // 駒取り・成り・打ち駒を含む並び。
        for usi in ["7g7f", "3c3d", "8h2b+", "3a2b", "B*4e", "2b3c", "4e3d", "3c3d"] {
            position.make(Move.fromUSI(usi)!)
            layout.update(to: position)

            let ids = layout.placements.map(\.id)
            #expect(Set(ids).count == ids.count, "\(usi) の後に ID が重複した")
            let squares = layout.placements.map(\.square)
            #expect(Set(squares).count == squares.count, "\(usi) の後に 1 マスへ 2 枚が乗った")
            // 盤の実際の中身と一致していること（表示だけが局面から乖離しない）。
            for placement in layout.placements {
                #expect(position.squares[placement.square] == placement.piece)
            }
            #expect(layout.placements.count == (0..<Sq.count).count { position.squares[$0] != nil })
        }
    }

    @Test("新規対局で局面を入れ替えても矛盾しない")
    func handlesFullBoardReplacement() {
        var position = Position.start()
        var layout = ShogiPieceLayout(position)
        for usi in ["7g7f", "3c3d", "8h2b+", "3a2b"] {
            position.make(Move.fromUSI(usi)!)
            layout.update(to: position)
        }

        layout.update(to: Position.start())

        #expect(layout.placements.count == 40)
        #expect(Set(layout.placements.map(\.id)).count == 40)
        for placement in layout.placements {
            #expect(Position.start().squares[placement.square] == placement.piece)
        }
    }
}

/// 盤上のマス → 画面の位置。駒を絶対座標で置くために足した逆変換（#200）。
@Suite("マスと画面位置の対応")
struct ShogiDisplayPositionTests {
    @Test("boardIndex の逆変換になっている", arguments: [false, true])
    func roundTripsWithBoardIndex(flipped: Bool) {
        for row in 0..<9 {
            for col in 0..<9 {
                let square = Sq.boardIndex(row: row, col: col, flipped: flipped)
                let spot = Sq.displayPosition(of: square, flipped: flipped)
                #expect(spot.row == row)
                #expect(spot.col == col)
            }
        }
    }
}

/// 「見た目を見るまで気づけない」種類の退行を、ソース走査で止める。
@Suite("駒の層の組み方")
struct ShogiPieceLayerSourceTests {

    private static var viewSource: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // GameShogiTests
                .deletingLastPathComponent()   // Tests
                .deletingLastPathComponent()   // GameKit
                .appendingPathComponent("Sources/GameShogi/ShogiView.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    @Test("ShogiCell は駒を描かない（盤全体を覆う層と二重に描くと移動が補間されない）")
    func cellDoesNotDrawPieces() throws {
        let lines = try Self.viewSource.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.hasPrefix("struct ShogiCell") }) else {
            Issue.record("struct ShogiCell が見つからない（走査の前提が壊れている）")
            return
        }
        guard let end = lines[start...].dropFirst().firstIndex(where: { $0 == "}" }) else {
            Issue.record("struct ShogiCell の終わりが見つからない")
            return
        }
        let body = lines[start..<end].joined(separator: "\n")
        #expect(body.contains("KomaView(") == false, "ShogiCell が駒を描いています:\n\(body)")
    }

    @Test("着手先の印は駒より後（= 上）に重ねる")
    func targetLayerIsAbovePieceLayer() throws {
        let lines = try Self.viewSource.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let piece = lines.firstIndex(of: ".overlay { pieceLayer(cell: cell) }"),
              let target = lines.firstIndex(of: ".overlay { targetLayer(cell: cell) }") else {
            Issue.record("盤に重ねる 2 層が見つからない（走査の前提が壊れている）")
            return
        }
        // 逆にすると、取れる駒を囲む枠が駒の下に潜って何が取れるのか読めなくなる。
        #expect(piece < target)
    }

    @Test("駒には .transition を .position より前に付ける")
    func transitionComesBeforePosition() throws {
        let lines = try Self.viewSource.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let transition = lines.firstIndex(where: { $0.hasPrefix(".transition(") }),
              let position = lines.firstIndex(where: { $0.hasPrefix(".position(") }) else {
            Issue.record("駒の層の .transition / .position が見つからない")
            return
        }
        // あとに置くと拡大・縮小の基準が盤の原点になり、消える駒が左上へ吸い込まれる。
        #expect(transition < position)
    }
}

private extension ShogiPieceLayout {
    func id(at square: Int) -> Int? { placements.first { $0.square == square }?.id }
}
