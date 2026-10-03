import Foundation

/// アンケート（挑戦 +1 回・1 日 1 回・3 問・選ぶだけ。README §3.4）。
///
/// 数字に出ない声を集めるための設問で、**回答は選択肢の番号（1 始まり）だけ**を解析イベント `survey_answer`
/// で送る。自由記述は持たず、端末には回答を残さない（台帳に残るのは「今日は済み」のフラグだけ）。
/// 選択肢の並びを変えると GA4 上の番号の意味が変わるので、変えるときは末尾に足すか設問ごと作り直す。
public enum HomerunSurvey {
    /// アンケートの入口（打席前・結果の「アンケートに答えて挑戦 +1 回」）を画面に出すか。
    /// **v1.1.9 では出さない**（会長決裁 2026-10-03・#1784。フォームの本格対応は #1693・v1.1.10 以降）。
    /// 戻すときは `true` にするだけ。台帳の `surveyDone`・`credit` の `.survey`・`submitSurvey` は互換のため残してあり、
    /// 入口が出ない間は `surveyDone` が立たないので回数の計算は変わらない。
    public static let isOffered = false

    public struct Question: Equatable, Sendable {
        public let prompt: String
        public let choices: [String]
    }

    public static let questions: [Question] = [
        Question(prompt: "このゲームをまた遊びたいですか？",
                 choices: ["ぜひ遊びたい", "ときどき遊びたい", "あまり遊びたくない"]),
        Question(prompt: "いちばん足りないと思うところは？",
                 choices: ["操作のしやすさ", "絵・演出", "遊びの種類・やり込み", "特にない"]),
        Question(prompt: "これが別のアプリなら入れたいですか？",
                 choices: ["入れたい", "無料なら入れる", "入れない"]),
    ]

    /// 全問に 1 つずつ、範囲内の番号（1 始まり）で答えているか。
    public static func isValid(_ answers: [Int]) -> Bool {
        guard answers.count == questions.count else { return false }
        return zip(answers, questions).allSatisfy { (1...$1.choices.count).contains($0) }
    }
}
