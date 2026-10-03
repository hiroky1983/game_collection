import Foundation
import CoreGraphics
import simd

/// 打ち上げた球が自分の頭に落ちてたんこぶができる演出（#1793・会長決裁 2026-10-03。発生条件は `HomerunTankobu`）。
/// 飛距離は 0。見た目は判定（`HomerunJudge`）を変えず、ここの純粋な値で時刻から決める（`HomerunWhiffGag` と同じ作り）。
///
/// 組み立て:
/// - 骨の動き: 通常のスイング → 振り終わり（`holdFrame` = 44 コマ）で球を待つ → 頭に当たったら空振りの演出（`HomerunWhiffGag`）の
///   クリップの `resumeFrame`（50）コマ目から尻もち・座ってぐるぐるを流す。44〜50 コマは同じ姿勢なのでつなぎ目は出ない。
///   体全体の回転は掛けない（真上から球が落ちてきて尻もちをつくだけ）。星・ぐるぐる目は空振りの演出の部品を流用する。
/// - 球: 打点から真上へ上がり、頂点を過ぎて頭のてっぺんへ落ちる（実際の重力の放物線）。当たったら弾んで地面へ転がる。
/// - カメラ（モックの T3）: 一塁側の低い所から打球を見上げ、頂点を過ぎたら球と一緒に下りて、当たる瞬間に斜め上からの見下ろしに着く。
/// - たんこぶ: ヘルメットの上に当たった瞬間ぷくっと膨らみ、トゥーン調の陰影と輪郭を付ける。次の球の構えでも残す（`HomerunFaceMark.waitingLump`）。
///
/// 時刻はすべて「20 コマ目を置いた実時刻（`HomerunBatterMotion.swing` の `start`）からの秒」（`offset`）。ヒットストップ（`hitStop`）は
/// `effective(_:)` で当たる瞬間の時刻を止め、骨・球・カメラ・たんこぶはその時刻で決める。
enum HomerunTankobuGag {
    // MARK: 時間（会長 QA で調整する前提で、ここに集める）

    /// 振り終わり（元のスイングの最後のコマ）で球を待つコマと、当たってから流し始めるコマ（クリップの 1 始まり）。
    static let holdFrame: Double = 44
    static let resumeFrame: Double = 50
    /// 20 コマ目から球が頭に当たるまで（秒・会長決裁: 振ってから約 2.0 秒）。
    static let impactDelay: TimeInterval = 2.0
    /// 当たった瞬間のヒットストップ（秒）。
    static let hitStop: TimeInterval = 0.12
    /// 結果のカードを出すまで（20 コマ目から・秒・会長決裁: 約 3.8 秒）。
    static let cardDelay: TimeInterval = 3.8
    /// 離してから次の球が始まるまで（`HomerunModel.resultDuration`）。20 コマ目は離した時刻とほぼ同じか少し前なので、
    /// 球がバットに当たるまでの最大（`contactLeadMax`）を足しておく。
    static var resultDuration: TimeInterval { HomerunBallChase.contactLeadMax + cardDelay + HomerunBallChase.cardHold }

    /// ヒットストップを入れた時刻。当たる瞬間に `hitStop` 秒だけ止まる。
    static func effective(_ offset: TimeInterval) -> TimeInterval {
        if offset <= impactDelay { return offset }
        return max(impactDelay, offset - hitStop)
    }

    /// 打者の骨のクリップの再生位置（20 コマ目からの秒）。振り終わりまでは元のスイング、当たるまで振り終わりで止まり、
    /// 当たったら `resumeFrame` コマ目から流す。
    static func segmentTime(effective e: TimeInterval) -> TimeInterval {
        let swing = HomerunBatterMotion.swingDuration
        if e < swing { return max(e, 0) }
        if e < impactDelay { return swing }
        return min(resumeSegment + (e - impactDelay), HomerunWhiffGag.clipEnd - HomerunBatterMotion.loadDuration)
    }

    /// `resumeFrame` コマ目の、20 コマ目からの秒。
    static var resumeSegment: TimeInterval { (resumeFrame - 1) / HomerunWhiffGag.frameRate - HomerunBatterMotion.loadDuration }

    /// 当たる瞬間のクリップ時刻（秒・0 = 1 コマ目）。
    static var impactClipTime: TimeInterval { HomerunBatterMotion.loadDuration + resumeSegment }

    // MARK: 頭・たんこぶの位置

    /// ヘルメットの頂上（頭の骨の `headTop` から上へ・m。ヘルメットは頭のてっぺんから見て中心 -0.175・半径 0.29 の球）。
    static let helmetRise: Float = 0.115
    /// たんこぶの中心をヘルメットの頂上から上へ持ち上げる量（m）と、膨らみきったときの半径（m）。打席のカメラは遠い（28m）ので大きめにする。
    static let lumpLift: Float = 0.05
    static let lumpRadius: Float = 0.11

    /// ヘルメットの頂上（打者の局所・クリップ時刻 `t` の頭の骨から）。
    static func helmetTop(atClipTime t: TimeInterval) -> SIMD3<Float> {
        let h = HomerunWhiffGag.head(atClipTime: t)
        return h.position + h.rotation.act(HomerunWhiffGag.headTop + HomerunWhiffGag.headUp * helmetRise)
    }

    /// 構え・踏み込み（1〜20 コマ目）のヘルメットの頂上（打者の局所）。
    static func preSwingHelmetTop(atClipTime t: TimeInterval) -> SIMD3<Float> {
        let h = HomerunWhiffGag.preSwingHead(atClipTime: t)
        return h.position + h.rotation.act(HomerunWhiffGag.headTop + HomerunWhiffGag.headUp * helmetRise)
    }

    /// 球が落ちて当たる点（世界座標）: 振り終わりのヘルメットの頂上。
    static var impactPoint: SIMD3<Float> {
        HomerunAtBatLayout.batterWorld(helmetTop(atClipTime: impactClipTime))
    }

    // MARK: 球

    static let gravity: Float = 9.8
    /// 当たって弾んだ球が地面へ落ちるまで・転がって止まるまで（秒）と、それぞれの水平の動き（m・世界座標・+x が打者の側）。
    static let reboundDuration: TimeInterval = 0.6
    static let reboundBulge: Float = 0.45
    static let reboundTravel: SIMD3<Float> = [0.9, 0, 0.25]
    static let hopDuration: TimeInterval = 0.25
    static let hopBulge: Float = 0.1
    static let hopTravel: SIMD3<Float> = [0.35, 0, 0.05]

    /// 球の中心（世界座標）。`contact` は打点、`contactOffset` はそこに当たった時刻（20 コマ目から・秒）。
    /// 当たってから `impactDelay` まで: 打点から頭のてっぺんへ放物線（水平は等速・上下は実際の重力）。当たった後: 弾んで地面へ。
    static func ballPosition(effective e: TimeInterval, contact: SIMD3<Float>, contactOffset: TimeInterval) -> SIMD3<Float> {
        let target = impactPoint
        let span = max(impactDelay - contactOffset, 0.5)
        if e < impactDelay {
            let u = Float(min(max((e - contactOffset) / span, 0), 1))
            let bulge = gravity * Float(span * span) / 8
            var p = contact + (target - contact) * u
            p.y += 4 * bulge * u * (1 - u)
            return p
        }
        let ground = Float(HomerunBallChase.ballRadius)
        let landing = SIMD3<Float>(target.x + reboundTravel.x, ground, target.z + reboundTravel.z)
        let t = e - impactDelay
        if t < reboundDuration {
            let u = Float(t / reboundDuration)
            var p = target + (landing - target) * u
            p.y = target.y + (ground - target.y) * u + 4 * reboundBulge * u * (1 - u)
            return p
        }
        let hopEnd = landing + hopTravel
        let u = Float(min((t - reboundDuration) / hopDuration, 1))
        var p = landing + (hopEnd - landing) * u
        p.y = ground + 4 * hopBulge * u * (1 - u)
        return p
    }

    // MARK: カメラ（モックの T3）

    static let cameraFieldOfView: Float = 46
    /// 見上げる間のカメラの位置（世界座標・一塁側の低い所）。
    static let lowCamera: SIMD3<Float> = [6.5, 0.8, 3.0]
    /// 当たる瞬間の見下ろしのカメラの、頭のてっぺんからの相対位置（斜め上）。
    static let highCameraOffset: SIMD3<Float> = [2.4, 2.8, 3.0]
    /// 頂点を過ぎてからカメラを下ろし始める割合（打点→当たるまでの 0〜1）。T3 は切り替えがやや速かったので、頂点（0.5）の少し手前から
    /// 当たる瞬間までかけてゆっくり下ろす。
    static let descendStart: Double = 0.4
    /// 当たった後、見下ろしの注視点を球から座った打者へ移すのにかける時間（秒）と、その注視点の高さ（m）。
    static let settleTime: TimeInterval = 0.3
    static let settleHeight: Float = 0.9

    private static func smoothstep(_ x: Double) -> Double {
        let k = min(max(x, 0), 1)
        return k * k * (3 - 2 * k)
    }

    /// 打球を追うカメラ 1 コマ（`HomerunBallChase.Frame`）。
    static func frame(effective e: TimeInterval, contact: SIMD3<Float>, contactOffset: TimeInterval) -> HomerunBallChase.Frame {
        let ball = ballPosition(effective: e, contact: contact, contactOffset: contactOffset)
        let span = max(impactDelay - contactOffset, 0.5)
        let u = min(max((e - contactOffset) / span, 0), 1)
        let k = Float(smoothstep((u - descendStart) / (1 - descendStart)))
        let high = impactPoint + highCameraOffset
        let position = lowCamera + (high - lowCamera) * k
        let settle = Float(smoothstep((e - impactDelay) / settleTime))
        let anchor = SIMD3<Float>(impactPoint.x, settleHeight, impactPoint.z)
        let target = ball + (anchor - ball) * settle
        let scale = HomerunBallChase.ballScale(distance: Double(simd_distance(position, ball)))
        return HomerunBallChase.Frame(
            camera: HomerunAtBatLayout.Camera(position: position, target: target, verticalFieldOfView: cameraFieldOfView),
            ball: ball, ballScale: scale)
    }

    // MARK: 座るときの位置の補正

    /// 回転なしで尻もちを流すと、頭が本塁・捕手側へ約 0.9m 動いて本塁の上に座って見える（#1793）。座るあいだ頭の水平のずれを
    /// 打ち消し（打者の局所・y は 0）、さらに本塁から離れる側（局所の -z = 世界の +x）へ `sitOutward` 離す。支点（`turnPivot`）の位置に足す。
    static let sitOutward: Float = 0.3
    static func sitCorrection(effective e: TimeInterval) -> SIMD3<Float> {
        let held = HomerunWhiffGag.head(atClipTime: HomerunBatterMotion.loadDuration + HomerunBatterMotion.swingDuration).position
        let now = HomerunWhiffGag.head(atClipTime: HomerunBatterMotion.loadDuration + segmentTime(effective: e)).position
        let since = Float(smoothstep((e - impactDelay) / 0.8))
        return [-(now.x - held.x), 0, -(now.z - held.z) - sitOutward * since]
    }

    // MARK: たんこぶ

    /// 膨らみ（0 → `swellOvershoot` → 1）: 当たった瞬間から `swellRise` 秒でぷくっと膨らみすぎ、`swellSettle` 秒で元の大きさへ落ち着く。
    static let swellOvershoot: Float = 1.35
    static let swellRise: TimeInterval = 0.12
    static let swellSettle: TimeInterval = 0.35
    static func swell(since t: TimeInterval) -> Float {
        guard t > 0 else { return 0 }
        if t < swellRise { return swellOvershoot * Float(smoothstep(t / swellRise)) }
        let k = Float(smoothstep((t - swellRise) / swellSettle))
        return swellOvershoot + (1 - swellOvershoot) * k
    }

    /// 構えで残すたんこぶのわずかな脈動（回/秒・振れ幅）。
    static let throbRate: Double = 1.2
    static let throbDepth: Float = 0.03
    static func throb(at t: TimeInterval) -> Float { 1 + throbDepth * Float(sin(t * throbRate * 2 * .pi)) }

    // MARK: たんこぶの絵（トゥーン調の陰影・輪郭）

    /// 球の面（緯度・経度の分割数）。
    static let lumpRings = 12
    static let lumpSegments = 24
    /// 輪郭（反転した少し大きい球）の拡大率。
    static let lumpOutlineScale: Float = 1.14
    /// 絵の大きさ（画素）。
    static let lumpTextureSize = 64
    /// 光の向き（世界座標・上と、カメラ（+z）の側から）。
    static let lumpLight: SIMD3<Float> = simd_normalize([-0.35, 0.8, 0.5])
    /// 面の色（RGB）: 明るい面・ふつうの面・影の面。
    static let lumpHighlight: SIMD3<UInt8> = [255, 205, 196]
    static let lumpBase: SIMD3<UInt8> = [244, 140, 128]
    static let lumpShade: SIMD3<UInt8> = [196, 90, 94]
    /// 明るい面・影の面に入る光の強さ（光の向きとの内積）の境目。
    static let highlightThreshold: Float = 0.72
    static let shadeThreshold: Float = 0.05

    /// 球の面の点 `n`（単位ベクトル・世界座標）の色。3 段（明・中・影）のトゥーン。
    static func lumpColor(normal n: SIMD3<Float>) -> SIMD3<UInt8> {
        let d = simd_dot(n, lumpLight)
        if d >= highlightThreshold { return lumpHighlight }
        if d >= shadeThreshold { return lumpBase }
        return lumpShade
    }

    /// 緯度・経度の球（半径 1）: 頂点・UV（u = 経度・v = 上から下）・三角形。`flipped` は表裏を逆にした輪郭用。
    static func lumpMesh(flipped: Bool) -> (positions: [SIMD3<Float>], uvs: [SIMD2<Float>], indices: [UInt32]) {
        var positions: [SIMD3<Float>] = [], uvs: [SIMD2<Float>] = [], indices: [UInt32] = []
        for r in 0...lumpRings {
            let v = Float(r) / Float(lumpRings)
            let theta = v * .pi
            for s in 0...lumpSegments {
                let u = Float(s) / Float(lumpSegments)
                let phi = u * 2 * .pi
                positions.append([sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi)])
                uvs.append([u, v])
            }
        }
        let row = UInt32(lumpSegments + 1)
        for r in 0..<lumpRings {
            for s in 0..<lumpSegments {
                let a = UInt32(r) * row + UInt32(s), b = a + 1, c = a + row, d = c + 1
                indices += flipped ? [a, c, b, b, c, d] : [a, b, c, b, d, c]
            }
        }
        return (positions, uvs, indices)
    }

    /// 絵の画素（RGBA・左上から行ごと）。画素の (u, v) に対応する球の点の向きから色を決める。
    static func lumpPixels() -> [UInt8] {
        let n = lumpTextureSize
        var bytes = [UInt8](repeating: 255, count: n * n * 4)
        for py in 0..<n {
            let theta = (Float(py) + 0.5) / Float(n) * .pi
            for px in 0..<n {
                let phi = (Float(px) + 0.5) / Float(n) * 2 * .pi
                let c = lumpColor(normal: [sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi)])
                let o = (py * n + px) * 4
                bytes[o] = c.x; bytes[o + 1] = c.y; bytes[o + 2] = c.z
            }
        }
        return bytes
    }

    static func lumpImage() -> CGImage? {
        let n = lumpTextureSize
        let provider = CGDataProvider(data: Data(lumpPixels()) as CFData)
        return provider.flatMap {
            CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                    provider: $0, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
    }
}
