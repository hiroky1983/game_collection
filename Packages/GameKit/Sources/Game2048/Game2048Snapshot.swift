/// 2048 の中断スナップショット。盤面そのものを保存するため乱数シードの再現は不要。
/// ベストスコアは持たない（仕様）。
public struct Game2048Snapshot: Codable, Equatable, Sendable {
    public var board: [[Int]]
    public var score: Int
    /// コンティニュー（広告視聴による復活）を使い切っているか。
    /// これを保存しないと、コンティニュー後にアプリを再起動するだけで同じプレイを
    /// 何度でも復活できてしまう（#122 の PR #134 で CodeRabbit が指摘）。
    public var continueUsed: Bool

    public init(board: [[Int]], score: Int, continueUsed: Bool = false) {
        self.board = board
        self.score = score
        self.continueUsed = continueUsed
    }

    /// `continueUsed` は後から足したキー。既存プレイヤーの中断データにはこのキーが無く、
    /// 合成された `init(from:)` だと復号に失敗して中断中のゲームを失わせてしまうため、
    /// 欠けていたら「まだ使っていない」として読む。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        board = try container.decode([[Int]].self, forKey: .board)
        score = try container.decode(Int.self, forKey: .score)
        continueUsed = try container.decodeIfPresent(Bool.self, forKey: .continueUsed) ?? false
    }
}
