import CoreGraphics
import Testing
@testable import GameOjisanPuzzle

@Suite("腰痛おじさんパズル: 作業服おじさんのドット絵（#1909）")
struct OjisanPuzzleArtTests {
    @Test("4 コマすべて同梱され、読み込める")
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
    }

    @Test("段階ごとに別のコマ")
    func poseForStage() {
        #expect(OjisanPuzzleArt.pose(for: .easy) == .easy)
        #expect(OjisanPuzzleArt.pose(for: .aching) == .aching)
        #expect(OjisanPuzzleArt.pose(for: .severe) == .severe)
    }
}
