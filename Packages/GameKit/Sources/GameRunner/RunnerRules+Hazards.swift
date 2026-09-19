import Foundation

/// 障害ごとの定数（#1149 で `RunnerRules.swift` から分けた）。
///
/// 沈む床（#1089）・崩れる足場（#1090）・高い塀（#1091）・動く障害（#796/#800/#801）・
/// 突き上げ（#1010）の 5 つ。基礎物理と進行は `RunnerRules.swift` にある。
extension RunnerRules {
    // MARK: 沈む床（#1089・会長決裁 2026-09-17〜18。里山＝田んぼ・港町＝干潟）

    /// 沈む床に乗っているあいだ、**接地中の速さ**に掛かる倍率。
    ///
    /// 置き場所も掛け方も加速床（`boostFloorMultiplier`）とまったく同じ——床は区間の性質で、
    /// 乗り（`pedalBoost`）は操作の上手さという別の軸なので掛け合わせる。加速床が 1 を超える
    /// 値なのに対し、こちらは 1 未満（「乗ると遅くなる」）。
    ///
    /// 値は 0.6。上限まで乗り切った状態（1.55）でも 0.93 倍で、**素の基準速より遅い**
    /// ——「漕いでも前に進まない」という泥の手応えを出すための下限。これより上げると
    /// 乗り切った人には減速が体感できず、下げると沈みを戻すための跳躍が間に合わなくなる
    /// （下の `sinkDuration` の見積もりはこの値を前提にしている）。
    /// **空中には一切乗らない**（`RunnerField.currentSpeed`）ので、加速床と同じく
    /// 「1 回のジャンプで進む距離 = `speed × jumpAirTime`」は動かない。
    public static let sinkFloorMultiplier: Double = 0.6

    /// 沈む床に**接地したまま**沈み切る（＝溺れる）までの秒数。
    ///
    /// 沈みは接地しているあいだだけ増え、**足が離れた瞬間に 0 へ戻る**
    /// （`RunnerField.sinkProgress`）。「一定量だけ減らす」形にしなかったのは、跳ぶ回数と
    /// 抜けられる長さの関係が跳んだ高さ・間隔で変わってしまい、「1 秒に 3 回の連打で
    /// いちばん長い床を抜けられる」という公平さの保証（`RunnerStageTests`）を
    /// 床の長さだけから計算できなくなるため。0 へ戻すなら、保証は
    /// **「接地が続く時間がこの秒数を超えないこと」**だけになる。
    ///
    /// 値は 0.8 秒。根拠:
    /// - **連打の側**: 人が無理なく出せる 1 秒 3 回（周期 0.333 秒）なら、接地が続くのは
    ///   最悪でも 0.333 秒で、0.8 秒の 4 割ちょうど。どれだけ長い床でも溺れない
    /// - **放置の側**: いちばん長い床（2 区画ぶん = 112）を跳ばずに渡ると、里山のいちばん遅い
    ///   面（21 面・速さ 50）でも 112 ÷ (50 × 1.55 × 0.6) ≒ 2.4 秒かかる。0.8 秒では渡り切れず
    ///   必ず溺れる＝「跳び続けろ」が成立する
    /// - **短い床（1 区画ぶん = 48）**も、素の乗りのままなら 48 ÷ 46.5 ≒ 1.0 秒で渡り切れない
    ///   ——最低 1 回は跳ぶ必要がある。アイテムの上乗せ（合計 1.95）まで乗せていれば
    ///   0.72 秒で走り抜けられるので、「加速して押し切る」選択肢は残る
    public static let sinkDuration: Double = 0.8

    /// 沈む床の左右に残す岸（あぜ道・干潟の縁）の幅（タイル数）。
    ///
    /// 床は区画まるごと（64）を占めるが、**両端に岸を残して水面だけを実効の長さにする**。
    /// こうしないと 1 区画ぶんの短い床でも長さが 64 になり、二段ジャンプの最大の飛距離
    /// （`doubleJumpRange(at:)` は 21 面の速さ 50 で 64.0）とちょうど同じで、
    /// **理屈の上でも越えられない**——「短い床は二段で跳び越せる」という決裁が成立しない。
    /// 岸を 2 タイルずつ残すと 1 区画ぶんの水面は 48 になり、21 面で 25% の余裕ができる。
    /// 見た目の側でも、水面の手前に必ず岸が見えるほうが「ここから沈む」と読みやすい。
    public static let sinkFloorBankTiles = 2

    /// 沈み切ったときに走者の**絵**が地面から下がる量（ワールド単位）。
    ///
    /// **当たり判定の地面の高さ（`RunnerField.Metrics.groundY`）は動かさない**（決裁）。
    /// 動かすとジャンプの軌道と全ステージの成立条件がやり直しになる。下がるのは
    /// `RunnerScene` が走者ノードを置く y だけ（`RunnerField.sinkDepth`）。
    /// 値は走者の高さ 11 の半分強で、沈み切る頃には腰まで浸かって見える。
    public static let sinkVisualDepth: Double = 6

    // MARK: 崩れる足場（#1090・会長決裁 2026-09-17〜18。里山＝古い吊り橋・港町＝古い木の桟橋）

    /// 崩れる足場の左右に残す岸（橋の袂・桟橋の付け根）の幅（タイル数）。
    ///
    /// 台座（`P`）は区画まるごと（64）を占めるが、**崩れる足場は両端に岸を残した板張りだけ**にする。
    /// 理由は 2 つ:
    ///
    /// - **公平さの計算に効く**。渡り切るのに要る距離がそのまま板張りの長さなので、短いほど
    ///   `crumbleDuration` に余裕が出る。区画まるごと（64）だと、ショーケース（速さ 34）で
    ///   渡り切るのに 1.88 秒かかり、崩れるまでの時間をそれ以上に伸ばさないと成立しない
    /// - **跳び越す選択肢が残る**。台座は正面が壁なので、左端に届く前に上面より高く上がる助走
    ///   （`riseTime(to: platformHeight) × 速さ` ＋ 半身）が要る。本編で足場を置いてある
    ///   いちばん遅い 24 面（52.4）では 助走 14.8 ＋ 板張り 48 = 62.8 で、二段ジャンプの飛距離
    ///   89.5（`doubleJumpRange(at:)`）の内側——「乗らずに跳び越えれば崩れない」という決裁の
    ///   遊びが成立する。区画まるごと（64）だと 78.8 になり、速い面でしか成立しない
    ///   （QA 用ショーケースの 34 では助走 12.4 ＋ 48 = 60.4 が飛距離 58.0 を超えて越えられないが、
    ///   そちらは撮影用のコースで本編には出ない）
    ///
    /// 沈む床の岸（`sinkFloorBankTiles`）と同じ値・同じ役割で、見た目の側でも
    /// 「板の手前に必ず地面が見える」ほうが踏み切る位置を読みやすい。
    public static let crumbleBankTiles = 2

    /// 崩れる足場の板張りの長さ（1 区画ぶん）。両端の岸を引いた実効値。
    public static var crumbleDeckLength: Double {
        Double(segmentTiles) * tileWidth - Double(crumbleBankTiles) * tileWidth * 2
    }

    /// 走者が**初めて乗ってから**、板が抜け始めるまでの秒数（ぎしぎし揺れているあいだ）。
    ///
    /// きっかけは初めて接地した瞬間だけで、以後は乗っていてもいなくても時計は進む
    /// （`RunnerField.crumbleElapsed`）。**跳んで着地し直しても二重に始まらない**のはこのため。
    ///
    /// 値は 0.5 秒。いちばん遅いショーケース（速さ 34）でも、乗りが上限（1.55）なら板張り 48 を
    /// 0.91 秒で渡るので、**普通に走っても半分あたりで板が抜け始めるのが見える**——
    /// 「乗るとぎしぎし揺れて、一定時間で崩れる」という決裁の手応えを、渡り切れる人にも
    /// 必ず 1 度は見せる長さ。
    public static let crumbleWarnDuration: Double = 0.5

    /// 板が抜け始めてから、足場が崩れ切るまでの秒数。
    ///
    /// **このあいだも板の上には乗れる**（決裁の「崩れ始めてから崩れ切るまでの間に乗っている
    /// 場合の扱い」への回答）。抜けるのは**左から順**で、走者は必ず右へ進むので、
    /// **板が消えた縁**（`RunnerScene.crumblePlankStagger`）が走者に追いつくことはない。
    /// 消えた縁は 1 次式で、**板張りの右端に届くのはちょうど `crumbleDuration`**
    /// ——そこでの走者の位置は「板張りの長さ < その面の速さ × `crumbleDuration`」が成り立つ限り
    /// 必ず先なので（`RunnerCrumblingPlatformTests.crumblingPlatformsAreCrossableAtMinimumPedal`
    /// が固定する）、両端で先なら途中も先になる。
    ///
    /// 「抜け始めた瞬間に落ちる」にしなかったのは、そうすると渡り切る猶予が
    /// `crumbleWarnDuration` だけになり、**予告を見せる時間と渡る時間が同じ枠を取り合う**ため。
    /// 分けておけば「予告は必ず見える」と「最低の乗りでも渡り切れる」を別々に決められる。
    public static let crumbleFallDuration: Double = 1.1

    /// 乗ってから足場が崩れ切るまでの秒数（揺れ + 抜け落ち）。渡り切る猶予そのもの。
    public static var crumbleDuration: Double { crumbleWarnDuration + crumbleFallDuration }

    /// 速さ `speed` の面に置ける崩れる足場の長さの上限。
    ///
    /// **ペダルの乗りが最低（1.0 倍）でも渡り切れること**が決裁の公平さの条件。接地中の速さは
    /// `speed × 乗り` で乗りは 1 以上、空中の横速度は必ず `speed`（`RunnerField.currentSpeed`）
    /// なので、**跳ぼうが跳ぶまいが横の進みは `speed` を下回らない**——上限はこの 1 本で足りる。
    ///
    /// 崩れの時計を進めるのは 1 サブステップの**移動より先**（`RunnerField.advance`）なので、
    /// 崩れ切る瞬間の走者は「時計どおりの位置」より最大 1 サブステップぶん手前にいる。
    /// その `RunnerField.Metrics.maxSubstep` を上限から引いて、式のほうで飲み込んでおく。
    ///
    /// 板張り 48 に対し、いちばん遅いショーケース（34）で 52.4、里山の初出 24 面（52.4）で 81.8。
    /// 2 区画ぶん（112）はどの面でも超えるので、**連続した `C` は機械的に弾かれる**。
    public static func crumbleMaxLength(at speed: Double) -> Double {
        speed * crumbleDuration - RunnerField.Metrics.maxSubstep
    }

    /// 二段ジャンプで空中にいられる最大の時間。
    ///
    /// 一段目で頂点（`jumpApex`）まで上がり、**その頂点で二段目を踏み切る**のがいちばん長い
    /// （二段目は `vy` を `jumpVelocity` に戻すので、高いところで踏み切るほど落ちるのに時間がかかる）。
    /// `v/g`（頂点まで）＋ `(v + √(v² + 2g·apex))/g`（そこから地面まで）= `v(2 + √2)/g`。
    /// 沈む床を「跳び越せるか」の上限はこの時間 × その面の基準速で決まる（`doubleJumpRange(at:)`）。
    public static var doubleJumpAirTime: Double {
        jumpVelocity * (2 + 2.0.squareRoot()) / gravity
    }

    /// 速さ `speed` の面で、二段ジャンプで跳び越せる横の距離の上限。
    ///
    /// **空中の横速度は必ず基準速**（`RunnerField.currentSpeed`）なので、乗りにも床の倍率にも
    /// 左右されない。沈む床の長さがこれを下回れば「二段で跳び越せる床」、上回れば
    /// 「跳び越せない床」（`RunnerStageTests` が両方を固定する）。
    public static func doubleJumpRange(at speed: Double) -> Double {
        speed * doubleJumpAirTime
    }

    // MARK: 二段ジャンプでしか越えられない高い塀（#1091・会長決裁 2026-09-17〜18。里山＝石垣・港町＝積まれたコンテナ）
    //
    // 以下の 3 つは**「一段目の頂点で二段目を踏む」ジャンプ**を基準にした値。二段目は `vy` を
    // `jumpVelocity` に戻す（`RunnerField.jump()`）ので、**高いところで踏むほど高く・長く**なり、
    // 一段目の頂点で踏むのがいちばん高い。自動操縦（`RunnerAutoPilot`）もそこで踏む。

    /// 二段ジャンプで届く最高点。一段目の頂点（`jumpApex`）で二段目を踏むので、ちょうど 2 倍。
    ///
    /// 高い塀（`RunnerHazardKind.wallTop` = 18）はこれより低く、`jumpApex` より高い——
    /// それが「二段でしか越えられない」の中身そのもの。
    public static var doubleJumpApex: Double { 2 * jumpApex }

    /// 踏み切ってから、二段ジャンプで足が高さ `height` に**初めて**届くまでの時間。
    /// 届かない高さなら `.infinity`。
    ///
    /// 一段目の頂点までの `v/g` に、そこから二段目で `height − jumpApex` を稼ぐ上昇時間を足す。
    /// `height` が一段の頂点より低ければ一段目の上昇だけで届くので `riseTime(to:)` と同じ。
    /// **踏み切りの余裕**（`RunnerAutoPilot.lead`）はこの時間 × 速さで決まる——塀は岩より高いので、
    /// そのぶん手前で踏み切る必要がある。
    public static func doubleJumpRiseTime(to height: Double) -> Double {
        guard height > jumpApex else { return riseTime(to: height) }
        let remaining = height - jumpApex
        let discriminant = jumpVelocity * jumpVelocity - 2 * gravity * remaining
        guard discriminant >= 0 else { return .infinity }
        return jumpVelocity / gravity + (jumpVelocity - discriminant.squareRoot()) / gravity
    }

    /// 二段ジャンプで足が高さ `height` 以上にある時間。0 なら届かない。
    ///
    /// `airTime(above:)` の二段版。**塀と横に重なっているあいだ、ずっと上端より上にいられるか**を
    /// `RunnerStageTests.everyHazardIsClearable` がこれで確かめる（一段の式をそのまま当てると、
    /// 塀は「越えられない障害」として弾かれてしまう）。
    ///
    /// **一段目の頂点より低い高さでも、二段ジャンプ全体で上にいる時間を返す**（PR #1115 で
    /// CodeRabbit が指摘）。塀（18）はこの分岐を通らないが、`airTime(above:)` を返す旧実装は
    /// 「一段目で上を通る時間」しか数えず、`height == jumpApex` では 0 という**式の名前と
    /// 食い違う値**になっていた。低い側は「一段目で `height` を越えてから頂点まで」＋
    /// 「頂点で踏み直して `height` まで降りてくるまで」の和で、`height` を 0 にすれば
    /// `doubleJumpAirTime` に、`jumpApex` に近づければ上の分岐に連続する。
    public static func doubleJumpAirTime(above height: Double) -> Double {
        guard height > 0 else { return doubleJumpAirTime }
        if height > jumpApex {
            let remaining = height - jumpApex
            let discriminant = jumpVelocity * jumpVelocity - 2 * gravity * remaining
            guard discriminant > 0 else { return 0 }
            return discriminant.squareRoot() / gravity * 2
        }
        let ascent = jumpVelocity / gravity - riseTime(to: height)
        let fall = (jumpVelocity * jumpVelocity + 2 * gravity * (jumpApex - height)).squareRoot()
        return ascent + (jumpVelocity + fall) / gravity
    }

    /// その障害を越えるジャンプの滞空時間。**高い塀（#1091）だけが二段ぶん**で、ほかは一段。
    ///
    /// 「前の障害を跳んで着地してから次の踏み切りに入れるか」（`RunnerStageTests.hazardsAreFarEnoughApart` /
    /// `RunnerEndlessCourse.hasLandingGap`）は、前の障害を跳んだ滞空で進む距離を土台にしている。
    /// 塀を二段で越えると滞空が 0.75 → 1.28 秒に伸びる（進む距離は約 1.7 倍）ので、
    /// **ここを一段で見積もると塀の次の障害が近すぎても緑になる**。
    public static func airTime(clearing kind: RunnerHazardKind) -> Double {
        kind == .wall ? doubleJumpAirTime : jumpAirTime
    }

    /// 高い塀の着地点（塀の右端から、二段ジャンプで降りてくるまで）に何も置かない距離。
    ///
    /// 二段ジャンプは滞空が長い（`doubleJumpAirTime` ≒ 1.28 秒）ぶん**着地点を選べない**ので、
    /// 決裁の「入れない組み合わせ」は塀の着地点に穴・突き上げ・沈む床・動物を禁じている。
    /// その「着地点」を距離で表したのがこの値——塀の右端から、いちばん速い面（30 面・57.2）で
    /// 降りきるまでに進む距離（`doubleJumpRange(at: 57.2)` ≒ 73.2）を区画（64）に切り上げた
    /// **2 区画**。`RunnerStageTests.wallsLeaveSafeLandingGround` が区画の記号で機械的に弾く。
    public static let wallLandingSegments = 2

    /// 高い塀の手前、鳥を置かない距離（区画数）。
    ///
    /// 鳥は**下を走り抜ける**相手（帯の下端が `RunnerHazardKind.birdMeetBottom` ≒ 14）で、
    /// 塀を越える二段ジャンプの軌道（頂点 28.13）はその帯を必ず通る。塀の手前で踏み切ると
    /// 鳥に当たり、鳥をくぐろうと待つと塀に間に合わない——どちらを選んでもミスになる。
    /// 1 区画（64）あれば、鳥をくぐってから塀の踏み切り地点（いちばん速い 30 面で 39.5 手前）に
    /// 着地して踏み切り直せる。`RunnerStageTests.noBirdRightBeforeAWall` が固定する。
    public static let wallBirdClearanceSegments = 1

    /// 高い塀の手前、たこ焼きを置かない距離（区画数）。
    ///
    /// たこ焼きの無敵（`invincibleDuration` = 3 秒）を着けたまま塀へ着くと、**二段ジャンプを
    /// 踏まずに素通りできる**——#1091 の「二段ジャンプに必然性を与える」が崩れる。
    /// 鳥（`wallBirdClearanceSegments`）と違って距離の規則が無く、27・30 面がたこ焼きから
    /// 4 区画で塀に着く並びのまま出ていた（#1148）。
    ///
    /// 要る距離は **3 秒 × 接地中に出せるいちばん速い速さ**。いちばん速い面（30 面・57.2）で
    /// ペダルの乗りが上限（`maxPedalBoost` 1.55）＋ジャスト着地の上乗せ（`justLandingOverboost`
    /// 0.2）なら 57.2 × 1.75 ≒ 100.1 で、3 秒に 300.4 進む。区画（64）に直すと 4.7 なので
    /// **手前 4 区画には置かない**（＝ 5 区画以上離す。5 区画 = 320 単位で 3.2 秒かかる）。
    /// 加速床があいだに架かる並びはこの区画数では足りないので、
    /// `RunnerDoubleJumpWallTests.noTakoyakiRightBeforeAWall` が座標でも見る。
    public static let wallTakoyakiClearanceSegments = 4

    // MARK: 動く障害（#796 飛び立つ鳥 / #800 犬 / #801 イノシシ・会長決裁 2026-09-14）
    //
    // どれも**走者の距離**で動く（時計では動かない）。ゆっくりモード・一時停止・ペダルの乗りに
    // 関わらず、同じ地点では同じ場所にいる——だから自動操縦のテストで軌道ごと固定できる。
    // 「走者が 1 進むあいだに動く量」（`advance`）で書いてあるので、走者の基準速に対する
    // 倍率がそのまま見た目の速さになる。

    /// 鳥が飛び立つ間合い。走者の**前端**がこの距離まで近づいた瞬間に飛び立つ（仕様「手前 6 タイル」）。
    ///
    /// 飛び立ってから走者の前端が帯に触れるまでの走者の進みは `G/(1−k)`（= 30）。1 面の速さで
    /// 0.88 秒、18 面で 0.55 秒——このあいだに鳥は跳んだ先の高さ（`birdClimbDistance` 参照）
    /// まで上がりきる。
    public static let birdTriggerDistance: Double = 6 * tileWidth
    /// 鳥の横の速さ（走者 1 に対して）。
    ///
    /// **大きいほど出会う地点が先へずれる。** 走者から見た鳥の等価な静止区間
    /// （`RunnerHazard.encounter`）は `start + k·G/(1−k)` から `(4 + 8)/(1−k) − 8` の長さ
    /// ——0.2 なら区画中央の 6 先から長さ 7。既存の面の `bt`（鳥の次の区画に高い岩）でも
    /// 着地して踏み切り直す余白が最速の 18 面で 2 単位以上残る値（0.25 だと 0.4 まで削れる）。
    /// 走者が鳥の下を抜けるあいだ（帯と横に重なる 15 単位）鳥は 3 だけ進み、抜けたあとは
    /// 走者の後ろへ置き去りになる。
    public static let birdAdvance: Double = 0.2
    /// 飛び立ってから、帯の下端が跳んだ先の高さ（`RunnerHazardKind.birdMeetBottom`）に届くまでの
    /// 鳥の移動量（1 タイル・#945）。そこから先は同じ高さのまま飛び続ける。
    ///
    /// **走者の前端が帯に触れる（`birdTravel` = `k·G/(1−k)` = 6）より手前で上がりきる**のが要点
    /// （#945 会長QA「飛び立つのが遅く、跳ぶだけで躱せる」）。鳥が 1 タイル進むあいだに走者は
    /// 20 進むので、上がりきるのは走者の前端が帯の 8 手前に来た時点。帯の下端が走者の頭
    /// （`RunnerField.Metrics.playerHeight` = 11）を越えるのはさらに手前（走者の進み 15、
    /// 帯までの間合い 16）で、自動操縦が岩と見なして踏み切る間合い（`RunnerAutoPilot.lead`・
    /// 上限の速さで 9.5）より十分外側——自動操縦は鳥を「跳ぶ相手」として見ずに済む
    /// （`RunnerHazardMotionTests.birdRisesAboveTheHeadBeforeTheTakeOffWindow`）。
    /// 上限は 1.5 タイル（= 6。触れる瞬間にちょうど上がりきる）で、そこまで延ばすと頭を越えるのが
    /// 間合いと同じ 9.5 手前になり、自動操縦が跳んで鳥に当たる。
    public static let birdClimbDistance: Double = 1 * tileWidth
    /// 上がる傾き（鳥が 1 進むごとに上がる高さ）。止まっている帯の下端から跳んだ先の高さまで、
    /// `birdClimbDistance` で一定に上がる。
    static var birdClimbSlope: Double {
        (RunnerHazardKind.birdMeetBottom - RunnerHazardKind.bird.bottom) / birdClimbDistance
    }
    /// 飛び立つ前に羽ばたく予備動作を始める、走者の距離の手前（見た目だけ・当たり判定は変えない）。
    public static let birdFlutterDistance: Double = 2 * tileWidth

    /// 犬が画面の右の外に現れてから、鼻先が走者の前端に触れるまでの走者の進み（#955）。
    ///
    /// 現れる瞬間、鼻先は走者の前端の `(1 + dogAdvance) × 56` ≒ 75.6 先——画面の先読み
    /// （`RunnerField.Metrics.width` − `playerX` − 半身 = 70）より 5.6 外側で、絵を当たり判定より
    /// 大きく描いても（#943 の倍率 2 で前後に 2 ずつ張り出す）画面の中に「湧く」ことは無い。
    /// 13 タイル（52）だと 70.2 でぎりぎり、これ以上長くしても見え方は変わらない
    /// （見えるのは画面に入ってからで、それは `dogAdvance` だけで決まる）。
    public static let dogApproachDistance: Double = 14 * tileWidth
    /// 犬の歩く速さ（走者 1 に対して）。走者に向かって左へ歩くので相対速度は `1 + dogAdvance`。
    ///
    /// 小さいほど静止した低い岩に近づく（0 なら低い岩そのもの）。相対速度が上がるほど重なる
    /// 時間は短くなる（等価な静止区間は `(4 + 8) / (1 + k) − 8`）が、**画面に入ってから触れる
    /// までの時間も縮む**: 画面の先読み 70 を `1 + k` で詰めるので、1 面の速さ（34）で
    /// 0.5 なら 1.37 秒、0.35 なら 1.53 秒——受け入れ条件「見えてから当たるまで 1.5 秒以上」
    /// （#955）を満たす上限が 0.37。0.35 で相対速度は 1.35、重なりは 8.9 / speed
    /// （低い岩の 12 / speed より短い）。18 面（47.6・#968）では 1.09 秒で、これは低い岩（1.47 秒）と
    /// 同じ比率で縮んでいるだけ。
    public static let dogAdvance: Double = 0.35

    /// イノシシの予告から出会いまでの走者の進み（仕様「1 秒ほど」）。
    ///
    /// 出会いの地点の手前この距離で「ドドド」と土煙が出て、同じ距離だけ向こうから走者と同じ
    /// 速さで向かってくる。7 面の基準速 41 で 1.75 秒、ペダルが乗った実際の速さ（1.3〜1.5 倍）で
    /// 1.2〜1.35 秒。出現点（`start + 72`）は次の区画の岩（`start + 64`〜`68`）より先なので、
    /// 岩の手前に置いた（`it`）イノシシはその岩で止まる。予告の瞬間、出現点は画面の外
    /// （前端から 148 先・見えるのは 74 まで）で、見えてから出会うまでは約 35 単位。
    public static let boarChargeDistance: Double = 18 * tileWidth
    /// イノシシの速さ（走者 1 に対して）。走者と同じなので相対速度は 2 倍。
    public static let boarAdvance: Double = 1

    // MARK: 突き上げ（#1010 竹の子・波しぶき・会長決裁 2026-09-17〜18）

    /// 突き上げの予告が出て伸び始める間合い。走者の**前端**がこの距離まで近づいた瞬間
    /// （`RunnerHazard.shootCueDistance`）。
    ///
    /// **値は「その区画が画面の右端に入る間合い」そのもの**（= 画面の先読み `width − playerX` から
    /// 前端のぶん半身を引いた 70）で、直値では書かない。予告は**見て読むもの**なので、
    /// 画面の外で出しても意味が無く、かつ**これ以上早くはできない**——読める時間の上限は
    /// 「画面に入ってから踏み切るべき地点に着くまで」で決まる。
    ///
    /// 実測（`RunnerHazardMotionTests.shootCueLeavesTimeToRead`）: 最速の 30 面（基準速 57.2）で、
    /// 予告から踏み切り地点（高い岩と同じ `lead` = 15.2 手前）までは 58.8 単位。**基準速で 1.03 秒**で、
    /// これは犬の「見えてから触れるまで」（18 面の基準速で 1.09 秒）とほぼ同じ——**同じ物差しで
    /// 並べるならここ**。ペダルが上限まで乗った実際の速さ（1.55 倍 = 88.7/秒）では **0.66 秒**で、
    /// これが最悪値。下限はテストで 0.6 秒に固定してある（#1010 の受け入れ条件が
    /// 「ペダル上限 1.55 倍でも」と物差しを指定しているため、上乗せ枠
    /// `pickupOverboost` / `justLandingOverboost` は載せない——両方乗った 1.95 倍では 0.53 秒になるが、
    /// それは一過性で、かつ予告〜踏み切りの区間に加速床が重なる配置は 29 本とも無い）。
    /// **これ以上短くしない**（画面に入るのと同時に出しているので、これ以上長くもできない）。
    public static var shootTriggerDistance: Double {
        RunnerField.Metrics.width - RunnerField.Metrics.playerX - RunnerField.Metrics.playerHalfWidth
    }
    /// 予告が出てから伸び切るまでの**走者の進み**（8 タイル）。
    ///
    /// 上限は「踏み切るべき地点に走者が来るまでに伸び切る」こと——`shootTriggerDistance + 半身
    /// − lead`（30 面で 58.8）まで延ばせるが、伸び切った姿を読む時間が無くなる。32 なら
    /// 30 面でも踏み切り地点の 26.8 手前（0.30 秒）で伸び切り、残りを「高い岩と同じ相手」として
    /// 読める。時間ではなく距離で決めているのは、動く障害すべてと同じ理由——同じ地点では
    /// 常に同じ高さになり、ゆっくりモード・一時停止・ペダルの乗りに左右されない。
    public static let shootRiseDistance: Double = 8 * tileWidth

}
