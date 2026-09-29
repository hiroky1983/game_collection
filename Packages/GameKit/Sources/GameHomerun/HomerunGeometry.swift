import Foundation
import HomerunCore

/// 打席の HUD の寸法（README §3.1）。判定の単位（pt）と画面の pt を同じにするため、**端末の広さで拡縮しない**
/// （帯の幅 22pt・芯の半径 11pt はゾーンの 1/4・1/8 で決まっている）。
public enum HomerunZoneGeometry {
    /// ストライクゾーン（9 分割）の一辺。帯の幅（`HomerunLaunch.bandWidth`）がこの 1/4。
    public static let zoneSize = HomerunLaunch.bandWidth * 4
    public static var cellSize: Double { zoneSize / 3 }
    /// 的（白い細い輪）の直径と線の太さ。
    public static let targetDiameter = 46.0
    public static let targetLineWidth = 1.0
    /// 縮む輪（コーラル）の直径（投球の開始時）と線の太さ。
    public static let ringStartDiameter = 118.0
    public static let ringLineWidth = 5.0
    /// カーソルが動ける範囲（ゾーン中心から・pt）。ゾーンの外へ 1 帯ぶんまで。
    public static var cursorLimit: Double { zoneSize / 2 + HomerunLaunch.bandWidth * 1.5 }

    /// 9 分割のゾーン（0 = 左上 … 8 = 右下）のボールの位置（ゾーン中心から・右と下が正）。
    public static func ballPoint(zone: Int) -> CGPoint {
        let z = min(max(zone, 0), 8)
        return CGPoint(x: Double(z % 3 - 1) * cellSize, y: Double(z / 3 - 1) * cellSize)
    }

    public static func clampCursor(_ p: CGPoint) -> CGPoint {
        let l = cursorLimit
        return CGPoint(x: min(max(p.x, -l), l), y: min(max(p.y, -l), l))
    }

    /// 縮む輪の直径。`elapsed` は投球開始（的が出た時刻）からの秒。1.2 秒で的と同じ大きさになり、
    /// そのまま同じ速さ（半径 0.03pt/ms）で縮み続ける（遅く離したときは的の内側に見える）。
    public static func ringDiameter(elapsed: TimeInterval) -> Double {
        let travel = Double(HomerunPitch.travelMilliseconds) / 1000
        let t = max(elapsed, 0)
        return max(ringStartDiameter - (ringStartDiameter - targetDiameter) * t / travel, 8)
    }
}

/// 照準の吸い寄せ（#1594 試作）。投球中に押している間、照準（`HomerunModel.aimCursor`）がボールの方へ少しずつ寄る。
/// 寄る割合は押し始め（的が出る前から押していれば的が出た瞬間）からの時間で `rampSeconds` かけて 0 → `maxPull` に増える
/// （1 = ボールの中心まで）。指でずらした分はそのまま効き、寄せはその上に掛かる。値は会長 QA で詰める。
public struct HomerunAimAssist: Equatable, Sendable {
    /// 最終的に詰める割合（0〜1）。
    public var maxPull: Double
    /// `maxPull` に届くまでの時間（秒）。
    public var rampSeconds: TimeInterval

    public init(maxPull: Double, rampSeconds: TimeInterval) {
        self.maxPull = maxPull
        self.rampSeconds = rampSeconds
    }

    /// 既定: 的が出てから 1.0 秒（輪が重なる 0.2 秒前）で距離の半分まで寄る。
    public static let standard = HomerunAimAssist(maxPull: 0.5, rampSeconds: 1.0)
    /// 寄せない（指で動かした位置のまま）。
    public static let off = HomerunAimAssist(maxPull: 0, rampSeconds: 1)

    /// 押し続けて `held` 秒たったときの寄せる割合。
    public func pull(heldFor held: TimeInterval) -> Double {
        guard maxPull > 0, held > 0 else { return 0 }
        return maxPull * min(held / max(rampSeconds, 0.001), 1)
    }
}

/// Reduce Motion のときの的の色（輪を縮める代わり・README §3.1）。
public enum HomerunTargetCue: Equatable, Sendable {
    /// まだ遠い（白）。
    case far
    /// 近い（黄）: 当たり窓の手前 300ms から。
    case near
    /// 今（コーラル）: 当たり窓の中。
    case now

    /// `offset`: 離したときのタイミングのずれ（ミリ秒・負が早い）。
    public init(offsetMilliseconds offset: Double) {
        if abs(offset) <= HomerunTiming.hitWindow { self = .now }
        else if offset < 0, offset >= -(HomerunTiming.hitWindow + 300) { self = .near }
        else { self = .far }
    }
}

/// 画面に出す言葉（ミリ秒・角度は見せない。README §3.1）。
public enum HomerunText {
    /// 空振りの理由（#1594・短く）。
    public static func missReason(_ reason: HomerunMissReason) -> String {
        switch reason {
        case .early: "振るのが早い"
        case .late: "振るのが遅い"
        case .aim: "照準がずれた"
        }
    }

    public static func timing(_ timing: HomerunTiming) -> String {
        switch timing {
        case .just: "ジャスト"
        case .nice: "ナイス"
        case .hit: "当たり"
        case .miss: "空振り"
        }
    }

    public static func kind(_ kind: HomerunKind) -> String {
        switch kind {
        case .miss: "空振り"
        case .foul: "ファウル"
        // スプレーチャートの凡例（★ 柵越え・● 当たり・● 直撃）と同じ語（README §3.3）。
        case .inPlay: "当たり"
        case .fenceHit: "直撃！"
        case .homer: "柵越え！"
        }
    }

    /// 距離（m・整数に丸める）。
    public static func meters(_ distance: Double) -> String { "\(Int(distance.rounded())) m" }

    /// 1 球の内訳の方向の呼び名（空振り・ファウル・直撃はその語）。
    public static func place(_ ball: HomerunBattedBall) -> String {
        switch ball.kind {
        case .miss: "—"
        case .foul: "ファウル"
        case .fenceHit: "直撃"
        case .inPlay, .homer: HomerunSector(direction: ball.direction).label
        }
    }

    /// 1 球の結果の見出し（例「柵越え！ 128 m 左中間」）。
    public static func headline(_ ball: HomerunBattedBall) -> String {
        switch ball.kind {
        case .miss: "空振り"
        case .foul: "ファウル"
        case .inPlay, .fenceHit, .homer:
            "\(kind(ball.kind)) \(meters(ball.distance)) \(HomerunSector(direction: ball.direction).label)"
        }
    }

    /// 1 球の読み上げ（VoiceOver）。
    public static func spoken(_ ball: HomerunBattedBall, number: Int) -> String {
        switch ball.kind {
        case .miss: "\(number)球目、空振り"
        case .foul: "\(number)球目、ファウル"
        case .inPlay, .fenceHit, .homer:
            "\(number)球目、\(kind(ball.kind).replacingOccurrences(of: "！", with: ""))、\(Int(ball.distance.rounded()))メートル、\(HomerunSector(direction: ball.direction).label)、\(timing(ball.timing))"
        }
    }

    /// 結果の一言（「左 4 ／ 中 2 ／ 右 2 ／ ファウル 1 ／ 空振り 1」）。
    public static func spraySummary(_ balls: [HomerunBattedBall]) -> String {
        let fair = balls.filter { $0.kind != .miss && $0.kind != .foul }
        let left = fair.filter { $0.direction < -7 }.count
        let right = fair.filter { $0.direction > 7 }.count
        let center = fair.count - left - right
        let fouls = balls.filter { $0.kind == .foul }.count
        let misses = balls.filter { $0.kind == .miss }.count
        return "左 \(left) ／ 中 \(center) ／ 右 \(right) ／ ファウル \(fouls) ／ 空振り \(misses)"
    }
}

/// スプレーチャート（上から見た扇）の座標。本塁が原点、中堅が上。
public enum HomerunSprayGeometry {
    /// 扇の半径に取る距離（m）。中堅の柵（122m）より少し外まで描く。
    public static let maxMeters = 135.0

    /// 方向（度・0 が中堅・負が左）と距離（m）を、本塁から見た単位円の座標（右と下が正・1 = maxMeters）にする。
    public static func point(direction: Double, distance: Double) -> CGPoint {
        let r = min(max(distance, 0), maxMeters * 1.1) / maxMeters
        let rad = direction * .pi / 180
        return CGPoint(x: r * sin(rad), y: -r * cos(rad))
    }

    /// 1 球をチャートのどこに置くか。空振りは本塁、ファウルは向いた側のファウルラインの外（距離 0 なので 40m 地点）。
    public static func mark(for ball: HomerunBattedBall) -> CGPoint {
        switch ball.kind {
        case .miss: return .zero
        case .foul: return point(direction: ball.direction < 0 ? -52 : 52, distance: 40)
        case .inPlay, .fenceHit, .homer: return point(direction: ball.direction, distance: ball.distance)
        }
    }
}
