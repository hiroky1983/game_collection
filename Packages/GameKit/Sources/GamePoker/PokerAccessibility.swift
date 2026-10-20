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
        return tr("%@、捨てる札に選択中", name)
    }

    /// 役一覧の見本 5 枚の読み上げ文（例: "スペードのA、スペードのK、…"）。役名と説明は
    /// 隣の Text が読むので、ここは札の並びだけにする。
    public static func handGuideCardsLabel(cards: [PokerCard]) -> String {
        cards.map { $0.figure.spokenLabel }.joined(separator: tr("、"))
    }

    /// 手札 1 枚のヒント。交換フェーズ以外は空（選べない札に操作を案内しない）。
    public static func handCardHint(phase: PokerPhase) -> String {
        acceptsSelection(phase: phase) ? tr("ダブルタップで捨てる札の選択を切り替えます") : ""
    }

    /// 勝敗と合計点の読み上げ文（例: "3勝1敗0分、合計18点"）。画面は 2 つの Text に分かれているので 1 要素にまとめる。
    public static func scoreLabel(wins: Int, losses: Int, draws: Int, points: Int) -> String {
        tr("%1$lld勝%2$lld敗%3$lld分、合計%4$@点", wins, losses, draws, RecordFormat.number(points))
    }
}
