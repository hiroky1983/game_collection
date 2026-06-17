import Foundation

/// 内部の指し手列(USI/Move)から KIF 形式テキストを生成する。エクスポート時のみ変換する。
enum KIF {
    private static let fileKanji = ["１", "２", "３", "４", "５", "６", "７", "８", "９"]
    private static let rankKanji = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]

    @MainActor
    static func export(_ model: ShogiGameModel) -> String {
        var lines: [String] = []
        lines.append("# 思考ゲーム詰め合わせ KIF")
        lines.append("手合割：平手")
        lines.append("先手：" + (model.sente == .ai ? "CPU" : "プレイヤー"))
        lines.append("後手：" + (model.gote == .ai ? "CPU" : "プレイヤー"))
        lines.append("手数----指手---------消費時間--")

        var pos = Position.fromSFEN(model.initialSFEN) ?? Position.start()
        var prevTo: Int?
        for (i, move) in model.moves.enumerated() {
            lines.append(String(format: "%4d ", i + 1) + notation(move, pos: pos, prevTo: prevTo))
            switch move {
            case let .board(_, to, _): prevTo = to
            case let .drop(_, to): prevTo = to
            }
            pos.make(move)
        }
        return lines.joined(separator: "\n") + "\n"
    }

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
