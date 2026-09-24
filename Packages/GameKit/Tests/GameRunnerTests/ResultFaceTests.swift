import Core
import Testing
@testable import GameRunner

/// リザルト・スタート画面に出すおじさんの表情（#702）。View の `switch` に埋めず純関数にしてあるので、
/// 「クリアはガッツポーズ・ミスはしかめ面・自己ベスト更新は喜ぶ」を機械で固定する。
@Suite("チャリンコおじさんのリザルトの表情")
struct RunnerResultFaceTests {
    @Test("クリア・全面クリアはガッツポーズ、ミスはしかめ面、スタート前は笑顔")
    func facesPerPhase() {
        #expect(RunnerResultFace.face(for: .ready) == .smile)
        #expect(RunnerResultFace.face(for: .cleared) == .cheer)
        #expect(RunnerResultFace.face(for: .allCleared) == .cheer)
        #expect(RunnerResultFace.face(for: .failed) == .frown)
    }

    @Test("走行中・一時停止・落下演出中は顔を出さない")
    func noFaceWhilePlaying() {
        for phase in [RunnerPhase.running, .paused, .falling] {
            #expect(RunnerResultFace.face(for: phase) == nil, "\(phase)")
            #expect(RunnerResultFace.face(for: phase, isNewBest: true) == nil, "\(phase)")
        }
    }

    @Test("エンドレスのミスは自己ベスト更新ならガッツポーズ、そうでなければしかめ面")
    func endlessMissHonorsNewBest() {
        #expect(RunnerResultFace.face(for: .failed, isNewBest: true) == .cheer)
        #expect(RunnerResultFace.face(for: .failed, isNewBest: false) == .frown)
        // クリア側は自己ベストの有無で変わらない。
        #expect(RunnerResultFace.face(for: .cleared, isNewBest: true) == .cheer)
        #expect(RunnerResultFace.face(for: .allCleared, isNewBest: false) == .cheer)
    }

    @Test("顔の倍率は整数で、コースの高さの 2 割に収まる最大の倍率（2〜4 倍）")
    func dotScaleFollowsCourseHeight() {
        // iPhone 15 級（コース高 320pt 以上）は 4 倍 = 64pt。
        #expect(RunnerResultFace.dotScale(forCourseHeight: 320) == 4)
        #expect(RunnerResultFace.dotScale(forCourseHeight: 394) == 4)
        #expect(RunnerResultFace.dotScale(forCourseHeight: 1000) == 4, "iPad でも 4 倍で止める")
        // iPhone SE 級（240〜319pt）は 3 倍 = 48pt。
        #expect(RunnerResultFace.dotScale(forCourseHeight: 319) == 3)
        #expect(RunnerResultFace.dotScale(forCourseHeight: 240) == 3)
        // それより低くても 2 倍 = 32pt は確保する。`GeometryReader` が最初に渡す 0 でも落ちない。
        #expect(RunnerResultFace.dotScale(forCourseHeight: 239) == 2)
        #expect(RunnerResultFace.dotScale(forCourseHeight: 0) == 2)
        // 顔の一辺（16 ドット × 倍率）はコースの高さの 2 割を超えない（2 倍の下限を除く）。
        for height in stride(from: 240.0, through: 600.0, by: 7) {
            let scale = RunnerResultFace.dotScale(forCourseHeight: height)
            #expect(Double(OjisanPixel.faceDotSize.width / OjisanPixel.faceResolution * scale) <= height * 0.2, "高さ \(height)")
        }
        #expect(RunnerResultFace.startDotScale == 2, "スタート画面の笑顔は 2 倍 = 32pt")
    }
}
