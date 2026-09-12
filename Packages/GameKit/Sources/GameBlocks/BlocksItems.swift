import Foundation

/// パワーアップの種類（#599）。
///
/// **既存の遊びを上書きせず「足す」**という Issue の要求どおり、どちらも
/// **プレイヤーを有利にするだけ**で、不利になる種類（パドルが縮む・球が速くなる等）は置かない。
/// 罰を落とすと「取らないほうが得なアイテム」が生まれ、受け止めるか避けるかの判断が
/// 反射神経の勝負に混ざる（ゆっくりモードで補えない難度の上がり方になる）。
///
/// 得点は持たない。**アイテムで増える点が 1 点でもあると、順位表に載る値の意味が
/// 版の前後で変わる**（`BlocksScoring` の理論上の満点が上がる）。ここで足すのは
/// 「満点へ届きやすくする手段」だけで、満点そのものは #463 のときと同じに保つ。
public enum BlocksItemKind: String, Codable, Equatable, Sendable, CaseIterable {
    /// パドルが `BlocksRules.widePaddleFactor` 倍に伸びる。効果時間つき。
    case widePaddle
    /// 球が増える（上限 `BlocksRules.maxBalls` 個）。その場で効いて終わる。
    case multiBall

    /// 落ちてくる順番。**乱数を使わない**（アクション枠の基盤規約）ので、
    /// 同じ崩し方からは常に同じ順で出る。
    public static let dropOrder: [BlocksItemKind] = [.widePaddle, .multiBall]

    /// 効果時間（秒）。その場で効いて終わる種類は nil。
    public var duration: Double? {
        switch self {
        case .widePaddle: return BlocksRules.widePaddleDuration
        case .multiBall:  return nil
        }
    }
}

/// 落下中のアイテム 1 個（#599）。
///
/// 球と違って反射しない。真下へ一定の速さで落ち、パドルに触れたら効果を出して消え、
/// 床まで落ちたら何も起きずに消える。
public struct BlocksItem: Equatable, Sendable {
    public let kind: BlocksItemKind
    /// 中心の x（抽象単位）。落ちるあいだ変わらない。
    public let x: Double
    /// 中心の y（抽象単位）。
    public var y: Double

    public init(kind: BlocksItemKind, x: Double, y: Double) {
        self.kind = kind
        self.x = x
        self.y = y
    }
}
