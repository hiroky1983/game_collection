import Foundation

/// 打球の種別（受け口 8: 方向・距離・種別の 3 つ組の「種別」）。数値は保存（`HomerunShot`）に使うので並びを変えない。
public enum HomerunKind: Int, Codable, Equatable, Sendable, CaseIterable {
    /// 空振り・見逃し（押さずに見送った場合も同じ）。距離 0。
    case miss = 0
    /// ファウル（方向が ±45° を越えた）。距離 0。
    case foul = 1
    /// 打球がフェアゾーンに落ちた（柵には届かず）。
    case inPlay = 2
    /// 柵の手前でフェンスに当たった。
    case fenceHit = 3
    /// 柵越え。
    case homer = 4
}

/// タイミングの段階。離した時刻と輪が的に重なる時刻の差（ミリ秒）の絶対値で決まる。
public enum HomerunTiming: Int, Codable, Equatable, Sendable {
    case just = 0, nice = 1, hit = 2, miss = 3

    public static let justWindow = 25.0
    public static let niceWindow = 60.0
    public static let hitWindow = 110.0

    public init(offsetMilliseconds: Double) {
        let a = abs(offsetMilliseconds)
        if a <= Self.justWindow { self = .just }
        else if a <= Self.niceWindow { self = .nice }
        else if a <= Self.hitWindow { self = .hit }
        else { self = .miss }
    }

    /// 飛距離の土台（m）。#1594 会長 QA で柵越えを出やすくした（旧 135 / 120 / 100）。
    var baseDistance: Double {
        switch self {
        case .just: 140
        case .nice: 125
        case .hit: 110
        case .miss: 0
        }
    }
}

/// 角度の 4 帯（カーソルの高さ）。
public enum HomerunLaunch: Int, Codable, Equatable, Sendable {
    case grounder = 0, liner = 1, fly = 2, pop = 3

    /// 帯の幅（pt）。ゾーンの 1/4（ゾーンの寸法の基準。縦の帯の境目は下の `linerFloor` 〜 `popFloor`）。
    public static let bandWidth = 22.0

    /// 帯の境目（ボールの中心からカーソルまでの縦のずれ・pt・下が正）。ここ以上がその帯。
    /// #1647 会長 QA: 以前はフライが 11〜33pt（芯の基準点 22pt = 芯の円の外）で、ボールのかなり下を叩かないと
    /// 最も飛ばなかった。PR #1649 でフライを 5〜25pt に寄せたが、まだ「下に大きく外しても柵越え」「かなり下を狙わないと
    /// 柵越えが出ない」だった（3D の球が 2D の的と縦にずれて映っていたのが主因・`HomerunAtBatLayout.pitchTarget` で直した）。
    /// フライを -3〜11pt（ボールの真ん中〜少し下）にし、芯の円（半径 `HomerunJudge.coreRadius` = 11pt）の外の下側は
    /// ポップ（柵越えにならない）にした。柵越え率を保つため、ライナーをボールの上寄り（-17〜-3pt）へ広げた。
    public static let linerFloor = -17.0
    public static let flyFloor = -3.0
    public static let popFloor = 11.0

    /// `dy`: ボールの中心からカーソルまでの縦のずれ（pt・下が正）。境界は角度の大きい方の帯に入れる。
    /// 下で当てるほど（dy が大きいほど）角度の大きい帯になる（ゴロ → ライナー → フライ → ポップ）。
    public init(cursorDY dy: Double) {
        if dy < Self.linerFloor { self = .grounder }
        else if dy < Self.flyFloor { self = .liner }
        else if dy < Self.popFloor { self = .fly }
        else { self = .pop }
    }

    /// 芯の基準点の高さ（ボールの中心から・pt・下が正）。芯の係数はここからの距離で決まる（ここで 1.0）。
    /// ライナーはボールの上寄り・フライはボールの中心の少し下（芯の円の内側・#1647）。ゴロ・ポップは帯の外側の境目から帯の幅の半分。
    public var centerDY: Double {
        switch self {
        case .grounder: Self.linerFloor - Self.bandWidth / 2
        case .liner: -8
        case .fly: 4
        case .pop: Self.popFloor + Self.bandWidth / 2
        }
    }

    /// 飛距離の係数。帯の中では一定（補間しない）。#1594 でライナー 0.85 → 1.0・フライ 1.0 → 1.15（柵越えを出やすく）。
    /// #1647 でライナー 1.0 → 1.05（フライの帯を芯の円の中へ狭めたぶん、ナイスのライナーでも柵越えが出るように）。
    public var distanceFactor: Double {
        switch self {
        case .grounder: 0.3
        case .liner: 1.05
        case .fly: 1.15
        case .pop: 0.5
        }
    }

    /// 弧の見た目に使う打ち出し角（度）。帯の中は線形に補間する（判定には使わない）。
    /// ゴロ・ポップは帯の幅 1 つぶんで 0° / 55° に届き、その外は打ち止め。
    public static func angle(cursorDY dy: Double) -> Double {
        let w = bandWidth
        let low = linerFloor - w, high = popFloor + w
        let clamped = min(max(dy, low), high)
        switch HomerunLaunch(cursorDY: clamped) {
        case .grounder: return 10 * (clamped - low) / w
        case .liner: return 10 + 15 * (clamped - linerFloor) / (flyFloor - linerFloor)
        case .fly: return 25 + 10 * (clamped - flyFloor) / (popFloor - flyFloor)
        case .pop: return 35 + 20 * (clamped - popFloor) / w
        }
    }
}

/// 1 スイングの入力（受け口 3: タイミング + カーソル座標の 3 値）。
public struct HomerunSwing: Equatable, Sendable {
    /// 離した時刻 − 輪が的に重なる時刻（ミリ秒）。負が早い。
    public var timingOffset: Double
    /// ボールの中心から見たカーソルの位置（pt・右が正・下が正）。
    public var cursorDX: Double
    public var cursorDY: Double

    public init(timingOffset: Double, cursorDX: Double, cursorDY: Double) {
        self.timingOffset = timingOffset
        self.cursorDX = cursorDX
        self.cursorDY = cursorDY
    }
}

/// 空振りの理由（#1594）。
public enum HomerunMissReason: Equatable, Sendable {
    /// 振るのが早い（当たり窓より前）。
    case early
    /// 振るのが遅い（当たり窓より後）。
    case late
    /// タイミングは合っていたが、照準がボールから外れていた。
    case aim
}

/// 能力値（受け口 1: 飛距離の式の入力を 1 本の構造体にする）。第 1 弾は `.standard` 固定。
public struct HomerunAbilities: Equatable, Sendable {
    /// パワー: 土台に足す距離（m）。
    public var power: Double
    /// ミート: 芯の当たり判定の半径にかける倍率。
    public var meet: Double
    /// バット: 最終距離にかける倍率。
    public var bat: Double

    public init(power: Double = 0, meet: Double = 1, bat: Double = 1) {
        self.power = power
        self.meet = meet
        self.bat = bat
    }

    public static let standard = HomerunAbilities()
}

/// 1 球の結果（受け口 8: 方向・距離・種別）。
public struct HomerunBattedBall: Equatable, Sendable {
    /// 打球方向（度・0 が中堅・負が左）。空振りは 0。
    public var direction: Double
    /// 飛距離（m）。ファウル・空振りは 0。
    public var distance: Double
    public var kind: HomerunKind
    public var timing: HomerunTiming
    public var launch: HomerunLaunch?
    /// 打球のあった方向の柵の距離（m）。空振りは中堅の値。
    public var fence: Double
    /// 月まで飛んだ（#1680 の隠し演出）。nil は普通の打球。1 挑戦（`HomerunChallenge.swing`）が条件
    /// （`HomerunJudge.isMoonShot`）を見て `.hit` を付け、同じ挑戦の 2 回目は `.broken` にする。保存（`HomerunShot`）には持たない。
    public var moon: HomerunMoon? = nil

    /// 月まで飛んだか。
    public var isMoon: Bool { moon != nil }
}

/// 月まで飛んだ打球の段階（#1680・会長決裁 2026-10-01）。
public enum HomerunMoon: Int, Codable, Equatable, Sendable {
    /// 1 回目: 月に当たってヒビが入る。
    case hit = 0
    /// 2 回目（同じ挑戦の中）: 月が半分に割れ、その挑戦は終わる（残りの球は没収・プレイ回数 +2）。
    case broken = 1

    /// 画面に出す飛距離（km・地球から月までのおおよその距離）。記録・合計には `HomerunJudge.moonCountedDistance`（m）で数える。
    public static let displayKilometers = 384_400
}

/// 判定の純粋ロジック（README §3.1）。乱数は使わない: 同じ入力は必ず同じ結果になる。
public enum HomerunJudge {
    /// 引っ張り・流しの最大（カーソル由来）。
    public static let maxCursorDirection = 35.0
    /// タイミング由来の最大。
    public static let maxTimingDirection = 15.0
    /// これを越える（絶対値）とファウル。
    public static let foulLimit = 45.0
    /// カーソルの横のずれがこの値で最大の 35° になる（pt）。
    public static let fullDeflection = 11.0
    /// 芯の半径（pt・ゾーンの 1/8）。帯の芯の基準点（`HomerunLaunch.centerDY`）から数えて、ここで係数 `coreEdgeFactor`。
    public static let coreRadius = 11.0
    /// 芯の半径（`coreRadius`）での芯の係数（#1594 で 0.8 → 0.9）。
    public static let coreEdgeFactor = 0.9
    /// 当たり判定の半径（pt・#1594 試作）。芯の外でもここまでは当たる（係数 `coreEdgeFactor` → `edgeFactor` へ下がる）。
    /// ゾーン（88pt）の 1 マスぶん（約 29.3pt）。以前は芯の半径（11pt）の外は空振りで、ボールのマスまで正確にずらさないと当たらなかった。
    public static let contactRadius = HomerunLaunch.bandWidth * 4 / 3
    /// 当たり判定の縁（`contactRadius`）での芯の係数（#1594 で 0.5 → 0.8。照準が多少ずれても飛ぶように）。
    public static let edgeFactor = 0.8
    /// 柵の手前でこの距離（m）以内なら「フェンス直撃」。
    public static let fenceHitMargin = 6.0
    /// 最高の当たり（ジャストの真ん中 0ms × フライの芯の基準点）の飛距離（m）。会長指示 2026-10-01（#1647）で 161m（140 × 1.15）→ 約 180m。
    /// 上乗せ（`sweetSpot`）はフライ・ジャストの窓の中・芯の円の中だけで効くので、ナイス・当たり・芯の外・ライナーの飛距離と
    /// 柵越え率はほぼ変わらない。
    public static let bestDistance = 180.0

    // MARK: 月（#1680・会長決裁 2026-10-01「ほとんど出ない」隠し演出）

    /// 月まで飛ぶタイミングのずれの幅（ms・±）。会長決裁の ±0.05 秒。
    public static let moonTimingWindow = 50.0
    /// 月まで飛ぶカーソルの幅（pt）: フライの芯の基準点（`HomerunLaunch.fly.centerDY`・ボールの中心の 4pt 下）からの距離がこれ以内。
    /// ボールの中心（何もずらさず真ん中の球を打ったとき・照準の吸い寄せが寄せる先）は基準点から 4pt 離れているので入らない。
    /// 1pt はゾーン（88pt）の 1/88。会長指示（2026-10-01）「ちょっと打ちやすく」で 0.5pt から広げた
    /// （発生率の見込み: ふつうの遊び方で 1 挑戦あたり約 11%・芯を狙う人で約 35%。見積もりは #1680 の PR の説明）。
    public static let moonCursorRadius = 1.0
    /// 月まで飛んだ打球を記録（自己ベスト・合計・最長）に数える距離（m）= 最高の当たりの飛距離（会長決裁: 180m として数える）。
    public static var moonCountedDistance: Double { bestDistance }

    /// 月まで飛ぶ条件は判定（`judge`・ふだんの飛距離の式）には入れず、1 挑戦（`HomerunChallenge.swing`）が振るたびに見る
    /// （1 挑戦の中で回数を数える演出なので）。
    /// 月まで飛ぶ条件（タイミング ±`moonTimingWindow` ms 以内 かつ カーソルがフライの芯の基準点から `moonCursorRadius` 以内）。
    public static func isMoonShot(_ swing: HomerunSwing) -> Bool {
        abs(swing.timingOffset) <= moonTimingWindow
            && hypot(swing.cursorDX, swing.cursorDY - HomerunLaunch.fly.centerDY) <= moonCursorRadius
    }

    /// 月まで飛んだ打球（柵越え・`moonCountedDistance` m・`.hit`）。方向はふだんの式（条件の中では ±10° に収まる）を、
    /// 確認用に条件の外から作ったとき（DEBUG の `-homerunForceMoon`）もフェアになるよう ±20° に丸める。
    public static func moonBall(_ swing: HomerunSwing) -> HomerunBattedBall {
        let direction = min(max(direction(swing), -20), 20)
        let timing = HomerunTiming(offsetMilliseconds: swing.timingOffset)
        return HomerunBattedBall(direction: direction, distance: moonCountedDistance, kind: .homer,
                                 timing: timing == .miss ? .just : timing, launch: .fly,
                                 fence: fence(atDirection: direction), moon: .hit)
    }

    /// 最高の当たりの近さ（0〜1）。`(タイミングの近さ) × (芯の近さ)` で、両方が満点（0ms・帯の芯の基準点ちょうど）で 1。
    /// タイミングの近さはジャストの窓（±25ms）の端で 0、芯の近さは芯の半径（`coreRadius` × ミート）で 0。
    /// 掛け算なので、片方だけ良くても伸びは小さい（例: 10ms・基準点から 2pt で 0.49 = 約 +9m）。
    public static func sweetSpot(timingOffset: Double, distanceFromBandCenter d: Double,
                                 abilities: HomerunAbilities = .standard) -> Double {
        let timing = max(1 - abs(timingOffset) / HomerunTiming.justWindow, 0)
        let core = max(1 - d / (coreRadius * max(abilities.meet, 0.01)), 0)
        return timing * core
    }

    /// 最高の当たり（`sweetSpot` = 1）でフライに上乗せする距離（m・161m → 180m の差 19m）。
    static var sweetSpotExtra: Double { bestDistance - HomerunTiming.just.baseDistance * HomerunLaunch.fly.distanceFactor }

    /// 柵の距離。両翼 100m・中堅 122m。
    public static func fence(atDirection degrees: Double) -> Double {
        100 + 22 * cos(2 * degrees * .pi / 180)
    }

    /// 芯の係数。`d` は「カーソルが入った角度の帯の芯の基準点（`centerDY`）」からカーソルまでの距離（pt）。
    /// 中心で 1.0・芯の半径で `coreEdgeFactor`・当たり判定の半径（`contactRadius`）で `edgeFactor`（それぞれ線形）・その外は 0（空振り）。
    /// 基準点から測るのは、帯の幅が芯の直径と同じくらいで、ボール中心から測ると柵越えの帯（少し下）が常に芯の縁の係数以下になるため。
    public static func core(distanceFromBandCenter d: Double, abilities: HomerunAbilities = .standard) -> Double {
        let meet = max(abilities.meet, 0.01)
        let radius = coreRadius * meet
        let contact = max(contactRadius * meet, radius)
        if d > contact { return 0 }
        if d <= radius { return 1 - (1 - coreEdgeFactor) * d / radius }
        return coreEdgeFactor - (coreEdgeFactor - edgeFactor) * (d - radius) / (contact - radius)
    }

    /// 空振りの理由（結果に出す・#1594）。振っていない（見送り）・空振りでない（当たった・ファウル）なら nil。
    /// タイミングが窓の外なら早い / 遅い（照準も外れていてもタイミングを先に言う）、窓の中なら照準のずれ。
    public static func missReason(_ swing: HomerunSwing?, abilities: HomerunAbilities = .standard) -> HomerunMissReason? {
        guard let swing, judge(swing, abilities: abilities).kind == .miss else { return nil }
        if HomerunTiming(offsetMilliseconds: swing.timingOffset) == .miss {
            return swing.timingOffset < 0 ? .early : .late
        }
        return .aim
    }

    /// 打球方向（度）。カーソルの左右（内側 = 引っ張り = 左）にタイミング（早い = 引っ張り）を足す。
    public static func direction(_ swing: HomerunSwing) -> Double {
        let cursor = min(max(swing.cursorDX / fullDeflection, -1), 1) * maxCursorDirection
        let timing = min(max(swing.timingOffset / HomerunTiming.hitWindow, -1), 1) * maxTimingDirection
        return cursor + timing
    }

    /// `swing` が nil のときは押さずに見送った扱い（空振りと同じ）。
    public static func judge(_ swing: HomerunSwing?, abilities: HomerunAbilities = .standard) -> HomerunBattedBall {
        let centerFence = fence(atDirection: 0)
        guard let swing else {
            return HomerunBattedBall(direction: 0, distance: 0, kind: .miss, timing: .miss, launch: nil, fence: centerFence)
        }
        let timing = HomerunTiming(offsetMilliseconds: swing.timingOffset)
        let launch = HomerunLaunch(cursorDY: swing.cursorDY)
        let fromCenter = hypot(swing.cursorDX, swing.cursorDY - launch.centerDY)
        let core = core(distanceFromBandCenter: fromCenter, abilities: abilities)
        guard timing != .miss, core > 0 else {
            return HomerunBattedBall(direction: 0, distance: 0, kind: .miss, timing: timing, launch: nil, fence: centerFence)
        }
        let direction = direction(swing)
        let fence = fence(atDirection: direction)
        if abs(direction) > foulLimit {
            return HomerunBattedBall(direction: direction, distance: 0, kind: .foul, timing: timing, launch: launch, fence: fence)
        }
        var distance = (timing.baseDistance + abilities.power) * launch.distanceFactor * core * abilities.bat
        if launch == .fly {
            distance += sweetSpotExtra * sweetSpot(timingOffset: swing.timingOffset, distanceFromBandCenter: fromCenter,
                                                   abilities: abilities) * abilities.bat
        }
        let kind: HomerunKind
        if distance >= fence { kind = .homer }
        else if distance >= fence - fenceHitMargin { kind = .fenceHit }
        else { kind = .inPlay }
        return HomerunBattedBall(direction: direction, distance: distance, kind: kind, timing: timing, launch: launch, fence: fence)
    }
}

/// 方向の呼び名（結果の内訳・通算の集計）。
public enum HomerunSector: Int, Codable, Equatable, Sendable, CaseIterable {
    case left = 0, leftCenter, center, rightCenter, right

    public init(direction: Double) {
        switch direction {
        case ..<(-21): self = .left
        case ..<(-7): self = .leftCenter
        case ...7: self = .center
        case ...21: self = .rightCenter
        default: self = .right
        }
    }

    public var label: String {
        switch self {
        case .left: "レフト"
        case .leftCenter: "左中間"
        case .center: "センター"
        case .rightCenter: "右中間"
        case .right: "ライト"
        }
    }
}
