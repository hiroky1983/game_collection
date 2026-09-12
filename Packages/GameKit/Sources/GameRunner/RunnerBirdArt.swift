import CoreGraphics
import Foundation

/// 鳥（`RunnerHazardKind.bird`）の絵の寸法（#609）。
///
/// `RunnerScene.addBird` の中に直書きしていた座標をここへ出してある。狙いは
/// **絵が当たり判定の矩形（幅 `width` × 高さ `height`）からはみ出していないことを
/// 数値で検証できるようにする**こと——SpriteKit のノードを作らずに済むので、
/// `BirdArtTests` がシミュレータ抜きで張り出しを測れる。
///
/// 直書きだった頃は絵のほうが箱の **1.5 倍**の幅があり、走者は鳥のくちばしを
/// すり抜けてから当たり、尾羽をすり抜けたあとは当たらない状態だった
/// （#609・PR #607 の CodeRabbit 指摘を当番が数値で追試）。`addBird` の doc コメントは
/// 「絵は矩形の内側に収まる寸法で組む」と書いていたが、実際には収まっていなかった。
///
/// はみ出していた 3 パーツ（くちばし・尾羽・翼）の寸法を**箱から導出する**形に変えてある:
///
/// - くちばしの先端がちょうど `width`（走者側の端）に来るように胴の中心 x を決める
/// - 奥の翼が羽ばたきの端まで振れたとき、その先端がちょうど 0（後端）に来るように翼の倍率を決める
/// - 長いほうの尾羽の先端がちょうど 0 に来るように尾羽の長さを決める
/// - 一番低いパーツ（畳んだ足）がちょうど 0（箱の床）に来るように胴の中心 y を決める
///
/// つまり絵は**箱の幅ちょうどいっぱい**で、横方向のはみ出しも余りもない。会長QA
/// 「箱いっぱいに大きく・シルエットで正体が分かるように」（2026-09-10）はこの形で満たす。
/// 胴は以前より小さくなるが（半径 1.54 → 1.16）、これは幅 4 の箱に収まる上限であり、
/// 翼・尾羽の長さと胴の比（1.5 倍前後）は以前の見た目から保っている。
///
/// **箱は当たり判定の「帯」そのもの**（#671）。鳥の当たり判定は地面から生えた矩形ではなく
/// 空中の帯 `[bottom, height]`（13〜22）なので、ここの `height` には**帯の高さ**
/// （上端 − 下端）を渡し、`addBird` が帯の床の位置へ置く。`groundDrop` は帯の床から
/// 地面までの落差で、影だけがそのぶん下（地面）へ降りる。
///
/// 縦は**床合わせ**にしてある（#609 の頃は天井合わせだった）。帯の床は
/// 「接地してくぐれる／跳ぶと当たる」の境目そのもので、ここに絵の無いすき間を残すと
/// 「鳥の下を通ったのに当たった」になる。逆に天井側は 2 段ジャンプでしか届かない高さで、
/// 幅 1 タイルの鳥では絵の縦横比が足りず帯の高さ（9）を埋めきれない——**埋めきれない余りは
/// 必ず天井側に寄せる**、というのがこの合わせ方の意味。
///
/// 座標系は `addBird` のローカル系と同じで、**x は 0（後端）から `width`（走者側の端）へ、
/// y は 0（帯の床）から `height`（帯の天井）へ**。`addBird` はこれを丸ごと左右反転して置く。
struct RunnerBirdArt {
    /// 当たり判定の矩形の幅（`RunnerHazard.length`）。
    let width: Double
    /// 当たり判定の帯の高さ（`RunnerHazard.height - RunnerHazard.bottom`）。
    let height: Double
    /// 帯の床から地面までの落差（`RunnerHazard.bottom`）。影はこのぶん下に敷く。
    let groundDrop: Double

    /// 羽ばたき・尾羽のように回転するパーツ。`points` は `pivot` を原点とした座標で、
    /// `rotation` の範囲いっぱいに回る（羽ばたきの両端）。
    struct RotatingPart {
        let pivot: CGPoint
        let points: [CGPoint]
        let rotation: ClosedRange<Double>
    }

    /// 回らないパーツ（尾羽）。`points` は `anchor` を原点とした座標。
    struct FixedPart {
        let anchor: CGPoint
        let points: [CGPoint]
    }

    /// 丸いパーツ（胴・頭・腹・目）。
    struct Disc {
        let center: CGPoint
        let radius: Double
    }

    // MARK: 体

    let bodyRadius: Double
    let bodyCenter: CGPoint
    let headRadius: Double
    let headCenter: CGPoint
    /// くちばしの三角形（`headCenter` を原点とした座標）。
    let beak: FixedPart
    /// 腹（明るい差し色）。単色の玉に見えないよう下面を明るくする。
    let belly: Disc
    /// 目（白目と黒目）。暗緑に暗色の点では見えないので白目を敷く。
    let eyeWhite: Disc
    let pupil: Disc
    /// 畳んだ足。飛行中の鳥は足を体へ引き込むので、ぶら下げず腹の後ろ寄りに小さく畳む。
    /// 傾いた矩形なので、張り出しは 4 隅を回して測る。
    let foot: RotatingPart
    /// 足の矩形の大きさ（`foot.pivot` を中心に置く）。
    let footSize: CGSize

    // MARK: 付属物

    /// 尾羽 2 枚（長いほうが先）。
    let tails: [FixedPart]
    /// 奥の翼（胴の向こう側・逆位相）。
    let farWing: RotatingPart
    /// 手前の翼。
    let nearWing: RotatingPart

    // MARK: 動き

    /// 浮遊の振れ幅。体はこの高さぶん**上へ**動く（下へは動かない）。
    let bobAmplitude: Double

    // MARK: 地面

    /// 影の大きさ。体とのすき間が「飛んでいる」ことの一番の手がかりなので、
    /// 浮遊には追従させない（`addBird` が `bobber` の外に置く）。
    let shadowSize: CGSize
    let shadowCenter: CGPoint

    /// 見た目の比率。箱の寸法から各パーツを導くときの係数で、**ここを動かすと
    /// `BirdArtTests` が張り出しを測り直す**。
    private enum Ratio {
        /// 箱の高さに対する胴の半径。幅 4 の箱に収まる上限（`bodyCenter.x - bodyRadius >= 0`）は
        /// およそ 0.216 で、翼と尾羽に胴の 1.5 倍ぶんの長さを残すとここに落ち着く。
        static let body = 0.165
        /// 胴の半径に対する頭の半径・付け根の位置。
        static let head = 0.66
        static let headOffsetX = 0.62
        static let headOffsetY = 0.55
        /// 頭の半径に対するくちばしの先端。遠目でも尖りが分かる長さ。
        static let beakReach = 1.55
        /// 浮遊の振れ幅（箱の高さに対する比）。
        static let bob = 0.064
        /// 2 枚目の尾羽の長さ（1 枚目に対する比）。
        static let shortTail = 0.909
    }

    /// 翼の形（倍率 1 のときの座標）。肩を軸に回すので、付け根が原点で後方へ伸びる。
    private static let wingShape: [CGPoint] = [
        CGPoint(x: 0, y: 0.35),
        CGPoint(x: -1.1, y: 0.65),
        CGPoint(x: -2.8, y: 0.3),
        CGPoint(x: -0.9, y: -0.45),
    ]

    /// 尾羽の付け根の位置と振り上げ（いずれも胴の半径に対する比）。
    private static let tailSpecs: [(dx: Double, dy: Double, lift: Double)] = [
        (0.097, 0.227, 0.714),
        (0.162, -0.032, 0.390),
    ]
    /// 尾羽の三角形の厚み（胴の半径に対する比）。
    private static let tailThickness = 0.455

    /// 帯（幅 `width` × 高さ `height`）に収まる鳥を組む。`groundDrop` は帯の床から
    /// 地面までの落差で、影だけがそのぶん下へ降りる（#671）。
    ///
    /// 胴の中心 y は**一度 0 に置いて組んだ下組みを測り、一番低いパーツが帯の床（0）に
    /// 来るだけ持ち上げて**決める。持ち上げ量を手で計算しないのは、パーツを 1 つ足したときに
    /// 計算のほうを直し忘れて絵が床から浮く（＝くぐったのに当たる帯が下に残る）のを防ぐため
    /// ——測るのは `birdVerticalExtent`、すなわち `BirdArtTests` が見るのと同じ値。
    init(width: Double, height: Double, groundDrop: Double = 0) {
        let probe = RunnerBirdArt(width: width, height: height, groundDrop: groundDrop, centerY: 0)
        self.init(
            width: width, height: height, groundDrop: groundDrop,
            centerY: -probe.birdVerticalExtent.lowerBound
        )
    }

    private init(width: Double, height: Double, groundDrop: Double, centerY: Double) {
        self.width = width
        self.height = height
        self.groundDrop = groundDrop

        let bodyRadius = height * Ratio.body
        let headRadius = bodyRadius * Ratio.head
        self.bodyRadius = bodyRadius
        self.headRadius = headRadius
        bobAmplitude = height * Ratio.bob

        // 胴の中心 x は「くちばしの先端が箱の走者側の端に一致する」ことから決める。
        let beakTipFromBody = bodyRadius * Ratio.headOffsetX + headRadius * Ratio.beakReach
        let centerX = width - beakTipFromBody

        // 尾羽の長さは「長いほうの先端が箱の後端に一致する」ことから決める。
        let longTailLength = centerX + bodyRadius * Self.tailSpecs[0].dx - bodyRadius * 0.5
        let tailLengths = [longTailLength, longTailLength * Ratio.shortTail]

        // 翼の倍率は「奥の翼が羽ばたきの端まで振れたとき、その先端が箱の後端に一致する」
        // ことから決める。手前の翼は肩が前寄りなので、同じ倍率でも後端には届かない。
        let farPivotX = centerX - bodyRadius * 0.35
        let farRotation = -0.2...0.7
        let wingReach = -Self.rotatedXRange(Self.wingShape, farRotation).lowerBound
        let wingScale = wingReach > 0 ? farPivotX / wingReach : 0
        let wingShape = Self.wingShape.map { CGPoint(x: $0.x * wingScale, y: $0.y * wingScale) }

        let nearRotation = -0.55...0.55
        let bodyCenter = CGPoint(x: centerX, y: centerY)
        self.bodyCenter = bodyCenter
        headCenter = CGPoint(
            x: centerX + bodyRadius * Ratio.headOffsetX,
            y: centerY + bodyRadius * Ratio.headOffsetY
        )
        beak = FixedPart(anchor: headCenter, points: [
            CGPoint(x: headRadius * 0.7, y: headRadius * 0.35),
            CGPoint(x: headRadius * Ratio.beakReach, y: -headRadius * 0.05),
            CGPoint(x: headRadius * 0.7, y: -headRadius * 0.45),
        ])
        belly = Disc(
            center: CGPoint(x: centerX + bodyRadius * 0.28, y: centerY - bodyRadius * 0.42),
            radius: bodyRadius * 0.6
        )
        let eyeCenter = CGPoint(
            x: centerX + bodyRadius * Ratio.headOffsetX + headRadius * 0.3,
            y: centerY + bodyRadius * Ratio.headOffsetY + headRadius * 0.18
        )
        eyeWhite = Disc(center: eyeCenter, radius: headRadius * 0.34)
        pupil = Disc(
            center: CGPoint(x: eyeCenter.x + headRadius * 0.12, y: eyeCenter.y),
            radius: headRadius * 0.17
        )
        let footSize = CGSize(width: bodyRadius * 0.584, height: bodyRadius * 0.208)
        self.footSize = footSize
        let halfFoot = (x: Double(footSize.width) / 2, y: Double(footSize.height) / 2)
        foot = RotatingPart(
            pivot: CGPoint(x: centerX + bodyRadius * 0.05, y: centerY - bodyRadius * 0.95),
            points: [
                CGPoint(x: -halfFoot.x, y: -halfFoot.y), CGPoint(x: halfFoot.x, y: -halfFoot.y),
                CGPoint(x: halfFoot.x, y: halfFoot.y), CGPoint(x: -halfFoot.x, y: halfFoot.y),
            ],
            rotation: (-0.3)...(-0.3)
        )
        tails = zip(Self.tailSpecs, tailLengths).map { spec, length in
            FixedPart(
                anchor: CGPoint(x: centerX + bodyRadius * spec.dx, y: centerY + bodyRadius * spec.dy),
                points: Self.tailPoints(bodyRadius: bodyRadius, spec: spec, length: length)
            )
        }
        farWing = RotatingPart(
            pivot: CGPoint(x: farPivotX, y: centerY + bodyRadius * 0.5),
            points: wingShape,
            rotation: farRotation
        )
        nearWing = RotatingPart(
            pivot: CGPoint(x: centerX + bodyRadius * 0.15, y: centerY + bodyRadius * 0.45),
            points: wingShape,
            rotation: nearRotation
        )

        // 影は帯の床ではなく**地面**に敷く（#671）。体とのすき間がそのまま
        // 「この高さを飛んでいる」の手がかりになるので、帯が地面から離れているぶんだけ下げる。
        shadowSize = CGSize(width: width * 0.95, height: 0.55)
        shadowCenter = CGPoint(x: width * 0.5, y: -groundDrop + 0.3)
    }

    private static func tailPoints(
        bodyRadius: Double, spec: (dx: Double, dy: Double, lift: Double), length: Double
    ) -> [CGPoint] {
        let root = -bodyRadius * 0.5
        let lift = bodyRadius * spec.lift
        let thickness = bodyRadius * tailThickness
        return [
            CGPoint(x: root, y: 0),
            CGPoint(x: root - length, y: lift + thickness),
            CGPoint(x: root - length + thickness, y: lift - thickness),
        ]
    }

    // MARK: 張り出しの計測

    /// 丸いパーツの全量。**`addBird` が描く丸はここに漏れなく並べる**——`horizontalExtent` /
    /// `verticalExtent` はこの一覧しか見ないので、ここに載せ忘れたパーツは測られない
    /// （腹・目を載せ忘れていたのを PR #633 の敵対的検証で指摘された）。
    /// （影は丸ではなく平たい楕円なので、ここではなく `extent` が最後に直接足す。）
    var discs: [Disc] { [bodyDisc, headDisc, belly, eyeWhite, pupil] }

    /// 胴・頭を丸として取り出したもの（`addBird` が `discs` と同じ値で描くための入口）。
    var bodyDisc: Disc { Disc(center: bodyCenter, radius: bodyRadius) }
    var headDisc: Disc { Disc(center: headCenter, radius: headRadius) }

    /// 回らない多角形の全量（くちばし・尾羽）。
    var fixedParts: [FixedPart] { [beak] + tails }

    /// 回る多角形の全量（翼・足）。
    var rotatingParts: [RotatingPart] { [farWing, nearWing, foot] }

    /// 絵が占める x の範囲（羽ばたき・浮遊の端まで含む）。当たり判定は `0...width` なので、
    /// **この値が `0...width` に一致していること**が「見た目と判定のズレが無い」の定義。
    var horizontalExtent: ClosedRange<Double> {
        extent(
            axis: { Double($0.x) },
            rotated: { Self.rotatedXRange($0, $1) },
            halfShadow: Double(shadowSize.width) / 2,
            shadowCenter: Double(shadowCenter.x),
            bob: 0
        )
    }

    /// 絵が占める y の範囲。上端は浮遊の一番高いところ、下端は**地面に敷いた影**の底。
    var verticalExtent: ClosedRange<Double> {
        extent(
            axis: { Double($0.y) },
            rotated: { Self.rotatedYRange($0, $1) },
            halfShadow: Double(shadowSize.height) / 2,
            shadowCenter: Double(shadowCenter.y),
            bob: bobAmplitude
        )
    }

    /// 影を除いた、**鳥そのもの**が占める y の範囲（#671）。影は帯の外（地面）に敷くので、
    /// 「絵が帯からはみ出していない」は影を抜いたこちらで見る。下端が 0 に一致することが
    /// 「くぐれる側の縁と絵が合っている」の定義（`init` の持ち上げ量もこれで決めている）。
    var birdVerticalExtent: ClosedRange<Double> {
        extent(
            axis: { Double($0.y) },
            rotated: { Self.rotatedYRange($0, $1) },
            halfShadow: nil,
            shadowCenter: 0,
            bob: bobAmplitude
        )
    }

    /// 上の 3 つの共通処理。片方だけパーツを足す取りこぼしが起きないよう 1 本にまとめてある。
    ///
    /// `bob` は浮遊の振れ幅。体（影以外）はこのぶん**上へ**動くので、y 方向でだけ上端に足す。
    /// `halfShadow` が nil のときは影を数えない。
    private func extent(
        axis: (CGPoint) -> Double,
        rotated: ([CGPoint], ClosedRange<Double>) -> ClosedRange<Double>,
        halfShadow: Double?,
        shadowCenter: Double,
        bob: Double
    ) -> ClosedRange<Double> {
        var lower = Double.infinity, upper = -Double.infinity
        func include(_ low: Double, _ high: Double) {
            lower = min(lower, low)
            upper = max(upper, high)
        }
        for disc in discs {
            include(axis(disc.center) - disc.radius, axis(disc.center) + disc.radius)
        }
        for part in fixedParts {
            let values = part.points.map { axis(part.anchor) + axis($0) }
            include(values.min() ?? 0, values.max() ?? 0)
        }
        for part in rotatingParts {
            let range = rotated(part.points, part.rotation)
            include(axis(part.pivot) + range.lowerBound, axis(part.pivot) + range.upperBound)
        }
        // 影は地面に敷いたままで浮遊に追従しないので、体の分を上げてから足す。
        upper += bob
        if let halfShadow {
            include(shadowCenter - halfShadow, shadowCenter + halfShadow)
        }
        return lower...upper
    }

    /// 原点まわりに `rotation` の範囲で回したときに各点が取る x の範囲。
    ///
    /// 半径 `r`・偏角 `φ` の点は `x(θ) = r·cos(φ + θ)` を描くので、両端の値に加えて
    /// **`cos` が ±1 を取る角を範囲がまたぐか**だけを見れば最大・最小が確定する
    /// （回転角を刻んで探すと、刻み幅の谷間に本当の端が隠れる）。
    static func rotatedXRange(_ points: [CGPoint], _ rotation: ClosedRange<Double>) -> ClosedRange<Double> {
        var lower: Double?, upper: Double?
        for point in points {
            let x = Double(point.x), y = Double(point.y)
            let radius = (x * x + y * y).squareRoot()
            let phase = radius > 0 ? atan2(y, x) : 0
            let range = cosRange(phase + rotation.lowerBound, phase + rotation.upperBound)
            lower = min(lower ?? .infinity, radius * range.lowerBound)
            upper = max(upper ?? -.infinity, radius * range.upperBound)
        }
        return (lower ?? 0)...(upper ?? 0)
    }

    /// 同じく y の範囲。`sin(a) = cos(a - π/2)` なので偏角をずらして使い回す。
    static func rotatedYRange(_ points: [CGPoint], _ rotation: ClosedRange<Double>) -> ClosedRange<Double> {
        let turned = points.map { CGPoint(x: $0.y, y: -$0.x) }
        return rotatedXRange(turned, rotation)
    }

    private static func cosRange(_ from: Double, _ to: Double) -> ClosedRange<Double> {
        var lower = min(cos(from), cos(to))
        var upper = max(cos(from), cos(to))
        if spans(angle: 0, from: from, to: to) { upper = 1 }
        if spans(angle: .pi, from: from, to: to) { lower = -1 }
        return lower...upper
    }

    /// `[from, to]` が `angle + 2πk` を含むか。
    private static func spans(angle: Double, from: Double, to: Double) -> Bool {
        let turn = 2 * Double.pi
        let first = angle + (((from - angle) / turn).rounded(.up)) * turn
        return first <= to
    }
}
