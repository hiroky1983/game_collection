import SwiftUI

/// 画面の広さに応じたレイアウト値を **1 か所で決める**ための適応レイヤ（#458・iPad 対応）。
///
/// 設計上の制約: 237 ファイルに `horizontalSizeClass` の分岐を撒かない。
/// 判定と数値はすべてここに集約し、各画面は `@Environment(\.adaptiveLayout)` から
/// **値を読むだけ**にする。新しい画面を iPad へ広げるときも、増えるのはこの型のプロパティであって
/// 各画面の分岐ではない。
///
/// 判定に `horizontalSizeClass` ではなく**実際のコンテナ幅**を使う理由:
///
/// 1. サイズクラスは UIKit 由来で macOS には無く、`swift test`（mac ターゲット）で検証できない。
///    幅なら純粋な値の計算になるので `LayoutTests` でそのままテストできる。
/// 2. iPadOS 26 以降のウインドウ表示や Split View では、同じ iPad でも実際の幅が大きく変わる。
///    「iPad かどうか」ではなく「いま何 pt あるか」で決めるほうが素直に追従する。
public struct AdaptiveLayout: Equatable, Sendable {
    /// 「広い」と見なす境目（pt）。
    ///
    /// 現行 iPhone の最大幅は 440pt（16 Pro Max）、iPad の最小幅は 744pt（iPad mini 縦）。
    /// あいだを取って 700pt に置く。iPad でも Split View で半分以下に絞られたときは
    /// この値を下回り、iPhone と同じ狭いレイアウトに落ちる（意図した挙動）。
    public static let wideThreshold: CGFloat = 700

    /// いま使えるコンテナの幅（pt）。
    public let width: CGFloat

    public init(width: CGFloat) {
        self.width = width
    }

    /// 幅の広い環境（iPad の全画面など）か。
    public var isWide: Bool { width >= Self.wideThreshold }

    /// ハブのゲームカードに与える最小幅（`GridItem(.adaptive(minimum:))` に渡す）。
    ///
    /// 狭い側の 130pt は #119 の値をそのまま維持する（iPhone は SE 相当の 320pt でも必ず 2 列）。
    /// 広い側を 200pt に上げるのは、130pt のままだと 13 インチ iPad で 7 列に割れて
    /// カードが iPhone より小さくなってしまうため。1024pt 幅で 4 列・1366pt 幅で 6 列になる。
    public var hubCardMinWidth: CGFloat { isWide ? 200 : 130 }

    /// 盤と一緒には拡大されない**固定 pt の部品**（将棋の持ち駒など）に掛ける倍率。
    ///
    /// 盤そのものは `GeometryReader` で幅から作られるので放っておいても広がるが、その脇に置かれた
    /// 固定 pt の部品は据え置きのままで、盤だけが大きくなると比率が崩れて見える。
    ///
    /// 1.5 という値は**盤の拡大率そのものではない**。盤は iPhone の 393pt 幅から iPad の 1024pt 幅で
    /// およそ 2.6 倍になるが、同じだけ脇の部品を大きくすると帯の高さが増えて盤の取り分を食う
    /// （盤は幅ではなく高さで頭打ちになりうる）。見劣りしない範囲で盤を削らない中間に置いている。
    public var elementScale: CGFloat { isWide ? 1.5 : 1 }

    /// 固定 pt の寸法を広い画面向けに拡大する。狭い画面では恒等なので、iPhone の見た目は動かない。
    public func scaled(_ points: CGFloat) -> CGFloat { points * elementScale }
}

// MARK: - Environment

private struct AdaptiveLayoutKey: EnvironmentKey {
    /// 幅が測れるまでは狭いほうに倒す（iPhone の見た目を既定にする）。
    static let defaultValue = AdaptiveLayout(width: 0)
}

public extension EnvironmentValues {
    /// 画面の広さに応じたレイアウト値。`View.providesAdaptiveLayout()` を付けた祖先から配られる。
    var adaptiveLayout: AdaptiveLayout {
        get { self[AdaptiveLayoutKey.self] }
        set { self[AdaptiveLayoutKey.self] = newValue }
    }
}

/// `View.providesAdaptiveLayout()` の実体。
///
/// 幅の取得に `GeometryReader` を**コンテナとして**使うと、中身が左上寄せの
/// 「与えられた分だけ広がるビュー」に変わってレイアウトが崩れる。`.background` に潜り込ませれば
/// 測るだけで配置には一切干渉しない（`onGeometryChange` は iOS 18 以降で、本アプリの
/// デプロイメントターゲット 17.0 では使えない）。
private struct AdaptiveLayoutProvider: ViewModifier {
    @State private var layout = AdaptiveLayout(width: 0)

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear
                        .task(id: geo.size.width) {
                            layout = AdaptiveLayout(width: geo.size.width)
                        }
                }
            }
            .environment(\.adaptiveLayout, layout)
    }
}

public extension View {
    /// 自身の幅を測って `\.adaptiveLayout` を子孫へ配る。**アプリのルートに 1 回だけ**付ける。
    func providesAdaptiveLayout() -> some View {
        modifier(AdaptiveLayoutProvider())
    }
}
