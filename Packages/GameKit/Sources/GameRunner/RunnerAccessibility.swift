import Foundation

/// 画面の状態を読み上げる文（#494）。
///
/// アクション枠は**盤面を読み上げても遊べるようにはならない**（基盤規約 §3）。代わりに
/// 進行に関わる情報（ステージ・進み具合・タイム）を SwiftUI 側のヘッダーへ置き、
/// ここで作った文を `accessibilityLabel` に付ける。SpriteKit の中に文字は描かない。
///
/// 純関数なので、View を組まずに `AccessibilityTests` で文面を固定できる。
public enum RunnerAccessibility {
    /// ヘッダーのステージ表示。
    public static func stageLabel(number: Int, total: Int) -> String {
        "ステージ \(number) / \(total)"
    }

    /// 進み具合。パーセントは 5 刻みに丸める（1% ごとに読み上げが変わると耳で追えない）。
    public static func progressLabel(_ progress: Double) -> String {
        let clamped = min(1, max(0, progress))
        let percent = Int((clamped * 20).rounded()) * 5
        return "ゴールまで \(100 - percent)パーセント"
    }

    /// ペダルの乗り（#569）。0 が基準の速さ、100 が上限。
    ///
    /// 進み具合と同じく粗く丸める（走行中に 1% ごとに読み替えられても追えない）。
    /// 倍率（1.45 倍）ではなくゲージの割合で言うのは、画面のゲージと同じものを指すため。
    public static func speedLabel(ratio: Double) -> String {
        let clamped = min(1, max(0, ratio))
        let percent = Int((clamped * 10).rounded()) * 10
        return "スピード \(percent)パーセント"
    }

    /// タイム。分と秒に分けて読む（`1:05` は「いちころごー」と読まれてしまう）。
    public static func timeLabel(seconds: Int) -> String {
        let value = max(0, seconds)
        let minutes = value / 60
        let rest = value % 60
        return minutes > 0 ? "\(minutes)分\(rest)秒" : "\(rest)秒"
    }

    /// ベストタイム。未クリアのステージは記録が無いことを言う。
    public static func bestLabel(seconds: Int?) -> String {
        guard let seconds else { return "ベストタイムはまだありません" }
        return "ベストタイム \(timeLabel(seconds: seconds))"
    }

    /// ミス・クリアの結果。
    public static func resultLabel(phase: RunnerPhase, stageNumber: Int) -> String {
        switch phase {
        case .falling:    return "ステージ \(stageNumber) でミスしました"
        case .failed:     return "ステージ \(stageNumber) でミスしました"
        case .cleared:    return "ステージ \(stageNumber) クリア"
        case .allCleared: return "全ステージクリア"
        case .paused:     return "一時停止中"
        case .ready:      return "タップでスタート"
        case .running:    return "走行中"
        }
    }
}
