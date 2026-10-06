import Foundation
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
/// - たんこぶ: ヘルメットの上に当たった瞬間ぷくっと膨らむ。見た目はモックのピンクの球（下側の濃い色・上の光り・輪郭なし）。次の球の構えでも残す（`HomerunFaceMark.waitingLump`）。
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
        // 当たるまでは振り抜き・球待ちの姿勢のまま（補正すると振りの最中に体全体が横へずれ、バットが打点から外れる）。
        guard e >= impactDelay else { return .zero }
        let held = HomerunWhiffGag.head(atClipTime: HomerunBatterMotion.loadDuration + HomerunBatterMotion.swingDuration).position
        let now = HomerunWhiffGag.head(atClipTime: HomerunBatterMotion.loadDuration + segmentTime(effective: e)).position
        let since = Float(smoothstep((e - impactDelay) / 0.8))
        return [-(now.x - held.x), 0, -(now.z - held.z) - sitOutward * since]
    }

    /// ぐるぐる目・星の回転を数えるクリップ時刻（秒）: 骨のクリップは最後のコマで止まるが、目・星は止めずに回し続ける。
    static func overlayClipTime(effective e: TimeInterval) -> TimeInterval {
        HomerunBatterMotion.loadDuration + (e >= impactDelay ? resumeSegment + (e - impactDelay) : segmentTime(effective: e))
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

    // MARK: たんこぶの絵（モックの見た目に戻す・会長判定 2026-10-04「デザインは前（モック）の方が良かった」）

    /// ピンクの球の色（RGB 0〜1）と、下側の濃い色（陰の代わり）・上の光り。いずれも光を受けない平らな色（Unlit）。輪郭は付けない。
    static let lumpPink: SIMD3<Float> = [1.0, 0.50, 0.62]
    static let lumpUnderside: SIMD3<Float> = [0.86, 0.22, 0.36]
    static let lumpShine: SIMD3<Float> = [1.0, 0.92, 0.95]
    /// 下側の濃い球（ピンクの球の局所・半径 1 の単位）: 少し大きく・下へずらし・上下につぶす。下の縁だけ濃い色がのぞく。
    static let undersideRadius: Float = 1.04
    static let undersideOffset: SIMD3<Float> = [0, -0.18, 0]
    static let undersideScale: SIMD3<Float> = [1, 0.75, 1]
    /// 光りの点（ピンクの球の局所）。頭の向きと一緒に回る。
    static let shineRadius: Float = 0.28
    static let shineOffset: SIMD3<Float> = [-0.35, 0.62, 0.45]

    // MARK: たんこぶの定番の描き込み（会長判定 2026-10-04: 黒い点々・白い十字の絆創膏）
    // いずれもピンクの球の子（局所・半径 1 の単位）なので、球と一緒に膨らみ、次の球の構えでも残る。
    // 球の向きは世界に固定（`placeLump`）なので、局所の +y = 上・+z = カメラの側（投手側）・+x = 一塁側。

    /// 黒い点々を置く面の向き（球の面の点・正規化して使う）。カメラから見える上半分の手前にばらけて置き、光りの点・絆創膏とは重ねない。
    static let dotNormals: [SIMD3<Float>] = [
        [-0.55, 0.30, 0.78], [0.62, 0.28, 0.73], [-0.12, 0.10, 0.99], [0.30, 0.55, 0.78], [0.80, 0.50, 0.33],
    ]
    /// 黒い点 1 つの半径（球の局所）。上下は面に沿ってつぶす（`dotFlatten`）。
    static let dotRadius: Float = 0.06
    static let dotFlatten: Float = 0.5
    /// 絆創膏を貼る面の向き（頂点から少しカメラ側へ）と、1 枚の長さ・幅・厚み（球の局所）、面から浮かせる量、細い輪郭の太さ。
    static let bandageNormal: SIMD3<Float> = simd_normalize([0.05, 0.92, 0.38])
    static let bandageLength: Float = 0.95
    static let bandageWidth: Float = 0.26
    static let bandageThickness: Float = 0.02
    static let bandageLift: Float = 0.03
    static let bandageOutline: Float = 0.035
    /// 2 枚の向き（面の上で回す角度）。直角に重ね、光りの点の方向（約 25°）からどちらも 45° 外して、板が光りの点を隠さないようにする。
    static let bandageAngles: [Float] = [-20 * .pi / 180, 70 * .pi / 180]
}
