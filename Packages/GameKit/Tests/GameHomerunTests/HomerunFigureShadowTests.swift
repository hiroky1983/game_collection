import Testing
import Foundation
import simd
@testable import HomerunCore
@testable import GameHomerun

@Suite("柵越えおじさんの打者・マシンの影（#1653）")
struct HomerunFigureShadowTests {
    typealias Shadow = HomerunFigureShadow
    typealias Layout = HomerunAtBatLayout

    @Test("打者の影は腰の真下（本来の位置で x ≈ 0.40・z ≈ −0.08）の、白線の上（0.09m）に置く")
    func batterUnderHips() {
        let s = Shadow.batter(origin: Layout.batter.position, camera: [0, 100, 0])
        #expect(abs(s.center.x - 0.40) < 1e-4)
        #expect(abs(s.center.z - (-0.08)) < 1e-4)
        #expect(s.center.y == HomerunBallShadow.infieldClearance)
        #expect(s.radius == Shadow.batterRadius)
    }

    @Test("後ろのカメラの構えで外・捕手側へずらした打者にも、影が同じだけ付いて動く")
    func batterFollowsSlide() {
        let camera = Layout.CameraPreset.back.camera.renderPose.position
        let offset = Layout.batterOffset(slide: Layout.backStanceSlide)
        let base = Shadow.batter(origin: Layout.batter.position, camera: camera)
        let slid = Shadow.batter(origin: Layout.batter.position + offset, camera: camera)
        #expect(simd_length((slid.center - base.center) - offset) < 1e-5)
    }

    @Test("影の色・質感は球の影と同じ段のマテリアル（インク色の半透明）")
    func sameLookAsBall() {
        let step = HomerunBallShadow.opacityStep(Shadow.opacity)
        #expect(step > 0 && step < HomerunBallShadow.opacitySteps)
    }

    @Test("前・後ろのカメラとも、画面で線にならない楕円（横 : 縦 ≥ 2 : 1 相当）に伸ばし、奥行きは両足の幅（0.57m）を覆う")
    func notALineFromLowCameras() {
        for preset in Layout.CameraPreset.allCases {
            let camera = preset.camera
            let eye = camera.renderPose.position
            let s = Shadow.batter(origin: Layout.batter.position, camera: eye)
            let toShadow = s.center - eye
            let sinElevation = -toShadow.y / simd_length(toShadow)
            // 画面の縦の長さ ≒ 奥行き × sin(見下ろす角)。横に対する比が screenAspect 以上（上限の伸ばしに当たらない範囲）。
            let aspect = s.stretch * sinElevation
            #expect(aspect >= HomerunBallShadow.screenAspect - 1e-4, "\(preset)")
            #expect(s.radius * s.stretch >= 0.57 / 2, "\(preset)")
        }
    }

    @Test("鏡映するカメラ（後ろ）では描画のカメラ（x を鏡映した位置）から見た向きへ伸ばす")
    func mirroredCameraUsesRenderPose() {
        let back = Layout.CameraPreset.back.camera
        #expect(back.mirrored)
        let eye = back.renderPose.position
        let s = Shadow.batter(origin: Layout.batter.position, camera: eye)
        let dir = simd_normalize(SIMD2(s.center.x - eye.x, s.center.z - eye.z))
        #expect(abs(sin(s.yaw) - dir.x) < 1e-4)
        #expect(abs(cos(s.yaw) - dir.y) < 1e-4)
    }

    @Test("マシンの影はマウンドの上（0.3m + 0.03m）の台の真下に、台より一回り大きく置く")
    func machineOnMound() {
        let s = Shadow.machine(camera: [0, 100, 17.6])
        #expect(s.center == [0, HomerunBallShadow.moundHeight + HomerunBallShadow.moundClearance, 17.6])
        #expect(s.radius > 0.4)
        #expect(s.stretch == 1)
    }
}
