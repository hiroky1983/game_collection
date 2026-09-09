import Testing
import Foundation
@testable import GameShogi

/// 難易度カーブの回帰テスト（#502）。
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
/// 自己対戦は `timeLimit` を実測の 100 倍以上に取って**深さで決まる**状態にしてから行う。
/// 実時間で打ち切られると、同じテストが実行環境の速さで別の結果を返す。
enum ShogiSelfPlay {
    /// 決定的な擬似乱数（ランダム役の手を再現可能にする）。
    struct Rand {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
        mutating func int(_ upper: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let mixed = state ^ (state >> 33)
            return upper <= 0 ? 0 : Int(mixed % UInt64(upper))
        }
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
        var rng = Rand(seed: seed)
        for ply in 0..<maxPlies {
            let moves = pos.legalMoves()
            if moves.isEmpty {
                return Result(material: material(pos), plies: ply, mated: pos.sideToMove)
            }
            let engine = pos.sideToMove == .black ? black : white
            var chosen = moves[rng.int(moves.count)]
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

    /// 下方調整する前の「弱」（深さ 3 + 静止探索）。調整で本当に弱くなったかを測る基準。
    static let previousWeak = SimpleMinimaxEngine(
        depth: 3, usePositional: false, useQuiescence: true, useBook: false, timeLimit: 30)

    /// 出荷している難易度を、**時間で打ち切られない形**にして返す（探索設定はそのまま）。
    ///
    /// 出荷値の `timeLimit`（0.5〜1.5 秒）はデバッグビルドでは実際に効いてしまい、
    /// そのとき返る手は同時に走っている他のテストの負荷で変わる。テストが CPU の
    /// 混み具合で赤くなるのを避けるため、上限だけ十分大きい値へ差し替えて深さで決まる状態にする。
    static func untimed(level: Int) -> SimpleMinimaxEngine {
        let shipped = SimpleMinimaxEngine(level: level)
        return SimpleMinimaxEngine(
            depth: shipped.depth, usePositional: shipped.usePositional,
            useQuiescence: shipped.useQuiescence, useBook: shipped.useBook, timeLimit: 30)
    }

    /// 出荷している「弱」（探索設定は `level: 0` そのまま、時間の上限だけ外したもの）。
    static var currentWeak: SimpleMinimaxEngine { untimed(level: 0) }
}

@Suite("将棋の難易度: 3段階の設計（#502）")
struct ShogiDifficultyConfigTests {

    /// 表示している文言と探索の中身が一致していること（#416 の教訓）。
    /// 「弱=駒得だけ」「普通=囲いを作る」「強=定跡＋深読み」。
    @Test("表示文言と探索の中身が一致している")
    func labelsMatchTheSearch() {
        let weak = SimpleMinimaxEngine(level: 0)
        let normal = SimpleMinimaxEngine(level: 1)
        let strong = SimpleMinimaxEngine(level: 2)

        // 弱「駒得だけ」= 位置評価も静止探索も定跡も持たない。
        #expect(!weak.usePositional)
        #expect(!weak.useQuiescence)
        #expect(!weak.useBook)
        // 普通「囲いを作る」= 位置評価（kingSafety を含む）を持つ。定跡は持たない。
        #expect(normal.usePositional)
        #expect(!normal.useBook)
        // 強「定跡＋深読み」= 定跡を持ち、深さが最大。
        #expect(strong.useBook)
    }

    @Test("探索の深さは 弱 < 普通 < 強 の順で単調")
    func depthsAreOrdered() {
        #expect(SimpleMinimaxEngine(level: 0).depth < SimpleMinimaxEngine(level: 1).depth)
        #expect(SimpleMinimaxEngine(level: 1).depth < SimpleMinimaxEngine(level: 2).depth)
    }

    /// #502 の下方調整の実体。深さを 3 → 2 に落とし、静止探索を切った。
    /// 自己対戦のテストはこの値を読んで対戦相手を組み立てるので、ここで出荷値を固定しておく。
    @Test("「弱」は深さ 2・静止探索なしまで下げてある")
    func weakLevelIsTurnedDown() {
        let weak = SimpleMinimaxEngine(level: 0)
        #expect(weak.depth == 2)
        #expect(!weak.useQuiescence)
        #expect(weak.timeLimit == 0.5)
    }

    /// #502 の受け入れ条件「調整後も『強』の棋力が現状から落ちていないこと」。
    /// 下方調整は level 0 だけに閉じており、普通・強の探索設定は 1 ビットも動かさない。
    @Test("普通・強の設定は下方調整の前後で変わっていない")
    func strongLevelsAreUntouched() {
        let normal = SimpleMinimaxEngine(level: 1)
        #expect(normal.depth == 4)
        #expect(normal.useQuiescence)
        #expect(normal.timeLimit == 1.0)

        let strong = SimpleMinimaxEngine(level: 2)
        #expect(strong.depth == 5)
        #expect(strong.useQuiescence)
        #expect(strong.usePositional)
        #expect(strong.timeLimit == 1.5)
    }
}

/// 同じ局面を3段階に解かせ、**実際に選ぶ手**で 弱 < 普通 < 強 を固定する（#502）。
///
/// 設定の比較（深さの単調性）だけでは、評価や探索が退行して「弱」が「普通」に勝つように
/// なっても気付けない。ここでは「取ってから取り返し合いが何手続くか」を変えた局面を並べ、
/// **深く読める段階ほど、取り返しの奥にある駒得を取りに行く**ことを着手で確認する。
/// いずれも駒が少ない局面なので、深さ 5 でも一瞬で返る。
@Suite("将棋の難易度: 段階ごとの読みの深さ（#502）")
struct ShogiDifficultyLadderTests {

    /// 5e の金で 5d の歩を取れるが、5c の金に取り返される。取り返す手段は無い（＝2手先で駒損）。
    /// **どの段階も取ってはいけない。** 深さ 1 まで落とすとここで金を捨てる（実測）。
    private let poisonedPawn = "k8/9/4g4/4p4/4G4/9/9/9/K8 b - 1"

    /// 上と同じ形で 5i に飛車が利いている。金で取る → 金で取り返される → 飛車で取り返す。
    /// 2手先では −500、4手先では +100（歩 1 枚ぶんの得）。
    /// **深さ 5 の「強」だけが取りに行く**（「普通」は +100 より駒の働きを採る）。
    private let smallGainBehindRecapture = "k8/9/4g4/4p4/4G4/9/9/9/K3R4 b - 1"

    /// 5d の歩を守っているのが飛車で、こちらも 5i の飛車で取り返せる形。
    /// 2手先では −500（歩 100 − 金 600）だが、4手先では +500（さらに飛車 1000）。
    /// **深さ 2 の「弱」は取らず、深さ 4 の「普通」・深さ 5 の「強」は取る。**
    private let bigGainBehindRecapture = "8k/9/4r4/4p4/4G4/9/9/9/4R3K b - 1"

    /// 5d の飛車が無防備。**どの段階も取る**（弱がランダムに落ちていないことの下限）。
    private let freeRook = "4k4/9/9/4r4/4G4/9/9/9/4K4 b - 1"

    @Test("タダの駒はどの段階も取る")
    func everyLevelTakesAFreePiece() async {
        for level in 0...2 {
            let usi = await ShogiSelfPlay.untimed(level: level).bestMove(sfen: freeRook)
            #expect(usi == "5e5d", "level \(level) がタダの飛車を取っていない（\(usi ?? "-")）")
        }
    }

    @Test("取り返されるだけの駒はどの段階も取らない")
    func noLevelTakesTheHangingCapture() async {
        for level in 0...2 {
            let usi = await ShogiSelfPlay.untimed(level: level).bestMove(sfen: poisonedPawn)
            #expect(usi != "5e5d", "level \(level) が金を歩と刺し違えている")
        }
    }

    /// 弱 < 普通。取り返しの奥に飛車ぶんの駒得がある局面で、深さ 2 では見えず深さ 4 では見える。
    @Test("取り返しの奥の大きな駒得は「普通」以上だけが取りに行く")
    func onlyNormalAndAboveTakeTheBigGain() async {
        #expect(await ShogiSelfPlay.untimed(level: 0).bestMove(sfen: bigGainBehindRecapture) != "5e5d",
                "「弱」が4手先の駒得を読めている（深さ 2・静止探索なしが効いていない）")
        #expect(await ShogiSelfPlay.untimed(level: 1).bestMove(sfen: bigGainBehindRecapture) == "5e5d",
                "「普通」が4手先の駒得を逃している（棋力が落ちている）")
        #expect(await ShogiSelfPlay.untimed(level: 2).bestMove(sfen: bigGainBehindRecapture) == "5e5d",
                "「強」が4手先の駒得を逃している（棋力が落ちている）")
    }

    /// 普通 < 強。得が歩 1 枚ぶんしかない局面では、深さ 5 の「強」だけが取りに行く。
    @Test("取り返しの奥の小さな駒得は「強」だけが取りに行く")
    func onlyStrongTakesTheSmallGain() async {
        #expect(await ShogiSelfPlay.untimed(level: 0).bestMove(sfen: smallGainBehindRecapture) != "5e5d",
                "「弱」が3手先の駒得を読めている")
        #expect(await ShogiSelfPlay.untimed(level: 1).bestMove(sfen: smallGainBehindRecapture) != "5e5d",
                "「普通」の読みが「強」と同じになっている（段階の差が消えている）")
        #expect(await ShogiSelfPlay.untimed(level: 2).bestMove(sfen: smallGainBehindRecapture) == "5e5d",
                "「強」が3手先の駒得を逃している（棋力が落ちている）")
    }
}

@Suite("将棋の難易度: 「弱」の下方調整（#502）", .timeLimit(.minutes(5)))
struct ShogiWeakLevelSelfPlayTests {

    /// 調整の向きを固定する。旧「弱」（深さ 3 + 静止探索）と先後を入れ替えて 2 局指し、
    /// **旧のほうが駒得で上回り、新が旧を詰ますことは無い**ことを確認する。
    /// 双方とも時間では打ち切られないので結果は決定的（環境の速さに依存しない）。
    @Test("新しい「弱」は調整前の「弱」に勝てない")
    func newWeakIsWeakerThanTheOldWeak() async {
        let old = ShogiSelfPlay.previousWeak
        let new = ShogiSelfPlay.currentWeak

        let oldAsBlack = await ShogiSelfPlay.play(black: old, white: new, seed: 7, maxPlies: 100)
        let oldAsWhite = await ShogiSelfPlay.play(black: new, white: old, seed: 7, maxPlies: 100)

        // 旧視点の駒得の合計。先手視点の値なので、後手番の局は符号を反転する。
        let oldMaterial = oldAsBlack.material - oldAsWhite.material
        #expect(oldMaterial > 0, "調整後の「弱」が旧「弱」に駒得で負けていない（合計 \(oldMaterial)）")
        #expect(oldAsBlack.mated != .black, "旧「弱」が詰まされている")
        #expect(oldAsWhite.mated != .white, "旧「弱」が詰まされている")
    }

    /// 弱くしすぎて「ただの雑な手」に落ちていないことの下限。ランダムに指す相手には
    /// 先後どちらでも大差で駒得する。
    @Test("新しい「弱」はランダムな相手には大差で勝つ")
    func newWeakStillCrushesRandomPlay() async {
        let new = ShogiSelfPlay.currentWeak

        let asBlack = await ShogiSelfPlay.play(black: new, white: nil, seed: 13, maxPlies: 120)
        #expect(asBlack.material > 2_000, "先手の「弱」が駒得できていない（\(asBlack.material)）")

        let asWhite = await ShogiSelfPlay.play(black: nil, white: new, seed: 13, maxPlies: 120)
        #expect(asWhite.material < -2_000, "後手の「弱」が駒得できていない（\(asWhite.material)）")
    }
}
