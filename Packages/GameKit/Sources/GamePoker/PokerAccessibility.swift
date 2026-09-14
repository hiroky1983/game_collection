import Foundation
import Core

/// 手札の VoiceOver 読み上げ文（#710。大富豪の #188 と同じ形）。
///
/// 手札は `onTapGesture` で組んでいるため、Button と違ってボタン trait も読み上げ文も
/// 自動では付かない。捨てる札に選んだことも枠色と浮き沈みでしか表していないので、
/// 状態を文字にして補う。読み上げ文はここに集約して純関数にし、View を組まずにテストできるようにする。
public enum PokerAccessibility {

    /// 手札を選べるのは交換フェーズだけ（`PokerModel.toggleCardSelection` と同じ条件）。
    public static func acceptsSelection(phase: PokerPhase) -> Bool {
        phase == .exchange
    }

    /// 手札 1 枚の読み上げ文（例: "ハートの7、捨てる札に選択中"）。
    ///
    /// 選択の状態は交換フェーズでだけ読む。ほかのフェーズでは選べないので、札の名前だけにする。
    public static func handCardLabel(card: PokerCard, isSelected: Bool, phase: PokerPhase) -> String {
        let name = card.figure.spokenLabel
        guard acceptsSelection(phase: phase), isSelected else { return name }
        return "\(name)、捨てる札に選択中"
    }

    /// 手札 1 枚のヒント。交換フェーズ以外は空（選べない札に操作を案内しない）。
    public static func handCardHint(phase: PokerPhase) -> String {
        acceptsSelection(phase: phase) ? "ダブルタップで捨てる札の選択を切り替えます" : ""
    }
}
