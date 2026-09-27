import SwiftUI

// MARK: - 向き固定の解除

public extension View {
    /// この画面が表示されている間だけ横向きを許可する（#1511）。
    /// 画面を離れたら自動で許可を終える（`onDisappear` で対にする）。
    func allowsLandscapeWhileVisible(_ service: OrientationLockService) -> some View {
        modifier(LandscapeAllowingModifier(service: service))
    }
}

private struct LandscapeAllowingModifier: ViewModifier {
    let service: OrientationLockService

    func body(content: Content) -> some View {
        content
            .onAppear { service.beginAllowingLandscape() }
            .onDisappear { service.endAllowingLandscape() }
    }
}

// MARK: - 縦・横で組み方を切り替える共通の器

/// トランプのソリティア系 3 画面（ソリティア・スパイダー・フリーセル）で組み方を揃えるための器（#1511）。
///
/// 縦向きは既存どおり「状態バー → 盤 → 操作 → ヒント → 広告」の単純な縦積み。
/// 横向きは高さが乏しく幅が余るぶん、**盤を左に大きく、状態・ヒント・操作をまとめた細い列を右へ**
/// 動かす。広告だけは画面下いっぱいの帯として残し、盤と重ならないようにする。
///
/// 向きの判定は `UIDevice` の向きではなく**自分に与えられた枠の縦横比**で行う（#458 の
/// `AdaptiveLayout` と同じ考え方）。回転のたびに OS の通知を待つより、実際に描画される幅と高さを
/// 直接見るほうが `swift test` でも検証しやすく、Split View 等での見た目のずれも起きない。
public struct OrientationAdaptiveGameLayout<StatusBar: View, Board: View, Hint: View, Controls: View>: View {
    /// 横向き時に右へ寄せる列の幅。
    ///
    /// 状態バー（`GameStatusBar`）は本来盤と同じ幅いっぱいに広がる帯で、中の `Spacer` が
    /// 数字を両端へ押し広げる作り。狭い列にそのまま押し込むと `Text` が 1 文字ずつ折り返される
    /// （実測・#1511）。折り返させないため `.fixedSize` で自然な幅のまま置き、
    /// 列の幅はその自然な幅（時計アイコン付きの経過時間まで込みの実測）が収まる値にしてある。
    public static var sideColumnWidth: CGFloat { 220 }

    @State private var isLandscape = false

    private let boardSideInset: CGFloat
    private let ads: AdService
    private let statusBar: StatusBar
    private let board: Board
    private let hint: Hint
    private let controls: Controls

    /// - Parameters:
    ///   - boardSideInset: 盤の左右に足す余白（縦向き時。ソリティアは `Theme.pad`、
    ///     スパイダー・フリーセルは各 `Metrics.boardSideInset` を渡し、既存の見た目をそのまま保つ）。
    public init(
        boardSideInset: CGFloat,
        ads: AdService,
        @ViewBuilder statusBar: () -> StatusBar,
        @ViewBuilder board: () -> Board,
        @ViewBuilder hint: () -> Hint,
        @ViewBuilder controls: () -> Controls
    ) {
        self.boardSideInset = boardSideInset
        self.ads = ads
        self.statusBar = statusBar()
        self.board = board()
        self.hint = hint()
        self.controls = controls()
    }

    public var body: some View {
        Group {
            if isLandscape {
                landscapeBody
            } else {
                portraitBody
            }
        }
        // `.background` に潜り込ませて測るだけにする（`AdaptiveLayoutProvider` と同じ理由。
        // コンテナとして使うと中身が左上寄せの「与えられた分だけ広がるビュー」に変わる）。
        .background {
            GeometryReader { geo in
                Color.clear
                    .task(id: geo.size.width > geo.size.height) {
                        isLandscape = geo.size.width > geo.size.height
                    }
            }
        }
    }

    /// 既存の見た目と1pt も変えない（対象外の画面・縦に戻したときの受け入れ条件）。
    ///
    /// 各部品に個別に `.horizontal` パディングを当てる形（盤だけ `boardSideInset`、
    /// ほかは `Theme.pad`）は、外側の VStack をまとめて `.padding(Theme.pad)` するのと
    /// 見た目上は同じになる（子の幅の合計は変わらない）。ソリティアは元々まとめ塗りだったため
    /// `boardSideInset` に `Theme.pad` を渡して結果を一致させ、スパイダー・フリーセルは
    /// 元々の個別塗りをそのままここへ移す。
    private var portraitBody: some View {
        VStack(spacing: 8) {
            statusBar
                .padding(.horizontal, Theme.pad)
            board
                .padding(.horizontal, boardSideInset)
                .layoutPriority(1)
            controls
                .padding(.horizontal, Theme.pad)
            hint
                .padding(.horizontal, Theme.pad)
            Spacer(minLength: 0)
            BannerSlot(ads: ads)
                .padding(.horizontal, Theme.pad)
        }
        .padding(.vertical, Theme.pad)
    }

    private var landscapeBody: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                board
                    .layoutPriority(1)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        // 状態バーは幅いっぱいに広がる帯として作られているため、列幅へ
                        // 押し込むと中の文字が 1 文字ずつ折り返る。自然な幅のまま置く。
                        statusBar
                            .fixedSize(horizontal: true, vertical: false)
                        controls
                        hint
                    }
                }
                .frame(width: Self.sideColumnWidth)
            }
            .padding(.horizontal, Theme.pad)
            // 広告は画面下いっぱいの帯として残す（盤・側列のどちらとも重ねない）。
            BannerSlot(ads: ads)
                .padding(.horizontal, Theme.pad)
        }
        .padding(.top, Theme.pad)
        .padding(.bottom, 4)
    }
}
