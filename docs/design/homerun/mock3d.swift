// 柵越えおじさん（プレミアム枠・ホームラン案）の 3D モック生成器（#1316・3 回目）。
// macOS 上で `swiftc -O mock3d.swift -o mock3dbin && ./mock3dbin <出力ディレクトリ>` で、
// SceneKit の図形合成（球・カプセル・箱・円柱）+ トゥーン陰影 + 輪郭線（反転ハル）で描いた PNG を書き出す。
// アプリのビルドには一切使わない使い捨て。外部の 3D モデル・画像・フォント資産は使っていない
// （= 「社内で 0 円でできる 3D の上限」を見るための叩き台）。
// 出力は mock.swift が読み込んで iPhone 実寸の画面モックに組む（31〜36）。
import AppKit
import Metal
import SceneKit
import simd

// MARK: - パレット（mock.swift / Core の OjisanPixel と同じ色）

func col(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
enum P {
    static let ink = col(0x2B2634), skin = col(0xF2C8A0), skinDark = col(0xD69E76), white = col(0xFAF6EC)
    static let yellow = col(0xF0C030), navy = col(0x3E4E80), navyDark = col(0x28345C), gray = col(0x9696A2), grayDark = col(0x626270)
    static let eye = col(0x221E28), red = col(0xD43C2C), cheek = col(0xF0A088), wood = col(0xAA763E), woodDark = col(0x7A5228)
    static let uniform = col(0xF4F2F6), mouth = col(0x5E1418), sky = col(0x6CB8E8), glove = col(0x8A5A32)
    static let grass = col(0x4FA653), grassDark = col(0x3F8E45), dirt = col(0xC28C58), dirtDark = col(0xA9743F)
    static let fence = col(0x2F7A4F), fenceDark = col(0x225C3A), track = col(0xB8804C)
    static let crowd: [NSColor] = [0x8C7BE0, 0xFF8FB1, 0x22C3BE, 0xFFC24B, 0xFF6F61, 0xE9E1D6, 0x6C8BD8, 0x9AD0A0].map { col($0) }
}

// MARK: - トゥーン材質と部品

let toonModifier = """
#pragma body
float d = max(0.0, dot(_surface.normal, _light.direction));
float band = d > 0.5 ? 1.0 : (d > 0.18 ? 0.78 : 0.6);
_lightingContribution.diffuse += _light.intensity.rgb * band;
"""

func toon(_ color: NSColor, texture: NSImage? = nil, repeatX: CGFloat = 1, doubleSided: Bool = false) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .lambert
    m.diffuse.contents = texture ?? color
    if texture != nil {
        m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(repeatX, 1, 1)
    }
    m.shaderModifiers = [.lightingModel: toonModifier]
    m.isDoubleSided = doubleSided
    return m
}

func unlit(_ color: NSColor) -> SCNMaterial {
    let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = color; return m
}

/// 図形 1 個 + 輪郭線（反転ハル: 少し大きくして裏面だけ描く）。`outline` は部品の座標系での線の厚み。
func part(_ geo: SCNGeometry, _ color: NSColor, texture: NSImage? = nil, repeatX: CGFloat = 1, outline: CGFloat = 0.05) -> SCNNode {
    geo.materials = [toon(color, texture: texture, repeatX: repeatX)]
    let n = SCNNode(geometry: geo)
    if outline > 0 {
        let o = geo.copy() as! SCNGeometry
        let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = P.ink; m.cullMode = .front
        o.materials = [m]
        let on = SCNNode(geometry: o)
        let (mn, mx) = geo.boundingBox
        let sx = max(mx.x - mn.x, 0.01), sy = max(mx.y - mn.y, 0.01), sz = max(mx.z - mn.z, 0.01)
        on.scale = SCNVector3(1 + 2 * outline / sx, 1 + 2 * outline / sy, 1 + 2 * outline / sz)
        n.addChildNode(on)
    }
    return n
}

func v(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SCNVector3 { SCNVector3(x, y, z) }
func sphere(_ r: CGFloat, _ c: NSColor, at p: SCNVector3, scale: SCNVector3 = SCNVector3(1, 1, 1), outline: CGFloat = 0.05) -> SCNNode {
    let g = SCNSphere(radius: r); g.segmentCount = 48
    let n = part(g, c, outline: outline); n.position = p; n.scale = scale; return n
}
func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ c: NSColor, at p: SCNVector3, radius: CGFloat = 0, outline: CGFloat = 0.05) -> SCNNode {
    let n = part(SCNBox(width: w, height: h, length: d, chamferRadius: radius), c, outline: outline); n.position = p; return n
}
/// 2 点を結ぶカプセル（腕・脚・バット・襟）。ポーズ替えは座標 2 点で済む（2D モックの `limb` と同じ発想）。
func limb(_ a: SCNVector3, _ b: SCNVector3, r: CGFloat, _ c: NSColor, texture: NSImage? = nil, outline: CGFloat = 0.05) -> SCNNode {
    let d = simd_float3(Float(b.x - a.x), Float(b.y - a.y), Float(b.z - a.z))
    let len = CGFloat(simd_length(d))
    let g = SCNCapsule(capRadius: r, height: len + 2 * r); g.capSegmentCount = 24; g.radialSegmentCount = 32
    let n = part(g, c, texture: texture, outline: outline)
    n.position = v((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
    n.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: simd_normalize(d + simd_float3(1e-4, 0, 0)))
    return n
}
/// 円錐台（バット）。`a` が握り、`b` が先端。
func bat(_ a: SCNVector3, _ b: SCNVector3) -> SCNNode {
    let d = simd_float3(Float(b.x - a.x), Float(b.y - a.y), Float(b.z - a.z))
    let len = CGFloat(simd_length(d))
    let g = SCNCone(topRadius: 0.17, bottomRadius: 0.09, height: len); g.radialSegmentCount = 32
    let n = part(g, P.wood)
    n.position = v((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
    n.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: simd_normalize(d + simd_float3(1e-4, 0, 0)))
    let cap = sphere(0.17, P.wood, at: v(0, len / 2, 0)); n.addChildNode(cap)
    let knob = sphere(0.12, P.woodDark, at: v(0, -len / 2, 0)); n.addChildNode(knob)
    return n
}

/// ピンストライプ（ジャージ）。白地に紺の縦線を 1 本描いた画像を横に繰り返す。
let pinstripe: NSImage = {
    let img = NSImage(size: NSSize(width: 32, height: 32))
    img.lockFocus()
    P.uniform.setFill(); NSRect(x: 0, y: 0, width: 32, height: 32).fill()
    P.navy.withAlphaComponent(0.85).setFill(); NSRect(x: 14, y: 0, width: 4, height: 32).fill()
    img.unlockFocus(); return img
}()
/// 芝の刈り筋（濃淡の縞）。
let mowStripes: NSImage = {
    let img = NSImage(size: NSSize(width: 64, height: 64))
    img.lockFocus()
    P.grass.setFill(); NSRect(x: 0, y: 0, width: 64, height: 64).fill()
    P.grassDark.setFill(); NSRect(x: 0, y: 0, width: 64, height: 32).fill()
    img.unlockFocus(); return img
}()

// MARK: - おじさん（頭の半径 = 1 の単位で組み、置くときに縮める）

enum Eyes { case open, closed }
enum Mouth { case smile, open, line }
struct Pose3 {
    let name: String
    var elbowR: SCNVector3, handR: SCNVector3, elbowL: SCNVector3, handL: SCNVector3
    var batTip: SCNVector3? = nil          // nil ならバットは地面（cheer）か無し
    var batOnGround: Bool = false
    var helmetOn = true, capInAir = false, sweat = false
    var eyes = Eyes.open, mouth = Mouth.smile
    var headTilt: CGFloat = 0, bodyYaw: CGFloat = 0
    var batOneHand = false                // 右手だけで持つ（空振りのうなだれ）
    var headPitch: CGFloat = 0            // 負で見上げる
}
let shoulderR = v(0.95, 2.15, 0), shoulderL = v(-0.95, 2.15, 0)
let poses: [Pose3] = [
    Pose3(name: "構え", elbowR: v(1.45, 1.85, 0.4), handR: v(0.95, 2.5, 0.85), elbowL: v(-0.85, 1.55, 0.7), handL: v(0.6, 2.35, 0.95),
          batTip: v(1.75, 4.9, -0.35)),
    Pose3(name: "スイング", elbowR: v(0.55, 1.95, 1.15), handR: v(-0.75, 1.95, 1.35), elbowL: v(-1.05, 2.0, 0.65), handL: v(-1.0, 1.9, 1.25),
          batTip: v(-3.6, 1.75, 1.75), headTilt: -0.15, bodyYaw: -0.35),
    Pose3(name: "柵越え", elbowR: v(1.55, 3.05, 0.3), handR: v(1.5, 4.35, 0.35), elbowL: v(-1.55, 3.05, 0.3), handL: v(-1.5, 4.35, 0.35),
          batOnGround: true, helmetOn: false, capInAir: true, mouth: .open),
    Pose3(name: "空振り", elbowR: v(1.25, 1.55, 0.2), handR: v(1.2, 1.0, 0.45), elbowL: v(-1.25, 1.55, 0.2), handL: v(-1.15, 1.0, 0.45),
          batTip: v(1.6, 0.1, 1.3), sweat: true, eyes: .closed, mouth: .line, headTilt: 0.18, batOneHand: true),
]

enum Outfit { case batter, pitcher }

func ojisan(_ p: Pose3, outfit: Outfit = .batter) -> SCNNode {
    let root = SCNNode()
    // 脚・靴・ストッキング
    for sx: CGFloat in [-0.42, 0.42] {
        root.addChildNode(limb(v(sx, 0.35, 0), v(sx, 1.25, 0), r: 0.34, P.uniform))
        root.addChildNode(limb(v(sx, 0.3, 0), v(sx, 0.62, 0), r: 0.35, P.navy))
        root.addChildNode(box(0.62, 0.3, 0.9, P.eye, at: v(sx, 0.15, 0.12), radius: 0.1))
    }
    // 胴（カプセル・ピンストライプは打者だけ）・ベルト・襟・ボタン
    let torso = SCNNode(); torso.eulerAngles.y = p.bodyYaw
    let tex: NSImage? = outfit == .batter ? pinstripe : nil
    torso.addChildNode(limb(v(0, 1.35, 0), v(0, 2.05, 0), r: 0.88, P.uniform, texture: tex))
    if tex != nil { torso.childNodes.last!.geometry!.firstMaterial!.diffuse.contentsTransform = SCNMatrix4MakeScale(9, 1, 1) }
    torso.addChildNode(limb(v(0, 1.18, 0), v(0, 1.19, 0), r: 0.9, P.navy))          // ベルト
    let buckle = box(0.28, 0.22, 0.12, P.yellow, at: v(0, 1.18, 0.86)); torso.addChildNode(buckle)
    if outfit == .batter {
        torso.addChildNode(limb(v(-0.5, 2.55, 0.62), v(0, 2.1, 0.86), r: 0.075, P.yellow, outline: 0.03))
        torso.addChildNode(limb(v(0.5, 2.55, 0.62), v(0, 2.1, 0.86), r: 0.075, P.yellow, outline: 0.03))
        for y: CGFloat in [1.5, 1.8] { torso.addChildNode(sphere(0.075, P.navy, at: v(0, y, 0.87), outline: 0.02)) }
    } else {
        torso.addChildNode(limb(v(-0.5, 2.55, 0.62), v(0, 2.15, 0.86), r: 0.06, P.navy, outline: 0.02))
        torso.addChildNode(limb(v(0.5, 2.55, 0.62), v(0, 2.15, 0.86), r: 0.06, P.navy, outline: 0.02))
    }
    root.addChildNode(torso)
    // 腕（袖は白・前腕は肌・手は黄のグローブ。投手は左手に茶のグラブ）
    func arm(_ s: SCNVector3, _ e: SCNVector3, _ h: SCNVector3, left: Bool) {
        root.addChildNode(limb(s, e, r: 0.27, P.uniform))
        root.addChildNode(limb(e, h, r: 0.21, P.skin))
        if outfit == .pitcher && left { root.addChildNode(sphere(0.36, P.glove, at: h, scale: SCNVector3(1, 1.1, 0.6))) }
        else if outfit == .pitcher { root.addChildNode(sphere(0.26, P.skin, at: h)) }
        else { root.addChildNode(sphere(0.28, P.yellow, at: h)) }
    }
    arm(shoulderR, p.elbowR, p.handR, left: false)
    arm(shoulderL, p.elbowL, p.handL, left: true)
    // バット
    if let tip = p.batTip {
        let grip = p.batOneHand ? p.handR : v((p.handR.x + p.handL.x) / 2, (p.handR.y + p.handL.y) / 2, (p.handR.z + p.handL.z) / 2)
        let d = simd_normalize(simd_float3(Float(tip.x - grip.x), Float(tip.y - grip.y), Float(tip.z - grip.z)))
        let a = v(grip.x - CGFloat(d.x) * 0.5, grip.y - CGFloat(d.y) * 0.5, grip.z - CGFloat(d.z) * 0.5)
        root.addChildNode(bat(a, tip))
    } else if p.batOnGround {
        root.addChildNode(bat(v(-1.3, 0.14, 1.3), v(1.4, 0.14, 1.7)))
    }
    // 頭（首・頭・耳・側頭の白髪・顔）
    let head = SCNNode(); head.position = v(0, 3.3, 0); head.eulerAngles = SCNVector3(p.headPitch, p.bodyYaw * 0.4, p.headTilt)
    head.addChildNode(sphere(1.0, P.skin, at: v(0, 0, 0)))
    head.addChildNode(limb(v(0, -1.1, 0), v(0, -0.7, 0), r: 0.32, P.skin))
    for sx: CGFloat in [-1, 1] {
        head.addChildNode(sphere(0.2, P.skin, at: v(sx * 0.98, -0.1, 0.05), scale: SCNVector3(0.6, 1, 1)))
        // 側頭の白髪: ヘルメットの縁の下に出る房（球をつぶす。カプセルだと横から見てソーセージに見える）
        head.addChildNode(sphere(0.3, P.gray, at: v(sx * 0.9, -0.04, -0.22), scale: SCNVector3(0.4, 0.5, 0.95), outline: 0.035))
    }
    head.addChildNode(sphere(0.3, P.gray, at: v(0, -0.02, -0.88), scale: SCNVector3(1.6, 0.5, 0.45), outline: 0.035))   // 後頭部の白髪
    // 目・眉・鼻・頬・ヒゲ・口
    for sx: CGFloat in [-1, 1] {
        if p.eyes == .open {
            head.addChildNode(sphere(0.23, P.white, at: v(sx * 0.38, 0.06, 0.85), outline: 0.035))
            head.addChildNode(sphere(0.13, P.eye, at: v(sx * 0.35, 0.04, 1.03), outline: 0))
            head.addChildNode(sphere(0.045, P.white, at: v(sx * 0.3, 0.1, 1.13), outline: 0))
        } else {
            // ＞＜ 目（2 本の短い線をハの字に）
            head.addChildNode(limb(v(sx * 0.2, 0.2, 0.95), v(sx * 0.48, 0.08, 0.9), r: 0.035, P.eye, outline: 0))
            head.addChildNode(limb(v(sx * 0.2, -0.05, 0.95), v(sx * 0.48, 0.08, 0.9), r: 0.035, P.eye, outline: 0))
        }
        let brow = box(0.42, 0.13, 0.12, P.grayDark, at: v(sx * 0.4, 0.4, 0.9), radius: 0.03, outline: 0.03)
        brow.eulerAngles.z = sx * 0.12; head.addChildNode(brow)
        head.addChildNode(sphere(0.2, P.cheek, at: v(sx * 0.66, -0.2, 0.72), scale: SCNVector3(1, 0.8, 0.5), outline: 0))
        head.addChildNode(sphere(0.18, P.gray, at: v(sx * 0.23, -0.32, 0.9), scale: SCNVector3(1.4, 0.55, 0.7), outline: 0.035)) // ヒゲ
    }
    head.addChildNode(sphere(0.13, P.skinDark, at: v(0, -0.12, 1.0), outline: 0.03))
    switch p.mouth {
    case .smile: head.addChildNode(limb(v(-0.18, -0.52, 0.92), v(0.18, -0.52, 0.92), r: 0.04, P.mouth, outline: 0))
    case .line: head.addChildNode(limb(v(-0.14, -0.5, 0.94), v(0.14, -0.5, 0.94), r: 0.035, P.mouth, outline: 0))
    case .open: head.addChildNode(sphere(0.2, P.mouth, at: v(0, -0.5, 0.88), scale: SCNVector3(1, 1.1, 0.5), outline: 0.03))
    }
    // ヘルメット（打者）/ 帽子（投手）
    // ヘルメットの球は中心を少し後ろ（-z）へずらす。すると頭の球との交線が前で高く・横と後ろで低くなり、
    // 顔が開いて耳まで覆う「ヘルメットの形」が図形 1 個で出る（前は仰角 37° あたりが縁になる）
    let helmetC = v(0, 0.35, -0.22)
    func headwear(cap: Bool) -> SCNNode {
        let h = SCNNode()
        h.addChildNode(sphere(cap ? 1.05 : 1.08, P.navy, at: helmetC))
        if !cap {
            // 黄の中央ライン: 前（ツバの上）から頭頂を越えて後方 48° までの弧だけ（全周のトーラスだと横から後光に見える）
            for deg in stride(from: -48.0, through: 118.0, by: 3.5) {
                let a = deg * .pi / 180
                h.addChildNode(sphere(0.075, P.yellow, at: v(0, helmetC.y + 1.09 * cos(a), helmetC.z + 1.09 * sin(a)), outline: 0.025))
            }
            h.addChildNode(box(0.3, 0.55, 0.5, P.navy, at: v(-1.0, -0.15, 0.1), radius: 0.12))              // 左耳（投手側）の耳当て
        }
        // ツバ: 短く厚く、ヘルメットの前の縁から生える角度に
        let brim = part(SCNCylinder(radius: cap ? 0.75 : 0.66, height: 0.13), P.navyDark, outline: 0.03)
        brim.position = v(0, 0.66, cap ? 0.66 : 0.6); brim.eulerAngles.x = 0.28; h.addChildNode(brim)
        return h
    }
    if p.helmetOn { head.addChildNode(headwear(cap: outfit == .pitcher)) }
    else if p.capInAir { let c = headwear(cap: false); c.position = v(1.9, 2.1, -0.2); c.eulerAngles = SCNVector3(0.3, 0.2, 0.9); head.addChildNode(c) }
    if p.sweat { head.addChildNode(sphere(0.13, col(0x6CB8E8), at: v(1.25, 0.55, 0.55), scale: SCNVector3(1, 1.4, 1), outline: 0.03)) }
    root.addChildNode(head)
    return root
}

/// 投手（背中をカメラに向ける。投球の瞬間）。
func pitcherNode() -> SCNNode {
    let p = Pose3(name: "投球", elbowR: v(1.55, 3.3, -0.45), handR: v(1.35, 4.35, -0.75), elbowL: v(-1.35, 2.25, 0.5), handL: v(-1.0, 2.65, 1.15),
                  headTilt: 0.05)
    let n = ojisan(p, outfit: .pitcher)
    return n
}

/// 捕手（正面・しゃがみ）。4 回目（会長決裁 2026-09-24）で社長側参考ブランチの `28-character-3d.jpg` の見え方に寄せた:
/// 白い太ももを左右に開いたしゃがみ・グレーのレガース・紺の胸当て（上に薄い帯）・スカルキャップ + ケージ付きマスク（顔が見える）・
/// 左手（画面右）に大きな茶のミット・右手（画面左）は膝。3 回目の「青い塊に黒い板」は使わない。+z（投手）を向く。
func catcherNode() -> SCNNode {
    let n = SCNNode()
    let pad = col(0x9A9AA6), band = col(0x7A8CC4), cage = col(0xB4B4C0)
    // 脚: 太もも（白）を外へ開き、すね（レガース）は垂直。靴は黒
    for sx: CGFloat in [-1, 1] {
        let hip = v(sx * 0.45, 1.05, 0.1), knee = v(sx * 1.35, 0.95, 0.95), ankle = v(sx * 1.35, 0.25, 1.0)
        n.addChildNode(limb(hip, knee, r: 0.36, P.uniform))
        n.addChildNode(limb(knee, ankle, r: 0.3, P.uniform))
        n.addChildNode(box(0.72, 0.95, 0.5, pad, at: v(sx * 1.35, 0.6, 1.15), radius: 0.2))          // レガース
        n.addChildNode(sphere(0.34, pad, at: knee, scale: SCNVector3(1, 0.9, 0.9)))                    // 膝当て
        n.addChildNode(box(0.66, 0.3, 0.9, P.eye, at: v(sx * 1.35, 0.15, 1.05), radius: 0.1))        // 靴
    }
    // 胴: 胸当て（紺の角丸の箱）と肩の帯（薄い紺）。後ろに白の胴
    n.addChildNode(limb(v(0, 1.0, -0.1), v(0, 1.9, -0.1), r: 0.8, P.uniform))
    n.addChildNode(box(2.2, 1.7, 0.85, P.navy, at: v(0, 1.4, 0.25), radius: 0.36))
    n.addChildNode(box(1.9, 0.42, 0.9, band, at: v(0, 2.05, 0.25), radius: 0.18))
    // 腕: 袖は白・前腕は肌。左手（+x・画面右）は前に出してミット、右手（-x・画面左）は膝に置く
    let shL = v(1.05, 1.95, 0.15), elL = v(1.6, 1.55, 0.75), hdL = v(1.55, 1.65, 1.35)
    n.addChildNode(limb(shL, elL, r: 0.27, P.uniform)); n.addChildNode(limb(elL, hdL, r: 0.21, P.skin))
    let mitt = sphere(0.62, P.glove, at: v(1.55, 1.7, 1.55), scale: SCNVector3(1, 1.05, 0.55)); n.addChildNode(mitt)
    n.addChildNode(sphere(0.4, col(0xD9A070), at: v(1.5, 1.72, 1.86), scale: SCNVector3(0.8, 0.9, 0.12), outline: 0.02))   // ミットのポケット
    let shR = v(-1.05, 1.95, 0.15), elR = v(-1.5, 1.35, 0.55), hdR = v(-1.35, 1.05, 1.0)
    n.addChildNode(limb(shR, elR, r: 0.27, P.uniform)); n.addChildNode(limb(elR, hdR, r: 0.21, P.skin))
    n.addChildNode(sphere(0.27, P.skin, at: hdR))
    // 頭: 肌の球 + 紺のスカルキャップ（中心を上へ = 顔が開く）+ ケージ付きマスク（角丸の枠 + 横棒 3 本 + 縦棒 2 本。顔はケージ越しに見える）
    let head = SCNNode(); head.position = v(0, 2.85, 0)
    head.addChildNode(sphere(1.0, P.skin, at: v(0, 0, 0)))
    head.addChildNode(sphere(1.06, P.navy, at: v(0, 0.42, -0.1)))
    for sx: CGFloat in [-1, 1] {
        head.addChildNode(sphere(0.2, P.white, at: v(sx * 0.36, 0.02, 0.86), outline: 0.03))
        head.addChildNode(sphere(0.11, P.eye, at: v(sx * 0.33, 0.0, 1.02), outline: 0))
        let brow = box(0.36, 0.11, 0.1, P.grayDark, at: v(sx * 0.37, 0.33, 0.9), radius: 0.03, outline: 0.025); head.addChildNode(brow)
    }
    head.addChildNode(sphere(0.12, P.skinDark, at: v(0, -0.16, 1.0), outline: 0.03))
    head.addChildNode(limb(v(-0.15, -0.5, 0.92), v(0.15, -0.5, 0.92), r: 0.035, P.mouth, outline: 0))
    func bar(_ a: SCNVector3, _ b: SCNVector3) -> SCNNode { limb(a, b, r: 0.05, cage, outline: 0.02) }
    let fz: CGFloat = 1.22, fw: CGFloat = 0.78, ft: CGFloat = 0.62, fb: CGFloat = -0.78
    head.addChildNode(bar(v(-fw, ft, fz), v(fw, ft, fz))); head.addChildNode(bar(v(-fw, fb, fz), v(fw, fb, fz)))
    head.addChildNode(bar(v(-fw, ft, fz), v(-fw, fb, fz))); head.addChildNode(bar(v(fw, ft, fz), v(fw, fb, fz)))
    for y: CGFloat in [0.25, -0.15, -0.5] { head.addChildNode(bar(v(-fw, y, fz + 0.02), v(fw, y, fz + 0.02))) }
    for x: CGFloat in [-0.28, 0.28] { head.addChildNode(bar(v(x, ft, fz + 0.02), v(x, fb, fz + 0.02))) }
    // 枠から頭へ戻る側面のバー（マスクが顔に付いて見えるように）
    for sx: CGFloat in [-1, 1] { head.addChildNode(bar(v(sx * fw, ft, fz), v(sx * 0.95, 0.35, 0.35))); head.addChildNode(bar(v(sx * fw, fb, fz), v(sx * 0.9, -0.55, 0.4))) }
    n.addChildNode(head)
    return n
}

/// 審判（捕手の後ろ・前かがみ。チャコールの服・同じケージ付きマスク）。捕手に大半が隠れる「野球らしさ」の部品。+z を向く。
func umpireNode() -> SCNNode {
    let n = SCNNode()
    let ump = col(0x3A3F52), cage = col(0xB4B4C0)
    for sx: CGFloat in [-1, 1] {
        n.addChildNode(limb(v(sx * 0.6, 0.3, -0.2), v(sx * 0.55, 1.6, 0.05), r: 0.36, col(0x6A6E7E)))
        n.addChildNode(box(0.66, 0.3, 0.9, P.eye, at: v(sx * 0.6, 0.15, -0.1), radius: 0.1))
    }
    n.addChildNode(box(2.3, 1.9, 1.1, ump, at: v(0, 2.5, 0.2), radius: 0.5))                           // 前かがみの胴（胸当て込み）
    for sx: CGFloat in [-1, 1] {
        n.addChildNode(limb(v(sx * 1.15, 2.9, 0.3), v(sx * 1.3, 1.85, 0.75), r: 0.25, ump))
        n.addChildNode(sphere(0.26, P.skin, at: v(sx * 1.3, 1.75, 0.8)))
    }
    let head = SCNNode(); head.position = v(0, 3.65, 0.55); head.eulerAngles.x = 0.25
    head.addChildNode(sphere(0.9, P.skin, at: v(0, 0, 0)))
    head.addChildNode(sphere(0.96, ump, at: v(0, 0.4, -0.1)))
    func bar(_ a: SCNVector3, _ b: SCNVector3) -> SCNNode { limb(a, b, r: 0.05, cage, outline: 0.02) }
    let fz: CGFloat = 1.1, fw: CGFloat = 0.7, ft: CGFloat = 0.55, fb: CGFloat = -0.7
    head.addChildNode(bar(v(-fw, ft, fz), v(fw, ft, fz))); head.addChildNode(bar(v(-fw, fb, fz), v(fw, fb, fz)))
    head.addChildNode(bar(v(-fw, ft, fz), v(-fw, fb, fz))); head.addChildNode(bar(v(fw, ft, fz), v(fw, fb, fz)))
    for y: CGFloat in [0.2, -0.15, -0.45] { head.addChildNode(bar(v(-fw, y, fz + 0.02), v(fw, y, fz + 0.02))) }
    n.addChildNode(head)
    return n
}

// MARK: - 球場（メートル。本塁が原点、+z がセンター方向、+x が一塁側）

let charScale: CGFloat = 0.354  // 頭の半径 1 → 0.354m（全身 4.8 → 1.7m）

func fenceRadius(_ deg: Double) -> Double { 100 + 22 * cos(2 * deg * .pi / 180) }   // 両翼 100m・中堅 122m

func arcShape(r0: Double, r1: Double, from a0: Double, to a1: Double) -> SCNShape {
    let path = NSBezierPath()
    func pt(_ r: Double, _ deg: Double) -> NSPoint { NSPoint(x: r * sin(deg * .pi / 180), y: r * cos(deg * .pi / 180)) }
    path.move(to: pt(r0, a0))
    stride(from: a0, through: a1, by: 1.0).forEach { path.line(to: pt(r0, $0)) }
    stride(from: a1, through: a0, by: -1.0).forEach { path.line(to: pt(r1, $0)) }
    path.close()
    let s = SCNShape(path: path, extrusionDepth: 0.02); return s
}
/// 平らな形（NSBezierPath を xz 平面に寝かせる）。
func flat(_ shape: SCNShape, _ c: NSColor, y: CGFloat) -> SCNNode {
    let n = part(shape, c, outline: 0); n.eulerAngles.x = .pi / 2; n.position.y = y; return n   // path の +y → 世界の +z
}

func stadium(withOutfieldDetail: Bool) -> SCNNode {
    let root = SCNNode()
    // 芝（刈り筋）
    let grass = SCNPlane(width: 400, height: 400); grass.widthSegmentCount = 1
    let g = part(grass, P.grass, texture: mowStripes, repeatX: 1, outline: 0)
    g.geometry!.firstMaterial!.diffuse.contentsTransform = SCNMatrix4MakeScale(1, 40, 1)
    g.eulerAngles.x = -.pi / 2; g.position.y = 0; root.addChildNode(g)
    // 本塁まわりの土・マウンド・走路
    let homeDirt = part(SCNCylinder(radius: 4.0, height: 0.02), P.dirt, outline: 0); homeDirt.position = v(0, 0.01, 0); root.addChildNode(homeDirt)
    let mound = part(SCNCylinder(radius: 2.75, height: 0.3), P.dirt, outline: 0); mound.position = v(0, 0.15, 18.44); root.addChildNode(mound)
    root.addChildNode(box(0.61, 0.03, 0.15, P.white, at: v(0, 0.31, 18.44), outline: 0))
    for s: CGFloat in [-1, 1] {
        let path = box(1.9, 0.02, 27.4, P.dirt, at: v(s * 9.7, 0.012, 9.7), outline: 0); path.eulerAngles.y = s * .pi / 4; root.addChildNode(path)
        root.addChildNode(box(0.4, 0.1, 0.4, P.white, at: v(s * 19.4, 0.05, 19.4), outline: 0))
        let foul = box(0.12, 0.02, 100, P.white, at: v(s * 35.4, 0.013, 35.4), outline: 0); foul.eulerAngles.y = s * .pi / 4; root.addChildNode(foul)
    }
    root.addChildNode(box(0.4, 0.1, 0.4, P.white, at: v(0, 0.05, 38.8), outline: 0))
    // 本塁・バッターボックス
    let plate = NSBezierPath(); plate.move(to: NSPoint(x: -0.216, y: 0)); plate.line(to: NSPoint(x: 0.216, y: 0)); plate.line(to: NSPoint(x: 0.216, y: -0.216)); plate.line(to: NSPoint(x: 0, y: -0.432)); plate.line(to: NSPoint(x: -0.216, y: -0.216)); plate.close()
    root.addChildNode(flat(SCNShape(path: plate, extrusionDepth: 0.02), P.white, y: 0.03))
    for s: CGFloat in [-1, 1] {
        let cx = s * 0.9
        root.addChildNode(box(1.22, 0.02, 0.06, P.white, at: v(cx, 0.03, 0.9), outline: 0))
        root.addChildNode(box(1.22, 0.02, 0.06, P.white, at: v(cx, 0.03, -0.93), outline: 0))
        root.addChildNode(box(0.06, 0.02, 1.83, P.white, at: v(cx - s * 0.61, 0.03, 0), outline: 0))
        root.addChildNode(box(0.06, 0.02, 1.83, P.white, at: v(cx + s * 0.61, 0.03, 0), outline: 0))
    }
    // フェンス（弧・黄色の上線）・ウォーニングトラック・スタンド
    // フェンス板は「隣の点を結ぶ弦」の向きで回す（柵の距離が方向で変わるので、円の接線で回すと板が斜めになって隙間が出る）
    func fencePt(_ deg: Double, _ dr: Double = 0) -> (Double, Double) { let r = fenceRadius(deg) + dr; return (r * sin(deg * .pi / 180), r * cos(deg * .pi / 180)) }
    func chordYaw(_ a: (Double, Double), _ b: (Double, Double)) -> CGFloat { CGFloat(atan2(-(b.1 - a.1), b.0 - a.0)) }
    for deg in stride(from: -46.0, to: 46.0, by: 1.5) {
        let a = fencePt(deg), b = fencePt(deg + 1.5)
        let len = ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).squareRoot() + 0.15
        let c = v((a.0 + b.0) / 2, 1.6, (a.1 + b.1) / 2)
        let seg = box(len, 3.2, 0.4, P.fence, at: c, outline: 0); seg.eulerAngles.y = chordYaw(a, b); root.addChildNode(seg)
        let top = box(len, 0.18, 0.5, P.yellow, at: v(c.x, 3.25, c.z), outline: 0); top.eulerAngles.y = chordYaw(a, b); root.addChildNode(top)
    }
    // ウォーニングトラック（フェンスに沿った土の帯。柵の距離が方向で変わるのでフェンスと同じ関数で弧を取る）
    let trackPath = NSBezierPath()
    func fp(_ r: Double, _ deg: Double) -> NSPoint { NSPoint(x: r * sin(deg * .pi / 180), y: r * cos(deg * .pi / 180)) }
    trackPath.move(to: fp(fenceRadius(-46) - 7, -46))
    stride(from: -46.0, through: 46.0, by: 1.0).forEach { trackPath.line(to: fp(fenceRadius($0) - 7, $0)) }
    stride(from: 46.0, through: -46.0, by: -1.0).forEach { trackPath.line(to: fp(fenceRadius($0) + 0.3, $0)) }
    trackPath.close()
    root.addChildNode(flat(SCNShape(path: trackPath, extrusionDepth: 0.02), P.track, y: 0.02))
    // 内野の土の弧は無し（センターカメラからは見えないので省く）。走路の外側は芝のまま
    // 外野スタンド（客席 = 小さな色の箱を弧に並べて段々に上げる。色は控えめに混ぜる）
    let rows = withOutfieldDetail ? 12 : 5
    for k in 0..<rows {
        for deg in stride(from: -50.0, to: 50.0, by: 0.8) {
            let dr = 2.0 + Double(k) * 1.6
            let a = fencePt(deg, dr), b = fencePt(deg + 0.8, dr)
            let h = 0.9 + Double(k) * 0.95
            let colr = P.crowd[(Int(abs(deg) * 13) + k * 5) % P.crowd.count].blended(withFraction: 0.4, of: col(0x8A8A96)) ?? P.gray
            let seat = box(1.5, 0.9, 1.5, colr, at: v((a.0 + b.0) / 2, h, (a.1 + b.1) / 2), outline: 0)
            seat.eulerAngles.y = chordYaw(a, b); root.addChildNode(seat)
        }
    }
    // 外周の壁と照明塔（外野カメラの背景）
    if withOutfieldDetail {
        for deg in stride(from: -52.0, to: 52.0, by: 2.0) {
            let a = fencePt(deg, 2.0 + 12 * 1.6 + 1.5), b = fencePt(deg + 2.0, 2.0 + 12 * 1.6 + 1.5)
            let len = ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).squareRoot() + 0.2
            let wall = box(len, 3.0, 1.0, col(0x5D6B8C), at: v((a.0 + b.0) / 2, 13.5, (a.1 + b.1) / 2), outline: 0)
            wall.eulerAngles.y = chordYaw(a, b); root.addChildNode(wall)
        }
        for deg in [-36.0, 36.0] {
            let r = fenceRadius(deg) + 30
            let pole = part(SCNCylinder(radius: 0.9, height: 42), col(0x9AA0AE), outline: 0); pole.position = v(r * sin(deg * .pi / 180), 21, r * cos(deg * .pi / 180)); root.addChildNode(pole)
            root.addChildNode(box(9, 5, 1.2, col(0xE9E1D6), at: v(r * sin(deg * .pi / 180), 44, r * cos(deg * .pi / 180)), outline: 0))
        }
        // スコアボード（中堅の奥）
        root.addChildNode(box(22, 9, 1.5, col(0x2B2634), at: v(0, 20, 150), outline: 0))
        root.addChildNode(box(20, 7, 0.2, col(0x1A2A3C), at: v(0, 20, 149.1), outline: 0))
        // ファウルポール
        for s: CGFloat in [-1, 1] {
            let r = fenceRadius(45)
            let pole = part(SCNCylinder(radius: 0.25, height: 16), P.yellow, outline: 0); pole.position = v(s * r * sin(.pi / 4), 8, r * cos(.pi / 4)); root.addChildNode(pole)
        }
    }
    // 本塁の後ろのスタンド（センターカメラの背景）
    for k in 0..<14 {
        for deg in stride(from: 128.0, to: 232.0, by: 1.0) {
            let r = 16.0 + Double(k) * 1.5
            let h = 1.0 + Double(k) * 0.9
            let colr = P.crowd[(Int(deg * 7) + k * 5) % P.crowd.count].blended(withFraction: 0.35, of: col(0x8A8A96)) ?? P.gray
            let seat = box(1.2, 0.9, 1.4, colr, at: v(r * sin(deg * .pi / 180), h, r * cos(deg * .pi / 180)), outline: 0)
            seat.eulerAngles.y = -deg * .pi / 180; root.addChildNode(seat)
        }
    }
    // バックネット裏の壁（低い）
    for deg in stride(from: 126.0, to: 234.0, by: 3.0) {
        let r = 14.5
        let wall = box(1.0, 1.1, 0.4, col(0x3C5A3A), at: v(r * sin(deg * .pi / 180), 0.55, r * cos(deg * .pi / 180)), outline: 0)
        wall.eulerAngles.y = -deg * .pi / 180; root.addChildNode(wall)
    }
    return root
}

func skyImage(_ size: NSSize) -> NSImage {
    let img = NSImage(size: size); img.lockFocus()
    NSGradient(colors: [col(0x4FA3E6), col(0x9AD2F5), col(0xD8EEFB)])!.draw(in: NSRect(origin: .zero, size: size), angle: -90)
    img.unlockFocus(); return img
}

func addLights(_ scene: SCNScene, sunYaw: CGFloat) {
    let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional; sun.light!.intensity = 1050
    sun.eulerAngles = SCNVector3(-0.75, sunYaw, 0); scene.rootNode.addChildNode(sun)
    let amb = SCNNode(); amb.light = SCNLight(); amb.light!.type = .ambient; amb.light!.intensity = 330; scene.rootNode.addChildNode(amb)
}

func clouds(_ root: SCNNode, seed: [(CGFloat, CGFloat, CGFloat, CGFloat)]) {
    for (x, y, z, s) in seed {
        let c = SCNNode()
        for (dx, dy, r) in [(0.0, 0.0, 1.0), (-1.1, -0.2, 0.75), (1.0, -0.15, 0.8), (0.3, 0.4, 0.7)] {
            let g = SCNSphere(radius: r * s); g.materials = [unlit(col(0xFFFFFF, 0.92))]
            let n = SCNNode(geometry: g); n.position = v(dx * s, dy * s, 0); n.scale = SCNVector3(1, 0.7, 1); c.addChildNode(n)
        }
        c.position = v(x, y, z); root.addChildNode(c)
    }
}

struct Shot { let name: String; let size: CGSize; let scene: SCNScene; let camera: SCNNode; let probes: [(String, SCNVector3)] }

func blobShadow(_ r: CGFloat, at p: SCNVector3) -> SCNNode {
    let g = SCNCylinder(radius: r, height: 0.01); g.materials = [unlit(col(0x1A2A1A, 0.28))]
    let n = SCNNode(geometry: g); n.position = v(p.x, 0.02, p.z); return n
}

// MARK: - 打席（センターカメラ: 投手の背中越しに正面向きの打者を見る）

func atBatShot() -> Shot {
    let scene = SCNScene()
    scene.background.contents = skyImage(NSSize(width: 786, height: 1704))
    addLights(scene, sunYaw: 0.6)
    scene.rootNode.addChildNode(stadium(withOutfieldDetail: false))
    clouds(scene.rootNode, seed: [(-40, 30, -60, 5), (30, 36, -70, 6), (0, 42, -90, 7)])
    // 打者（右打席・胸を少し一塁側に開いて顔はカメラへ）
    let batter = ojisan(poses[0]); batter.scale = SCNVector3(charScale, charScale, charScale)
    batter.position = v(-1.0, 0, 0.15); batter.eulerAngles.y = 0.35
    scene.rootNode.addChildNode(batter); scene.rootNode.addChildNode(blobShadow(0.6, at: batter.position))
    // 審判（捕手の後ろ。ほとんど隠れる）と捕手（4 回目で参考ブランチの見え方に寄せた）
    let umpire = umpireNode(); umpire.scale = SCNVector3(charScale, charScale, charScale); umpire.position = v(0.15, 0, -2.75)
    scene.rootNode.addChildNode(umpire)
    let catcher = catcherNode(); catcher.scale = SCNVector3(charScale, charScale, charScale); catcher.position = v(0.0, 0, -1.7)
    scene.rootNode.addChildNode(catcher); scene.rootNode.addChildNode(blobShadow(0.7, at: catcher.position))
    // 投手（マウンドの前・本塁に向く = カメラに背中）
    let pitcher = pitcherNode(); pitcher.scale = SCNVector3(charScale, charScale, charScale)
    pitcher.position = v(0.0, 0.3, 17.4); pitcher.eulerAngles.y = .pi
    scene.rootNode.addChildNode(pitcher); scene.rootNode.addChildNode(blobShadow(0.6, at: v(0.0, 0.3, 17.4)))
    // ボール（投球の途中・打者の手前 6m）と残像
    let ballPos = v(-0.22, 1.3, 3.6)
    scene.rootNode.addChildNode(sphere(0.12, P.white, at: ballPos, outline: 0.025))
    for (i, dz) in [1.2, 2.4].enumerated() {
        let g = SCNSphere(radius: 0.1 - CGFloat(i) * 0.02); g.materials = [unlit(col(0xFFFFFF, 0.45 - CGFloat(i) * 0.15))]
        let n = SCNNode(geometry: g); n.position = v(-0.22 + dz * 0.01, 1.3 + dz * 0.05, 3.6 + dz); scene.rootNode.addChildNode(n)
    }
    // カメラ（センター側の遠く・望遠。投手と打者の大きさの差を縮め、投手は下端で腰から上だけ映す = 中継のセンターカメラ）
    let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera!.projectionDirection = .vertical; cam.camera!.fieldOfView = 9.6
    cam.camera!.zFar = 600
    cam.position = v(0.0, 6.0, 43.0); cam.look(at: v(0.0, 1.35, 0.3))
    scene.rootNode.addChildNode(cam)
    let zone = v(-0.25, 0.85, 0.35)   // ストライクゾーンの中心（打者の前・本塁の上）
    return Shot(name: "3d-at-bat", size: CGSize(width: 786, height: 1704), scene: scene, camera: cam,
                probes: [("zone", zone), ("ball", ballPos), ("batterHead", v(-1.0, 3.3 * charScale, 0.15)), ("batterFeet", v(-1.0, 0, 0.15)),
                         ("pitcherHead", v(0.0, 0.3 + 3.3 * charScale, 17.4)), ("pitcherHand", v(0.0 - 1.35 * charScale, 0.3 + 4.35 * charScale, 17.4 + 0.75 * charScale)),
                         ("plate", v(0, 0, 0))])
}

// MARK: - 外野カメラ（左中間へ伸びる打球を追う）

func outfieldShot() -> Shot {
    let scene = SCNScene()
    scene.background.contents = skyImage(NSSize(width: 786, height: 1704))
    addLights(scene, sunYaw: -2.4)
    scene.rootNode.addChildNode(stadium(withOutfieldDetail: true))
    clouds(scene.rootNode, seed: [(-120, 70, 260, 12), (40, 80, 300, 14), (-30, 62, 240, 9)])
    // 打球: 方向 -22°（左中間）・108m 地点・高さ 14m。軌跡は薄い球で残す
    let dirDeg = -22.0
    func along(_ d: Double, _ h: Double) -> SCNVector3 { v(d * sin(dirDeg * .pi / 180), h, d * cos(dirDeg * .pi / 180)) }
    let ballPos = along(104, 11.0)
    scene.rootNode.addChildNode(sphere(0.5, P.white, at: ballPos, outline: 0.07))
    for (i, d) in [99.0, 94, 89].enumerated() {
        let h = 11.0 + (104 - d) * 0.42 + pow(104 - d, 1.5) * 0.02
        let g = SCNSphere(radius: 0.42 - CGFloat(i) * 0.06); g.materials = [unlit(col(0xFFFFFF, 0.5 - CGFloat(i) * 0.08))]
        let n = SCNNode(geometry: g); n.position = along(d, h); scene.rootNode.addChildNode(n)
    }
    // 外野手（見上げる）
    let fielder = ojisan(Pose3(name: "外野手", elbowR: v(1.3, 1.6, 0.2), handR: v(1.1, 1.0, 0.4), elbowL: v(-1.4, 3.0, 0.2), handL: v(-1.2, 4.2, 0.5), headPitch: -0.55), outfit: .pitcher)   // グラブの左手を上げて追う
    fielder.scale = SCNVector3(charScale, charScale, charScale); fielder.position = along(94, 0); fielder.eulerAngles.y = .pi + 0.2
    scene.rootNode.addChildNode(fielder); scene.rootNode.addChildNode(blobShadow(0.6, at: fielder.position))
    // フェンスの距離表示（左中間 116m・左翼 100m・中堅 122m）: 白い板に紺の数字は SwiftUI 側で重ねる（3D テキストは使わない）
    for (deg, w) in [(-22.0, 8.0), (-44.0, 7.0), (0.0, 8.0)] {
        let r = fenceRadius(deg) - 0.3
        let a = (fenceRadius(deg - 1) * sin((deg - 1) * .pi / 180), fenceRadius(deg - 1) * cos((deg - 1) * .pi / 180))
        let b = (fenceRadius(deg + 1) * sin((deg + 1) * .pi / 180), fenceRadius(deg + 1) * cos((deg + 1) * .pi / 180))
        let sign = box(w, 1.5, 0.1, P.white, at: v(r * sin(deg * .pi / 180), 1.9, r * cos(deg * .pi / 180)), outline: 0)
        sign.eulerAngles.y = CGFloat(atan2(-(b.1 - a.1), b.0 - a.0)); scene.rootNode.addChildNode(sign)
    }
    // カメラ: 打球の後ろ・少し上から、左中間フェンスを見る
    let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera!.projectionDirection = .vertical; cam.camera!.fieldOfView = 40
    cam.camera!.zFar = 800
    cam.position = along(66, 9.0); cam.look(at: along(116, 5.5))
    scene.rootNode.addChildNode(cam)
    let signC = fenceRadius(-22) - 0.25
    return Shot(name: "3d-outfield", size: CGSize(width: 786, height: 1704), scene: scene, camera: cam,
                probes: [("ball", ballPos), ("signLC", v(signC * sin(-22 * .pi / 180), 1.9, signC * cos(-22 * .pi / 180))),
                         ("signLF", v((fenceRadius(-44) - 0.25) * sin(-44 * .pi / 180), 1.9, (fenceRadius(-44) - 0.25) * cos(-44 * .pi / 180))),
                         ("signCF", v(0, 1.9, fenceRadius(0) - 0.25)),
                         ("fenceTopLC", v(fenceRadius(-22) * sin(-22 * .pi / 180), 3.3, fenceRadius(-22) * cos(-22 * .pi / 180)))])
}

// MARK: - キャラ単体（透明背景・4 ポーズ + 回転 4 方向 + 投手）

func characterShot(_ pose: Pose3, yaw: CGFloat, name: String, outfit: Outfit = .batter, size: CGFloat = 640) -> Shot {
    nodeShot(ojisan(pose, outfit: outfit), yaw: yaw, name: name, size: size)
}
/// 任意のノードを透明背景で 1 枚に描く（捕手・審判用）。`lookY` は注視点の高さ（しゃがんだ捕手は低い）。
func nodeShot(_ n: SCNNode, yaw: CGFloat, name: String, size: CGFloat = 640, lookY: CGFloat = 2.45, camY: CGFloat = 3.6) -> Shot {
    let scene = SCNScene()
    scene.background.contents = NSColor.clear
    addLights(scene, sunYaw: 0.5)
    n.eulerAngles.y = yaw; scene.rootNode.addChildNode(n)
    let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera!.projectionDirection = .vertical; cam.camera!.fieldOfView = 30
    cam.position = v(0.4, camY, 13.5); cam.look(at: v(0, lookY, 0))
    scene.rootNode.addChildNode(cam)
    return Shot(name: name, size: CGSize(width: size, height: size * 1.15), scene: scene, camera: cam, probes: [])
}

// MARK: - 描画

guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal が使えません") }
let renderer = SCNRenderer(device: device, options: nil)
renderer.autoenablesDefaultLighting = false

func project(_ p: SCNVector3, cam: SCNNode, size: CGSize) -> CGPoint {
    let proj = simd_float4x4(cam.camera!.projectionTransform(withViewportSize: size))
    let view = simd_inverse(simd_float4x4(cam.worldTransform))
    let clip = proj * view * simd_float4(Float(p.x), Float(p.y), Float(p.z), 1)
    let nx = clip.x / clip.w, ny = clip.y / clip.w
    return CGPoint(x: CGFloat((nx + 1) / 2) * size.width, y: CGFloat((1 - ny) / 2) * size.height)
}

func render(_ shot: Shot, dir: String) {
    renderer.scene = shot.scene; renderer.pointOfView = shot.camera
    let img = renderer.snapshot(atTime: 0, with: shot.size, antialiasingMode: .multisampling4X)
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { fatalError("png: \(shot.name)") }
    let url = URL(fileURLWithPath: dir).appendingPathComponent(shot.name + ".png")
    try! png.write(to: url)
    print("wrote \(url.lastPathComponent) \(rep.pixelsWide)x\(rep.pixelsHigh)")
    for (label, p) in shot.probes {
        let q = project(p, cam: shot.camera, size: shot.size)
        print("  probe \(label): \(Int(q.x / 2))pt, \(Int(q.y / 2))pt")   // @2x → pt
    }
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let only = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil
if only == nil || only == "char" {
    for (i, p) in poses.enumerated() { render(characterShot(p, yaw: 0.25, name: "3d-pose-\(i)"), dir: dir) }
    for (i, yaw) in [0.0, 0.8, 1.35, 3.14].enumerated() { render(characterShot(poses[0], yaw: yaw, name: "3d-turn-\(i)"), dir: dir) }
    render(characterShot(Pose3(name: "投球", elbowR: v(1.55, 3.3, -0.45), handR: v(1.35, 4.35, -0.75), elbowL: v(-1.35, 2.25, 0.5), handL: v(-1.0, 2.65, 1.15)), yaw: 0.3, name: "3d-pitcher", outfit: .pitcher), dir: dir)
    // 4 回目: 投手の背中（打席で見える向き）と捕手（正面・しゃがみ。参考ブランチの見え方）
    render(characterShot(Pose3(name: "投球", elbowR: v(1.55, 3.3, -0.45), handR: v(1.35, 4.35, -0.75), elbowL: v(-1.35, 2.25, 0.5), handL: v(-1.0, 2.65, 1.15)), yaw: .pi + 0.15, name: "3d-pitcher-back", outfit: .pitcher), dir: dir)
    render(nodeShot(catcherNode(), yaw: 0.12, name: "3d-catcher", lookY: 1.75, camY: 2.9), dir: dir)
}
if only == nil || only == "field" {
    render(atBatShot(), dir: dir)
    render(outfieldShot(), dir: dir)
}
