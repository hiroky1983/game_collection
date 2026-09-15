import Core
import Foundation

/// コースに置く障害の種類（#494）。
///
/// アクション枠の 2 本目。ブロック崩し（#463）と同じく **`SKPhysicsBody` は使わず**、
/// 当たり判定は純粋な値型で書く（`docs/action-game-foundation.md`）。
///
/// 岩・穴は置いた場所から動かない。鳥（#796）・犬（#800）・イノシシ（#801）は
/// **位置が走者の進み（距離）で決まる「動く障害」**で、いまの当たり判定は
/// `RunnerHazard.frame(atRunnerDistance:)` が返す（時計ではなく距離で決まるので、
/// 同じ操作からは常に同じ軌道になり、自動操縦のテストにそのまま乗る）。
public enum RunnerHazardKind: String, Codable, Equatable, Sendable, CaseIterable {
    /// 穴。**中心が穴の上にある状態で足が地面まで落ちる**とミスになる。
    ///
    /// 判定に使うのは矩形ではなく中心の x。矩形にすると、爪先が縁を越えた瞬間に落ちて
    /// 「まだ地面に乗っているのに落ちた」という理不尽な当たりになる。
    case pit
    /// 低い障害物。またぐ感覚で越えられる高さ。
    case lowBlock
    /// 高い障害物。ジャンプの頂点近くを通さないと当たる。
    case tallBlock
    /// 飛び立つ鳥（#796・会長決裁 2026-09-14「置物からどれかにしたい」）。
    ///
    /// #671 までは帯 13〜絵の頂点に浮いている置物で、走っていれば当たらず何もしなければ
    /// 安全——障害として機能していなかった。#796 で「地面に止まっていて、近づくと飛び立つ」
    /// 動く障害にしたが、飛び立ってからしばらく低い岩の高さを飛ぶ形だったため「跳ぶだけで
    /// 躱せる岩」と変わらなかった（#945 会長QA 2026-09-15）。いまは**跳んだ先にいる障害**:
    ///
    /// - 地面に止まっていて（帯の上端 `birdLowTop` = 5）、おじさんの前端が手前
    ///   `RunnerRules.birdTriggerDistance`（6 タイル）に入ると右上へ飛び立つ
    /// - 飛び立ってから `RunnerRules.birdClimbDistance`（1 タイル）進むあいだに、帯の下端が
    ///   **普通のジャンプの頂点**（`birdMeetBottom` = `RunnerRules.jumpApex` ≒ 14）まで
    ///   上がりきり、そのままの高さで飛び続ける。**走者が着く前に上がりきっている**
    ///   （上がりきるのは走者の前端が帯の 8 手前に来た時点）
    /// - 走者は**走ったまま下を抜ける**（接地した頭 11 の上に 3 の余裕）。**着いてから跳ぶと
    ///   頭が帯に入って当たる**——反射で跳ぶ人を罰する障害で、岩の逆
    /// - 早く跳びすぎると、速い面では降りてくるところに鳥がいて当たる（跳んだ先にいる）
    ///
    /// 動きは走者の距離で決まる（`RunnerHazard.frame(atRunnerDistance:)`）ので、走者と鳥の
    /// 相対軌道は 1 通りしか無く、同じ操作からは常に同じ結果になる（自動操縦のテストに乗る）。
    /// 「上を越える」は帯の上端（14 + `birdBandHeight`）が 1 段の頂点より高いので 1 段では
    /// できない。下を抜けるのが正解で、隣の障害との成立条件（`encounter`）もそれで書いてある。
    case bird
    /// 犬（#800 → #944）。**画面の左（走者の後ろ）から現れ、おじさんより速く右へ走り抜けて**
    /// 画面の外へ消える。
    ///
    /// 走者の手前 `RunnerRules.dogChaseDistance` で吠え声の手応え（`RunnerEvent.dogBarking`）を
    /// 出し、その瞬間に画面の外（後ろ）に現れて走者の `dogAdvance` 倍の速さで追ってくる
    /// （イノシシの「ドドド」と同じ作法で、向きが逆）。鼻先が走者の背中に触れる地点は区画の中央
    /// （`RunnerHazard.start`）で、高さは低い岩と同じ 5——跳べば足の下を抜けていく。
    /// `dogAdvance` = 2 なら相対速度は走者の速さそのもので、走者から見た等価な静止区間
    /// （`RunnerHazard.encounter`）は**置いた位置の低い岩と 1 単位も違わない**。だから
    /// 隣の障害との間隔は低い岩と同じ物差しで成立する。
    ///
    /// 立ち止まって吠える挙動（#800 の `dogStopGap`）は「前を走る犬がいつ止まるか」を読む
    /// 必要があって難しかったので廃止した（会長 QA 2026-09-15）。
    case dog
    /// イノシシ（#801）。**右から突進**してくる（犬の難しい版）。
    ///
    /// 走者の手前 `RunnerRules.boarChargeDistance` で「ドドド」の手応え（`RunnerEvent.boarCharging`）
    /// と土煙を出し、同じ距離だけ向こうから走者と同じ速さで向かってくる——相対速度は足し算で
    /// 2 倍、出会う地点は区画の中央（`RunnerHazard.start`）。高さは低い岩と同じ 5 で、跳べば越えられる。
    /// **岩にぶつかると止まる**（`RunnerHazard.stopAt`）: 出会う地点と出現点のあいだに岩があれば、
    /// その岩の右側で止まって低い岩と同じ置物になる（「岩の手前に置くと岩で止まる」読み）。
    case boar

    /// 当たり判定の**下端**（地面からの高さ）。地面から生えている障害は 0。
    ///
    /// 鳥は「地面に止まっているあいだ」の値（帯の厚みは絵の縦の寸法 `birdBandHeight`）。
    /// 走者の高さ 11 より低いが、走者が着く前に飛び立って上がりきる（`birdMeetBottom`）ので、
    /// 止まった鳥に触れることは無い。
    public var bottom: Double {
        switch self {
        case .pit, .lowBlock, .tallBlock, .dog, .boar: return 0
        case .bird:                                    return Self.birdLowTop - Self.birdBandHeight
        }
    }

    /// 当たり判定の**上端**（地面からの高さ）。穴は高さを持たない。
    ///
    /// **ジャンプの頂点（`RunnerRules.jumpApex`）より十分低く**すること。越えられない高さを置くと
    /// ステージが詰む。`RunnerStageTests` が全ステージで機械的に確かめる。
    /// 動く障害（犬・イノシシ）は**走者と出会うときの上端**。鳥だけは例外で、これは**止まっている
    /// あいだの上端**（低い岩と同じ 5）——走者と出会うときの帯は頭より上（`birdMeetBottom` から
    /// 上）にあり、跳んで越える相手ではなく下を抜ける相手なので「越える高さ」は無い。
    /// 自動操縦の踏み切りの余裕（`RunnerAutoPilot.lead`）と隣の障害との間隔（`encounter`）は
    /// この値を「岩と同じ物差し」として使う（上がりきった鳥に自動操縦が踏み切ることは無い——
    /// `RunnerField.nextHazard` が頭より上の帯を対象から外す）。
    public var height: Double {
        switch self {
        case .pit:               return 0
        case .lowBlock:          return 5
        case .tallBlock:         return 9
        case .bird, .dog, .boar: return Self.birdLowTop
        }
    }

    /// 地面を走る動物か（犬・イノシシ）。解析の死因（`missCause`）と絵の置き場の分岐に使う。
    public var isAnimal: Bool { self == .dog || self == .boar }

    /// 岩か（イノシシが止まる相手・#801）。
    public var isRock: Bool { self == .lowBlock || self == .tallBlock }

    /// この障害にやられたときの死因（`game_end` の `cause`・#796）。語彙は Core の enum に閉じる。
    public var missCause: AnalyticsEndCause {
        switch self {
        case .pit:                  return .pit
        case .lowBlock, .tallBlock: return .rock
        case .bird:                 return .bird
        case .dog, .boar:           return .animal
        }
    }

    /// 鳥が地面に止まっているあいだの帯の上端。**低い岩と同じ**（#796 の仕様「低い岩と同じ高さ（5）」）。
    public static var birdLowTop: Double { lowBlock.height }
    /// 走者と出会うときの帯の下端 = **普通のジャンプの頂点**（`RunnerRules.jumpApex` ≒ 14.06・#945）。
    ///
    /// 「跳んだ先にいる」をそのまま数にしたもの。接地した走者の頭（`RunnerField.Metrics.playerHeight`
    /// = 11）より 3 ほど上なので走ったまま下を抜けられ、着いてから跳ぶと頭が 0.05 秒で帯に入る。
    /// 帯の上端（+ `birdBandHeight`）は頂点より上なので、1 段のジャンプで上を越えることはできない。
    /// 鳥は飛び立ってから `RunnerRules.birdClimbDistance` でここまで上がり、以後はこの高さで飛ぶ。
    public static var birdMeetBottom: Double { RunnerRules.jumpApex }
    /// 鳥の帯の厚み。**絵（`RunnerBirdArt`）が縦に占める寸法に合わせて導出する**（#671）。
    ///
    /// 値を書き写さず計算させているのは、絵を描き替えたときに帯だけ古い値で取り残されるのを
    /// 防ぐため。**この一致は `BirdArtTests` が「絵の高さ == 帯の厚み」で固定する**。
    /// 1 度だけ評価する `static let` にしてあるのは、`frame(atRunnerDistance:)` が毎サブステップ
    /// 障害ごとに読むため（絵を組み直すコストをそこに持ち込まない）。
    static let birdBandHeight: Double = RunnerBirdArt(width: RunnerRules.tileWidth).bandHeight
}

/// 動く障害の**いまの当たり判定**（#796）。座標はワールド座標、高さは地面からの相対値。
public struct RunnerHazardFrame: Equatable, Sendable {
    /// 左端の x。
    public let start: Double
    /// 右端の x。
    public let end: Double
    /// 帯の下端。
    public let bottom: Double
    /// 帯の上端。
    public let top: Double
    /// 走者が 1 進むあいだにこの障害が動く量（右が正・静止は 0）。自動操縦が踏み切りの
    /// 余裕を「相対速度」で見積もるのに使う（`RunnerAutoPilot.lead`）。
    public let advance: Double

    public init(start: Double, end: Double, bottom: Double, top: Double, advance: Double) {
        self.start = start
        self.end = end
        self.bottom = bottom
        self.top = top
        self.advance = advance
    }
}

/// 動く障害を、**走者から見て等価な静止した障害**に読み替えたもの（#796）。
///
/// 相対軌道が距離で一意に決まるので、「走者の前端が初めて触れる地点」と「後端が抜ける地点」は
/// 静止した岩と同じく 1 つの区間 `[start, start + length]` に写せる（長さは負にもなる——
/// 向かってくるイノシシは走者の体の中を通り抜けるので、重なっている距離は体より短い）。
/// ステージの成立条件（`RunnerStageTests`）とエンドレスの生成（`RunnerEndlessCourse.canPlace`）は
/// この換算で岩と同じ式を使う。**実際の当たり判定（`frame`）と一致することは
/// `RunnerHazardMotionTests` が走査で確かめる。**
public struct RunnerHazardEncounter: Equatable, Sendable {
    public let start: Double
    public let length: Double
    /// 出会うときの上端。
    public let height: Double

    public var end: Double { start + length }
}

/// コース上の障害 1 つ。座標はステージ先頭からのワールド座標（左が 0）。
public struct RunnerHazard: Equatable, Sendable {
    public let kind: RunnerHazardKind
    /// 左端の x。動く障害では**走者と出会う地点**（鳥は止まっている位置、犬は鼻先が走者の背中に
    /// 触れる瞬間の走者の前端、イノシシは出現点と対称な出会いの地点）。区画の中央に置かれる
    /// （`RunnerStage.makeHazards`）。
    public let start: Double
    /// 長さ。レイアウトの連続した同じ文字がここでまとめられる。
    public let length: Double
    /// イノシシが止まる x（ぶつかる岩の右端・#801）。岩が無ければ nil。
    /// `RunnerStage.makeHazards` が岩の並びから決める（`RunnerStage.boarStop(for:among:)`）。
    public let stopAt: Double?

    public init(kind: RunnerHazardKind, start: Double, length: Double, stopAt: Double? = nil) {
        self.kind = kind
        self.start = start
        self.length = length
        self.stopAt = stopAt
    }

    /// 右端の x。
    public var end: Double { start + length }
    /// 下端の高さ（地面からの相対値）。地面から生えている障害は 0。
    public var bottom: Double { kind.bottom }
    /// 上端の高さ（地面からの相対値）。穴は 0。
    public var height: Double { kind.height }

    // MARK: 動く障害（#796 / #800 / #801）

    /// 鳥が飛び立つ瞬間の走者の距離（中心 x）。**前端**（`playerMaxX`）が手前 6 タイルに入った瞬間。
    public var birdTakeoffDistance: Double {
        start - RunnerRules.birdTriggerDistance - RunnerField.Metrics.playerHalfWidth
    }

    /// 鳥の飛行距離（飛び立ってから右へ進んだ量）。飛び立つ前は 0。
    public func birdTravel(atRunnerDistance distance: Double) -> Double {
        max(0, RunnerRules.birdAdvance * (distance - birdTakeoffDistance))
    }

    /// 犬の鼻先が走者の背中に触れる瞬間の走者の距離（#944）。走者の前端が `start` に入る瞬間で、
    /// 置いた位置の低い岩に前端が触れる瞬間と同じ。
    public var dogContactDistance: Double { start - RunnerField.Metrics.playerHalfWidth }
    /// 吠え声の予告（`RunnerEvent.dogBarking`）が出て犬が後ろに現れる走者の距離。
    /// 触れる瞬間の `RunnerRules.dogChaseDistance` 手前。
    public var dogBarkDistance: Double { dogContactDistance - RunnerRules.dogChaseDistance }
    /// 予告の瞬間に犬が現れる x（走者の後ろ・画面の外）。触れる瞬間に鼻先が走者の背中
    /// （`start − playerWidth`）に届くよう、走る量 `dogAdvance × dogChaseDistance` だけ手前。
    public var dogSpawn: Double {
        start - RunnerField.Metrics.playerWidth - length - RunnerRules.dogAdvance * RunnerRules.dogChaseDistance
    }

    /// 予告の手応え（#801 イノシシ・#944 犬）。現れる瞬間の走者の距離と、そのとき出すできごと。
    /// 予告の無い障害は nil。`RunnerField.step` がこの距離をまたいだサブステップで 1 回だけ出す。
    public var cue: (distance: Double, event: RunnerEvent)? {
        switch kind {
        case .pit, .lowBlock, .tallBlock, .bird: return nil
        case .dog:  return (dogBarkDistance, .dogBarking)
        case .boar: return (boarChargeStartDistance, .boarCharging)
        }
    }

    /// イノシシの予告（手応え・土煙）が出て突進が始まる走者の距離。
    /// 前端が出会いの地点 `start` の `boarChargeDistance` 手前に入った瞬間。
    public var boarChargeStartDistance: Double {
        start - RunnerRules.boarChargeDistance - RunnerField.Metrics.playerHalfWidth
    }
    /// イノシシの出現点。出会いの地点と対称。
    public var boarSpawn: Double { start + RunnerRules.boarChargeDistance }

    /// 走者の中心が `distance` にあるときの当たり判定。**まだ現れていない**障害（突進前の
    /// イノシシ）は nil。岩・穴は常に置いた場所そのもの。
    public func frame(atRunnerDistance distance: Double) -> RunnerHazardFrame? {
        switch kind {
        case .pit, .lowBlock, .tallBlock:
            return RunnerHazardFrame(start: start, end: end, bottom: bottom, top: height, advance: 0)
        case .bird:
            let travel = birdTravel(atRunnerDistance: distance)
            // 飛び立った瞬間から一定の傾きで上がり、`birdClimbDistance` 進んだところで帯の下端が
            // 跳んだ先の高さ（`birdMeetBottom`）に届く。そこから先は同じ高さで飛び続ける
            // （走者が下を抜けて追い越すので、鳥は後ろへ置き去りになって画面の左へ消える・#945）。
            let climb = min(travel, RunnerRules.birdClimbDistance) * RunnerRules.birdClimbSlope
            let bandBottom = bottom + climb
            return RunnerHazardFrame(
                start: start + travel, end: end + travel,
                bottom: bandBottom, top: bandBottom + RunnerHazardKind.birdBandHeight,
                advance: travel > 0 ? RunnerRules.birdAdvance : 0
            )
        case .dog:
            // 予告の瞬間に後ろに現れ、以後は止まらず右へ走り続ける（画面の外へ抜けても消さない
            // ——走者より速いので二度と追いつけず、当たり判定として効くことはない）。
            guard distance >= dogBarkDistance else { return nil }
            let x = dogSpawn + RunnerRules.dogAdvance * (distance - dogBarkDistance)
            return RunnerHazardFrame(
                start: x, end: x + length, bottom: 0, top: height, advance: RunnerRules.dogAdvance
            )
        case .boar:
            guard distance >= boarChargeStartDistance else { return nil }
            let charging = boarSpawn - RunnerRules.boarAdvance * (distance - boarChargeStartDistance)
            // 岩にぶつかったらそこで止まる（岩の右側に並ぶ）。
            if let stopAt, charging <= stopAt {
                return RunnerHazardFrame(start: stopAt, end: stopAt + length, bottom: 0, top: height, advance: 0)
            }
            return RunnerHazardFrame(
                start: charging, end: charging + length, bottom: 0, top: height,
                advance: -RunnerRules.boarAdvance
            )
        }
    }

    /// 走者から見て等価な静止した障害（`RunnerHazardEncounter` を参照）。
    ///
    /// 走者の前端が動く障害に初めて触れる地点を `start`、後端が抜ける地点から逆算した長さを
    /// `length` にする。速さ `a`（右が正）で動く幅 `w` の障害と幅 `p` の走者が重なっている
    /// 走者の進みは `(w + p) / (1 - a)` なので、等価な静止した長さは `(w + p) / (1 - a) - p`。
    ///
    /// 鳥（#945）は**横に重なる区間**そのもの。帯は頭より上（`RunnerHazardKind.birdMeetBottom`）
    /// にあるので接地していれば当たらず、跳んでいるあいだだけ当たる——つまりこの区間は
    /// 「跳んでいてはいけない区間」で、隣の障害を跳んだ着地がこの手前で終わり、次の踏み切りが
    /// この先で始まることを、岩と同じ間隔の式（`RunnerStageTests.hazardsAreFarEnoughApart` /
    /// `RunnerEndlessCourse.hasLandingGap`）がそのまま保証する。`height` は止まっている
    /// あいだの 5（`RunnerHazardKind.height` を参照）。
    public var encounter: RunnerHazardEncounter {
        let playerWidth = RunnerField.Metrics.playerWidth
        switch kind {
        case .pit, .lowBlock, .tallBlock:
            return RunnerHazardEncounter(start: start, length: length, height: height)
        case .dog:
            // 後ろから `k` (> 1) で追い越す相手（#944）。鼻先が背中に触れるのは前端が `start` に
            // 入る瞬間（`dogContactDistance`）で、そこから相対速度 `k − 1` で体を通り抜ける。
            // `k` = 2 なら `(4 + 8) / 1 − 8` = 4 で、置いた位置の低い岩と同じ区間になる。
            let k = RunnerRules.dogAdvance
            return RunnerHazardEncounter(
                start: start,
                length: (length + playerWidth) / (k - 1) - playerWidth,
                height: height
            )
        case .bird:
            // 前端が触れるとき、鳥は飛び立ってから `k·G/(1−k)` だけ進んでいる（`birdTakeoffDistance` で
            // 前端は `start − G` にあり、そこから相対速度 `1 − k` で `G` を詰める）。
            let k = RunnerRules.birdAdvance
            let shift = k * RunnerRules.birdTriggerDistance / (1 - k)
            return RunnerHazardEncounter(
                start: start + shift,
                length: (length + playerWidth) / (1 - k) - playerWidth,
                height: height
            )
        case .boar:
            if let stopAt {
                return RunnerHazardEncounter(start: stopAt, length: length, height: height)
            }
            let k = RunnerRules.boarAdvance
            return RunnerHazardEncounter(
                start: start,
                length: (length + playerWidth) / (1 + k) - playerWidth,
                height: height
            )
        }
    }

    /// この障害が走者に関わる距離の範囲（走者の中心 x）。チェックポイントはこの外に置く
    /// （#796: 動く障害の途中——飛び立つ最中・突進の予告中——から再開させない）。
    public var activeRange: ClosedRange<Double> {
        let half = RunnerField.Metrics.playerHalfWidth
        switch kind {
        case .pit, .lowBlock, .tallBlock:
            return (start - half)...(end + half)
        case .bird:
            // 羽ばたきの予備動作から、後端が抜けるまで。
            return (birdTakeoffDistance - RunnerRules.birdFlutterDistance)...(encounter.end + half)
        case .dog:
            // 予告から、追い越されて後端が抜けるまで。抜けたあとの犬は前方を走り去るだけで
            // 追いつけないので、その先から再開しても差し支えない。
            return dogBarkDistance...(encounter.end + half)
        case .boar:
            return boarChargeStartDistance...(max(encounter.end, boarSpawn) + half)
        }
    }

    /// 自動操縦が**前方の踏み切りの相手**として見る当たり判定（`RunnerField.nextHazard`）。
    ///
    /// 後ろから追い越す犬（#944）だけは `frame(atRunnerDistance:)` と違う。いまの位置が走者の
    /// 後ろにあって「前方の間合い」では測れないが、相対軌道は距離で一意なので、走者から見れば
    /// 置いた位置に静止した低い岩（`encounter`）と同じ——その静止した区間を前方の相手として返す。
    /// 踏み切り地点は相対速度で見積もった場合と同じになる（`RunnerHazardMotionTests`）。
    /// 現れる前（予告の前）は nil。ほかの障害はいまの当たり判定そのもの。
    public func targetFrame(atRunnerDistance distance: Double) -> RunnerHazardFrame? {
        guard let frame = frame(atRunnerDistance: distance) else { return nil }
        guard kind == .dog else { return frame }
        let encounter = encounter
        return RunnerHazardFrame(
            start: encounter.start, end: encounter.end, bottom: bottom, top: encounter.height, advance: 0
        )
    }
}

/// 取ると得するアイテムの種類（#797 で 2 種類目を足した）。
public enum RunnerPickupKind: String, Codable, Equatable, Sendable, CaseIterable {
    /// スピードアップ（稲妻・区画記号 `s`）。取った瞬間から一定時間、上限を超えて加速する。
    case speed
    /// たこ焼き（区画記号 `k`・#797）。取ってから `RunnerRules.invincibleDuration` 秒のあいだ
    /// **岩・鳥・台座の正面に当たってもミスにならない**。穴は従来どおり落ちる——無敵は
    /// 「ぶつかっても平気」であって「飛べる」ではない。
    case invincible
}

/// コース上のアイテム 1 つ（会長QA「スピードアップアイテムor床とかあったほうがいい」・#797）。
///
/// **`RunnerHazard` とは別の型**にしてある。穴・障害物は「触れると失敗する」当たり判定
/// （`isHittingBlock`/`isPit`）の対象だが、ピックアップは「触れると得する」だけで
/// 失敗ロジックには一切混ぜない。種類と位置だけを持つ軽量な値。
public struct RunnerPickup: Equatable, Sendable {
    public let kind: RunnerPickupKind
    /// 中心の x（コース先頭からのワールド座標）。
    public let start: Double

    public init(kind: RunnerPickupKind, start: Double) {
        self.kind = kind
        self.start = start
    }
}

/// コース上の「乗れる台座」1 つ（#674）。歩道橋・工事の足場・バスの屋根のような、
/// 街の中の高い場所。
///
/// **`RunnerHazard` とは別の型・別の配列**にしてある。障害は「越えるもの」で当たり判定が
/// 失敗に直結するが、台座は「上に乗って走るもの」で、地面と同じ**接地面**として働く
/// （`RunnerField.surfaceY(at:)`）。同じ配列に混ぜると、既存の成立条件チェック
/// （`RunnerStageTests` の「すべての障害が越えられる」）が台座まで「越えるべきもの」として
/// 巻き込んでしまう——台座は越えるのではなく乗るので、その判定は意味を成さない。
///
/// 高低差を**地面の高さを動かさずに**作るための型（#635 会長決裁 2026-09-12）。
/// `RunnerField.Metrics.groundY` は接地判定・障害の高さ・カメラ・自動操縦・テストの
/// 物差しがすべて前提にしている全体でただ 1 つの定数なので、そこを可変にすると全部が
/// 連鎖する。台座は「地面の上に置く物体」なのでその前提を一切壊さない。
public struct RunnerPlatform: Equatable, Sendable {
    /// 左端の x（コース先頭からのワールド座標）。
    public let start: Double
    /// 長さ。レイアウトの連続した `P` がここでまとめられる。
    public let length: Double
    /// 上面の高さ（**地面からの相対値**。障害の `height` と同じ物差し）。
    ///
    /// 第 1 弾は 1 種類（`RunnerRules.platformHeight` = 8）だけ。値を型に持たせてあるのは、
    /// 接地面の解決（`RunnerField.surfaceY(at:)`）を「覆っている台座のうち最も高い上面」で
    /// 書けるようにするため——高さ違いの台座を足す日が来ても、重ねた段の解決はそのまま動く。
    public let top: Double

    public init(start: Double, length: Double, top: Double = RunnerRules.platformHeight) {
        self.start = start
        self.length = length
        self.top = top
    }

    /// 右端の x。
    public var end: Double { start + length }
}

/// コース上のスピードアップ床 1 区間（#672。#635 で会長決裁）。
///
/// アイテム（`RunnerPickup`）が「空中で取る一過性のご褒美」なのに対し、床は
/// **乗っているあいだだけずっと効く地面の区間**。区間から出れば即座に効果が切れるので、
/// `RunnerField` は状態を持たず毎サブステップ位置から判定する（`isOnBoostFloor`）。
///
/// `RunnerHazard` とも `RunnerPickup` とも別の型にしてある。床は「触れると失敗する」
/// 当たり判定（`isHittingBlock`/`isPit`）にも、ステージの成立条件チェック
/// （`RunnerStageTests` の間隔・跳べる高さ）にも一切混ぜない——障害としては平地そのもの。
public struct RunnerBoostFloor: Equatable, Sendable {
    /// 左端の x（コース先頭からのワールド座標）。
    public let start: Double
    /// 長さ。レイアウトの連続した `=` がここでまとめられる。
    public let length: Double

    public init(start: Double, length: Double) {
        self.start = start
        self.length = length
    }

    /// 右端の x。
    public var end: Double { start + length }
}

/// 1 サブステップで起きたできごと。Model がこれを見て進行・記録・音を動かす。
///
/// `RunnerField` は状態を進めるだけで、ステージ番号もタイムも記録も知らない
/// （アクション枠の基盤規約・#463 と同じ層の分け方）。
public enum RunnerEvent: Equatable, Sendable {
    /// 着地した（ジャンプから地面へ戻った）。
    case landed
    /// チェックポイントを通過した。
    case passedCheckpoint
    /// 穴に落ちた。
    case fell
    /// 障害物にぶつかった。
    case crashed
    /// ゴールに到達した。
    case reachedGoal
    /// スピードアップアイテムを取った。決着ではないので `isTerminal` は false。
    case collectedSpeedItem
    /// たこ焼き（#797）を取った。以後 `RunnerField.isInvincible` が一定時間 true になる。
    case collectedInvincibleItem
    /// イノシシの突進が始まった（#801）。土煙と「ドドド」の手応えの発火点。決着ではない。
    case boarCharging
    /// 犬が後ろで吠えた（#944）。左（走者の後ろ）から追い越しにくる予告の手応えの発火点。
    /// 決着ではない。
    case dogBarking

    /// このできごとでコースが終わるか（ミスかゴール）。
    public var isTerminal: Bool {
        switch self {
        case .fell, .crashed, .reachedGoal:
            return true
        case .landed, .passedCheckpoint, .collectedSpeedItem, .collectedInvincibleItem, .boarCharging, .dogBarking:
            return false
        }
    }
}

/// 遊び方のモード（#675）。**開始時に `RunnerModel` へ焼き込み、走行中に読み替えない**
/// （`docs/ai-devops.md`「1局=1RuleSet」。麻雀の `MahjongGameLength` と同じ形）。
///
/// ステージ制は v1.1.4 までと 1 ビットも変わらない現行ルール。エンドレスはランダム生成の
/// コース（`RunnerEndlessCourse`）を**ミスするまで走って距離を競う**1 回完結のモードで、
/// チェックポイントも中断保存も持たない（会長決裁 2026-09-12）。
public enum RunnerMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// 18 ステージを順にクリアしていく現行ルール。
    case stages
    /// 走行距離を競うエンドレス（#675）。
    case endless

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .stages:  return "ステージ"
        case .endless: return "エンドレス"
        }
    }

    /// 開始シートに出す 1 行の説明。
    public var summary: String {
        switch self {
        case .stages:  return "ステージ 1 から 18 面を順にクリアして、3 つの世界を先へ進む、いつもの遊び方"
        case .endless: return "毎回ちがうコースをミスするまで走って、走行距離を競う。途中で閉じると記録は残りません"
        }
    }

    /// 解析イベント `game_start` / `game_end` の `mode`（#783 で入った枠）。
    ///
    /// ステージ制は `level: .stage(n)` をそのまま持ち、`mode` で「どの遊び方か」だけを分ける。
    public var analyticsMode: AnalyticsMode {
        switch self {
        case .stages:  return .stage
        case .endless: return .endless
        }
    }

    /// 自己ベスト・通算成績を分けて数えるための区分キー（`GameScore.variant`）。
    ///
    /// ステージ制は **nil のまま**にする。ここに文字列を入れると記録の保存先が `runner` から
    /// `runner#stages` に変わり、これまでの到達ステージの記録がどこからも参照されなくなる
    /// （麻雀の `MahjongGameLength.recordVariant` と同じ理由）。
    public var recordVariant: String? {
        self == .stages ? nil : rawValue
    }

    /// ハブ・リザルトの記録行に添える区分名。ステージ制は従来どおり添えない。
    public var recordVariantLabel: String? {
        self == .stages ? nil : title
    }
}

/// ゲームの進行状態。
public enum RunnerPhase: Equatable, Sendable {
    /// スタート前。タップで走り出す。
    case ready
    /// 走っている。
    case running
    /// 一時停止中。アクセシビリティ要件「いつでも一時停止できる」の実体。
    case paused
    /// 穴に落ちた/ぶつかった直後の短い演出中（会長QA「落ちるアニメーションがある方がいい」）。
    ///
    /// タップ・一時停止は効かず、`RunnerRules.fallDuration` 秒で自動的に `.failed` へ移る。
    case falling
    /// ミスした。リトライ（無料・無制限）か、チェックポイント再開（リワード広告・1 ステージ 1 回）を選ぶ。
    case failed
    /// ステージクリア（まだ次のステージが残っている）。
    case cleared
    /// 最終ステージまでクリアした。
    case allCleared

    /// 走っていて `tick` を進めるべき状態か。
    public var isRunning: Bool { self == .running }
}
