/// テンキーの 1 つ。
public enum AnzanKey: Hashable, Sendable {
    case digit(Int)
    case backspace
    case submit
}

/// VoiceOver の読み上げ文。数は画面に一瞬しか出ないので、出ている数・入力中の値・正誤を文字で伝える。
public enum AnzanAccessibility {
    /// テンキーの読み上げ。
    public static func keyLabel(_ key: AnzanKey) -> String {
        switch key {
        case let .digit(digit): return String(digit)
        case .backspace:        return "1文字消す"
        case .submit:           return "決定"
        }
    }

    /// 出題の板の読み上げ。
    ///
    /// - Parameters:
    ///   - step: 見せているコマ（`flashing` のときだけ意味を持つ）。
    ///   - displayedNumber: 見せている数。
    ///   - input: 入力中の答え。
    ///   - sum: 正解。
    ///   - answer: 決定した答え。
    public static func stageLabel(
        phase: AnzanModel.Phase,
        step: AnzanDisplayStep?,
        displayedNumber: Int?,
        input: String,
        sum: Int,
        answer: Int?,
        isCorrect: Bool
    ) -> String {
        switch phase {
        case .idle:
            return "難易度を選んで始めましょう"
        case .flashing:
            if step == .ready { return "よーい" }
            if let displayedNumber { return String(displayedNumber) }
            return "次の数を待っています"
        case .answering:
            return input.isEmpty ? "ぜんぶ足した答えを入力してください" : "いまの入力は\(input)"
        case .result:
            if isCorrect { return "せいかい。合計は\(sum)" }
            if let answer { return "ざんねん。正解は\(sum)、あなたの答えは\(answer)" }
            return "ざんねん。正解は\(sum)"
        }
    }
}
