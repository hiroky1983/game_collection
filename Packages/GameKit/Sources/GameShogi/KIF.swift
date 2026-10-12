import Foundation

/// 指し手を KIF 形式の表記に変換する。直前手の表示に使う。
enum KIF {
    private static let fileKanji = ["１", "２", "３", "４", "５", "６", "７", "８", "９"]  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
    private static let rankKanji = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）

    static func notation(_ move: Move, pos: Position, prevTo: Int?) -> String {
        switch move {
        case let .board(from, to, promote):
            let piece = pos.squares[from]!
            let dest = (prevTo == to) ? "同　" : fileKanji[Sq.file(to)] + rankKanji[Sq.rank(to)]  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
            let fromStr = "(\(Sq.file(from) + 1)\(Sq.rank(from) + 1))"
            return dest + kifName(piece) + (promote ? "成" : "") + fromStr  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
        case let .drop(type, to):
            let dest = fileKanji[Sq.file(to)] + rankKanji[Sq.rank(to)]
            return dest + kifName(Piece(type: type, color: .black)) + "打"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
        }
    }

    private static func kifName(_ p: Piece) -> String {
        if p.promoted {
            switch p.type {
            case .pawn: return "と"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
            case .lance: return "成香"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
            case .knight: return "成桂"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
            case .silver: return "成銀"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
            case .bishop: return "馬"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
            case .rook: return "龍"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
            default: break
            }
        }
        switch p.type {
        case .pawn: return "歩"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
        case .lance: return "香"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
        case .knight: return "桂"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
        case .silver: return "銀"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
        case .gold: return "金"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
        case .bishop: return "角"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
        case .rook: return "飛"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
        case .king: return "玉"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
        }
    }
}
