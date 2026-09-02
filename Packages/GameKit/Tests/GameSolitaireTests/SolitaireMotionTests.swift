import Testing
import Foundation
import CoreGraphics
import Core
@testable import GameSolitaire

/// 配札・めくり・移動の演出（#421）。
///
/// 見た目そのものはシミュレータでしか確認できないので、**進捗 → 見え方の翻訳**・
/// **配る順と距離**・**長さの大小関係**をここで固定する。定数だけでは View 側の
/// 外し忘れを素通しするため、結線もブラックジャック（`BlackjackMotionTests`）と
/// 同じやり方でソースから見る。
@Suite("ソリティアの演出")
struct SolitaireMotionTests {

    typealias Motion = SolitaireMotion

    // MARK: - 受け入れ条件1a: 配札

    @Test("場札に配るのは 7 列ぶんの 28 枚で、順番に過不足も重複も無い")
    func dealOrderCoversEveryCardOnce() {
        var seen: Set<Int> = []
        for pile in 0..<SolitaireBoard.pileCount {
            // `SolitaireDealer.deal` は `pile` 列に `pile + 1` 枚配る。
            for depth in 0...pile {
                let order = Motion.dealOrder(pile: pile, depth: depth)
                #expect(order >= 0)
                #expect(order < Motion.dealtCardCount)
                #expect(seen.insert(order).inserted, "配る順が \(order) で重複した")
            }
        }
        #expect(seen.count == Motion.dealtCardCount)
        #expect(Motion.dealtCardCount == 28)
    }

    @Test("配る順は列ごとにまとまっていて、列の中では下の札が先に来る")
    func dealOrderFollowsTheDealer() {
        // `SolitaireDealer.deal` は 1 列目を配り切ってから 2 列目へ進む。演出もその順に揃える。
        for pile in 1..<SolitaireBoard.pileCount {
            let lastOfPrevious = Motion.dealOrder(pile: pile - 1, depth: pile - 1)
            #expect(Motion.dealOrder(pile: pile, depth: 0) == lastOfPrevious + 1)
        }
        for pile in 0..<SolitaireBoard.pileCount where pile > 0 {
            for depth in 1...pile {
                #expect(Motion.dealOrder(pile: pile, depth: depth)
                        > Motion.dealOrder(pile: pile, depth: depth - 1))
            }
        }
    }

    @Test("配る遅れは順番どおりに増え、異常な入力でも負にならない")
    func dealDelayGrowsWithOrder() {
        #expect(abs(Motion.dealDelay(pile: 0, depth: 0)) < 0.0001)
        #expect(abs(Motion.dealDelay(pile: 1, depth: 0) - Motion.dealStagger) < 0.0001)
        #expect(Motion.dealDelay(pile: 6, depth: 6) > Motion.dealDelay(pile: 6, depth: 0))
        // 段差が無くなると 28 枚が同時に現れて「配っている」と読めなくなる。
        #expect(Motion.dealStagger > 0)
        #expect(Motion.dealDelay(pile: -1, depth: -1) >= 0)
    }

    @Test("28 枚ぶんの段差を含めた配札全体の長さが定数と一致し、待たされ過ぎない")
    func dealTotalCoversEveryCard() {
        let expected = Motion.dealCardDuration
            + Motion.dealStagger * Double(Motion.dealtCardCount - 1)
        #expect(abs(Motion.dealTotalDuration - expected) < 0.0001)
        // 新規ゲームのたびに待つ時間なので、1 秒を超えると「配り終わるのを待つ」画面になる。
        #expect(Motion.dealTotalDuration <= 1.0)
    }

    @Test("札は左上（山札）の方向から飛んでくる")
    func dealStartsFromTheStock() {
        let metrics = SolitaireMetrics.faceMetrics(width: 48)

        // 山札は場札の上の行にあるので、どの札も必ず上（負方向）から来る。
        for pile in 0..<SolitaireBoard.pileCount {
            let offset = Motion.dealStartOffset(pile: pile, restY: 0, metrics: metrics)
            #expect(offset.height < 0)
        }

        // 山札は 1 列目の真上にあるので、1 列目は横に動かず、右の列ほど左から飛んでくる。
        #expect(abs(Motion.dealStartOffset(pile: 0, restY: 0, metrics: metrics).width) < 0.0001)
        var previous: CGFloat = 1
        for pile in 0..<SolitaireBoard.pileCount {
            let width = Motion.dealStartOffset(pile: pile, restY: 0, metrics: metrics).width
            #expect(width < previous)
            previous = width
        }

        // 列の深いところに置かれる札ほど、山札からの距離は遠い。
        let shallow = Motion.dealStartOffset(pile: 3, restY: 0, metrics: metrics).height
        let deep = Motion.dealStartOffset(pile: 3, restY: 60, metrics: metrics).height
        #expect(deep < shallow)

        // 異常な入力でも「下から湧く」向きに反転しないこと。
        #expect(Motion.dealStartOffset(pile: -1, restY: -100, metrics: metrics).height < 0)
        #expect(abs(Motion.dealStartOffset(pile: -1, restY: 0, metrics: metrics).width) < 0.0001)
    }

    // MARK: - 受け入れ条件1b: めくり

    @Test("反転の前半は裏・真横を越えたら表")
    func flipSwapsFaceAtHalfway() {
        #expect(Motion.showsFace(progress: 0) == false)
        #expect(Motion.showsFace(progress: 0.49) == false)
        #expect(Motion.showsFace(progress: 0.5) == true)
        #expect(Motion.showsFace(progress: 1) == true)
    }

    @Test("回転角は 0 度から 180 度まで単調に進み、範囲外は頭打ちになる")
    func flipDegreesAreMonotonicAndClamped() {
        #expect(abs(Motion.flipDegrees(progress: 0) - 0) < 0.0001)
        #expect(abs(Motion.flipDegrees(progress: 0.5) - 90) < 0.0001)
        #expect(abs(Motion.flipDegrees(progress: 1) - 180) < 0.0001)

        // バネ等で 0〜1 を外れた進捗が来ても、札が裏返り過ぎないこと。
        #expect(abs(Motion.flipDegrees(progress: -0.2) - 0) < 0.0001)
        #expect(abs(Motion.flipDegrees(progress: 1.2) - 180) < 0.0001)

        var previous = -1.0
        for step in 0...10 {
            let degrees = Motion.flipDegrees(progress: Double(step) / 10)
            #expect(degrees > previous)
            previous = degrees
        }
    }

    // MARK: - 演出のトーン

    @Test("演出のトーンは移動 < 配りの1枚 < めくりの順")
    func revealIsTheHeaviestEffect() {
        // 1 手ごとに何度も起きる移動がいちばん軽く、新しい情報が出るめくりがいちばん濃い。
        #expect(Motion.moveDuration < Motion.dealCardDuration)
        #expect(Motion.dealCardDuration < Motion.flipDuration)
    }

    // MARK: - 受け入れ条件1c: 移動（結線）

    @Test("View が配札・めくり・移動の演出に結線されている")
    func viewIsWiredToTheMotion() throws {
        let source = try Self.viewSource()

        // 1. 配札: 伏せ札と表向き札の両方が配りの演出を通っていること（定義 1 + 呼び出し 2）。
        #expect(
            Self.matchCount(of: #"SolitaireDealtCardView"#, in: source) >= 3,
            "場札が SolitaireDealtCardView を経由していない"
        )
        #expect(
            Self.matchCount(of: #"SolitaireMotion\.dealAppear\(pile:"#, in: source) == 1,
            "配札に段差付きのアニメーションが掛かっていない"
        )
        #expect(
            Self.matchCount(of: #"SolitaireMotion\.dealStartOffset\(pile:"#, in: source) == 1,
            "配札の開始位置が山札の方向になっていない"
        )
        #expect(
            Self.matchCount(of: #"dealing: model\.isFreshDeal"#, in: source) == 2,
            "配札の演出が「配ったばかりの盤面」以外でも走る/走らない状態になっている"
        )

        // 2. めくり: 捨て札と伏せ札からの露出が反転ビューを通っていること（定義 1 + 呼び出し 2）。
        #expect(
            Self.matchCount(of: #"SolitaireRevealCardView"#, in: source) >= 3,
            "捨て札・伏せ札の露出が SolitaireRevealCardView を経由していない"
        )
        #expect(
            Self.matchCount(of: #"SolitaireFlipCardView"#, in: source) >= 2,
            "反転そのものを描く Animatable なビューが失われている"
        )
        #expect(
            Self.matchCount(of: #"withGameAnimation\(SolitaireMotion\.flip\)"#, in: source) == 1,
            "めくりにアニメーションが掛かっていない"
        )
        #expect(
            Self.matchCount(of: #"SolitaireMotion\.flipDegrees\(progress:"#, in: source) == 1,
            "進捗から回転角への翻訳が View に直書きされている"
        )
        #expect(
            Self.matchCount(of: #"flips: model\.lastMoveWasDraw"#, in: source) == 1,
            "山めくりの 1 枚だけを返す条件が View 側で失われている"
        )
        #expect(
            Self.matchCount(of: #"flips: model\.revealedCardIDs\.contains\(card\.id\)"#, in: source) == 1,
            "伏せ札から出た札だけを返す条件が View 側で失われている"
        )

        // 3. 移動: 札の同一性が位置ではなく札に付いていること。
        //    `id: \.offset` に戻ると、動いた札は消えて生まれる扱いになり補間が効かなくなる。
        #expect(
            Self.matchCount(of: #"ForEach\(Array\(column\.(faceDown|faceUp)\.enumerated\(\)\), id: \\\.element\.id\)"#,
                            in: source) == 2,
            "場札の ForEach が札の id ではなく添字で並んでいる"
        )
        #expect(
            Self.matchCount(of: #"id: \\\.offset"#, in: source) == 0,
            "添字を identity にした ForEach が残っている（移動が補間されない）"
        )
        // 場札（伏せ・表）・捨て札・組札の 4 か所が同じ名前空間で繋がっていること。
        #expect(
            Self.matchCount(of: #"\.matchedGeometryEffect\(id: .+, in: cardMotion\)"#, in: source) == 4,
            "札の移動を繋ぐ matchedGeometryEffect が欠けている"
        )
        #expect(
            Self.matchCount(of: #"SolitaireMotion\.move"#, in: source) == 1,
            "盤面の移動にアニメーションが掛かっていない"
        )
        // 段差を `.offset` に戻すとレイアウト上の位置が変わらず、移動の補間が
        // 「札の位置」ではなく「列の上端」どうしを結んでしまう。
        #expect(
            Self.matchCount(of: #"\.padding\(\.top, restY\)"#, in: source) == 2,
            "場札の段差が余白ではなく offset に戻っている"
        )

        // Reduce Motion に追従しない素の `.animation(` / `withAnimation(` が
        // 紛れ込んでいないこと（#210）。
        #expect(
            Self.matchCount(of: #"[^e]\.animation\("#, in: source) == 0,
            "Reduce Motion に追従しない .animation( が使われている"
        )
        #expect(
            Self.matchCount(of: #"[^e]withAnimation\("#, in: source) == 0,
            "Reduce Motion に追従しない withAnimation( が使われている"
        )
    }

    // MARK: - ヘルパー

    private static func viewSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameSolitaireTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources/GameSolitaire/SolitaireView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func matchCount(of pattern: String, in source: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(
            in: source, range: NSRange(source.startIndex..., in: source)
        )
    }
}

// MARK: - めくりの対象の見つけ方

/// 「どの札が裏から表になったか」は手の種類からは決まらない（同じ `tableauToTableau` でも
/// 返る局面と返らない局面がある）ので、盤面どうしの差分で見る。
@Suite("ソリティアのめくり対象")
struct SolitaireRevealDiffTests {

    @Test("表向きが無くなった列で出てきた 1 枚だけを返す対象にする")
    func revealsTheUncoveredCard() {
        let hidden = SolitaireCard(.club, 7)
        let before = SolitaireBoard(tableau: [
            SolitairePile(faceDown: [hidden], faceUp: [SolitaireCard(.spade, 5)]),
            SolitairePile(faceUp: [SolitaireCard(.heart, 6)])
        ])
        var after = before
        let moved = after.apply(.tableauToTableau(from: 0, cardIndex: 0, to: 1))
        #expect(moved)

        // `normalize()` が伏せ札を 1 枚めくっている。
        #expect(after.tableau[0].faceUp == [hidden])
        #expect(SolitaireBoard.revealedCardIDs(before: before, after: after) == [hidden.id])
    }

    @Test("もともと表だった札は返す対象にしない")
    func alreadyFaceUpCardsAreNotRevealed() {
        let before = SolitaireBoard(tableau: [
            SolitairePile(faceUp: [SolitaireCard(.heart, 6), SolitaireCard(.spade, 5)]),
            SolitairePile(faceUp: [SolitaireCard(.diamond, 6)])
        ])
        var after = before
        // 上の 1 枚だけを動かす。列に残って一番上になる `♥6` は元から表なので返らない。
        let moved = after.apply(.tableauToTableau(from: 0, cardIndex: 1, to: 1))
        #expect(moved)
        #expect(after.tableau[0].faceUp == [SolitaireCard(.heart, 6)])
        #expect(SolitaireBoard.revealedCardIDs(before: before, after: after).isEmpty)
    }

    @Test("盤面が動かなければ返す対象は空")
    func noMoveRevealsNothing() {
        let board = SolitaireDealer.deal(seed: SolitaireDealer.verifiedSeeds[0])
        #expect(SolitaireBoard.revealedCardIDs(before: board, after: board).isEmpty)
    }

    @Test("置いたジョーカーは伏せ札から出てこないので返す対象にならない")
    func placedJokerIsNotRevealed() {
        let before = SolitaireBoard(
            tableau: [SolitairePile(faceDown: [SolitaireCard(.club, 7)],
                                    faceUp: [SolitaireCard(.spade, 5)])],
            jokerAvailable: true
        )
        var after = before
        let placed = after.apply(.placeJoker(pile: 0))
        #expect(placed)
        #expect(after.tableau[0].faceUp.last?.isJoker == true)
        #expect(SolitaireBoard.revealedCardIDs(before: before, after: after).isEmpty)
    }
}
