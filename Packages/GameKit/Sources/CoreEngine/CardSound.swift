import Foundation

/// トランプの場面の効果音（#2697）。配る・めくる・出す・切るの 4 場面だけ、合成音ではなく
/// 同梱した本物のカードの音（CC0 素材・出所は `docs/design/card-sfx/assets-license.md`）を鳴らす。
///
/// 触覚と同じ呼び出し箇所に相乗りさせるため `FeedbackImpact.card(_:)` として届く。
/// 勝ち・負け・引き分け・節目の音（`SoundEffect`）と、カードを「選ぶ」だけの操作は今のまま。
public enum CardSound: String, CaseIterable, Sendable {
    /// 配る（1 枚ずつ配る・山から引く）。
    case deal = "card-deal"
    /// めくる（裏から表へ）。
    case flip = "card-flip"
    /// 出す・置く（場に出す・台札に置く・組札へ移す）。
    case place = "card-place"
    /// 切る（シャッフル。新しいゲームの開始時に 1 回）。
    case shuffle = "card-shuffle"

    /// 同梱ファイルの拡張子。
    public static let fileExtension = "caf"

    /// 同梱ファイル。見つからなければ nil（呼び出し側は無音で済ませる）。
    public var url: URL? {
        Bundle.module.url(forResource: rawValue, withExtension: Self.fileExtension, subdirectory: "Sounds")
    }

    /// 触覚の強さ。カードの音を鳴らす場面は、これまでの触覚（配る・切る・出す＝手応え、めくる＝軽い）を保つ。
    public var haptic: FeedbackImpact {
        switch self {
        case .deal, .place, .shuffle: return .medium
        case .flip:                   return .light
        }
    }
}
