import Foundation

public enum ChessGamePhase: String, Codable, Sendable { case playing, review }
public enum ChessPlayerKind: String, Codable, Sendable { case human, ai }

/// チェスの中断スナップショット。中断復帰・検討の 2 用途をこの 1 データで賄う。
///
/// **盤そのものは保存せず「開始局面 FEN + UCI の手順」だけを持つ**（将棋の `ShogiSnapshot`
/// と同じ設計）。こうしておくと、キャスリング権・アンパッサン標的・50手計数・
/// 3回同形の判定材料が、復元時に指し手を再生するだけで自動的に揃う。
/// 派生できる状態を別々に保存すると、片方だけ古いという壊れ方を作り込むことになる。
public struct ChessSnapshot: Codable, Equatable, Sendable {
    public var initialFen: String
    public var moves: [String]       // UCI 形式の指し手列
    public var phase: ChessGamePhase
    public var reviewPly: Int?       // 検討で表示中の手数（playing 時は nil = 末尾）
    public var white: ChessPlayerKind
    public var black: ChessPlayerKind
    public var aiLevel: Int?
    public var startedAt: Date
    /// 追加する項目は**必ず Optional**にする（古いスナップショットが読めなくなるため）。
    public var undoUsed: Bool?
    public var resigned: Bool?

    public init(
        initialFen: String,
        moves: [String],
        phase: ChessGamePhase,
        reviewPly: Int?,
        white: ChessPlayerKind,
        black: ChessPlayerKind,
        aiLevel: Int?,
        startedAt: Date,
        undoUsed: Bool,
        resigned: Bool = false
    ) {
        self.initialFen = initialFen
        self.moves = moves
        self.phase = phase
        self.reviewPly = reviewPly
        self.white = white
        self.black = black
        self.aiLevel = aiLevel
        self.startedAt = startedAt
        self.undoUsed = undoUsed
        self.resigned = resigned
    }
}
