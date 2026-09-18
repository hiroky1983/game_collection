
/// 撮影・QA 用の起動引数（`-simulateRunner`）で狙った画面を作る部分（#1106 で `RunnerModel.swift` から分けた）。
///
/// まるごと `#if DEBUG` なので製品には入らない。止めた画を撮るための格納プロパティ
/// （`isFrozenForCapture` / `isAutoPilotForDebug`）だけは extension に置けないので本体に残してある。
#if DEBUG
extension RunnerModel {
    /// 撮影用のエンドレスの種（#675）。毎回同じコースを撮るための固定値で、意味は無い。
    private static let captureSeed: UInt64 = 675
    /// 7 桁の走行距離を撮るときの地点（#1086）。10,000,000 単位 ＝ 2,500,000 m。区画の左端
    /// （64 の倍数）なので、置いた瞬間に障害の上にはいない。
    static let farCaptureDistance: Double = 10_000_000

    /// 撮影・動作確認用に狙った画面まで進める（起動引数 `-simulateRunner <名前>`）。
    ///
    /// 走行中・一時停止・ミス・クリアの画は、実機では**指で遊ばないと**出せない。
    /// シミュレータには自動タップの手段が無いため、`-simulateBlocks`（#463）と同じ形で
    /// 起動引数から状態を作る。
    public func applyDebugScenario(_ name: String) {
        switch name {
        case "running":
            press(); release()
            // 最初の障害を跳び越している最中で止める（走っていることが 1 枚で分かる画）。
            autoPlayForDebug(until: { $0.field.altitude > RunnerRules.jumpApex * 0.6 })
            isFrozenForCapture = true
        case "pedaling":
            press(); release()
            // 漕いでいる画を撮る。`running` は空中で止めるので、そちらは `jump` のコマになる（#569）。
            // 漕ぐコマは 2 枚（#701）で、`ride0` は走り出す前と同じ絵なので、**左ペダルが前の
            // `ride1` が出る瞬間**で止める。シーンは最初の反映で「それまでに進んだ距離」を
            // まとめて位相に足すので、凍らせた画のコマは接地距離だけで決まる。
            autoPlayForDebug(until: {
                $0.field.isGrounded && $0.field.distance > 34
                    && RunnerRider.pedalFrame(
                        phase: RunnerRider.phase(forGroundedDistance: $0.field.distance)
                    ) == .ride1
            })
            isFrozenForCapture = true
        case "paused":
            press(); release()
            autoPlayForDebug(until: { $0.field.distance > 80 })
            pause()
        case "failed":
            press(); release()
            // 跳ばずに走り続ければ、最初の障害で必ずミスになる。
            advanceFramesForDebug(seconds: 30)
        case "cleared":
            press(); release()
            autoPlayForDebug(until: { _ in false })
            // ゴールの演出（#1092）は飛ばして、**リザルトの画**で止める。ASO 撮影の絵を変えない。
            skipGoalChase()
        case "chasing":
            // ゴールの演出のさなか（#1092）。宝くじが飛び、おじさんがまだ画面の中にいる
            // ところを撮りたいので、進みが 4 割ほどのところで時間ごと止める。
            press(); release()
            autoPlayForDebug(until: { _ in false })
            advanceFramesForDebug(seconds: RunnerRules.goalChaseDuration * 0.4)
            isFrozenForCapture = true
        case let value where RunnerStory.debugScene(for: value)?.triggerStage != nil:
            // 世界の締め（`story-world1`〜`story-world5`・#1092）。締めは**リザルトの手前**に
            // 出るものなので、まず普通にゴールさせて `.cleared` を作り、その上に被せる。
            // 面はどこでもよい（締めの絵は `RunnerStoryArt` が自前の背景で描く）。
            press(); release()
            autoPlayForDebug(until: { _ in false })
            skipGoalChase()
            if let scene = RunnerStory.debugScene(for: value) { beginStory(scene) }
        case "showcase":
            // QA用: 低い障害物・高い障害物・鳥・穴3サイズを1本で見比べる（`RunnerStage.debugShowcase`）。
            // `.ready` のまま渡すので、実機・シミュレータで普通にタップして遊べる。
            applyDebugStage(.debugShowcase)
        case "bird":
            // 飛び立つ前（羽ばたきの予備動作中）で止める（#796 の受け入れ条件の画 1/3）。
            // ショーケース（`RunnerStage.debugShowcase`）の鳥を使う。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                guard let bird = model.field.stage.hazards.first(where: { $0.kind == .bird }) else { return true }
                return model.field.distance >= bird.birdTakeoffDistance - RunnerRules.birdFlutterDistance / 2
            })
            isFrozenForCapture = true
        case "bird-low":
            // 飛び立った直後、まだ頭より低いところを上がっている途中（画 2/3・#945）。
            // 帯の下端が止まっていた上端（5）を越え、頭（11）にはまだ届いていないところで止める
            // ——おじさんはまだ手前を走っている。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                let field = model.field
                guard let bird = field.stage.hazards.first(where: { $0.kind == .bird }),
                      let frame = bird.frame(atRunnerDistance: field.distance) else { return true }
                return frame.bottom >= RunnerHazardKind.birdLowTop
                    && frame.bottom < RunnerField.Metrics.playerHeight
            })
            isFrozenForCapture = true
        case "bird-up":
            // 上がりきった鳥の真下を走ったまま抜けている瞬間（画 3/3・#945 の受け入れ条件そのもの）。
            // 接地したまま帯と横に重なったところで止める——帯の下端は頭の 3 上（`birdMeetBottom`）。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                let field = model.field
                guard let bird = field.stage.hazards.first(where: { $0.kind == .bird }),
                      let frame = bird.frame(atRunnerDistance: field.distance) else { return true }
                return field.isGrounded && frame.bottom >= RunnerHazardKind.birdMeetBottom
                    && field.playerMaxX > frame.start && field.playerMinX < frame.end
            })
            isFrozenForCapture = true
        case "dog":
            // 犬が走者の少し前（画面の中央）で向かい合っている瞬間（#955）。左向きに歩いて来る
            // 犬の鼻先が画面の中央（走者の中心の `width / 2 − playerX` = 24 先）に入った最初の
            // フレームで止める——自動操縦の踏み切り（間合い 10 前後）より手前なので、走者は
            // まだ接地して向かい合っている。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                let field = model.field
                guard let dog = field.stage.hazards.first(where: { $0.kind == .dog }),
                      let frame = dog.frame(atRunnerDistance: field.distance) else { return false }
                let center = RunnerField.Metrics.width / 2 - RunnerField.Metrics.playerX
                return field.isGrounded && frame.start - field.distance <= center
            })
            isFrozenForCapture = true
        case "boar":
            // イノシシが画面に入って突進している瞬間（#801）。出会う手前で止める。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                let field = model.field
                guard let boar = field.stage.hazards.first(where: { $0.kind == .boar }),
                      let frame = boar.frame(atRunnerDistance: field.distance) else { return false }
                return field.isGrounded && frame.start - field.distance < 40
            })
            isFrozenForCapture = true
        case "shoot":
            // 突き上げ（#1010）が伸びかけている瞬間（予告の塚から穂先が出たところ）。
            // ショーケースの `^` を使い、伸びた高さが箱の 3〜7 割のあいだで止める。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                let field = model.field
                guard let shoot = field.stage.hazards.first(where: { $0.kind == .shoot }) else { return true }
                let rise = shoot.shootRise(atRunnerDistance: field.distance)
                return rise >= RunnerHazardKind.shootTop * 0.3 && rise <= RunnerHazardKind.shootTop * 0.7
            })
            isFrozenForCapture = true
        case "shoot-up":
            // 伸び切った突き上げに走者が近づいている瞬間（#1010 の受け入れ条件「伸び切った高さは
            // 高い岩と同じ」の画）。踏み切る前——接地したまま、間合いが 20 を切ったところで止める。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                let field = model.field
                guard let shoot = field.stage.hazards.first(where: { $0.kind == .shoot }),
                      let frame = shoot.frame(atRunnerDistance: field.distance) else { return false }
                return field.isGrounded && frame.top >= RunnerHazardKind.shootTop
                    && frame.start - field.distance < 20
            })
            isFrozenForCapture = true
        case "wall":
            // 高い塀（#1091）の**手前**で止める（受け入れ条件の撮影シナリオ `wall`）。
            // ショーケースの `w` まで自動操縦で行き、接地したまま間合いが 24 を切ったところで止める
            // ——塀の全高（18）と走者が 1 画面に収まり、「一段では届かない」高さが読める画になる。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                let field = model.field
                guard let wall = field.stage.hazards.first(where: { $0.kind == .wall }) else { return true }
                return field.isGrounded && wall.start - field.distance < 24
            })
            isFrozenForCapture = true
        case "wall-double":
            // **二段目の頂点**で止める（撮影シナリオ `wall-double`）。自動操縦が一段目の頂点で
            // 二段目を踏む（`RunnerAutoPilot.shouldTakeSecondJump`）ので、そのあと上昇が終わった
            // 瞬間 = 二段ジャンプのいちばん高いところを撮る。塀の上端より足が上にある画になる。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                let field = model.field
                guard field.stage.hazards.contains(where: { $0.kind == .wall }) else { return true }
                return field.jumpCount == 2 && field.vy <= 0
            })
            isFrozenForCapture = true
        case "platform":
            // 台座の上を走っている瞬間で止める（#674 の受け入れ条件「台座の上を走っている瞬間」の画）。
            // 本番では台座は 16 面以降にしか出ないので、ショーケースの台座を使う。端から 8 単位
            // 内側に入ってから止め、乗った直後・降りる直前の画にならないようにする。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                let field = model.field
                return field.isGrounded
                    && field.stage.platforms.contains { $0.start + 8 <= field.distance && field.distance < $0.end - 8 }
            })
            isFrozenForCapture = true
        case "floor":
            // スピードアップ床の上を走っている瞬間で止める（#672 の受け入れ条件の画）。
            // 区間に入って 20 単位進んだところで止め、矢印模様が走者の足元に見えるようにする。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                let field = model.field
                return field.isOnBoostFloor
                    && field.stage.boostFloors.contains { $0.start + 20 <= field.distance }
            })
            isFrozenForCapture = true
        case "sink":
            // 沈む床（#1089）の上で沈みかけている瞬間で止める（受け入れ条件「沈みの見た目」の画）。
            // ショーケースの `~~`（2 区画ぶん = 長い床）まで自動操縦で行き、**そこから跳ぶのをやめて**
            // 沈みが 5〜8 割まで溜まったところで止める（自動操縦は床の上で必ず跳ぶので、
            // 最後まで任せると沈みかけの画が撮れない）。
            applyDebugStage(.debugShowcase)
            press(); release()
            runUpToSinkFloorForDebug()
            advanceUntilForDebug { (0.5...0.8).contains($0.field.sinkProgress) }
            isFrozenForCapture = true
        case "sink-failed":
            // 沈み切って溺れた直後のリザルト（#1089）。同じく床の手前まで自動操縦で行き、
            // 跳ぶのをやめて溺れさせ、ミスの演出（`fallDuration`）が明けるまで進める。
            applyDebugStage(.debugShowcase)
            press(); release()
            runUpToSinkFloorForDebug()
            advanceFramesForDebug(seconds: 10)
        case "crumble":
            // 崩れる足場（#1090）に乗って**ぎしぎし揺れている**瞬間で止める
            // （受け入れ条件「乗って揺れている」の画）。ショーケースの `C` まで自動操縦で行き、
            // 板の上で揺れの段（`RunnerRules.crumbleWarnDuration` 以内）に居るあいだに止める。
            applyDebugStage(.debugShowcase)
            press(); release()
            runOntoCrumblingPlatformForDebug()
            advanceUntilForDebug { model in
                guard let progress = model.crumbleProgressForDebug else { return false }
                return progress * RunnerRules.crumbleDuration >= RunnerRules.crumbleWarnDuration * 0.5
            }
            isFrozenForCapture = true
        case "crumble-fallen":
            // 板が全部抜け落ちて**谷だけが残った**瞬間で止める（受け入れ条件「崩れた後」の画）。
            //
            // 公平さの保証（`RunnerRules.crumbleMaxLength(at:)`）により、**走者が板の上に居る
            // まま崩れ切ることはできない**——どんな跳び方をしても横の進みは基準速を下回らず、
            // 板張りは必ずその速さで渡り切れる長さだから。そこで「渡り切った直後の走者の
            // 後ろで崩れ切る」ところを撮る。跳び続けると横の進みが基準速に落ちる
            // （空中は乗りが効かない）ので、崩れ切った跡が画面に残る。
            applyDebugStage(.debugShowcase)
            press(); release()
            runOntoCrumblingPlatformForDebug()
            advanceUntilForDebug(jumping: true) { model in
                model.crumbleProgressForDebug.map { $0 >= 1 } ?? false
            }
            isFrozenForCapture = true
        case "invincible":
            // たこ焼き（#797）を取って無敵のまま最初の岩に重なっている瞬間で止める
            // （受け入れ条件「無敵中に岩へ当たっても crashed が出ない」「残り時間が画面で分かる」の画）。
            // 本番では 4 面以降にしか出ないので、ショーケースの `k`（最初の岩の直前）を使う。
            // 自動操縦は無敵でも岩の手前で跳んでしまうので、**跳ばずに**走らせて岩の中に
            // 居る瞬間（接地したまま岩と重なっている＝無敵でなければミスの位置）で止める。
            applyDebugStage(.debugShowcase)
            press(); release()
            var frames = 0
            while phase.isRunning, frames < 60 * 30 {
                let field = self.field
                guard let rock = field.stage.hazards.first(where: { $0.kind != .pit }) else { break }
                if field.isInvincible, field.playerMaxX > rock.start, field.playerMinX < rock.end { break }
                frames += 1
                tick(dt: 1.0 / 60)
            }
            isFrozenForCapture = true
        case "endless":
            // エンドレス（#675）の走り出す前の画。上部セクションが「走行距離」表示に変わる。
            // 種を固定して毎回同じコースを撮る。
            newEndlessGame(seed: Self.captureSeed)
        case "endless-running":
            // エンドレスの走行中（距離が伸びている画）。冒頭の固定区画（#930 で 4 区画に短縮）を
            // 抜けたランダム区画で、跳んでいる最中の瞬間で止める（距離 600 超・跳躍の 6 割以上）。
            newEndlessGame(seed: Self.captureSeed)
            press(); release()
            autoPlayForDebug(until: { $0.field.distance > 600 && $0.field.altitude > RunnerRules.jumpApex * 0.6 })
            isFrozenForCapture = true
        case "endless-far":
            // 7 桁の走行距離で走っている画（#1086。距離表示が崩れないか・遠くでも絵がガタつかないか）。
            // 遠くまで一気に進めてから自動操縦で少し走り、跳んでいる最中で止める。
            newEndlessGame(seed: Self.captureSeed)
            press(); release()
            fastForwardEndlessForDebug(to: Self.farCaptureDistance)
            autoPlayForDebug(until: {
                $0.field.distance > Self.farCaptureDistance + 400 && $0.field.altitude > RunnerRules.jumpApex * 0.6
            })
            isFrozenForCapture = true
        case "endless-far-failed":
            // 7 桁の走行距離でミスしたリザルト（#1086。自己ベストも 7 桁になるので、続けて `endless-far` を
            // 撮るとヘッダーの走行距離と自己ベストが両方 7 桁の画になる）。
            newEndlessGame(seed: Self.captureSeed)
            press(); release()
            fastForwardEndlessForDebug(to: Self.farCaptureDistance)
            advanceFramesForDebug(seconds: 60)
        case "endless-autopilot":
            // 自動操縦で走り続ける（#1086。メモリが横ばいかの長時間の実測・録画用）。止めない。
            newEndlessGame(seed: Self.captureSeed)
            isAutoPilotForDebug = true
            press(); release()
        case "endless-failed":
            // エンドレスのリザルト（走行距離・自己ベスト）。冒頭を自動操縦で抜けてから
            // 跳ぶのをやめ、ランダム区画の最初の障害でミスさせる。
            newEndlessGame(seed: Self.captureSeed)
            press(); release()
            autoPlayForDebug(until: { $0.field.distance > 700 })
            advanceFramesForDebug(seconds: 60)
        case let name where name.hasPrefix("bird:"):
            // 本番ステージの鳥を、その面の世界の背景の上で撮る（例 `-simulateRunner bird:5`）。
            // `bird` はショーケースで走るので、面ごとの世界の配色で鳥が見分けられるか（#818）は
            // こちらで確かめる。最初の鳥が走者の少し前方（画面の中央付近）に来た接地中の瞬間で止める。
            if let number = Int(name.dropFirst("bird:".count)),
               RunnerStage.stage(number: number)?.hazards.contains(where: { $0.kind == .bird }) == true {
                stageNumber = number
                startStage(from: 0, passedCheckpoint: false)
                press(); release()
                autoPlayForDebug(until: { model in
                    let field = model.field
                    guard let bird = field.stage.hazards.first(where: { $0.kind == .bird }) else { return true }
                    return field.isGrounded && (8...45).contains(bird.start - field.distance)
                })
                isFrozenForCapture = true
            }
        case let name where name.hasPrefix("map:"):
            // 撮影用: ワールドマップ（#798）の到達面を作る（例 `-simulateRunner map:8` で 8 面まで到達済み）。
            // 開始シートは `RunnerView` が `-showRunnerStartSheet` で開く。
            if let number = Int(name.dropFirst("map:".count)) {
                reachedStage = min(max(number, 1), RunnerRules.stageCount)
            }
        case let name where name.hasPrefix("sink:"):
            // 本番ステージの沈む床を、その面の世界の背景の上で撮る（例 `-simulateRunner sink:21`）。
            // `sink` はショーケース（朝の下町）で走るので、里山の田んぼ・港町の干潟の見え方は
            // こちらで確かめる（`bird:` と同じ理由）。床の手前まで自動操縦で行き、そこから跳ぶのを
            // やめて沈みが 5〜8 割のところで止める。
            if let number = Int(name.dropFirst("sink:".count)),
               RunnerStage.stage(number: number)?.sinkFloors.isEmpty == false {
                stageNumber = number
                startStage(from: 0, passedCheckpoint: false)
                press(); release()
                runUpToSinkFloorForDebug()
                advanceUntilForDebug { (0.5...0.8).contains($0.field.sinkProgress) }
                isFrozenForCapture = true
            }
        case let name where name.hasPrefix("crumble-fallen:"):
            // 本番ステージの足場が**抜け落ちている最中**（里山＝川・港町＝海が板の下に見える）を撮る
            // （例 `-simulateRunner crumble-fallen:24`）。ショーケースは朝の下町で谷が黒い空隙
            // なので、「崩れた後に下の景色が見える」はこちらで確かめる。
            //
            // **崩れ切るまで待てない**のがこの面の事情。走者は板を渡り切ってからも基準速で進むので、
            // 崩れ切る頃（乗ってから 1.6 秒）には足場の右端が 50 以上後ろ——画面に映る後方は
            // `Metrics.playerX`（26）ぶんしかないので、足場ごと画面の外へ出る。板が画面に残る
            // いちばん遅い瞬間（右端から 20 まで離れたところ）で止める。
            if let number = Int(name.dropFirst("crumble-fallen:".count)),
               let platform = RunnerStage.stage(number: number)?.crumblingPlatforms.first {
                stageNumber = number
                startStage(from: 0, passedCheckpoint: false)
                press(); release()
                runOntoCrumblingPlatformForDebug()
                advanceUntilForDebug(jumping: true) { model in
                    if model.crumbleProgressForDebug.map({ $0 >= 1 }) == true { return true }
                    return model.field.distance > platform.end + 20
                }
                isFrozenForCapture = true
            }
        case let name where name.hasPrefix("crumble:"):
            // 本番ステージの崩れる足場を、その面の世界の背景の上で撮る（例 `-simulateRunner crumble:24`）。
            // `crumble` はショーケース（朝の下町）で走るので、里山の古い吊り橋・港町の古い木の桟橋は
            // こちらで確かめる（`sink:` と同じ理由）。板に乗って揺れているところで止める。
            if let number = Int(name.dropFirst("crumble:".count)),
               RunnerStage.stage(number: number)?.crumblingPlatforms.isEmpty == false {
                stageNumber = number
                startStage(from: 0, passedCheckpoint: false)
                press(); release()
                runOntoCrumblingPlatformForDebug()
                advanceUntilForDebug { model in
                    guard let progress = model.crumbleProgressForDebug else { return false }
                    return progress * RunnerRules.crumbleDuration >= RunnerRules.crumbleWarnDuration * 0.5
                }
                isFrozenForCapture = true
            }
        case let name where name.hasPrefix("wall:"):
            // 本番ステージの高い塀を、その面の世界の背景の上で撮る（例 `-simulateRunner wall:24`）。
            // `wall` はショーケース（朝の下町）で走るので、里山の石垣・港町のコンテナは
            // こちらで確かめる（`sink:` / `crumble:` と同じ理由）。塀の手前で止める。
            if let number = Int(name.dropFirst("wall:".count)),
               let stage = RunnerStage.stage(number: number),
               stage.hazards.contains(where: { $0.kind == .wall }) {
                stageNumber = number
                startStage(from: 0, passedCheckpoint: false)
                press(); release()
                autoPlayForDebug(until: { model in
                    let field = model.field
                    guard let wall = field.stage.hazards.first(where: { $0.kind == .wall }) else { return true }
                    // **踏み切りの余裕より手前で止める。** 本編の面は速さのぶん踏み切りが早く
                    // （19〜30 面で 30 前後）、塀のすぐ手前を狙うと条件が成立するのは空中——
                    // 接地するのは塀を越えたあとで、撮れるのは「通り過ぎた画」になる。
                    let lead = RunnerAutoPilot.lead(for: wall, speed: field.stage.speed)
                    return field.isGrounded && wall.start - field.distance <= lead + 16
                })
                isFrozenForCapture = true
            }
        case let name where name.hasPrefix("stage:"):
            // QA用: 本番ステージを番号で指定して最初から遊ぶ（例 `-simulateRunner stage:16`）。
            // 後半の面を確かめるのに 1 面目から遊び直す手間を省く（会長QA 2026-09-12）。
            // `applyDebugStage` ではなく `stageNumber` ごと差し替える——番号を動かさないと、
            // ミスして「もう一度」を押した瞬間に `startStage` が 1 面目を読み直す
            // （会長QA「ミスると元のステージに戻る」）。ヘッダーの番号も記録先もその面になる。
            // `stage:19@640` のように `@距離` を添えると、その面を自動操縦でその距離まで走らせて
            // 接地した瞬間で止める（#1009: 里山・港町の着せ替えを、本番の面の狙った区画で撮る用）。
            let spec = name.dropFirst("stage:".count).split(separator: "@", maxSplits: 1)
            if let first = spec.first, let number = Int(first),
               RunnerStage.stage(number: number) != nil {
                stageNumber = number
                startStage(from: 0, passedCheckpoint: false)
                if spec.count == 2, let target = Double(spec[1]) {
                    press(); release()
                    autoPlayForDebug(until: { $0.field.isGrounded && $0.field.distance >= target })
                    isFrozenForCapture = true
                }
            }
        default:
            break
        }
    }

    /// 自動操縦で `step` 秒ぶん進める（`-simulateRunner endless-autopilot`・#1086）。
    ///
    /// 自動操縦の判断は**1/60 秒以下の刻みごと**にする。実機のフレームは描画の重さ（計測中の Instruments など）で
    /// 伸び、1 フレームに 1 回の判断だと踏み切りが最大 1/20 秒遅れて、テスト（1/60 秒刻み）では越えられる
    /// 障害に当たる。刻みを揃えて、長時間の実測をテストと同じ走り方にする。
    func advanceWithAutoPilotForDebug(by step: Double) {
        var remaining = step
        while remaining > 0, phase.isRunning {
            let chunk = min(remaining, 1.0 / 60)
            remaining -= chunk
            if RunnerAutoPilot.shouldJump(field: field) { press() }
            if RunnerAutoPilot.shouldRelease(field: field) { release() }
            for event in field.step(dt: chunk) {
                guard phase.isRunning else { break }
                handle(event)
            }
        }
    }

    /// エンドレスの走者を `distance` まで一気に進める（撮影・テスト用・#1086）。ステージ制では何もしない。
    ///
    /// コースは生成器が頭から順に作る（区画の中身は種と通し番号だけで決まる）ので、遠いほど時間が掛かる。
    func fastForwardEndlessForDebug(to distance: Double) {
        guard mode == .endless else { return }
        field.placeForTesting(distance: distance, altitude: 0, vy: 0)
    }

    /// `RunnerStage.all` を経由せず、任意のステージ定義で走らせ直す（QA用）。
    ///
    /// `stageNumber`（ヘッダーの「ステージ N/18」表示・到達点の記録先）はそのまま
    /// 動かさない。「もう一度」「はじめから」を押すと `startStage` が `RunnerStage.all` から
    /// 引き直すので、ショーケースからは抜ける——QA専用の一時的な差し替えとして割り切る。
    private func applyDebugStage(_ customStage: RunnerStage) {
        debugStageOverride = customStage
        resetRun(RunnerField(stage: customStage))
    }

    /// 指定秒ぶん 60fps で進める。
    ///
    /// 決着の演出（`.falling` / `.chasing`）は `isRunning` に含めていないので、演出中で
    /// 止まらないようループの継続条件にも加える（そうしないと `-simulateRunner failed` が
    /// `.falling` で止まってしまい `.failed` の画が撮れない）。
    private func advanceFramesForDebug(seconds: Double) {
        var remaining = seconds
        while remaining > 0, phase.isRunning || phase.isSettling {
            tick(dt: 1.0 / 60)
            remaining -= 1.0 / 60
        }
    }

    /// 地形を読んで自動で跳びながら、`until` が真になるかゴールに着くまで走る（撮影用）。
    ///
    /// 判断は `RunnerAutoPilot` に置いてある。**テストが全ステージのクリア可能性を
    /// 確かめるのに使うのと同じ関数**なので、撮影用にだけ都合の良い操作を書き足す余地がない。
    /// 沈む床（#1089）の**手前**まで自動操縦で行く。床の左端まで体 3 つぶんに入った接地中の
    /// 瞬間で止めるので、そこから先は跳ばずに走るだけで水に入る。
    private func runUpToSinkFloorForDebug() {
        autoPlayForDebug(until: { model in
            guard let floor = model.field.stage.sinkFloors.first else { return true }
            return model.field.isGrounded && (0...24).contains(floor.start - model.field.distance)
        })
    }

    /// 崩れる足場（#1090）の**上**まで自動操縦で行く。板に足が着いた（崩れの時計が動き出した）
    /// 瞬間で止めるので、そこから先はこちらで走らせ方を決められる。
    private func runOntoCrumblingPlatformForDebug() {
        autoPlayForDebug(until: { model in
            model.field.stage.crumblingPlatforms.isEmpty || !model.field.crumbleElapsed.isEmpty
        })
    }

    /// 撮影用に、いま乗っている（または最後に乗った）崩れる足場の崩れ具合。
    private var crumbleProgressForDebug: Double? {
        field.crumbleElapsed.keys.sorted().last.flatMap { field.crumbleProgress($0) }
    }

    /// 走らせて、条件が満たされるまで進める（沈む床・崩れる足場の撮影用）。
    ///
    /// - Parameter jumping: true なら接地するたびに踏み切る。空中では乗り（`pedalBoost`）が
    ///   効かず横の進みが基準速に落ちるので、**いちばんゆっくり進む走り方**になる。
    private func advanceUntilForDebug(jumping: Bool = false, _ stop: (RunnerModel) -> Bool) {
        var frames = 0
        while phase.isRunning, !stop(self), frames < 60 * 30 {
            frames += 1
            if jumping, field.isGrounded { press(); release() }
            tick(dt: 1.0 / 60)
        }
    }

    private func autoPlayForDebug(until stop: (RunnerModel) -> Bool) {
        var frames = 0
        while phase.isRunning, !stop(self), frames < 60 * 120 {
            frames += 1
            // 着地するまで離さない（`RunnerAutoPilot.shouldRelease` を参照。早く離すと
            // ジャンプが切り詰められて越えられない）。
            if RunnerAutoPilot.shouldJump(field: field) { press() }
            if RunnerAutoPilot.shouldRelease(field: field) { release() }
            tick(dt: 1.0 / 60)
        }
    }
}
#endif
