import Testing
import Foundation
import CoreEngine
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

    /// 下方調整する前の「弱」（深さ 3 + 静止探索）。調整で本当に弱くなったかを測る基準。
    static let previousWeak = SimpleMinimaxEngine(
        depth: 3, usePositional: false, useQuiescence: true, useBook: false, timeLimit: .infinity)

    /// 出荷している難易度を、**時間で打ち切られない形**にして返す（探索設定はそのまま）。
    ///
    /// 出荷値の `timeLimit`（0.5〜1.5 秒）はデバッグビルドでは実際に効いてしまい、
    /// そのとき返る手は同時に走っている他のテストの負荷で変わる。テストが CPU の
    /// 混み具合で赤くなるのを避けるため、`timeLimit: .infinity` で締切そのものを無くし、
    /// 深さだけで決まる状態にする（有限の大きい値だと、高負荷時にその値を超えて打ち切りが
    /// 発生しうる。#1187: 実測で60秒設定が360秒かかるケースがあった）。
    ///
    /// **「強」の探索深さ上限は #1134 で 32（実質無制限）に緩めた**ため、そのまま使うと
    /// 反復深化が時間（30 秒）で打ち切られてしまい、この関数の「深さで決まる」という前提が
    /// 崩れる（実測: 軽い局面でも depth 32 は 10 秒あっても到達しない）。ここでのテストが
    /// 要求する最大の読みは `smallGainBehindRecapture` の深さ 5（#502）なので、上限が
    /// 大きい設定は絞って探索を自然終了させる（#1134 の実測 0.03〜0.31 秒は 7 まで。#1397 で「むずかしい」の
    /// 出荷上限を 7 にしたが、ここは従来どおり 5 に絞る＝デバッグビルドの CI 時間を延ばさない）。
    ///
    /// - Parameter seed: 「入門」（#1174）の乱択を再現したいときに渡す。他の段は乱数を使わない。
    ///
    /// - Parameter slips: `true` なら出荷どおり「見逃し」（#1397）を起こす。既定は `false`
    ///   （読みの深さだけを固定するテストが確率で揺れないように）。
    static func untimed(level: Int, seed: UInt64? = nil, slips: Bool = false) -> SimpleMinimaxEngine {
        let shipped = SimpleMinimaxEngine(level: level)
        return SimpleMinimaxEngine(
            depth: min(shipped.depth, 5), usePositional: shipped.usePositional,
            useQuiescence: shipped.useQuiescence, useBook: shipped.useBook, timeLimit: .infinity,
            nodeLimit: nil, policy: slips ? shipped.policy : shipped.policy.withoutSlip, seed: seed)
    }

    /// 出荷している「弱」（探索設定は `level: 0` そのまま、時間の上限だけ外したもの）。
    static var currentWeak: SimpleMinimaxEngine { untimed(level: 0) }

    /// 呼び出し時点で既に期限切れの設定（#1196 回帰テスト用）。`timeLimit` に負の値を渡すと
    /// `SearchContext.init` の `Date().addingTimeInterval` がその場で過去の時刻になる。
    static func expired(level: Int, seed: UInt64? = nil) -> SimpleMinimaxEngine {
        let shipped = SimpleMinimaxEngine(level: level)
        return SimpleMinimaxEngine(
            depth: shipped.depth, usePositional: shipped.usePositional,
            useQuiescence: shipped.useQuiescence, useBook: shipped.useBook, timeLimit: -1,
            nodeLimit: nil, policy: shipped.policy.withoutSlip, seed: seed)
    }
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
    /// 下方調整は level 0 だけに閉じており、普通の探索設定は 1 ビットも動かさない。
    /// **「強」の探索深さ上限は #1134 で 5 → 32 に上げていたが、v1.1.6 で一旦取り消した**
    /// （会長指摘・2026-09-22。「ガチ」の見送りと合わせ、v1.1.5 から公開されている 5 に戻す）。
    @Test("普通の探索深さ上限は v1.1.5 の値のまま・強は 7（打ち切りは局面数で決める・#1397）")
    func strongLevelsAreUntouched() {
        let normal = SimpleMinimaxEngine(level: 1)
        #expect(normal.depth == 4)
        #expect(normal.useQuiescence)

        let strong = SimpleMinimaxEngine(level: 2)
        #expect(strong.depth == 7, "深さ上限は 5 → 7（#1397: 打ち切りは局面数で決め、ふつうに負けない深さまで読む）")
        #expect(strong.useQuiescence)
        #expect(strong.usePositional)
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

    /// #1174 で足した両端（入門・ガチ）も含めた全段階。番号は 0 始まりではないので
    /// `CPUStrength` から引く。
    private let allLevels = CPUStrength.allCases.map(\.rawValue)

    @Test("タダの駒はどの段階も取る")
    func everyLevelTakesAFreePiece() async {
        for level in allLevels {
            let usi = await ShogiSelfPlay.untimed(level: level).bestMove(sfen: freeRook)
            #expect(usi == "5e5d", "level \(level) がタダの飛車を取っていない（\(usi ?? "-")）")
        }
    }

    /// 入門は読みが自分の手 1 手だけ（#1397）なので、取り返される取りを指すことがある
    /// （只で取られる手も一定の確率で指す、が入門の設計）。簡単以上は取らない。
    @Test("取り返されるだけの駒は簡単以上の段階は取らない")
    func noLevelTakesTheHangingCapture() async {
        for level in allLevels where level != CPUStrength.novice.rawValue {
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

// MARK: - 入門・ガチ（#1174）

/// 両端に足した 2 段（#1174）。
///
/// **「入門 < 簡単」の実測はこのファイルの方針どおり CI に置かない。** 深さ 2 どうしの
/// 直接対戦ではどちらも駒損を避けるだけで取り合いが起こらず（実測: 100手2局の駒得差 0）、
/// 差を見るには読める相手を挟む必要がある。旧「弱」（深さ 3 + 静止探索）を相手に
/// 80手2局×先後で測ると **簡単 −10,200 / 入門 −14,000**（デバッグビルド実測。
/// 相手が同じなので符号ではなく差を読む）で、入門のほうが負け込む。
/// この 1 組だけで 213 秒かかるため、CI には①設定 ②同じ局面で手が散ること
/// ③只捨て・タダ取りの下限（`ShogiDifficultyLadderTests` が全 5 段階で見る）を置く。
@Suite("将棋の難易度: 入門（#1174）", .timeLimit(.minutes(5)))
struct ShogiNoviceAndSeriousTests {

    private static let novice = CPUStrength.novice.rawValue

    /// 「入門」は自分の手 1 手だけを読む（深さ 1・#1397）。深さ 2 のままだと、簡単との
    /// 対戦で簡単が詰まされる局が残り「上の段階は下の段階に負けない」を満たせなかった
    /// （48 局中 1〜2 局。深さ 1 なら 0 局）。取り返される取りを指すのは設計どおり。
    @Test("入門は簡単より浅く読み、読み以外の設定は簡単と同じ")
    func noviceReadsShallowerThanEasy() {
        let novice = SimpleMinimaxEngine(level: Self.novice)
        let easy = SimpleMinimaxEngine(level: CPUStrength.easy.rawValue)
        #expect(novice.isNovice)
        #expect(!easy.isNovice)
        #expect(novice.depth == 1 && easy.depth == 2)
        #expect(novice.useQuiescence == easy.useQuiescence)
        #expect(novice.usePositional == easy.usePositional)
        #expect(novice.useBook == easy.useBook)
        #expect(novice.timeLimit == easy.timeLimit)
        #expect(novice.nodeLimit == nil && easy.nodeLimit == nil)
        // 許す損は歩 1 枚未満。駒を只で捨てる手はこの幅に入らない。
        #expect(SimpleMinimaxEngine.noviceMargin < PieceValue.base(.pawn))
    }

    /// 「ガチ」は v1.1.6 で一旦見送った（会長指摘・2026-09-22。強さを実感できず調整が必要と判断）。
    /// `#1134`で試した深さ上限32への変更・`#1174`の「ガチ」（深さ7・3.0秒）も一旦取り消し、
    /// v1.1.5から公開されている「むずかしい」（深さ5・1.5秒）の設定へ戻す。
    @Test("むずかしいの探索設定（深さ上限 7・定跡・静止探索・位置評価）")
    func hardConfigurationMatchesShippedValue() {
        let hard = SimpleMinimaxEngine(level: CPUStrength.hard.rawValue)
        #expect(hard.depth == 7)
        #expect(hard.useBook && hard.useQuiescence && hard.usePositional)
        #expect(!hard.isNovice)
    }

    /// 「入門」は同じ局面でも手が散る（＝選び方を崩している）。
    /// 「簡単」は乱数を使わないので必ず同じ手になる。
    @Test("入門は同じ局面でも指す手が散る")
    func noviceVariesItsMove() async {
        let sfen = Position.start().toSFEN()
        var noviceMoves = Set<String>()
        for seed in UInt64(1)...30 {
            if let usi = await ShogiSelfPlay.untimed(level: Self.novice, seed: seed).bestMove(sfen: sfen) {
                noviceMoves.insert(usi)
            }
        }
        #expect(noviceMoves.count > 1, "入門の手が 1 通りしかない（乱択が効いていない）")

        // 見逃しを切った「簡単」は決定的（見逃しの確率だけが乱数を使う）。
        var easyMoves = Set<String>()
        for _ in 0..<5 {
            if let usi = await ShogiSelfPlay.untimed(level: CPUStrength.easy.rawValue)
                .bestMove(sfen: sfen) { easyMoves.insert(usi) }
        }
        #expect(easyMoves.count == 1, "前提が崩れている: 見逃しを除いた簡単は決定的")
    }

    /// 呼び出し時点で既に `deadline` を過ぎていても、`policyMove` は評価済みの候補から選ぶ
    /// （#1196）。安全フロア（`minNoviceEvaluations`）を入れる前は、1手も評価できないまま
    /// `orderedMoves.first` を無条件に返していたため、乱数の種を変えても常に同じ手になっていた。
    @Test("期限切れでも評価済みの候補から選ぶ（1手固定に戻らない）")
    func noviceStillVariesWhenDeadlineAlreadyPassed() async {
        let sfen = Position.start().toSFEN()
        var moves = Set<String>()
        for seed in UInt64(1)...30 {
            if let usi = await ShogiSelfPlay.expired(level: Self.novice, seed: seed).bestMove(sfen: sfen) {
                moves.insert(usi)
            }
        }
        #expect(moves.count > 1, "期限切れ時に手が1通りしかない = 1件も評価されず orderedMoves.first に固定されている")
    }

    /// 安全フロアの評価は `negamax` の期限判定も無効化しないと、相手の応手を読まない
    /// 静的評価（`evaluate(pos)`）のまま候補に残り、取り返される取りを選びうる
    /// （CodeRabbit 指摘・PR #1199）。合法手を金の1手（取り返される取り）と玉の2手（安全）の
    /// 計3手だけに絞った局面（角に追い込んだ玉・金の退路は自駒でふさぐ）を使い、
    /// 安全フロア（3手）の範囲内だけで判定できるようにした。
    /// - 9a の金は 8a の歩しか取れない（前方・後方は盤外か自駒でふさいでいる）。
    ///   取ると 8b の金に取り返される。
    /// - 1a の玉は 2a / 2b の2箇所だけ動ける（前方は盤外、後方は自駒でふさいでいる）。
    @Test("期限切れでも取り返されるだけの駒は取らない（合法手を3手に限定した局面・簡単）")
    func expiredEasyAvoidsTheHangingCaptureInMinimalPosition() async {
        let sfen = "Gp6K/Pg6P/9/9/9/9/9/9/9 b - 1"
        for seed in UInt64(1)...30 {
            let usi = await ShogiSelfPlay.expired(level: CPUStrength.easy.rawValue, seed: seed).bestMove(sfen: sfen)
            #expect(usi != "9a8a", "期限切れの簡単が金を歩と刺し違えている（seed \(seed)・\(usi ?? "nil")）")
        }
    }

    /// 弱くしても壊れていないことの下限: でたらめに指す相手には大差で駒得する
    /// （「弱」に対する `newWeakStillCrushesRandomPlay` と同じ物差し）。
    @Test("入門もランダムな相手には大差で勝つ")
    func noviceStillCrushesRandomPlay() async {
        let novice = ShogiSelfPlay.untimed(level: Self.novice, seed: 13)

        let asBlack = await ShogiSelfPlay.play(black: novice, white: nil, seed: 13, maxPlies: 120)
        #expect(asBlack.material > 2_000, "先手の「入門」が駒得できていない（\(asBlack.material)）")

        let asWhite = await ShogiSelfPlay.play(black: nil, white: novice, seed: 13, maxPlies: 120)
        #expect(asWhite.material < -2_000, "後手の「入門」が駒得できていない（\(asWhite.material)）")
    }
}
