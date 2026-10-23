import Foundation

/// 盤ゲームの着手の効果音（#2767）。将棋・囲碁（五目並べ）・オセロ・チェスの「自分の着手」だけ、
/// 合成音ではなく同梱した本物の駒・石の音（CC0 素材・出所は `docs/design/board-sfx/assets-license.md`）を鳴らす。
///
/// 触覚と同じ呼び出し箇所に相乗りさせるため `FeedbackImpact.board(_:)` として届く（`CardSound` と同じ作り）。
/// 勝ち・負け・引き分け・王手の音（`SoundEffect`）は今のまま。CPU の着手は無音のまま。
public enum BoardSound: String, CaseIterable, Sendable {
    /// 将棋：駒を指す・打つ・成る。
    case shogiPiece = "shogi-piece"
    /// 将棋：駒を取る（指す音より少し重い）。
    case shogiCapture = "shogi-capture"
    /// 囲碁・五目並べ：碁盤に石を置く。
    case goStone = "go-stone"
    /// オセロ：石を置く（返る石は鳴らさない）。
    case othelloDisc = "othello-disc"
    /// チェス：木の駒を置く。
    case chessPiece = "chess-piece"

    /// 同梱ファイルの拡張子。
    public static let fileExtension = "caf"

    /// 同梱ファイル。見つからなければ nil（呼び出し側は無音で済ませる）。
    public var url: URL? {
        Bundle.module.url(forResource: rawValue, withExtension: Self.fileExtension, subdirectory: "Sounds")
    }

    /// 触覚の強さ。着手の手応えはこれまでどおり `medium`。
    public var haptic: FeedbackImpact { .medium }
}
