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

    // MARK: - 跳ねる・転がる

    /// 跳ねる動きの区切り（持ち上がる高さ pt と、そこへ着くまでの秒）。だんだん低く跳ねて着地する。
    /// 合計の長さは `rollDuration` と同じにする（止まる前に跳ね終わる・止まったあとも跳ねている、を防ぐ）。
    static let bounceSegments: [(lift: CGFloat, duration: TimeInterval)] = [
        (-22, 0.16), (0, 0.16),
        (-9, 0.12), (0, 0.12),
        (-3, 0.10), (0, 0.14),
    ]

    /// 転がりきるまでの秒。最後の小さな跳ねの間は回さず、着地の手前で向きをそろえる。
    static let spinDuration: TimeInterval = 0.6

    /// 転がる向き。隣どうしで逆に回すと、転がっている感じが出る。
    static func spinDirection(index: Int) -> Double {
        index.isMultiple(of: 2) ? 1 : -1
    }

    /// 立体に転がる角度（度）の区切り（#2389）。手前へ転がる x 軸と横へ転がる y 軸を別の速さで回し、
    /// どちらもちょうど 1 周して正面に戻る（止まったときに読む目が前面に来る）。
    /// 最初は速く、着地へ向けて減速する（投げたサイコロは勢いよく転がり始めて止まる）。
    /// それぞれの長さの合計は `spinDuration`。
    static let tumbleSegmentsX: [(degrees: Double, duration: TimeInterval)] = [
        (230, 0.26), (360, 0.34),
    ]
    static let tumbleSegmentsY: [(degrees: Double, duration: TimeInterval)] = [
        (150, 0.20), (360, 0.40),
    ]

    /// 跳ねる・転がる演出のキーフレーム。View の `KeyframeAnimator` と、コマを取り出すテストで同じものを使う。
    @KeyframesBuilder<DiceComboTumble>
    static func tumbleKeyframes() -> some Keyframes<DiceComboTumble> {
        KeyframeTrack(\.lift) {
            for segment in bounceSegments {
                CubicKeyframe(segment.lift, duration: segment.duration)
            }
        }
        KeyframeTrack(\.rollX) {
            for segment in tumbleSegmentsX {
                CubicKeyframe(segment.degrees, duration: segment.duration)
            }
            CubicKeyframe(tumbleSegmentsX.last?.degrees ?? 0, duration: rollDuration - spinDuration)
        }
        KeyframeTrack(\.rollY) {
            for segment in tumbleSegmentsY {
                CubicKeyframe(segment.degrees, duration: segment.duration)
            }
            CubicKeyframe(tumbleSegmentsY.last?.degrees ?? 0, duration: rollDuration - spinDuration)
        }
    }

    /// `tumbleKeyframes()` の時刻 `time`（秒）のコマ。テストと静止画の書き出しに使う。
    static func tumble(at time: TimeInterval) -> DiceComboTumble {
        KeyframeTimeline(initialValue: DiceComboTumble()) { tumbleKeyframes() }.value(time: time)
    }

    // MARK: - 振る前の目

    /// まだ振っていないサイコロに見せる目（#2389）。「？」ではなく最初からサイコロの形で出し、薄く描いて
    /// 「まだ振っていない」ことを表す。**役の計算には使わない**（Model の `dice` は空のまま）。
    /// 並びは固定。1 列で見たときに役（連番・そろい）に見えない順にしてある。
    static let idleFaces = [5, 2, 6, 3, 1]

    static func idleFace(index: Int) -> Int {
        idleFaces[((index % idleFaces.count) + idleFaces.count) % idleFaces.count]
    }
}

/// 跳ねる・転がる演出の 1 コマ。`KeyframeAnimator` の値として使う。
struct DiceComboTumble {
    /// 持ち上がる高さ（pt・上が負）。
    var lift: CGFloat = 0
    /// 立体の転がり（度）。x は手前へ、y は横へ。
    var rollX: Double = 0
    var rollY: Double = 0

    /// `direction`（±1）の向きに手前へ転がす立方体の向き。
    func rotation(direction: Double) -> DiceComboCube.Rotation {
        DiceComboCube.Rotation(x: rollX * direction, y: rollY)
    }
}
