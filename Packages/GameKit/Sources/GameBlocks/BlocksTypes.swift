import Foundation

/// ブロックの種類（#463）。
///
/// Issue の「最小構成でよい」に従い 3 種だけ持つ。パワーアップ・特殊ブロックはここに足すのではなく、
/// 別 Issue で `BlockKind` を増やす形になる（耐久と得点はこの enum に閉じている）。
public enum BlockKind: String, Codable, Equatable, Sendable, CaseIterable {
    /// 1 回当てると壊れる。
    case normal
    /// 2 回当てないと壊れない。
    case hard
    /// 壊れない障害物。ステージクリアの条件には数えない。
    case solid

    /// 初期耐久。壊れないブロックは nil。
    public var hitPoints: Int? {
        switch self {
        case .normal: return 1
        case .hard:   return 2
        case .solid:  return nil
        }
    }

    /// ステージ定義の 1 文字表現。`BlocksStage` のレイアウト文字列が使う。
    public var symbol: Character {
        switch self {
        case .normal: return "n"
        case .hard:   return "h"
        case .solid:  return "s"
        }
    }

    /// レイアウト文字列の 1 文字から。空きマス（"."）と未知の文字は nil。
    public static func from(symbol: Character) -> BlockKind? {
        allCases.first { $0.symbol == symbol }
    }
}

/// 盤上の 1 ブロック。
public struct Block: Equatable, Sendable {
    public let kind: BlockKind
    /// 残り耐久。壊れないブロック（`solid`）は常に nil で、何回当ててもこの値は変わらない。
    public private(set) var remaining: Int?

    public init(kind: BlockKind) {
        self.kind = kind
        self.remaining = kind.hitPoints
    }

    /// 壊せるブロックか。ステージクリアの判定はこれが true のものだけを数える。
    public var isBreakable: Bool { remaining != nil }

    /// 1 回当たったあとの姿。壊れたときは nil を返す。
    ///
    /// **得点はここでは決めない**（`BlocksScoring` が持つ）。耐久と得点を同じ場所に置くと、
    /// ステージ倍率のようなゲーム進行側の都合がブロックの定義に混ざる。
    public func damaged() -> (block: Block?, destroyed: Bool) {
        guard let remaining else { return (self, false) }  // solid は無傷
        let next = remaining - 1
        if next <= 0 { return (nil, true) }
        var copy = self
        copy.remaining = next
        return (copy, false)
    }
}

/// 1 サブステップで起きたできごと。Model がこれを見て得点・残機・音を動かす。
///
/// **Field は状態を進めるだけで、得点も残機も知らない**。ゲームの進行はすべて Model 側にあり、
/// この enum が両者の唯一の接点になる（アクション枠の基盤規約・#463）。
public enum BlocksEvent: Equatable, Sendable {
    /// 壁（左右・天井）で跳ね返った。
    case wallBounce
    /// パドルで跳ね返った。
    case paddleBounce
    /// ブロックに当たった。`destroyed` が true ならこの一撃で壊れた。
    case blockHit(row: Int, column: Int, kind: BlockKind, destroyed: Bool)
    /// 球が床へ落ちた（1 機失う）。
    case ballLost
}

/// ゲームの進行状態。
public enum BlocksPhase: Equatable, Sendable {
    /// 球がパドルの上で待機している。タップ / ドラッグ開始で発射する。
    case ready
    /// 球が動いている。
    case playing
    /// 一時停止中。アクセシビリティ要件「いつでも一時停止できる」の実体。
    case paused
    /// ステージクリア（まだ次のステージが残っている）。
    case stageCleared
    /// 残機を使い切った。コンティニュー（リワード広告）を選べる。
    case gameOver
    /// 最終ステージまでクリアした。
    case allCleared

    /// 決着してこれ以上進まない状態か。
    public var isFinished: Bool { self == .gameOver || self == .allCleared }
}
