import Core
import Foundation

/// 走者のコマの選び方と絵の置き方（#701）。
///
/// **SpriteKit に依存しない純粋な計算**にしてある。コマそのもの（40×37 ドット・右向き）は
/// `Core` の `OjisanPixel` が持ち、`RunnerScene` はここで決めたコマのテクスチャを 1 枚の
/// スプライトに差し替えるだけ（寸法・位相の規則をシーンに書かない）。
enum RunnerRider {
    // MARK: - 漕ぐ位相

    /// クランク 1 回転で進む距離（ワールド単位）。
    ///
    /// 実車のギア比の代わりに、ケイデンスがそれらしく見える値を置く。小さくすると脚が
    /// 高速で回りすぎ、大きくすると走っているのに漕いでいないように見える。
    static let crankTravel: Double = 13

    /// クランクの位相（ラジアン）を、接地して進んだ距離から進める。
    ///
    /// **接地しているあいだだけ進める**。空中ではペダルを漕げない（`RunnerField.currentSpeed` が
    /// 乗りを無視するのと同じ扱い）ので、脚も止まって見えるのが正しい。
    /// 距離が戻る場合（ステージのやり直し・チェックポイント再開）は進めない。
    static func advance(phase: Double, by distanceDelta: Double, isPedaling: Bool) -> Double {
        guard isPedaling, distanceDelta > 0 else { return phase }
        return phase + distanceDelta / crankTravel * 2 * .pi
    }

    /// 走り出しからずっと接地して `distance` だけ進んだときの位相。
    ///
    /// `RunnerScene` は最初の反映で「それまでに進んだ距離」をまとめて位相に足すので、撮影
    /// （`-simulateRunner pedaling`）のように接地した瞬間で凍らせた画のコマはこの位相で決まる。
    static func phase(forGroundedDistance distance: Double) -> Double {
        advance(phase: 0, by: distance, isPedaling: true)
    }

    /// 漕ぐコマ。半回転（π）ごとに右ペダル前（`ride0`）と左ペダル前（`ride1`）を切り替える。
    ///
    /// 位相は前進で増える一方（`advance`）なので、速く走るほど速く切り替わる。
    static func pedalFrame(phase: Double) -> OjisanPixel.RiderFrame {
        let halfTurns = Int((phase / .pi).rounded(.down))
        return halfTurns.isMultiple(of: 2) ? .ride0 : .ride1
    }

    // MARK: - コマの選択

    /// 局面と接地からコマを決める。
    ///
    /// - `.falling`（落下・激突の演出中）は `tumble`、演出明けの `.failed` は `dizzy`。
    /// - 空中は `jump`（前のめりの傾きはシーンが `zRotation` で足す）。
    /// - 接地していれば位相で `ride0` / `ride1`。走り出す前（`.ready`・位相 0）は `ride0`。
    static func frame(phase: RunnerPhase, isGrounded: Bool, pedalPhase: Double) -> OjisanPixel.RiderFrame {
        switch phase {
        case .falling: return .tumble
        case .failed: return .dizzy
        default: return isGrounded ? pedalFrame(phase: pedalPhase) : .jump
        }
    }

    // MARK: - 絵の置き方

    /// 図形で組んでいた頃の走者の見た目の高さ（帽子の天辺まで。当たり判定の 11 より少し上）。
    /// コマの不透明部分の高さをここに合わせて、置き換え前後で走者の大きさを変えない。
    static let visualHeight: Double = 11.9

    /// コマの格子をシーンの単位へ写す寸法。
    struct Placement: Equatable {
        /// 1 ドットの大きさ（ワールド単位）。
        var unit: Double
        /// スプライトの `anchorPoint`（0〜1）。x は前後の車輪の接地点の中央、y は車輪の底の行。
        var anchorX: Double
        var anchorY: Double
    }

    /// 基準のコマ（`ride0`）から置き方を決める。全コマは同じ格子で、車輪の底が同じ行にある
    /// （`RunnerRiderTests` が固定）ので、他のコマにもそのまま使う。
    ///
    /// - 1 ドット = `visualHeight` ÷ 不透明部分の高さ。
    /// - x の原点は**最下行の不透明な範囲の中央**（両輪の接地点の中間）。当たり判定の中心
    ///   （`RunnerField.Metrics.playerX`）と、図形時代の原点（前輪と後輪の中間）に合わせる。
    /// - y の原点は不透明部分の下端（車輪の底）。`player` の原点 = 足元（`field.footY`）に乗る。
    static func placement(for sprite: PixelSprite) -> Placement {
        guard let bounds = sprite.opaqueBounds, bounds.height > 0, sprite.width > 0
        else { return Placement(unit: visualHeight / 36, anchorX: 0.5, anchorY: 0) }
        // 不透明部分の最下行（車輪の底）。その行で色の付いた範囲が両輪の接地点。
        let bottom = sprite.rows[bounds.y + bounds.height - 1]
        let opaqueColumns = bottom.enumerated().filter { $0.element != "." }.map(\.offset)
        let left = Double(opaqueColumns.min() ?? bounds.x)
        let right = Double(opaqueColumns.max() ?? (bounds.x + bounds.width - 1)) + 1
        return Placement(
            unit: visualHeight / Double(bounds.height),
            anchorX: (left + right) / 2 / Double(sprite.width),
            anchorY: Double(sprite.height - (bounds.y + bounds.height)) / Double(sprite.height)
        )
    }
}
