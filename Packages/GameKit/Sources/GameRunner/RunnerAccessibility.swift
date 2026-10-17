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
        tr("ステージ %1$lld / %2$lld", number, total)
    }

    /// ステージ表示の読み上げ。番号に世界の名前（#703）を添える——画面では背景の色で
    /// 分かる「どこを走っているか」を、見えない人にも番号だけでなく言葉で伝える。
    public static func stageLabelWithWorld(number: Int, total: Int) -> String {
        tr("%1$@、%2$@", stageLabel(number: number, total: total), RunnerWorld.world(forStage: number).displayName)
    }

    /// ワールドマップ（#798）の面のボタン。「1-1、到達済み」の形で、表記と選べるかどうかを
    /// 1 文で言う（鍵の絵だけでは読み上げに出ない）。面の名前は #946 で外した。
    public static func stageMapLabel(number: Int, reached: Bool) -> String {
        tr("%1$@、%2$@", stageHeadline(number: number), reached ? tr("到達済み") : tr("未到達"))
    }

    /// 面の見出し「2-3」（#931。名前は #946 で外し番号だけ）。走行中の HUD・スタート画面の
    /// 主ボタン・クリア表示の「つぎは」・ワールドマップで同じ形を使う。どの世界にも収まらない番号
    /// （範囲外）は「ステージ N」に倒す。
    public static func stageHeadline(number: Int) -> String {
        guard RunnerWorld.contains(stage: number) else { return tr("ステージ %lld", number) }
        return RunnerWorld.code(forStage: number)
    }

    /// スタート画面（#931）の主ボタン。「2-3 から走る」。
    public static func startStageLabel(number: Int) -> String {
        tr("%@ から走る", stageHeadline(number: number))
    }

    /// スタート画面（#931）のエンドレスのボタン。自己ベストを添えて
    /// 「エンドレス、自己ベスト 1,234 メートル」。まだ走っていなければ「まだ記録なし」。
    public static func startEndlessLabel(bestDistance: Int?) -> String {
        guard let bestDistance else { return tr("エンドレス、まだ記録なし") }
        return tr("エンドレス、自己ベスト %@ メートル", RecordFormat.number(max(0, bestDistance)))
    }

    /// 進み具合。パーセントは 5 刻みに丸める（1% ごとに読み上げが変わると耳で追えない）。
    public static func progressLabel(_ progress: Double) -> String {
        let clamped = min(1, max(0, progress))
        let percent = Int((clamped * 20).rounded()) * 5
        return tr("ゴールまで %lldパーセント", 100 - percent)
    }

    /// ペダルの乗り（#569）。0 が基準の速さ、100 が上限。
    ///
    /// 進み具合と同じく粗く丸める（走行中に 1% ごとに読み替えられても追えない）。
    /// 倍率（1.45 倍）ではなくゲージの割合で言うのは、画面のゲージと同じものを指すため。
    public static func speedLabel(ratio: Double) -> String {
        let clamped = min(1, max(0, ratio))
        let percent = Int((clamped * 10).rounded()) * 10
        return tr("スピード %lldパーセント", percent)
    }

    /// たこ焼き（#797）の無敵の残り時間。秒は切り上げる（残り 0.3 秒を「0秒」と読まない）。
    public static func invincibleLabel(remaining: Double) -> String {
        tr("無敵 あと%lld秒", Int(max(0, remaining).rounded(.up)))
    }

    /// 走行距離（エンドレス・#675）。単位はワールド単位だが、画面と同じ「m」で読む。
    public static func distanceLabel(_ distance: Int) -> String {
        tr("走行距離 %lldメートル", max(0, distance))
    }

    /// エンドレスの自己ベスト。まだ 1 回も走っていなければ記録が無いことを言う。
    public static func bestDistanceLabel(_ distance: Int?) -> String {
        guard let distance else { return tr("自己ベストはまだありません") }
        return tr("自己ベスト %lldメートル", max(0, distance))
    }

    /// エンドレスの結果。ステージ番号の代わりに走行距離を言う。
    ///
    /// エンドレスにゴールは無い（#1086）ので `.cleared` / `.allCleared` にはならない。switch を
    /// 網羅するために、万一来ても走行距離だけを言う（「走りきった」とは言わない）。
    public static func endlessResultLabel(phase: RunnerPhase, distance: Int) -> String {
        switch phase {
        case .falling, .failed: return tr("%lldメートルでミスしました", max(0, distance))
        // 締め（`.story`・#1092）もステージ制だけの局面なので、同じくここには来ない。
        case .chasing, .story, .cleared, .allCleared: return distanceLabel(distance)
        case .paused:     return tr("一時停止中")
        case .ready:      return tr("エンドレス。タップでスタート")
        case .running:    return tr("走行中")
        }
    }

    /// コースを二本指ダブルタップしたとき何が起きるか。
    ///
    /// ゴールの演出中（`.chasing`・#1092）だけは**ジャンプではなく演出を飛ばす**操作になるので、
    /// ヒントの文言も入れ替える（`RunnerModel.press` の分岐と 1:1）。
    /// 世界の締め（`.story`・#1092）も同じくジャンプにはならない。あちらはオーバーレイ側が
    /// 「スキップ」ボタンを持つので、コースのヒントは何も起きないことだけを言う。
    public static func courseHint(phase: RunnerPhase) -> String {
        switch phase {
        case .chasing: return tr("ダブルタップで演出をスキップ")
        case .story:   return tr("おはなしを表示中です")
        default:       return tr("ダブルタップでジャンプ")
        }
    }

    /// ミス・クリアの結果。
    public static func resultLabel(phase: RunnerPhase, stageNumber: Int) -> String {
        switch phase {
        case .falling:    return tr("ステージ %lld でミスしました", stageNumber)
        case .failed:     return tr("ステージ %lld でミスしました", stageNumber)
        // ゴールの演出中（#1092）も、記録はもう確定しているのでクリアと言い切る
        // ——読み上げが「走行中」のまま 1.5 秒待たされるのを避ける。
        case .chasing:    return tr("ステージ %lld クリア", stageNumber)
        // 世界の締め（#1092）はオーバーレイ自身が場面と台詞を読み上げるので、
        // 背後のコースはクリアの事実だけを言う。
        case .story:      return tr("ステージ %lld クリア", stageNumber)
        case .cleared:    return tr("ステージ %lld クリア", stageNumber)
        case .allCleared: return tr("全ステージクリア")
        case .paused:     return tr("一時停止中")
        case .ready:      return tr("タップでスタート")
        case .running:    return tr("走行中")
        }
    }
}
