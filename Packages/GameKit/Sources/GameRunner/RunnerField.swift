import Core
import Foundation

/// 横スクロールランナーのコースそのもの（#494）。
///
/// **SpriteKit にも SwiftUI にも依存しない値型**で、`step(dt:)` を呼ぶと走者が進む。
/// ステージ番号・タイム・記録は持たない（それは `RunnerModel` の仕事）。
/// この分離のおかげで、当たり判定・ジャンプの軌道・ゴール判定をシミュレータ無しで検証できる。
///
/// 座標系は**左下が原点**（SpriteKit と同じ向き）。単位はコース固有の抽象単位で、
/// 画面 pt への変換は `RunnerScene` が `scaleMode = .aspectFit` で一括して行う。
/// 走者の画面上の x は動かず、**コースのほうが左へ流れる**（`distance` が世界での位置）。
public struct RunnerField: Equatable, Sendable {
    /// コースと走者の寸法。すべて抽象単位。
    public enum Metrics {
        /// 画面に見える横幅。
        ///
        /// 縦持ちの画面に載る帯の横幅なので、**広くしすぎない**。広げるほど 1 単位が
        /// 小さく描かれ、走者も地形も豆粒になる。最速のステージ（30 面の 57.2 / 秒・#1009）でも
        /// 走者の前に 74 単位 = 約 1.3 秒ぶんの地形が見えるので、初見でも反応できる。
        public static let width: Double = 100
        /// 画面に見える縦幅。
        ///
        /// 元は 80（`width` に対してほぼ正方形）→ 140（「正方形である意味がない」という
        /// 会長QAで縦長化・2026-09-10）→ 95（「プレイ画面の横幅を上部セクションと揃えて
        /// 不変にしてほしい」という会長QAで再調整・2026-09-11）→ **115**（会長QAで指摘された
        /// AdMob広告との隙間を詰めるため実測で再調整・2026-09-11）。
        ///
        /// `RunnerView.course`は`.aspectRatio(width/height, contentMode: .fit)`でこの比率に
        /// 固定されるため、比率が縦長すぎると横幅が`topSummary`より狭く縮む（#621）。
        /// **95は「横幅を100%使い切る」比率だが、実機では95が使う高さの先にもまだ余白があった**
        /// （会長がバナー広告との隙間をスクリーンショットで指摘・2026-09-11）。実機で
        /// 105→115→120と刻みながら横幅を計測し直したところ、**115までは横幅が一切縮まず、
        /// 120から縮み始める**ことを確認した。115はこの「横幅を保てる最大値」——
        /// 横幅を1ptも犠牲にせず、95より縦を約15%多く使える。
        /// `width`はそのまま（横方向に見える地形の量・1単位の大きさは変えない）。
        public static let height: Double = 115
        /// 地面の高さ（走者の足がここに乗る）。
        ///
        /// 跳んでも足が届くのは 34 + 21（大ジャンプの頂点）= 55 までなので、上端
        /// （`Metrics.height`）まで空にすると余る。地面をやや厚くしてその余りの一部を詰め、残りは
        /// `RunnerScene` の丘・雲で埋める（見た目の都合だけで、当たり判定はすべて
        /// 地面からの相対値で書いてあるため軌道は変わらない）。
        public static let groundY: Double = 34
        /// 走者の画面上の x（固定）。左に寄せて、先の地形を読む余裕を作る。
        public static let playerX: Double = 26
        public static let playerWidth: Double = 8
        public static let playerHeight: Double = 11

        public static var playerHalfWidth: Double { playerWidth / 2 }
        /// 1 サブステップで進んでよい最大距離。
        ///
        /// 障害 1 つの最小の長さ（`RunnerRules.tileWidth` = 4）より小さくしないと、
        /// 速いステージで 1 フレームぶん進んだ先が障害の向こう側になり、当たり判定を素通りする。
        public static let maxSubstep: Double = 2
    }

    /// 走っているコース。エンドレス（#1086）では速さの式だけを持つ空のコース
    /// （`RunnerEndlessCourse.stage`）で、中身は `track` が持つ。
    public let stage: RunnerStage
    /// エンドレスのコースの、いま走者のまわりにある区画（#1086）。ステージ制では nil。
    ///
    /// 障害・アイテム・台座・床の問い合わせは、ステージ制なら `stage` の配列を、エンドレスなら
    /// この枠を見る（下の「コースの中身」）。枠は `advance(dt:into:)` が 1 サブステップごとに
    /// 走者へ追いつかせる。**エンドレスにゴールとチェックポイントは無い**（`reachedGoal` /
    /// `passedCheckpoint` を出さない）。
    public private(set) var track: RunnerEndlessTrack?
    /// 走者の中心のワールド x。ステージ先頭が 0、`stage.length` でゴール。
    public private(set) var distance: Double
    /// 足元の高さ。`Metrics.groundY` が接地。
    public private(set) var footY: Double
    /// 上下の速度。
    public private(set) var vy: Double
    public private(set) var isGrounded: Bool
    /// 接地してから使ったジャンプの回数。着地すると 0 に戻る（`RunnerRules.maxJumps` まで）。
    public private(set) var jumpCount: Int
    /// ジャンプボタンを押し続けているか（大ジャンプ）。**離した瞬間にまだ true なら**、
    /// `endHold()` が上昇速度を切り詰める（`RunnerRules.jumpCutVelocity`）。
    /// 着地すると自動的に `false` へ戻る。
    public private(set) var isHolding: Bool
    /// 踏み切ってからの経過秒（`isHolding` のあいだだけ進む）。`jumpCutGraceTime` に
    /// 達するまでは `endHold()` が呼ばれても実際には切り詰めず、猶予が明けた瞬間に
    /// `pendingCut` があれば切り詰める（会長QA「進まねえ」2026-09-11 への対応。詳細は
    /// `RunnerRules.jumpCutGraceTime` のドキュメントを参照）。
    private var holdElapsed: Double = 0
    /// 猶予中に `endHold()` が呼ばれ、猶予明けに切り詰めを適用すべきか。
    private var pendingCut: Bool = false
    /// チェックポイントを通過済みか。
    public private(set) var passedCheckpoint: Bool
    /// ペダルの乗り（#569）。1.0 が下限で、`RunnerRules.maxPedalBoost` が上限。
    ///
    /// 接地して漕いでいるあいだに上がり、跳んでいるあいだは漕げないので落ちる。
    /// **速さに効くのは接地しているあいだだけ**（`currentSpeed`）。
    public private(set) var pedalBoost: Double
    /// スピードアップアイテムを取った直後だけ乗る、上限（`maxPedalBoost`）を超える一時的な
    /// 上乗せ分。時間経過で 0 まで減衰する（`RunnerRules.pickupOverboostDuration`）。
    ///
    /// **「もう乗りが上限に達している状態で取っても意味がない」という会長QA
    /// （2026-09-10）への対応**。`pedalBoost` 自体の上限は変えず、取った瞬間だけ別枠で
    /// 上乗せすることで、どんな乗り具合で取っても必ず体感できる加速になる。
    public private(set) var pickupOverboost: Double = 0
    /// `pickupOverboost` が 0 になるまでの残り秒数。
    private var pickupOverboostRemaining: Double = 0
    /// 取得済みのアイテムの数（スピードアップ・たこ焼きを問わない）。
    public private(set) var collectedPickupCount: Int = 0
    /// 沈む床（#1089）にどれだけ沈んでいるか（0…1）。1 で溺れてミス。
    ///
    /// **接地して沈む床の上にいるあいだだけ増える**（`RunnerRules.sinkDuration` 秒で 1 に届く）。
    /// 足が離れた瞬間——跳んでも、床を出ても——**0 に戻す**。「跳ぶと沈みが戻る」を
    /// 状態遷移ではなく「接地していなければ 0」という不変条件で書いてあるので、
    /// 一時停止・バックグラウンド復帰・チェックポイント再開のどこにも取りこぼす経路が無い。
    ///
    /// ゆっくりモードでは `RunnerModel.tick` が `dt` そのものを縮めるので、沈む速さも
    /// 同じ割合で遅くなる（この型は時計を知らない）。
    public private(set) var sinkProgress: Double = 0
    /// 沈みに応じて走者の**絵**を下げる量（ワールド単位）。`RunnerScene` が走者ノードの y から引く。
    ///
    /// **当たり判定には一切効かない**（決裁「当たり判定の地面の高さは変えない」）。
    /// `footY` も `surfaceY(at:)` も動かさないので、ジャンプの軌道と全ステージの成立条件は
    /// 沈んでいるかどうかに左右されない——沈んだ状態で踏み切っても普通のジャンプになる。
    public var sinkDepth: Double { sinkProgress * RunnerRules.sinkVisualDepth }
    /// たこ焼き（#797）の無敵の残り秒数。0 なら無敵ではない。
    ///
    /// 取り直すと満タンに戻す（重ねない。`pickupOverboost` と同じ扱い）。空中でも減る
    /// ——「取ってから何秒」の物差しで、跳んで時間を止めて持ち越せてはいけない。
    /// 画面の残り時間表示（`RunnerView`）はこの値をそのまま読む。
    public private(set) var invincibleRemaining: Double = 0
    /// 直前の着地がジャスト着地だったか（#673）。
    ///
    /// 着地するたびに書き換わる（ジャストでなければ false に戻る）ので、`.landed` の
    /// できごとと**同じフレームでだけ**意味を持つ。触覚の強さを変えるのに Model が使う。
    public private(set) var lastLandingWasJust: Bool = false
    /// この走行で決めたジャスト着地の回数。**1 回の着地につき 1 増える単調増加**。
    ///
    /// 描画側（`RunnerScene`）は毎フレームこの数を前フレームと比べて土煙を出す。
    /// できごと（`RunnerEvent`）を増やさずに済ませているのは、`collectedPickupCount` と
    /// 同じ理由——見た目だけの都合でルール層のできごとを増やすと、Model の分岐が
    /// 演出のために太る。
    public private(set) var justLandingCount: Int = 0
    /// いまの滞空を始めた地点（接地中は nil）。ジャスト着地の判定で「この滞空のあいだに
    /// 越えた障害」を絞り込むのに使う。
    private var jumpStartDistance: Double?
    /// ジャスト着地で乗っている、上限（`maxPedalBoost`）を超える一時的な上乗せ分（#673）。
    ///
    /// **`pickupOverboost` とまったく同じ仕組み**（時間で線形に減衰し、接地中だけ効く）。
    /// `pedalBoost` に足す形では上限に張り付いた状態で何も起きず、効果が測れないほど
    /// 小さかった（`RunnerRules.justLandingOverboost` のドキュメント参照）。
    public private(set) var justLandingOverboost: Double = 0
    /// `justLandingOverboost` が 0 になるまでの残り秒数。
    private var justLandingOverboostRemaining: Double = 0
    /// 直近のミスの原因（#796）。`.fell` / `.crashed` を返した瞬間に決まり、解析の `game_end` の
    /// `cause` に載る。台座の正面（`isHittingPlatformFace`）は岩と同じ扱い。ミスするまで nil。
    public private(set) var lastMissCause: AnalyticsEndCause?
    /// `stage.pickups` のうち、すでに取得した添字。**同じ走行中に同じアイテムは 1 回しか取れない**。
    ///
    /// 描画側はこの添字でノードを消す。**取得は先頭から順とは限らない**——チェックポイントから
    /// 再開すると手前のアイテムは取らないまま残る（#733）。
    ///
    /// エンドレス（#1086）では**区画の通し番号**（`RunnerEndlessSegment.index`）で覚える。枠の中の
    /// 位置で覚えると、枠を回した瞬間に取っていないアイテムが消える／取ったアイテムが復活する。
    /// 枠から捨てた区画の番号はここからも消す（距離に比例して増えない）。
    public private(set) var collectedPickupIndices: Set<Int> = []
    /// エンドレスで、`collectedPickupIndices` からこの番号より手前の区画を消し終えている（#1086）。
    private var collectedPickupsPrunedBelow = 0

    /// ステージの頭から始める。
    public init(stage: RunnerStage) {
        self.init(stage: stage, startingAt: 0, passedCheckpoint: false)
    }

    /// 指定した地点から始める（チェックポイント再開・テスト用）。
    public init(stage: RunnerStage, startingAt distance: Double, passedCheckpoint: Bool) {
        self.stage = stage
        self.distance = distance
        self.footY = Metrics.groundY
        self.vy = 0
        self.isGrounded = true
        self.jumpCount = 0
        self.isHolding = false
        self.passedCheckpoint = passedCheckpoint
        self.pedalBoost = 1
    }

    /// エンドレスのコースを頭から走る（#1086）。コースは走りながら種 `seed` から作る。
    public init(endlessSeed seed: UInt64) {
        self.init(endless: RunnerEndlessTrack(seed: seed))
    }

    /// 枠の数などを変えた `track` で走る（テスト用）。
    init(endless track: RunnerEndlessTrack) {
        self.init(stage: RunnerEndlessCourse.stage)
        self.track = track
        // 取ったアイテムの番号は枠にある区画のぶんしか持たないので、枠の数だけ先に取っておく。
        collectedPickupIndices.reserveCapacity(track.capacity)
    }

    // MARK: - 問い合わせ

    /// ゴールまでの進み具合（0〜1）。エンドレス（#1086）にゴールは無く、常に 1（画面には出さない）。
    public var progress: Double {
        guard stage.length > 0 else { return 1 }
        return min(1, max(0, distance / stage.length))
    }

    /// いま実際に進んでいる速さ（ワールド単位 / 秒）。
    ///
    /// **空中では必ず `stage.speed`**（ペダルを漕げないので乗りが効かない・#569）。
    /// この一点で「跳んで進む距離 = `speed × 滞空時間`」が乗りに左右されなくなり、
    /// ステージの成立条件（`RunnerStageTests`）を丸ごと据え置ける。`pickupOverboost` も
    /// ジャスト着地の上乗せ（#673）もスピードアップ床の倍率（#672）も、同じ理由で
    /// 接地中にしか効かせない。
    ///
    /// 床の倍率が**掛け算**で乗る理由は `RunnerRules.boostFloorMultiplier` を参照
    /// （床は区間の性質、乗りは操作の上手さ、と別の軸なので掛け合わせる）。
    public var currentSpeed: Double {
        // 基準速はその地点の値（#675）。ステージ制では `stage.speed` そのもの。
        let base = stage.speed(at: distance)
        guard isGrounded else { return base }
        // 加速床と沈む床は同じ区画に置けない（区画記号は 1 文字）ので、掛かるのは高々どちらか一方。
        var floor: Double = 1
        if isOnBoostFloor { floor *= RunnerRules.boostFloorMultiplier }
        if isOnSinkFloor { floor *= RunnerRules.sinkFloorMultiplier }
        return base * (pedalBoost + pickupOverboost + justLandingOverboost) * floor
    }

    /// いまスピードアップ床の上に乗っているか（#672）。
    ///
    /// **状態は持たず毎回位置から判定する**ので、区間を出た瞬間に効果が切れる
    /// （アイテムのような減衰は無い）。判定に使うのは矩形ではなく**中心の x**——穴
    /// （`isPit`）と同じ物差しにしてある。矩形で見ると爪先が縁にかかった時点から効き始め、
    /// 床の境目が走者の体の幅ぶんぼやけて「どこから速くなったのか」が読めない。
    ///
    /// 空中では常に false（跳んだ瞬間に効果が切れる）。床の真上を跳んでいる間まで速いと、
    /// 「跳んで進む距離 = `speed × 滞空時間`」が崩れてステージの成立条件がやり直しになる。
    public var isOnBoostFloor: Bool {
        guard isGrounded else { return false }
        return firstBoostFloor { $0.start <= distance && distance < $0.end } != nil
    }

    /// いま沈む床（#1089）の上に乗っているか。
    ///
    /// 判定の作法は加速床（`isOnBoostFloor`）とまったく同じ——状態は持たず**中心の x** で
    /// 毎回見るので、水面を出た瞬間に減速も沈みも切れる。空中では常に false で、
    /// そのおかげで「跳んでいるあいだは沈まない・空中の横速度は基準速のまま」が両方成り立つ。
    ///
    /// 台座（#674）の上に乗っているあいだも false——台座は水面より上の接地面なので、
    /// 足は水に浸かっていない（`surfaceY(at:)` が地面より高い値を返す）。
    public var isOnSinkFloor: Bool {
        guard isGrounded, surfaceY(at: distance) <= Metrics.groundY else { return false }
        return firstSinkFloor { $0.start <= distance && distance < $0.end } != nil
    }

    /// いま無敵か（たこ焼き・#797）。true のあいだは岩・鳥・台座の正面に当たっても
    /// `.crashed` を出さない。**穴は落ちる**（`advance` の接地判定はこの値を見ない）。
    public var isInvincible: Bool { invincibleRemaining > 0 }

    /// 走者の当たり判定の矩形。
    public var playerMinX: Double { distance - Metrics.playerHalfWidth }
    public var playerMaxX: Double { distance + Metrics.playerHalfWidth }
    /// 足元の**地面からの**高さ。
    ///
    /// 台座（#674）の上に立っていると `RunnerRules.platformHeight` になる——**接地面からの
    /// 高さではなく、あくまで地面が 0 の物差し**のまま。障害の高さ（`RunnerHazard.height`）・
    /// 描画（`RunnerScene` は `footY` をそのまま使う）・ジャンプの軌道の検証
    /// （`FieldTests` が `jumpApex` と突き合わせる）がすべてこの物差しで書かれているので、
    /// ここを「接地面からの高さ」に変えると台座の有無で意味が変わる値になってしまう。
    public var altitude: Double { footY - Metrics.groundY }

    /// `x` に穴が開いているか（点で見る）。
    public func isPit(at x: Double) -> Bool {
        firstHazard { $0.kind == .pit && $0.start <= x && x < $0.end } != nil
    }

    /// その x で**足が乗る高さ**（#674）。台座の範囲内なら台座の上面、外は地面。
    ///
    /// 「足が地面まで落ちたら接地」という既存の判定を、地面の代わりにこの値と比べる形へ
    /// 一本化したもの。`Metrics.groundY` を直に見ている接地まわりの箇所はすべてここを通す
    /// ——そうしておかないと「地面では接地するが台座では素通りする」という食い違いが生まれる。
    ///
    /// 覆っている台座が複数あれば**最も高い上面**を採る。**第 1 弾ではこの `max` に到達しない**
    /// ——台座の高さは 1 種類（`RunnerRules.platformHeight`）で、連続する `P` は 1 基に
    /// まとまるため、ある x を覆う台座は常に高々 1 つ。高さ違いの台座を足して段を重ねる日
    /// （次弾）に効く受け口として残してある。
    public func surfaceY(at x: Double) -> Double {
        var surface = Metrics.groundY
        forEachPlatform { platform in
            guard platform.start <= x && x < platform.end else { return }
            surface = max(surface, Metrics.groundY + platform.top)
        }
        return surface
    }

    /// 走者の**前方**にある最も近い障害。自動操縦テストと先読みの読み上げが使う。
    ///
    /// 動く障害（#796）は**いまの位置**（`frame(atRunnerDistance:)`）で見る。配列の並び
    /// （置いた位置の順）と現在の並びは食い違いうる——岩の右側で止まったイノシシは、置いた
    /// 位置では岩の手前の区画でも、いまは岩の向こう側にいる。まだ現れていない障害（突進前の
    /// イノシシ・現れる前の犬）と、上がりきって接地した走者の頭より高い鳥は対象にしない
    /// （跳ぶ相手ではない）。
    public func nextHazard(from x: Double) -> RunnerHazard? {
        var best: (hazard: RunnerHazard, start: Double)?
        forEachHazard { hazard in
            guard let frame = hazard.frame(atRunnerDistance: distance), frame.end > x else { return }
            guard hazard.kind == .pit || frame.bottom < Metrics.playerHeight else { return }
            if best == nil || frame.start < best!.start { best = (hazard, frame.start) }
        }
        return best?.hazard
    }

    /// `nextHazard` と同じ規則で、その障害の**いまの当たり判定**を返す。
    public func nextHazardFrame(from x: Double) -> (hazard: RunnerHazard, frame: RunnerHazardFrame)? {
        guard let hazard = nextHazard(from: x),
              let frame = hazard.frame(atRunnerDistance: distance) else { return nil }
        return (hazard, frame)
    }

    /// 走者の**前方**にある最も近い台座（#674）。自動操縦が「跳んで乗る」対象に使う。
    ///
    /// 左端がまだ前方にあるものだけを返す。すでに上に乗っている台座（左端を通り過ぎている）を
    /// 返してしまうと、自動操縦が台座の上で踏み切り続けることになる。
    public func nextPlatform(from x: Double) -> RunnerPlatform? {
        firstPlatform { $0.start >= x }
    }

    // MARK: - 操作

    /// 踏み切る。接地中か、空中でもまだ二段目が残っていれば効く（`RunnerRules.maxJumps`）。
    ///
    /// 二段目も初速は一段目と同じ `jumpVelocity` にする。踏み切った時点の `vy` へ足し込むと
    /// 頂点付近で踏み切るほど高く跳べてしまい、地形の成立条件が踏み切りのタイミング次第で
    /// 変わってしまう（`RunnerStageTests` が前提にできなくなる）。
    @discardableResult
    public mutating func jump() -> Bool {
        guard jumpCount < RunnerRules.maxJumps else { return false }
        // 滞空の起点は**一段目の踏み切り**。二段目で上書きすると、一段目で越えた障害が
        // 「この滞空で越えた障害」から外れてしまう（#673）。
        //
        // **この `isGrounded` は意図の表明で、いまの物理では観測できない**（2026-09-13 の
        // 敵対的検証で確認。外しても全テストが緑）。上書きすると起点が後ろへ動いて候補が
        // 減るだけなので、選ばれる障害の右端は小さくなる方向にしか変わらない。そして
        // 答えが変わるのは「二段目より後に越えた障害が無い」場合だけだが、二段目は `vy` を
        // `jumpVelocity` に戻すので着地は必ず `jumpAirTime` 以上あと——最低でも
        // 34 × 0.75 = 25.5 先で、窓（`RunnerRules.justLandingWindow` = 8）の外。
        // つまり答えが変わる場合はどちらの実装でも加算されない。二段目の弾道を弱める
        // （短いホップにする等）変更を入れた日にここが効き始めるので、残してある。
        if isGrounded { jumpStartDistance = distance }
        vy = RunnerRules.jumpVelocity
        isGrounded = false
        // 沈み（#1089）は「接地していなければ 0」が不変条件だが、**次の `advance` を待たずに
        // ここで戻す**。描画（`RunnerScene.sync`）は `tick` と独立に毎フレーム走るので、
        // 踏み切った直後に一時停止すると `advance` が呼ばれないまま、空中の走者が沈んだ位置で
        // 描かれ続ける（PR #1110 の指摘）。
        sinkProgress = 0
        jumpCount += 1
        isHolding = true
        holdElapsed = 0
        pendingCut = false
        return true
    }

    /// ボタンを離す。
    ///
    /// **猶予時間（`RunnerRules.jumpCutGraceTime`）を過ぎていれば、その場で `vy` を
    /// 切り詰める**（会長QA「軽いタップなら本当に小ジャンプぐらいの感じにしたい」
    /// 2026-09-10）。踏み切った直後にすぐ離すほど高い `vy` のまま切り詰められて低い
    /// ホップになり、離すのが遅くなる（＝長押しする）ほど重力で `vy` がすでに下がっている
    /// ため切り詰めの影響が薄れ、十分粘れば無傷の全弾道（`RunnerRules.jumpApex`）まで伸びる
    /// ——重力そのものはどちらの場合も一定のまま（旧方式の「押している間だけ重力を弱める」
    /// より単純）。
    ///
    /// **猶予時間の間に呼ばれた場合は、その場では切り詰めず `pendingCut` を立てるだけ**にする
    /// （`advance(dt:)` が猶予明けに適用する）。`press()`→`release()` が同じフレーム内で
    /// ほぼ同時に呼ばれるタップ操作で `vy` がまだ何も減っていないまま切り詰められ、
    /// ステージ1の最初の穴にすら届かない、という不具合（会長QA「進まねえ」2026-09-11）
    /// への対応。
    public mutating func endHold() {
        guard isHolding else { return }
        if holdElapsed >= RunnerRules.jumpCutGraceTime {
            applyCutIfNeeded()
            isHolding = false
        } else {
            pendingCut = true
        }
    }

    private mutating func applyCutIfNeeded() {
        if vy > RunnerRules.jumpCutVelocity {
            vy = RunnerRules.jumpCutVelocity
        }
    }

    /// テスト・撮影用に走者を直接置く。製品コードからは呼ばない。
    ///
    /// `altitude` は `altitude` プロパティと同じ**地面からの高さ**。台座の上に置きたければ
    /// `RunnerRules.platformHeight` を渡す（接地したかどうかは、その x の接地面
    /// （`surfaceY(at:)`）に届いているかで決まる）。
    public mutating func placeForTesting(distance: Double, altitude: Double, vy: Double) {
        self.distance = distance
        self.footY = Metrics.groundY + altitude
        self.vy = vy
        self.isGrounded = footY <= surfaceY(at: distance) && vy <= 0
        self.jumpCount = self.isGrounded ? 0 : 1
        self.isHolding = false
        self.holdElapsed = 0
        self.pendingCut = false
        // 空中に置いた場合は「ここで踏み切った」扱い。手前の障害を越えた扱いにはしない。
        self.jumpStartDistance = self.isGrounded ? nil : distance
        self.lastMissCause = nil
        self.sinkProgress = 0
        advanceTrack()
    }

    // MARK: - 進行

    /// `dt` 秒ぶん進め、その間に起きたできごとを順に返す。
    ///
    /// **決着（ミス・ゴール）が起きた時点で打ち切る**。以降のできごとは「もう走っていない走者」の
    /// もので、続けて処理するとミスとゴールが同じフレームに並ぶ。
    public mutating func step(dt: Double) -> [RunnerEvent] {
        guard dt > 0 else { return [] }
        var events: [RunnerEvent] = []

        // 1 サブステップの移動量を障害の最小寸法より小さく抑える（すり抜け防止）。
        // 横は**この dt のあいだに出しうる最大の速さ**で見積もる。いまの速さで割ると、
        // 同じ dt の中でペダルが乗ったぶんだけ 1 サブステップの移動量が見積もりを超える。
        // スピードアップ床（#672）に踏み込むとさらに倍率が乗るので、床の上に居るかに
        // 関わらず**常に床の倍率まで見込んで**刻む（見積もりを多めに取るぶんには
        // サブステップが細かくなるだけで、進み方も当たり判定も変わらない）。
        //
        // 上限を超える上乗せ（アイテム `pickupOverboost` とジャスト着地
        // `justLandingOverboost`・#673）も足す。**`maxPedalBoost` だけで見積もると
        // 上乗せが乗っているあいだ 1 サブステップが `Metrics.maxSubstep`（2）を超える**。
        //
        // 実測（dt は上限の `maxStep` = 1/20 秒。床がある 16〜18 面で起きる。数字は #968 で
        // 18 面が 47.6 に下がる前の 54.4 のもので、速い側の見積もりとして残してある）:
        // - ステージ18（速さ 54.4・床の上）の旧式の見積もりは 54.4 × 1.55 × 1.3 × 0.05 =
        //   5.481 → 3 分割。ところが実移動は上乗せ 2 つとも乗ると
        //   54.4 × 1.95 × 1.3 × 0.05 = 6.895 で、**1 サブステップ 2.298**
        //   （アイテム単独の 1.75 倍でも 6.188 → 2.063）
        // - 床が無いステージ（〜15 面）では超過しない。ステージ15 は見積もり 5.118 に対し
        //   実移動 4.953（床の倍率ぶん見積もりが多めなので追いつかれない）
        //
        // 障害の最小寸法（`RunnerRules.tileWidth` = 4）よりは小さいのですり抜けは
        // 起きていなかったが、安全の余裕が削れていた既存の見落とし。新式では同じ条件
        // （ステージ18・全部乗り）で 6.895 → 4 分割・1 サブステップ 1.724 に収まる。
        let maxFactor = RunnerRules.maxPedalBoost
            + RunnerRules.pickupOverboost
            + RunnerRules.justLandingOverboost
        // 基準速は上限（`speedCap`。ステージ制では `speed` と同じ）で見積もる（#675）。
        let horizontal = stage.speedCap * maxFactor * RunnerRules.boostFloorMultiplier * dt
        let vertical = abs(vy) * dt + RunnerRules.gravity * dt * dt
        let travel = max(horizontal, vertical)
        let substeps = max(1, Int((travel / Metrics.maxSubstep).rounded(.up)))
        let substepDT = dt / Double(substeps)

        for _ in 0..<substeps {
            advance(dt: substepDT, into: &events)
            if events.last?.isTerminal == true { return events }
        }
        return events
    }

    /// 1 サブステップ。
    private mutating func advance(dt: Double, into events: inout [RunnerEvent]) {
        // ペダルは地面でしか漕げない（#569）。跳んでいるあいだは乗りが落ちる。
        let rate = isGrounded ? RunnerRules.pedalGain : -RunnerRules.pedalLoss
        pedalBoost = min(RunnerRules.maxPedalBoost, max(1, pedalBoost + rate * dt))
        // アイテムの上乗せ分は時間で線形に減衰する。取った瞬間の乗り具合に関わらず、
        // 必ず一定時間ぶんの加速が体感できる（`currentSpeed` を参照）。
        if pickupOverboostRemaining > 0 {
            pickupOverboostRemaining = max(0, pickupOverboostRemaining - dt)
            pickupOverboost = RunnerRules.pickupOverboost
                * (pickupOverboostRemaining / RunnerRules.pickupOverboostDuration)
        }
        // ジャスト着地の上乗せ分も同じ形で減衰する（#673）。**跳んでいるあいだも減る**
        // ——上乗せは「決めた直後の勢い」なので、空中で時間を止めて持ち越せてはいけない
        // （`currentSpeed` が空中では効かせないのと合わせて、跳べば跳ぶほど損になる）。
        if justLandingOverboostRemaining > 0 {
            justLandingOverboostRemaining = max(0, justLandingOverboostRemaining - dt)
            justLandingOverboost = RunnerRules.justLandingOverboost
                * (justLandingOverboostRemaining / RunnerRules.justLandingOverboostDuration)
        }
        // 無敵（たこ焼き・#797）も同じ物差しで減る。速さには一切効かない。
        if invincibleRemaining > 0 {
            invincibleRemaining = max(0, invincibleRemaining - dt)
        }
        let previousDistance = distance
        distance += currentSpeed * dt
        // エンドレス（#1086）は、進んだぶんだけ前の区画を作って後ろの区画を捨てる。
        advanceTrack()

        // 動く障害の予告の地点をこのサブステップでまたいだ（#801 イノシシの突進。犬は #955 で
        // 前から歩いて来るようになり予告を持たない）。手応え・土煙の発火点で、当たり判定には
        // 関わらない（位置は `frame(atRunnerDistance:)` が距離から引く）。チェックポイント再開で
        // この地点より先から走り出した場合は鳴らない（予告する相手がいない）。
        forEachHazard { hazard in
            guard let cue = hazard.cue else { return }
            if previousDistance < cue.distance, cue.distance <= distance { events.append(cue.event) }
        }

        // 台座の端から出た（#674）。接地面が足の下から消えるので、そのまま落下へ移す。
        // ここで切り替えておかないと `isGrounded && vy == 0` のまま重力が掛からず、
        // 台座の高さのまま空中を走り続けてしまう。落ちた先が穴なら、下の接地判定で
        // 既存の穴の判定がそのまま効く。
        if isGrounded, footY > surfaceY(at: distance) {
            isGrounded = false
        }

        if !isGrounded || vy != 0 {
            // 重力は押している間も一定（大ジャンプの高さは `endHold()` の切り詰めだけで決まる）。
            vy -= RunnerRules.gravity * dt
            footY += vy * dt
        }

        // 猶予時間ぶん経過したら、猶予中に来ていた `endHold()` を今適用する。
        if isHolding {
            holdElapsed += dt
            if pendingCut, holdElapsed >= RunnerRules.jumpCutGraceTime {
                applyCutIfNeeded()
                isHolding = false
                pendingCut = false
            }
        }

        // 障害物は矩形どうしの重なりで見る（岩・低く飛ぶ鳥・犬・イノシシは跳んで越える）。
        // 台座（#674）は正面（左端）に突っ込んだ場合だけ同じくミスになる。
        // 無敵（たこ焼き・#797）のあいだはこの判定だけを通さない——動く障害（飛び立つ鳥・犬・
        // イノシシ・#796）も岩と同じく素通りする。穴は下の接地判定で従来どおり落ちる。
        // 台座の正面に突っ込んだ場合は当たり判定を素通りして上面に乗る
        // （`surfaceY(at:)` が台座の範囲で上面を返すので、次の接地判定で足が上面に止まる）。
        if !isInvincible {
            if let hit = hittingHazard {
                lastMissCause = hit.kind.missCause
                events.append(.crashed)
                return
            }
            if isHittingPlatformFace {
                lastMissCause = .rock
                events.append(.crashed)
                return
            }
        }

        // アイテム。「触れると得する」だけなので、穴・障害物と違って
        // 高さは問わず横方向の重なりだけで見る。`currentSpeed` の「空中では必ず基準速度」
        // という不変条件には触れない（接地しているあいだしか乗りは効かないので、
        // 跳んで取ってもその場では速くならない）。
        //
        // スピードアップの効果は2つ: (1) `pedalBoost` を即座に上限へ引き上げる（乗れていない
        // 状態で取った場合の底上げ）、(2) それとは別枠の `pickupOverboost` を一時的に乗せる
        // （会長QA「取るタイミングが大体もうMAX速度で意味がない」2026-09-10 への対応。
        // `pedalBoost` 自体はどの道 `maxPedalBoost` で頭打ちなので、上限に張り付いた状態で
        // 取っても (1) だけでは何も変わらない。上限を超える一時的な上乗せにすることで、
        // 乗り具合に関わらず必ず体感できる加速にする）。
        // たこ焼き（#797）は速さに触らず、無敵の残り時間を満タンにするだけ。
        if let track {
            // エンドレス（#1086）は区画の通し番号で覚える（`collectedPickupIndices` を参照）。
            for position in 0..<track.count {
                let segment = track[position]
                guard let pickup = segment.pickup, !collectedPickupIndices.contains(segment.index) else { continue }
                collect(pickup, index: segment.index, into: &events)
            }
        } else {
            for (index, pickup) in stage.pickups.enumerated() where !collectedPickupIndices.contains(index) {
                collect(pickup, index: index, into: &events)
            }
        }

        // 接地面は「地面 or 台座の上面」（#674）。台座の範囲内なら上面で止まる。
        let surface = surfaceY(at: distance)
        if footY <= surface {
            // 穴の判定は**中心の x** で行う。矩形で見ると爪先が縁を越えた瞬間に落ちてしまう。
            // 台座の上に落ち着く場合は穴を見ない——穴は地面に開いた欠落なので、その上に
            // 台座が架かっているなら渡れる（台座の端から降りれば下の穴の判定が効く）。
            if surface <= Metrics.groundY, isPit(at: distance) {
                lastMissCause = .pit
                events.append(.fell)
                return
            }
            let wasAirborne = !isGrounded
            footY = surface
            vy = 0
            isGrounded = true
            jumpCount = 0
            isHolding = false
            pendingCut = false
            if wasAirborne {
                applyJustLanding()
                events.append(.landed)
            }
        }

        // 沈む床（#1089）。**接地して水面の上にいるあいだだけ**沈みが溜まり、足が離れていれば
        // 0 に戻る。溜まり切ったら溺れてミス——穴に落ちたときと同じ `.fell` を出す
        // （見た目も「下へ沈んでいく」で、`RunnerScene` の落下演出がそのまま合う）。
        // 死因だけは `.sink` で区別する。
        if isOnSinkFloor {
            sinkProgress = min(1, sinkProgress + dt / RunnerRules.sinkDuration)
            if sinkProgress >= 1 {
                lastMissCause = .sink
                events.append(.fell)
                return
            }
        } else {
            sinkProgress = 0
        }

        // エンドレス（#1086）にチェックポイントとゴールは無い。
        guard track == nil else { return }

        if !passedCheckpoint, distance >= stage.checkpoint {
            passedCheckpoint = true
            events.append(.passedCheckpoint)
        }

        if distance >= stage.length {
            distance = stage.length
            events.append(.reachedGoal)
        }
    }

    /// 走者の体に触れていればアイテムを取る。`index` は取得済みとして覚える番号（`collectedPickupIndices`）。
    private mutating func collect(_ pickup: RunnerPickup, index: Int, into events: inout [RunnerEvent]) {
        guard playerMinX <= pickup.start, pickup.start <= playerMaxX else { return }
        collectedPickupIndices.insert(index)
        collectedPickupCount += 1
        switch pickup.kind {
        case .speed:
            pedalBoost = RunnerRules.maxPedalBoost
            pickupOverboost = RunnerRules.pickupOverboost
            pickupOverboostRemaining = RunnerRules.pickupOverboostDuration
            events.append(.collectedSpeedItem)
        case .invincible:
            invincibleRemaining = RunnerRules.invincibleDuration
            events.append(.collectedInvincibleItem)
        }
    }

    /// エンドレスの枠を走者の位置に追いつかせ、枠から捨てた区画の取得済みの印を消す（#1086）。
    private mutating func advanceTrack() {
        guard track != nil else { return }
        track!.advance(to: distance)
        let firstIndex = track!.firstIndex
        while collectedPickupsPrunedBelow < firstIndex {
            collectedPickupIndices.remove(collectedPickupsPrunedBelow)
            collectedPickupsPrunedBelow += 1
        }
    }

    /// 着地した瞬間に「越えた障害の真裏に降りられたか」を見て、一時的な上乗せを乗せる（#673）。
    ///
    /// **速さに触るのは接地中だけ**——空中の横速度（`currentSpeed`）は基準のままなので、
    /// 「1 回のジャンプで進む距離 = `speed × jumpAirTime`」という全ステージの成立条件
    /// （`RunnerStageTests`）の物差しは動かない（#635 決裁）。
    ///
    /// ギリギリで跳んで直後に降りれば上乗せが乗り続け、早すぎ・遅すぎの跳び方では
    /// 何も乗らない。これがベストタイムに出るスキル差の実体。
    ///
    /// **台座（#674）は対象外**。台座は `RunnerHazard` とは別の型（`RunnerPlatform`）で、
    /// そもそも `stage.hazards` に居ないので網羅 switch（`rewardsJustLanding`）には
    /// 現れない——「越えた対象」は岩と穴だけ。台座は越えるものではなく乗るもので、
    /// 上面に降りるのは「越えた直後の着地」ではないため報酬の対象にしない。
    /// 台座から降りたあと**その先の穴を越えて**着地した場合は、越えた対象が穴なので普通に拾う。
    private mutating func applyJustLanding() {
        lastLandingWasJust = false
        guard let takeOff = jumpStartDistance else { return }
        jumpStartDistance = nil
        // 「直前に越えた障害」= この滞空のあいだに**中心 x が右端を通過した**障害のうち最後のもの。
        // `hazards` は左から順に並んでいるので `last` がそのまま「最後に越えたもの」になる。
        var cleared: RunnerHazard?
        forEachHazard { hazard in
            if Self.rewardsJustLanding(hazard.kind), hazard.end > takeOff, hazard.end <= distance { cleared = hazard }
        }
        guard let cleared else { return }
        guard distance - cleared.end <= RunnerRules.justLandingWindow else { return }
        // 上限（`maxPedalBoost`）を超える別枠に乗せる。重ねず、決め直すたびに上書きして
        // 満タンへ戻す（`pickupOverboost` と同じ扱い）。
        justLandingOverboost = RunnerRules.justLandingOverboost
        justLandingOverboostRemaining = RunnerRules.justLandingOverboostDuration
        lastLandingWasJust = true
        justLandingCount += 1
    }

    /// ジャスト着地の対象になる障害か（#673）。
    ///
    /// **跳んで越え、置いた位置（`RunnerHazard.end`）がそのまま「真裏」になるものだけ**
    /// ——「越えた直後に降りる」が判定の実体なので、跳び越える対象でない障害を混ぜると、
    /// 越え方と関係なく上乗せが乗る。
    /// 鳥は飛んで動いている相手で「真裏」が置いた位置にない（#796）、イノシシ（#801）と犬（#955）は
    /// 向かってきて走者の体の中を通り抜けるので、どれも対象外。
    /// 突き上げ（#1010）は横に動かず、走者が着く前に伸び切って置いた位置の高い岩そのものになる
    /// ので岩と同じ扱い（実際には高さ 9 を落ちるあいだに体 4 つぶん進むため、岩と同じく窓に
    /// 入ることは無い。判断を 1 か所に閉じるために対象からは外さない）。
    private static func rewardsJustLanding(_ kind: RunnerHazardKind) -> Bool {
        switch kind {
        case .pit, .lowBlock, .tallBlock, .shoot: return true
        case .bird, .dog, .boar:                  return false
        }
    }

    /// いま当たっている障害物（無ければ nil）。ミスの原因（`lastMissCause`）を決めるのに種類が要る。
    ///
    /// 縦は**帯どうしの重なり**で見る（#671）。走者は足（`footY`）から頭
    /// （`footY + playerHeight`）まで、障害は帯の下端から上端まで。地面から生えている岩は
    /// 下端が 0 なので「頭が下端より上」は常に真になり、従来どおり「足が上端より上なら
    /// 飛び越えている」だけの判定に一致する。位置と帯は**いまの走者の距離で引く**
    /// （`RunnerHazard.frame(atRunnerDistance:)`・#796）——上がりきった鳥は帯が頭より上に
    /// 抜けるので、同じ式のまま自然に当たらなくなる。
    private var hittingHazard: RunnerHazard? {
        firstHazard { hazard in
            guard hazard.kind != .pit,
                  let frame = hazard.frame(atRunnerDistance: distance) else { return false }
            guard frame.start < playerMaxX, playerMinX < frame.end else { return false }
            return footY < Metrics.groundY + frame.top
                && Metrics.groundY + frame.bottom < footY + Metrics.playerHeight
        }
    }

    /// いま台座の正面（左端）に突っ込んでいるか（#674）。高い障害物と同じくミスになる。
    ///
    /// **中心がまだ台座の左端より手前にある場合しか見ない**のが要点。矩形の重なりだけで
    /// 判定すると、上面を走り切って右端から降りる瞬間——尻がまだ台座に重なったまま、
    /// 足が上面より下へ落ちる——を「正面衝突」と取り違えて、まっとうな着地が全部ミスになる。
    /// 走者は後退しないので、中心が左端を越えた時点でその台座は「乗ったか、越えたか」の
    /// どちらかであって、もう当たるものではない。
    ///
    /// **`private` にしていないのは境界をテストで直接突けるようにするため**。`step` 経由だと
    /// この判定に来る前に `distance` と `footY` が動いてしまい、「中心が左端ちょうど」
    /// 「足が上面ちょうど」という 2 つの等号の扱いを固定できない
    /// （`FieldTests.platformFaceIsInclusiveAtTheBoundary`）。
    var isHittingPlatformFace: Bool {
        firstPlatform { platform in
            guard distance < platform.start else { return false }
            guard platform.start < playerMaxX else { return false }
            return footY < Metrics.groundY + platform.top
        } != nil
    }

    // MARK: - コースの中身（#1086）
    //
    // ステージ制は `stage` の配列、エンドレスは `track` の枠を、どちらも**左から順に**見る。
    // 当たり判定・接地・先読みはすべてここを通す（片方だけ直して食い違わないように）。

    /// 障害を左から順に見て、`predicate` を満たす最初のもの。
    private func firstHazard(where predicate: (RunnerHazard) -> Bool) -> RunnerHazard? {
        guard let track else { return stage.hazards.first(where: predicate) }
        for position in 0..<track.count {
            if let hazard = track[position].hazard, predicate(hazard) { return hazard }
        }
        return nil
    }

    /// 障害を左から順にすべて見る。
    private func forEachHazard(_ body: (RunnerHazard) -> Void) {
        guard let track else { return stage.hazards.forEach(body) }
        for position in 0..<track.count {
            if let hazard = track[position].hazard { body(hazard) }
        }
    }

    /// 台座を左から順に見て、`predicate` を満たす最初のもの。
    private func firstPlatform(where predicate: (RunnerPlatform) -> Bool) -> RunnerPlatform? {
        guard let track else { return stage.platforms.first(where: predicate) }
        for position in 0..<track.count {
            if let platform = track[position].platform, predicate(platform) { return platform }
        }
        return nil
    }

    /// 台座を左から順にすべて見る。
    private func forEachPlatform(_ body: (RunnerPlatform) -> Void) {
        guard let track else { return stage.platforms.forEach(body) }
        for position in 0..<track.count {
            if let platform = track[position].platform { body(platform) }
        }
    }

    /// スピードアップ床を左から順に見て、`predicate` を満たす最初のもの。
    private func firstBoostFloor(where predicate: (RunnerBoostFloor) -> Bool) -> RunnerBoostFloor? {
        guard let track else { return stage.boostFloors.first(where: predicate) }
        for position in 0..<track.count {
            if let floor = track[position].boostFloor, predicate(floor) { return floor }
        }
        return nil
    }

    /// 沈む床を左から順に見て、`predicate` を満たす最初のもの。
    ///
    /// **エンドレス（#1086）には沈む床を置かない**（#1089 決裁「生成器に教えるのは別の版」）ので、
    /// 枠で走っているあいだは常に nil。生成器（`RunnerEndlessCourse`）が `~` を出さないことは
    /// `RunnerStageTests.endlessCourseHasNoSinkFloors` が固定する。
    private func firstSinkFloor(where predicate: (RunnerSinkFloor) -> Bool) -> RunnerSinkFloor? {
        guard track == nil else { return nil }
        return stage.sinkFloors.first(where: predicate)
    }
}
