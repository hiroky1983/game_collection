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

    // #1668 会長 QA（2026-10-01）: 体の影だけでバットの影が無かった。
    @Test("バットの影: 真上から見ると、地面へ落としたバットの線分を覆う細長い楕円（向きはバットに沿う）。立てたバットは手元の小さな影")
    func batShadowFollowsTheBat() {
        let overhead: SIMD3<Float> = [0, 100, 0]
        let flat = Shadow.bat(grip: [0.6, 1.0, 0.2], tip: [-0.2, 1.0, 0.2], camera: overhead)
        #expect(abs(flat.center.x - 0.2) < 1e-4 && abs(flat.center.z - 0.2) < 1e-4)
        #expect(flat.center.y == HomerunBallShadow.infieldClearance)
        #expect(abs(flat.size.y - (0.8 + Shadow.batWidth)) < 1e-3 && abs(flat.size.x - Shadow.batWidth) < 1e-3)
        // 縦（局所 z）が -x を向く: (sin yaw, cos yaw) = (-1, 0)。
        #expect(abs(sin(flat.yaw) + 1) < 1e-4 && abs(cos(flat.yaw)) < 1e-4)
        let upright = Shadow.bat(grip: [0.4, 1.0, 0], tip: [0.4, 1.8, 0.01], camera: overhead)
        #expect(upright.size.y < Shadow.batWidth + 0.02, "立てたバットの影は短い \(upright.size.y)")
    }

    @Test("バットの影: 低い前のカメラでは、視線に沿う太さを体の影と同じ割合で伸ばす（横向きのバットが線につぶれない）")
    func batShadowStretchesForLowCamera() {
        let eye = Layout.CameraPreset.front.camera.renderPose.position
        let across = Shadow.bat(grip: [0.6, 1.0, 0.2], tip: [-0.2, 1.0, 0.2], camera: eye)
        let body = Shadow.batter(origin: Layout.batter.position, camera: eye)
        #expect(body.stretch > 2)
        // 横向き（視線にほぼ直交）のバット: 長さはほぼそのまま、太さは視線に沿うので伸びる。
        #expect(abs(across.size.y - (0.8 + Shadow.batWidth)) < 0.1)
        #expect(across.size.x > Shadow.batWidth * body.stretch * 0.8, "太さ \(across.size.x)")
    }
}
