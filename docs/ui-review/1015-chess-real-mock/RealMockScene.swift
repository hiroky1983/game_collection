import AppKit
import SceneKit
import SwiftUI

// MARK: - C: SceneKit の 3D モデル（自作の回転体＋ナイトは押し出し）

enum RealScene {
    /// 断面を回転して SCNGeometry にする。頂点法線は断面の接線から出す。
    static func lathe(_ profile: Prof, segments: Int = 72) -> SCNGeometry {
        let prof = RealProfiles.smooth(profile)
        var verts: [SCNVector3] = [], norms: [SCNVector3] = [], idx: [Int32] = []
        func n2(_ i: Int) -> (Double, Double) {
            let a = prof[max(0, i - 1)], b = prof[min(prof.count - 1, i + 1)]
            let dr = Double(b.r - a.r), dy = Double(b.y - a.y)
            let l = max(1e-9, (dr * dr + dy * dy).squareRoot())
            return (dy / l, -dr / l)
        }
        for i in 0..<prof.count {
            let (nr, ny) = n2(i)
            for j in 0...segments {
                let phi = Double(j) / Double(segments) * 2 * .pi
                verts.append(SCNVector3(prof[i].r * CGFloat(cos(phi)), prof[i].y, prof[i].r * CGFloat(sin(phi))))
                norms.append(SCNVector3(CGFloat(nr * cos(phi)), CGFloat(ny), CGFloat(nr * sin(phi))))
            }
        }
        let row = Int32(segments + 1)
        for i in 0..<(prof.count - 1) {
            for j in 0..<segments {
                let a = Int32(i) * row + Int32(j), b = a + 1, c = a + row, d = c + 1
                idx += [a, c, b, b, c, d]
            }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    static func material(_ c: ChessColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.isDoubleSided = true
        if c == .white {
            m.diffuse.contents = NSColor(srgbRed: 0.90, green: 0.85, blue: 0.74, alpha: 1)
            m.roughness.contents = 0.30
            m.metalness.contents = 0.0
        } else {
            m.diffuse.contents = NSColor(srgbRed: 0.14, green: 0.10, blue: 0.075, alpha: 1)
            m.roughness.contents = 0.16
            m.metalness.contents = 0.10
        }
        return m
    }

    /// 反射用の環境画像（空の白・窓の照り・盤の茶）。写り込みの「素材」になる。
    static func environment() -> CGImage {
        let w = 512, h = 256
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let g = CGGradient(colorsSpace: cs, colors: [
            CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1),
            CGColor(srgbRed: 0.93, green: 0.90, blue: 0.85, alpha: 1),
            CGColor(srgbRed: 0.45, green: 0.32, blue: 0.20, alpha: 1),
            CGColor(srgbRed: 0.25, green: 0.17, blue: 0.10, alpha: 1),
        ] as CFArray, locations: [0, 0.48, 0.52, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 60, y: 120, width: 90, height: 100))     // 窓（強い面光源）
        return ctx.makeImage()!
    }

    static func blobShadow() -> NSImage {
        let s = 256
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let g = CGGradient(colorsSpace: cs, colors: [
            CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55), CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0),
        ] as CFArray, locations: [0.35, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: 0,
                               endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: CGFloat(s) / 2, options: [])
        return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: s, height: s))
    }

    static func extrudedKnight(_ mat: SCNMaterial) -> SCNNode {
        let unit = ChessKnightShape().path(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let ns = NSBezierPath()
        func m(_ p: CGPoint) -> NSPoint { let (dx, y) = RealProfiles.knightMap(p.x, p.y); return NSPoint(x: dx, y: y) }
        unit.forEach { el in
            switch el {
            case .move(let p): ns.move(to: m(p))
            case .line(let p): ns.line(to: m(p))
            case .quadCurve(let p, let c):
                let s = ns.currentPoint, e = m(p), c1 = m(c)
                ns.curve(to: e, controlPoint1: NSPoint(x: s.x + 2 * (c1.x - s.x) / 3, y: s.y + 2 * (c1.y - s.y) / 3),
                         controlPoint2: NSPoint(x: e.x + 2 * (c1.x - e.x) / 3, y: e.y + 2 * (c1.y - e.y) / 3))
            case .curve(let p, let c1, let c2): ns.curve(to: m(p), controlPoint1: m(c1), controlPoint2: m(c2))
            case .closeSubpath: ns.close()
            }
        }
        ns.flatness = 0.002
        let shape = SCNShape(path: ns, extrusionDepth: 0.20)
        shape.chamferRadius = 0.05
        shape.chamferMode = .both
        shape.materials = [mat]
        let node = SCNNode(geometry: shape)
        return node
    }

    static func pieceNode(_ p: ChessPiece) -> SCNNode {
        let mat = material(p.color)
        let root = SCNNode()
        let body = SCNNode(geometry: lathe(RealProfiles.profile(p.type)))
        body.geometry?.materials = [mat]
        root.addChildNode(body)
        switch p.type {
        case .knight:
            root.addChildNode(extrudedKnight(mat))
        case .rook:
            // 銃眼: 6 本の歯を輪に並べる
            for k in 0..<6 {
                let phi = Double(k) / 6 * 2 * .pi
                let box = SCNBox(width: 0.13, height: 0.075, length: 0.12, chamferRadius: 0.012)
                box.materials = [mat]
                let n = SCNNode(geometry: box)
                n.position = SCNVector3(0.225 * CGFloat(cos(phi)), 0.638, 0.225 * CGFloat(sin(phi)))
                n.eulerAngles.y = CGFloat(-phi)
                root.addChildNode(n)
            }
        case .queen:
            for k in 0..<8 {
                let phi = Double(k) / 8 * 2 * .pi
                let s = SCNSphere(radius: 0.034); s.materials = [mat]
                let n = SCNNode(geometry: s)
                n.position = SCNVector3(0.235 * CGFloat(cos(phi)), 0.785, 0.235 * CGFloat(sin(phi)))
                root.addChildNode(n)
            }
            let top = SCNSphere(radius: 0.055); top.materials = [mat]
            let tn = SCNNode(geometry: top); tn.position = SCNVector3(0, 0.815, 0); root.addChildNode(tn)
        case .king:
            let v = SCNBox(width: 0.07, height: 0.15, length: 0.07, chamferRadius: 0.02); v.materials = [mat]
            let vn = SCNNode(geometry: v); vn.position = SCNVector3(0, 0.915, 0); root.addChildNode(vn)
            let h = SCNBox(width: 0.17, height: 0.06, length: 0.07, chamferRadius: 0.02); h.materials = [mat]
            let hn = SCNNode(geometry: h); hn.position = SCNVector3(0, 0.90, 0); root.addChildNode(hn)
        case .bishop:
            let cut = SCNBox(width: 0.16, height: 0.012, length: 0.30, chamferRadius: 0)
            let dm = SCNMaterial(); dm.diffuse.contents = NSColor.black.withAlphaComponent(0.9); dm.lightingModel = .constant
            cut.materials = [dm]
            let cn = SCNNode(geometry: cut)
            cn.position = SCNVector3(0.02, 0.64, 0.11); cn.eulerAngles = SCNVector3(0.35, 0, -0.6)
            root.addChildNode(cn)
        default: break
        }
        return root
    }

    /// 透明背景の駒画像を焼く（白背景と黒背景の 2 回描いて差分から α を復元する）。
    static func bake(_ p: ChessPiece, px: Int, elevationDeg: Double = 14) -> CGImage {
        let scene = SCNScene()
        let piece = pieceNode(p)
        scene.rootNode.addChildNode(piece)

        let blob = SCNPlane(width: 0.95, height: 0.95)
        let bm = SCNMaterial(); bm.diffuse.contents = blobShadow(); bm.lightingModel = .constant
        bm.writesToDepthBuffer = false
        blob.materials = [bm]
        let bn = SCNNode(geometry: blob)
        bn.eulerAngles.x = -.pi / 2; bn.position = SCNVector3(0.02, 0.002, 0.03)
        scene.rootNode.addChildNode(bn)

        scene.lightingEnvironment.contents = environment()
        scene.lightingEnvironment.intensity = 0.75

        let key = SCNNode(); key.light = SCNLight(); key.light!.type = .directional
        key.light!.intensity = 750; key.light!.color = NSColor(srgbRed: 1, green: 0.97, blue: 0.92, alpha: 1)
        key.eulerAngles = SCNVector3(-0.75, -0.6, 0)        // 左上手前から
        scene.rootNode.addChildNode(key)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light!.type = .ambient; fill.light!.intensity = 150
        scene.rootNode.addChildNode(fill)

        let cam = SCNNode(); cam.camera = SCNCamera()
        cam.camera!.usesOrthographicProjection = true
        cam.camera!.orthographicScale = 0.52
        cam.camera!.zNear = 0.1; cam.camera!.zFar = 20
        let e = elevationDeg * .pi / 180
        let target = SCNVector3(0, 0.44, 0)
        cam.position = SCNVector3(0, target.y + CGFloat(sin(e)) * 5, CGFloat(cos(e)) * 5)
        cam.eulerAngles = SCNVector3(-CGFloat(e), 0, 0)
        scene.rootNode.addChildNode(cam)

        let device = MTLCreateSystemDefaultDevice()!
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cam
        func snap(_ bg: NSColor) -> [UInt8] {
            scene.background.contents = bg
            let img = renderer.snapshot(atTime: 0, with: CGSize(width: px, height: px), antialiasingMode: .multisampling4X)
            return rgba(img.cgImage(forProposedRect: nil, context: nil, hints: nil)!, px: px)
        }
        let w = snap(.white), b = snap(.black)
        var out = [UInt8](repeating: 0, count: px * px * 4)
        for i in 0..<(px * px) {
            let o = i * 4
            let dr = Double(w[o] - b[o]) / 255, dg = Double(w[o + 1] - b[o + 1]) / 255, db = Double(w[o + 2] - b[o + 2]) / 255
            let a = max(0, min(1, 1 - (dr + dg + db) / 3))
            out[o + 3] = UInt8(a * 255 + 0.5)
            // 黒背景の色 = 前景色 × α（プリマルチ済み）
            out[o] = b[o]; out[o + 1] = b[o + 1]; out[o + 2] = b[o + 2]
        }
        return out.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }
    }

    static func rgba(_ img: CGImage, px: Int) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: px * px * 4)
        buf.withUnsafeMutableBytes { p in
            let ctx = CGContext(data: p.baseAddress, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: px, height: px))
        }
        return buf
    }
}
