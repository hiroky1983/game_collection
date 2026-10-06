import Foundation

/// 打ち上げた球が自分の頭に落ちてたんこぶ（#1793・会長決裁 2026-10-03）。ポップフライになる当たりのうち、球の結構下を擦って
/// 当てたときに低い頻度で出すギャグ演出の、発生条件。飛距離は 0・方向は 0。見た目は `GameHomerun`（`HomerunTankobuGag`）。
///
/// 確率・帯の下限・1 挑戦の上限は初期値で、会長 QA で調整する前提のため、このファイルの定数に集めてある。
public enum HomerunTankobu {
    /// 条件を満たした当たり 1 回あたりの発生確率（初期値 1/5）。
    public static let chance: Double = 1.0 / 5
    /// 1 挑戦に出せる回数（初期値 1）。
    public static let perChallenge = 1
    /// 「球の結構下を擦った」帯の下限（ボールの中心からカーソルまでの縦のずれ・pt・下が正）。ポップの帯
    /// （`HomerunLaunch.popFloor` 〜）のうち、帯の芯の基準点（`HomerunLaunch.pop.centerDY`）より下を叩いた当たり。
    public static var scrapeFloor: Double { HomerunLaunch.pop.centerDY }

    /// この振りが「球の結構下を擦った」帯か（当たるかどうかは見ない）。
    public static func isScrape(_ swing: HomerunSwing) -> Bool {
        swing.cursorDY >= scrapeFloor
    }

    /// 判定済みの打球 `ball` を、たんこぶの演出にしてよいか: 擦った帯で、フェアに落ちる当たり（ファウル・空振りは除く）。
    public static func qualifies(swing: HomerunSwing, ball: HomerunBattedBall) -> Bool {
        isScrape(swing) && ball.launch == .pop && ball.kind == .inPlay
    }

    /// 打球をたんこぶの演出に置き換える: 飛距離 0・方向 0（真上に上がって落ちてくる）。種別・タイミングは元のまま。
    static func apply(to ball: HomerunBattedBall) -> HomerunBattedBall {
        var b = ball
        b.direction = 0
        b.distance = 0
        b.isJustMeet = false
        b.isTankobu = true
        return b
    }
}
