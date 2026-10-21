import CoreGraphics
import Foundation

/// サイコロを立方体として描くための純関数（#2389）。状態は持たない。
///
/// SwiftUI の `rotation3DEffect` は入れ子にしても 1 枚の面を回すだけで立方体にはならない
/// （内側の面は 2D に潰れてから外側の回転が掛かる）。そこで 6 面の向きを自分で回し、
/// 見える面だけを平行投影して画面の平行四辺形に写す。面の中身（角丸・目）は単位正方形の座標で描き、
/// ここが返すアフィン変換で画面へ移す。回転が 0 のときは前面がちょうど正方形になり、
/// 止まっているサイコロ（平面）と同じ絵になる。
enum DiceComboCube {

    /// 立方体の向き（度）。x は手前へ転がる・y は横へ転がる・z は画面上で回る。
    struct Rotation: Equatable {
        var x: Double = 0
        var y: Double = 0
        var z: Double = 0

        static let identity = Rotation()
    }

    /// 6 面。`front` が画面を向いている面で、止まったときに読む目。
    enum Face: CaseIterable {
        case front, back, right, left, top, bottom
    }

    /// 画面に写した 1 面。
    struct ProjectedFace: Equatable {
        /// この面の目（1〜6）。
        var value: Int
        /// 単位正方形（0〜1）の座標を、辺 `side` のサイコロの描画座標へ写すアフィン変換。
        var transform: CGAffineTransform
        /// 明るさ（0〜1）。画面を正面に向いた面が 1。
        var brightness: Double
        /// 面の法線の画面手前成分（0〜1）。大きいほど正面を向いている。
        var facing: Double
    }

    // MARK: - 目の割り当て

    /// 前面の目から 6 面の目を決める。向かい合う面の和は 7（本物のサイコロと同じ）。
    /// 右面・上面は残った 2 組から小さい方を取る（転がる途中に見せる目なので、どれでも矛盾しない）。
    static func faceValues(front: Int) -> [Face: Int] {
        let front = (1...6).contains(front) ? front : 1
        let pairs = [(1, 6), (2, 5), (3, 4)].filter { $0.0 != front && $0.1 != front }
        let right = pairs[0].0
        let top = pairs[1].0
        return [
            .front: front, .back: 7 - front,
            .right: right, .left: 7 - right,
            .top: top, .bottom: 7 - top,
        ]
    }

    // MARK: - 幾何

    /// 3 次元の向き（右手系・y は画面の下向き・z は画面の手前向き）。
    struct Vector: Equatable {
        var x: Double, y: Double, z: Double

        static func * (lhs: Vector, rhs: Double) -> Vector { Vector(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs) }
        static func + (lhs: Vector, rhs: Vector) -> Vector { Vector(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z) }
        static func - (lhs: Vector, rhs: Vector) -> Vector { Vector(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z) }
    }

    /// 面ごとの、回す前の向き。`normal` は外向きの法線、`u`/`v` は単位正方形の横・縦の向き。
    static func axes(of face: Face) -> (normal: Vector, u: Vector, v: Vector) {
        switch face {
        case .front:  return (Vector(x: 0, y: 0, z: 1),  Vector(x: 1, y: 0, z: 0),  Vector(x: 0, y: 1, z: 0))
        case .back:   return (Vector(x: 0, y: 0, z: -1), Vector(x: -1, y: 0, z: 0), Vector(x: 0, y: 1, z: 0))
        case .right:  return (Vector(x: 1, y: 0, z: 0),  Vector(x: 0, y: 0, z: -1), Vector(x: 0, y: 1, z: 0))
        case .left:   return (Vector(x: -1, y: 0, z: 0), Vector(x: 0, y: 0, z: 1),  Vector(x: 0, y: 1, z: 0))
        case .top:    return (Vector(x: 0, y: -1, z: 0), Vector(x: 1, y: 0, z: 0),  Vector(x: 0, y: 0, z: 1))
        case .bottom: return (Vector(x: 0, y: 1, z: 0),  Vector(x: 1, y: 0, z: 0),  Vector(x: 0, y: 0, z: -1))
        }
    }

    /// `rotation`（度）で向きを回す。x → y → z の順に回す。
    static func rotate(_ v: Vector, by rotation: Rotation) -> Vector {
        func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }
        var (x, y, z) = (v.x, v.y, v.z)
        // x 軸
        let (sx, cx) = (sin(rad(rotation.x)), cos(rad(rotation.x)))
        (y, z) = (y * cx - z * sx, y * sx + z * cx)
        // y 軸
        let (sy, cy) = (sin(rad(rotation.y)), cos(rad(rotation.y)))
        (x, z) = (x * cy + z * sy, -x * sy + z * cy)
        // z 軸
        let (sz, cz) = (sin(rad(rotation.z)), cos(rad(rotation.z)))
        (x, y) = (x * cz - y * sz, x * sz + y * cz)
        return Vector(x: x, y: y, z: z)
    }

    /// 向いていない面は暗く見せる。正面（`facing` = 1）で 1、真横（0）で `shadowFloor`。
    static let shadowFloor: Double = 0.62

    static func brightness(facing: Double) -> Double {
        shadowFloor + (1 - shadowFloor) * min(max(facing, 0), 1)
    }

    /// 辺 `side` のサイコロを `rotation` に向けたとき、画面に見える面を返す（奥の面から順）。
    ///
    /// 平行投影なので、見える面どうしは重ならない。`rotation` が 0 なら前面 1 枚だけで、
    /// その変換は単位正方形を `(0,0)-(side,side)` へ拡大するだけになる。
    static func visibleFaces(front: Int, rotation: Rotation, side: CGFloat) -> [ProjectedFace] {
        let values = faceValues(front: front)
        let s = Double(side)
        let half = s / 2
        var faces: [ProjectedFace] = []
        for face in Face.allCases {
            let local = axes(of: face)
            let normal = rotate(local.normal, by: rotation)
            // 法線がほぼ真横のときは幅のない線になるので描かない。
            guard normal.z > 1e-6 else { continue }
            let u = rotate(local.u, by: rotation) * s
            let v = rotate(local.v, by: rotation) * s
            // 面の左上の角（単位正方形の原点）。面の中心は法線の向きに半分だけ外へ出ている。
            let origin = normal * half - u * 0.5 - v * 0.5
            let transform = CGAffineTransform(
                a: u.x, b: u.y,
                c: v.x, d: v.y,
                tx: origin.x + half, ty: origin.y + half
            )
            faces.append(ProjectedFace(
                value: values[face] ?? 1,
                transform: transform,
                brightness: brightness(facing: normal.z),
                facing: normal.z
            ))
        }
        return faces.sorted { $0.facing < $1.facing }
    }
}
