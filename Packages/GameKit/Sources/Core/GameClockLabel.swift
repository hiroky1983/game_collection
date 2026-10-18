import SwiftUI

/// 計時のあるゲームのステータスバーに出す時計の見え方（#1857）。
///
/// 文字列の組み立て（`0:00`・`00:00`・`000` など）はゲームごとの表示の約束なので呼び出し側に任せ、
/// アイコン・フォント・色だけを揃える。
public struct GameClockLabel: View {
    private let text: String
    private let size: CGFloat

    public init(_ text: String, size: CGFloat = 14) {
        self.text = text
        self.size = size
    }

    public var body: some View {
        Label(text, systemImage: "clock")
            .scaledFont(size, weight: .bold, design: .monospaced)
            .foregroundStyle(Theme.tealText)
    }
}

public extension View {
    /// 計時の止め方・動かし方（画面側）をまとめて取り付ける（#1857）。
    ///
    /// - 画面を離れたら止める（#375）。戻れば各画面の `.task` が `resume` で再開する。
    /// - 背面に回っている間は止める（基盤規約「バックグラウンド移行時は即一時停止」・#1734）。
    ///   前面に戻ったら、広告の視聴中でも `isHeld` でもなければ再開する。
    /// - 「遊び方（？）」のシートを開いている間は止める（#2406）。
    /// - 広告のロード〜視聴中は止める（全画面広告は `onDisappear` を発火させない・#1382）。
    ///
    /// - Parameters:
    ///   - rescues: この画面の救済。どれかが `isWatching` の間は止める。
    ///   - isHeld: 開始シート・新規ゲームのシートを出している間など、画面の都合で止めておくとき true。
    ///     true になったら止め、false に戻ったら再開する（#2406）。「遊び方（？）」のシートは
    ///     `.howToPlay` が自動で伝えるので渡さなくてよい。
    ///   - pause: 計時を止める（`model.pauseTimer`。止める前に保存し直す）。
    ///   - resume: 計時を再開する（`model.resumeTimerIfNeeded`）。
    func gameTimerLifecycle(
        rescues: [RewardedRescue] = [],
        isHeld: Bool = false,
        pause: @escaping @MainActor () -> Void,
        resume: @escaping @MainActor () -> Void
    ) -> some View {
        modifier(GameTimerLifecycle(rescues: rescues, isHeld: isHeld, pause: pause, resume: resume))
    }
}

/// 計時を動かしてよいか。止める要因（シート・広告）が 1 つも無いときだけ true。
public enum GameTimerHold {
    public static func allowsRunning(isHeld: Bool, isHowToPlayOpen: Bool, rescueHoldsClock: Bool) -> Bool {
        !isHeld && !isHowToPlayOpen && !rescueHoldsClock
    }
}

private struct GameTimerLifecycle: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isHowToPlayOpen = false
    let rescues: [RewardedRescue]
    let isHeld: Bool
    let pause: @MainActor () -> Void
    let resume: @MainActor () -> Void

    func body(content: Content) -> some View {
        content
            .onDisappear { pause() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    pause()
                } else if allowsRunning {
                    resume()
                }
            }
            // シート（新規ゲーム・遊び方）を開いている間は止め、閉じたら再開する（#2406）。
            .onPreferenceChange(HowToPlayPresentedKey.self) { isHowToPlayOpen = $0 }
            .onChange(of: isHeld || isHowToPlayOpen) { _, held in
                if held { pause() } else if allowsRunning { resume() }
            }
            .pausesTimerWhileWatching(rescues, pause: pause, resume: resume)
    }

    private var allowsRunning: Bool {
        GameTimerHold.allowsRunning(
            isHeld: isHeld, isHowToPlayOpen: isHowToPlayOpen,
            rescueHoldsClock: rescues.contains(where: { $0.holdsClock }))
    }
}
