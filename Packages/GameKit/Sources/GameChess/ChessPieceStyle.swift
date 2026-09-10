import SwiftUI
import Core

/// 駒の意匠（#598）。**見た目だけ**の分岐で、ルール・記録には一切触れない。
///
/// 「1局=1RuleSet」規約（`docs/ai-devops.md`）の対象外。局の進行に影響しないので局へ焼き込まず、
/// `GameScore.variant` も **nil のまま**にする（意匠で自己ベストの保存先を分けると、
/// 見た目を替えただけでこれまでの記録がどこからも参照されなくなる）。
public enum ChessPieceStyle: String, CaseIterable, Sendable {
    /// 平らな塗りの駒。v1.1.3 までと同じ見た目で、**既定**。
    case flat
    /// 影・ツヤを足した立体的な駒。
    case sculpted

    /// 設定シートのタイルに出す名前。
    public var label: String {
        switch self {
        case .flat:     return "シンプル"
        case .sculpted: return "立体"
        }
    }

    /// タイルの副題。
    public var subtitle: String {
        switch self {
        case .flat:     return "今までの駒"
        case .sculpted: return "影とツヤ"
        }
    }

    /// この意匠での陰影の指定。色ごとに変える（白駒と黒駒では、同じ強さの照りが同じ立体感にならない）。
    public func shading(for color: ChessColor) -> ChessPieceShading {
        switch self {
        case .flat:
            return ChessPieceShading(
                fill: color == .white
                    ? [ChessBoardStyle.whitePieceTop, ChessBoardStyle.whitePieceBottom]
                    : [ChessBoardStyle.blackPieceTop, ChessBoardStyle.blackPieceBottom],
                highlight: nil,
                highlightRadius: 0,
                sheen: 0,
                depth: 0,
                shadowOpacity: 0.28,
                shadowRadius: 0.03,
                shadowOffset: 0.02
            )
        case .sculpted:
            // 面の色は現行と同じものを使い、**光の当て方だけ**で立体にする。
            // 照りの中心は左上（碁石・五目の石と同じ光源。#398/#368）。ここを揃えないと、
            // 同じ画面に出る駒とカードで光の向きが食い違う。
            return ChessPieceShading(
                fill: color == .white
                    ? [ChessBoardStyle.whitePieceTop, ChessBoardStyle.whitePieceBottom]
                    : [ChessBoardStyle.blackPieceTop, ChessBoardStyle.blackPieceBottom],
                highlight: CGPoint(x: 0.34, y: 0.26),
                highlightRadius: 1.15,
                // 黒駒は面が暗いぶん白のツヤが乗りやすい。同じ値にすると黒だけ塗料を塗った
                // ように光る（実測して白 0.42 / 黒 0.30 に分けた）。
                sheen: color == .white ? 0.42 : 0.30,
                // 逆に落とす陰は黒駒のほうを強くする。白駒で同じだけ落とすと、
                // 明るいマスの上で下半分が灰色に濁る。
                depth: color == .white ? 0.18 : 0.30,
                shadowOpacity: color == .white ? 0.34 : 0.40,
                shadowRadius: 0.05,
                shadowOffset: 0.035
            )
        }
    }
}

/// 駒 1 枚ぶんの陰影の指定。`Canvas` に渡す値を意匠から切り離して置く
/// （`Canvas` の描画そのものはテストから覗けないため、値の側だけでも固定できるようにする）。
///
/// 長さの単位はすべて**駒の描画矩形に対する比**で、実寸には依存しない。
public struct ChessPieceShading: Equatable, Sendable {
    /// 面の塗り（`highlight` があればラジアル、無ければ上→下の線形）。
    public var fill: [Color]
    /// 照りの中心（正規化座標）。nil なら平らな塗り。
    public var highlight: CGPoint?
    /// 照りが消えきる距離（駒の幅に対する比）。
    public var highlightRadius: CGFloat
    /// 上に重ねる白のツヤの濃さ。0 なら重ねない。
    public var sheen: Double
    /// 下端に落とす陰の濃さ。0 なら落とさない。
    public var depth: Double
    /// 駒の外に落とす影の濃さ。
    public var shadowOpacity: Double
    /// 同・ぼけの半径（駒の大きさに対する比）。
    public var shadowRadius: CGFloat
    /// 同・下方向のずれ（駒の大きさに対する比）。
    public var shadowOffset: CGFloat

    /// 面の塗りより上に重ねるものがあるか。無ければ `Canvas` は塗りと輪郭だけで済む。
    public var hasOverlay: Bool { sheen > 0 || depth > 0 }
}

/// 選んだ意匠の保存先（#598）。
///
/// 触覚・効果音の `FeedbackPreference` と同じ形にしてある（キーと既定値の規則を 1 か所に閉じ込め、
/// 呼び出し側は読み書きするだけ）。あちらは Bool 専用なので、文字列を入れるここだけを別に置く。
///
/// `static let` にすると `UserDefaults` を抱えた共有可変状態になり Sendable 違反になるため、
/// 使う側で都度組み立てる（実体は文字列と `UserDefaults` の参照だけなので安い）。
public struct ChessPieceStylePreference {
    /// 保存キー。**改名すると、既に立体を選んでいる人の設定が既定へ戻る**。
    static let key = "chessPieceStyle_v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 保存された意匠。未設定（初回起動）と、読めない値が入っていたときは既定の `.flat`。
    public var style: ChessPieceStyle {
        get {
            guard let raw = defaults.string(forKey: Self.key) else { return .flat }
            return ChessPieceStyle(rawValue: raw) ?? .flat
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.key) }
    }
}
