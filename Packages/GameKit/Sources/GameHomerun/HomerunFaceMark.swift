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
    /// 怒りマーク（#1769）: 振った空振りの次の球の構えで、頭の横に赤い怒りマークを出す（弾ませてプンプンさせる）。
    case waitingAngry
    /// 柵越えを打った次の球の構え（#1762）: 球を待つ間、目だけを星にする（頭の横のきらめきは出さない）。
    case waitingSparkle

    // MARK: 発生

    /// 構え（次の球を待つ間）に出す記号か。構えの記号は振っていない段階（構え・踏み込み）で置く。
    var isWaiting: Bool { self == .waitingSparkle || self == .waitingAngry }

    /// 1 球の結果から記号を決める（純粋な値）。
    /// - `swung`: 振ったか（見送りは記号を出さない）。
    /// - `isNewBest`: この球で挑戦が終わり、自己ベストを更新したか。
    static func decide(ball: HomerunBattedBall?, swung: Bool, isNewBest: Bool) -> HomerunFaceMark {
        guard swung, let ball else { return .none }
        switch ball.kind {
        case .miss, .foul:
            return .none
        case .inPlay, .fenceHit, .homer:
            // ジャストの当たり・柵越え・自己ベスト更新。
            return ball.timing == .just || ball.kind == .homer || isNewBest ? .sparkle : .none
        }
    }

    /// 次の球の構えに出す記号。次の球を打つ・見送るまでの 1 球だけ。挑戦が終わる球（10 球目・月が割れた球）の次は無いので出さない。
    /// - 柵越え（場外・ポール直撃・月を含む）を打った次はキラキラ目（#1762）。
    /// - 振った空振り（見送りは数えない）の次は怒りマーク（#1769）。
    static func waiting(after ball: HomerunBattedBall?, swung: Bool, challengeFinished: Bool) -> HomerunFaceMark {
        guard let ball, !challengeFinished else { return .none }
        if ball.kind == .homer { return .waitingSparkle }
        return swung && ball.kind == .miss ? .waitingAngry : .none
    }

    // MARK: 時間

    /// 記号が出始めるコマ（クリップの 1 始まり。振り抜きの打点は約 26 コマ目・フォロースルーは 31 コマ目〜）と、広がりきるまで（秒）。
    static let appearFrame: Double = 31
    static let appearGrow: TimeInterval = 0.15

    // MARK: 大きさ・置き方（m・頭の骨の局所を基準）

    /// キラキラ目の星の外側の半径（目の飾りと同じ位置に貼る）。
    static let sparkleEyeRadius: Float = 0.05
    /// きらめき（頭の横の小さな星）の外側の半径（前のカメラは遠い・`HomerunWhiffGag.starSize` と同じ考え方）と、頭の中心からの横・上の距離。
    static func sparkleSize(back: Bool) -> Float { back ? 0.055 : 0.075 }
    static let sparkleSide: Float = 0.24
    static let sparkleLift: Float = 0.12
    /// きらめきの明滅（回/秒）と振れ幅（割合）。
    static let twinkleRate: Double = 2.5
    static let twinkleDepth: Float = 0.25

    /// 怒りマークの大きさ（m・外側の半径）・頭の中心からの横と上の距離・脈打つ速さ（回/秒）と振れ幅（割合）・弾む高さ（m）。
    /// 「プンプン」に見えるよう、脈打ちを強めてぴょこぴょこ弾ませる。
    static func angrySize(back: Bool) -> Float { back ? 0.10 : 0.14 }
    static let angrySide: Float = 0.22
    static let angryLift: Float = 0.2
    static let angryPulseRate: Double = 4
    static let angryPulseDepth: Float = 0.3
    static let angryHop: Float = 0.03

    /// 弾み（0 以上 `angryHop` 以下）。脈打ちと同じ速さで、跳ねて着く。
    static func angryBounce(since t: TimeInterval) -> Float {
        angryHop * abs(sin(Float(t * angryPulseRate * .pi)))
    }

    /// 構えのキラキラ目の明滅（回/秒）と振れ幅（割合）。
    static let waitingTwinkleRate: Double = 2
    static let waitingTwinkleDepth: Float = 0.12

    /// 出始めから `t` 秒後の明滅の係数（1 を中心に ±`depth`）。
    static func pulse(since t: TimeInterval, rate: Double, depth: Float) -> Float {
        1 + depth * Float(sin(t * rate * 2 * .pi))
    }
}
