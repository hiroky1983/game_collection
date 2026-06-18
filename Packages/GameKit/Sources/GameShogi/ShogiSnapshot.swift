import Foundation

public enum GamePhase: String, Codable, Sendable { case playing, review }
public enum PlayerKind: String, Codable, Sendable { case human, ai }

/// 将棋の中断スナップショット。中断復帰・検討・KIF エクスポートの 3 用途をこの 1 データで賄う。
public struct ShogiSnapshot: Codable, Equatable, Sendable {
    public var initialSfen: String   // 開始局面（平手の標準 SFEN）
    public var moves: [String]       // USI 形式の指し手列
    public var phase: GamePhase
    public var reviewPly: Int?       // 検討で表示中の手数（playing 時は nil = 末尾）
    public var sente: PlayerKind
    public var gote: PlayerKind
    public var aiLevel: Int?
    public var startedAt: Date
    public var undoUsed: Bool?

    public init(
        initialSfen: String,
        moves: [String],
        phase: GamePhase,
        reviewPly: Int?,
        sente: PlayerKind,
        gote: PlayerKind,
        aiLevel: Int?,
        startedAt: Date,
        undoUsed: Bool
    ) {
        self.initialSfen = initialSfen
        self.moves = moves
        self.phase = phase
        self.reviewPly = reviewPly
        self.sente = sente
        self.gote = gote
        self.aiLevel = aiLevel
        self.startedAt = startedAt
        self.undoUsed = undoUsed
    }
}
