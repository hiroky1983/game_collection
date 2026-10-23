import Foundation
import Core

/// 盤・持ち駒の VoiceOver 読み上げ文（#188）。
///
/// 見た目（`ShogiCell` / `KomaView`）は色と漢字1文字で先後や成りを表しているため、
/// 画面を見ないと駒種も手番も分からない。読み上げ文はここに集約して純関数にし、
/// View を組まずにテストできるようにする。
public enum ShogiAccessibility {
    /// 段の漢数字（rank 0 = 一段目）。日本語の読み上げ用で、棋譜の慣習どおりの表記なので訳さない。
    private static let rankKanji = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]  // i18n-keep: 日本語の読み上げ用の段の漢数字（英語は a〜i で読む）
    /// 英語の段の呼び名（rank 0 = a）。英語圏の将棋の棋譜で使う「7g」の形（#2166）。
    private static let rankLetters = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]

    /// 読み上げ文の言語。`nil` ならいまの表示言語（テストは英語を明示して引く）。
    private static func resolved(_ language: AppLanguage?) -> AppLanguage {
        language ?? AppLanguageStore.shared.language
    }

    /// マスの呼び名（例: index 60 → "7七"、英語では "7g"）。筋はアラビア数字・段は漢数字という棋譜の慣習に合わせる。
    public static func squareName(_ index: Int, language: AppLanguage? = nil) -> String {
        let file = Sq.file(index) + 1
        let rank = Sq.rank(index)
        if resolved(language) == .english { return "\(file)\(rankLetters[rank])" }
        return "\(file)\(rankKanji[rank])"
    }

    /// 駒の呼び名（例: 成った歩 → "と金"）。盤面の1文字表記（`Glyph.kanji`）は
    /// 「圭」「全」のように読み上げても意味が伝わらないため、別に語を用意する。
    public static func pieceName(_ piece: Piece, language: AppLanguage? = nil) -> String {
        let language = resolved(language)
        if piece.promoted {
            switch piece.type {
            case .pawn:   return tr("と金", language: language)
            case .lance:  return tr("成香", language: language)
            case .knight: return tr("成桂", language: language)
            case .silver: return tr("成銀", language: language)
            case .bishop: return tr("馬", language: language)
            case .rook:   return tr("龍", language: language)
            case .gold, .king: break
            }
        }
        switch piece.type {
        case .pawn:   return tr("歩", language: language)
        case .lance:  return tr("香車", language: language)
        case .knight: return tr("桂馬", language: language)
        case .silver: return tr("銀", language: language)
        case .gold:   return tr("金", language: language)
        case .bishop: return tr("角", language: language)
        case .rook:   return tr("飛車", language: language)
        case .king:   return tr("玉", language: language)
        }
    }

    private static func sideName(_ side: Side, language: AppLanguage) -> String {
        side == .black ? tr("先手", language: language) : tr("後手", language: language)
    }

    /// 読み上げの区切り。日本語は読点、英語はカンマ。
    private static func separator(_ language: AppLanguage) -> String {
        language == .english ? ", " : "、"  // i18n-keep: 読み上げの区切り（日本語のとき）。英語は直前の分岐で「, 」
    }

    /// 盤上 1 マスの読み上げ文。
    public static func squareLabel(
        index: Int,
        piece: Piece?,
        isSelected: Bool,
        isTarget: Bool,
        isLastMove: Bool,
        isCheckedKing: Bool = false,
        isHint: Bool = false,
        hintDrop: Piece? = nil,
        language: AppLanguage? = nil
    ) -> String {
        let language = resolved(language)
        var parts = [squareName(index, language: language)]
        if let piece {
            parts.append(tr("%1$@の%2$@", sideName(piece.color, language: language),
                            pieceName(piece, language: language), language: language))
        } else {
            parts.append(tr("空きマス", language: language))
        }
        // 王手は「なぜ動かせないのか」に直結する情報なので、選択状態より先に読ませる（#377）。
        // 見た目の赤枠（`ShogiView.checkLayer`）と同じ条件で出す。
        if isCheckedKing { parts.append(tr("王手されています", language: language)) }
        if isSelected { parts.append(tr("選択中", language: language)) }
        if isTarget {
            parts.append(piece == nil ? tr("ここに指せます", language: language) : tr("取れます", language: language))
        }
        if isLastMove { parts.append(tr("直前の手", language: language)) }
        // ヒントの印（#1118）。見た目の枠（`ShogiView.targetLayer` が描くヒントの印）と同じ条件で読ませる。
        // 打つ手（#2768）は何を打つかも読ませる。例: 「ヒント：銀を打つ」。
        if isHint {
            if let hintDrop {
                parts.append(tr("ヒント：%@を打つ", pieceName(hintDrop, language: language), language: language))
            } else {
                parts.append(tr("ヒントの手", language: language))
            }
        }
        return parts.joined(separator: separator(language))
    }

    /// 成り確認の札の読み上げ文（#1641）。見た目の問い（`ShogiView.promotionOverlay`）と同じ文言にする。
    /// 表示言語の切り替えに追従するよう、保存せず毎回引く（#2109）。
    public static var promotionPromptLabel: String { tr("成りますか？") }

    /// 持ち駒 1 種類の読み上げ文。
    public static func handLabel(
        type: PieceType, color: Side, count: Int, isSelected: Bool, isHint: Bool = false, language: AppLanguage? = nil
    ) -> String {
        let language = resolved(language)
        var text = tr("%1$@の持ち駒、%2$@%3$lld枚", sideName(color, language: language),
                      pieceName(Piece(type: type, color: color), language: language), count,
                      language: language)
        if isSelected { text += separator(language) + tr("選択中", language: language) }
        // ヒントが打つ手のとき、打つ駒の欄に印が付く（#2768）。
        if isHint { text += separator(language) + tr("ヒントの駒", language: language) }
        return text
    }

    /// CPU が指したときの読み上げ文（#2280）。`piece` は指したあとの `to` にある駒（成ったあとの姿）。
    /// 王手は「なぜ動かせない駒があるのか」に直結するが、バナーは 1 秒で消えるので続けて読ませる。
    public static func cpuMoveAnnouncement(
        move: Move, piece: Piece?, isCheck: Bool, language: AppLanguage? = nil
    ) -> String {
        let language = resolved(language)
        var text: String
        switch move {
        case let .board(from, to, promote):
            let name = piece.map { pieceName($0, language: language) } ?? ""
            text = tr("CPUは%1$@を%2$@から%3$@へ動かしました", name,
                      squareName(from, language: language), squareName(to, language: language), language: language)
            if promote { text += tr("。", language: language) + tr("成りました", language: language) }
        case let .drop(type, to):
            let name = pieceName(Piece(type: type, color: piece?.color ?? .white), language: language)
            text = tr("CPUは%1$@を%2$@に打ちました", name, squareName(to, language: language), language: language)
        }
        if isCheck { text += tr("。", language: language) + tr("王手です", language: language) }
        return text
    }
}
