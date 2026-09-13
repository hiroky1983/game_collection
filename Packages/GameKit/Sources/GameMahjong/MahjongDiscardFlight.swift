import SwiftUI
import Core
import MahjongTiles

// MARK: - 打牌が河へ飛ぶ動き（麻雀刷新 #738）
//
// 卓（`MahjongTableView`）は「ルーレット現象」の反省で暗黙アニメーションを全部止めている
// （`transaction { $0.animation = nil }`）。打牌の動きはその外側に**1 枚だけの飛行レイヤー**として
// 重ね、河の本物の牌は着地まで隠す。動かすのは進捗 0→1 の値 1 つだけで、位置は純関数
// （`MahjongDiscardFlight.position(progress:)`）で決めるのでテストで縛れる。
// Reduce Motion では `withGameAnimation` が nil を返し、進捗が即 1 になる（＝瞬時に置かれる）。

/// 飛んでいる最中の 1 枚。
struct MahjongDiscardFlight: Equatable {
    /// 手番順の家（0=自分, 1=下家, 2=対面, 3=上家）。
    var seat: Int
    /// 河の何枚目か（着地先）。
    var index: Int
    var tile: MahjongTile
    /// 出発点（自分は手牌一覧、CPU はその家の立て牌の列の中ほど）。
    var from: CGPoint
    /// 着地点（`MahjongTableLayout.riverSlot`）。
    var to: CGPoint
    var rotation: Double
    var scale: CGFloat

    /// 飛行の長さ。
    static let duration: TimeInterval = 0.28
    /// 途中で持ち上がる高さ（pt。手前の縮尺 1 のとき）。放物線の頂点。
    static let lift: CGFloat = 26

    /// 進捗 0〜1 での位置。直線に、上向きの放物線を足す。
    func position(progress: CGFloat) -> CGPoint {
        let t = min(1, max(0, progress))
        let x = from.x + (to.x - from.x) * t
        let y = from.y + (to.y - from.y) * t - Self.lift * scale * sin(t * .pi)
        return CGPoint(x: x, y: y)
    }
}

/// 飛行レイヤー。卓と同じ座標系（卓の矩形の左上が原点）に置く。
struct MahjongDiscardFlightView: View {
    let flight: MahjongDiscardFlight
    let progress: CGFloat
    let tileWidth: CGFloat

    var body: some View {
        let w = tileWidth * flight.scale
        MahjongTileView(tile: flight.tile, width: w, height: w * MahjongTableLayout.tileAspect)
            .rotationEffect(.degrees(flight.rotation))
            // 大きさは変えない（一覧の牌と河の牌が同じ大きさなので、そのまま滑る。会長指摘 2026-09-13）。
            // 浮いている手掛かりは影だけ。
            .shadow(color: .black.opacity(0.35 * Double(sin(progress * .pi))), radius: 6, y: 6)
            .position(flight.position(progress: progress))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
