import Foundation
import CoreGraphics
import simd

/// 空振りで回って倒れて目を回す演出（#1681）。振った空振りのときだけ、1 挑戦の 2 回目の空振りは必ず、それ以外は
/// 空振りの約 5 回に 1 回出す（会長決裁 2026-10-01）。見た目は試作動画 whiff_full_try2 で決裁（2026-10-02）、
/// よろめきを削って回転の勢いのまま後ろへ尻もちにつなぐ（会長追加指示 2026-10-02）。
///
/// 組み立て（`scratchpad/whiff-app/bake.py` で生成）:
/// - 骨の動き: `HomerunBatter.usdz` のスイング（1〜44 コマ）の後ろに 45〜`lastFrame` コマとして足したクリップ。振り終わりの
///   姿勢から Meshy の「よろけて後ろへ尻もち → 座って頭をぐるぐる」へ混ぜる。腰の水平移動の固定・上体の起こし・経路の
///   向きと縮尺・首のぐるぐるは試作と同じ補正を焼き込み済み。モデルは複製せず、同じ USDZ の時間を延ばしただけ。
/// - 体全体の回転（約 1.8 回転・減速）と後ろへの傾き: 骨ではなく親の実体のヨー・傾きで足す（`spinYaw`・`lean`）。回転の量は
///   座りきったとき顔が打席のカメラ（センターカメラ）を向く量（649°）。
/// - ぐるぐる目・頭上の星: 頭の骨に合わせて毎コマ置く（`head` の表から）。骨は読まない。
/// - バット・体の影: 表から引いて回転・傾きを掛ける（`HomerunFigureShadow`）。
///
/// 判定（`HomerunJudge`）は変えない。見た目と、結果を見せる時間（`resultDuration`）だけ。純粋な値なのでテストで固定する。
enum HomerunWhiffGag {
    // MARK: 発生

    /// 2 回目以外の空振りで演出を出す確率（約 5 回に 1 回・#1769）。
    static let chance: Double = 1.0 / 5

    /// 1 挑戦の中で `whiffNumber` 回目（1 始まり・振った空振りだけを数える）の空振りで演出を出すか。`roll` は 0 以上 1 未満の乱数。
    static func shows(whiffNumber: Int, roll: Double) -> Bool {
        whiffNumber == 2 || roll < chance
    }

    // MARK: 時間

    static let frameRate: Double = 30
    /// クリップの最後のコマの時刻（秒・0 = 1 コマ目）。
    static var clipEnd: TimeInterval { Double(lastFrame - 1) / frameRate }
    /// 振り抜きの頭（20 コマ目）から最後のコマまで（秒）。
    static var span: TimeInterval { clipEnd - HomerunBatterMotion.loadDuration }
    /// 座りきった後（クリップの最後のコマで止めて、目と星だけ回す）、次の球まで見せておく時間（秒）。
    static let endHold: TimeInterval = 0.4
    /// 演出を出す空振りの結果の時間（離してから次の球のマシンが込め始めるまで・秒）。振り抜きの頭は離した時刻より前
    /// （`HomerunSwingContact.swingStart`）なので、離した時刻から数えれば座りきるまで次の球を投げない。
    static var resultDuration: TimeInterval { span + endHold }
    /// 結果のカード（「空振り」）を出すまで（離してから・秒）。座り込んだ後に出す（すぐ出すと、回っている頭と星が
    /// カードに隠れた・シミュレータの録画で確認）。座り込むのは 92 コマ目ごろ = 振り抜きの頭から約 2.4 秒。
    static let cardDelay: TimeInterval = 2.4

    // MARK: 体全体の回転と傾き（親の実体）

    /// 振り終わりの姿勢から後ろへ傾ける角（ラジアン・捕手側へ・試作と同じ 7°）と、傾け始め・傾けきり・戻し始め・戻しきりのコマ。
    static let leanAngle: Float = 7 * .pi / 180
    static let leanFrames: (start: Double, full: Double, release: Double, end: Double) = (53.5, 65, 65.5, 77)

    /// クリップ時刻 `t`（秒・0 = 1 コマ目）のコマ番号（1 始まり・小数）。
    static func frame(atClipTime t: TimeInterval) -> Double { t * frameRate + 1 }

    /// 体全体の回転（ラジアン・打者の局所の y まわり）。座ったとき顔が打席のカメラを向く。
    static func spinYaw(atClipTime t: TimeInterval) -> Float {
        let table = frontYaw
        let k = (frame(atClipTime: t) - spinFirstFrame) * 2
        guard k > 0 else { return 0 }
        guard k < Double(table.count - 1) else { return table[table.count - 1] }
        let i = Int(k)
        let a = Float(k - Double(i))
        return table[i] * (1 - a) + table[i + 1] * a
    }

    /// 後ろ（捕手側）への傾き（ラジアン・0 〜 `leanAngle`）。
    static func lean(atClipTime t: TimeInterval) -> Float {
        let f = frame(atClipTime: t)
        let s = { (x: Double) in Float(x * x * (3 - 2 * x)) }
        let k = leanFrames
        if f <= k.start || f >= k.end { return 0 }
        if f < k.full { return leanAngle * s((f - k.start) / (k.full - k.start)) }
        if f < k.release { return leanAngle }
        return leanAngle * (1 - s((f - k.release) / (k.end - k.release)))
    }

    /// 傾ける軸（打者の局所）: 世界の x 軸（打席の置き方のヨーで打者の局所へ戻した向き）。正の角で頭が捕手側（世界の −z）へ倒れる。
    static var leanAxis: SIMD3<Float> {
        simd_quatf(angle: -HomerunAtBatLayout.batter.yaw, axis: [0, 1, 0]).act([-1, 0, 0])
    }

    /// 回転・傾き（親の実体の向き）。支点は `pivot`。
    static func turn(atClipTime t: TimeInterval) -> simd_quatf {
        simd_quatf(angle: lean(atClipTime: t), axis: leanAxis) * simd_quatf(angle: spinYaw(atClipTime: t), axis: [0, 1, 0])
    }

    /// クリップの骨だけの打者の局所の点 `p` を、回転・傾きを掛けた打者の局所へ置く。
    static func place(_ p: SIMD3<Float>, turn: simd_quatf) -> SIMD3<Float> {
        pivot + turn.act(p - pivot)
    }

    // MARK: 表（`HomerunWhiffGag+Samples.swift`）

    /// 表の 1 行の値の数と、表の頭のコマ。
    static let rowWidth = 15
    static let firstTableFrame = 20
    static var tableRows: Int { frames.count / rowWidth }

    /// コマ `f`（小数）の前後の行と混ぜる割合。
    private static func rows(atClipTime t: TimeInterval) -> (Int, Int, Float) {
        let position = min(max(frame(atClipTime: t) - Double(firstTableFrame), 0), Double(tableRows - 1))
        let i0 = Int(position)
        return (i0, min(i0 + 1, tableRows - 1), Float(position - Double(i0)))
    }

    private static func value(_ row: Int, _ column: Int) -> Float { frames[row * rowWidth + column] }

    private static func vector(_ row: Int, _ column: Int) -> SIMD3<Float> {
        [value(row, column), value(row, column + 1), value(row, column + 2)]
    }

    /// バットのグリップ端と先端（クリップの骨だけの打者の局所）。
    static func bat(atClipTime t: TimeInterval) -> (grip: SIMD3<Float>, tip: SIMD3<Float>) {
        let (i0, i1, a) = rows(atClipTime: t)
        return (simd_mix(vector(i0, 0), vector(i1, 0), SIMD3(repeating: a)), simd_mix(vector(i0, 3), vector(i1, 3), SIMD3(repeating: a)))
    }

    /// 体の中心（腰・頭・両足の平均）の、振り抜きの頭（20 コマ目）からの水平のずれ（クリップの骨だけの打者の局所）。
    static func bodyShift(atClipTime t: TimeInterval) -> SIMD3<Float> {
        let (i0, i1, a) = rows(atClipTime: t)
        let x = value(i0, 6) * (1 - a) + value(i1, 6) * a
        let z = value(i0, 7) * (1 - a) + value(i1, 7) * a
        return [x - value(0, 6), 0, z - value(0, 7)]
    }

    /// 頭の骨の位置・向き（クリップの骨だけの打者の局所）。
    static func head(atClipTime t: TimeInterval) -> (position: SIMD3<Float>, rotation: simd_quatf) {
        let (i0, i1, a) = rows(atClipTime: t)
        func q(_ i: Int) -> simd_quatf { simd_quatf(ix: value(i, 11), iy: value(i, 12), iz: value(i, 13), r: value(i, 14)) }
        return (simd_mix(vector(i0, 8), vector(i1, 8), SIMD3(repeating: a)), simd_slerp(q(i0), q(i1), a))
    }

    /// 構え〜踏み込み（クリップの 0〜19/30 秒 = 1〜20 コマ目）の頭の骨の位置・向き（#1762・`HomerunWhiffGag+PreSwingSamples.swift`）。
    static func preSwingHead(atClipTime t: TimeInterval) -> (position: SIMD3<Float>, rotation: simd_quatf) {
        let rows = preSwingHead.count / preSwingHeadRowWidth
        let position = min(max(frame(atClipTime: t) - 1, 0), Double(rows - 1))
        let i0 = Int(position), i1 = min(i0 + 1, rows - 1), a = Float(position - Double(i0))
        func v(_ row: Int, _ column: Int) -> Float { preSwingHead[row * preSwingHeadRowWidth + column] }
        func p(_ i: Int) -> SIMD3<Float> { [v(i, 0), v(i, 1), v(i, 2)] }
        func q(_ i: Int) -> simd_quatf { simd_quatf(ix: v(i, 3), iy: v(i, 4), iz: v(i, 5), r: v(i, 6)) }
        return (simd_mix(p(i0), p(i1), SIMD3(repeating: a)), simd_slerp(q(i0), q(i1), a))
    }

    /// 構え〜踏み込みの目の飾り `index`（0 = 左・1 = 右）の置き方（打者の局所・+z が顔の外）。
    static func preSwingEyePose(atClipTime t: TimeInterval, index: Int) -> (position: SIMD3<Float>, rotation: simd_quatf) {
        let h = preSwingHead(atClipTime: t)
        let mount = eyeMounts[index]
        return (h.position + h.rotation.act(mount.position), h.rotation * mount.rotation)
    }

    // MARK: ぐるぐる目・頭上の星

    /// 目の飾りの半径（m・白地 + 黒の縁）。縁の外径は `eyeRadius * eyeRimScale`。
    static let eyeRadius: Float = 0.045
    static let eyeRimScale: Float = 1.18
    /// 目が出始めるコマ・広がりきるまで（秒）・渦の回る速さ（回/秒・時計回り）。
    static let eyeInFrame: Double = 51.5
    static let eyeGrow: TimeInterval = 0.15
    static let eyeTurnsPerSecond: Double = 1.6
    /// 星が出始めるコマ・広がりきるまで（秒）・頭の周りを回る速さ（回/秒）・回る半径（m）・頭のてっぺんからの高さ（m）。
    static let starInFrame: Double = 55.5
    static let starGrow: TimeInterval = 0.2
    static let starTurnsPerSecond: Double = 1.3
    static let starOrbitRadius: Float = 0.26
    static let starLift: Float = 0.10
    static let starCount = 3
    /// 星の外側の半径（m）。打席のカメラは遠い（28m）ので大きめ（試作と同じ）。
    static let starSize: Float = 0.10

    /// 出始めから `grow` 秒で 0 → 1。
    static func appear(atClipTime t: TimeInterval, from frame: Double, grow: TimeInterval) -> Float {
        let since = t - (frame - 1) / frameRate
        return Float(min(max(since / grow, 0), 1))
    }

    /// 目の渦の回転（ラジアン・飾りの +z まわり）。
    static func eyeSpin(atClipTime t: TimeInterval) -> Float {
        let since = max(t - (eyeInFrame - 1) / frameRate, 0)
        return -Float((since * eyeTurnsPerSecond).truncatingRemainder(dividingBy: 1) * 2 * .pi)
    }

    /// 星 `index` の頭の周りの角（ラジアン）。
    static func starAngle(atClipTime t: TimeInterval, index: Int) -> Float {
        let since = t - (starInFrame - 1) / frameRate
        return Float((since * starTurnsPerSecond).truncatingRemainder(dividingBy: 1) * 2 * .pi) + Float(index) * 2 * .pi / Float(starCount)
    }

    /// 星 `index` の中心（回転・傾きを掛けた打者の局所）。頭のてっぺんの上を、頭の上向きに垂直な面で回る。
    static func starCenter(atClipTime t: TimeInterval, index: Int, turn: simd_quatf) -> SIMD3<Float> {
        let h = head(atClipTime: t)
        let top = place(h.position + h.rotation.act(headTop), turn: turn)
        let up = simd_normalize((turn * h.rotation).act(headUp))
        let center = top + up * starLift
        let ref: SIMD3<Float> = abs(up.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        let ax = simd_normalize(simd_cross(up, ref))
        let ay = simd_cross(up, ax)
        let angle = starAngle(atClipTime: t, index: index)
        return center + (ax * cos(angle) + ay * sin(angle)) * starOrbitRadius
    }

    /// 目の飾り `index`（0 = 左・1 = 右）の置き方（回転・傾きを掛けた打者の局所・+z が顔の外）。
    static func eyePose(atClipTime t: TimeInterval, index: Int, turn: simd_quatf) -> (position: SIMD3<Float>, rotation: simd_quatf) {
        let h = head(atClipTime: t)
        let mount = eyeMounts[index]
        return (place(h.position + h.rotation.act(mount.position), turn: turn), turn * h.rotation * mount.rotation)
    }

    // MARK: 目の絵（白地に黒の渦巻き・黒の縁）

    /// 目の絵の大きさ（正方形・画素）。
    static let eyeTextureSize = 128
    /// 渦の巻き数・内側と外側の半径（`eyeRadius` を 1 とする）・太さ（外側ほど太い）。
    static let swirlTurns: Float = 2.6
    static let swirlInner: Float = 0.076
    static let swirlOuter: Float = 0.874
    static let swirlWidth: Float = 0.24

    /// 目の絵の点（`eyeRadius` を 1 とする中心からの位置）が黒か。縁（1〜`eyeRimScale`）と渦の帯が黒、それ以外は白。
    static func isInk(x: Float, y: Float) -> Bool {
        let r = (x * x + y * y).squareRoot()
        if r >= 1 { return true }
        let b = (swirlOuter - swirlInner) / (swirlTurns * 2 * .pi)
        var phi = atan2(y, x)
        if phi < 0 { phi += 2 * .pi }
        var k: Float = 0
        while k <= swirlTurns {
            let theta = phi + 2 * .pi * k
            if theta <= swirlTurns * 2 * .pi {
                let along = theta / (swirlTurns * 2 * .pi)
                let rs = swirlInner + b * theta
                if abs(r - rs) < swirlWidth * (0.55 + 0.45 * along) / 2 { return true }
            }
            k += 1
        }
        return false
    }

    /// 目の絵の画素（RGBA・左上から行ごと）。絵の端 = 縁の外径（`eyeRimScale`）。
    static func eyePixels() -> [UInt8] {
        let n = eyeTextureSize
        var bytes = [UInt8](repeating: 255, count: n * n * 4)
        for py in 0..<n {
            for px in 0..<n {
                let x = ((Float(px) + 0.5) / Float(n) * 2 - 1) * eyeRimScale
                let y = (1 - (Float(py) + 0.5) / Float(n) * 2) * eyeRimScale
                if isInk(x: x, y: y) {
                    let o = (py * n + px) * 4
                    bytes[o] = 20; bytes[o + 1] = 20; bytes[o + 2] = 26
                }
            }
        }
        return bytes
    }

    static func eyeImage() -> CGImage? {
        let n = eyeTextureSize
        let provider = CGDataProvider(data: Data(eyePixels()) as CFData)
        return provider.flatMap {
            CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                    provider: $0, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
    }
}
