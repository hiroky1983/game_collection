import SwiftUI

/// ブラックジャックの演出の長さと形（#209）。**状態を持たない定数と純関数だけ**を置き、View から切り出す。
///
/// ポーカー（`PokerMotion`）・将棋（`ShogiMotion`）と同じ方針で、長さは秒の定数として持ち
/// `Animation` はそこから組む。`Animation` からは長さを読み出せないため、定数を経由しないと
/// 「配りは公開より短い」のような**長さの大小関係をテストで固定できない**。
///
/// Reduce Motion への追従は `gameAnimation(_:value:)` / `withGameAnimation(_:_:)` 側が持つ。
/// ON のときは補間が起きず、伏せカードは即座に表になり、カードは遅れなく置かれるだけで、
/// 公開・配布・勝敗の表示そのものは従来どおり反映される。
enum BlackjackMotion {

    // MARK: - 伏せカードの公開（山場）

    /// ディーラーの伏せカードが裏から表へ返りきるまでの長さ（秒）。
    ///
    /// このゲームで唯一「緊張が解ける」瞬間なので、配りの1枚（`dealCardDuration`）より
    /// 長く取り、山場のほうが濃く見えるようにする。
    static let holeCardFlipDuration: TimeInterval = 0.34

    /// 伏せカードの公開。
    static let holeCardFlip: Animation = .easeInOut(duration: holeCardFlipDuration)

    /// 反転の進捗（0 = 裏 / 1 = 表）から、カードを表として描くかどうか。
    ///
    /// 真横を向く 0.5 で入れ替えることで、裏面が縮んで消えた瞬間に表面が現れる。
    static func showsFace(progress: Double) -> Bool { progress >= 0.5 }

    /// 反転の進捗から、カードの Y 軸まわりの回転角（度）。
    static func flipDegrees(progress: Double) -> Double {
        min(max(progress, 0), 1) * 180
    }

    // MARK: - 配布

    /// 初期配牌で各自に配られる枚数。段差の総量を求めるのに使う。
    static let initialCardsPerHand = 2

    /// カード 1 枚が置かれるまでの長さ（秒）。
    static let dealCardDuration: TimeInterval = 0.22

    /// 次の1枚が置かれ始めるまでの遅れ（秒）。
    ///
    /// 実際のディールと同じ「あなた → ディーラー → あなた → ディーラー」の順に置くため、
    /// 4 枚ぶんの段差になる。
    static let dealStagger: TimeInterval = 0.09

    /// 初期配牌の 4 枚すべてが置き終わるまでの長さ（秒）。
    static var dealTotalDuration: TimeInterval {
        dealCardDuration + dealStagger * Double(initialCardsPerHand * 2 - 1)
    }

    /// カードが置かれる前の位置（上に持ち上げた量・pt）。ここから手元へ落ちてくる。
    static let dealOffset: CGFloat = -26

    /// カードが置かれる前の大きさ（1 = 実寸）。遠くから来たように見せる。
    static let dealStartScale: CGFloat = 0.82

    /// `index` 枚目（0 始まり）が置かれ始めるまでの遅れ（秒）。
    ///
    /// 初期配牌の 2 枚だけ段差をつけ、ヒット・ディーラーの引きで**後から増えた 3 枚目以降は
    /// 遅らせない**（1 枚ずつ引く場面で待たされると操作が重く感じるため）。
    static func dealDelay(index: Int, isDealer: Bool) -> TimeInterval {
        guard index >= 0, index < initialCardsPerHand else { return 0 }
        return dealStagger * Double(index * 2 + (isDealer ? 1 : 0))
    }

    /// `index` 枚目（0 始まり）が置かれる動き。
    static func dealAppear(index: Int, isDealer: Bool) -> Animation {
        .easeOut(duration: dealCardDuration)
            .delay(dealDelay(index: index, isDealer: isDealer))
    }

    // MARK: - 勝敗バッジ

    /// 勝敗バッジが現れるまでの長さ（秒）。日常の表示なので山場より短く取る。
    static let outcomeBadgeDuration: TimeInterval = 0.2

    /// 勝敗バッジの出現。
    ///
    /// 伏せカードより先に出ると**答えを見せてから返す**ことになるので、公開が終わってから薄く現れる
    /// （ポーカーが役名を `showdownTotalDuration` だけ遅らせているのと同じ理由）。
    static let outcomeBadge: Animation = .easeIn(duration: outcomeBadgeDuration)
        .delay(holeCardFlipDuration)
}
