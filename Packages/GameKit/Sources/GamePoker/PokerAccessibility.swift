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

    /// 上の帯の読み上げ文（例: "3回目 / 10、合計12点、CPU 8点"）。画面は回数と点が別の Text で、
    /// そのままだと別々の要素に分かれて読まれる（#2162 と同じ手当て）。
    public static func scoreboardLabel(round: Int, playerPoints: Int, cpuPoints: Int) -> String {
        tr("%1$lld回目 / %2$lld、合計%3$lld点、CPU %4$lld点",
           round, PokerModel.roundsPerSession, playerPoints, cpuPoints)
    }

    /// 決着時の役名の行の読み上げ文（例: "あなた、スリーカード、勝ち！"）。画面は見出し・役名・勝敗の印が
    /// 別々の Text で、役名だけが順に読まれると誰の役か分からない（#2589）。
    /// `winner` が nil（勝敗の印を出さない `.showdown`）のときは主体と役名だけにする。
    public static func handRankLabel(subject: String, rank: PokerHandRank, side: PokerWinner, winner: PokerWinner?) -> String {
        var label = tr("%@、%@", subject, rank.description)
        guard let winner else { return label }
        let verdict: String
        switch winner {
        case .tie: verdict = tr("引き分け")
        case side: verdict = tr("勝ち！")
        default: verdict = tr("負け")
        }
        label = tr("%@、%@", label, verdict)
        return label
    }
}
