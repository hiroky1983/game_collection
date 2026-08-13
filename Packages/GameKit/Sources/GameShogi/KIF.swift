import Foundation

/// 指し手を KIF 形式の表記に変換する。直前手の表示に使う。
enum KIF {
    private static let fileKanji = ["１", "２", "３", "４", "５", "６", "７", "８", "９"]
    private static let rankKanji = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]

    static func notation(_ move: Move, pos: Position, prevTo: Int?) -> String {
        switch move {
        case let .board(from, to, promote):
            let piece = pos.squares[from]!
            let dest = (prevTo == to) ? "同　" : fileKanji[Sq.file(to)] + rankKanji[Sq.rank(to)]
            let fromStr = "(\(Sq.file(from) + 1)\(Sq.rank(from) + 1))"
            return dest + kifName(piece) + (promote ? "成" : "") + fromStr
        case let .drop(type, to):
            let dest = fileKanji[Sq.file(to)] + rankKanji[Sq.rank(to)]
            return dest + kifName(Piece(type: type, color: .black)) + "打"
        }
    }

    private static func kifName(_ p: Piece) -> String {
        if p.promoted {
            switch p.type {
            case .pawn: return "と"
            case .lance: return "成香"
            case .knight: return "成桂"
            case .silver: return "成銀"
            case .bishop: return "馬"
            case .rook: return "龍"
            default: break
            }
        }
        switch p.type {
        case .pawn: return "歩"
        case .lance: return "香"
        case .knight: return "桂"
        case .silver: return "銀"
        case .gold: return "金"
        case .bishop: return "角"
        case .rook: return "飛"
        case .king: return "玉"
        }
    }
}
