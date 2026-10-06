import Testing
import Core

/// 1 ハンドの決着表示（#1754）の文言。ポーカーとブラックジャックが同じ部品に乗るので Core 単体で固定する。
struct HandResultTests {

    private func result(delta: Int?) -> HandResult {
        HandResult(kind: .win, headline: "勝ち！", reason: "ツーペア 対 ワンペア",
                   chipDelta: delta, spokenResult: "勝ちです")
    }

    @Test("増減は符号つきで、桁区切りを入れない")
    func chipText() {
        #expect(result(delta: 40).chipText == "+40枚")
        #expect(result(delta: -20).chipText == "−20枚")
        #expect(result(delta: 0).chipText == "±0枚")
        #expect(result(delta: 1500).chipText == "+1500枚")
        #expect(result(delta: nil).chipText == nil, "増減が取れないときは行ごと出さない")
    }

    @Test("読み上げは勝敗・理由・増減の順")
    func spokenText() {
        #expect(result(delta: 40).spokenText == "勝ちです。ツーペア 対 ワンペア。チップが40枚増えました")
        #expect(result(delta: -20).spokenText == "勝ちです。ツーペア 対 ワンペア。チップが20枚減りました")
        #expect(result(delta: 0).spokenText.hasSuffix("チップの増減はありません"))
        #expect(result(delta: nil).spokenText == "勝ちです。ツーペア 対 ワンペア")
    }
}
