import Testing
import Foundation
import CoreEngine
@testable import GameShogi

/// 難易度の回帰テスト（#502・#1461）。段階の差は「考える時間」と「最善手を打つ確率」だけ（#1461）。
///
/// **勝率の実測は `-O` の単体バイナリで行い、結果は #502 / PR の表に残す。**
/// ここに入れるのは CI（最適化なしのデバッグビルド）で現実的な時間に収まるものだけ:
/// 深さ 4・5 の設定を自己対戦させると 1 手あたり秒単位かかり、20 手 6 局で `-O` でも
/// 265 秒だった（実測）。デバッグビルドではさらに遅くなるため、上の段どうしの勝率は
/// CI に置けない。代わりに
/// ①段階の設定そのもの ②同じ局面で3段階が選ぶ手（読みの深さの差が着手に出ること）
/// ③軽い設定どうし（旧「弱」対 新「弱」・新「弱」対ランダム）の直接対戦
/// で固定する。
///
/// 自己対戦は `timeLimit: .infinity` で締切そのものを無くし、**深さで決まる**状態にしてから行う。
/// 実時間で打ち切られると、同じテストが実行環境の速さで別の結果を返す（#1187: 有限の大きい値だと
/// 高負荷時にその値を超えて打ち切りが再発した）。
enum ShogiSelfPlay {
    /// 決定的な擬似乱数（ランダム役の手を再現可能にする）。共通の `MMIXRandom`（#1150）。
    /// 0 個からは選べないので `upper <= 0` は 0 を返す（`next()` は進めない）。
    static func randomIndex(_ upper: Int, using rng: inout MMIXRandom) -> Int {
        upper <= 0 ? 0 : Int(rng.next() % UInt64(upper))
    }

    struct Result {
        /// 先手視点の駒得（玉を除く盤上＋持ち駒）。
        var material: Int
        var plies: Int
        /// 詰みで終わったなら負けた側。手数上限で終わったら nil。
        var mated: Side?
    }

    /// `nil` を渡した側はランダムに指す（「壊れていないこと」の対照）。
    static func play(
        black: SimpleMinimaxEngine?,
        white: SimpleMinimaxEngine?,
        seed: UInt64,
        maxPlies: Int
    ) async -> Result {
        var pos = Position.start()
        var rng = MMIXRandom(seed: seed)
        for ply in 0..<maxPlies {
            let moves = pos.legalMoves()
            if moves.isEmpty {
                return Result(material: material(pos), plies: ply, mated: pos.sideToMove)
            }
            let engine = pos.sideToMove == .black ? black : white
            var chosen = moves[randomIndex(moves.count, using: &rng)]
            if let engine {
                let usi = await engine.bestMove(sfen: pos.toSFEN())
                let move = usi.flatMap(Move.fromUSI)
                #expect(move != nil, "CPU が手を返さなかった")
                if let move {
                    #expect(moves.contains(move), "CPU が非合法手を選んだ: \(usi ?? "-")")
                    chosen = move
                }
            }
            pos.make(chosen)
        }
        return Result(material: material(pos), plies: maxPlies, mated: nil)
    }

    /// 玉を除いた駒の価値の差（先手視点）。
    static func material(_ pos: Position) -> Int {
        var s = 0
        for sq in 0..<Sq.count {
            guard let p = pos.squares[sq], p.type != .king else { continue }
            s += (p.color == .black ? 1 : -1) * PieceValue.onBoard(p)
        }
        for type in PieceType.allCases where type.isDroppable {
            s += pos.hands[Side.black.rawValue][type.rawValue] * PieceValue.base(type)
            s -= pos.hands[Side.white.rawValue][type.rawValue] * PieceValue.base(type)
        }
        return s
    }

    /// 出荷している難易度を、**時間で打ち切られない形**にして返す（探索設定はそのまま）。
    ///
    /// 出荷値の `timeLimit`（0.5〜3 秒）はデバッグビルドでは実際に効いてしまい、そのとき返る手は
    /// 同時に走っている他のテストの負荷で変わる。テストが CPU の混み具合で赤くなるのを避けるため、
    /// `timeLimit: .infinity` で締切そのものを無くし、深さだけで決まる状態にする（有限の大きい値だと、
    /// 高負荷時にその値を超えて打ち切りが再発しうる。#1187）。出荷値の深さ上限は 32 で、そのままでは
    /// 終わらないので `depth` に絞る（既定 5 は `smallGainBehindRecapture` が要る深さ・#502）。
    ///
    /// - Parameter slips: `true` なら出荷どおり「最善手を外す」（#1461）。既定は `false`
    ///   （読みだけを固定するテストが確率で揺れないように）。
    static func untimed(level: Int, seed: UInt64? = nil, slips: Bool = false, depth: Int = 5) -> SimpleMinimaxEngine {
        let shipped = SimpleMinimaxEngine(level: level)
        return SimpleMinimaxEngine(
            depth: min(shipped.depth, depth), usePositional: shipped.usePositional,
            useQuiescence: shipped.useQuiescence, useBook: shipped.useBook, timeLimit: .infinity,
            nodeLimit: nil, policy: slips ? shipped.policy : shipped.policy.withoutSlip, seed: seed)
    }

    /// 対局を回すテスト用の軽い設定（深さ 2・静止探索なし）。確率と損の幅は出荷値のまま。
    static func light(level: Int, seed: UInt64? = nil) -> SimpleMinimaxEngine {
        let shipped = SimpleMinimaxEngine(level: level)
        return SimpleMinimaxEngine(
            depth: 2, usePositional: false, useQuiescence: false, useBook: false, timeLimit: .infinity,
            nodeLimit: nil, policy: shipped.policy, seed: seed)
    }
}

@Suite("将棋の難易度: 段階の設計（#1461）")
struct ShogiDifficultyConfigTests {

    /// 会長決裁（2026-09-26）: 入門 0.5 秒 / かんたん 1 秒 / ふつう 2 秒 / むずかしい 3 秒。
    /// 局面数の上限は強さの主軸にしない（出荷値では使わない）。
    @Test("考える時間は 0.5 / 1 / 2 / 3 秒で、局面数の上限は無い")
    func timeLimitsFollowTheDecision() {
        let limits = CPUStrength.allCases.map { SimpleMinimaxEngine(level: $0.rawValue).timeLimit }
        #expect(limits == [0.5, 1, 2, 3])
        #expect(CPUStrength.allCases.allSatisfy { SimpleMinimaxEngine(level: $0.rawValue).nodeLimit == nil })
    }

    @Test("探索は全段階で同じで、違うのは時間・確率・定跡（むずかしいだけ）")
    func onlyTimeAndProbabilityDiffer() {
        let engines = CPUStrength.allCases.map { SimpleMinimaxEngine(level: $0.rawValue) }
        #expect(engines.allSatisfy { $0.depth == SimpleMinimaxEngine.maxDepth && $0.usePositional && $0.useQuiescence })
        #expect(engines.map(\.useBook) == [false, false, false, true])
    }

    @Test("最善手の確率は上の段階ほど高く、むずかしいは 100%・外したときの損の幅は共通")
    func probabilitiesAreOrdered() {
        let p = CPUStrength.allCases.map { SimpleMinimaxEngine(level: $0.rawValue).policy }
        #expect(p[3].isExact && p[3].bestMoveProbability == 1)
        #expect(p[0].bestMoveProbability >= 0 && p[0].bestMoveProbability <= p[1].bestMoveProbability
                && p[1].bestMoveProbability <= p[2].bestMoveProbability && p[2].bestMoveProbability < 1)
        #expect(p[0..<3].allSatisfy { !$0.isExact && $0.slipMargin == SimpleMinimaxEngine.slipMargin })
        #expect(SimpleMinimaxEngine.slipMargin < PieceValue.base(.gold), "外しでも金より大きい駒は損しない")
    }

    /// 確率・損の幅は PR #1461 の勝率表（200 局×先後入れ替え・上の負けが 3% 以下）で決めた値。
    /// 変えるときは同じ計測（`Scripts/shogi-cpu-bench`）をやり直して表を更新する。
    @Test("最善手の確率は実測で決めた 0% / 10% / 50% / 100%、損の幅は銀 1 枚ぶん")
    func probabilitiesArePinnedToTheMeasurement() {
        let p = CPUStrength.allCases.map { SimpleMinimaxEngine(level: $0.rawValue).policy.bestMoveProbability }
        #expect(p == [0, 0.1, 0.5, 1])
        #expect(SimpleMinimaxEngine.slipMargin == PieceValue.base(.silver))
    }
}

/// 同じ局面を段階に解かせ、**実際に選ぶ手**を固定する（#502）。最善手を外す確率は切ってあるので、
/// 読み（深さ 5）だけを見る。いずれも駒が少ない局面なので、深さ 5 でも一瞬で返る。
@Suite("将棋の難易度: 読みの下限（#502）")
struct ShogiDifficultyLadderTests {

    /// 5e の金で 5d の歩を取れるが、5c の金に取り返される。取り返す手段は無い（＝2手先で駒損）。
    private let poisonedPawn = "k8/9/4g4/4p4/4G4/9/9/9/K8 b - 1"

    /// 上と同じ形で 5i に飛車が利いている。金で取る → 金で取り返される → 飛車で取り返す。
    /// 2手先では −500、4手先では +100（歩 1 枚ぶんの得）。
    private let smallGainBehindRecapture = "k8/9/4g4/4p4/4G4/9/9/9/K3R4 b - 1"

    /// 5d の歩を守っているのが飛車で、こちらも 5i の飛車で取り返せる形。
    /// 2手先では −500（歩 100 − 金 600）だが、4手先では +500（さらに飛車 1000）。
    private let bigGainBehindRecapture = "8k/9/4r4/4p4/4G4/9/9/9/4R3K b - 1"

    /// 5d の飛車が無防備。
    private let freeRook = "4k4/9/9/4r4/4G4/9/9/9/4K4 b - 1"

    private let allLevels = CPUStrength.allCases.map(\.rawValue)

    @Test("タダの駒はどの段階も取る")
    func everyLevelTakesAFreePiece() async {
        for level in allLevels {
            let usi = await ShogiSelfPlay.untimed(level: level).bestMove(sfen: freeRook)
            #expect(usi == "5e5d", "level \(level) がタダの飛車を取っていない（\(usi ?? "-")）")
        }
    }

    @Test("取り返されるだけの駒はどの段階も取らない")
    func noLevelTakesTheHangingCapture() async {
        for level in allLevels {
            let usi = await ShogiSelfPlay.untimed(level: level).bestMove(sfen: poisonedPawn)
            #expect(usi != "5e5d", "level \(level) が金を歩と刺し違えている")
        }
    }

    /// 全段階が同じ探索を回す（#1461: `onlyTimeAndProbabilityDiffer`）ので、取り返しの奥の駒得は
    /// 時間内に読めればどの段階でも見える。代表として「ふつう」で確かめる。
    @Test("取り返しの奥の駒得は、時間内に読めれば取る")
    func seesTheGainBehindRecapture() async {
        let engine = ShogiSelfPlay.untimed(level: CPUStrength.normal.rawValue)
        #expect(await engine.bestMove(sfen: bigGainBehindRecapture) == "5e5d", "大きな駒得を逃している")
        #expect(await engine.bestMove(sfen: smallGainBehindRecapture) == "5e5d", "小さな駒得を逃している")
    }
}

@Suite("将棋の難易度: 弱い段階の設計（#502・#1461）", .timeLimit(.minutes(5)))
struct ShogiWeakLevelsDesignTests {

    @Test("むずかしいの設定（定跡・3 秒・100%）")
    func hardConfigurationMatchesTheDecision() {
        let hard = SimpleMinimaxEngine(level: CPUStrength.hard.rawValue)
        #expect(hard.useBook && hard.timeLimit == 3 && hard.policy.isExact)
    }

    /// 入門は最善手を外す割合が高く、同じ局面でも指す手が散る。むずかしいは決定的。
    @Test("入門は同じ局面でも指す手が散り、むずかしいは散らない")
    func noviceVariesItsMove() async {
        let sfen = "4k4/9/9/4p4/4G4/9/9/9/4K4 b - 1"
        var novice = Set<String>()
        for seed in UInt64(1)...40 {
            if let usi = await ShogiSelfPlay.untimed(level: CPUStrength.novice.rawValue, seed: seed, slips: true, depth: 2)
                .bestMove(sfen: sfen) { novice.insert(usi) }
        }
        #expect(novice.count > 1, "入門の手が 1 通りしかない（外しが効いていない）")
        var hard = Set<String>()
        for seed in UInt64(1)...10 {
            if let usi = await ShogiSelfPlay.untimed(level: CPUStrength.hard.rawValue, seed: seed, slips: true, depth: 2)
                .bestMove(sfen: sfen) { hard.insert(usi) }
        }
        #expect(hard.count == 1, "むずかしいの手が散っている")
    }
}
