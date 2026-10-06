import SwiftUI

/// ヒントを促す表示の出し方の決まり（#1424）。
///
/// 30 秒以上操作が無いときに、ヒントを指す控えめな表示を出す。**表示するだけ**で、
/// ヒントの使用も広告の再生もしない（ナンプレ・麻雀ソリティアのヒントは広告制なので、勝手に押さない）。
/// 見せ方は 2 つ（#1856）: 段にヒントのカプセルがあればそれを光らせ、ヒントが「⋯」の中にあれば「⋯」の左に吹き出しを出す。
public enum HintNudgePolicy {
    /// 操作が無いまま待つ長さ。
    public static let idleDelay: Duration = .seconds(30)
    /// 1 局に出す回数の上限。出しすぎると邪魔になるため。
    public static let maxPerGame = 2

    /// まだ出してよいか。
    public static func canShow(shownCount: Int) -> Bool { shownCount < maxPerGame }

    /// 待ち時間を数え始めてよいか。「⋯」メニューを開いているあいだは数えず、出ている表示も隠す（#1485）。
    /// 閉じると条件が変わるので、そこから改めて `idleDelay` を待つ（閉じた直後にすぐは出さない）。
    public static func canSchedule(isEligible: Bool, isActive: Bool, isMenuOpen: Bool, shownCount: Int) -> Bool {
        isEligible && isActive && !isMenuOpen && canShow(shownCount: shownCount)
    }
}

/// 操作行に渡す「ヒントを促してよい状態か」と「操作があったか」の 2 つ。
///
/// - `isEligible`: 自分の手番・対局中・ヒントが使える、を全部満たすとき true。
///   CPU の手番・結果表示中・広告の視聴中・ヒントが尽きたときは false にする。
/// - `activity`: **操作のたびに値が変わる**印（手数・選択・盤面など）。変わると待ち時間を数え直し、出ている表示を消す。
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

/// 促しを出している最中か。段のヒントのカプセル（`GameActionCapsule`）がこれを読んで光る。
private struct HintNudgeIsShowingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var hintNudgeIsShowing: Bool {
        get { self[HintNudgeIsShowingKey.self] }
        set { self[HintNudgeIsShowingKey.self] = newValue }
    }
}

extension View {
    /// 操作行に、ヒントを促す表示を付ける。`nudge` が nil なら何もしない。
    /// - Parameter isMenuOpen: 「⋯」メニューを開いているか。開いているあいだは促しを出さない（#1485）。
    /// - Parameter highlightsAction: 段にヒントのカプセルがあるか。あれば環境値 `hintNudgeIsShowing` でカプセルを光らせ、
    ///   無ければ「⋯」の左に吹き出しを出す（ヒントが「⋯」の中にある形）。
    func hintNudge(_ nudge: HintNudge?, isMenuOpen: Bool = false, highlightsAction: Bool = false) -> some View {
        modifier(HintNudgeModifier(nudge: nudge, isMenuOpen: isMenuOpen, highlightsAction: highlightsAction))
    }

    /// 段のヒントのカプセルを光らせる（白い縁 + 黄色のにじみ）。Reduce Motion ではにじみを脈打たせない。
    /// 縁は枠の内側、にじみは影なので、段の高さも隣のカプセルの位置も変えない。
    func hintNudgeGlow(_ isOn: Bool, reduceMotion: Bool) -> some View {
        modifier(HintNudgeGlowModifier(isOn: isOn, reduceMotion: reduceMotion))
    }
}

private struct HintNudgeModifier: ViewModifier {
    let nudge: HintNudge?
    let isMenuOpen: Bool
    let highlightsAction: Bool
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
        let isMenuOpen: Bool
    }

    private var key: Key {
        Key(isEligible: nudge?.isEligible ?? false, game: nudge?.game ?? 0, activity: nudge?.activity ?? AnyHashable(0),
            isActive: scenePhase == .active, isMenuOpen: isMenuOpen)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.hintNudgeIsShowing, isShowing && highlightsAction)
            .overlay(alignment: .trailing) {
                // ヒントが「⋯」の中にあるときだけ、「⋯」の**左**に、行の高さの中で横向きに置く（#1485）。
                // 行の中に収まるので、盤にも広告にも重ならない。
                // 出し入れは opacity で行う（`if` で挿し替えると出入りのたびに重なりの計算がやり直しになる）。
                if !highlightsAction {
                    HintNudgeBubble()
                        .opacity(isShowing ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .padding(.trailing, HintNudgeBubble.trailingInset)
                }
            }
            .onChange(of: nudge?.game) { shownCount = 0 }
            .task(id: key) {
                setShowing(false)
                guard HintNudgePolicy.canSchedule(isEligible: key.isEligible, isActive: key.isActive,
                                                  isMenuOpen: key.isMenuOpen, shownCount: shownCount) else { return }
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

/// 段のヒントのカプセルを光らせる。
private struct HintNudgeGlowModifier: ViewModifier {
    let isOn: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if isOn, !reduceMotion {
            // 2 つの位相を行き来して脈打たせる（`phaseAnimator` は trigger を渡さなければ繰り返す）。
            content
                .phaseAnimator([false, true]) { view, bright in
                    glowing(view, intensity: bright ? 1 : 0.35)
                } animation: { _ in
                    .easeInOut(duration: 0.8)
                }
        } else if isOn {
            glowing(content, intensity: 1)
        } else {
            content
        }
    }

    private func glowing<V: View>(_ view: V, intensity: Double) -> some View {
        view
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 2.5)
                    .allowsHitTesting(false)
            )
            .shadow(color: Theme.yellow.opacity(intensity), radius: 8)
    }
}

/// 吹き出し。黄＋電球（ヒントの色・#1011）で、右向きの三角が右隣の「⋯」を指す（#1485）。
/// ヒントが「⋯」の中にあるゲーム向け（段にヒントがあるゲームはカプセルを光らせる）。
struct HintNudgeBubble: View {
    /// 行の右端からの距離。「⋯」の丸（44pt）とのあいだに 4pt あける。
    static let trailingInset: CGFloat = BoardGameControlMetrics.minTapTarget + 4

    var body: some View {
        HStack(spacing: 0) {
            Label("ヒントは「⋯」から", systemImage: "lightbulb.fill")
                .themeCaption(15, maxScale: 1.5)
                .lineLimit(1)
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Theme.yellow))
            Triangle()
                .fill(Theme.yellow)
                .frame(width: 8, height: 16)
        }
        .fixedSize()
    }

    /// 右を向いた三角。
    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}
