import Foundation
import Observation
import Core

/// 将棋の対局状態。盤・指し手列・選択状態・終局・検討を管理する。
/// ルールは `Position` に委譲し、ここは UI 操作と永続化を担う。
@MainActor
@Observable
public final class ShogiGameModel {
    public let initialSFEN: String
    public private(set) var moves: [Move]
    public private(set) var position: Position
    public private(set) var legalMovesCache: [Move]

    // 選択状態
    public private(set) var selectedSquare: Int?
    public private(set) var selectedHand: PieceType?
    /// 成り選択待ち（成・不成の両方が合法な移動）。
    public private(set) var pendingPromotion: (from: Int, to: Int)?

    // 対局設定・進行
    public private(set) var phase: GamePhase
    public private(set) var reviewPly: Int
    public private(set) var gameOver: Bool
    public private(set) var resultText: String?
    public var sente: PlayerKind
    public var gote: PlayerKind
    public var aiLevel: Int

    private let services: GameServices?
    private let gameID = "shogi"
    private var startedAt: Date

    public init(services: GameServices? = nil) {
        self.services = services
        let snap = services?.snapshots.load(ShogiSnapshot.self, for: "shogi")

        let sfen = snap?.initialSfen ?? Position.startSFEN
        var pos = Position.fromSFEN(sfen) ?? Position.start()
        var moveList: [Move] = []
        if let snap {
            for usi in snap.moves {
                guard let m = Move.fromUSI(usi) else { break }
                moveList.append(m)
                pos.make(m)
            }
        }

        self.initialSFEN = sfen
        self.moves = moveList
        self.position = pos
        self.legalMovesCache = pos.legalMoves()
        self.selectedSquare = nil
        self.selectedHand = nil
        self.pendingPromotion = nil
        self.phase = snap?.phase ?? .playing
        self.reviewPly = snap?.reviewPly ?? moveList.count
        // 既定は CPU 対戦（人間=先手 / CPU=後手）。
        self.sente = snap?.sente ?? .human
        self.gote = snap?.gote ?? .ai
        self.aiLevel = snap?.aiLevel ?? 1
        self.startedAt = snap?.startedAt ?? Date()
        self.gameOver = false
        self.resultText = nil

        if legalMovesCache.isEmpty {
            self.gameOver = true
            self.phase = .review
        }
    }

    // MARK: - 表示用

    /// 検討中は reviewPly までの局面、対局中は最新局面を表示する。
    public var displayedPosition: Position {
        if phase == .review {
            return positionAt(ply: reviewPly)
        }
        return position
    }

    /// 強調表示する直前の指し手（対局中は最新手、検討中は表示局面に至った手）。
    public var highlightedMove: Move? {
        let ply = (phase == .review) ? reviewPly : moves.count
        return ply > 0 ? moves[ply - 1] : nil
    }

    /// 直前手の移動元・移動先マス（CPU の手などを色で示す用）。
    public var highlightedSquares: Set<Int> {
        switch highlightedMove {
        case let .board(from, to, _): return [from, to]
        case let .drop(_, to): return [to]
        case nil: return []
        }
    }

    /// 直前手の棋譜表記（例 "▲７六歩"）。無ければ nil。
    public var highlightedMoveText: String? {
        guard let m = highlightedMove else { return nil }
        let ply = (phase == .review) ? reviewPly : moves.count
        let before = positionAt(ply: ply - 1)
        let mover = before.sideToMove == .black ? "▲" : "△"
        return mover + KIF.notation(m, pos: before, prevTo: nil)
    }

    /// 現在の選択から導く合法な着手先マス。
    public var legalTargets: Set<Int> {
        if let from = selectedSquare {
            return Set(legalMovesCache.compactMap {
                if case let .board(f, t, _) = $0, f == from { return t }
                return nil
            })
        } else if let hand = selectedHand {
            return Set(legalMovesCache.compactMap {
                if case let .drop(ty, t) = $0, ty == hand { return t }
                return nil
            })
        }
        return []
    }

    // MARK: - 対局操作

    public func tapSquare(_ sq: Int) {
        // CPU の手番（思考中含む）は人間の操作を受け付けない。
        guard phase == .playing, !gameOver, pendingPromotion == nil, !isAITurn else { return }
        if (selectedSquare != nil || selectedHand != nil), legalTargets.contains(sq) {
            attemptMove(to: sq)
            return
        }
        if let p = position.squares[sq], p.color == position.sideToMove {
            selectedSquare = sq
            selectedHand = nil
        } else {
            clearSelection()
        }
    }

    public func tapHand(_ type: PieceType, color: Side) {
        guard phase == .playing, !gameOver, pendingPromotion == nil, !isAITurn else { return }
        guard color == position.sideToMove,
              position.hands[color.rawValue][type.rawValue] > 0 else { return }
        selectedHand = type
        selectedSquare = nil
    }

    private func attemptMove(to sq: Int) {
        if let from = selectedSquare {
            let candidates = legalMovesCache.filter {
                if case let .board(f, t, _) = $0 { return f == from && t == sq }
                return false
            }
            if candidates.count >= 2 {
                pendingPromotion = (from, sq) // 成・不成を選ばせる
            } else if let m = candidates.first {
                apply(m)
            }
        } else if let hand = selectedHand {
            if let m = legalMovesCache.first(where: { $0 == .drop(type: hand, to: sq) }) {
                apply(m)
            }
        }
    }

    public func resolvePromotion(_ promote: Bool) {
        guard let pp = pendingPromotion else { return }
        pendingPromotion = nil
        apply(.board(from: pp.from, to: pp.to, promote: promote))
    }

    /// 合法手を適用する（AI もここを通る）。
    public func apply(_ move: Move) {
        position.make(move)
        moves.append(move)
        clearSelection()
        legalMovesCache = position.legalMoves()
        reviewPly = moves.count
        if legalMovesCache.isEmpty {
            gameOver = true
            let loser = position.sideToMove
            resultText = (loser == .black ? "先手" : "後手") + "の負け（詰み）"
            phase = .review
        }
        persist()
    }

    public func clearSelection() {
        selectedSquare = nil
        selectedHand = nil
        pendingPromotion = nil
    }

    /// 新規対局（CPU 対戦）。人間が指す側を選ぶ。
    public func newGame(humanSide: Side = .black, aiLevel: Int = 1) {
        position = Position.start()
        moves = []
        legalMovesCache = position.legalMoves()
        phase = .playing
        reviewPly = 0
        gameOver = false
        resultText = nil
        self.sente = humanSide == .black ? .human : .ai
        self.gote = humanSide == .black ? .ai : .human
        self.aiLevel = aiLevel
        startedAt = startedAtFallback()
        clearSelection()
        persist()
    }

    /// 人間が指している側（CPU 戦の表示用）。
    public var humanSide: Side { sente == .human ? .black : .white }

    // MARK: - CPU 着手

    public private(set) var isThinking: Bool = false

    /// AI の手番なら最善手を計算して指す。View から手番変化のたびに呼ぶ。
    public func performAIMoveIfNeeded() async {
        guard isAITurn, !isThinking else { return }
        isThinking = true
        defer { isThinking = false }

        let level = aiLevel
        let sfen = position.toSFEN()
        let usi = await Task.detached(priority: .userInitiated) {
            await SimpleMinimaxEngine(level: level).bestMove(sfen: sfen)
        }.value

        // 計算中に状況が変わっていないか確認してから着手。
        guard isAITurn, let usi, let move = Move.fromUSI(usi),
              legalMovesCache.contains(move) else { return }
        apply(move)
    }

    // MARK: - 検討（終局後に手を戻す／進める）

    public func reviewGoTo(ply: Int) {
        phase = .review
        reviewPly = min(max(ply, 0), moves.count)
        clearSelection()
        persist()
    }

    public func reviewStepBack() { reviewGoTo(ply: reviewPly - 1) }
    public func reviewStepForward() { reviewGoTo(ply: reviewPly + 1) }

    /// 指定手数までの局面を再生して返す。
    public func positionAt(ply: Int) -> Position {
        var pos = Position.fromSFEN(initialSFEN) ?? Position.start()
        for m in moves.prefix(min(ply, moves.count)) {
            pos.make(m)
        }
        return pos
    }

    /// 現在の対局が AI の手番か（手番側プレイヤーが AI）。
    public var isAITurn: Bool {
        guard phase == .playing, !gameOver else { return false }
        return (position.sideToMove == .black ? sente : gote) == .ai
    }

    // MARK: - 永続化

    private func persist() {
        let snap = ShogiSnapshot(
            initialSfen: initialSFEN,
            moves: moves.map(\.usi),
            phase: phase,
            reviewPly: phase == .review ? reviewPly : nil,
            sente: sente,
            gote: gote,
            aiLevel: (sente == .ai || gote == .ai) ? aiLevel : nil,
            startedAt: startedAt
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    public func clearSnapshot() {
        services?.snapshots.clear(for: gameID)
    }

    // Date.now を init 前に使えないため分離。
    private func startedAtFallback() -> Date { Date() }
}
