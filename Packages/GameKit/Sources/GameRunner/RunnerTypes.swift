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
    /// 鳥（会長QA「鳥とか右から車が来るとか要素はいる」）。
    ///
    /// **岩と違い、地面から生えていない「帯」の障害**（#671・#635 で会長決裁 2026-09-12）。
    /// 判定は `bottom`（13）から `height`（≒ 17.34 = 絵の頂点・`birdBandTop`）までの
    /// 空中の帯で、地面との間は空いている:
    ///
    /// - **接地していれば安全**（走者の高さ 11 < 13 なので頭がつかえずくぐれる）
    /// - **跳ぶと当たる**（最小のジャンプでも頂点は `RunnerRules.jumpApex` ≒ 14.06 まで上がり、
    ///   高さ 2 を超えた時点で頭が帯へ入る。単発では足が上端を越えられないので抜けられない）
    /// - **2 段ジャンプなら上を抜けられる**（足が上端より上にいるあいだは安全）
    ///
    /// つまり岩・穴が「跳んで越える」障害なのに対し、鳥は**跳ばずにくぐる**障害で、
    /// 「跳ぶか跳ばないか」の判断そのものを問う。高さ 7 の“低い岩”のままでは
    /// 「地に足ついてるから岩と変わらない」（会長QA 2026-09-10）が再発する。
    /// ジャンプ物理は一切変えていない（#635 決裁）ので、15 ステージの他の成立条件は
    /// そのまま据え置ける。
    case bird

    /// 当たり判定の**下端**（地面からの高さ）。地面から生えている障害は 0。
    ///
    /// 0 でないのは鳥だけで、`RunnerField.isHittingBlock` はこの値のおかげで
    /// 「岩は従来どおりの高さ判定・鳥だけ帯判定」を 1 本の式で書ける。
    public var bottom: Double {
        switch self {
        case .pit, .lowBlock, .tallBlock: return 0
        // 走者の高さ（`RunnerField.Metrics.playerHeight` = 11）より高くしないと、
        // 接地したままでは絶対にくぐれない障害になる。
        case .bird:                       return 13
        }
    }

    /// 当たり判定の**上端**（地面からの高さ）。穴は高さを持たない。
    ///
    /// 地面から生えている障害（`bottom` が 0）の上端は**ジャンプの頂点
    /// （`RunnerRules.jumpApex`）より十分低く**すること。越えられない高さを置くと
    /// ステージが詰む。`RunnerStageTests` が全ステージで機械的に確かめる。
    /// 鳥だけは「跳ばずにくぐる」障害なのでこの上限が効かず、**絵の頂点**（`birdBandTop`）に
    /// 合わせてある。
    public var height: Double {
        switch self {
        case .pit:       return 0
        case .lowBlock:  return 5
        case .tallBlock: return 9
        case .bird:      return Self.birdBandTop
        }
    }

    /// 鳥の帯の上端。**絵（`RunnerBirdArt`）が縦に占める寸法に合わせて導出する**
    /// （#671・会長決裁 2026-09-12）。
    ///
    /// #622 D案の決裁値は 22 だったが、幅 1 タイルの鳥は縦横比の都合で 4.34 しか埋められず、
    /// **絵より 4.66 単位上まで見えない即死の帯**が残っていた。「見えている鳥を跳び越したのに
    /// 当たる」は #609 で潰したはずの理不尽なので、上端を絵に合わせて下げた。
    ///
    /// **本質は下端（`bottom` = 13）**——接地ならくぐれる／跳べば当たる、という #622 D案の
    /// 設計はそこで決まっており、1 ミリも動かしていない（単発ジャンプの頂点 14.06 では
    /// 足が上端を越えられないので、跳べば必ず当たる）。2 段ジャンプで上を抜けられる余裕が
    /// 広がるのは意図した結果で、上手い人の抜け道として残す。
    ///
    /// 値を書き写さず計算させているのは、絵を描き替えたときに帯だけ古い値で取り残されるのを
    /// 防ぐため。**この一致は `BirdArtTests` が「絵の上端 == 帯の上端」で固定する**。
    /// 1 度だけ評価する `static let` にしてあるのは、`isHittingBlock` が毎サブステップ
    /// 障害ごとに `height` を読むため（絵を組み直すコストをそこに持ち込まない）。
    static let birdBandTop: Double = bird.bottom
        + RunnerBirdArt(width: RunnerRules.tileWidth).bandHeight
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
    /// 下端の高さ（地面からの相対値）。地面から生えている障害は 0、鳥だけ 13。
    public var bottom: Double { kind.bottom }
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
