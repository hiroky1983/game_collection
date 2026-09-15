import Core
import Foundation

// MARK: - チャリンコおじさんのドット絵（走者以外）

/// チャリンコおじさんの**走者以外**のドット絵の置き場（#956）。走者と正面顔はおじさんシリーズで
/// 使い回すので `Core` の `OjisanPixel` にあり、こちらはこのゲーム限りの物——アイテム・障害物・
/// 背景の飾り——を集める。今後、図形の組み立て（`SKShapeNode`）からドット絵へ置き換える物は
/// すべてここに `〜Rows` と `〜()` を足し、`RunnerPixelArtTests` の走査に入れる。
///
/// 描き方は走者と同じ（SFC 級・#701）: 1 文字 = 1 ドット、`.` は透明、暗い縁取りで背景から
/// 浮かせる（#929「手前の物は縁取る」）。1 ドットの大きさはシーン側が走者と同じ単位
/// （`RunnerRider.placement` の `unit` ≒ 0.33）で貼るので、**ここでは寸法をドット数だけで考える**
/// （3 ドット ≒ 1 単位、走者の頭までが 36 ドット）。
enum RunnerPixelArt {
    /// 共通パレット。おじさんのパレット（`OjisanPixel.palette`）とは別に持つ——食べ物・背景の
    /// 色はキャラクターと混ぜたくない。文字は絵をまたいで同じ意味に使う（`K` は常に縁取り）。
    static let palette: [Character: UInt32] = [
        "K": outline,
        "D": takoyakiDough,
        "d": 0xB8682A,
        "S": 0x5C2C10,
        "s": 0x8E4A1E,
        "M": 0xFAF6EC,
        "A": 0x3F8F4C,
        "T": 0xE6C98C,
    ]

    /// 縁取り（焦げ茶寄りの黒）。3 世界の縁取り（`RunnerWorld.outline`・0x0E1420〜0x241A14）と同じ
    /// 濃さで、朝のパステルの丘・壁、夕方の手前の丘（0x6E5A96・いちばん厳しい）の上でも輪郭が立つ
    /// （`WorldTests` が 3:1 を固定。朝の値 0x241A14 は夕方の丘に 2.9 で届かないので一段暗い）。
    static let outline: UInt32 = 0x1A120E

    /// たこ焼きの生地の主色（きつね色）。岩のグレー・地面の茶・鳥の緑のどれとも系統が違う食べ物の色。
    static let takoyakiDough: UInt32 = 0xE8A860

    // MARK: たこ焼き（`RunnerPickupKind.invincible`・#797 → #956）

    /// たこ焼き 1 個（15×18 ドット）。舟皿に 3 個を並べた図形は小さすぎて「何か分からない」
    /// （会長 QA 2026-09-15）ので、1 個を走者の頭ほどの大きさ（高さ 18 ドット ≒ 6 単位）で描く。
    ///
    /// - 丸い生地はきつね色 2 階調（`D` 明・`d` 陰は右下）
    /// - 上面に濃い茶のソース（`S`）と照り（`s`・左上）、その上を白いマヨ（`M`）の線が斜めに走る
    /// - 青のり（`A`）を 3 ドット
    /// - 上に爪楊枝（`T`）1 本（縁取り込みで 3 ドット幅・生地の上に 5 ドット）
    /// - 格子は絵にぴったり（透明な余白の行・列が無い）。シーン側は `anchorPoint = (0.5, 0)` で
    ///   **絵の底の中央**を置き場に合わせる（`RunnerPixelArtTests` が余白なしを固定）
    /// - 特定のキャラクター・作品には寄せない（#494 の権利チェック）
    static let takoyakiRows: [String] = [
        ".......K.......",
        "......KTK......",
        "......KTK......",
        "......KTK......",
        "......KTK......",
        ".....KKTKK.....",
        "...KKSKTKSKK...",
        "..KSssSSSSSSK..",
        ".KSsMMSSASSSSK.",
        "KSsMSSMMSSSSASK",
        "KSSSSSSSMMSSSSK",
        "KSSSASSSSSMMSSK",
        "KDSSDDSSDDDSSdK",
        "KDDDDDDSDDDDddK",
        ".KDDDDDDDDDddK.",
        "..KDDDDDDdddK..",
        "...KKdddddKK...",
        ".....KKKKK.....",
    ]

    static func takoyaki() -> PixelSprite {
        PixelSprite(rows: takoyakiRows, palette: palette)
    }
}
