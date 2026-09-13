import Core

/// できごと（`RunnerEvent`）に対して鳴らす手応え（#703 の効果音 4 音）。
///
/// このゲームには**音の発火点を別に作らない**。Core の `SoundEffect` は触覚
/// （`FeedbackImpact` / `FeedbackNotice`）と 1 対 1 で、App 層が `CompositeFeedbackService` で
/// 触覚と効果音を同じ呼び出しに相乗りさせている（`SoundEffect` の doc）。だから
/// 「跳ぶ → light」「取る → light」「やられる → error」「クリア → success」の 4 音は、
/// ここで決めた触覚をそのまま `services.feedback` に渡すだけで鳴る。設定の効果音オフは
/// `GatedFeedbackService` が受け持つので、ここには条件分岐が無い。
///
/// 純関数にしてあるのは、`RunnerModel.handle` の中で状態遷移と混ざっている対応表を
/// テストで固定するため（`FeedbackCueTests`）。跳ぶ音だけは `RunnerEvent` ではなく
/// `RunnerModel.press()` が「ジャンプが成立したとき」（`RunnerField.jump()` が true）に
/// 直接 `impact(.light)` を鳴らす——踏み切りはできごとではなく操作の結果なので。
public enum RunnerFeedbackCue: Equatable, Sendable {
    /// 操作の成立（触覚の強さ）。
    case impact(FeedbackImpact)
    /// 決着・通過（触覚の種類）。
    case notice(FeedbackNotice)

    /// できごとに対する手応え。
    ///
    /// - Parameter lastLandingWasJust: `.landed` のとき、その着地がジャスト着地（#673）だったか。
    ///   上乗せが乗ったことを数字を見ずに指で分かるよう、一段強くする。
    public static func cue(for event: RunnerEvent, lastLandingWasJust: Bool) -> RunnerFeedbackCue {
        switch event {
        case .landed:             return .impact(lastLandingWasJust ? .medium : .light)
        case .passedCheckpoint:   return .notice(.success)
        case .collectedSpeedItem: return .impact(.light)
        case .fell, .crashed:     return .notice(.error)
        case .reachedGoal:        return .notice(.success)
        }
    }

    /// この手応えに相乗りして鳴る効果音（App 層の `SoundFeedbackService` が同じ対応で鳴らす）。
    public var soundEffect: SoundEffect {
        switch self {
        case .impact(let style): return SoundEffect(style)
        case .notice(let type):  return SoundEffect(type)
        }
    }
}

extension FeedbackService {
    /// 手応えを鳴らす。
    @MainActor func play(_ cue: RunnerFeedbackCue) {
        switch cue {
        case .impact(let style): impact(style)
        case .notice(let type):  notify(type)
        }
    }
}
