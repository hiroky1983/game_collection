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

    /// 飛距離の土台（m）。
    var baseDistance: Double {
        switch self {
        case .just: 135
        case .nice: 120
        case .hit: 100
        case .miss: 0
        }
    }
}

/// 角度の 4 帯（カーソルの高さ）。
public enum HomerunLaunch: Int, Codable, Equatable, Sendable {
    case grounder = 0, liner = 1, fly = 2, pop = 3

    /// 帯の幅（pt）。ゾーンの 1/4。
    public static let bandWidth = 22.0

    /// `dy`: ボールの中心からカーソルまでの縦のずれ（pt・下が正）。境界は角度の大きい方の帯に入れる。
    public init(cursorDY dy: Double) {
        if dy < -Self.bandWidth / 2 { self = .grounder }
        else if dy < Self.bandWidth / 2 { self = .liner }
        else if dy < Self.bandWidth * 1.5 { self = .fly }
        else { self = .pop }
    }

    /// 帯の中心の高さ（ボールの中心から・pt・下が正）。ライナーがボールの高さ。
    public var centerDY: Double { Double(rawValue - 1) * Self.bandWidth }

    /// 飛距離の係数。帯の中では一定（補間しない）。
    public var distanceFactor: Double {
        switch self {
        case .grounder: 0.3
        case .liner: 0.85
        case .fly: 1.0
        case .pop: 0.5
        }
    }

    /// 弧の見た目に使う打ち出し角（度）。帯の中は線形に補間する（判定には使わない）。
    public static func angle(cursorDY dy: Double) -> Double {
        let w = bandWidth
        let clamped = min(max(dy, -1.5 * w), 2.5 * w)
        switch HomerunLaunch(cursorDY: clamped) {
        case .grounder: return 10 * (clamped + 1.5 * w) / w
        case .liner: return 10 + 15 * (clamped + w / 2) / w
        case .fly: return 25 + 10 * (clamped - w / 2) / w
        case .pop: return 35 + 20 * (clamped - 1.5 * w) / w
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
    /// 芯の半径（pt・ゾーンの 1/8）。帯の中心から数えて、ここで係数 0.8・これより外は当たり判定の外。
    public static let coreRadius = 11.0
    /// 柵の手前でこの距離（m）以内なら「フェンス直撃」。
    public static let fenceHitMargin = 6.0

    /// 柵の距離。両翼 100m・中堅 122m。
    public static func fence(atDirection degrees: Double) -> Double {
        100 + 22 * cos(2 * degrees * .pi / 180)
    }

    /// 芯の係数。`d` は「カーソルが入った角度の帯の中心」からカーソルまでの距離（pt）。
    /// 中心で 1.0・半径で 0.8（線形）・半径の外は 0（当たり判定の外 = 空振り）。
    /// 帯の中心から測るのは、帯の幅（22pt）が芯の直径と同じで、ボール中心から測ると柵越えの帯（少し下）が常に 0.8 以下になるため。
    public static func core(distanceFromBandCenter d: Double, abilities: HomerunAbilities = .standard) -> Double {
        let radius = coreRadius * max(abilities.meet, 0.01)
        if d > radius { return 0 }
        return 1 - 0.2 * d / radius
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
        let core = core(
            distanceFromBandCenter: hypot(swing.cursorDX, swing.cursorDY - launch.centerDY),
            abilities: abilities
        )
        guard timing != .miss, core > 0 else {
            return HomerunBattedBall(direction: 0, distance: 0, kind: .miss, timing: timing, launch: nil, fence: centerFence)
        }
        let direction = direction(swing)
        let fence = fence(atDirection: direction)
        if abs(direction) > foulLimit {
            return HomerunBattedBall(direction: direction, distance: 0, kind: .foul, timing: timing, launch: launch, fence: fence)
        }
        let distance = (timing.baseDistance + abilities.power) * launch.distanceFactor * core * abilities.bat
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
