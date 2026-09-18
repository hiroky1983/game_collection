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
        [
            ("たこ焼き", RunnerPixelArt.takoyaki()),
            // 岩の枠の着せ替え（#1009）。色は世界によらない。
            ("切り株", RunnerPixelArt.stump()),
            ("ロープの束", RunnerPixelArt.ropeCoil()),
            ("ドラム缶", RunnerPixelArt.drum()),
            // 突き上げ（#1010）。色は世界によらず、着せ替え（竹の子・波しぶき）で絵ごと替わる。
            ("竹の子", RunnerPixelArt.shoot(world: .satoyama)),
            ("波しぶき", RunnerPixelArt.shoot(world: .harbor)),
            ("土の盛り上がり", RunnerPixelArt.shootCue(world: .satoyama)),
            ("泡", RunnerPixelArt.shootCue(world: .harbor)),
            // 高い塀（#1091）。こちらも色は世界によらず、着せ替え（石垣・コンテナ）で絵ごと替わる。
            ("石垣", RunnerPixelArt.wallArt(for: .stoneWall)),
            ("積まれたコンテナ", RunnerPixelArt.wallArt(for: .containerStack)),
        ] + RunnerWorld.allCases.flatMap { world in
            RunnerPixelArt.WalkFrame.allCases.flatMap { frame in
                [
                    ("犬 \(frame)（\(world)）", RunnerPixelArt.dog(frame, colors: world.creatures)),
                    ("イノシシ \(frame)（\(world)）", RunnerPixelArt.boar(frame, colors: world.creatures)),
                    // 世界の着せ替え（#1009）で実際に貼られる絵（港町は猫・フォークリフト）。
                    ("犬の枠 \(frame)（\(world)）", RunnerPixelArt.walker(frame, world: world)),
                    ("イノシシの枠 \(frame)（\(world)）", RunnerPixelArt.charger(frame, world: world)),
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
    @Test("犬・イノシシ（猫・フォークリフトの車輪も）の脚の高さは全体の 1/4 以下", arguments: [
        ("犬 walk0", RunnerPixelArt.dogWalk0Rows), ("犬 walk1", RunnerPixelArt.dogWalk1Rows),
        ("イノシシ walk0", RunnerPixelArt.boarWalk0Rows), ("イノシシ walk1", RunnerPixelArt.boarWalk1Rows),
        ("猫 walk0", RunnerPixelArt.catWalk0Rows), ("猫 walk1", RunnerPixelArt.catWalk1Rows),
        ("フォークリフト walk0", RunnerPixelArt.forkliftDrive0Rows), ("フォークリフト walk1", RunnerPixelArt.forkliftDrive1Rows),
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
            ("猫", RunnerPixelArt.catWalk0Rows, RunnerPixelArt.catWalk1Rows),
            ("フォークリフト", RunnerPixelArt.forkliftDrive0Rows, RunnerPixelArt.forkliftDrive1Rows),
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
            // 猫・フォークリフト（#1009）も同じ文字で世界の色を写す。
            let cat = RunnerPixelArt.catPalette(c), forklift = RunnerPixelArt.forkliftPalette(c)
            #expect(cat["K"] == c.outline && cat["O"] == c.dogBody && cat["o"] == c.dogDark && cat["W"] == c.dogBelly, "\(world)")
            #expect(forklift["K"] == c.outline && forklift["B"] == c.boarBody && forklift["b"] == c.boarDark && forklift["S"] == c.boarSnout, "\(world)")
            // 主色が絵の中でいちばん多い色（遠目にはこの色で見分ける）。
            for (name, rows, key) in [
                ("犬", RunnerPixelArt.dogWalk0Rows, "O"), ("イノシシ", RunnerPixelArt.boarWalk0Rows, "B"),
                ("猫", RunnerPixelArt.catWalk0Rows, "O"),
            ] {
                var counts: [Character: Int] = [:]
                for row in rows { for ch in row where ch != "." { counts[ch, default: 0] += 1 } }
                #expect(counts.max { $0.value < $1.value }?.key == Character(key), "\(name): 主色が \(key) でない \(counts)")
            }
        }
    }

    // MARK: 着せ替え（`RunnerWorld.Dressing`・#1009）

    /// 世界の着せ替えで貼られる絵: 港町の犬の枠は猫、イノシシの枠はフォークリフト。それ以外の
    /// 4 世界（里山の田舎の犬・イノシシを含む）は犬・イノシシの格子そのもの（色だけ世界の値）。
    @Test("犬の枠・イノシシの枠の絵は世界の着せ替えに従う")
    func dressedWalkersFollowTheWorld() {
        for frame in RunnerPixelArt.WalkFrame.allCases {
            for world in [RunnerWorld.morning, .evening, .night, .satoyama] {
                #expect(RunnerPixelArt.walker(frame, world: world) == RunnerPixelArt.dog(frame, colors: world.creatures), "\(world) \(frame)")
                #expect(RunnerPixelArt.charger(frame, world: world) == RunnerPixelArt.boar(frame, colors: world.creatures), "\(world) \(frame)")
                #expect(RunnerPixelArt.walkerRows(world: world) == RunnerPixelArt.dogWalk0Rows)
                #expect(RunnerPixelArt.chargerRows(world: world) == RunnerPixelArt.boarWalk0Rows)
                #expect(RunnerPixelArt.chargerRearFootX(world: world) == RunnerPixelArt.boarRearFootX)
            }
            #expect(RunnerPixelArt.walker(frame, world: .harbor) == RunnerPixelArt.cat(frame, colors: RunnerWorld.harbor.creatures))
            #expect(RunnerPixelArt.charger(frame, world: .harbor) == RunnerPixelArt.forklift(frame, colors: RunnerWorld.harbor.creatures))
        }
        #expect(RunnerPixelArt.walkerRows(world: .harbor) == RunnerPixelArt.catWalk0Rows)
        #expect(RunnerPixelArt.chargerRows(world: .harbor) == RunnerPixelArt.forkliftDrive0Rows)
        #expect(RunnerPixelArt.chargerRearFootX(world: .harbor) == RunnerPixelArt.forkliftRearWheelX)
        // 里山の田舎の犬は朝の柴と色で見分けが付く（絵は同じ）。
        #expect(RunnerWorld.satoyama.creatures.dogBody != RunnerWorld.morning.creatures.dogBody)
    }

    /// 猫は犬と同じ格子（`addDog` が同じ置き方で貼る）で、頭が左・耳が頭の上に 2 つ・尾が背中の上の
    /// 右端に立ち、首輪（`R`）が無い。犬から「猫らしさ」として外した要素（#975）がこちらにある。
    @Test("猫は犬と同じ 30×21 で頭は左、立ち耳 2 つ・立った尾・首輪なし")
    func catLooksLikeACat() throws {
        for frame in RunnerPixelArt.WalkFrame.allCases {
            let cat = RunnerPixelArt.cat(frame, colors: RunnerWorld.harbor.creatures)
            let dog = RunnerPixelArt.dog(frame, colors: RunnerWorld.harbor.creatures)
            #expect(cat.width == dog.width && cat.height == dog.height, "猫 \(frame): \(cat.width)×\(cat.height)")
            let b = try #require(cat.opaqueBounds)
            #expect(b.x == 0 && b.y == 0 && b.width == cat.width && b.height == cat.height, "余白: \(b)")
            let rows = cat.rows.map(Array.init)
            // 鼻（縁取り）が左端にあり、口元の薄い色 `W` がその右に続く。
            #expect(rows.contains { $0[0] == "K" && $0[1] == "W" }, "猫 \(frame): 左端にマズルが無い")
            // 耳: 上から 3 行目までに、左半分で不透明な範囲が 2 つに割れている行がある（三角の耳 2 つ）。
            let ears = rows.prefix(3).contains { row in
                var runs = 0, inRun = false
                for ch in row.prefix(cat.width / 2) {
                    if ch != "." { if !inRun { runs += 1; inRun = true } } else { inRun = false }
                }
                return runs == 2
            }
            #expect(ears, "猫 \(frame): 頭の上に耳が 2 つ無い")
            // 尾: 最上段の不透明なドットは右半分（背中の上に立つ）。
            #expect(rows[0].prefix(cat.width / 2).allSatisfy { $0 == "." } && rows[0].contains { $0 != "." }, "猫 \(frame): 尾が立っていない")
            #expect(!cat.rows.joined().contains("R"), "猫 \(frame): 首輪がある")
        }
    }

    /// フォークリフトはイノシシと同じ格子で、フォークの先が左端の列（鼻先と同じ約束）。
    /// 土煙（排気）の列 `forkliftRearWheelX` は 2 コマとも底の行で後輪の上にある。
    @Test("フォークリフトはイノシシと同じ 33×23 で、フォークが左端・排気の列は後輪の下")
    func forkliftForksAtTheLeftEdge() throws {
        let x = RunnerPixelArt.forkliftRearWheelX
        for frame in RunnerPixelArt.WalkFrame.allCases {
            let lift = RunnerPixelArt.forklift(frame, colors: RunnerWorld.harbor.creatures)
            let boar = RunnerPixelArt.boar(frame, colors: RunnerWorld.harbor.creatures)
            #expect(lift.width == boar.width && lift.height == boar.height, "フォークリフト \(frame): \(lift.width)×\(lift.height)")
            let b = try #require(lift.opaqueBounds)
            #expect(b.x == 0 && b.y == 0 && b.width == lift.width && b.height == lift.height, "余白: \(b)")
            let rows = lift.rows.map(Array.init)
            // フォーク: 下の 3 行に、左端が縁取りで鋼（`S`）が横に長く続く行がある。
            let fork = rows.suffix(3).contains { row in row[0] == "K" && row[1...8].allSatisfy { $0 == "S" } }
            #expect(fork, "フォークリフト \(frame): 左端にフォークが無い")
            let bottom = rows[lift.height - 1]
            let left = Int(x.rounded(.down)), right = Int(x.rounded(.up))
            #expect(bottom[left] != "." && bottom[right] != ".", "底の行の列 \(x) が車輪でない")
            #expect(x > Double(lift.width) / 2, "後輪（右半分）でない: \(x)")
        }
    }

    /// 岩の枠の置物は当たり判定の箱いっぱいに貼る（`RunnerScene.makeBlock`）ので、格子の縦横比が
    /// 箱と同じ（低い岩 4×5、高い岩 4×9）で余白が無いこと。伸びて貼られると 1 ドットが走者と違う大きさになる。
    @Test("切り株・ロープの束は 4:5、ドラム缶は 4:9 の格子で余白が無い")
    func blocksFitTheHitBoxes() throws {
        let low = RunnerHazardKind.lowBlock, tall = RunnerHazardKind.tallBlock
        for (name, sprite, kind) in [
            ("切り株", RunnerPixelArt.stump(), low), ("ロープの束", RunnerPixelArt.ropeCoil(), low),
            ("ドラム缶", RunnerPixelArt.drum(), tall),
        ] {
            let width = RunnerRules.tileWidth, height = kind.height
            #expect(Double(sprite.width) * height == Double(sprite.height) * width, "\(name): \(sprite.width)×\(sprite.height) は \(width)×\(height) の比でない")
            #expect(sprite.width >= 12, "\(name): 1 ドットが走者より大きい")
            let b = try #require(sprite.opaqueBounds)
            #expect(b.x == 0 && b.y == 0 && b.width == sprite.width && b.height == sprite.height, "\(name) の余白: \(b)")
        }
    }

    // MARK: 突き上げ（#1010）

    /// 突き上げ（竹の子・波しぶき）も**当たり判定の箱いっぱい**（4×9 = 高い岩と同じ）に貼るので、
    /// 格子の縦横比が箱と同じで余白が無いこと。予告（土の塚・泡）は 2 つの世界で**同じ格子**
    /// （動きと置き方を 1 つにしてあることの裏取り）。
    @Test("竹の子・波しぶきは 4:9 の格子で余白が無く、予告は 2 世界で同じ格子")
    func shootsFitTheTallHitBox() throws {
        let height = RunnerHazardKind.shoot.height
        for (name, sprite) in [
            ("竹の子", RunnerPixelArt.shoot(world: .satoyama)),
            ("波しぶき", RunnerPixelArt.shoot(world: .harbor)),
        ] {
            #expect(
                Double(sprite.width) * height == Double(sprite.height) * RunnerRules.tileWidth,
                "\(name): \(sprite.width)×\(sprite.height) は 4×\(height) の比でない"
            )
            #expect(sprite.width >= 12, "\(name): 1 ドットが走者より大きい")
            let b = try #require(sprite.opaqueBounds)
            #expect(b.x == 0 && b.y == 0 && b.width == sprite.width && b.height == sprite.height, "\(name) の余白: \(b)")
        }
        let body = RunnerPixelArt.shoot(world: .satoyama)
        let mound = RunnerPixelArt.shootCue(world: .satoyama)
        let foam = RunnerPixelArt.shootCue(world: .harbor)
        #expect(mound.width == foam.width && mound.height == foam.height, "予告の格子が世界で違う")
        // 予告は当たり判定の `shootCueVisualScale` 倍の幅で貼る（`RunnerScene.addShoot`）。
        // 格子の幅がその倍率どおりなら、1 ドットの大きさが本体と揃う（引き伸ばされない）。
        #expect(
            Double(mound.width) / Double(body.width) == RunnerPixelArt.shootCueVisualScale,
            "予告の格子 \(mound.width) が倍率 \(RunnerPixelArt.shootCueVisualScale) と合わない（本体 \(body.width)）"
        )
        // 予告は地面に置く低い塚（本体の 1/3 以下の高さ）。
        #expect(mound.height * 3 <= body.height, "予告が高すぎる: \(mound.height)")
    }

    /// **里山と港町で絵が別物**であること（#1010「里山版と港町版の 2 種類の見た目を持つ」）。
    ///
    /// `RunnerPixelArt.shoot(world:)` が両方とも竹の子を返しても、着せ替えの列挙
    /// （`RunnerWorld.Dressing.Shoot`）だけを見ていると気付けない（2026-09-18 の敵対的検証で
    /// 368 件緑だったのを実測）。**絵そのものの色で別物だと言い切る**。
    @Test("里山は竹の子（緑の穂先）・港町は波しぶき（水色と青の陰）で、色が混ざらない")
    func shootArtDiffersBetweenWorlds() {
        // **着せ替え → 絵の対応**（`RunnerScene.shootTexture` が通る唯一の経路）を直接固定する。
        #expect(RunnerPixelArt.shootArt(for: .bambooShoot).rows == RunnerPixelArt.bambooShootRows)
        #expect(RunnerPixelArt.shootArt(for: .seaSpray).rows == RunnerPixelArt.seaSprayRows)
        #expect(RunnerPixelArt.shootCueArt(for: .bambooShoot).rows == RunnerPixelArt.soilMoundRows)
        #expect(RunnerPixelArt.shootCueArt(for: .seaSpray).rows == RunnerPixelArt.foamRows)
        // 世界から引く版は着せ替え経由で同じものになる。
        #expect(RunnerPixelArt.shoot(world: .satoyama).rows == RunnerPixelArt.bambooShootRows)
        #expect(RunnerPixelArt.shoot(world: .harbor).rows == RunnerPixelArt.seaSprayRows)

        let bamboo = RunnerPixelArt.shoot(world: .satoyama).rows.joined()
        let spray = RunnerPixelArt.shoot(world: .harbor).rows.joined()
        #expect(bamboo != spray, "里山と港町の絵が同じ")
        // 竹の子: 緑（`a`/`A`）があり、水の色（`C`/`L`/`N`）は無い。
        #expect(bamboo.contains("a") && bamboo.contains("A"), "竹の子に緑が無い")
        for water in ["C", "L", "N"] {
            #expect(!bamboo.contains(water), "竹の子に水の色 \(water) が混ざっている")
        }
        // 波しぶき: 水色（`C`）と**陰の 2 階調**（`L`/`N`）があり、緑は無い。
        #expect(spray.contains("C") && spray.contains("L") && spray.contains("N"), "波しぶきに水の濃淡が無い")
        #expect(!spray.contains("a") && !spray.contains("A"), "波しぶきに緑が混ざっている")
        // 濃淡は「淡い青の背景で形が立つ」ための要（36df5c6）。**柱が全幅になる行では、
        // 右端（縁取りの 1 つ内側）が必ず陰**であること——ここを潰すと平たい三角に戻る。
        // 面の中の明暗（白い泡 `M` と陰 `N`）も 3:1 以上離しておく（背景に依らず形が読める）。
        let sprayRows = RunnerPixelArt.shoot(world: .harbor).rows
        var shadedEdges = 0
        for row in sprayRows.dropLast() where !row.contains(".") {
            let chars = Array(row)
            let rightInner = chars[chars.count - 2]
            #expect("LN".contains(rightInner), "波しぶきの右端が陰でない: \(row)")
            shadedEdges += 1
        }
        #expect(shadedEdges >= 10, "全幅の行が \(shadedEdges) しか無い（空振り防止）")
        let art = RunnerPixelArt.palette
        #expect(WCAG.contrast(art["M"]!, art["N"]!) >= 3.0, "波しぶきの面の中の明暗が足りない")
        // 予告も同じ（土の塚は茶・泡は水色）。
        let mound = RunnerPixelArt.shootCue(world: .satoyama).rows.joined()
        let foam = RunnerPixelArt.shootCue(world: .harbor).rows.joined()
        #expect(mound != foam, "土の塚と泡の絵が同じ")
        #expect(mound.contains("S") && !mound.contains("C"), "土の塚が土の色でない")
        #expect(foam.contains("C") && !foam.contains("S"), "泡が水の色でない")
    }

    /// 突き上げは**切り株（低い岩）と明確に見分けられる**こと（#1010 の受け入れ条件）:
    /// 竹の子は切り株の 1.5 倍以上の高さ（箱が 4×9 対 4×5）で、主色が切り株の樹皮と 2:1 以上離れ、
    /// **穂先に切り株には無い緑がある**。港町側は波しぶき（水）とロープの束（麻）で、
    /// 上の `shootArtDiffersBetweenWorlds` が色の系統の違いを固定する。
    @Test("竹の子は切り株より高く、主色が離れていて、穂先が緑")
    func bambooShootLooksNothingLikeAStump() {
        let art = RunnerPixelArt.palette
        let shoot = RunnerPixelArt.shoot(world: .satoyama)
        let stump = RunnerPixelArt.stump()
        #expect(
            Double(RunnerHazardKind.shoot.height) >= Double(RunnerHazardKind.lowBlock.height) * 1.5,
            "竹の子の箱が切り株の 1.5 倍に届かない"
        )
        #expect(WCAG.contrast(art["T"]!, art["S"]!) >= 2.0, "竹の子の皮と切り株の樹皮が同じ明るさ")
        // 穂先（上から 1/3）に緑のドットがあり、切り株の同じ帯には無い。
        let tipRows = shoot.rows.prefix(shoot.height / 3).joined()
        #expect(tipRows.contains("a") || tipRows.contains("A"), "穂先に緑が無い")
        let stumpTop = stump.rows.prefix(stump.height / 3).joined()
        #expect(!stumpTop.contains("a"), "切り株の上に濃い緑がある（見分けが付かない）")
    }

    // MARK: 高い塀（#1091）

    /// 高い塀（石垣・積まれたコンテナ）も**当たり判定の箱いっぱい**（4×20）に貼るので、
    /// 格子の縦横比が箱と同じで余白が無いこと。
    @Test("石垣・コンテナは 4:20 の格子で余白が無い")
    func wallsFitTheWallHitBox() throws {
        let height = RunnerHazardKind.wall.height
        for (name, sprite) in [
            ("石垣", RunnerPixelArt.wallArt(for: .stoneWall)),
            ("積まれたコンテナ", RunnerPixelArt.wallArt(for: .containerStack)),
        ] {
            #expect(
                Double(sprite.width) * height == Double(sprite.height) * RunnerRules.tileWidth,
                "\(name): \(sprite.width)×\(sprite.height) は 4×\(height) の比でない"
            )
            #expect(sprite.width >= 12, "\(name): 1 ドットが走者より大きい")
            let b = try #require(sprite.opaqueBounds)
            #expect(
                b.x == 0 && b.y == 0 && b.width == sprite.width && b.height == sprite.height,
                "\(name) の余白: \(b)"
            )
        }
    }

    /// **里山と港町で絵が別物**であること（#1091「里山版と港町版の 2 種類の見た目を持つ」）。
    /// 突き上げと同じく、着せ替えの列挙だけを見ると「両方とも石垣を返す」実装でも緑になる。
    @Test("里山は石垣（灰の石と目地）・港町はコンテナ（赤い箱と桁）で、色が混ざらない")
    func wallArtDiffersBetweenWorlds() {
        #expect(RunnerPixelArt.wallArt(for: .stoneWall).rows == RunnerPixelArt.stoneWallRows)
        #expect(RunnerPixelArt.wallArt(for: .containerStack).rows == RunnerPixelArt.containerStackRows)
        let stone = RunnerPixelArt.stoneWallRows.joined()
        let container = RunnerPixelArt.containerStackRows.joined()
        #expect(stone != container, "石垣とコンテナの絵が同じ")
        // 石垣: 石（`G`）・目地（`g`）・笠石（`W`）があり、コンテナの赤（`R`/`r`/`O`）は無い。
        #expect(stone.contains("G") && stone.contains("g") && stone.contains("W"), "石垣に石の階調が無い")
        for red in ["R", "r", "O"] {
            #expect(!stone.contains(red), "石垣にコンテナの色 \(red) が混ざっている")
        }
        // コンテナ: 赤の 3 階調があり、石の色は無い。
        #expect(container.contains("R") && container.contains("r") && container.contains("O"), "コンテナに赤の階調が無い")
        for grey in ["G", "g", "W"] {
            #expect(!container.contains(grey), "コンテナに石垣の色 \(grey) が混ざっている")
        }
    }

    /// 高い塀は**高い岩（大きな石・ドラム缶）と一目で区別できる**こと（#1091 の受け入れ条件
    /// 「高さが倍以上に見える・形が違う」）。
    @Test("塀は高い岩の 2 倍以上の高さで、主色も岩と離れている")
    func wallsLookNothingLikeATallBlock() {
        let art = RunnerPixelArt.palette
        #expect(
            RunnerHazardKind.wall.height >= RunnerHazardKind.tallBlock.height * 2,
            "塀の箱が高い岩の 2 倍に届かない"
        )
        // 形: 石垣は横一直線の目地が何段も入る（丸い岩塊・円筒のドラム缶には無い）。
        let seams = RunnerPixelArt.stoneWallRows.filter { row in
            row.dropFirst().dropLast().allSatisfy { dot in dot == "g" }
        }
        #expect(seams.count >= 6, "石垣の目地が \(seams.count) 段しかない（積んで見えない）")
        // コンテナは桁（`r` で埋まる行）が段ごとに 2 本ずつ入るので、2 段積みなら 4 行以上。
        let rails = RunnerPixelArt.containerStackRows.filter { row in
            row.dropFirst().dropLast().allSatisfy { dot in dot == "r" }
        }
        #expect(rails.count >= 4, "コンテナの桁が \(rails.count) 行しかない（2 段に見えない）")
        // 色: コンテナの赤はドラム缶の青と 1.5:1 以上離す（港町で隣り合っても別物に見える）。
        #expect(WCAG.contrast(art["R"]!, art["N"]!) >= 1.5, "コンテナの赤とドラム缶の青が同じ明るさ")
    }
}
