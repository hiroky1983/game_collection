import CoreGraphics

/// ルーレットの操作まわりの寸法（#1318・#2364）。**View から切り出した定数**として置く。
///
/// 切り出しの理由はブラックジャック（`BlackjackMetrics`・#709）と同じで、ここが「押しにくい」の急所だから。
/// 値が縮んだらテストで気づけるようにする。
///
/// #2364 でホイールを主役にした（会長決裁 2026-10-17・案 A と B の組み合わせ）。ホイールの直径は
/// 固定の値をやめ、**ほかの部品を置いて余った高さいっぱい**に取る（`wheelDiameter(fitting:)`）。
enum RouletteMetrics {

    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44

    /// 操作ボタン（戻す・スピン・結果まで進める・次のゲーム・同じ賭けでもう一度）の高さの下限。
    static let actionButtonMinHeight: CGFloat = minimumTapTarget

    /// チップの額を選ぶ丸ボタンの直径。毎スピン触るので HIG の下限に置く。
    static let chipButtonSize: CGFloat = minimumTapTarget

    /// マスの間隔。
    static let cellSpacing: CGFloat = 3

    /// 盤面（賭けの表）のカードの内側の余白。
    static let boardPadding: CGFloat = 10
    /// タブと表の間隔。
    static let tableTabSpacing: CGFloat = 8
    /// 操作欄の 2 段の間隔。
    static let actionRowSpacing: CGFloat = 8

    // MARK: - ホイール

    /// 賭けの画面のホイールのカードの内側の余白（ホイールの上下左右）。
    static let wheelCardPadding: CGFloat = 8
    /// ホイールの下の 1 行（出目の履歴と「賭ける場所をタップ」などの案内）の高さ。
    static let wheelCardFooterHeight: CGFloat = 22
    /// ホイールと下の 1 行の間隔。
    static let wheelCardFooterSpacing: CGFloat = 4
    /// ホイールのカードでホイール以外が取る高さ（余白 + 下の 1 行）。
    static var wheelCardChromeHeight: CGFloat {
        wheelCardPadding * 2 + wheelCardFooterSpacing + wheelCardFooterHeight
    }

    /// 賭けの画面でホイールに残したい最小の直径。初回ガイドが出ている SE でもこれを下回らないこと。
    static let minimumBettingWheelDiameter: CGFloat = 100

    /// ホイールの画面（回転中・結果）の上の札（チップ・ベット）の行の高さ。
    static let wheelScreenStatsHeight: CGFloat = 30
    /// ホイールの画面の「あなたの賭け」のカードの高さ（見出し・置いた口・出目の履歴の 3 行 + 余白）。
    static let betSummaryHeight: CGFloat = 100

    /// 与えられた枠に収まるホイールの直径。`GeometryReader` は最初に大きさ 0 を渡すことがあるので負にしない。
    static func wheelDiameter(fitting size: CGSize) -> CGFloat {
        max(0, min(size.width, size.height))
    }

    // MARK: - 縦の狭さ

    /// 「縦が狭い」と見なす境目（pt）。画面の中身に使える高さがこれを下回ったら `Sizing.compact` に落とす。
    ///
    /// 通常の寸法（`Sizing.regular`）が初回ガイドとバナー込み・ホイールを最小の直径にして要る高さ
    /// （約 635pt・`RouletteMetricsTests` が見積もる）より上に置く。iPhone SE（第 3 世代）は約 603pt・
    /// iPhone 13 mini は約 687pt で詰める側、iPhone 17 は約 715pt で通常の側。
    static let compactHeightThreshold: CGFloat = 690

    /// 画面の高さで変える寸法の束。`AdaptiveLayout`（#458）は幅しか見ないので、縦の狭さはこの画面で持つ。
    struct Sizing: Equatable {
        /// 数字 1 点のマスの高さ。37 マスを 1 画面に並べるため HIG の 44pt には届かない
        /// （幅は 4 段 × 9 列で約 32pt）。隣を押しても同じ「数字 1 点」の賭けで、置いた口は
        /// 「戻す」で外せるので、誤タップの損は 1 タップで取り返せる。
        let numberCellHeight: CGFloat
        /// 賭けの表のタブ（数字 / 赤黒・区分）の高さ。横幅が画面の半分あるので、SE では高さを少し詰める。
        let tabHeight: CGFloat
        /// カード同士の縦の間隔。
        let stackSpacing: CGFloat
        /// 操作欄の上下の余白。
        let cardVerticalPadding: CGFloat

        static let regular = Sizing(numberCellHeight: 34, tabHeight: 44, stackSpacing: 10, cardVerticalPadding: 12)
        static let compact = Sizing(numberCellHeight: 30, tabHeight: 36, stackSpacing: 8, cardVerticalPadding: 6)

        /// 表の中身の高さ。2 つのタブで同じ高さにして、切り替えても画面が上下に動かないようにする。
        var tableContentHeight: CGFloat {
            numberCellHeight * 4 + cellSpacing * 3
        }

        /// 「赤黒・区分」タブのマスの高さ。区分 3 つと赤黒など 6 つの 2 段で、数字の表と同じ高さを分け合う。
        var outsideCellHeight: CGFloat {
            (tableContentHeight - cellSpacing) / 2
        }

        /// 賭けの表のカードの高さ（タブ + 間隔 + 表 + 内側の余白）。
        var tableCardHeight: CGFloat {
            tabHeight + tableTabSpacing + tableContentHeight + boardPadding * 2
        }

        /// 操作欄の高さ（チップ額 4 つ + 戻す / スピンの 2 段）。
        var actionBarHeight: CGFloat {
            max(chipButtonSize, actionButtonMinHeight) + actionRowSpacing + actionButtonMinHeight
                + cardVerticalPadding * 2
        }
    }

    /// 画面の中身に使える高さから寸法を選ぶ。境目未満なら詰める。
    static func sizing(forHeight height: CGFloat) -> Sizing {
        height < compactHeightThreshold ? .compact : .regular
    }
}
