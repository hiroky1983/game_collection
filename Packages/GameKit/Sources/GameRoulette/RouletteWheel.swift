import Foundation

// MARK: - Wheel

/// ポケットの色。0 だけが緑で、赤・黒は 18 個ずつ。
public enum RouletteColor: String, Codable, Sendable, Equatable {
    case red, black, green
}

/// ヨーロピアン配列（0〜36 の 37 ポケット）のホイール（#1318）。
///
/// 配列も色も実物のヨーロピアンホイールと同じで、伝統的なカジノゲームの一般則。
/// アメリカン配列（00 あり）は採らない（0 が 2 つになりハウスの取り分が倍になる。一人で
/// 遊ぶ仮想チップのゲームで、負けやすくする理由が無い）。
public enum RouletteWheel {
    /// ポケットの数（0〜36）。
    public static let pocketCount = 37

    /// 出目の範囲。
    public static let numbers = 0...36

    /// ホイール上の並び（時計回り・0 を先頭に）。**盤面の数字の並びとは無関係**で、
    /// 隣り合う数字が赤黒・大小・奇偶で散るように組まれている。
    public static let pocketOrder: [Int] = [
        0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10,
        5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26,
    ]

    /// 赤のポケット。残りの 1〜36 が黒。
    public static let redNumbers: Set<Int> = [
        1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36,
    ]

    public static func color(of number: Int) -> RouletteColor {
        if number == 0 { return .green }
        return redNumbers.contains(number) ? .red : .black
    }

    /// `number` がホイール上で何番目のポケットか（0 始まり・時計回り）。範囲外は 0 に倒す。
    public static func pocketIndex(of number: Int) -> Int {
        pocketOrder.firstIndex(of: number) ?? 0
    }
}

// MARK: - Bets

/// 賭けの種類（#1318）。盤面のどこに置いたかを表し、配当と当たり判定を持つ。
///
/// 実物のテーブルにあるうち、**スマホの盤面で場所と意味が一目で対応するもの**だけに絞った。
/// 縦列（コラム）は 4 段 × 9 列の盤面では列と対応しないので入れていない。
/// スプリット・ストリートなど数字の境目に置く賭けも、境目をタップで狙い分けられないので入れていない。
public enum RouletteBetKind: Codable, Hashable, Sendable {
    /// 数字 1 点（0〜36）。配当 35 倍。
    case straight(Int)
    /// 赤・黒・奇数・偶数・1〜18・19〜36。配当 1 倍（元金と同額）。0 はすべて外れ。
    case red, black, odd, even, low, high
    /// 12 個ずつの区分（1 = 1〜12・2 = 13〜24・3 = 25〜36）。配当 2 倍。
    case dozen(Int)

    /// 当たったときに**元金に加えて**受け取る倍率。元金は別に戻る。
    public var payout: Int {
        switch self {
        case .straight: return 35
        case .dozen:    return 2
        default:        return 1
        }
    }

    /// この賭けが `number` で当たるか。
    public func covers(_ number: Int) -> Bool {
        switch self {
        case .straight(let n): return n == number
        case .red:             return RouletteWheel.color(of: number) == .red
        case .black:           return RouletteWheel.color(of: number) == .black
        case .odd:             return number != 0 && number % 2 == 1
        case .even:            return number != 0 && number % 2 == 0
        case .low:             return (1...18).contains(number)
        case .high:            return (19...36).contains(number)
        case .dozen(let d):    return d >= 1 && d <= 3 && ((d - 1) * 12 + 1...d * 12).contains(number)
        }
    }

    /// 盤面と結果表示に出す名前。
    public var label: String {
        switch self {
        case .straight(let n): return "\(n)"
        case .red:             return "赤"
        case .black:           return "黒"
        case .odd:             return "奇数"
        case .even:            return "偶数"
        case .low:             return "1〜18"
        case .high:            return "19〜36"
        case .dozen(let d):    return "\((d - 1) * 12 + 1)〜\(d * 12)"
        }
    }

    /// 盤面の下段に並べる「数字 1 点」以外の賭け（表示順）。
    public static let dozens: [RouletteBetKind] = [.dozen(1), .dozen(2), .dozen(3)]
    public static let evenMoney: [RouletteBetKind] = [.low, .even, .red, .black, .odd, .high]
}

/// 盤面に置いた 1 口。同じ場所へ何度も置けるので、口ごとに持って「戻す」で最後の 1 口だけ外す。
public struct RouletteBet: Identifiable, Codable, Equatable, Sendable {
    public let id: Int
    public let kind: RouletteBetKind
    public let amount: Int

    public init(id: Int, kind: RouletteBetKind, amount: Int) {
        self.id = id
        self.kind = kind
        self.amount = amount
    }
}

// MARK: - Settlement

/// 1 スピンの精算結果。
public struct RouletteSettlement: Equatable, Sendable {
    /// 場に出した総額。
    public let staked: Int
    /// 戻ってきた総額（当たった口の元金 + 配当）。
    public let returned: Int
    /// 当たった口の数。
    public let winningBets: Int

    public init(staked: Int, returned: Int, winningBets: Int) {
        self.staked = staked
        self.returned = returned
        self.winningBets = winningBets
    }

    /// 収支。チップの増減はこの値。
    public var net: Int { returned - staked }
}

/// 精算の純関数。当たった口は元金 × (1 + 配当倍率) が戻り、外れた口は元金ごと失う。
public func rouletteSettlement(bets: [RouletteBet], winningNumber: Int) -> RouletteSettlement {
    var returned = 0
    var winning = 0
    for bet in bets where bet.kind.covers(winningNumber) {
        returned += bet.amount * (1 + bet.kind.payout)
        winning += 1
    }
    return RouletteSettlement(
        staked: bets.reduce(0) { $0 + $1.amount },
        returned: returned,
        winningBets: winning
    )
}
