import SwiftUI

private struct PlayStreakProviderKey: EnvironmentKey {
    /// 配られていない画面（テスト・プレビュー・撮影用の単独表示）では 0 日 = 何も出さない。
    static let defaultValue: @MainActor () -> Int = { 0 }
}

public extension EnvironmentValues {
    /// 今日時点の連続プレイ日数を返す口（#2510）。ハブがゲーム画面ごとに配る。
    ///
    /// 値ではなく関数にしているのは、決着で今日が「遊んだ日」に加わると連続日数が変わるため。
    /// 画面を作った時点の値を持つと、その日の最初の 1 局を終えても古い日数のままになる。
    var playStreakProvider: @MainActor () -> Int {
        get { self[PlayStreakProviderKey.self] }
        set { self[PlayStreakProviderKey.self] = newValue }
    }
}

/// 結果カードの末尾に添える「連続 N 日あそび中」の 1 行（#2510）。
///
/// 文言と出す条件（2 日以上）はハブと同じ `PlayDayStreak.hubText`。連続が 2 日未満なら何も描画しない。
/// 通知・広告・報酬には繋げない（`docs/spec-app.md` の連続日数の方針）。
struct PlayStreakLine: View {
    @Environment(\.playStreakProvider) private var provider

    var body: some View {
        if let text = PlayDayStreak.hubText(streak: provider()) {
            Text(text)
                .themeCaption(13, weight: .semibold, maxScale: 1.3)
                .foregroundStyle(Theme.inkSub)
                .multilineTextAlignment(.center)
        }
    }
}
