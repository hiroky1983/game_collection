import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// アニメーションを OS の「視差効果を減らす」設定（Reduce Motion）に追従させる共通レイヤー（#210）。
///
/// 盤面の駒・カード・牌が動く演出は前庭障害・動揺病のあるユーザーに直接影響するため、
/// **アプリ内のアニメーションはすべてこのレイヤー経由で書く**。
/// - 宣言的な指定 … `View.gameAnimation(_:value:)`（`.animation(_:value:)` の代わり）
/// - 命令的な指定 … `withGameAnimation(_:_:)`（`withAnimation(_:_:)` の代わり）
///
/// Reduce Motion が ON のときはアニメーションを `nil`（＝即時反映）へ落とすだけで、
/// **状態変更そのものは必ず実行する**。ここを取り違えると「演出が消える」ではなく
/// 「盤面が更新されない・オーバーレイが出ない」という退行になる。
/// OFF のときは要求されたアニメーションをそのまま通すので、既定の見た目は従来と一切変わらない。
public enum Motion {
    /// 要求されたアニメーションを Reduce Motion の状態に応じて解決する。
    ///
    /// この関数だけが「ON なら止める」という判断を持つ。宣言的・命令的の両経路がここに集まるため、
    /// 挙動の検証は `MotionTests` でこの純関数に対して行える。
    public static func resolve(_ animation: Animation?, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// SwiftUI の環境（`\.accessibilityReduceMotion`）を参照できない場所向けの現在値。
    ///
    /// `withAnimation` はビューの外からも呼べる命令的 API なので、環境ではなく
    /// プラットフォームの設定を直接読む。SwiftUI の環境値も同じ設定を出所にしている。
    @MainActor public static var isReduceMotionEnabled: Bool {
        if let override { return override }
        #if canImport(UIKit)
        return UIAccessibility.isReduceMotionEnabled
        #elseif canImport(AppKit)
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        return false
        #endif
    }

    /// テストから `isReduceMotionEnabled` を差し替えるための注入口。`nil` で実機の設定に戻る。
    /// 製品コードから触らせないよう `internal` に留める（テストは `@testable import Core` で参照する）。
    @MainActor static var override: Bool?
}

/// `withAnimation(_:_:)` の Reduce Motion 追従版（#210）。
///
/// ON のときはアニメーションなしで `body` を実行する。**`body` は常に実行される**。
@MainActor
@discardableResult
public func withGameAnimation<Result>(
    _ animation: Animation? = .default,
    _ body: () throws -> Result
) rethrows -> Result {
    try withAnimation(Motion.resolve(animation, reduceMotion: Motion.isReduceMotionEnabled), body)
}

public extension View {
    /// `.animation(_:value:)` の Reduce Motion 追従版（#210）。
    ///
    /// ON のときは `nil` アニメーション（＝即時反映）に落とす。`value` の変化そのものは
    /// 従来どおりビューに反映されるため、状態遷移が失われることはない。
    func gameAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(GameAnimation(animation: animation, value: value))
    }
}

/// `View.gameAnimation(_:value:)` の実体。
private struct GameAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(Motion.resolve(animation, reduceMotion: reduceMotion), value: value)
    }
}
