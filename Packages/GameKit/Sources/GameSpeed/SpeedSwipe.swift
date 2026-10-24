import CoreGraphics
import Foundation

/// 手札を払って台札に出す操作の判定（会長 QA 2026-10-23「スワイプ前提にしてみたほうがいいかも」・#1323）。
///
/// View の `DragGesture` が指を離した瞬間の値（動いた量・速さ）と、同じ座標空間で測った札・台札の枠を渡し、
/// ここが「どの台札に出すか / 外れか / タップか / 取り消しか」を決める。時刻は使わない
/// （柵越えおじさんで `DragGesture` の時刻の扱いがテストとずれた事故の再発防止。速さは OS が出す `velocity` を読むだけ）。
///
/// 判定の順:
/// 1. ほとんど動いていない → タップ（通常の操作では札を出さない。支援機能を使っているときだけ今までのタップの操作に渡す）。
/// 2. 札の中心が台札の枠の中で離した → その台札（速さは問わない）。
/// 3. 離した瞬間の速さが `flickSpeed` 以上で、向きが真下寄りでない → 向きで台札を決める。
///    - 真上から `straightUpTolerance` 以内: 出せる台札が 1 つならそこ、2 つなら角度の近いほう。
///    - それ以外: 動かす前の札から見て角度の近い台札（出せなければ外れ）。
///    台札の枠の外側の余裕（`dropMargin`）より先に向きを見る。速く払った指が隣の台札の縁をかすめても、
///    払った向きのほうを採る（シミュレータで右上へ払った札が左の台札の余裕に入って外れになった実測による）。
/// 4. 遅い動きで、台札の枠を `dropMargin` だけ広げた枠の中で離した → その台札。
/// 5. 遅くても `commitDistance` 以上はっきり上・横へ動かしていた → 動かした向きで 3 と同じに決める
///    （払い終わりに指が止まりかけると速さが落ちる。XCUITest の短い払いで速さ 50pt/秒前後まで落ちた実測による）。
/// 6. それ以外（ゆっくり動かして台札の外で離した・下へ払った）→ 取り消し（元の位置へ戻すだけで警告は鳴らさない）。
enum SpeedSwipe {
    /// これ未満の移動で、速さも `flickSpeed` 未満ならタップとみなす（pt）。
    static let tapSlop: CGFloat = 10
    /// フリックとみなす、離した瞬間の速さの下限（pt/秒）。
    static let flickSpeed: CGFloat = 300
    /// 台札の上で離したとみなす、台札の枠の外側の余裕（pt）。
    static let dropMargin: CGFloat = 20
    /// 速さが足りなくても、動かした向きで台札を決める移動量（pt）。
    static let commitDistance: CGFloat = 36
    /// 「上へまっすぐ」とみなす、真上からの角度（度）。
    static let straightUpTolerance: Double = 15
    /// フリックとして受ける、真上からの角度の上限（度）。真横（90 度）は受け、下向きは受けない。
    static let maxFlickAngle: Double = 100

    enum Outcome: Equatable {
        /// タップ（通常の操作では出さずに持ち上げて戻す。支援機能では今までのタップ操作に渡す）。
        case tap
        /// その台札に出す。
        case play(Int)
        /// その台札を狙ったが出せない（跳ね返して警告）。
        case miss(Int)
        /// 何もしない（元の位置へ戻す）。
        case cancel
    }

    /// - Parameters:
    ///   - cardCenter: 動かす前の札の中心。
    ///   - translation: 指が動いた量（`DragGesture.Value.translation`）。
    ///   - velocity: 離した瞬間の速さ（`DragGesture.Value.velocity`。pt/秒）。
    ///   - pileFrames: 台札の枠（台札の番号 → 枠）。`cardCenter` と同じ座標空間。
    ///   - playable: この札を出せる台札の番号。
    static func resolve(
        cardCenter: CGPoint,
        translation: CGSize,
        velocity: CGSize,
        pileFrames: [Int: CGRect],
        playable: Set<Int>
    ) -> Outcome {
        let distance = hypot(translation.width, translation.height)
        let speed = hypot(velocity.width, velocity.height)
        if distance < tapSlop && speed < flickSpeed { return .tap }

        let release = CGPoint(x: cardCenter.x + translation.width, y: cardCenter.y + translation.height)
        // 台札の枠の中で離したら、その台札（2 山の枠は重ならないが、念のため番号の小さいほうから見る）。
        if let dropped = pile(containing: release, in: pileFrames, margin: 0) {
            return playable.contains(dropped) ? .play(dropped) : .miss(dropped)
        }

        guard !pileFrames.isEmpty else { return .cancel }
        let direction: CGSize
        if speed >= flickSpeed {
            direction = velocity
        } else {
            // 遅い動き: 台札の縁の少し外で離しても置く。
            if let dropped = pile(containing: release, in: pileFrames, margin: dropMargin) {
                return playable.contains(dropped) ? .play(dropped) : .miss(dropped)
            }
            guard distance >= commitDistance else { return .cancel }
            direction = translation
        }
        let flickAngle = angleFromUp(direction)
        guard abs(flickAngle) <= maxFlickAngle else { return .cancel }

        // 動かす前の札から見た各台札の向きと、払った向きの差（0〜180 度）。台札は必ず手札より上にあるので、
        // 離した位置（台札を越えることがある）ではなく動かす前の位置から測る。
        let diffs: [(pile: Int, diff: Double)] = pileFrames.keys.sorted().compactMap { index in
            guard let frame = pileFrames[index] else { return nil }
            let toPile = CGSize(width: frame.midX - cardCenter.x, height: frame.midY - cardCenter.y)
            let raw = abs(angleFromUp(toPile) - flickAngle).truncatingRemainder(dividingBy: 360)
            return (index, min(raw, 360 - raw))
        }
        if abs(flickAngle) <= straightUpTolerance, playable.count == 1, let only = playable.first {
            return .play(only)
        }
        let candidates = abs(flickAngle) <= straightUpTolerance && !playable.isEmpty
            ? diffs.filter { playable.contains($0.pile) }
            : diffs
        guard let nearest = candidates.min(by: { $0.diff < $1.diff })?.pile else { return .cancel }
        return playable.contains(nearest) ? .play(nearest) : .miss(nearest)
    }

    private static func pile(containing point: CGPoint, in frames: [Int: CGRect], margin: CGFloat) -> Int? {
        frames.keys.sorted().first { frames[$0]?.insetBy(dx: -margin, dy: -margin).contains(point) == true }
    }

    /// 真上（画面の上向き）からの角度（度）。右回りが正、左回りが負。真下は ±180。
    static func angleFromUp(_ vector: CGSize) -> Double {
        // 画面の座標は y が下向きなので、上向きは -y。
        atan2(Double(vector.width), Double(-vector.height)) * 180 / .pi
    }
}
