import Foundation
import Observation
import Core
import MahjongTiles

// MARK: - 永続化

struct MahjongSnapshot: Codable {
    let wall: [MahjongTile]
    let wallIndex: Int
    let deadWall: [MahjongTile]
    let hands: [MahjongHand]
    let drawnTile: MahjongTile?
    let discards: [[MahjongTile]]
    let riichi: [Bool]
    let riichiFuriten: [Bool]
    let scores: [Int]
    let dealer: Int
    let roundNumber: Int
    let honba: Int
    let riichiSticks: Int
    let currentPlayer: Int
    let turnCount: Int
    // 鳴き（#263）で足した項目。**古い中断データを読めなくしないため任意**にする
    // （必須にすると更新直後の 1 局が黙って消える）。
    let melds: [[MahjongCall]]?
    /// フリテンの判定に使う「これまでに捨てた牌の種類」。鳴かれて河から消えた牌も残す。
    let discardedKinds: [[Int]]?
    let revealedDoraCount: Int?
    let deadWallDraws: Int?
    /// トビ復活（#338）を使い切ったか。中断を挟んでも「1 半荘 1 回まで」を守るために持ち回る。
    /// 上と同じ理由で任意（古い中断データは「まだ使っていない」扱いになる）。
    let hasRevivedThisGame: Bool?
    // 局のリザルト中の中断（#350）で足した項目。同じく任意にして古い中断データも読めるようにする。
    /// リザルト表示中に中断したときの決着内容。**nil なら対局中の中断**（この有無が
    /// `.handResult` か `.playing` かをそのまま表す。決着内容は決着時にしか入らないため）。
    let handResult: MahjongHandResult?
    /// アガリやめが確定しているか。リザルト中断から再開しても終局判定を引き継ぐ。
    let endsAfterThisHand: Bool?
    /// その対局に焼き込まれた長さ（#639）。上と同じく**旧データには鍵が無い**ので任意にする
    /// （必須にすると更新直後の 1 局が黙って消える）。nil は一局戦が無かった頃の対局 = 東風戦。
    let gameLength: MahjongGameLength?
}

// MARK: - Seeded RNG

/// テスト用の決定的な乱数生成器（CoreEngine の `SplitMix64`・#1074）。本番は `seed` を渡さないので system の乱数を使う。
typealias MahjongSeededGenerator = SplitMix64
