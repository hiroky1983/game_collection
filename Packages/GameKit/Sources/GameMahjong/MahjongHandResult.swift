import Foundation
import Observation
import Core
import MahjongTiles

// MARK: - 進行の段階

public enum MahjongPhase: String, Equatable, Sendable, Codable {
    /// 開始前（スタートシート表示中）。
    case idle
    /// 対局中。
    case playing
    /// 自分がロンできる牌が出て、宣言するか見逃すかを待っている。
    case ronOffer
    /// 自分が鳴ける牌が出て、鳴くかスルーするかを待っている。
    case callOffer
    /// 1 局の決着（和了 or 流局）を見せている。
    case handResult
    /// 東風戦そのものの終了（順位が出ている）。
    case gameResult
}

/// 1 局の決着の内訳。リザルト表示にそのまま使う。
public struct MahjongHandResult: Equatable, Sendable, Codable {
    public enum Kind: String, Equatable, Sendable, Codable {
        case tsumo, ron, exhaustiveDraw
    }
    public let kind: Kind
    /// 和了した人。流局なら nil。
    public let winner: Int?
    /// 放銃した人。ツモ・流局なら nil。
    public let loser: Int?
    /// 成立した役（表示用の名前と飜数）。
    public let yaku: [String]
    public let han: Int
    public let fu: Int
    /// 満貫以上の呼び名。
    public let limitName: String?
    /// 和了者が受け取った点（本場・供託を含む）。
    public let gainedPoints: Int
    /// 流局時に聴牌していた人。
    public let tenpaiPlayers: [Int]
    /// この局で各プレイヤーの点数がどれだけ動いたか（添字はプレイヤー番号、この局の直前からの差分）。
    /// 和了者はプラス、放銃・ツモ払い・流局のノーテン罰符はマイナス。会長指摘「誰が誰に振り込んだか
    /// わかるようにしてほしい」への対応で、リザルト画面の得点表に添える。
    public let pointChanges: [Int]
    // 和了手の表示（#351）で足した項目。`handResult` はリザルト中断の保存対象（#350）なので、
    // 古い中断データを読めなくしないため**任意**にする（`melds` と同じ判断）。
    /// 和了者の門前手牌（和了牌を含まない）。流局では nil。
    public let winningHand: [MahjongTile]?
    /// 和了者の副露。流局では nil。
    public let winningMelds: [MahjongCall]?
    /// 和了牌。流局では nil。
    public let winningTile: MahjongTile?
    /// 立直で和了ったときの裏ドラ表示牌。立直していない和了・流局では nil。
    public let uraDoraIndicators: [MahjongTile]?
    // 卓中央の表示ずれ（#375）で足した項目。上と同じ理由で**任意**にする。
    /// 決着したこの局の局数（東 n 局の n）。`finishHand` はリザルト表示に入るのと同時に
    /// 次局へ繰り上げるため、卓中央にはこちらを出す。古い中断データでは nil。
    public let roundNumber: Int?
    /// 決着したこの局の本場。`roundNumber` と同じ理由で持つ。
    public let honba: Int?

    init(
        kind: Kind,
        winner: Int?,
        loser: Int?,
        yaku: [String],
        han: Int,
        fu: Int,
        limitName: String?,
        gainedPoints: Int,
        tenpaiPlayers: [Int],
        pointChanges: [Int],
        winningHand: [MahjongTile]? = nil,
        winningMelds: [MahjongCall]? = nil,
        winningTile: MahjongTile? = nil,
        uraDoraIndicators: [MahjongTile]? = nil,
        roundNumber: Int? = nil,
        honba: Int? = nil
    ) {
        self.kind = kind
        self.winner = winner
        self.loser = loser
        self.yaku = yaku
        self.han = han
        self.fu = fu
        self.limitName = limitName
        self.gainedPoints = gainedPoints
        self.tenpaiPlayers = tenpaiPlayers
        self.pointChanges = pointChanges
        self.winningHand = winningHand
        self.winningMelds = winningMelds
        self.winningTile = winningTile
        self.uraDoraIndicators = uraDoraIndicators
        self.roundNumber = roundNumber
        self.honba = honba
    }
}

// MARK: - 表示（#2166）

/// `yaku`・`limitName` は中断データに入る保存値なので日本語のまま持ち（`MahjongModel+Settlement`・
/// `MahjongScoring`）、画面に出すときにだけ表示言語に直す。日本語では保存値をそのまま返す。
/// 知らない形（将来の表記変更・壊れたデータ）は保存値をそのまま出す。
extension MahjongHandResult {
    /// `yaku` の 1 行（「立直 1飜」「役牌 字牌の中 1飜」「国士無双 役満」）。
    static func displayYakuLine(_ stored: String) -> String {
        guard let space = stored.lastIndex(of: " ") else { return displayYakuName(stored) }
        let name = String(stored[..<space])
        let han = String(stored[stored.index(after: space)...])
        return displayYakuName(name) + " " + displayHan(han)
    }

    /// 役名（`MahjongYaku.name`、または役牌の「役牌 」+ 日本語の牌名）。
    static func displayYakuName(_ stored: String) -> String {
        if let yaku = MahjongYaku.allCases.first(where: { $0.name == stored }) {
            return yaku.displayName
        }
        let dragonPrefix = MahjongYaku.yakuhaiDragon.name + " "
        if stored.hasPrefix(dragonPrefix) {
            let tileName = String(stored.dropFirst(dragonPrefix.count))
            if let tile = MahjongTile.all.first(where: { $0.displayName(language: .development) == tileName }) {
                return tr("役牌 %@", tile.displayName)
            }
        }
        return stored
    }

    /// 飜数の欄（「1飜」または「役満」）。
    static func displayHan(_ stored: String) -> String {
        if stored == "役満" { return tr("役満") }
        if stored.hasSuffix("飜"), let han = Int(stored.dropLast()) { return tr("%lld飜", han) }
        return stored
    }

    /// 満貫以上の呼び名（`MahjongScoring.basePoints` の保存値）。
    static func displayLimitName(_ stored: String) -> String {
        switch stored {
        case "役満":   return tr("役満")
        case "数え役満": return tr("数え役満")
        case "三倍満":  return tr("三倍満")
        case "倍満":   return tr("倍満")
        case "跳満":   return tr("跳満")
        case "満貫":   return tr("満貫")
        default:
            // 複数の役満（「2倍役満」）。
            if stored.hasSuffix("倍役満"), let count = Int(stored.dropLast(3)) {
                return tr("%lld倍役満", count)
            }
            return stored
        }
    }
}

/// 東風戦が終わった理由。リザルトの見出しに使う（#352。東2局で突然終わっても
/// 「なぜ終わったか」が画面から読めるようにする）。
public enum MahjongGameEndReason: Equatable, Sendable {
    /// 東4局まで打ち切った（通常の終局）。
    case completedAllRounds
    /// 東4局の親がトップのまま連荘条件を満たしたため打ち切った。
    case agariYame
    /// 誰かの持ち点がマイナスになった。
    case busted
}
