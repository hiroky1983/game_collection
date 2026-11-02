/// サイコロ役づくり（#1752）の中断スナップショット。出目・キープ・振った回数・埋めた役の点を保存する
/// （乱数の種は保存しない。次に振る目は再開後の乱数で決まる）。
///
/// 鍵を足すときは **optional で足す**（鍵の無い旧データを読めなくしない。15 パズルの `hintsUsed` と同じ作法）。
public struct DiceComboSnapshot: Codable, Equatable, Sendable {
    /// いまの出目。このターンでまだ振っていなければ空。
    public var dice: [Int]
    /// 各サイコロをキープしているか（`dice` と同じ並び。まだ振っていなければ空）。
    public var held: [Bool]
    /// このターンに振った回数（0〜3）。
    public var rollsUsed: Int
    /// 埋めた役の点。鍵は `DiceComboCategory.rawValue`（英字）。
    public var scores: [String: Int]
    /// このターンに広告で振った回数（#3257）。旧データには無い（nil は 0 として読む）。
    public var adRollsUsed: Int?
    /// この局でコンティニュー（広告での 1 役やり直し）を使ったか（#3257）。旧データには無い（nil は未使用）。
    public var continueUsed: Bool?

    private enum CodingKeys: String, CodingKey {
        case dice, held, rollsUsed, scores, adRollsUsed, continueUsed
    }

    /// 従来の鍵は厳格に読み、後から足した鍵だけは型が合わなくても捨てて読む
    /// （広告まわりの値が壊れていても、局そのものは再開できるようにする）。
    /// 以前あった「役選びを戻す」の鍵（`undosRemaining`・`lastChoice`）は読み捨てる。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dice = try container.decode([Int].self, forKey: .dice)
        held = try container.decode([Bool].self, forKey: .held)
        rollsUsed = try container.decode(Int.self, forKey: .rollsUsed)
        scores = try container.decode([String: Int].self, forKey: .scores)
        adRollsUsed = try? container.decodeIfPresent(Int.self, forKey: .adRollsUsed)
        continueUsed = try? container.decodeIfPresent(Bool.self, forKey: .continueUsed)
    }

    public init(dice: [Int], held: [Bool], rollsUsed: Int, scores: [String: Int],
                adRollsUsed: Int? = nil, continueUsed: Bool? = nil) {
        self.dice = dice
        self.held = held
        self.rollsUsed = rollsUsed
        self.scores = scores
        self.adRollsUsed = adRollsUsed
        self.continueUsed = continueUsed
    }

    /// 1 回も振っていない手つかずの局か（ハブの「続きから」に出さない・#1847 / #2161）。
    public var isUntouched: Bool { rollsUsed == 0 && scores.isEmpty }
}
