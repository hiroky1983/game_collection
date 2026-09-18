import Core
import Foundation
import SpriteKit

/// 乗ると崩れる足場（#1090。里山＝古い吊り橋・港町＝古い木の桟橋）の絵と、毎フレームの反映。
///
/// **当たり判定は `RunnerField` が台座（`RunnerPlatform`）としてそのまま持つ**（上面の高さも
/// 乗り降りの規則も #674 の台座と同じ）。ここが足すのは「いつどれだけ崩れて見えるか」だけで、
/// その進み具合も `RunnerField.crumbleProgress(_:)` が持つ時計をそのまま読む。
///
/// 動きを `SKAction` ではなく**毎フレームの計算**で作ってあるのは、一時停止・バックグラウンド
/// 復帰と辻褄を合わせるため。`SKAction` は自分の時計で進むので、`tick` が止まっているあいだも
/// 板が落ち続け、戻ってきたときに当たり判定（まだ架かっている）と絵（もう落ちた）がずれる。
extension RunnerScene {
    /// 1 基ぶんの絵。`sync` が毎フレーム崩れの進みを写す。
    struct CrumblingPlatformView {
        /// 揺らす対象（板・縄・ひび。杭と袂の柱は揺らさないので入れない）。
        let deck: SKNode
        /// 板 1 枚ずつ。左から順で、`fallStart` は「崩れ始めてからこの板が抜けるまで」の割合（0…1）。
        let planks: [SKNode]
        /// 崩れる予告のひび（揺れているあいだだけ濃くする）。
        let cracks: SKNode
        /// 吊り橋の縄・桟橋の桁（板が全部落ちたら一緒に切れる／落ちる）。
        let carriers: [SKNode]
        /// 板の上面の高さ（`RunnerPlatform.top`）。落ちた板を戻す先。
        let top: Double
    }

    /// 崩れる足場の絵を組んで、コース層へ足す。
    ///
    /// 板張りの**下は谷**（里山＝川、港町＝海）。谷そのものは `buildStageCourse` が
    /// 穴と同じ部品（`addPitVoid` / `addPitEdgeMarkers`）で描くので、ここでは架かっている
    /// ものだけを作る——「崩れた後に下の景色が見える」は、板を消せば谷がそのまま出る形にしてある。
    func makeCrumblingPlatform(_ platform: RunnerPlatform) -> CrumblingPlatformView {
        typealias P = RunnerWorld.DressingPalette
        let pier = world.dressing.crumblingPlatform == .woodenPier
        let node = SKNode()
        node.position = CGPoint(x: platform.start, y: Metrics.groundY)
        courseLayer.addChild(node)

        let length = platform.length
        let top = platform.top
        // 揺れる部分。板・縄・ひびをここへぶら下げ、`sync` がこのノードごと上下に震わせる
        // （板 1 枚ずつ揺らすと、抜け落ちる途中の板だけ位相がずれてばらばらに見える）。
        let deck = SKNode()
        node.addChild(deck)

        // 袂の柱（吊り橋）／付け根の杭（桟橋）。**揺れない**＝崩れても残る、この区間の縁の目印。
        for x in [0.0, length] {
            let post = SKSpriteNode(
                color: RunnerPalette.color(P.crumblePost),
                size: CGSize(width: 1.4, height: pier ? top + 1.0 : top + 3.5)
            )
            post.anchorPoint = CGPoint(x: 0.5, y: 0)
            post.position = CGPoint(x: x, y: pier ? -Self.roadHeight : 0)
            post.zPosition = 1
            node.addChild(post)
        }

        // 板を渡す。1 枚ぶんの幅は走者の体（8）の 1/4 ——1 枚落ちただけでは踏み外さないが、
        // 抜けていく列としては十分細かく見える幅。
        let plankWidth = 2.0
        let gap = 0.5
        let pitch = plankWidth + gap
        let count = max(2, Int((length / pitch).rounded()))
        var planks: [SKNode] = []
        for i in 0..<count {
            let x = length * Double(i) / Double(count)
            let plank = SKSpriteNode(
                color: RunnerPalette.color(P.crumbleDeck),
                size: CGSize(width: plankWidth, height: 1.6)
            )
            plank.anchorPoint = CGPoint(x: 0, y: 1)
            plank.position = CGPoint(x: x, y: top)
            plank.zPosition = 3
            // 木目（板の下側の影）。板と別ノードにすると枚数が倍になるので、子 1 つで済ませる。
            let seam = SKSpriteNode(
                color: RunnerPalette.color(P.crumbleDeckSeam),
                size: CGSize(width: plankWidth, height: 0.45)
            )
            seam.anchorPoint = CGPoint(x: 0, y: 1)
            seam.position = CGPoint(x: 0, y: -1.6)
            plank.addChild(seam)
            deck.addChild(plank)
            planks.append(plank)
        }

        var carriers: [SKNode] = []
        if pier {
            // 桟橋: 板を載せる桁（横木）と、海へ落ちる杭。桁は板と一緒に落ちる。
            let beam = SKSpriteNode(
                color: RunnerPalette.color(P.crumblePost),
                size: CGSize(width: length, height: 0.8)
            )
            beam.anchorPoint = .zero
            beam.position = CGPoint(x: 0, y: top - 2.6)
            beam.zPosition = 2
            deck.addChild(beam)
            carriers.append(beam)
            var x = pitch * 3
            while x < length - pitch {
                let pile = SKSpriteNode(
                    color: RunnerPalette.color(P.crumblePost),
                    size: CGSize(width: 1.0, height: top - 2.6 + Self.roadHeight)
                )
                pile.anchorPoint = CGPoint(x: 0.5, y: 1)
                pile.position = CGPoint(x: x, y: top - 2.6)
                pile.zPosition = 1
                deck.addChild(pile)
                carriers.append(pile)
                x += pitch * 4
            }
        } else {
            // 吊り橋: 主索（両端の柱の頭から板の高さまで垂れる）と吊り索。
            let cable = CGMutablePath()
            let headY = top + 3.0
            cable.move(to: CGPoint(x: 0, y: headY))
            cable.addQuadCurve(
                to: CGPoint(x: length, y: headY),
                control: CGPoint(x: length / 2, y: top - 2.2)
            )
            let cableNode = SKShapeNode(path: cable)
            cableNode.strokeColor = RunnerPalette.color(P.crumbleRope)
            cableNode.lineWidth = 0.6
            cableNode.fillColor = .clear
            cableNode.zPosition = 2
            deck.addChild(cableNode)
            carriers.append(cableNode)

            let hangers = CGMutablePath()
            var x = pitch * 2
            while x < length - pitch {
                // 主索の高さ（上の 2 次曲線）から板まで垂らす。
                let t = x / length
                let y = (1 - t) * (1 - t) * headY + 2 * (1 - t) * t * (top - 2.2) + t * t * headY
                hangers.addRect(CGRect(x: x - 0.2, y: top, width: 0.4, height: max(0, y - top)))
                x += pitch * 3
            }
            let hangerNode = SKShapeNode(path: hangers)
            hangerNode.fillColor = RunnerPalette.color(P.crumbleRope)
            hangerNode.strokeColor = .clear
            hangerNode.zPosition = 2
            deck.addChild(hangerNode)
            carriers.append(hangerNode)
        }

        // 崩れる予告のひび。乗るまでは透明で、揺れているあいだに濃くなる
        // （決裁「崩れ始めの予告（揺れ・ひび）が見える」）。
        let cracks = CGMutablePath()
        var cx = pitch * 2.5
        while cx < length - pitch {
            cracks.addRect(CGRect(x: cx, y: top - 1.5, width: 0.35, height: 1.5))
            cracks.addRect(CGRect(x: cx + 0.35, y: top - 0.9, width: 1.6, height: 0.3))
            cx += pitch * 5
        }
        let crackNode = SKShapeNode(path: cracks)
        crackNode.fillColor = RunnerPalette.color(P.crumbleCrack)
        crackNode.strokeColor = .clear
        crackNode.zPosition = 4
        crackNode.alpha = 0
        deck.addChild(crackNode)

        return CrumblingPlatformView(
            deck: deck, planks: planks, cracks: crackNode, carriers: carriers, top: top
        )
    }

    /// 板が抜け始める時刻を左右にずらす幅（抜け落ち時間に対する割合）。
    ///
    /// 左端の板は抜け落ちの頭（`fallen == 0`）で、右端の板は `fallen == stagger` で落ち始め、
    /// どれも `1 - stagger` かけて消える。**「消えた縁」が板張りの右端に届くのはちょうど
    /// `fallen == 1`**（＝当たり判定が穴に変わる瞬間）で、絵と当たり判定がずれない。
    ///
    /// 消えた縁は 1 次式なので、両端で走者より後ろなら途中も後ろ——
    /// 「板張りの長さ < 速さ × `crumbleDuration`」（`RunnerRules.crumbleMaxLength(at:)`）が
    /// 成り立つ限り、残った板を踏み外すことも、足の下の板が先に消えることも無い。
    static let crumblePlankStagger: Double = 0.75

    /// 崩れの進みを絵へ写す（`sync` から毎フレーム）。
    ///
    /// - 乗るまで: 何も起きない
    /// - 揺れ（`RunnerRules.crumbleWarnDuration` まで）: 板ごと上下に震え、ひびが濃くなる
    /// - 抜け落ち: **左から順に**板が落ちて薄くなる。落ちる縁は走者に追いつかない
    ///   （`RunnerRules.crumbleFallDuration`）ので、残った板の上を走っている限り踏み外さない
    /// - 崩れ切ったあと: 板も縄／桁も消え、下の谷（川・海）がそのまま見える
    func syncCrumblingPlatforms(_ field: RunnerField) {
        for (index, view) in crumblingPlatformNodes {
            guard let progress = field.crumbleProgress(index) else {
                view.deck.position = .zero
                view.cracks.alpha = 0
                continue
            }
            let elapsed = progress * RunnerRules.crumbleDuration
            let warn = RunnerRules.crumbleWarnDuration

            // 揺れ。抜け落ちが始まってからは振れ幅を倍にして「もう保たない」を見せる。
            let amplitude = elapsed < warn ? 0.35 : 0.7
            view.deck.position = CGPoint(x: 0, y: sin(elapsed * 34) * amplitude)

            let fallen = max(0, (elapsed - warn) / RunnerRules.crumbleFallDuration)
            // ひびは板の上の模様なので、**板が抜けるのと同じ割合で消す**。濃さだけを見て
            // 描き続けると、板が全部落ちたあとに宙へひびだけが残る。
            view.cracks.alpha = CGFloat(min(1, elapsed / warn) * (1 - min(1, fallen)))
            for (i, plank) in view.planks.enumerated() {
                // この板が抜け始める割合。左端が 0、右端が `Self.crumblePlankStagger`。
                //
                // **右端を 1 にしない**のが要点。1 だと右端の板は「崩れ切る瞬間」にようやく
                // 落ち始めることになり、足場が穴として扱われたあとも板が残って見える
                // （PR #1113 の指摘）。1 枚が落ち切るのに残りの `1 - stagger` を使うので、
                // **右端の板もちょうど `fallen == 1` で消える**。
                let order = Double(i) / Double(max(1, view.planks.count - 1))
                let drop = fallen - order * Self.crumblePlankStagger
                guard drop > 0 else {
                    plank.position = CGPoint(x: plank.position.x, y: view.top)
                    plank.alpha = 1
                    continue
                }
                let fall = min(1, drop / (1 - Self.crumblePlankStagger))
                plank.position = CGPoint(
                    x: plank.position.x,
                    y: view.top - Metrics.groundY * fall * fall
                )
                plank.alpha = CGFloat(1 - fall)
            }
            let carrierAlpha = CGFloat(max(0, 1 - max(0, fallen - 0.6) / 0.4))
            for carrier in view.carriers { carrier.alpha = carrierAlpha }
        }
    }
}
