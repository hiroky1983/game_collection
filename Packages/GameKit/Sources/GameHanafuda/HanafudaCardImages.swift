import CoreGraphics
import Foundation
import ImageIO

/// 札 48 枚の絵柄の画像（#2188）。
///
/// 絵は Codex の画像生成に**文章だけで**伝統図柄を指示して描いたもので、参考画像は一切渡していない
/// （指示文の全文・原画・出所と利用可否は `docs/design/hanafuda-cards/`）。
/// 同梱するのは原画 1024×1536 を表示サイズに合わせて縮めた `Resources/Cards/Hanafuda_NN.png`
/// （NN は `HanafudaCard.id`・320×480・256 色）。札は画面では幅 40〜130pt なので、これで 3x でも足りる。
///
/// GameKit は macOS でもビルドされる（`swift test`）ので UIImage は使わず ImageIO で読む（`OjisanPuzzleArt` と同じ）。
enum HanafudaCardImages {
    /// `Resources/` の下のフォルダ名。
    static let directory = "Cards"

    /// 札の画像のファイル名（拡張子なし）。
    static func resourceName(for id: Int) -> String {
        String(format: "Hanafuda_%02d", id)
    }

    static func url(for id: Int) -> URL? {
        Bundle.module.url(forResource: resourceName(for: id), withExtension: "png", subdirectory: directory)
    }

    /// 48 枚を最初に使うときにまとめて読む（読めなかった札は入らない）。
    private static let images: [Int: CGImage] = {
        var out: [Int: CGImage] = [:]
        for id in 0..<HanafudaCard.deckSize {
            if let url = url(for: id),
               let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                out[id] = cg
            }
        }
        return out
    }()

    /// 札の絵。読めなければ nil（`HanafudaCardFace` は生成りの面に帯だけを描いて逃がす）。
    static func image(for card: HanafudaCard) -> CGImage? {
        images[card.id]
    }
}
