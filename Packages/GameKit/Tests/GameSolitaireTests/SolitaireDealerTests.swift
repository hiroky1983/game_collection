import Testing
import Foundation
@testable import GameSolitaire

@Suite("配札")
struct SolitaireDealerTests {

    @Test("配札はクロンダイクの初期配置になる")
    func dealsKlondikeLayout() {
        let board = SolitaireDealer.deal(seed: 12345)
        #expect(board.tableau.count == 7)
        for (column, pile) in board.tableau.enumerated() {
            #expect(pile.faceUp.count == 1)                 // 各列で表向きは一番上の1枚だけ
            #expect(pile.faceDown.count == column)          // 1列目から 0, 1, 2 … 枚
        }
        #expect(board.stock.count == 24)                    // 52 - (1+2+…+7)
        #expect(board.waste.isEmpty)
        #expect(board.foundations == [0, 0, 0, 0])
        #expect(!board.jokerAvailable)                      // ジョーカーは配札に含めない
    }

    @Test("52枚がちょうど1枚ずつ配られる")
    func usesEveryCardOnce() {
        let board = SolitaireDealer.deal(seed: 999)
        let all = board.tableau.flatMap { $0.faceDown + $0.faceUp } + board.stock + board.waste
        #expect(all.count == 52)
        #expect(Set(all.map(\.id)).count == 52)
        #expect(all.allSatisfy { !$0.isJoker })
    }

    @Test("同じ種はいつでも同じ配札になる")
    func isDeterministic() {
        #expect(SolitaireDealer.deal(seed: 7) == SolitaireDealer.deal(seed: 7))
        #expect(SolitaireDealer.deal(seed: 7) != SolitaireDealer.deal(seed: 8))
    }

    @Test("検証済みの種は十分な数があり、重複していない")
    func verifiedSeedsAreUsable() {
        #expect(SolitaireDealer.verifiedSeeds.count >= 1000)
        #expect(Set(SolitaireDealer.verifiedSeeds).count == SolitaireDealer.verifiedSeeds.count)
    }

    /// **`SolitaireVerifiedSeeds.swift` を作り直す手順**
    ///
    /// 種の並びは「1 から順に試して、ソルバーが勝ち筋を見つけた種を採用したもの」で、
    /// `SolitaireSolver.defaultMaxStates` と手の並び（`successors`）を変えると結果も変わる。
    /// ソルバーに手を入れたら、次を実行して出力でファイルの配列を丸ごと置き換える:
    ///
    /// ```
    /// swift test --filter 検証済みの種を作り直す 2>/dev/null   # SOLITAIRE_REGENERATE_SEEDS=<本数> を付けて実行
    /// ```
    ///
    /// デバッグビルドでは1配札あたり1秒前後かかるので、本数が多いときは
    /// `Sources/GameSolitaire/*.swift` を `swiftc -O` で直接ビルドしたほうが速い。
    @Test("検証済みの種を作り直す",
          .enabled(if: ProcessInfo.processInfo.environment["SOLITAIRE_REGENERATE_SEEDS"] != nil))
    func regenerateVerifiedSeeds() {
        let target = Int(ProcessInfo.processInfo.environment["SOLITAIRE_REGENERATE_SEEDS"] ?? "400") ?? 400
        var seeds: [UInt64] = []
        var seed: UInt64 = 1
        while seeds.count < target {
            if SolitaireSolver.solve(SolitaireDealer.deal(seed: seed)).isSolvable { seeds.append(seed) }
            seed += 1
        }
        var out = "let solitaireVerifiedSeeds: [UInt64] = [\n"
        for start in stride(from: 0, to: seeds.count, by: 10) {
            out += "    " + seeds[start..<min(start + 10, seeds.count)]
                .map(String.init).joined(separator: ", ") + ",\n"
        }
        print(out + "]")
    }

    /// 配列の中身が本当に「クリア可能」であることを、**勝ち筋を実際に指し切って**確かめる。
    /// ソルバーの結論をそのまま信じず、公開 API（`apply`）を通してクリアに到達することまで見る。
    @Test("検証済みの種は勝ち筋を指し切ればクリアできる", arguments: [0, 137, 999])
    func verifiedSeedsAreActuallyWinnable(index: Int) {
        let seed = SolitaireDealer.verifiedSeeds[index]
        var board = SolitaireDealer.deal(seed: seed)
        let result = SolitaireSolver.solve(board)
        guard let solution = result.solution else {
            Issue.record("種 \(seed) の勝ち筋が見つからなかった（探索局面 \(result.statesExplored)）")
            return
        }
        for move in solution {
            let applied = board.apply(move)
            #expect(applied, "種 \(seed) の勝ち筋に非合法手が混ざっている: \(move)")
        }
        #expect(board.isWon, "種 \(seed) は勝ち筋を指し切ってもクリアにならなかった")
    }

    /// 全件の検証は時間がかかるので、既定では走らせない。
    @Test("検証済みの種を全件確かめる",
          .enabled(if: ProcessInfo.processInfo.environment["SOLITAIRE_VERIFY_ALL_SEEDS"] != nil))
    func allVerifiedSeedsAreWinnable() {
        for seed in SolitaireDealer.verifiedSeeds {
            #expect(SolitaireSolver.solve(SolitaireDealer.deal(seed: seed)).isSolvable,
                    "種 \(seed) の勝ち筋が見つからなかった")
        }
    }
}
