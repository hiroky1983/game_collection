import Foundation

/// ブロック崩しの中断スナップショット（#463）。
///
/// **フレーム単位の保存はしない**（アクション枠の基盤規約）。球の位置・速度・崩しかけの
/// ブロックまで保存すると、保存の粒度がフレームに縛られてファイルが毎フレーム書き換わるうえ、
/// 「再開した瞬間に球が目の前にある」という理不尽な復帰になる。
/// 保存するのは**ステージ開始時点の状態だけ**で、「続きから」はそのステージの頭から始まる。
public struct BlocksSnapshot: Codable, Equatable, Sendable {
    /// 再開するステージ番号（1 始まり）。
    public var stage: Int
    /// そのステージを始めた時点の累計スコア。
    public var score: Int
    /// そのステージを始めた時点の残機。
    public var lives: Int
    /// コンティニュー（リワード広告）を使い切っているか。
    ///
    /// 再起動でコンティニュー権が復活しないよう保存する（2048 の `continueUsed` と同じ理由）。
    public var continueUsed: Bool

    public init(stage: Int, score: Int, lives: Int, continueUsed: Bool) {
        self.stage = stage
        self.score = score
        self.lives = lives
        self.continueUsed = continueUsed
    }
}
