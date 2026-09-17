import Core
import Foundation

/// 画面の状態を読み上げる文（#494）。
///
/// アクション枠は**盤面を読み上げても遊べるようにはならない**（基盤規約 §3）。代わりに
/// 進行に関わる情報（ステージ・進み具合・スピード）を SwiftUI 側のヘッダーへ置き、
/// ここで作った文を `accessibilityLabel` に付ける。SpriteKit の中に文字は描かない。
///
/// 純関数なので、View を組まずに `AccessibilityTests` で文面を固定できる。
public enum RunnerAccessibility {
    /// ヘッダーのステージ表示。
    public static func stageLabel(number: Int, total: Int) -> String {
        "ステージ \(number) / \(total)"
    }

    /// ステージ表示の読み上げ。番号に世界の名前（#703）を添える——画面では背景の色で
    /// 分かる「どこを走っているか」を、見えない人にも番号だけでなく言葉で伝える。
    public static func stageLabelWithWorld(number: Int, total: Int) -> String {
        "\(stageLabel(number: number, total: total))、\(RunnerWorld.world(forStage: number).displayName)"
    }

    /// ワールドマップ（#798）の面のボタン。「1-1、到達済み」の形で、表記と選べるかどうかを
    /// 1 文で言う（鍵の絵だけでは読み上げに出ない）。面の名前は #946 で外した。
    public static func stageMapLabel(number: Int, reached: Bool) -> String {
        "\(stageHeadline(number: number))、\(reached ? "到達済み" : "未到達")"
    }

    /// 面の見出し「2-3」（#931。名前は #946 で外し番号だけ）。走行中の HUD・スタート画面の
    /// 主ボタン・クリア表示の「つぎは」・ワールドマップで同じ形を使う。3 世界に収まらない番号
    /// （範囲外）は「ステージ N」に倒す。
    public static func stageHeadline(number: Int) -> String {
        guard RunnerWorld.contains(stage: number) else { return "ステージ \(number)" }
        return RunnerWorld.code(forStage: number)
    }

    /// スタート画面（#931）の主ボタン。「2-3 から走る」。
    public static func startStageLabel(number: Int) -> String {
        "\(stageHeadline(number: number)) から走る"
    }

    /// スタート画面（#931）のエンドレスのボタン。自己ベストを添えて
    /// 「エンドレス、自己ベスト 1,234 メートル」。まだ走っていなければ「まだ記録なし」。
    public static func startEndlessLabel(bestDistance: Int?) -> String {
        guard let bestDistance else { return "エンドレス、まだ記録なし" }
        return "エンドレス、自己ベスト \(RecordFormat.number(max(0, bestDistance))) メートル"
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

    /// たこ焼き（#797）の無敵の残り時間。秒は切り上げる（残り 0.3 秒を「0秒」と読まない）。
    public static func invincibleLabel(remaining: Double) -> String {
        "無敵 あと\(Int(max(0, remaining).rounded(.up)))秒"
    }

    /// 走行距離（エンドレス・#675）。単位はワールド単位だが、画面と同じ「m」で読む。
    public static func distanceLabel(_ distance: Int) -> String {
        "走行距離 \(max(0, distance))メートル"
    }

    /// エンドレスの自己ベスト。まだ 1 回も走っていなければ記録が無いことを言う。
    public static func bestDistanceLabel(_ distance: Int?) -> String {
        guard let distance else { return "自己ベストはまだありません" }
        return "自己ベスト \(max(0, distance))メートル"
    }

    /// エンドレスの結果。ステージ番号の代わりに走行距離を言う。
    ///
    /// エンドレスにゴールは無い（#1086）ので `.cleared` / `.allCleared` にはならない。switch を
    /// 網羅するために、万一来ても走行距離だけを言う（「走りきった」とは言わない）。
    public static func endlessResultLabel(phase: RunnerPhase, distance: Int) -> String {
        switch phase {
        case .falling, .failed: return "\(max(0, distance))メートルでミスしました"
        case .cleared, .allCleared: return distanceLabel(distance)
        case .paused:     return "一時停止中"
        case .ready:      return "エンドレス。タップでスタート"
        case .running:    return "走行中"
        }
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
