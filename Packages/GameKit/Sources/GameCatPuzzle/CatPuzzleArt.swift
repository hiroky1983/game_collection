import CoreGraphics
import ImageIO
import SwiftUI

/// 会長の猫（グレーと白のハチワレ・赤い首輪に金の鈴）の絵（#2250）。
/// 素材は会長が ChatGPT で作成した表情・ポーズのシートからの切り抜きで、出所と利用条件は
/// `docs/design/cat-puzzle-2250/README.md`「猫の絵の出所」（アプリアイコン #2189 と同じ扱い）。
/// ここでは長辺 192px に縮めて同梱している（1 マス 45pt の 3 倍で足りる）。
enum CatPuzzleArt {
    enum Pose: String, CaseIterable {
        /// 盤に置いた猫（正面の顔）。
        case faceNormal = "face_normal"
        /// クリアで部屋ごとにくつろぐ姿。
        case sleep, belly, pounce, stretch
        case sitUp = "sit_up"
        case sitSide = "sit_side"
        case sitFront = "sit_front"
        case faceWow = "face_wow"
    }

    /// GameKit は macOS でもビルドされる（`swift test`）ので UIImage は使わず ImageIO で読む。
    private static let images: [Pose: CGImage] = {
        var out: [Pose: CGImage] = [:]
        for pose in Pose.allCases {
            if let url = Bundle.module.url(forResource: "cat_\(pose.rawValue)", withExtension: "png", subdirectory: "Cats"),
               let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                out[pose] = cg
            }
        }
        return out
    }()

    /// 盤の描画（`Canvas`）に渡す絵。読めなければ nil（呼び出し側が記号に退避する）。
    static func cgImage(_ pose: Pose) -> CGImage? { images[pose] }

    /// 絵の縦横比（幅 ÷ 高さ）。読めなければ 1。
    static func aspect(_ pose: Pose) -> CGFloat {
        guard let cg = images[pose], cg.height > 0 else { return 1 }
        return CGFloat(cg.width) / CGFloat(cg.height)
    }

    /// `rect` に収まる最大の大きさで中央に置いた矩形（縦横比を保つ）。
    static func fitted(_ pose: Pose, in rect: CGRect) -> CGRect {
        let aspect = aspect(pose)
        var size = CGSize(width: rect.width, height: rect.width / aspect)
        if size.height > rect.height {
            size = CGSize(width: rect.height * aspect, height: rect.height)
        }
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// 装飾なので VoiceOver は読まない。読み込めなかったときは SF Symbol に退避する。
    @ViewBuilder
    static func image(_ pose: Pose) -> some View {
        if let cg = images[pose] {
            Image(decorative: cg, scale: 1).resizable().scaledToFit()
        } else {
            Image(systemName: "cat.fill").resizable().scaledToFit()
        }
    }
}
