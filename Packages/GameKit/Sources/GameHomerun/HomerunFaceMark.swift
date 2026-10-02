import Foundation
import HomerunCore

/// 結果に応じて打者の頭に重ねる記号（#1760）。空振りのぐるぐる目・頭上の星（#1681・`HomerunWhiffGag`）と同じ仕組みで、
/// 頭の骨に合わせて記号の絵を置く。判定（`HomerunJudge`）・飛距離は変えない。
///
/// 発生条件・表示の数値はすべて初期値で、会長 QA で調整する前提のため、このファイルの定数に集めてある。
enum HomerunFaceMark: Equatable, Sendable {
    case none
    /// キラキラ目: 打球を見送る間、目を星にして頭の横にもきらめきを出す。
    case sparkle
    /// 怒りマーク: 頭の横に赤い怒りマークを出す。
    case angry
    /// 柵越えを打った次の球の構え（#1762）: 球を待つ間、目だけを星にする（頭の横のきらめきは出さない）。
    case waitingSparkle

    // MARK: 発生

    /// 怒りマークを出す空振りの連続回数（初期値 2 球連続以上）。
    static let angryStreak = 2

    /// 1 球の結果から記号を決める（純粋な値）。
    /// - `swung`: 振ったか（見送りは記号を出さない）。
    /// - `whiffGag`: 回って倒れる演出（ぐるぐる目）を出す球か。出す球はぐるぐる目を優先し、怒りマークは重ねない。
    /// - `whiffStreak`: この球を含む、振った空振りの連続回数。
    /// - `isNewBest`: この球で挑戦が終わり、自己ベストを更新したか。
    static func decide(ball: HomerunBattedBall?, swung: Bool, whiffGag: Bool, whiffStreak: Int, isNewBest: Bool) -> HomerunFaceMark {
        guard swung, let ball else { return .none }
        switch ball.kind {
        case .miss:
            return !whiffGag && whiffStreak >= angryStreak ? .angry : .none
        case .foul:
            return .none
        case .inPlay, .fenceHit, .homer:
            // ジャストの当たり・柵越え・自己ベスト更新。
            return ball.timing == .just || ball.kind == .homer || isNewBest ? .sparkle : .none
        }
    }

    /// 柵越え（場外・ポール直撃・月を含む）を打った球の次の球の構えに出す記号（#1762）。次の球を打つ・見送るまでの 1 球だけ。
    /// 挑戦が終わる球（10 球目・月が割れた球）の次は無いので出さない。
    static func waiting(after ball: HomerunBattedBall?, challengeFinished: Bool) -> HomerunFaceMark {
        ball?.kind == .homer && !challengeFinished ? .waitingSparkle : .none
    }

    // MARK: 時間

    /// 記号が出始めるコマ（クリップの 1 始まり。振り抜きの打点は約 26 コマ目・フォロースルーは 31 コマ目〜）と、広がりきるまで（秒）。
    static let appearFrame: Double = 31
    static let appearGrow: TimeInterval = 0.15

    // MARK: 大きさ・置き方（m・頭の骨の局所を基準）

    /// キラキラ目の星の外側の半径（目の飾りと同じ位置に貼る）。
    static let sparkleEyeRadius: Float = 0.05
    /// きらめき（頭の横の小さな星）の外側の半径（打席のカメラは遠い・`HomerunWhiffGag.starSize` と同じ考え方）と、頭の中心からの横・上の距離。
    static let sparkleSize: Float = 0.075
    static let sparkleSide: Float = 0.24
    static let sparkleLift: Float = 0.12
    /// きらめきの明滅（回/秒）と振れ幅（割合）。
    static let twinkleRate: Double = 2.5
    static let twinkleDepth: Float = 0.25

    /// 怒りマークの大きさ（m・外側の半径）・頭の中心からの横と上の距離・脈打つ速さ（回/秒）と振れ幅（割合）。
    static let angrySize: Float = 0.14
    static let angrySide: Float = 0.22
    static let angryLift: Float = 0.2
    static let angryPulseRate: Double = 3
    static let angryPulseDepth: Float = 0.18

    /// 構えのキラキラ目の明滅（回/秒）と振れ幅（割合）。
    static let waitingTwinkleRate: Double = 2
    static let waitingTwinkleDepth: Float = 0.12

    /// 出始めから `t` 秒後の明滅の係数（1 を中心に ±`depth`）。
    static func pulse(since t: TimeInterval, rate: Double, depth: Float) -> Float {
        1 + depth * Float(sin(t * rate * 2 * .pi))
    }
}
