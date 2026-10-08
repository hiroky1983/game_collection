import CoreGraphics
import ImageIO
import SwiftUI

/// 作業服おじさんの全身ドット絵（#1909。会長決定 2026-10-07: 48 ドット・腰痛の段階ごとにコマを替える）。
/// 素材は Codex で作った PNG で、出所と規約確認は docs/design/ojisan-pixel-pipeline にある。
/// 画像は 1 ドット = 1px で入っているので、表示は整数倍（`pointsPerDot`）の `frame` ＋
/// `interpolation(.none)` でにじませない。
enum OjisanPuzzleArt {
    enum Pose: String, CaseIterable {
        /// 余裕（軽い荷物・笑顔）。
        case easy = "carry_light_smile"
        /// 痛い（重い荷物・汗）。
        case aching = "carry_heavy_pain_sweat"
        /// 限界（腰を押さえる）。
        case severe = "limit_back_pain"
        /// 入院（倒れる。リザルトだけに出す）。
        case fallen = "fallen_face_down_crying"
    }

    /// 1 ドットを何 pt で描くか（画面モックの 1 ドット = 2pt）。
    static let pointsPerDot: CGFloat = 2

    static func pose(for stage: OjisanPuzzlePain.Stage) -> Pose {
        switch stage {
        case .easy: .easy
        case .aching: .aching
        case .severe: .severe
        }
    }

    /// GameKit は macOS でもビルドされる（`swift test`）ので UIImage は使わず ImageIO で読む。
    private static let images: [Pose: CGImage] = {
        var out: [Pose: CGImage] = [:]
        for pose in Pose.allCases {
            if let url = Bundle.module.url(forResource: "OjisanWork_\(pose.rawValue)", withExtension: "png"),
               let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                out[pose] = cg
            }
        }
        return out
    }()

    /// ドット数（画像の幅・高さ）。読めなければ nil。
    static func dotSize(_ pose: Pose) -> (width: Int, height: Int)? {
        images[pose].map { (width: $0.width, height: $0.height) }
    }

    /// 装飾なので VoiceOver は読まない。読み込めなかったときは SF Symbol に退避する。
    @ViewBuilder
    static func image(_ pose: Pose) -> some View {
        if let cg = images[pose] {
            Image(decorative: cg, scale: 1)
                .resizable()
                .interpolation(.none)
                .frame(width: CGFloat(cg.width) * pointsPerDot, height: CGFloat(cg.height) * pointsPerDot)
        } else {
            Image(systemName: "figure.stand").font(.largeTitle) // fixed-size: 素材が読めなかったときの退避
        }
    }
}
