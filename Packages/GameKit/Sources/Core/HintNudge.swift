import SwiftUI

/// ヒントを促す表示（吹き出し）の出し方の決まり（#1424）。
///
/// 30 秒以上操作が無いときに、「⋯」メニューのヒントを指す控えめな表示を出す。**表示するだけ**で、
/// ヒントの使用も広告の再生もしない（ナンプレ・麻雀ソリティアのヒントは広告制なので、勝手に押さない）。
public enum HintNudgePolicy {
    /// 操作が無いまま待つ長さ。
    public static let idleDelay: Duration = .seconds(30)
    /// 1 局に出す回数の上限。出しすぎると邪魔になるため。
    public static let maxPerGame = 2

    /// まだ出してよいか。
    public static func canShow(shownCount: Int) -> Bool { shownCount < maxPerGame }
}

/// 操作行に渡す「ヒントを促してよい状態か」と「操作があったか」の 2 つ。
///
/// - `isEligible`: 自分の手番・対局中・ヒントが使える、を全部満たすとき true。
///   CPU の手番・結果表示中・広告の視聴中・ヒントが尽きたときは false にする。
/// - `activity`: **操作のたびに値が変わる**印（手数・選択・盤面など）。変わると待ち時間を数え直し、出ている吹き出しを消す。
public struct HintNudge {
    let isEligible: Bool
    let game: Int
    let activity: AnyHashable

    /// - Parameter game: 局を数える番号（`gameSerial` 等）。変わると「1 局に出す回数」を数え直す。
    public init(isEligible: Bool, game: Int, activity: AnyHashable) {
        self.isEligible = isEligible
        self.game = game
        self.activity = activity
    }
}

extension View {
    /// 操作行に、ヒントを促す吹き出しを重ねる。`nudge` が nil なら何もしない。
    func hintNudge(_ nudge: HintNudge?) -> some View {
        modifier(HintNudgeModifier(nudge: nudge))
    }
}

private struct HintNudgeModifier: ViewModifier {
    let nudge: HintNudge?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownCount = 0
    @State private var isShowing = false

    /// 待ち時間を数え直す条件。バックグラウンドの時間は数えない（アクティブに戻ると 0 から）。
    private struct Key: Hashable {
        let isEligible: Bool
        let game: Int
        let activity: AnyHashable
        let isActive: Bool
    }

    private var key: Key {
        Key(isEligible: nudge?.isEligible ?? false, game: nudge?.game ?? 0, activity: nudge?.activity ?? AnyHashable(0), isActive: scenePhase == .active)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                // 出し入れは opacity で行う（`if` で挿し替えると下の alignmentGuide が効かず、吹き出しが操作行に重なった）。
                HintNudgeBubble()
                    .opacity(isShowing ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    // 操作行の真上・右端（「⋯」の上）に、下端を操作行の上辺へ合わせて置く。
                    .alignmentGuide(.top) { $0[.bottom] + 4 }
            }
            .onChange(of: nudge?.game) { shownCount = 0 }
            .task(id: key) {
                setShowing(false)
                guard key.isEligible, key.isActive, HintNudgePolicy.canShow(shownCount: shownCount) else { return }
                try? await Task.sleep(for: HintNudgePolicy.idleDelay)
                guard !Task.isCancelled else { return }
                shownCount += 1
                setShowing(true)
            }
    }

    private func setShowing(_ value: Bool) {
        guard isShowing != value else { return }
        withAnimation(Motion.resolve(.easeOut(duration: 0.2), reduceMotion: reduceMotion)) { isShowing = value }
    }
}

/// 吹き出し。黄＋電球（ヒントの色・#1011）で、下向きの三角が「⋯」を指す。
private struct HintNudgeBubble: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Label("ヒントは「⋯」から", systemImage: "lightbulb.fill")
                .themeCaption(12)
                .lineLimit(1)
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Theme.yellow))
            Triangle()
                .fill(Theme.yellow)
                .frame(width: 12, height: 6)
                .padding(.trailing, 32)
        }
        .fixedSize()
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}
