import Foundation

/// しりとりの「語尾で受ける・語頭で始める」かな判定（#1243）。純関数だけを持つ。
///
/// 読みはひらがなで持つが、カタカナで書かれても同じに扱えるよう先にひらがなへ揃える。
enum ShiritoriKana {
    private static let longMark: Character = "ー"

    /// 小さい字は大きい字に直して受ける（「エミュー」→「ゆ」）。
    private static let smallToLarge: [Character: Character] = [
        "ゃ": "や", "ゅ": "ゆ", "ょ": "よ", "ぁ": "あ", "ぃ": "い", "ぅ": "う", "ぇ": "え", "ぉ": "お",
        "ゎ": "わ", "っ": "つ",
    ]

    /// カタカナをひらがなに揃える（長音符「ー」はそのまま）。
    static func hiragana(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            (0x30A1...0x30F6).contains(scalar.value) ? Unicode.Scalar(scalar.value - 0x60) ?? scalar : scalar
        }))
    }

    /// 語頭（最初の 1 字）。空文字なら nil。
    static func head(of reading: String) -> Character? {
        hiragana(reading).first
    }

    /// 語尾（次の人が受ける字）。**長音符は 1 つ前の字で受ける**（本家と同じ）。
    /// 小さい字は大きい字に直す。空文字（長音符だけを含む）なら nil。
    static func tail(of reading: String) -> Character? {
        var chars = Array(hiragana(reading))
        while chars.last == longMark { chars.removeLast() }
        guard let last = chars.last else { return nil }
        return smallToLarge[last] ?? last
    }

    /// 語尾 `tail` の次に、語頭 `head` の読みを出してよいか。
    ///
    /// 濁音・半濁音の語尾は**そのままの字でも、濁点を取った字でも**受けてよい
    /// （「うさぎ」→「ぎたー」と「うさぎ」→「きつね」のどちらも成立）。
    static func accepts(head: Character, after tail: Character) -> Bool {
        head == tail || head == unvoiced(tail)
    }

    /// 濁点・半濁点を取った字（濁音でなければそのまま）。
    static func unvoiced(_ char: Character) -> Character {
        guard let first = String(char).decomposedStringWithCanonicalMapping.unicodeScalars.first else { return char }
        return Character(first)
    }

    /// 「ん」か（語尾がこれの札を選んだ側は即負け）。
    static func isN(_ char: Character) -> Bool { char == "ん" }
}
