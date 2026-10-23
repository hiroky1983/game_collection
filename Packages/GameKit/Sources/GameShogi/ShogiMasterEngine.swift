import Foundation
import CoreEngine

/// 達人（#2698）。「むずかしい」（`SimpleMinimaxEngine` の .hard）より強い段。
///
/// 既存の 4 段とは別の探索で、盤の持ち方から作り直してある（`Position` は駒ごとに `Piece?` を持つ配列で、
/// 1 局面ごとに確保と Zobrist の全計算が走り、読める局面数が 1 秒あたり数万に留まるため）。
/// 技法はやねうら王などの αβ 系の将棋ソフトで一般的なものを、考え方だけ参考にして自前で実装した
/// （ソースコード・評価関数のファイルは一切持ち込んでいない。GPLv3 のため）:
///
/// - 番兵つきの 1 次元盤（13 段 × 11 筋）、差分更新の Zobrist ハッシュ
/// - 反復深化 ＋ アスピレーション窓、PVS（主要変化の探索）
/// - 置換表（手・値・深さ・種別）
/// - 静止探索（取る手・成る手）、王手の延長
/// - 手の並べ替え（置換表の手 → 駒得の取り → キラー → 履歴）
/// - LMR（後ろの手の読みを浅くする）、Futility 枝刈り
/// - 評価: 駒の価値 ＋ 位置 ＋ 玉の周りの守り駒・攻め駒 ＋ 玉の周り 8 マスの利きと相手の持ち駒による危なさ
///
/// Null Move 枝刈りと 1 手詰めの検出も実装したが、外した方が強かった（自己対局で外した側が 67.5%）ので
/// 出荷では切ってある（`ShogiMasterOptions`）。各技法の効果は `docs/analytics/shogi-2698-master.md` と issue #2698。
/// UI にはまだ出さない（v1.1.15 で出す）。
public struct ShogiMasterEngine: ShogiEngine {
    /// 段の番号（`aiLevel`）。`CPUStrength` が見送った「ガチ」の 3 を将棋だけで使う。`CPUStrength` には足さないので、
    /// 開始シートの段の並び（`CPUStrength.allCases`）には出ない（UI に出すのは v1.1.15）。
    public static let level = 3

    /// 段の番号に対応するエンジン。達人の番号だけこちら、ほかは今の `SimpleMinimaxEngine`（設定は変えない）。
    public static func engine(level: Int) -> any ShogiEngine {
        level == Self.level ? ShogiMasterEngine() : SimpleMinimaxEngine(level: level)
    }

    /// 1 手の考える時間の上限（秒・実時間）。禁止事項「1 手 3 秒を超えない」に余裕を残した値。
    public static let shippedTimeLimit: TimeInterval = 2.5

    let timeLimit: TimeInterval
    /// 読む局面数の上限（計測用。`nil` なら無し）。
    let nodeLimit: Int?
    let options: ShogiMasterOptions

    public init() {
        self.init(timeLimit: Self.shippedTimeLimit)
    }

    init(timeLimit: TimeInterval, nodeLimit: Int? = nil, options: ShogiMasterOptions = .shipped) {
        self.timeLimit = timeLimit
        self.nodeLimit = nodeLimit
        self.options = options
    }

    public func bestMove(sfen: String) async -> String? {
        analyze(sfen: sfen)?.usi
    }

    /// 計測用: 手と、読んだ局面数・読み切った深さ・評価値（手番側から見た値）を返す。
    func analyze(sfen: String) -> (usi: String?, nodes: Int, depth: Int, score: Int)? {
        let startedAt = Date()
        guard let pos = Position.fromSFEN(sfen) else { return nil }
        let legal = pos.legalMoves()
        guard !legal.isEmpty else { return nil }
        if legal.count == 1 { return (legal[0].usi, 0, 0, 0) }
        let searcher = MasterSearcher(pos, options: options)
        defer { searcher.release() }
        let deadline = timeLimit.isFinite
            ? startedAt.addingTimeInterval(timeLimit - Self.overhead) : Date.distantFuture
        let r = searcher.think(deadline: deadline, startedAt: startedAt, timeLimit: timeLimit, nodeLimit: nodeLimit)
        // 自前の手生成が万一食い違っても、非合法手は指さない（既存の合法手生成で必ず確かめる）。
        if let usi = r.usi, let m = Move.fromUSI(usi), legal.contains(m) {
            return (usi, r.nodes, r.depth, r.score)
        }
        return (legal[0].usi, r.nodes, r.depth, r.score)
    }

    /// 時間の上限から引く後始末ぶん（秒）。合法手の確かめと返り値の受け渡しに使う。
    static let overhead: TimeInterval = 0.05
}

/// 達人の探索の切り替え（技法ごとの効果を計測するための口。出荷値は `shipped`）。
struct ShogiMasterOptions: Sendable, Equatable {
    var aspiration = true
    var pvs = true
    /// 外した方が強かった（自己対局 20 局で外した側が 75%）。
    var nullMove = false
    var lmr = true
    var futility = true
    var checkExtension = true
    /// 外した方が強かった（自己対局 20 局で外した側が 65%。1 局面ごとに全部の手を作るので読める局面数が半分になる）。
    var mateInOne = false
    var kingSafety = true
    /// 玉の周り 8 マスの利きの数（攻め・守り）と相手の持ち駒から、玉の危なさを見る（自己対局で入れた側が 82.5%）。
    var kingAttackMap = true
    /// 安い駒を高い駒で取り、取り返される取り（損な取り）を、静止探索では読まず、本探索ではキラーより後に回す。
    var badCaptures = false
    /// `kingAttackMap` の強さ（危なさの 2 乗にかける重み）。
    var kingAttackWeight = 3
    /// 置換表の大きさ（エントリ数の 2 の冪の指数）。
    var ttBits = 20

    static let shipped = ShogiMasterOptions()
}

// MARK: - 盤の表現

/// 駒の符号: 0 = 空、1...14 = 先手の駒（下表）、17...30 = 後手の駒（+16）、64 = 盤外（番兵）。
/// 種類: 1 歩, 2 香, 3 桂, 4 銀, 5 金, 6 角, 7 飛, 8 玉, 9 と, 10 成香, 11 成桂, 12 成銀, 13 馬, 14 龍。
private enum MP {
    static let empty: Int = 0
    static let wall: Int = 64
    static let pawn = 1, lance = 2, knight = 3, silver = 4, gold = 5, bishop = 6, rook = 7, king = 8
    static let horse = 13, dragon = 14

    /// 盤は 13 段 × 11 筋（上下 2 段・左右 1 筋の番兵）。
    static let width = 11
    static let size = 143

    @inline(__always) static func sq(file: Int, rank: Int) -> Int { (rank + 2) * width + file + 1 }
    @inline(__always) static func rank(_ s: Int) -> Int { s / width - 2 }
    @inline(__always) static func file(_ s: Int) -> Int { s % width - 1 }

    /// 先手から見た方向（前 = 段が小さくなる = -11）。0...7 が 8 方向、8...11 が桂の跳び。
    static let dirs: [Int] = [-11, -10, -12, 1, -1, 11, 12, 10, -21, -23, 21, 23]

    @inline(__always) static func color(_ code: Int) -> Int { code >> 4 }   // 1...30 のみ有効
    @inline(__always) static func type(_ code: Int) -> Int { code & 15 }
    @inline(__always) static func isPiece(_ code: Int) -> Bool { code != 0 && code < wall }

    /// 成ったときの種類（成れない駒は 0）。
    static let promoteOf: [Int] = [0, 9, 10, 11, 12, 0, 13, 14, 0, 0, 0, 0, 0, 0, 0, 0]
    /// 持ち駒になるときの種類（成りを外す）。
    static let unpromoteOf: [Int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 6, 7, 0]

    /// 駒の価値（盤上）。
    static let value: [Int] = [0, 90, 315, 405, 495, 540, 855, 990, 15000, 540, 540, 540, 540, 945, 1395, 0]
    /// 持ち駒の価値（盤上より少し高い。打てる自由がある）。
    static let handValue: [Int] = [0, 105, 345, 445, 550, 600, 900, 1060, 0]
    /// 取ったときの得（相手の駒が消え、自分の持ち駒が増える）。
    static func captureGain(_ t: Int) -> Int { value[t] + handValue[unpromoteOf[t]] }

    /// stepMask[code] の i ビット = その駒が dirs[i] へ 1 歩動ける。slideMask は 0...7 の方向へ走れる。
    static let tables: (step: [UInt16], slide: [UInt8]) = {
        var step = [UInt16](repeating: 0, count: 128)
        var slide = [UInt8](repeating: 0, count: 128)
        // 先手の向きでの方向番号: 0 前, 1・2 斜め前, 3・4 横, 5 後, 6・7 斜め後, 8・9 桂の跳び
        let front = [0, 1, 2], sideways = [3, 4], back = [5], backDiag = [6, 7]
        let goldDirs = front + sideways + back
        let silverDirs = front + backDiag
        let kingDirs = front + sideways + back + backDiag
        let diag = [1, 2, 6, 7], orth = [0, 3, 4, 5]
        func steps(_ t: Int) -> [Int] {
            switch t {
            case pawn: return [0]
            case knight: return [8, 9]
            case silver: return silverDirs
            case gold, 9, 10, 11, 12: return goldDirs
            case king: return kingDirs
            case horse: return orth
            case dragon: return diag
            default: return []
            }
        }
        func slides(_ t: Int) -> [Int] {
            switch t {
            case lance: return [0]
            case bishop, horse: return diag
            case rook, dragon: return orth
            default: return []
            }
        }
        // 後手は方向を 180 度回す（dirs の相手側の番号）。
        let flip = [5, 7, 6, 4, 3, 0, 2, 1, 10, 11, 8, 9]
        for t in 1...14 {
            for i in steps(t) { step[t] |= 1 << i; step[t + 16] |= 1 << flip[i] }
            for i in slides(t) { slide[t] |= 1 << i; slide[t + 16] |= 1 << flip[i] }
        }
        return (step, slide)
    }()

    static let zobrist: (piece: [UInt64], hand: [UInt64], side: UInt64) = {
        var rng = SplitMix64(seed: 0x2698_5A5A_C0FF_EE01)
        var piece = [UInt64](repeating: 0, count: 32 * size)
        for i in 0..<piece.count { piece[i] = rng.next() }
        var hand = [UInt64](repeating: 0, count: 2 * 8)
        for i in 0..<hand.count { hand[i] = rng.next() }
        return (piece, hand, rng.next() | 1)
    }()
}

/// 指し手の符号（UInt32）: bit 0-7 = 行き先、bit 8-15 = 元のマス（打ちは駒の種類）、bit 16 = 成り、bit 17 = 打ち。
private enum MM {
    @inline(__always) static func board(_ from: Int, _ to: Int, promote: Bool) -> UInt32 {
        UInt32(to) | UInt32(from) << 8 | (promote ? 1 << 16 : 0)
    }
    @inline(__always) static func drop(_ type: Int, _ to: Int) -> UInt32 { UInt32(to) | UInt32(type) << 8 | 1 << 17 }
    @inline(__always) static func to(_ m: UInt32) -> Int { Int(m & 0xFF) }
    @inline(__always) static func from(_ m: UInt32) -> Int { Int((m >> 8) & 0xFF) }
    @inline(__always) static func isPromote(_ m: UInt32) -> Bool { m & (1 << 16) != 0 }
    @inline(__always) static func isDrop(_ m: UInt32) -> Bool { m & (1 << 17) != 0 }
    static let none: UInt32 = 0
}

// MARK: - 探索本体

private struct TTSlot {
    var key: UInt64 = 0
    var move: UInt32 = 0
    var score: Int16 = 0
    var depth: Int8 = -1
    var flag: UInt8 = 0   // 1 = 下界, 2 = 上界, 3 = 正確
}

private let mateScore = 30000
private let mateBound = 29000
private let infinity = 32000
private let maxPly = 96

/// 1 回の思考の状態。速さのため生のバッファを持つ（`release()` で解放する）。
private final class MasterSearcher {
    let options: ShogiMasterOptions
    let board: UnsafeMutablePointer<Int>
    /// hands[color * 8 + type]
    let hands: UnsafeMutablePointer<Int>
    var kingSq = [0, 0]
    var side = 0
    var hash: UInt64 = 0
    var ply = 0

    // 手の置き場（深さごとに区切って使う）
    static let movesPerPly = 1024
    let moveBuf: UnsafeMutablePointer<UInt32>
    let scoreBuf: UnsafeMutablePointer<Int32>

    // 巻き戻し
    let undoCaptured: UnsafeMutablePointer<Int>
    let undoHash: UnsafeMutablePointer<UInt64>
    let undoMove: UnsafeMutablePointer<UInt32>
    /// 探索の経路上の局面（千日手の検出）。
    let pathHash: UnsafeMutablePointer<UInt64>

    let tt: UnsafeMutablePointer<TTSlot>
    let ttMask: Int
    let killers: UnsafeMutablePointer<UInt32>   // [ply * 2 + i]
    let history: UnsafeMutablePointer<Int32>    // [side * 2 * 256 * 256 ...] を簡略: (from or 128+type) * 256 + to
    static let historySize = 2 * 256 * 256

    let stepMask: [UInt16]
    let slideMask: [UInt8]
    let dirs: [Int]
    let zPiece: [UInt64]
    let zHand: [UInt64]
    let zSide: UInt64

    var nodes = 0
    var nodeLimit = Int.max
    var deadline = Date.distantFuture
    var stopped = false

    init(_ pos: Position, options: ShogiMasterOptions) {
        self.options = options
        board = .allocate(capacity: MP.size)
        board.initialize(repeating: MP.wall, count: MP.size)
        hands = .allocate(capacity: 16)
        hands.initialize(repeating: 0, count: 16)
        moveBuf = .allocate(capacity: Self.movesPerPly * (maxPly + 8))
        scoreBuf = .allocate(capacity: Self.movesPerPly * (maxPly + 8))
        undoCaptured = .allocate(capacity: maxPly + 8)
        undoHash = .allocate(capacity: maxPly + 8)
        undoMove = .allocate(capacity: maxPly + 8)
        pathHash = .allocate(capacity: maxPly + 8)
        ttMask = (1 << options.ttBits) - 1
        tt = .allocate(capacity: 1 << options.ttBits)
        tt.initialize(repeating: TTSlot(), count: 1 << options.ttBits)
        killers = .allocate(capacity: (maxPly + 8) * 2)
        killers.initialize(repeating: 0, count: (maxPly + 8) * 2)
        history = .allocate(capacity: Self.historySize)
        history.initialize(repeating: 0, count: Self.historySize)
        stepMask = MP.tables.step
        slideMask = MP.tables.slide
        dirs = MP.dirs
        zPiece = MP.zobrist.piece
        zHand = MP.zobrist.hand
        zSide = MP.zobrist.side

        for i in 0..<81 {
            guard let p = pos.squares[i] else { continue }
            let s = MP.sq(file: Sq.file(i), rank: Sq.rank(i))
            var t = p.type.rawValue + 1
            if p.promoted { t = MP.promoteOf[t] }
            let code = t | (p.color.rawValue << 4)
            board[s] = code
            if t == MP.king { kingSq[p.color.rawValue] = s }
            hash ^= zPiece[code * MP.size + s]
        }
        for c in 0..<2 {
            for t in 0..<7 {
                let n = pos.hands[c][t]
                hands[c * 8 + t + 1] = n
                hash &+= zHand[c * 8 + t + 1] &* UInt64(n)
            }
        }
        side = pos.sideToMove.rawValue
        if side == 1 { hash ^= zSide }
        for s in 0..<MP.size where MP.rank(s) < 0 || MP.rank(s) > 8 || MP.file(s) < 0 || MP.file(s) > 8 {
            board[s] = MP.wall
        }
        for r in 0..<9 { for f in 0..<9 where board[MP.sq(file: f, rank: r)] == MP.wall {
            board[MP.sq(file: f, rank: r)] = MP.empty
        }}
    }

    func release() {
        board.deallocate(); hands.deallocate(); moveBuf.deallocate(); scoreBuf.deallocate()
        undoCaptured.deallocate(); undoHash.deallocate(); undoMove.deallocate(); pathHash.deallocate()
        tt.deallocate(); killers.deallocate(); history.deallocate()
    }

    // MARK: 利き

    /// マス t に color の駒が利いているか。
    @inline(__always) func isAttacked(_ t: Int, by color: Int) -> Bool {
        for i in 0..<12 {
            let p = board[t - dirs[i]]
            if MP.isPiece(p) && MP.color(p) == color && stepMask[p] & (1 << i) != 0 { return true }
        }
        for i in 0..<8 {
            let d = dirs[i]
            var s = t - d
            while board[s] == MP.empty { s -= d }
            let p = board[s]
            if MP.isPiece(p) && MP.color(p) == color && slideMask[p] & (1 << i) != 0 { return true }
        }
        return false
    }

    /// マス t に color の駒が利いている数（3 で打ち切る）。
    @inline(__always) func attackCount(_ t: Int, by color: Int) -> Int {
        var n = 0
        for i in 0..<12 {
            let p = board[t - dirs[i]]
            if MP.isPiece(p) && MP.color(p) == color && stepMask[p] & (1 << i) != 0 { n += 1 }
        }
        for i in 0..<8 {
            let d = dirs[i]
            var s = t - d
            while board[s] == MP.empty { s -= d }
            let p = board[s]
            if MP.isPiece(p) && MP.color(p) == color && slideMask[p] & (1 << i) != 0 { n += 1 }
            if n >= 3 { return 3 }
        }
        return min(n, 3)
    }

    /// color の玉の危なさ（大きいほど危ない）。玉の周り 8 マスについて、相手の利きが自分の利き（玉を除く）を
    /// 上回るマスを重く、相手が利かせているだけのマスを軽く数え、空いたマスは相手に持ち駒があれば打ち込みの的として数える。
    func kingDangerMap(_ color: Int) -> Int {
        let k = kingSq[color], opp = color ^ 1
        var danger = 0
        var oppHand = 0
        for t in 1...7 { oppHand += hands[opp * 8 + t] * (t >= MP.silver ? 2 : 1) }
        for i in 0..<8 {
            let s = k + dirs[i]
            let occ = board[s]
            if occ == MP.wall { continue }
            let a = attackCount(s, by: opp)
            if a > 0 {
                let d = attackCount(s, by: color) - 1   // 玉自身の利きを除く
                danger += a > d ? 2 + a : 1
            } else if occ == MP.empty && oppHand > 0 {
                danger += 1
            }
        }
        if isAttacked(k, by: opp) { danger += 2 }
        return danger * danger * options.kingAttackWeight + danger * min(oppHand, 12) * 3
    }

    @inline(__always) func inCheck() -> Bool { isAttacked(kingSq[side], by: side ^ 1) }

    // MARK: 手の生成（疑似合法。王手放置は make のあとで弾く）

    @inline(__always) func inZone(_ s: Int, _ c: Int) -> Bool {
        let r = MP.rank(s)
        return c == 0 ? r <= 2 : r >= 6
    }

    /// 行き所の無い段（不成で動けない・打てない）か。
    @inline(__always) func deadRank(_ t: Int, _ s: Int, _ c: Int) -> Bool {
        let r = c == 0 ? MP.rank(s) : 8 - MP.rank(s)
        switch t {
        case MP.pawn, MP.lance: return r == 0
        case MP.knight: return r <= 1
        default: return false
        }
    }

    @inline(__always) func addBoardMove(_ code: Int, _ from: Int, _ to: Int, _ buf: UnsafeMutablePointer<UInt32>,
                                        _ n: inout Int, capturesOnly: Bool) {
        let t = MP.type(code)
        let c = MP.color(code)
        let target = board[to]
        let promotable = MP.promoteOf[t] != 0 && (inZone(from, c) || inZone(to, c))
        if capturesOnly {
            // 静止探索: 取る手と、歩・角・飛の成り（駒得に直結する）。
            if target == MP.empty && !(promotable && (t == MP.pawn || t == MP.bishop || t == MP.rook)) { return }
        }
        if promotable {
            buf[n] = MM.board(from, to, promote: true); n += 1
            // 歩・角・飛の不成は損しかない（打ち歩詰めの抜け道も無い）ので生成しない。
            if t == MP.pawn || t == MP.bishop || t == MP.rook { return }
            if deadRank(t, to, c) { return }
            if capturesOnly && target == MP.empty { return }
            buf[n] = MM.board(from, to, promote: false); n += 1
        } else {
            buf[n] = MM.board(from, to, promote: false); n += 1
        }
    }

    func generate(_ buf: UnsafeMutablePointer<UInt32>, capturesOnly: Bool) -> Int {
        var n = 0
        let us = side
        for r in 0..<9 {
            for f in 0..<9 {
                let from = (r + 2) * 11 + f + 1
                let code = board[from]
                guard MP.isPiece(code), MP.color(code) == us else { continue }
                let sm = stepMask[code]
                if sm != 0 {
                    for i in 0..<12 where sm & (1 << i) != 0 {
                        let to = from + dirs[i]
                        let target = board[to]
                        if target == MP.wall || (target != MP.empty && MP.color(target) == us) { continue }
                        addBoardMove(code, from, to, buf, &n, capturesOnly: capturesOnly)
                    }
                }
                let lm = slideMask[code]
                if lm != 0 {
                    for i in 0..<8 where lm & (1 << i) != 0 {
                        let d = dirs[i]
                        var to = from + d
                        while true {
                            let target = board[to]
                            if target == MP.wall { break }
                            if target != MP.empty {
                                if MP.color(target) != us { addBoardMove(code, from, to, buf, &n, capturesOnly: capturesOnly) }
                                break
                            }
                            addBoardMove(code, from, to, buf, &n, capturesOnly: capturesOnly)
                            to += d
                        }
                    }
                }
            }
        }
        if capturesOnly { return n }

        // 打つ手
        let hb = us * 8
        var types: [Int] = []
        types.reserveCapacity(7)
        for t in 1...7 where hands[hb + t] > 0 { types.append(t) }
        if types.isEmpty { return n }
        var pawnFile = [Bool](repeating: false, count: 9)
        if hands[hb + MP.pawn] > 0 {
            let myPawn = MP.pawn | (us << 4)
            for r in 0..<9 { for f in 0..<9 where board[(r + 2) * 11 + f + 1] == myPawn { pawnFile[f] = true } }
        }
        for r in 0..<9 {
            let rr = us == 0 ? r : 8 - r
            for f in 0..<9 {
                let to = (r + 2) * 11 + f + 1
                guard board[to] == MP.empty else { continue }
                for t in types {
                    switch t {
                    case MP.pawn: if rr == 0 || pawnFile[f] { continue }
                    case MP.lance: if rr == 0 { continue }
                    case MP.knight: if rr <= 1 { continue }
                    default: break
                    }
                    buf[n] = MM.drop(t, to); n += 1
                }
            }
        }
        return n
    }

    // MARK: make / unmake

    @inline(__always) func make(_ m: UInt32) {
        let to = MM.to(m)
        undoMove[ply] = m
        undoHash[ply] = hash
        pathHash[ply] = hash
        let us = side
        if MM.isDrop(m) {
            let t = MM.from(m)
            let code = t | (us << 4)
            hands[us * 8 + t] -= 1
            hash &-= zHand[us * 8 + t]
            board[to] = code
            hash ^= zPiece[code * MP.size + to]
            undoCaptured[ply] = MP.empty
        } else {
            let from = MM.from(m)
            var code = board[from]
            let cap = board[to]
            undoCaptured[ply] = cap
            if cap != MP.empty {
                let ht = MP.unpromoteOf[MP.type(cap)]
                hands[us * 8 + ht] += 1
                hash &+= zHand[us * 8 + ht]
                hash ^= zPiece[cap * MP.size + to]
            }
            hash ^= zPiece[code * MP.size + from]
            board[from] = MP.empty
            if MM.isPromote(m) { code = MP.promoteOf[MP.type(code)] | (us << 4) }
            board[to] = code
            hash ^= zPiece[code * MP.size + to]
            if MP.type(code) == MP.king { kingSq[us] = to }
        }
        side ^= 1
        hash ^= zSide
        ply += 1
    }

    @inline(__always) func unmake() {
        ply -= 1
        side ^= 1
        let m = undoMove[ply]
        hash = undoHash[ply]
        let us = side
        let to = MM.to(m)
        if MM.isDrop(m) {
            let t = MM.from(m)
            hands[us * 8 + t] += 1
            board[to] = MP.empty
        } else {
            let from = MM.from(m)
            var code = board[to]
            if MM.isPromote(m) { code = MP.unpromoteOf[MP.type(code)] | (us << 4) }
            board[from] = code
            let cap = undoCaptured[ply]
            board[to] = cap
            if cap != MP.empty { hands[us * 8 + MP.unpromoteOf[MP.type(cap)]] -= 1 }
            if MP.type(code) == MP.king { kingSq[us] = from }
        }
    }

    func makeNull() {
        undoHash[ply] = hash
        pathHash[ply] = hash
        undoMove[ply] = MM.none
        side ^= 1
        hash ^= zSide
        ply += 1
    }

    func unmakeNull() {
        ply -= 1
        side ^= 1
        hash = undoHash[ply]
    }

    /// 直前の手を指した側の玉が取られない（王手放置でない）か。打ち歩詰めもここで弾く。
    @inline(__always) func lastMoveIsLegal() -> Bool {
        let mover = side ^ 1
        if isAttacked(kingSq[mover], by: side) { return false }
        let m = undoMove[ply - 1]
        if MM.isDrop(m) && MM.from(m) == MP.pawn {
            let to = MM.to(m)
            let ahead = mover == 0 ? to - 11 : to + 11
            if board[ahead] == (MP.king | (side << 4)) && !hasLegalMove() { return false }
        }
        return true
    }

    /// 手番側に合法手が 1 つでもあるか（打ち歩詰めの判定・詰みの判定）。
    func hasLegalMove() -> Bool {
        let buf = moveBuf + Self.movesPerPly * min(ply + 1, maxPly + 7)
        let n = generate(buf, capturesOnly: false)
        for i in 0..<n {
            make(buf[i])
            // 打ち歩詰めの判定の中で、さらに打ち歩詰めを判定しない（王手放置だけ見る）。
            let ok = !isAttacked(kingSq[side ^ 1], by: side)
            unmake()
            if ok { return true }
        }
        return false
    }

    /// 手 m を指すと相手に王手がかかるか（指す前の局面で判定）。
    func givesCheck(_ m: UInt32) -> Bool {
        make(m)
        let r = isAttacked(kingSq[side], by: side ^ 1)
        unmake()
        return r
    }

    // MARK: 評価

    /// 玉からの相対位置ごとの重み（距離が近いほど大きい）。
    @inline(__always) func proximity(_ s: Int, _ k: Int) -> Int {
        let df = abs(MP.file(s) - MP.file(k)), dr = abs(MP.rank(s) - MP.rank(k))
        let d = max(df, dr)
        switch d {
        case 1: return 4
        case 2: return 2
        case 3: return 1
        default: return 0
        }
    }

    @inline(__always) func kingPressure(_ attack: Int, _ defend: Int) -> Int {
        let pressure = max(0, attack - defend / 2)
        return pressure * pressure / 40 + attack / 2
    }

    /// 種類ごと・自陣からの段（0 = 自陣の奥）ごとの位置の加点。
    let advanceBonus: [Int] = {
        var t = [Int](repeating: 0, count: 16 * 9)
        func set(_ type: Int, _ v: [Int]) { for i in 0..<9 { t[type * 9 + i] = v[i] } }
        set(MP.pawn, [0, 0, 0, 6, 10, 16, 24, 30, 0])
        for g in [MP.silver, MP.gold, 9, 10, 11, 12] { set(g, [0, 4, 6, 8, 10, 12, 14, 14, 10]) }
        set(MP.knight, [0, 0, 6, 12, 18, 20, 0, 0, 0])
        // 玉は自陣の奥がよい（中段玉・入玉の評価は考えない）。
        set(MP.king, [30, 20, 0, -30, -60, -80, -90, -100, -100])
        return t
    }()
    /// 自玉の近くにいるときの守りの重み・相手玉の近くにいるときの攻めの重み（種類ごと）。
    let defendWeight: [Int] = [0, 2, 2, 2, 7, 7, 0, 0, 0, 7, 7, 7, 7, 8, 0, 0]
    let attackWeight: [Int] = [0, 2, 4, 4, 5, 5, 4, 9, 0, 5, 5, 5, 5, 8, 9, 0]

    /// 手番側から見た評価値。
    func evaluate() -> Int {
        var score = 0
        let bk = kingSq[0], wk = kingSq[1]
        let useKing = options.kingSafety
        // attack[c] = c の駒が相手玉に迫っている度合い、defend[c] = c の玉の周りの守り
        var attack0 = 0, attack1 = 0, defend0 = 0, defend1 = 0
        for r in 0..<9 {
            for f in 0..<9 {
                let s = (r + 2) * 11 + f + 1
                let code = board[s]
                guard code != MP.empty else { continue }
                let t = MP.type(code), c = MP.color(code)
                let sign = c == 0 ? 1 : -1
                var v = MP.value[t]
                let adv = c == 0 ? 8 - r : r   // 0 = 自陣の奥
                v += advanceBonus[t * 9 + adv]
                if useKing && t != MP.king {
                    let ownK = c == 0 ? bk : wk
                    let oppK = c == 0 ? wk : bk
                    let d = proximity(s, ownK) * defendWeight[t]
                    let a = proximity(s, oppK) * attackWeight[t]
                    if c == 0 { defend0 += d; attack0 += a } else { defend1 += d; attack1 += a }
                }
                score += sign * v
            }
        }
        for c in 0..<2 {
            let sign = c == 0 ? 1 : -1
            var handAttack = 0
            for t in 1...7 {
                let n = hands[c * 8 + t]
                if n == 0 { continue }
                score += sign * MP.handValue[t] * n
                switch t {
                case MP.rook, MP.bishop: handAttack += 14 * n
                case MP.gold, MP.silver: handAttack += 9 * n
                case MP.knight, MP.lance: handAttack += 5 * n
                default: handAttack += min(n, 3) * 2
                }
            }
            if c == 0 { attack0 += handAttack } else { attack1 += handAttack }
        }
        if useKing {
            // 迫る駒が守り駒を上回るほど、その差を大きく見る（攻めは数がそろって初めて効く）。
            score += kingPressure(attack0, defend1) - kingPressure(attack1, defend0)
        }
        if options.kingAttackMap {
            score += kingDangerMap(1) - kingDangerMap(0)
        }
        return side == 0 ? score : -score
    }

    // MARK: 並べ替え

    @inline(__always) func historyIndex(_ m: UInt32) -> Int {
        let a = MM.isDrop(m) ? 128 + MM.from(m) : MM.from(m)
        return (side * 256 + a) * 256 + MM.to(m)
    }

    /// 手に点を付ける。置換表の手 > 駒得の取り（MVV-LVA）> 成り > キラー > 履歴。
    func scoreMoves(_ buf: UnsafeMutablePointer<UInt32>, _ scores: UnsafeMutablePointer<Int32>, _ n: Int,
                    ttMove: UInt32) {
        let k0 = killers[ply * 2], k1 = killers[ply * 2 + 1]
        for i in 0..<n {
            let m = buf[i]
            var s: Int
            if m == ttMove {
                s = 1_000_000_000
            } else if !MM.isDrop(m), board[MM.to(m)] != MP.empty {
                let victim = MP.type(board[MM.to(m)])
                let attacker = MP.type(board[MM.from(m)])
                s = 500_000_000 + MP.captureGain(victim) * 16 - MP.value[attacker] / 16
                if MM.isPromote(m) { s += 1000 }
                if options.badCaptures && isBadCapture(m) { s = 200_000_000 + MP.captureGain(victim) }
            } else if MM.isPromote(m) {
                s = 400_000_000 + MP.value[MP.promoteOf[MP.type(board[MM.from(m)])]]
            } else if m == k0 {
                s = 300_000_002
            } else if m == k1 {
                s = 300_000_001
            } else {
                s = Int(history[historyIndex(m)])
            }
            scores[i] = Int32(clamping: s)
        }
    }

    /// 安い駒を高い駒で取り、相手に取り返される取りか（駒の損得の大まかな見積もり）。
    @inline(__always) func isBadCapture(_ m: UInt32) -> Bool {
        let victim = MP.type(board[MM.to(m)])
        let attacker = MP.type(board[MM.from(m)])
        if attacker == MP.king || MP.value[victim] >= MP.value[attacker] { return false }
        return isAttacked(MM.to(m), by: side ^ 1)
    }

    /// i 番目以降で最も点の高い手を i へ持ってくる（選択ソート。途中で枝刈りされることが多い）。
    @inline(__always) func pickNext(_ buf: UnsafeMutablePointer<UInt32>, _ scores: UnsafeMutablePointer<Int32>,
                                    _ i: Int, _ n: Int) {
        var best = i
        var bs = scores[i]
        var j = i + 1
        while j < n {
            if scores[j] > bs { bs = scores[j]; best = j }
            j += 1
        }
        if best != i {
            let m = buf[i]; buf[i] = buf[best]; buf[best] = m
            let v = scores[i]; scores[i] = scores[best]; scores[best] = v
        }
    }

    // MARK: 時間

    @inline(__always) func checkStop() -> Bool {
        if stopped { return true }
        nodes += 1
        if nodes & 1023 == 0 {
            if nodes >= nodeLimit || Date() > deadline { stopped = true }
        } else if nodes >= nodeLimit {
            stopped = true
        }
        return stopped
    }

    // MARK: 置換表

    @inline(__always) func ttProbe() -> TTSlot? {
        let e = tt[Int(truncatingIfNeeded: hash) & ttMask]
        return e.key == hash ? e : nil
    }

    @inline(__always) func ttStore(depth: Int, score: Int, flag: UInt8, move: UInt32) {
        let i = Int(truncatingIfNeeded: hash) & ttMask
        let e = tt[i]
        // 同じ局面なら浅い結果で深い結果を潰さない（手だけは残す）。
        if e.key == hash && Int(e.depth) > depth && flag != 3 {
            return
        }
        var s = score
        // 詰みの値は「この局面からの手数」に直して持つ。
        if s > mateBound { s += ply } else if s < -mateBound { s -= ply }
        tt[i] = TTSlot(key: hash, move: move != MM.none ? move : (e.key == hash ? e.move : MM.none),
                       score: Int16(clamping: s), depth: Int8(clamping: depth), flag: flag)
    }

    @inline(__always) func ttScore(_ e: TTSlot) -> Int {
        var s = Int(e.score)
        if s > mateBound { s -= ply } else if s < -mateBound { s += ply }
        return s
    }

    // MARK: 1 手詰め

    /// 王手になる手のうち、相手に合法な応手が無い手（1 手詰め）を探す。
    func mateInOne() -> UInt32? {
        let buf = moveBuf + Self.movesPerPly * ply
        let n = generate(buf, capturesOnly: false)
        let oppK = kingSq[side ^ 1]
        for i in 0..<n {
            let m = buf[i]
            // 玉の近く（距離 2 以内）に着く手か、走り駒の手だけを候補にする（遠い手で詰むことは稀で、重い）。
            let to = MM.to(m)
            let near = abs(MP.file(to) - MP.file(oppK)) <= 2 && abs(MP.rank(to) - MP.rank(oppK)) <= 2
            if !near {
                let code = MM.isDrop(m) ? MM.from(m) | (side << 4) : board[MM.from(m)]
                if slideMask[code] == 0 { continue }
            }
            // 打ち歩詰めは反則なので、歩を打つ手は詰みの候補にしない。
            if MM.isDrop(m) && MM.from(m) == MP.pawn { continue }
            make(m)
            if !isAttacked(kingSq[side ^ 1], by: side), isAttacked(kingSq[side], by: side ^ 1), !hasLegalMove() {
                unmake()
                return m
            }
            unmake()
        }
        return nil
    }

    // MARK: 静止探索

    func quiesce(_ alphaIn: Int, _ beta: Int, qply: Int) -> Int {
        if checkStop() { return 0 }
        var alpha = alphaIn
        let checked = inCheck()
        let buf = moveBuf + Self.movesPerPly * ply
        let scores = scoreBuf + Self.movesPerPly * ply
        var standPat = -infinity
        if !checked {
            standPat = evaluate()
            if standPat >= beta { return standPat }
            if standPat > alpha { alpha = standPat }
            if ply >= maxPly - 2 || qply >= 12 { return standPat }
        } else if ply >= maxPly - 2 {
            return evaluate()
        }
        // 王手されているときは全部の手で逃げ方を読む（取るだけだと詰みを見落とす）。
        let n = generate(buf, capturesOnly: !checked)
        scoreMoves(buf, scores, n, ttMove: MM.none)
        var best = standPat
        var legal = 0
        for i in 0..<n {
            pickNext(buf, scores, i, n)
            let m = buf[i]
            if !checked {
                // デルタ枝刈り: 取った駒の得を足しても alpha に届かない取りは読まない。
                let cap = board[MM.to(m)]
                let gain = cap != MP.empty ? MP.captureGain(MP.type(cap)) : 0
                let promo = MM.isPromote(m) ? MP.value[MP.promoteOf[MP.type(board[MM.from(m)])]] - MP.value[MP.type(board[MM.from(m)])] : 0
                if standPat + gain + promo + 200 <= alpha { continue }
                if options.badCaptures && cap != MP.empty && isBadCapture(m) { continue }
            }
            make(m)
            if !lastMoveIsLegal() { unmake(); continue }
            legal += 1
            let s = -quiesce(-beta, -alpha, qply: qply + 1)
            unmake()
            if stopped { return 0 }
            if s > best {
                best = s
                if s > alpha {
                    alpha = s
                    if s >= beta { return s }
                }
            }
        }
        if checked && legal == 0 { return -mateScore + ply }
        return best
    }

    // MARK: αβ（PVS）

    func search(_ alphaIn: Int, _ betaIn: Int, depth: Int, allowNull: Bool) -> Int {
        if depth <= 0 { return quiesce(alphaIn, betaIn, qply: 0) }
        if checkStop() { return 0 }
        var alpha = alphaIn
        var beta = betaIn
        let isPV = beta - alpha > 1

        // 千日手（探索の経路上で同じ局面）は引き分けとして 0 点。
        if ply >= 4 {
            var i = ply - 4
            while i >= 0 {
                if pathHash[i] == hash { return 0 }
                i -= 2
            }
        }
        if ply >= maxPly - 2 { return evaluate() }

        // 詰みの距離による枝刈り
        alpha = max(alpha, -mateScore + ply)
        beta = min(beta, mateScore - ply - 1)
        if alpha >= beta { return alpha }

        var ttMove = MM.none
        if let e = ttProbe() {
            ttMove = e.move
            if !isPV && Int(e.depth) >= depth {
                let s = ttScore(e)
                if e.flag == 3 || (e.flag == 1 && s >= beta) || (e.flag == 2 && s <= alpha) { return s }
            }
        }

        let checked = inCheck()

        if !checked && options.mateInOne {
            if let m = mateInOne() {
                let s = mateScore - ply - 1
                ttStore(depth: depth, score: s, flag: 3, move: m)
                return s
            }
        }

        var staticEval = 0
        if !checked { staticEval = evaluate() }

        // Futility 枝刈り（親の深さが浅く、静的評価が beta を大きく上回る）。
        if options.futility && !isPV && !checked && depth <= 3 && abs(beta) < mateBound
            && staticEval - 150 * depth >= beta {
            return staticEval
        }

        // Null Move 枝刈り
        if options.nullMove && allowNull && !isPV && !checked && depth >= 3 && staticEval >= beta
            && abs(beta) < mateBound {
            let r = 3 + depth / 6
            makeNull()
            let s = -search(-beta, -beta + 1, depth: depth - 1 - r, allowNull: false)
            unmakeNull()
            if stopped { return 0 }
            if s >= beta { return s >= mateBound ? beta : s }
        }

        // 内部反復深化（置換表の手が無い PV の局面）
        if isPV && ttMove == MM.none && depth >= 5 {
            _ = search(alpha, beta, depth: depth - 2, allowNull: false)
            if stopped { return 0 }
            ttMove = ttProbe()?.move ?? MM.none
        }

        let buf = moveBuf + Self.movesPerPly * ply
        let scores = scoreBuf + Self.movesPerPly * ply
        let n = generate(buf, capturesOnly: false)
        scoreMoves(buf, scores, n, ttMove: ttMove)

        var best = -infinity
        var bestMove = MM.none
        var legal = 0
        let origAlpha = alpha
        var quietsTried = 0
        let futilityMargin = staticEval + 120 + 120 * depth

        for i in 0..<n {
            pickNext(buf, scores, i, n)
            let m = buf[i]
            let isCapture = !MM.isDrop(m) && board[MM.to(m)] != MP.empty
            let isQuiet = !isCapture && !MM.isPromote(m)

            // 浅いところの静かな手の枝刈り（Futility・後ろの手の打ち切り）
            if options.futility && !isPV && !checked && isQuiet && legal > 0 && depth <= 3
                && best > -mateBound && futilityMargin <= alpha {
                if !givesCheck(m) { continue }
            }

            make(m)
            if !lastMoveIsLegal() { unmake(); continue }
            legal += 1
            let givesCheckNow = inCheck()
            var ext = 0
            if options.checkExtension && givesCheckNow && depth <= 6 { ext = 1 }
            let newDepth = depth - 1 + ext
            var s: Int
            if legal == 1 || !options.pvs {
                s = -search(-beta, -alpha, depth: newDepth, allowNull: true)
            } else {
                var reduction = 0
                if options.lmr && depth >= 3 && isQuiet && !checked && !givesCheckNow && legal > 3 {
                    reduction = 1 + (legal > 10 ? 1 : 0) + (depth >= 8 && legal > 20 ? 1 : 0)
                    if isPV { reduction -= 1 }
                    if m == killers[(ply - 1) * 2] || m == killers[(ply - 1) * 2 + 1] { reduction -= 1 }
                    reduction = max(0, min(reduction, newDepth - 1))
                }
                s = -search(-alpha - 1, -alpha, depth: newDepth - reduction, allowNull: true)
                if s > alpha && reduction > 0 {
                    s = -search(-alpha - 1, -alpha, depth: newDepth, allowNull: true)
                }
                if s > alpha && s < beta {
                    s = -search(-beta, -alpha, depth: newDepth, allowNull: true)
                }
            }
            unmake()
            if stopped { return 0 }
            if isQuiet { quietsTried += 1 }

            if s > best {
                best = s
                bestMove = m
                if s > alpha {
                    alpha = s
                    if s >= beta {
                        if isQuiet {
                            if killers[ply * 2] != m {
                                killers[ply * 2 + 1] = killers[ply * 2]
                                killers[ply * 2] = m
                            }
                            let hi = historyIndex(m)
                            history[hi] = min(history[hi] + Int32(depth * depth), 200_000_000)
                        }
                        ttStore(depth: depth, score: s, flag: 1, move: m)
                        return s
                    }
                }
            }
        }

        if legal == 0 { return -mateScore + ply }
        ttStore(depth: depth, score: best, flag: best > origAlpha ? 3 : 2, move: bestMove)
        return best
    }

    // MARK: 根

    func think(deadline: Date, startedAt: Date, timeLimit: TimeInterval, nodeLimit: Int?)
        -> (usi: String?, nodes: Int, depth: Int, score: Int) {
        self.deadline = deadline
        self.nodeLimit = nodeLimit ?? .max
        let buf = moveBuf
        let scores = scoreBuf
        var n = generate(buf, capturesOnly: false)
        // 合法手だけ残す
        var k = 0
        for i in 0..<n {
            make(buf[i])
            let ok = lastMoveIsLegal()
            unmake()
            if ok { buf[k] = buf[i]; k += 1 }
        }
        n = k
        guard n > 0 else { return (nil, 0, 0, 0) }
        var rootMoves = (0..<n).map { buf[$0] }
        var bestMove = rootMoves[0]
        var bestScore = 0
        var completed = 0

        if options.mateInOne, let m = mateInOne() {
            return (usi(m), nodes, 1, mateScore - 1)
        }

        // 取る手・成る手が先に来るように並べる（1 手詰めの確認で buf は上書きされているので書き戻す）
        for i in 0..<n { buf[i] = rootMoves[i] }
        scoreMoves(buf, scores, n, ttMove: MM.none)
        var order = (0..<n).map { (buf[$0], scores[$0]) }
        order.sort { $0.1 > $1.1 }
        rootMoves = order.map(\.0)

        var prevScore = 0
        for depth in 1...(maxPly - 10) {
            var delta = 60
            var alpha = -infinity, beta = infinity
            if options.aspiration && depth >= 4 {
                alpha = max(prevScore - delta, -infinity)
                beta = min(prevScore + delta, infinity)
            }
            var iterBest = rootMoves[0]
            var iterScore = -infinity
            while true {
                iterScore = -infinity
                var a = alpha
                var localBest = rootMoves[0]
                for (i, m) in rootMoves.enumerated() {
                    make(m)
                    var s: Int
                    let ext = options.checkExtension && inCheck() ? 1 : 0
                    if i == 0 || !options.pvs {
                        s = -search(-beta, -a, depth: depth - 1 + ext, allowNull: true)
                    } else {
                        s = -search(-a - 1, -a, depth: depth - 1 + ext, allowNull: true)
                        if s > a && s < beta && !stopped {
                            s = -search(-beta, -a, depth: depth - 1 + ext, allowNull: true)
                        }
                    }
                    unmake()
                    if stopped { break }
                    if s > iterScore {
                        iterScore = s
                        localBest = m
                        if s > a {
                            a = s
                            // 良い手を先頭へ（次の反復・再探索で最初に読む）
                            if let idx = rootMoves.firstIndex(of: m), idx > 0 {
                                rootMoves.remove(at: idx)
                                rootMoves.insert(m, at: 0)
                            }
                        }
                        if s >= beta { break }
                    }
                }
                if stopped {
                    // 途中で止まっても、この反復の窓の中で値が確定した最善手は使う（前の最善手より良いと分かった手）。
                    if iterScore > alpha { bestMove = localBest }
                    break
                }
                iterBest = localBest
                if iterScore <= alpha {
                    alpha = max(alpha - delta, -infinity)
                    delta *= 3
                    if delta > 1500 { alpha = -infinity }
                    continue
                }
                if iterScore >= beta {
                    beta = min(beta + delta, infinity)
                    delta *= 3
                    if delta > 1500 { beta = infinity }
                    continue
                }
                break
            }
            if stopped { break }
            bestMove = iterBest
            bestScore = iterScore
            prevScore = iterScore
            completed = depth
            if bestScore > mateBound { break }   // 詰みを見つけた
            // 次の反復は今の反復より長くかかるので、残り時間で読み終わりそうにないなら始めない。
            if timeLimit.isFinite {
                let used = Date().timeIntervalSince(startedAt)
                if used > timeLimit * 0.45 { break }
            }
            if nodes >= self.nodeLimit / 2 && nodeLimit != nil { break }
        }
        return (usi(bestMove), nodes, completed, bestScore)
    }

    func usi(_ m: UInt32) -> String {
        let to = MM.to(m)
        let toIdx = Sq.index(file: MP.file(to), rank: MP.rank(to))
        if MM.isDrop(m) {
            let type = PieceType(rawValue: MM.from(m) - 1)!
            return Move.drop(type: type, to: toIdx).usi
        }
        let from = MM.from(m)
        let fromIdx = Sq.index(file: MP.file(from), rank: MP.rank(from))
        return Move.board(from: fromIdx, to: toIdx, promote: MM.isPromote(m)).usi
    }

    // MARK: 検証用

    /// 合法手の一覧（USI）。既存の手生成と突き合わせるテスト用。歩・角・飛の不成は含まない。
    func legalMovesUSI() -> [String] {
        let buf = moveBuf
        let n = generate(buf, capturesOnly: false)
        var out: [String] = []
        for i in 0..<n {
            make(buf[i])
            if lastMoveIsLegal() { out.append(usi(buf[i])) }
            unmake()
        }
        return out
    }

    func perft(_ depth: Int) -> Int {
        if depth == 0 { return 1 }
        let buf = moveBuf + Self.movesPerPly * ply
        let n = generate(buf, capturesOnly: false)
        var total = 0
        for i in 0..<n {
            make(buf[i])
            if lastMoveIsLegal() { total += perft(depth - 1) }
            unmake()
        }
        return total
    }
}

extension ShogiMasterEngine {
    /// テスト用: 自前の手生成で数えた合法手（USI）。
    static func legalMovesUSI(sfen: String) -> [String] {
        guard let pos = Position.fromSFEN(sfen) else { return [] }
        let s = MasterSearcher(pos, options: .shipped)
        defer { s.release() }
        return s.legalMovesUSI()
    }

    /// テスト用: 自前の手生成での perft（歩・角・飛の不成は数えない）。
    static func perft(sfen: String, depth: Int) -> Int {
        guard let pos = Position.fromSFEN(sfen) else { return 0 }
        let s = MasterSearcher(pos, options: .shipped)
        defer { s.release() }
        return s.perft(depth)
    }
}
