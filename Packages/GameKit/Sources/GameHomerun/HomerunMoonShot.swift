import Foundation
import CoreGraphics
import simd
import HomerunCore

/// 月まで飛ぶ隠し演出（#1680・会長決裁 2026-10-01）の見せ方。打球を追うカメラ（`HomerunBallChase`）の代わりに、当たった瞬間から
/// 次の流れを時刻だけで決める（乱数なし・純粋な値なのでテストで固定する）。
///
/// 1. 打席のカメラのまま球がバットから飛び出す（`HomerunBallChase.cutDelay` まで）
/// 2. 本塁の後ろの低いカメラへ切り替え、上がっていく球を追って**真上へ見上げる**（注視点を球 → 月へ移す）
/// 3. 空が夜空になり（`night`）、星と月が出る。月は遠くの小さな点から、加速しながら画面いっぱいまで迫ってくる（`moonDistance`）。
///    球は逆に遠ざかって小さくなり、月面に吸い込まれて当たる（会長 QA 2026-10-01）。大気圏を抜ける（空が夜になる）ところで
///    球が燃え、オレンジ〜赤の炎と火の尾をまとった火の玉になる（`Fireball`・月の黄土色と夜空の紺の上でも見えるように）
/// 4. 球が月に当たる（`impact`）: 白く光り、月が揺れてヒビが入る（1 回目）。2 回目は続けて月が半分に割れて左右へ離れる
/// 5. 結果のカード（1 回目「月まで飛んだ！ 384,400 km」・2 回目「月が割れた！」と「プレイ回数 +2」）
///
/// 月・夜空・星は打席の 3D（`HomerunAtBatScene3DView`）に足すだけで、新しい `ARView` は作らない。月はクレーターの模様を貼った球
/// （割れた後は半球 2 つ）にインクの輪郭線を付けたトゥーン調（`HomerunMoonArt`）。Meshy は使わない。
enum HomerunMoonShot {
    // MARK: 置き方（世界座標・m）

    /// 見上げるカメラ（本塁の 7m 後ろ・目の高さ）。
    static let cameraPosition: SIMD3<Float> = [0, 1.6, -7]
    /// カメラから月へ向かう向き。本塁の真上寄り（仰角約 75°）で、カメラが「真上へ」向くようにする。真上ちょうどにしないのは、
    /// 注視点がカメラの真上だと見る向きの上下が決まらない（RealityKit の `look(at:)` が上向き +y を使う）ため。
    static let moonDirection: SIMD3<Float> = simd_normalize([0, 498.4, 137])
    /// 当たる瞬間の月の中心までの距離（m）と、月が出た時の距離（遠くの小さな点）。
    static let moonNearDistance: Float = 400
    static let moonFarDistance: Float = 9000
    /// 当たる瞬間の月の中心（ここで当たり、ヒビ・割れもここで見せる）。
    static var moonCenter: SIMD3<Float> { cameraPosition + moonDirection * moonNearDistance }
    /// 月の半径（m）。当たる瞬間（400m・寄った画角 `endFieldOfView`）の縦画面で横幅の約 8 割に映る。
    static let moonRadius: Float = 45

    /// 月の手前の面（カメラ側）の、球が当たる点。カメラから見て月の真ん中に当たる。
    static var impactPoint: SIMD3<Float> {
        moonCenter + simd_normalize(cameraPosition - moonCenter) * moonRadius
    }

    /// 月の向き: 模様の正面（局所の +z・ヒビを描いた面）をカメラへ向ける。回す軸は x なので、局所の x は画面の横のまま
    /// （割れた半球は画面の左右へ離れる）。
    static var moonOrientation: simd_quatf {
        simd_quatf(from: [0, 0, 1], to: -moonDirection)
    }

    /// 月が出てから `t` 秒の、カメラから月の中心までの距離（m）。距離を対数で補間し（見かけの大きさが一定の割合で増える）、
    /// その進みを x^1.5 のイーズインにする: 小さな点から途中もじわじわ大きくなり、終わりほど加速して画面いっぱいに迫る
    /// （距離を線形・3 乗で縮めると、見かけの大きさ ∝ 1 / 距離 のため最後の 0.3 秒まで点のままで、急に現れて見えた）。
    static func moonDistance(at t: TimeInterval) -> Float {
        let x = min(max((t - moonAppear) / (impact - moonAppear), 0), 1)
        let k = Float(pow(x, 1.5))
        return moonFarDistance * pow(moonNearDistance / moonFarDistance, k)
    }

    /// `t` 秒の月の中心（当たった後は `moonCenter` のまま）。
    static func moonPosition(at t: TimeInterval) -> SIMD3<Float> {
        cameraPosition + moonDirection * moonDistance(at: t)
    }

    /// 月の見かけの半径（ラジアン・カメラから）。
    static func moonApparentRadius(at t: TimeInterval) -> Float {
        asin(min(moonRadius / moonDistance(at: t), 1))
    }

    // MARK: 時間（当たった瞬間 = 0 秒から）

    /// 球が月に当たるまで（秒）。
    static let impact: TimeInterval = 3.4
    /// 空が夜になり始める・なり切る時刻（秒）。
    static let nightStart: TimeInterval = 0.6
    static let nightEnd: TimeInterval = 1.8
    /// 月が出る時刻（秒）。空が半分ほど暗くなってから出す（昼の空に月が浮かんでいると先に分かってしまう）。
    static let moonAppear: TimeInterval = 1.2
    /// 画角を寄せ始める時刻（秒）と、寄せる前・寄せた後の縦の画角（度）。
    static let zoomStart: TimeInterval = 1.2
    static let startFieldOfView: Float = 46
    static let endFieldOfView: Float = 34
    /// 月へ向かう球の見かけの大きさを、当たる直前にこの割合まで縮める（ふだんの打球の下限 `HomerunBallChase.minApparentRadius`
    /// より小さくし、迫ってくる月との大きさの対比を出す）。縮め始めるのは注視点が月へ移り終えてから。
    static let ballShrinkEnd: Float = 0.45
    /// 球が燃え始める・燃え切る時刻（秒）。空が夜に変わり始める（大気圏を抜ける）のに合わせる。
    static let burnStart: TimeInterval = nightStart
    static let burnFull: TimeInterval = nightStart + 0.5
    /// 火の玉の見かけの半径（ラジアン）。遠ざかっても点にならず、月の上でも見分けられる大きさ。燃え切った時にこの値で、
    /// 当たる直前は `ballShrinkEnd` と同じ割合まで縮める（迫る月との対比）。
    static let fireApparentRadius: Float = 0.014
    /// 火の尾の玉の数（板ポリ・パーティクルは使わず、輪郭線付きの球を並べるだけ）。
    static let trailCount = 6

    /// 火の玉（燃えている球）の 1 コマ。
    struct Fireball: Equatable {
        /// 炎の中心（世界座標）と半径（m）。
        var center: SIMD3<Float>
        var radius: Float
        /// 火の尾の向き（進む向きの逆・単位ベクトル）。
        var trail: SIMD3<Float>
        /// 炎のゆらぎ（0〜1）。
        var flicker: Float
    }

    /// 球の進む向き（打ち出す点 → 月の当たる点）。
    static var flightDirection: SIMD3<Float> {
        simd_normalize(impactPoint - HomerunBallChase.world(HomerunBallChase.start, direction: 0))
    }

    /// 見上げたカメラの画面の下向き（世界座標・月へ向かう向きに垂直）。球はこちら側から月へ昇っていき、火の尾もこちらへ引く
    /// （カメラと球の道がほぼ一直線なので、そのままだと球が月の真ん中に重なって月の点を隠し、火の尾も奥へ伸びて見えない）。
    static var screenDown: SIMD3<Float> {
        let up: SIMD3<Float> = [0, 1, 0]
        return -simd_normalize(up - moonDirection * simd_dot(up, moonDirection))
    }
    /// 球を画面の下側へずらす量（カメラからの距離に対する割合 = 見かけの角・ラジアン）の最大。月が出る頃に最大で、当たる瞬間に 0。
    static let ballDrop: Float = 0.16

    /// `t` 秒の火の玉。燃える前・当たった後は nil。
    static func fireball(at t: TimeInterval) -> Fireball? {
        guard t >= burnStart, let ball = ballPosition(at: t) else { return nil }
        let burn = Float(smoothstep((t - burnStart) / (burnFull - burnStart)))
        let shrink = 1 + (ballShrinkEnd - 1) * Float(smoothstep((t - lookUpEnd) / (impact - lookUpEnd)))
        let flicker = Float(0.5 + 0.5 * sin(t * 37))
        let radius = simd_distance(cameraPosition, ball) * fireApparentRadius * burn * shrink * (0.94 + 0.12 * flicker)
        guard radius > 0 else { return nil }
        return Fireball(center: ball, radius: radius, trail: simd_normalize(screenDown - flightDirection * 0.35), flicker: flicker)
    }
    /// 注視点を球から月へ移し始める・移し終える時刻（秒）。
    static let lookUpStart: TimeInterval = 0.3
    static let lookUpEnd: TimeInterval = 1.6
    /// 当たったときの白い光が消えるまで（秒）と、月が揺れる時間（秒）。
    static let flashDuration: TimeInterval = 0.45
    static let shakeDuration: TimeInterval = 0.5
    /// 2 回目: 当たってから割れ始めるまで（ヒビを見せる）と、離れ切るまで（秒）。
    static let splitDelay: TimeInterval = 0.6
    static let splitDuration: TimeInterval = 1.4
    /// 当たってから結果のカードを出すまで（秒）。2 回目は割れて離れるのを見届けてから。
    static func cardDelayAfterImpact(_ moon: HomerunMoon) -> TimeInterval {
        switch moon {
        case .hit: 1.5
        case .broken: splitDelay + splitDuration + 0.6
        }
    }

    /// 当たった瞬間から結果のカードを出すまで（秒）。
    static func cardDelay(_ moon: HomerunMoon) -> TimeInterval { impact + cardDelayAfterImpact(moon) }

    /// 1 球の結果を見せる時間（`HomerunModel.resultDuration`）: 離してから当たるまでの最大 + カードまで + カードを読む時間。
    /// 2 回目はカードに「挑戦はここまで」「プレイ回数 +2」が増えるので 1 秒長く読ませる。
    static func resultDuration(_ moon: HomerunMoon) -> TimeInterval {
        HomerunBallChase.contactLeadMax + cardDelay(moon) + HomerunBallChase.cardHold + (moon == .broken ? 1 : 0)
    }

    // MARK: 1 コマ

    /// 月・夜空の見え方（打席の 3D に渡す）。
    struct Look: Equatable {
        /// 夜空の濃さ（0 = 昼の空・1 = 夜空）。星も同じ濃さで出す。
        var night: Double
        /// 月を出すか。
        var moonVisible: Bool
        /// ヒビが入っているか（当たった後）。
        var cracked: Bool
        /// 割れて離れる割合（0 = 割れていない・1 = 離れ切った）。1 回目は常に 0。
        var split: Double
        /// 当たったときの白い光（0〜1）。
        var flash: Double
        /// 月の揺れ（世界座標のずれ・m）。
        var shake: SIMD3<Float>
        /// 月の中心（世界座標・揺れの前）。遠くから迫ってくる。
        var moonCenter: SIMD3<Float> = HomerunMoonShot.moonCenter
        /// 燃えている球（大気圏を抜けてから当たるまで）。
        var fire: Fireball? = nil
    }

    static func smoothstep(_ x: Double) -> Double {
        let k = min(max(x, 0), 1)
        return k * k * (3 - 2 * k)
    }

    /// 当たってから `t` 秒の月・夜空。
    static func look(_ moon: HomerunMoon, at t: TimeInterval) -> Look {
        let since = t - impact
        let shakeAmount = since >= 0 && since < shakeDuration ? (1 - since / shakeDuration) : 0
        let shake = SIMD3<Float>(Float(sin(since * 55) * shakeAmount) * moonRadius * 0.04, 0, 0)
        let split = moon == .broken ? smoothstep((since - splitDelay) / splitDuration) : 0
        return Look(night: smoothstep((t - nightStart) / (nightEnd - nightStart)),
                    moonVisible: t >= moonAppear,
                    cracked: since >= 0,
                    split: split,
                    flash: since >= 0 ? max(0, 1 - since / flashDuration) : 0,
                    shake: shake,
                    moonCenter: moonPosition(at: t))
    }

    /// 球の位置（当たった瞬間の打ち出す点から月の当たる点まで。はじめ速く、遠ざかるほどゆっくり見える）。当たった後は nil。
    static func ballPosition(at t: TimeInterval) -> SIMD3<Float>? {
        guard t < impact else { return nil }
        let x = min(max(t / impact, 0), 1)
        let u = Float(1 - pow(1 - x, 2.2))
        let from = HomerunBallChase.world(HomerunBallChase.start, direction: 0)
        let straight = from + (impactPoint - from) * u
        // 画面の下側から月へ昇っていくよう、道を画面の下へふくらませる（打ち出した直後と当たる瞬間は 0）。
        let rise = Float(smoothstep(t / moonAppear)) * Float(1 - smoothstep((t - moonAppear) / (impact - moonAppear)))
        return straight + screenDown * simd_distance(cameraPosition, straight) * ballDrop * rise
    }

    /// 当たってから `t` 秒のコマ（`HomerunBallChase.Frame` の形で返し、打球を追うカメラと同じ道で描く）。
    static func frame(_ moon: HomerunMoon, at t: TimeInterval) -> HomerunBallChase.Frame {
        let ball = ballPosition(at: t)
        let shown = ball ?? impactPoint
        let w = Float(smoothstep((t - lookUpStart) / (lookUpEnd - lookUpStart)))
        let target = shown + (moonPosition(at: t) - shown) * w
        // 画角も月が迫るのに合わせて加速しながら寄せる（イーズイン）。
        let zx = min(max((t - zoomStart) / (impact - zoomStart), 0), 1)
        let fov = startFieldOfView + (endFieldOfView - startFieldOfView) * Float(zx * zx)
        let camera = HomerunAtBatLayout.Camera(position: cameraPosition, target: target, verticalFieldOfView: fov)
        let shrink = 1 + (ballShrinkEnd - 1) * Float(smoothstep((t - lookUpEnd) / (impact - lookUpEnd)))
        let scale = HomerunBallChase.ballScale(distance: Double(simd_distance(cameraPosition, shown))) * shrink
        var look = look(moon, at: t)
        look.fire = fireball(at: t)
        return HomerunBallChase.Frame(camera: camera, ball: shown, ballScale: scale, ballHidden: ball == nil,
                                      moon: look)
    }
}

// MARK: - 月の絵（模様の画像・半球の頂点）

/// 月の見た目の素材（純粋な値）。模様は正距円筒の画像（横 = 経度・縦 = 緯度）で、頂点の uv は `HomerunMoonMesh` が同じ式で振る。
enum HomerunMoonArt {
    static let textureWidth = 512
    static let textureHeight = 256
    /// 地の色（淡い黄）・クレーターの中・クレーターの縁・ヒビ（インク）・割れた断面。
    static let surface: (UInt8, UInt8, UInt8) = (0xF6, 0xE9, 0xAE)
    static let craterFill: (UInt8, UInt8, UInt8) = (0xDD, 0xC9, 0x80)
    static let craterRim: (UInt8, UInt8, UInt8) = (0xB8, 0xA2, 0x5E)
    static let crack: (UInt8, UInt8, UInt8) = (0x2B, 0x26, 0x34)
    static let core: UInt32 = 0xC98B4A

    /// クレーター（向き・中心から見た角の半径・ラジアン）。乱数なしの固定の並び。正面（+z・カメラ側）にも大小を散らす。
    static let craters: [(direction: SIMD3<Float>, radius: Float)] = [
        (simd_normalize([0.35, 0.45, 0.82]), 0.22), (simd_normalize([-0.42, 0.2, 0.88]), 0.16),
        (simd_normalize([0.1, -0.5, 0.86]), 0.18), (simd_normalize([-0.25, -0.15, 0.95]), 0.08),
        (simd_normalize([0.55, -0.2, 0.8]), 0.1), (simd_normalize([-0.6, -0.55, 0.58]), 0.2),
        (simd_normalize([0.05, 0.8, 0.6]), 0.12), (simd_normalize([0.8, 0.3, 0.5]), 0.14),
        (simd_normalize([-0.85, 0.3, 0.42]), 0.13), (simd_normalize([0.3, -0.85, 0.4]), 0.12),
        (simd_normalize([0, 0.2, -1]), 0.3), (simd_normalize([0.7, 0, -0.7]), 0.2), (simd_normalize([-0.6, 0.5, -0.6]), 0.18),
    ]
    /// クレーターの縁の太さ（中心から見た角・ラジアン）。
    static let rimWidth: Float = 0.025

    /// ヒビ（正面の接平面 (x, y) の折れ線・月の半径 1 の単位）。縦に走る本筋（割れる線 x ≒ 0 に沿う）と枝 3 本。
    static let crackLines: [[SIMD2<Float>]] = [
        [[0.0, 0.95], [0.06, 0.7], [-0.05, 0.45], [0.07, 0.2], [-0.04, 0.0], [0.05, -0.25], [-0.06, -0.5], [0.04, -0.75], [0.0, -0.95]],
        [[0.07, 0.2], [0.3, 0.32], [0.45, 0.25]],
        [[-0.04, 0.0], [-0.28, -0.08], [-0.42, 0.05]],
        [[0.05, -0.25], [0.25, -0.45], [0.3, -0.62]],
    ]
    /// ヒビの太さ（半径 1 の単位）。
    static let crackWidth: Float = 0.022

    /// 画像の点（u, v は 0〜1・v = 0 が上 = +y の極）が指す球面の向き（`HomerunBallSeam.direction` と同じ式）。
    static func direction(u: Float, v: Float) -> SIMD3<Float> {
        let lon = u * 2 * .pi, lat = v * .pi
        return [sin(lat) * cos(lon), cos(lat), sin(lat) * sin(lon)]
    }

    static func distance(_ p: SIMD2<Float>, toSegment a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let ab = b - a
        let k = min(max(simd_dot(p - a, ab) / max(simd_dot(ab, ab), 1e-6), 0), 1)
        return simd_distance(p, a + ab * k)
    }

    /// その向きがヒビの上か（正面の半球だけ）。
    static func isCrack(_ d: SIMD3<Float>) -> Bool {
        guard d.z > 0.2 else { return false }
        let p = SIMD2(d.x, d.y)
        return crackLines.contains { line in
            zip(line, line.dropFirst()).contains { distance(p, toSegment: $0, $1) < crackWidth }
        }
    }

    /// その向きの色。
    static func color(_ d: SIMD3<Float>, cracked: Bool) -> (UInt8, UInt8, UInt8) {
        if cracked, isCrack(d) { return crack }
        for c in craters {
            let angle = acos(min(max(simd_dot(d, c.direction), -1), 1))
            if angle < c.radius - rimWidth { return craterFill }
            if angle < c.radius { return craterRim }
        }
        return surface
    }

    /// 画像の画素（RGBA・左上から行ごと）。
    static func pixels(cracked: Bool) -> [UInt8] {
        var bytes = [UInt8](repeating: 255, count: textureWidth * textureHeight * 4)
        for y in 0..<textureHeight {
            for x in 0..<textureWidth {
                let d = direction(u: (Float(x) + 0.5) / Float(textureWidth), v: (Float(y) + 0.5) / Float(textureHeight))
                let c = color(d, cracked: cracked)
                let o = (y * textureWidth + x) * 4
                bytes[o] = c.0; bytes[o + 1] = c.1; bytes[o + 2] = c.2
            }
        }
        return bytes
    }

    static func image(cracked: Bool) -> CGImage? {
        let provider = CGDataProvider(data: Data(pixels(cracked: cracked)) as CFData)
        return provider.flatMap {
            CGImage(width: textureWidth, height: textureHeight, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: textureWidth * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                    provider: $0, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
    }

    // MARK: 夜空の星

    /// 星（画面の割合の位置 0〜1・半径 pt）。乱数なしの固定の並び（線形合同法の決まった列）。
    static let stars: [(x: Double, y: Double, radius: Double)] = {
        var seed: UInt32 = 1680
        func next() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed >> 8) / Double(1 << 24)
        }
        return (0..<90).map { _ in (next(), next(), 0.6 + next() * 1.4) }
    }()
}

/// 月の球・半球の頂点（RealityKit に依存しない値）。uv は正距円筒（`HomerunMoonArt.direction` と同じ向き）。
struct HomerunMoonMesh: Equatable {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    /// 球面のうち経度 `fromLon`〜`toLon`（ラジアン）の部分。全周（0〜2π）で球、半周で半球の殻。
    /// x = sinθ cosφ なので、φ が −π/2〜π/2 なら x ≥ 0 の半分、π/2〜3π/2 なら x ≤ 0 の半分。
    static func shell(radius r: Float, fromLon: Float = 0, toLon: Float = 2 * .pi, rings: Int = 24, segments: Int = 48) -> HomerunMoonMesh {
        var m = HomerunMoonMesh()
        for i in 0...rings {
            let theta = Float(i) / Float(rings) * .pi
            for j in 0...segments {
                let phi = fromLon + (toLon - fromLon) * Float(j) / Float(segments)
                let n = SIMD3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
                m.positions.append(n * r)
                m.normals.append(n)
                var u = phi / (2 * .pi)
                u -= floor(u)
                // 経度の継ぎ目（u が 1 → 0 に戻る）を跨がないよう、範囲の終わりは 1 のままにする。
                if j == segments, u == 0, toLon > fromLon { u = 1 }
                // RealityKit の uv は左下が原点（画像の上 = v 1）。
                m.uvs.append(SIMD2(u, 1 - theta / .pi))
            }
        }
        let columns = segments + 1
        for i in 0..<rings {
            for j in 0..<segments {
                let a = UInt32(i * columns + j), b = a + 1, c = a + UInt32(columns), e = c + 1
                // 外向き（表が外）: 北（i）→ 南（i + 1）・φ が増える向きで、外から見て反時計回り。
                m.indices += [a, b, c, b, e, c]
            }
        }
        return m
    }

    /// 半球の断面（x = 0 の面の円板）。`facingPositiveX` なら +x を向く（x ≤ 0 の半分のふた）。
    static func cap(radius r: Float, facingPositiveX: Bool, segments: Int = 48) -> HomerunMoonMesh {
        var m = HomerunMoonMesh()
        let n: SIMD3<Float> = facingPositiveX ? [1, 0, 0] : [-1, 0, 0]
        m.positions.append(.zero); m.normals.append(n); m.uvs.append([0.5, 0.5])
        for j in 0...segments {
            let a = Float(j) / Float(segments) * 2 * .pi
            m.positions.append([0, cos(a) * r, sin(a) * r]); m.normals.append(n); m.uvs.append([0.5 + cos(a) / 2, 0.5 + sin(a) / 2])
        }
        for j in 0..<UInt32(segments) {
            // 表の向きは (v1 − v0) × (v2 − v0)（`shell` と同じ）。p(a) × p(a + da) は +x を向く。
            m.indices += facingPositiveX ? [0, j + 1, j + 2] : [0, j + 2, j + 1]
        }
        return m
    }

    /// 輪郭線用（反転ハル）: 少し大きくして三角形の巻きを逆にする（`HomerunToonMesh.flipped` と同じ考え方）。
    func outline(scale: Float) -> HomerunMoonMesh {
        var m = self
        m.positions = positions.map { $0 * scale }
        m.normals = normals.map { -$0 }
        var flipped: [UInt32] = []
        flipped.reserveCapacity(indices.count)
        for i in stride(from: 0, to: indices.count, by: 3) {
            flipped.append(contentsOf: [indices[i], indices[i + 2], indices[i + 1]])
        }
        m.indices = flipped
        return m
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// 月まで飛んだ打球（#1680）の夜空と星。打席の 3D の背景（昼の空のグラデーション）の上・3D の下に `amount` の濃さで重ねる。
struct HomerunNightSky: View {
    let amount: Double

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.04, blue: 0.14), Color(red: 0.08, green: 0.10, blue: 0.28),
                                    Color(red: 0.16, green: 0.18, blue: 0.40)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                for star in HomerunMoonArt.stars {
                    let r = star.radius
                    let rect = CGRect(x: star.x * size.width - r, y: star.y * size.height - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(Color(red: 1, green: 0.97, blue: 0.85)))
                }
            }
        }
        .opacity(amount)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
