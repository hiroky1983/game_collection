/// ゲーム1回の決着の種類。各ゲームの Model が決着を判定した場所から `GameServices.gameDidFinish`
/// へ渡す。評価リクエスト（#53）は `win` のときだけ反応する。
public enum GameOutcome: String, Equatable, Sendable {
    /// 勝利・クリア。
    case win
    /// 敗北・投了・ゲームオーバー・地雷を踏んだ。
    case loss
    /// 引き分け・プッシュ。
    case draw
}
