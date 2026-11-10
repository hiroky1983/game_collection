import SwiftUI
import Testing
@testable import Core

/// 開始シートの段選択部品（#3363）。選択肢の数・文字の長さで高さが変わらないこと。
@Suite("SetupStepSelector（#3363）")
@MainActor
struct SetupStepSelectorTests {

    private func height(count: Int, title: String = "段") -> CGFloat {
        let options = (0..<count).map {
            SetupStepOption(value: $0, title: "\(title)\($0)", detail: "説明", accent: Theme.Fill.teal)
        }
        let view = SetupStepSelector(options: options, selection: .constant(0))
            .frame(width: 343)
            .fixedSize(horizontal: false, vertical: true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.cgImage?.height.cgFloat ?? 0
    }

    @Test("2・4・5・30 段で高さが同じ")
    func heightIsIndependentOfCount() {
        let base = height(count: 2)
        #expect(base > 0)
        for count in [4, 5, 30] {
            #expect(height(count: count) == base, "\(count) 段で高さが変わった")
        }
    }

    @Test("長い値の名前でも高さが変わらない")
    func heightIsIndependentOfTitleLength() {
        #expect(height(count: 5, title: "とてもとてもとても長い名前の段") == height(count: 5))
    }
}

private extension Int { var cgFloat: CGFloat { CGFloat(self) } }
