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

    public init(dice: [Int], held: [Bool], rollsUsed: Int, scores: [String: Int]) {
        self.dice = dice
        self.held = held
        self.rollsUsed = rollsUsed
        self.scores = scores
    }

    /// 1 回も振っていない手つかずの局か（ハブの「続きから」に出さない・#1847 / #2161）。
    public var isUntouched: Bool { rollsUsed == 0 && scores.isEmpty }
}
