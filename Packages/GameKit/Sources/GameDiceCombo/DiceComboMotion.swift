import SwiftUI

/// サイコロが転がる演出の長さと形（#2365）。**状態を持たない定数と純関数だけ**を置き、View から切り出す。
///
/// ルーレット（`RouletteMotion`）と同じ方針で、長さは秒の定数として持ち、Model へは `Duration` で渡す。
/// 出目は振った瞬間に Model が確定させていて、ここが決めるのは「止まるまでに何を見せるか」だけ。
enum DiceComboMotion {

    // MARK: - 長さ

    /// 振ってから止まるまで（秒）。連続で振ってもテンポを損なわない 0.6〜1 秒の中に収める。
    static let rollDuration: TimeInterval = 0.8

    /// `rollDuration` を Model に渡す形。
    static var rollInterval: Duration {
        .milliseconds(Int((rollDuration * 1000).rounded()))
    }

    /// 転がっている間に目を切り替える間隔（秒）。
    static let flickerStep: TimeInterval = 0.07

    // MARK: - 目の切り替え

    /// 転がっている途中に見せる目（1〜6）。`tick` が 1 進むごとに必ず違う目になる。
    /// 乱数は使わない（出目の乱数列を消費しない・テストで決め打ちに確かめられる）。
    static func flickerFace(final: Int, index: Int, tick: Int) -> Int {
        // 7 は 6 で割って 1 余るので、隣り合う tick の目は必ず 1 ずれる。
        let raw = tick &* 7 &+ index &* 3 &+ final
        return ((raw % 6) + 6) % 6 + 1
    }

    /// サイコロ 1 個に今描く目。転がっていてキープしていないものだけ途中の目、それ以外は確定した目。
    static func displayedFace(final: Int?, isRolling: Bool, isHeld: Bool, index: Int, tick: Int) -> Int? {
        guard let final, isRolling, !isHeld else { return final }
        return flickerFace(final: final, index: index, tick: tick)
    }

    /// 時刻から目を切り替える番号を出す。
    static func tick(at date: Date) -> Int {
        Int((date.timeIntervalSinceReferenceDate / flickerStep).rounded(.down))
    }

    // MARK: - 跳ねる・回る

    /// 跳ねる動きの区切り（持ち上がる高さ pt と、そこへ着くまでの秒）。だんだん低く跳ねて着地する。
    /// 合計の長さは `rollDuration` と同じにする（止まる前に跳ね終わる・止まったあとも跳ねている、を防ぐ）。
    static let bounceSegments: [(lift: CGFloat, duration: TimeInterval)] = [
        (-22, 0.16), (0, 0.16),
        (-9, 0.12), (0, 0.12),
        (-3, 0.10), (0, 0.14),
    ]

    /// 回りきるまでの秒。最後の小さな跳ねの間は回さず、着地の手前で向きをそろえる。
    static let spinDuration: TimeInterval = 0.6

    /// 回る向き。隣どうしで逆に回すと、転がっている感じが出る。
    static func spinDirection(index: Int) -> Double {
        index.isMultiple(of: 2) ? 1 : -1
    }

    /// 転がるあいだに回る角度（度）。1 周して元の向きに戻る（止まったあとの傾きは View が別に付ける）。
    static let spinDegrees: Double = 360
}

/// 跳ねる・回る演出の 1 コマ。`keyframeAnimator` の値として使う。
struct DiceComboTumble {
    var lift: CGFloat = 0
    var spin: Double = 0
}
