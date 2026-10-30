import Testing
import Foundation
import CoreEngine
@testable import GameShogi

/// 達人（#2698）の自前の盤・手生成と探索の検収。強さの計測は `Scripts/shogi-cpu-bench`（`master`）で行う。
@Suite("将棋 達人のエンジン")
struct MasterEngineTests {
    /// 達人は段の番号 3 で引ける。開始シートの段の並びには出ない（UI に出すのは v1.1.15）。
    /// 既存の段は今の `SimpleMinimaxEngine` のまま。
    @Test func masterIsLevelThreeAndHiddenFromPicker() {
        #expect(ShogiMasterEngine.engine(level: ShogiMasterEngine.level) is ShogiMasterEngine)
        #expect(!CPUStrength.allCases.map(\.rawValue).contains(ShogiMasterEngine.level))
        for strength in CPUStrength.allCases {
            #expect(ShogiMasterEngine.engine(level: strength.rawValue) is SimpleMinimaxEngine)
        }
        #expect(ShogiMasterEngine.shippedTimeLimit <= 3)
    }

    /// 達人の記録・解析は既存の段と混ざらない（確認用ビルド tf/shogi-master）。既存の段は今のまま。
    /// #3110: 条件チップの強さ名。達人が「ふつう」に倒れない・既存 4 段は今のまま。
    @Test func strengthLabelNamesMasterAndKeepsExistingLadder() {
        #expect(ShogiMasterEngine.strengthLabel(forLevel: ShogiMasterEngine.level) == ShogiMasterEngine.label)
        #expect(ShogiMasterEngine.strengthLabel(forLevel: ShogiMasterEngine.level) != CPUStrength.standard.label)
        for strength in CPUStrength.allCases {
            #expect(ShogiMasterEngine.strengthLabel(forLevel: strength.rawValue) == strength.label)
        }
    }

    @Test func masterRecordAndAnalyticsAreSeparate() {
        let master = ShogiMasterEngine.level
        #expect(ShogiMasterEngine.recordVariant(level: master, handicapVariant: nil) == "master")
        #expect(ShogiMasterEngine.recordVariant(level: master, handicapVariant: "rook-player") == "master-rook-player")
        #expect(ShogiMasterEngine.analyticsLevel(forLevel: master) == .expert)
        for strength in CPUStrength.allCases {
            #expect(ShogiMasterEngine.recordVariant(level: strength.rawValue, handicapVariant: nil) == nil)
            #expect(ShogiMasterEngine.recordVariant(level: strength.rawValue, handicapVariant: "bishop-cpu") == "bishop-cpu")
            #expect(ShogiMasterEngine.analyticsLevel(forLevel: strength.rawValue) == strength.analyticsLevel)
        }
        #expect(RecordVariantLabels.label(recordKey: "shogi#master", language: .japanese) == "達人")
        #expect(RecordVariantLabels.label(recordKey: "shogi#master-rook-player", language: .japanese)
                == "達人・飛車落ち・自分が落とす")
    }

    /// 既存の合法手生成（`Position.legalMoves`）と同じ手を出すか。達人は歩・角・飛の不成を生成しない
    /// （成れるのに成らない手は損しかない）ので、比べる側からも外す。
    static func referenceMoves(_ pos: Position) -> Set<String> {
        let moves = pos.legalMoves()
        let promoting = Set(moves.compactMap { m -> String? in
            if case let .board(from, to, true) = m { return "\(from)-\(to)" }
            return nil
        })
        return Set(moves.compactMap { m -> String? in
            if case let .board(from, to, false) = m, promoting.contains("\(from)-\(to)"),
               let p = pos.squares[from], [.pawn, .bishop, .rook].contains(p.type) {
                return nil
            }
            return m.usi
        })
    }

    @Test func startPositionPerftMatchesWithoutRedundantNonPromotions() {
        #expect(ShogiMasterEngine.perft(sfen: Position.startSFEN, depth: 1) == 30)
        #expect(ShogiMasterEngine.perft(sfen: Position.startSFEN, depth: 2) == 900)
        // 3 手目までに角の成り・不成の選択は出ない（25470 は成・不成を別に数えた公表値。角交換の 8八角成ほかで差が出る）
        #expect(ShogiMasterEngine.perft(sfen: Position.startSFEN, depth: 3) <= 25470)
    }

    /// 乱数で進めた対局（取った駒を打つ・成る・王手の局面を含む）の各局面で、合法手が既存の生成と一致する。
    @Test func legalMovesMatchReferenceOnRandomGames() {
        var rng = MMIXRandom(seed: 2698)
        var checked = 0
        for _ in 0..<10 {
            var pos = Position.start()
            for _ in 0..<120 {
                let ref = Self.referenceMoves(pos)
                let mine = Set(ShogiMasterEngine.legalMovesUSI(sfen: pos.toSFEN()))
                #expect(mine == ref, "局面 \(pos.toSFEN()): 余分 \(mine.subtracting(ref)) 不足 \(ref.subtracting(mine))")
                if mine != ref { return }
                checked += 1
                let moves = pos.legalMoves()
                if moves.isEmpty { break }
                // 取る手を優先して、持ち駒のある局面を増やす。
                let captures = moves.filter { if case let .board(_, to, _) = $0 { return pos.squares[to] != nil }; return false }
                let pool = !captures.isEmpty && rng.next() % 2 == 0 ? captures : moves
                pos.make(pool[Int(rng.next() % UInt64(pool.count))])
            }
        }
        #expect(checked > 500)
    }

    /// 打ち歩詰めは指さない・数えない。
    @Test func pawnDropMateIsExcluded() {
        // 後手玉 1a、先手の金 2c（1b・2b に利く）と銀 3b（2a に利く）。1b への歩打ちは打ち歩詰め。
        let sfen = "8k/6S2/7G1/9/9/9/9/9/K8 b P 1"
        let mine = ShogiMasterEngine.legalMovesUSI(sfen: sfen)
        #expect(!mine.contains("P*1b"))
        #expect(Set(mine) == Self.referenceMoves(Position.fromSFEN(sfen)!))
    }

    /// 1 手詰めを見つけて指す。
    @Test func findsMateInOne() async {
        // 上と同じ形で持ち駒が金。G*1b・G*2b・G*2a のどれでも詰む（どれを選ぶかは問わない）。
        let sfen = "8k/6S2/7G1/9/9/9/9/9/K8 b G 1"
        let usi = await ShogiMasterEngine(timeLimit: 1).bestMove(sfen: sfen)
        #expect(usi != nil)
        var pos = Position.fromSFEN(sfen)!
        pos.make(Move.fromUSI(usi!)!)
        #expect(pos.legalMoves().isEmpty)
    }

    /// 只で取れる大駒は取る。
    @Test func capturesHangingRook() async {
        // 先手の歩 5f の前に後手の飛 5e。
        let sfen = "4k4/9/9/9/4r4/4P4/9/9/4K4 b - 1"
        let usi = await ShogiMasterEngine(timeLimit: 1).bestMove(sfen: sfen)
        #expect(usi == "5f5e")
    }

    /// 時間の上限（ここでは 1 秒）で打ち切って指す（デバッグビルドなので余裕を見る）。
    @Test func respectsTimeLimit() async {
        let sfen = "ln1g1g1nl/1r1s1k1s1/p1pp1pbpp/1p2p1p2/9/2P1P1P2/PPBP1P1PP/1S2K2R1/LN1G1GSNL b - 15"
        let t = Date()
        let usi = await ShogiMasterEngine(timeLimit: 1.0).bestMove(sfen: sfen)
        #expect(usi != nil)
        #expect(Date().timeIntervalSince(t) < 2.0)
    }
}
