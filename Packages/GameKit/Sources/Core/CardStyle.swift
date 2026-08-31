import SwiftUI

/// トランプ・カード面の共通質感（#366）。
///
/// カードは「平面の駒」なので、#366 で確定した描き分けの原則に従い、
/// 面は**明度差の控えめな縦グラデーション**で紙の実在感だけを出す
/// （ラジアルの照りはドーム＝碁石系の表現なので使わない）。
/// 裏は濃色の縦グラデーション + 白の内枠（実物のカード裏の定番構図）。
///
/// ポーカー・ブラックジャック・大富豪・神経衰弱の4ゲームがこの定数を共有する。
/// ここを1か所にしておけば、トーン調整（会長レビュー）が全ゲームへ同時に効き、
/// `CardStyleTests` で「表は下端へわずかに沈む」「裏は暗くなる方向」を固定できる。
public enum CardStyle {

    // MARK: - 表面（紙）

    /// 表面の上端。真っ白から始める。
    public static let faceTop: UInt32 = 0xFFFFFF

    /// 表面の下端。わずかに沈む紙色。明度差を大きくすると面が曲がって見えるので控えめに。
    public static let faceBottom: UInt32 = 0xF1EDE2

    // MARK: - 裏面（藍）

    /// 裏面の上端 → 下端。従来の単色（0x2A5298）を挟む藍で、上から下へ暗くする。
    public static let backTop: UInt32 = 0x33619E
    public static let backBottom: UInt32 = 0x1E3F73

    /// 裏面の内枠（実物カードの縁取り）。
    public static let backFrameOpacity: Double = 0.35
    public static let backFrameInset: CGFloat = 4

    /// 裏面中央のモチーフ（スート印など）の白の不透明度。
    public static let backMotifOpacity: Double = 0.38

    // MARK: - 塗り

    public static var faceFill: LinearGradient {
        LinearGradient(colors: [Color(hex: faceTop), Color(hex: faceBottom)],
                       startPoint: .top, endPoint: .bottom)
    }

    public static var backFill: LinearGradient {
        LinearGradient(colors: [Color(hex: backTop), Color(hex: backBottom)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// 裏面の内枠。呼び出し側のカードの角丸に合わせて `cornerRadius` を渡す
    /// （外形より `backFrameInset` ぶん内側に入るので、角丸も同じだけ絞る）。
    public static func backFrame(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: max(cornerRadius - backFrameInset, 2), style: .continuous)
            .strokeBorder(Color.white.opacity(backFrameOpacity), lineWidth: 1)
            .padding(backFrameInset)
    }
}
