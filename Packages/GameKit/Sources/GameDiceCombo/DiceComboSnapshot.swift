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
    /// 「役選びを戻す」の残り回数（#2940）。旧データには無い（nil は無料枠として読む）。
    public var undosRemaining: Int?
    /// 直前の役選び（戻す用）。旧データ・戻せない局面には無い。
    public var lastChoice: Choice?

    /// 戻すために控える、役を選ぶ前の局面。
    public struct Choice: Codable, Equatable, Sendable {
        /// 選んだ役（`DiceComboCategory.rawValue`）。
        public var category: String
        public var dice: [Int]
        public var held: [Bool]
        public var rollsUsed: Int

        public init(category: String, dice: [Int], held: [Bool], rollsUsed: Int) {
            self.category = category
            self.dice = dice
            self.held = held
            self.rollsUsed = rollsUsed
        }
    }

    private enum CodingKeys: String, CodingKey {
        case dice, held, rollsUsed, scores, undosRemaining, lastChoice
    }

    /// 従来の鍵は厳格に読み、後から足した「戻す」の鍵だけは型が合わなくても捨てて読む
    /// （戻す用の値が壊れていても、局そのものは再開できるようにする）。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dice = try container.decode([Int].self, forKey: .dice)
        held = try container.decode([Bool].self, forKey: .held)
        rollsUsed = try container.decode(Int.self, forKey: .rollsUsed)
        scores = try container.decode([String: Int].self, forKey: .scores)
        undosRemaining = try? container.decodeIfPresent(Int.self, forKey: .undosRemaining)
        lastChoice = try? container.decodeIfPresent(Choice.self, forKey: .lastChoice)
    }

    public init(dice: [Int], held: [Bool], rollsUsed: Int, scores: [String: Int],
                undosRemaining: Int? = nil, lastChoice: Choice? = nil) {
        self.dice = dice
        self.held = held
        self.rollsUsed = rollsUsed
        self.scores = scores
        self.undosRemaining = undosRemaining
        self.lastChoice = lastChoice
    }

    /// 1 回も振っていない手つかずの局か（ハブの「続きから」に出さない・#1847 / #2161）。
    public var isUntouched: Bool { rollsUsed == 0 && scores.isEmpty }
}
