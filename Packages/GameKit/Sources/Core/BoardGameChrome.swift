import SwiftUI

/// 盤ゲーム（将棋・チェス）で共通の演出・共通の枠（#530）。
///
/// チェス（#464）は将棋からミラー実装で起こしたため、**同じ意図の実装が2か所にある**状態が
/// 続いていた。片方だけ直すと片方に不具合が残る（#477 では盤の角丸と駒の層の重なり順を
/// 両方に当て直している）。ここに1つだけ置き、両方から使う。
///
/// **ここに置くのは「両方で同じでなければならないもの」だけ**。盤の目数（9×9 と 8×8）・
/// マスの塗り分け（将棋は無地、チェスは明暗の市松）・駒の描き方は、ゲームごとに違って
/// 当然のものなので各ゲーム側に残す。

// MARK: - 演出の時間

/// 盤ゲームの演出にかける時間と `Animation`（#201・#377・#530）。
///
/// 将棋の `ShogiMotion` とチェスの `ChessMotion` は、**同じ値・同じ理由**の定数を
/// それぞれに持っていた（実測: 6 つの秒数と 5 つの `Animation` がすべて一致）。
/// 片方だけ調整すると盤ゲーム間で手触りがずれるため、1 つにまとめて両方から参照する。
public enum BoardGameMotion {
    /// 駒の移動にかかる時間の目安（バネの `response`）。CPU が即指しする場面や早指しでも
    /// 次の着手に食い込まないよう短めに取る。
    public static let pieceMoveResponse: TimeInterval = 0.26
    /// 成り・プロモーション確認の札の出入り。`pieceMoveResponse` より短くする。
    public static let promotionPromptDuration: TimeInterval = 0.18
    /// 手番バッジの色替え。
    public static let turnChangeDuration: TimeInterval = 0.2
    /// 「王手」「チェック」の合図が飛び出す・引っ込むのにかかる時間（バネの `response`）。
    public static let checkBannerResponse: TimeInterval = 0.24
    /// 合図を出しておく時間。**駒の移動より長く取る**（`pieceMoveResponse`）。
    /// ここが短いと、王手を掛けた駒がまだ動いている最中に文字が消えて何が起きたか読めない。
    public static let checkBannerHold: TimeInterval = 1.1

    /// 駒の移動。跳ね返り（`dampingFraction` < 1）は駒がマスから外れて見えるため、ほぼ入れない。
    public static let pieceMove: Animation = .spring(response: pieceMoveResponse, dampingFraction: 0.9)
    /// 成り・プロモーション確認の札の出入り（#201）。**駒の移動より短く取る**。
    /// 札が消えるのと同時に成った駒が動き出すため、ここが長いと札が駒に被ったまま残る。
    public static let promotionPrompt: Animation = .easeOut(duration: promotionPromptDuration)
    /// 手番バッジの色替え（#201）。手番が移ったと分かる程度に留め、
    /// タップから盤が反応するまでの体感を遅くしない。
    public static let turnChange: Animation = .easeInOut(duration: turnChangeDuration)
    /// 合図の出入り（#377）。危急を伝えるので、駒の移動と違って少し跳ねさせる
    /// （札は盤の上の中空にあり、マスから外れて見える心配がない）。
    public static let checkBanner: Animation = .spring(response: checkBannerResponse, dampingFraction: 0.65)

    /// 選択した駒の持ち上げにかかる時間（バネの `response`）。**駒の移動より短く取る**。
    /// タップへの即応が命の演出なので、ここが長いと操作が重く感じる。
    public static let pieceLiftResponse: TimeInterval = 0.16
    /// 持ち上げ量（マス幅に対する比）と拡大率。浮いたと分かる最小限に留め、隣のマスに被せない。
    public static let pieceLiftRatio: CGFloat = 0.12
    public static let pieceLiftScale: CGFloat = 1.07
    /// 選択した駒の持ち上げ。掴んだ手応えとして少しだけ跳ねさせる
    /// （持ち上げは駒がマスの中心から浮く演出なので、跳ねてもマスからはみ出て見えない）。
    public static let pieceLift: Animation = .spring(response: pieceLiftResponse, dampingFraction: 0.7)
}

// MARK: - 王手の色

/// 「王手」「チェック」の合図に使う緋色（#377・#530）。
///
/// 差し色（`Theme.coral` など）は**白文字を載せると WCAG AA 未達**で #220 の対象になっているため
/// 使わない。この緋色は白文字との対比が 6.5:1 あり、盤の飴色・明暗どちらのマスに対しても
/// 十分に沈んで見える。
///
/// `Color` は生成後に成分を取り出せないため、コントラストを検証するテストが参照できるよう
/// 数値のまま持つ（`Theme.Hex` と同じ理由）。
public enum BoardGameCheckColor {
    public static let hex: UInt32 = 0xB3261E
    public static let color = Color(hex: hex)
}

// MARK: - 駒の持ち上げ

public extension View {
    /// 選択した駒を少し持ち上げる（拡大 + 浮かせ + 落ち影）。
    ///
    /// 「浮いている」ことは駒の下に落ちる影で伝わるので、**影を先に描く**。
    /// アニメーションはここでは掛けない——`.gameAnimation(BoardGameMotion.pieceLift, value:)` を
    /// **呼び出し側の駒単位**で、この修飾子より後ろに置くこと。層全体に置くと、着手確定で
    /// 配置と選択が同時に変わったとき `pieceMove` 側の指定に上書きされ、戻りの速さが
    /// 意図とずれる（verifier 検証 2026-09-06）。
    ///
    /// - Parameters:
    ///   - isLifted: 選択されている（= 持ち上げる）か。
    ///   - cell: マスの実寸。持ち上げ量と影の大きさをここから作る。
    func pieceLift(isLifted: Bool, cell: CGFloat) -> some View {
        scaleEffect(isLifted ? BoardGameMotion.pieceLiftScale : 1)
            .shadow(color: .black.opacity(isLifted ? 0.28 : 0),
                    radius: isLifted ? cell * 0.10 : 0,
                    y: isLifted ? cell * 0.10 : 0)
            .offset(y: isLifted ? -cell * BoardGameMotion.pieceLiftRatio : 0)
    }

    /// 盤のマス層の上に、**角丸 → 駒 → 王手 → 着手先** の順で層を重ねる（#200・#377・#477）。
    ///
    /// 順番そのものが不具合の有無を決めるので、両ゲームで別々に書かない:
    ///
    /// - **角丸は駒より前**。あとに掛けると、選択して持ち上げた駒（拡大 + 上へ 12%）が
    ///   盤の上端で切り落とされる（PR #477 の CodeRabbit 指摘。将棋の表示 0 段目で実測）。
    /// - **駒はマスの中ではなく盤全体を覆う 1 枚の層**（#200）。マスに紐づけると駒の同一性が
    ///   マスと一緒に変わり、移動が補間されない。
    /// - **王手の印と着手先の印は駒より後（= 上）**。駒の下に潜ると、玉を囲む枠も
    ///   「取れる駒」に重ねる枠も読めなくなる。
    func boardLayers<Pieces: View, Check: View, Targets: View>(
        corner: CGFloat,
        @ViewBuilder pieces: () -> Pieces,
        @ViewBuilder check: () -> Check,
        @ViewBuilder targets: () -> Targets
    ) -> some View {
        clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay { pieces() }
            .overlay { check() }
            .overlay { targets() }
    }
}

// MARK: - 検討ナビ

/// 終局後の検討ナビ（1手戻す / 手数 / 1手進める）と「もう一度」を 1 段にまとめた帯（#139・#530）。
///
/// 2 段のままだと盤の下が伸び、決着の瞬間に盤が縮む。対局中の操作列と同じ高さに収める。
///
/// 記号だけのボタンは VoiceOver が SF Symbols の名前を推測して読み、何をするボタンかが
/// 伝わらない。読み上げ文はこの共通実装に持たせる——**将棋側の実装にはこの指定が無く、
/// チェス側にだけ入っていた**（#530 が防ごうとしている「片方だけ直した」状態そのもの）。
public struct ReviewNavBar: View {
    /// 表示中の手数（0 = 初期局面）。
    public let ply: Int
    /// 総手数。
    public let total: Int
    public let onBack: () -> Void
    public let onForward: () -> Void
    public let onNewGame: () -> Void

    public init(
        ply: Int,
        total: Int,
        onBack: @escaping () -> Void,
        onForward: @escaping () -> Void,
        onNewGame: @escaping () -> Void
    ) {
        self.ply = ply
        self.total = total
        self.onBack = onBack
        self.onForward = onForward
        self.onNewGame = onNewGame
    }

    public var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) { Image(systemName: "backward.frame.fill") }
                .disabled(ply <= 0)
                .accessibilityLabel("1手戻す")
            Text("\(ply)/\(total)手")
                .themeBody(14).monospacedDigit().foregroundStyle(Theme.ink)
                .accessibilityLabel("\(total)手中 \(ply)手目")
            Button(action: onForward) { Image(systemName: "forward.frame.fill") }
                .disabled(ply >= total)
                .accessibilityLabel("1手進める")

            Spacer(minLength: 8)

            Button(action: onNewGame) {
                Label("もう一度", systemImage: "arrow.clockwise")
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Fill.coral))
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 5)
        .popCard(corner: Theme.cornerSmall)
    }
}
