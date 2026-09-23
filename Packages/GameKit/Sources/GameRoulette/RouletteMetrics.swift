import CoreGraphics

/// ルーレットの操作まわりの寸法（#1318）。**View から切り出した定数**として置く。
///
/// 切り出しの理由はブラックジャック（`BlackjackMetrics`・#709）と同じで、ここが「押しにくい」の急所だから。
/// 値が縮んだらテストで気づけるようにする。
enum RouletteMetrics {

    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44

    /// 操作ボタン（戻す・スピン・結果まで進める・次のゲーム・同じ賭けでもう一度）の高さの下限。
    static let actionButtonMinHeight: CGFloat = minimumTapTarget

    /// チップの額を選ぶ丸ボタンの直径。毎スピン触るので HIG の下限に置く。
    static let chipButtonSize: CGFloat = minimumTapTarget

    /// マスの間隔。
    static let cellSpacing: CGFloat = 3

    /// 「縦が狭い」と見なす境目（pt）。画面の中身に使える高さがこれを下回ったら `Sizing.compact` に落とす。
    ///
    /// iPhone SE（第 3 世代）は 667pt からステータスバーとナビゲーションバーを引いて約 603pt。
    /// iPhone 13 mini は 812pt で約 720pt。あいだの 620pt に置く。
    static let compactHeightThreshold: CGFloat = 620

    /// 画面の高さで変える寸法の束。`AdaptiveLayout`（#458）は幅しか見ないので、縦の狭さはこの画面で持つ
    /// （盤面 37 マス・ホイール・操作欄・バナーを 1 画面に固定 pt で並べる画面はここだけ）。
    struct Sizing: Equatable {
        /// ホイールの直径（iPhone）。iPad は `AdaptiveLayout.elementScale` で相似に拡大する。
        let wheelDiameter: CGFloat
        /// 数字 1 点のマスの高さ。37 マスを 1 画面に並べるため HIG の 44pt には届かない
        /// （幅は 4 段 × 9 列で約 32pt）。隣を押しても同じ「数字 1 点」の賭けで、置いた口は
        /// 「戻す」で外せるので、誤タップの損は 1 タップで取り返せる。
        let numberCellHeight: CGFloat
        /// 12 個ずつの区分・赤黒などのマスの高さ。数字のマスより少しだけ高くして段を見分けやすくする。
        let outsideCellHeight: CGFloat
        /// カード同士の縦の間隔。
        let stackSpacing: CGFloat
        /// ホイールのカードと操作欄の上下の余白。
        let cardVerticalPadding: CGFloat

        static let regular = Sizing(wheelDiameter: 132, numberCellHeight: 34, outsideCellHeight: 36,
                                    stackSpacing: 10, cardVerticalPadding: 12)
        static let compact = Sizing(wheelDiameter: 104, numberCellHeight: 30, outsideCellHeight: 32,
                                    stackSpacing: 8, cardVerticalPadding: 6)

        /// 盤面のカードの高さ（マス 4 段 + 区分 2 段 + 間隔 + 内側の余白）。
        var boardHeight: CGFloat {
            numberCellHeight * 4 + outsideCellHeight * 2 + cellSpacing * 5 + boardPadding * 2
        }
    }

    /// 盤面のカードの内側の余白。
    static let boardPadding: CGFloat = 10

    /// 画面の中身に使える高さから寸法を選ぶ。境目未満なら詰める。
    static func sizing(forHeight height: CGFloat) -> Sizing {
        height < compactHeightThreshold ? .compact : .regular
    }
}
