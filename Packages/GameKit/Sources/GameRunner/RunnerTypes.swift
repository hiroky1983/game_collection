import Foundation

/// コースに置く障害の種類（#494）。
///
/// アクション枠の 2 本目。ブロック崩し（#463）と同じく **`SKPhysicsBody` は使わず**、
/// 当たり判定は純粋な値型で書く（`docs/action-game-foundation.md`）。
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
    /// 鳥。低い障害物と高い障害物の中間の高さ（会長QA「鳥とか右から車が来るとか要素はいる」）。
    ///
    /// **当たり判定・クリア可能性の数学は `lowBlock`/`tallBlock` と完全に同じ**
    /// （地面から生えていて、ジャンプで頂点付近を通せば越えられる、という既存モデルをそのまま使う）。
    case bird

    /// 地面からの高さ。穴は高さを持たない。
    ///
    /// 高さの上限は**ジャンプの頂点（`RunnerRules.jumpApex`）より十分低く**すること。
    /// 越えられない高さを置くとステージが詰む。`RunnerStageTests` が全ステージで機械的に確かめる。
    public var height: Double {
        switch self {
        case .pit:       return 0
        case .lowBlock:  return 5
        case .bird:      return 7
        case .tallBlock: return 9
        }
    }
}

/// コース上の障害 1 つ。座標はステージ先頭からのワールド座標（左が 0）。
public struct RunnerHazard: Equatable, Sendable {
    public let kind: RunnerHazardKind
    /// 左端の x。
    public let start: Double
    /// 長さ。レイアウトの連続した同じ文字がここでまとめられる。
    public let length: Double

    public init(kind: RunnerHazardKind, start: Double, length: Double) {
        self.kind = kind
        self.start = start
        self.length = length
    }

    /// 右端の x。
    public var end: Double { start + length }
    /// 上端の高さ（地面からの相対値）。穴は 0。
    public var height: Double { kind.height }
}

/// コース上のスピードアップアイテム 1 つ（会長QA「スピードアップアイテムor床とかあったほうがいい」）。
///
/// **`RunnerHazard` とは別の型**にしてある。穴・障害物は「触れると失敗する」当たり判定
/// （`isHittingBlock`/`isPit`）の対象だが、ピックアップは「触れると得する」だけで
/// 失敗ロジックには一切混ぜない。位置だけを持つ軽量な値。
public struct RunnerPickup: Equatable, Sendable {
    /// 中心の x（コース先頭からのワールド座標）。
    public let start: Double

    public init(start: Double) {
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

    /// このできごとでコースが終わるか（ミスかゴール）。
    public var isTerminal: Bool {
        switch self {
        case .fell, .crashed, .reachedGoal:                  return true
        case .landed, .passedCheckpoint, .collectedSpeedItem: return false
        }
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
