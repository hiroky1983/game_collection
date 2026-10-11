import CoreGraphics
import Testing
@testable import GameOjisanPuzzle

@Suite("おじさんの荷物運びパズル: 作業服おじさんのドット絵（#1909）")
struct OjisanPuzzleArtTests {
    @Test("5 コマすべて同梱され、読み込める")
    func allPosesLoad() {
        for pose in OjisanPuzzleArt.Pose.allCases {
            #expect(OjisanPuzzleArt.dotSize(pose) != nil, "\(pose) の画像が読めない")
        }
    }

    @Test("立ちポーズは 48 ドット以内、倒れたコマは横長")
    func sizes() throws {
        for pose in [OjisanPuzzleArt.Pose.easy, .aching, .severe] {
            let size = try #require(OjisanPuzzleArt.dotSize(pose))
            #expect(size.height <= 48 && size.height > size.width)
            // 右の列の箱（88×96pt）に収まる。
            #expect(CGFloat(size.width) * OjisanPuzzleArt.pointsPerDot <= OjisanPuzzleView.figureBoxWidth)
            #expect(CGFloat(size.height) * OjisanPuzzleArt.pointsPerDot <= OjisanPuzzleView.figureBoxHeight)
        }
        let fallen = try #require(OjisanPuzzleArt.dotSize(.fallen))
        #expect(fallen.width > fallen.height)
        // 入院のベッド（#2064）は 64 ドット版（83×64）。
        let bed = try #require(OjisanPuzzleArt.dotSize(.hospitalized))
        #expect(bed.width == 83 && bed.height == 64)
    }

    @Test("決着ごとの絵: 入院はベッド、積み上がりは倒れる絵、片付いたら笑顔（#2064）")
    func resultPoseForOutcome() {
        #expect(OjisanPuzzleArt.resultPose(for: .hospitalized) == .hospitalized)
        #expect(OjisanPuzzleArt.resultPose(for: .buried) == .fallen)
        #expect(OjisanPuzzleArt.resultPose(for: .cleared) == .easy)
    }

    @Test("段階ごとに別のコマ")
    func poseForStage() {
        #expect(OjisanPuzzleArt.pose(for: .easy) == .easy)
        #expect(OjisanPuzzleArt.pose(for: .aching) == .aching)
        #expect(OjisanPuzzleArt.pose(for: .severe) == .severe)
    }
}
