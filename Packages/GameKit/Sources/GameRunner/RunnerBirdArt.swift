import CoreGraphics
import Foundation

/// 鳥（`RunnerHazardKind.bird`）の絵の寸法（#609）。
///
/// #796 で鳥は「近づくと飛び立つ障害」になったが、絵は #671 の飛ぶ鳥をそのまま流用する。
/// 帯は走者の進みで上下する（`RunnerHazard.frame(atRunnerDistance:)`）ので、以下で「帯の床 13」と
/// あるのは**上がりきったとき**の値（`RunnerHazardKind.birdHighBottom`）。変わらないのは
/// **帯の厚み = この絵の高さ**（`bandHeight` → `RunnerHazardKind.birdBandHeight`）で、
/// `BirdArtTests` が固定するのはそこ。
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
/// **縦は絵が当たり判定を決める**（#671・会長決裁 2026-09-12）。鳥の当たり判定は地面から
/// 生えた矩形ではなく空中の帯 `[bottom, height]` で、**帯の上端は `bandHeight`（この絵が
/// 縦に占める寸法）そのもの**。`RunnerHazardKind.bird.height` がここから導出される
/// ——横の #609 と同じ考え方を縦にも通し、絵と判定がズレる余地を型から消してある。
///
/// #622 D案の決裁値は帯 `[13, 22]` だったが、上端 22 は**絵より 4.66 単位上まで即死の帯**
/// （幅 1 タイルの鳥は縦横比の都合で 4.34 しか埋められない）になっていた。これは
/// 「見えている鳥を跳び越したのに当たる」という #609 で潰したはずの理不尽そのものなので、
/// 会長決裁で上端を絵に合わせて下げた。**本質は下端 13**（接地でくぐれる／跳べば当たる）で、
/// そこは 1 ミリも動いていない。2 段ジャンプで上を抜けられる余裕が広がるのは意図した結果で、
/// 上手い人の抜け道として残す。
///
/// 縦は**床合わせ**にしてある（#609 の頃は天井合わせだった）。帯の床は
/// 「接地してくぐれる／跳ぶと当たる」の境目そのもので、ここに絵の無いすき間を残すと
/// 「鳥の下を通ったのに当たった」になる。天井は絵の頂点（浮遊の上端）に一致する。
///
/// 大きさを決めるのは**幅だけ**。胴の半径は幅 4 の箱に収まる上限で決まっており
/// （`Ratio.body`）、縦は各パーツを積んだ結果として決まる——縦を入力にすると
/// 「帯の高さ ← 絵の高さ ← 帯の高さ」の循環になる。
///
/// 座標系は `addBird` のローカル系と同じで、**x は 0（後端）から `width`（走者側の端）へ、
/// y は 0（帯の床）から `bandHeight`（帯の天井）へ**。`addBird` はこれを丸ごと左右反転して置く。
///
/// **見た目の倍率**（#943・会長QA 2026-09-15「鳥が小さすぎて見えない」）。上の「箱いっぱい」で
/// 組むと幅 1 タイルの鳥は胴の半径が 1.5 弱にしかならず、実機では豆粒だった。当たり判定
/// （帯の床 13・厚み・横幅 1 タイル）とジャンプ物理は会長決裁（2026-09-12）のまま動かさず、
/// **絵だけ `visualScale` 倍に描く**。つまり絵は当たり判定より大きく、
///
/// - **横は帯に中央合わせ**: 前後に `width × (visualScale − 1) / 2` ずつ張り出す
/// - **縦は床合わせのまま**: 絵の底は帯の床に一致し、頂点だけ帯の天井より上へ出る
///
/// 「絵が当たり判定より大きい」方向のズレは、**触れて見えるのに当たらない**（走者に甘い）
/// だけで、#609 で潰した「見えていないのに当たる」理不尽は起きない。床を合わせたままに
/// するのは、帯の床 13 が「接地でくぐれる」の境目で、そこに絵を下ろすと接地した頭（11）と
/// 見た目で触れそうになるから。帯の厚み（`bandHeight`）は**倍率 1 で組んだ絵**から測るので、
/// 倍率を動かしても当たり判定は 1 ミリも変わらない（`BirdArtTests` が固定する）。
struct RunnerBirdArt {
    /// 見た目の倍率の既定値（#943）。会長の目安「胴・翼が今の 1.4〜1.6 倍」の中央。
    /// **当たり判定にはいっさい効かない**（`bandHeight` は倍率 1 で測る）。1 未満にすると
    /// 絵より当たり判定が大きくなる（#609 の理不尽）ので、`BirdArtTests` が 1 以上を固定する。
    static let defaultVisualScale = 1.5

    /// 当たり判定の矩形の幅（`RunnerHazard.length`）。**帯の厚みはこれだけで決まる**。
    let width: Double
    /// 帯の床から地面までの落差（`RunnerHazard.bottom`）。影はこのぶん下に敷く。
    let groundDrop: Double
    /// 見た目の倍率（#943）。絵は幅 `width × visualScale` の箱いっぱいに組む。
    let visualScale: Double
    /// 絵を組む箱の x 範囲。幅 `width × visualScale` で当たり判定 `0...width` に中央合わせ。
    /// 倍率 1 なら `0...width` そのもの。
    let drawnRange: ClosedRange<Double>
    /// **当たり判定の帯の高さ**（#671・会長決裁 2026-09-12）。**倍率 1 で組んだ絵**が縦に占める
    /// 寸法で、`RunnerHazardKind.bird.height`（帯の上端）はこの値から導出される。
    ///
    /// 浮遊の振れ幅（`bobAmplitude`）を含む——鳥は一番上まで浮いた瞬間にもそこにいるので、
    /// そこを帯の外にすると「絵に触れたのに当たらない」逆の理不尽になる。
    ///
    /// `visualScale` には**依存しない**（#943）。絵を大きく描いても帯は倍率 1 の寸法のままで、
    /// 描いた絵の頂点（`birdVerticalExtent.upperBound`）はこの値の `visualScale` 倍になる。
    let bandHeight: Double

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
    /// `BirdArtTests` が張り出しを測り直す**。「箱」は絵を組む箱（`drawnRange`。倍率 1 なら
    /// 当たり判定そのもの、#943 以降は当たり判定の `visualScale` 倍）。
    private enum Ratio {
        /// **箱の幅**に対する胴の半径。幅 4 の箱に収まる上限（`bodyCenter.x - bodyRadius >= 0`）は
        /// およそ 0.378 で、翼と尾羽に胴の 1.5 倍ぶんの長さを残すとここに落ち着く。
        ///
        /// 以前は箱の高さ（帯の高さ 9）に対する 0.165 として書いていた。**帯の上端を絵に
        /// 合わせた（#671・会長決裁 2026-09-12）ことで縦を入力に使えなくなった**ので、
        /// 実際に大きさを縛っている幅を基準に読み替えてある（9 × 0.165 = 4 × 0.37125 = 1.485 で
        /// 絵は 1 ミリも変わらない）。
        static let body = 0.37125
        /// 胴の半径に対する頭の半径・付け根の位置。
        static let head = 0.66
        static let headOffsetX = 0.62
        static let headOffsetY = 0.55
        /// 頭の半径に対するくちばしの先端。遠目でも尖りが分かる長さ。
        static let beakReach = 1.55
        /// 浮遊の振れ幅（**箱の幅**に対する比。`body` と同じ理由で幅基準に読み替えてあり、
        /// 9 × 0.064 = 4 × 0.144 = 0.576 で振れ幅は変わらない）。
        static let bob = 0.144
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

    /// 幅 `width` の帯に合わせた鳥を組む。`groundDrop` は帯の床から地面までの落差で、
    /// 影だけがそのぶん下へ降りる（#671）。**帯の高さは入力ではなく結果**（`bandHeight`）。
    /// `visualScale` は見た目の倍率（#943）で、絵だけを大きくし帯の高さには効かない。
    ///
    /// 胴の中心 y は**一度 0 に置いて組んだ下組みを測り、一番低いパーツが帯の床（0）に
    /// 来るだけ持ち上げて**決める。持ち上げ量を手で計算しないのは、パーツを 1 つ足したときに
    /// 計算のほうを直し忘れて絵が床から浮く（＝くぐったのに当たる帯が下に残る）のを防ぐため
    /// ——測るのは `birdVerticalExtent`、すなわち `BirdArtTests` が見るのと同じ値。
    ///
    /// 帯の厚みも同じ手順で、ただし**倍率 1 の下組み**を測って決める。各パーツの寸法は幅に
    /// 比例するので「倍率 1 の高さ = 描いた高さ ÷ 倍率」でも同じ値になるが、その比例関係を
    /// 前提にせず実際に倍率 1 で組んで測る——固定寸法のパーツを足したときに帯が黙って
    /// 動くのを防ぐため。
    init(width: Double, groundDrop: Double = 0, visualScale: Double = Self.defaultVisualScale) {
        let unit = RunnerBirdArt(
            width: width, groundDrop: groundDrop, visualScale: 1, centerY: 0, bandHeight: 0
        )
        let unitExtent = unit.birdVerticalExtent
        let bandHeight = unitExtent.upperBound - unitExtent.lowerBound
        let drawn = RunnerBirdArt(
            width: width, groundDrop: groundDrop, visualScale: visualScale, centerY: 0, bandHeight: 0
        )
        self.init(
            width: width, groundDrop: groundDrop, visualScale: visualScale,
            centerY: -drawn.birdVerticalExtent.lowerBound, bandHeight: bandHeight
        )
    }

    private init(
        width: Double, groundDrop: Double, visualScale: Double, centerY: Double, bandHeight: Double
    ) {
        self.width = width
        self.groundDrop = groundDrop
        self.visualScale = visualScale
        self.bandHeight = bandHeight

        // 絵を組む箱（#943）。当たり判定 `0...width` を `visualScale` 倍に広げ、中央を揃える。
        // 以下の「箱の後端／走者側の端」はすべてこの箱の縁を指す。
        let drawnWidth = width * visualScale
        let rear = (width - drawnWidth) / 2
        drawnRange = rear...(rear + drawnWidth)

        let bodyRadius = drawnWidth * Ratio.body
        let headRadius = bodyRadius * Ratio.head
        self.bodyRadius = bodyRadius
        self.headRadius = headRadius
        bobAmplitude = drawnWidth * Ratio.bob

        // 胴の中心 x は「くちばしの先端が箱の走者側の端に一致する」ことから決める。
        let beakTipFromBody = bodyRadius * Ratio.headOffsetX + headRadius * Ratio.beakReach
        let centerX = rear + drawnWidth - beakTipFromBody

        // 尾羽の長さは「長いほうの先端が箱の後端に一致する」ことから決める。
        let longTailLength = (centerX - rear) + bodyRadius * Self.tailSpecs[0].dx - bodyRadius * 0.5
        let tailLengths = [longTailLength, longTailLength * Ratio.shortTail]

        // 翼の倍率は「奥の翼が羽ばたきの端まで振れたとき、その先端が箱の後端に一致する」
        // ことから決める。手前の翼は肩が前寄りなので、同じ倍率でも後端には届かない。
        let farPivotX = centerX - bodyRadius * 0.35
        let farRotation = -0.2...0.7
        let wingReach = -Self.rotatedXRange(Self.wingShape, farRotation).lowerBound
        let wingScale = wingReach > 0 ? (farPivotX - rear) / wingReach : 0
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
        // 幅は絵（`drawnWidth`）に合わせる（#943。体だけ大きくして影が小さいままだと浮いて見えない）。
        // 中心は当たり判定の中央＝絵の中央なので倍率で動かない。
        shadowSize = CGSize(width: drawnWidth * 0.95, height: 0.55)
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

    /// 絵が占める x の範囲（羽ばたき・浮遊の端まで含む）。絵は `drawnRange` の箱いっぱいに
    /// 組むので**この値が `drawnRange` に一致する**。当たり判定は `0...width` で、倍率 1 なら
    /// 両者は同じ（#609 の「見た目と判定のズレが無い」）。倍率が 1 を超えると絵のほうが
    /// 当たり判定を包む（#943。**逆に当たり判定が絵から出ることは無い**）。
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
    /// 「絵が帯の床から浮いていない」は影を抜いたこちらで見る。下端が 0 に一致することが
    /// 「くぐれる側の縁と絵が合っている」の定義（`init` の持ち上げ量もこれで決めている）。
    /// 上端は倍率 1 なら `bandHeight` に一致し、倍率ぶん大きく描くとその倍率だけ帯の天井より
    /// 上へ出る（#943）。
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
