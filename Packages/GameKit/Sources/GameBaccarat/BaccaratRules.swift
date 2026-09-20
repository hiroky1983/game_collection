import Foundation
import Core

// MARK: - Card

public enum BaccaratSuit: Int, CaseIterable, Codable, Sendable {
    case spades, hearts, diamonds, clubs

    /// トランプ共通基盤（#397）の描画用スート。`rawValue` の一致に頼らず明示的に対応させる。
    public var playing: PlayingCardSuit {
        switch self {
        case .spades:   return .spade
        case .hearts:   return .heart
        case .diamonds: return .diamond
        case .clubs:    return .club
        }
    }
}

public struct BaccaratCard: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public let suit: BaccaratSuit
    public let rank: Int  // 1–13 (1=A, 11=J, 12=Q, 13=K)

    /// バカラの点数。**A=1・2〜9 は数字どおり・10 と絵札は 0**（ブラックジャックと違い A は 1 点固定）。
    public var points: Int { rank >= 10 ? 0 : rank }

    /// トランプ共通基盤（#397）へ渡す面の内容。`rank` は既に A=1 表記なのでそのまま渡す。
    public var figure: PlayingCardFigure {
        .pip(suit: suit.playing, rank: rank)
    }
}

// MARK: - 合計

/// 手の合計。バカラは**下 1 桁だけ**を見る（7+8=15 → 5）。9 がいちばん強い。
func baccaratTotal(_ hand: [BaccaratCard]) -> Int {
    hand.reduce(0) { $0 + $1.points } % 10
}

/// ナチュラル（最初の 2 枚で 8 か 9）。どちらか一方でも成立したら、**両者とも 3 枚目を引かず即決着**する。
func isNatural(_ hand: [BaccaratCard]) -> Bool {
    hand.count == 2 && baccaratTotal(hand) >= 8
}

// MARK: - 3 枚目の引き足し（公式ルール）

/// プレイヤーが 3 枚目を引くか。2 枚合計 0〜5 で引き、6〜7 はスタンド。
///
/// ナチュラル（8・9）はこの関数より先に `baccaratPlayOut` が弾く。
func playerDrawsThird(total: Int) -> Bool { total <= 5 }

/// バンカーが 3 枚目を引くか。
///
/// - Parameter playerThird: プレイヤーの 3 枚目の**点数**。プレイヤーが引かなかったときは nil。
///   nil のときはプレイヤーと同じ「0〜5 なら引く」に戻る。
///
/// 引いたときの公式表（`playerThird` はプレイヤーの 3 枚目の点数）:
///
/// | バンカーの 2 枚合計 | 引く条件 |
/// | --- | --- |
/// | 0・1・2 | 必ず引く |
/// | 3 | 8 以外 |
/// | 4 | 2〜7 |
/// | 5 | 4〜7 |
/// | 6 | 6・7 |
/// | 7 | スタンド |
func bankerDrawsThird(total: Int, playerThird: Int?) -> Bool {
    guard let playerThird else { return total <= 5 }
    switch total {
    case 0, 1, 2: return true
    case 3:       return playerThird != 8
    case 4:       return (2...7).contains(playerThird)
    case 5:       return (4...7).contains(playerThird)
    case 6:       return (6...7).contains(playerThird)
    // 7 はスタンド。8・9 はナチュラルなので `baccaratPlayOut` がここへ来させない。
    default:      return false
    }
}

/// 最初の 2 枚ずつから、公式ルールの引き足しを適用した最終形を返す。
///
/// 引く順は**プレイヤーが先**。バンカーの判断はプレイヤーの 3 枚目を見てから決まるので、
/// この順序を崩すと表が引けなくなる。
///
/// - Parameter thirdCards: 3 枚目に使う候補を**山から引く順**に渡す（先頭から順に使う）。
///   最大 2 枚しか使わず、使わなかったぶんは捨て札になる（配りごとに山を切り直すので影響しない）。
///   純関数に保つために山そのものは受け取らない——テストは狙った 3 枚目を直接渡せる。
func baccaratPlayOut(
    player: [BaccaratCard],
    banker: [BaccaratCard],
    thirdCards: [BaccaratCard]
) -> (player: [BaccaratCard], banker: [BaccaratCard]) {
    var player = player
    var banker = banker
    // ナチュラルはどちらの手も引かずに決着する。
    guard !isNatural(player), !isNatural(banker) else { return (player, banker) }

    var nextIndex = 0
    func take() -> BaccaratCard? {
        guard nextIndex < thirdCards.count else { return nil }
        defer { nextIndex += 1 }
        return thirdCards[nextIndex]
    }

    var playerThird: Int?
    if playerDrawsThird(total: baccaratTotal(player)), let card = take() {
        player.append(card)
        playerThird = card.points
    }
    // バンカーの判断は**2 枚合計**で行う（引いた 3 枚目を含めない）。
    if bankerDrawsThird(total: baccaratTotal(banker), playerThird: playerThird), let card = take() {
        banker.append(card)
    }
    return (player, banker)
}

// MARK: - 賭け先と決着

/// 1 局に 1 つだけ選ぶ賭け先。
public enum BaccaratBet: String, CaseIterable, Codable, Sendable {
    case player, banker, tie

    public var label: String {
        switch self {
        case .player: return "プレイヤー"
        case .banker: return "バンカー"
        case .tie:    return "タイ"
        }
    }

    /// 配当の見出し（ボタンに出す）。手数料を引いたあとの倍率で書く。
    public var payoutLabel: String {
        switch self {
        case .player: return "1倍"
        case .banker: return "0.95倍"
        case .tie:    return "8倍"
        }
    }
}

public enum BaccaratOutcome: String, Codable, Sendable, Equatable {
    case player, banker, tie
}

func baccaratOutcome(player: [BaccaratCard], banker: [BaccaratCard]) -> BaccaratOutcome {
    let playerTotal = baccaratTotal(player)
    let bankerTotal = baccaratTotal(banker)
    if playerTotal > bankerTotal { return .player }
    if bankerTotal > playerTotal { return .banker }
    return .tie
}

// MARK: - 配当

/// 配当の倍率。数え違いを 1 か所に閉じるため、画面の文言もここから作る。
enum BaccaratPayout {
    /// バンカー勝ちに掛かる手数料（5%）。ハウスエッジの原資で、バンカーの配当だけ 0.95 倍になる。
    static let bankerCommission = 0.05
    /// タイを当てたときの倍率。
    static let tieMultiplier = 8
}

/// 賭け先と決着から、チップの増減を返す。
///
/// - プレイヤー勝ち: 1 倍
/// - バンカー勝ち: 手数料 5% を引いた 0.95 倍（端数は切り捨て）
/// - タイ的中: 8 倍
/// - **タイのとき、プレイヤー／バンカーへの賭けは引き分け**（賭け金はそのまま戻り、増減 0）。
///   一般的なバカラのプッシュ規則で、賭け金を没収しない。
func baccaratChipDelta(bet: BaccaratBet, outcome: BaccaratOutcome, amount: Int) -> Int {
    switch (bet, outcome) {
    case (.player, .player):
        return amount
    case (.banker, .banker):
        return Int(Double(amount) * (1 - BaccaratPayout.bankerCommission))
    case (.tie, .tie):
        return amount * BaccaratPayout.tieMultiplier
    case (.player, .tie), (.banker, .tie):
        return 0
    default:
        return -amount
    }
}
