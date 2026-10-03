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
    /// 怒りマーク（#1769）: 振った空振りの次の球の構えで、頭の横に白い吹き出しに入れた赤い 💢 を出す（弾ませてプンプンさせる）。
    case waitingAngry
    /// 怒りが溜まった構え（#1797）: 💢 に加えて、顔の赤み（顔の赤い円＋両頬）と湯気を出す。怒りゲージが `angerStageThreshold` 以上のとき。
    case waitingAngryHot
    /// 柵越えを打った次の球の構え（#1762）: 球を待つ間、目だけを星にする（頭の横のきらめきは出さない）。
    case waitingSparkle

    // MARK: 発生

    /// 構え（次の球を待つ間）に出す記号か。構えの記号は振っていない段階（構え・踏み込み）で置く。
    var isWaiting: Bool { self == .waitingSparkle || self == .waitingAngry || self == .waitingAngryHot }

    /// 💢 を出す構えか（段階①・②）。
    var showsAngryMark: Bool { self == .waitingAngry || self == .waitingAngryHot }

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
    /// - 怒りゲージ（`anger`・この球を数えた後の値）が `angerStageThreshold` 以上なら、怒りマークは顔の赤みと湯気つきの段階②（#1797）。
    static func waiting(after ball: HomerunBattedBall?, swung: Bool, challengeFinished: Bool, anger: Int = 0) -> HomerunFaceMark {
        guard let ball, !challengeFinished else { return .none }
        if ball.kind == .homer { return .waitingSparkle }
        guard swung && ball.kind == .miss else { return .none }
        return anger >= angerStageThreshold ? .waitingAngryHot : .waitingAngry
    }

    // MARK: 怒りゲージ（#1797・裏パラメータ・画面には出さない）

    /// 振った空振りで `angerWhiffGain` 増え、当たり（ファウル含む）で `angerHitRelief` 減る（0 未満にしない）。見送りは変えない。
    /// `angerStageThreshold` 以上で段階②。挑戦の開始で 0。会長 QA で調整する前提で、数値はここの 3 つに集める。
    static let angerWhiffGain = 1
    static let angerHitRelief = 1
    static let angerStageThreshold = 3

    /// 1 球を締めた後の怒りゲージ。
    static func angerGauge(after ball: HomerunBattedBall?, swung: Bool, from gauge: Int) -> Int {
        guard swung, let ball else { return gauge }
        return ball.kind == .miss ? gauge + angerWhiffGain : max(gauge - angerHitRelief, 0)
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

    /// 怒りマーク（#1797）: 白い吹き出し（輪郭つき・頭の方へ向く尾つき）の中に、赤い「く」の字 4 本の 💢 を入れる。
    /// 吹き出しは頭の左横（カメラから見て左）・ひさしの高さ・カメラ側へ `angryForward`。脈打ち・弾みは吹き出しごと。
    /// 💢 の大きさ（m・外側の半径）は、モック v3（0.22）の約 6 割。吹き出しの半径はそれが余白をもって収まる大きさ。
    static let angrySize: Float = 0.13
    static let angryBubbleRadius: Float = 0.17
    /// 吹き出しの輪郭の太らせ幅（吹き出しの半径を 1 とした比）。
    static let angryBubbleRim: Float = 0.09
    /// 頭のてっぺんから見た吹き出しの中心: 左への距離・上（負 = 下）の距離（ひさしの高さ）・カメラ側への距離（m）。
    static let angrySide: Float = 0.55
    static let angryLift: Float = -0.09
    static let angryForward: Float = 0.2
    /// 脈打つ速さ（回/秒）と振れ幅（割合）・弾む高さ（m）。
    static let angryPulseRate: Double = 4
    static let angryPulseDepth: Float = 0.2
    static let angryHop: Float = 0.03
    /// 💢 の形（外側の半径を 1 とした比）: 太さ一定・端が丸い「く」の字。曲がり角が中心を向き、斜め 4 方向。中心の空白は直径の約 42%。
    static let angryStrokeWidth: Float = 0.2
    static let angryHoleRatio: Float = 0.42
    /// 「く」の腕が、外向きの軸から開く角（ラジアン）。
    static let angryArmSpread: Float = 0.66

    /// 💢 の 1 本（「く」の字）: 曲がり角と 2 つの腕の先（外側の半径 1 の単位・中心が原点）。
    struct AngryStroke: Equatable {
        var corner: SIMD2<Float>
        var tips: [SIMD2<Float>]
    }

    /// 4 本の「く」の字。曲がり角の内側の縁が中心から `angryHoleRatio` の位置、腕の先の外側の縁が外側の半径 1 にちょうど届く。
    static var angryStrokes: [AngryStroke] {
        let half = angryStrokeWidth / 2
        let rv = angryHoleRatio + half
        let c = cos(angryArmSpread)
        // |rv·u + L·d|² = (1 - half)² を L について解く（u と d の角が spread）。
        let reach = 1 - half
        let len = -rv * c + (rv * rv * c * c - rv * rv + reach * reach).squareRoot()
        return (0..<4).map { i in
            let a = Float(i) * .pi / 2 + .pi / 4
            let u = SIMD2<Float>(cos(a), sin(a))
            func arm(_ sign: Float) -> SIMD2<Float> {
                let t = a + sign * angryArmSpread
                return u * rv + SIMD2(cos(t), sin(t)) * len
            }
            return AngryStroke(corner: u * rv, tips: [arm(1), arm(-1)])
        }
    }

    /// 吹き出しの尾（吹き出しの半径を 1 とした比・頭の方 = +x）の先端。
    static let angryTailTip = SIMD2<Float>(1.55, -0.2)

    // MARK: 段階②（顔の赤み・湯気）

    /// 顔の赤い円・両頬（頭の骨の局所・m）: 円の中心と半径・頬の中心（左右）と半径・不透明度。
    static let flushCenter = SIMD3<Float>(0, 0.11, 0.232)
    static let flushRadius: Float = 0.15
    static let flushOpacity: Float = 0.5
    static let cheekOffset = SIMD3<Float>(0.1, 0.075, 0.22)
    static let cheekRadius: Float = 0.05
    static let cheekOpacity: Float = 0.8
    /// 湯気: 頭のてっぺんから見た 2 つの塊の位置（左右の横・上・m）・塊の大きさ（m）・「プンッ」と弾ける周期（秒）・立ち上る高さ（m）。
    static let steamSide: Float = 0.16
    static let steamLift: Float = 0.17
    static let steamSize: Float = 0.06
    static let steamPeriod: TimeInterval = 0.9
    static let steamRise: Float = 0.08

    /// 湯気の 1 周期（0〜1）の大きさの係数: 素早くふくらみ（約 2 割）、ゆっくりしぼんで消える。
    static func steamPuff(phase: Double) -> Float {
        let p = phase - phase.rounded(.down)
        return p < 0.2 ? Float(p / 0.2) : Float(max(1 - (p - 0.2) / 0.8, 0))
    }

    /// ヘルメット（頭のてっぺんから見て中心 (0, -0.175)・半径 0.29 の球。`HomerunOjisan3D` の頭の球 0.27 m を基準）と吹き出しの間の最小の隙間（m）。
    /// 脈打ち・弾みが最大でも重ならないことをテストで確かめる。
    static var angryMinClearance: Float {
        let dx = angrySide, dy = angryLift + 0.175
        return (dx * dx + dy * dy).squareRoot() - 0.29 - angryHop - angryBubbleRadius * (1 + angryPulseDepth)
    }

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
