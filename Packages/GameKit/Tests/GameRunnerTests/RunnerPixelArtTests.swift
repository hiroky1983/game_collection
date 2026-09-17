import Core
import GameKitTestSupport
import Testing
@testable import GameRunner

/// チャリンコおじさんのドット絵（走者以外・`RunnerPixelArt`）が壊れていないこと（#956）。
/// `PixelArtTests`（走者）と同じく、縛るのは「格子が揃っている」「パレットに無い文字が無い」
/// 「寸法が決裁どおり」で、絵の良し悪しは撮影で見る。
@Suite("走者以外のドット絵（#956）")
struct RunnerPixelArtTests {
    /// ここに集めた絵をすべて走査する。絵を足したらこの表にも足す。犬・イノシシは色が世界ごと
    /// （`RunnerPixelArt.creaturePalette`）なので全世界ぶん並べる。
    private static let sprites: [(name: String, sprite: PixelSprite)] =
        [("たこ焼き", RunnerPixelArt.takoyaki())] + RunnerWorld.allCases.flatMap { world in
            RunnerPixelArt.WalkFrame.allCases.flatMap { frame in
                [
                    ("犬 \(frame)（\(world)）", RunnerPixelArt.dog(frame, colors: world.creatures)),
                    ("イノシシ \(frame)（\(world)）", RunnerPixelArt.boar(frame, colors: world.creatures)),
                ]
            }
        }

    @Test("行の長さが揃い、パレットに無い文字が無く、空でない")
    func spritesAreWellFormed() {
        for (name, s) in Self.sprites {
            #expect(s.width > 0 && s.height > 0, "\(name): 空")
            #expect(s.rows.allSatisfy { $0.count == s.width }, "\(name): 行の長さが揃っていない")
            #expect(s.undefinedKeys.isEmpty, "\(name): パレットに無い文字 \(s.undefinedKeys)")
            #expect(s.opaqueBounds != nil, "\(name): 不透明なドットが無い")
        }
    }

    /// 決裁（#956）: 走者の頭くらい = 高さ 16〜18 ドット（1 ドット ≒ 0.33 単位で 5〜6 単位）。
    /// シーン側は `anchorPoint = (0.5, 0)` で絵の底の中央を置き場に合わせるので、格子に透明な
    /// 余白の行・列が無いこと（不透明部分 = 格子全体）も固定する。
    @Test("たこ焼きは高さ 16〜18 ドットで、格子に余白が無い")
    func takoyakiFitsTheApprovedSize() throws {
        let s = RunnerPixelArt.takoyaki()
        let b = try #require(s.opaqueBounds)
        #expect((16...18).contains(b.height), "高さ \(b.height) ドット")
        #expect(b.x == 0 && b.y == 0 && b.width == s.width && b.height == s.height, "余白: \(b)")
        // 底の行の中央にドットがある（原点 = 底の中央が絵の上に乗る）。
        let bottom = Array(s.rows[s.height - 1])
        #expect(bottom[s.width / 2] != ".", "底の中央が透明")
    }

    /// #929 の規則: 手前の物は暗い縁取りで浮かせる。縁取り `K` はどの色より暗く、格子の外周
    /// （不透明部分の外側に接するドット）はすべて縁取りであること。たこ焼きも犬・イノシシも同じ。
    @Test("外周はすべて縁取りで、縁取りはどの色より暗い")
    func spritesAreOutlined() {
        for (name, s) in Self.sprites {
            let rows = s.rows.map(Array.init)
            func isTransparent(_ x: Int, _ y: Int) -> Bool {
                x < 0 || y < 0 || y >= s.height || x >= s.width || rows[y][x] == "."
            }
            for y in 0..<s.height {
                for x in 0..<s.width where rows[y][x] != "." {
                    let exposed = isTransparent(x - 1, y) || isTransparent(x + 1, y)
                        || isTransparent(x, y - 1) || isTransparent(x, y + 1)
                    if exposed { #expect(rows[y][x] == "K", "\(name): (\(x), \(y)) の \(rows[y][x]) が外気に触れている") }
                }
            }
            let outline = WCAG.relativeLuminance(s.palette["K"] ?? 0)
            for (key, color) in s.palette where key != "K" {
                #expect(WCAG.relativeLuminance(color) > outline, "\(name): \(key) が縁取りより暗い")
            }
        }
    }

    // MARK: 犬・イノシシ（#975）

    /// 格子の底から数えて「不透明な範囲が 2 つ以上に割れている行」が続く高さ = 脚の高さ。
    /// 胴に入ると 1 つの連続した範囲になるので、そこで数えるのをやめる。
    private static func legHeight(of rows: [String]) -> Int {
        var height = 0
        for row in rows.reversed() {
            var runs = 0
            var inRun = false
            for ch in row {
                if ch != "." { if !inRun { runs += 1; inRun = true } } else { inRun = false }
            }
            guard runs >= 2 else { break }
            height += 1
        }
        return height
    }

    /// 会長 QA（2026-09-15）「犬とイノシシ、足長い」→ 受け入れ条件: 脚の高さは全体の 1/4 以下。
    @Test("犬・イノシシの脚の高さは全体の 1/4 以下", arguments: [
        ("犬 walk0", RunnerPixelArt.dogWalk0Rows), ("犬 walk1", RunnerPixelArt.dogWalk1Rows),
        ("イノシシ walk0", RunnerPixelArt.boarWalk0Rows), ("イノシシ walk1", RunnerPixelArt.boarWalk1Rows),
    ])
    func animalLegsAreShort(name: String, rows: [String]) {
        let legs = Self.legHeight(of: rows)
        #expect(legs > 0, "\(name): 脚が見つからない")
        #expect(Double(legs) <= Double(rows.count) / 4, "\(name): 脚 \(legs) 行 / 全体 \(rows.count) 行")
    }

    /// 決裁（#975）: 犬 ≒ 幅 10 × 高さ 7 単位（30×21 ドット）、イノシシ ≒ 幅 11 × 高さ 7.5 単位
    /// （33×23 ドット）。走者の頭までが 36 ドットなので、どちらも走者の背丈の 6 割前後で
    /// 「おじさんと同じ位の大きさ」（#943）を保つ。絵の周りに透明な余白の行・列は無い
    /// （シーン側は絵の底・左端をそのまま置き場に合わせる）。
    @Test("犬は 30×21・イノシシは 33×23 ドットで、格子に余白が無い")
    func animalsFitTheApprovedSize() throws {
        for frame in RunnerPixelArt.WalkFrame.allCases {
            let dog = RunnerPixelArt.dog(frame, colors: RunnerWorld.morning.creatures)
            let boar = RunnerPixelArt.boar(frame, colors: RunnerWorld.morning.creatures)
            #expect((28...32).contains(dog.width) && (19...23).contains(dog.height), "犬 \(frame): \(dog.width)×\(dog.height)")
            #expect((31...35).contains(boar.width) && (21...25).contains(boar.height), "イノシシ \(frame): \(boar.width)×\(boar.height)")
            for (name, s) in [("犬", dog), ("イノシシ", boar)] {
                let b = try #require(s.opaqueBounds)
                #expect(b.x == 0 && b.y == 0 && b.width == s.width && b.height == s.height, "\(name) \(frame) の余白: \(b)")
            }
        }
    }

    /// 2 コマは脚だけが違う。胴・頭は同じ格子（`syncMovingHazards` がテクスチャを貼り替えるだけで、
    /// スプライトの寸法・原点は `walk0` の格子で決めているため）。
    @Test("犬・イノシシの 2 コマは同じ寸法で、脚より上は同じ絵")
    func walkFramesShareTheBody() {
        for (name, walk0, walk1) in [
            ("犬", RunnerPixelArt.dogWalk0Rows, RunnerPixelArt.dogWalk1Rows),
            ("イノシシ", RunnerPixelArt.boarWalk0Rows, RunnerPixelArt.boarWalk1Rows),
        ] {
            #expect(walk0.count == walk1.count && walk0[0].count == walk1[0].count, "\(name): 寸法が違う")
            let legs = max(Self.legHeight(of: walk0), Self.legHeight(of: walk1))
            let body0 = walk0.dropLast(legs + 1), body1 = walk1.dropLast(legs + 1)
            #expect(Array(body0) == Array(body1), "\(name): 脚より上の絵が違う")
            #expect(walk0.suffix(legs) != walk1.suffix(legs), "\(name): 脚が動いていない")
        }
    }

    /// イノシシは鼻先を当たり判定の左端に合わせる（`RunnerScene.addBoar`・#943 の約束）ので、
    /// 鼻先が格子の左端の列にあり、鼻先の色（`S`）がその列に接していること。犬は頭が左。
    @Test("イノシシの鼻先は格子の左端にあり、犬・イノシシとも頭は左（進行方向）")
    func animalsFaceLeft() {
        for frame in RunnerPixelArt.WalkFrame.allCases {
            let boar = RunnerPixelArt.boar(frame, colors: RunnerWorld.night.creatures).rows.map(Array.init)
            let snoutRows = boar.indices.filter { boar[$0][0] == "K" && boar[$0][1] == "S" }
            #expect(snoutRows.count >= 3, "イノシシ \(frame): 左端の列に鼻先が無い（\(snoutRows)）")
            let dog = RunnerPixelArt.dog(frame, colors: RunnerWorld.night.creatures).rows.map(Array.init)
            // 鼻（縁取り 2 ドット）が左端にあり、口元の薄い色 `W` がそのすぐ右に続く。
            let noseRows = dog.indices.filter { dog[$0][0] == "K" && dog[$0][1] == "K" && dog[$0][2] == "W" }
            #expect(!noseRows.isEmpty, "犬 \(frame): 左端にマズルが無い")
            // 巻き尾は右（後ろ）の上——右半分の上の行に不透明なドットがある。
            let tailTop = dog.prefix(4).contains { row in row.suffix(dog[0].count / 2).contains { $0 != "." } }
            #expect(tailTop, "犬 \(frame): 背中の上に尾が無い")
        }
    }

    /// 土煙（`RunnerScene.addBoar`）は `boarRearFootX` の列に立てる。2 コマとも底の行でその列の
    /// 両隣が脚（不透明）であること——絵の後ろ脚を動かしたら定数も動かす。
    @Test("イノシシの土煙の列は 2 コマとも後ろ脚の足元")
    func boarDustSitsUnderTheRearLegs() {
        let x = RunnerPixelArt.boarRearFootX
        for rows in [RunnerPixelArt.boarWalk0Rows, RunnerPixelArt.boarWalk1Rows] {
            let bottom = Array(rows[rows.count - 1])
            let left = Int(x.rounded(.down)), right = Int(x.rounded(.up))
            #expect(bottom[left] != "." && bottom[right] != ".", "底の行 \(String(bottom)) の列 \(x) が脚でない")
            #expect(x > Double(bottom.count) / 2, "後ろ脚（右半分）でない: \(x)")
        }
    }

    /// 歩きのコマは進んだ距離を 1 歩で刻んで交互（走者の `RunnerRider.pedalFrame` と同じ作法）。
    /// 現れる前（距離 0 以下）は `walk0`。
    @Test("歩きのコマは 1 歩ごとに交互で、進んでいなければ walk0")
    func walkFrameAlternatesByStride() {
        let stride = 2.0
        #expect(RunnerPixelArt.walkFrame(travel: -1, stride: stride) == .walk0)
        #expect(RunnerPixelArt.walkFrame(travel: 0, stride: stride) == .walk0)
        #expect(RunnerPixelArt.walkFrame(travel: 1.9, stride: stride) == .walk0)
        #expect(RunnerPixelArt.walkFrame(travel: 2.0, stride: stride) == .walk1)
        #expect(RunnerPixelArt.walkFrame(travel: 3.9, stride: stride) == .walk1)
        #expect(RunnerPixelArt.walkFrame(travel: 4.0, stride: stride) == .walk0)
        #expect(RunnerPixelArt.dogWalkStride > 0 && RunnerPixelArt.boarWalkStride > 0)
    }

    /// 世界ごとの色（#929）がそのまま絵に写る: 体の主色は `RunnerWorld.creatures` の値で、
    /// 縁取りは世界の `outline`。`WorldTests` が主色と背景の 3:1 を固定しているので、
    /// この写しが正しければ全世界での見え方も保証される。
    @Test("犬・イノシシの主色と縁取りは世界の Creatures をそのまま使う")
    func creaturePaletteMirrorsTheWorld() {
        for world in RunnerWorld.allCases {
            let c = world.creatures
            let p = RunnerPixelArt.creaturePalette(c)
            #expect(p["K"] == c.outline && p["O"] == c.dogBody && p["B"] == c.boarBody, "\(world)")
            #expect(p["W"] == c.dogBelly && p["o"] == c.dogDark && p["b"] == c.boarDark && p["S"] == c.boarSnout, "\(world)")
            // 主色が絵の中でいちばん多い色（遠目にはこの色で見分ける）。
            for (name, rows, key) in [("犬", RunnerPixelArt.dogWalk0Rows, "O"), ("イノシシ", RunnerPixelArt.boarWalk0Rows, "B")] {
                var counts: [Character: Int] = [:]
                for row in rows { for ch in row where ch != "." { counts[ch, default: 0] += 1 } }
                #expect(counts.max { $0.value < $1.value }?.key == Character(key), "\(name): 主色が \(key) でない \(counts)")
            }
        }
    }
}
