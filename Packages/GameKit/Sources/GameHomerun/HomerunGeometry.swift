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

    /// 1 球の種別の語。柵越えのうち場外（スタンドの最後列の後端を越えた・#1654）は「場外！」。
    public static func kind(of ball: HomerunBattedBall) -> String {
        ball.isOutOfPark ? "場外！" : kind(ball.kind)
    }

    /// 距離（m・整数に丸める）。
    public static func meters(_ distance: Double) -> String { "\(Int(distance.rounded())) m" }

    /// 1 球の内訳の方向の呼び名（空振り・ファウル・直撃はその語）。
    public static func place(_ ball: HomerunBattedBall) -> String {
        switch ball.kind {
        case .miss: "—"
        case .foul: "ファウル"
        case .fenceHit: "直撃"
        case .homer where ball.isOutOfPark: "場外"
        case .inPlay, .homer: HomerunSector(direction: ball.direction).label
        }
    }

    /// 1 球の結果の見出し（例「柵越え！ 128 m 左中間」）。
    public static func headline(_ ball: HomerunBattedBall) -> String {
        switch ball.kind {
        case .miss: "空振り"
        case .foul: "ファウル"
        case .inPlay, .fenceHit, .homer:
            "\(kind(of: ball)) \(meters(ball.distance)) \(HomerunSector(direction: ball.direction).label)"
        }
    }

    /// 1 球の読み上げ（VoiceOver）。
    public static func spoken(_ ball: HomerunBattedBall, number: Int) -> String {
        switch ball.kind {
        case .miss: "\(number)球目、空振り"
        case .foul: "\(number)球目、ファウル"
        case .inPlay, .fenceHit, .homer:
            "\(number)球目、\(kind(of: ball).replacingOccurrences(of: "！", with: ""))、\(Int(ball.distance.rounded()))メートル、\(HomerunSector(direction: ball.direction).label)、\(timing(ball.timing))"
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
    /// 扇の半径に取る距離（m）。最大飛距離（`HomerunJudge.bestDistance` = 180m）の★まで図の中に入れる（#1676）。
    /// 以前は 135m（の 1.1 倍 ≈ 148.5m で頭打ち）で、場外（中堅 ≈ 148.5m）より遠い★が扇の外に出て切れていた。
    public static let maxMeters = HomerunJudge.bestDistance

    /// 方向（度・0 が中堅・負が左）と距離（m）を、本塁から見た単位円の座標（右と下が正・1 = maxMeters）にする。
    /// `maxMeters` より遠い距離は扇の縁に置く。
    public static func point(direction: Double, distance: Double) -> CGPoint {
        let r = min(max(distance, 0), maxMeters) / maxMeters
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

    /// 描く枠（pt）の中での扇の置き方: 本塁の位置と、`maxMeters` を何 pt にするか。
    public struct Layout: Equatable, Sendable {
        public var home: CGPoint
        public var radius: CGFloat

        /// 単位円の座標（`point` / `mark`）を枠の中の座標にする。
        public func map(_ p: CGPoint) -> CGPoint { CGPoint(x: home.x + p.x * radius, y: home.y + p.y * radius) }
    }

    /// 枠 `size` に、扇（±45°・半径 `maxMeters`）が上・左右に `inset`、下に `bottom` の余白を残して収まる置き方。
    /// `inset` は★（18pt）と番号の札が縁で切れないための余白。
    public static func layout(in size: CGSize, inset: CGFloat, bottom: CGFloat = 6) -> Layout {
        let halfWidth = max(size.width / 2 - inset, 1)
        let radius = max(min(halfWidth / sin(.pi / 4), size.height - bottom - inset), 1)
        return Layout(home: CGPoint(x: size.width / 2, y: size.height - bottom), radius: radius)
    }

    /// 番号の札の置き場所の候補（印からのずれ・pt）。右上を先に試し、重なるなら次へ。
    static let labelOffsets: [CGVector] = [
        CGVector(dx: 10, dy: -9), CGVector(dx: -10, dy: -9), CGVector(dx: 10, dy: 9), CGVector(dx: -10, dy: 9),
        CGVector(dx: 0, dy: -17), CGVector(dx: 0, dy: 16), CGVector(dx: 17, dy: 0), CGVector(dx: -17, dy: 0),
    ]
    /// 番号の札の大きさ（pt・9pt の 2 桁がおさまる箱）。
    static let labelSize = CGSize(width: 13, height: 11)
    /// 印（★・●）が占める半径（pt）。札をここに重ねない。
    static let markRadius: CGFloat = 7

    /// 番号の札の中心（#1676）。印の位置 `marks`（枠の座標）の順に、ほかの札・ほかの印と重ならない最初の候補を選ぶ。
    /// どの候補も重なるときは重なりの最も少ないものにする（同じ所に何球落ちても札が完全には重ならない）。
    /// 描く枠 `bounds` からはみ出す候補は、枠内に収まる候補が 1 つでもあれば選ばない。
    public static func labelCenters(for marks: [CGPoint], in bounds: CGRect) -> [CGPoint] {
        var placed: [CGRect] = []
        // 自分の印は数えない（右上の札は★の縁に少し掛かるのが元からの見た目）。
        func markOverlap(_ rect: CGRect, _ own: Int) -> Int {
            marks.indices.filter { $0 != own && rect.insetBy(dx: -markRadius, dy: -markRadius).contains(marks[$0]) }.count
        }
        return marks.indices.map { index in
            let mark = marks[index]
            var best: (center: CGPoint, rect: CGRect, cost: Int)?
            for offset in labelOffsets {
                let center = CGPoint(x: mark.x + offset.dx, y: mark.y + offset.dy)
                let rect = CGRect(x: center.x - labelSize.width / 2, y: center.y - labelSize.height / 2,
                                  width: labelSize.width, height: labelSize.height)
                let outside = bounds.contains(rect) ? 0 : 100
                let cost = placed.filter { $0.intersects(rect) }.count * 2 + markOverlap(rect, index) + outside
                if best == nil || cost < best!.cost { best = (center, rect, cost) }
                if cost == 0 { break }
            }
            placed.append(best!.rect)
            return best!.center
        }
    }
}
