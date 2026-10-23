import SwiftUI

/// 操作の結果（正解・誤答・得点・動かない方向）を VoiceOver に 1 回だけ伝える（#2687）。
///
/// 結果は触覚とアニメだけで伝わることが多く、VoiceOver ではフォーカスが操作したボタンに残るため
/// 気づけない。モデルは操作のたびに `seq` を 1 つ進めた結果値を持ち、View は値が変わったときだけ読み上げる。
/// 連番を持つので、同じ文言（「その方向には動かせません」の連続など）でも毎回読まれる。
public struct OperationResult: Equatable, Sendable {
    public let seq: Int
    public let text: String

    public init(seq: Int, text: String) {
        self.seq = seq
        self.text = text
    }

    /// 次の結果値を作る。`previous` が無ければ 1 から。
    public static func next(after previous: OperationResult?, text: String) -> OperationResult {
        OperationResult(seq: (previous?.seq ?? 0) + 1, text: text)
    }
}

private struct OperationResultAnnouncementModifier: ViewModifier {
    let result: OperationResult?

    func body(content: Content) -> some View {
        content.onChange(of: result) { _, new in
            if let new {
                AccessibilityNotification.Announcement(new.text).post()
            }
        }
    }
}

public extension View {
    /// 操作の結果値が変わったとき、その文言を VoiceOver へ 1 回読み上げる。
    func operationResultAnnouncement(_ result: OperationResult?) -> some View {
        modifier(OperationResultAnnouncementModifier(result: result))
    }
}
