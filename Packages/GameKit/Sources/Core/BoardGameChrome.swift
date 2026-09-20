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

// MARK: - 操作列のカプセルボタン

/// 盤の下の操作列（投了・待った）のボタンの寸法（#711）。
///
/// View の `static let` は MainActor に隔離されるので、テストや他の定数から参照できるよう View の外に置く。
public enum BoardGameControlMetrics {
    /// 当たり判定の縦横の下限（Apple HIG）。
    public static let minTapTarget: CGFloat = 44
    /// このボタンを並べた操作列の上下の余白。
    ///
    /// ボタンの枠が 44pt になったぶん、従来の余白 8pt を詰めて**操作列の外寸をほぼ据え置く**
    /// （既定の文字サイズで 44pt + 1pt × 2 = 46pt。従来のカプセルは macOS の描画で 30pt なので 30 + 8 × 2 = 46pt で一致、
    /// iPhone SE のスクショでは 28.5pt で従来の操作カードが 44.5pt だったため、iOS では下端が 1.5pt 伸びる・#711 実測）。
    /// 盤の大きさは `GameControlArea` が終局後のひな形（既定で 118pt）で決めるので、この差では変わらない（#148）。
    public static let rowVerticalPadding: CGFloat = 1
    /// 検討ナビの記号ボタン（◀ ▶）の 44pt の枠を、帯のレイアウト上だけ上下それぞれこの量ぶん小さく数える（#713）。
    ///
    /// 44 − 8 × 2 = 28pt は「もう一度」のカプセル（macOS の描画で 30pt・iPhone SE で 28.5pt）より低いので、
    /// 帯の高さはこれまでどおりカプセルで決まり、決着の瞬間に盤が縮まない（#139）。
    public static let reviewNavLayoutInset: CGFloat = 8
}

/// 盤の下の操作列に置くカプセルのボタン（オセロ・五目並べの「投了」「待った」・#711）。
///
/// 以前は「投了」だけがカプセルで、「待った」は枠の無い素の文字（行高ぶん約 17pt）だった。
/// 同じ行の一方だけがボタンに見えず、指の腹より小さいので「壊れている」と受け取られる。
///
/// - **カプセルの見た目は従来どおり**（上下 6pt・左右 12pt の余白）。
/// - **44pt はボタン自身の枠に入れる**。カプセルを描いてから枠を広げ、その矩形全体で受ける。
///   枠の外へ当たり判定をはみ出させる方法（`overlay` に大きい透明な面を重ねる・負の `padding`）は、
///   macOS のプローブで Button のクリックが枠の外では反応しないと実測したため採らない（#711）。
/// - 並べる側は操作列の上下の余白を `BoardGameControlMetrics.rowVerticalPadding` に詰めて外寸を保つ。
/// - **押せないときは面を `fillMuted` に替える**。差し色の面に文字色を載せたままだと、
///   `.disabled` が付いても見た目が変わらない。
public struct BoardGameControlCapsuleStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    private let fill: Color

    public init(fill: Color) {
        self.fill = fill
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // `fillMuted` は白文字を載せる面色（`Theme.Hex.fillMuted`）。
            .foregroundStyle(isEnabled ? Theme.onAccent : Color.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(isEnabled ? fill : Theme.fillMuted))
            .frame(minWidth: BoardGameControlMetrics.minTapTarget,
                   minHeight: BoardGameControlMetrics.minTapTarget)
            // 広げた枠の透明な部分でも受ける（既定は描いた中身のぶんしか受けない）。
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - 操作列の「投了」「待った」

/// 「待った」を持つ盤ゲームの Model（将棋・チェス・オセロ・五目並べ・囲碁・#828）。
///
/// 5 本とも同じ名前・同じ意味で持っていたものを、`BoardUndoButton` が読む分だけ要求する。
@MainActor
public protocol BoardUndoModel: AnyObject {
    /// 計測（`reward_ad`）に載せるゲームの ID。
    var gameID: String { get }
    /// 「待った」が押せるか。
    var canUndo: Bool { get }
    /// 無料の「待った」を使い切ったか。使い切ったあとは広告を見て戻す。
    var undoUsed: Bool { get }
    /// 対局の通し番号 × 手数。広告を出す前に控え、戻す先の局面を照合する（#729）。
    var aiTurnKey: AITurnKey { get }
    /// 自分の直前の 1 手を、CPU の応手ごと戻す（無料の待った）。
    func undoLastExchange()
    /// 控えた局面のままのときだけ戻す。戻せなければ false（広告の待った）。
    func undoLastExchange(forTurn turn: AITurnKey) -> Bool
}

/// 操作列の「投了」ボタン（#828）。
///
/// 確認ダイアログは `boardResignConfirmation(isPresented:onResign:)` で別に取り付ける。
/// オセロだけ画面全体に付けていて、iOS 26 ではダイアログがアンカー付きのポップオーバーになるため、
/// ボタンに抱き合わせると出る位置が変わってしまう。
public struct BoardResignButton: View {
    /// 見た目。#711 で当たり判定を 44pt にしたのはオセロ・五目並べだけなので、共通化では組み方を変えない。
    public enum Look: Sendable {
        /// 手書きのカプセル（将棋・チェスは左右 12pt、3 つ並べる囲碁は 10pt）。
        case handDrawnCapsule(horizontalPadding: CGFloat)
        /// 枠 44pt の共通カプセル（`BoardGameControlCapsuleStyle`・オセロ・五目並べ）。
        case tapTargetCapsule
    }

    private let look: Look
    private let action: () -> Void

    public init(look: Look, action: @escaping () -> Void) {
        self.look = look
        self.action = action
    }

    public var body: some View {
        switch look {
        case .handDrawnCapsule(let horizontalPadding):
            Button(action: action) {
                Label("投了", systemImage: "flag.fill")
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, horizontalPadding).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Fill.coral))
            }
        case .tapTargetCapsule:
            Button(action: action) {
                Label("投了", systemImage: "flag.fill")
            }
            .buttonStyle(BoardGameControlCapsuleStyle(fill: Theme.Fill.coral))
        }
    }
}

public extension View {
    /// 投了の確認ダイアログ（#828）。文言を盤ゲーム 5 本で 1 か所にする。
    func boardResignConfirmation(isPresented: Binding<Bool>, onResign: @escaping () -> Void) -> some View {
        confirmationDialog("投了しますか？", isPresented: isPresented, titleVisibility: .visible) {
            Button("投了する", role: .destructive) { onResign() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("現在の対局を終了します。CPUの勝ちになります。")
        }
    }
}

/// 操作列の「待った」ボタン。確認アラート・広告の待った・失敗のアラートまでを持つ（#526・#729・#828）。
///
/// - **救済（`RewardedRescue`）は呼び出し側の `@State` から受け取る**。操作列は決着すると検討ナビに
///   入れ替わって消えるので、ここで持つと広告のロード中の連打ガードが操作列ごと捨てられる。
/// - 見た目は `usesTapTargetCapsule` で選ぶ（true = 枠 44pt の共通カプセル・オセロ・五目並べ、
///   false = 素の文字・将棋・チェス・囲碁）。
public struct BoardUndoButton<Model: BoardUndoModel>: View {
    private let model: Model
    private let services: GameServices
    private let undoRescue: RewardedRescue
    private let usesTapTargetCapsule: Bool
    @State private var showUndoConfirm = false

    public init(model: Model, services: GameServices, rescue: RewardedRescue, usesTapTargetCapsule: Bool) {
        self.model = model
        self.services = services
        self.undoRescue = rescue
        self.usesTapTargetCapsule = usesTapTargetCapsule
    }

    public var body: some View {
        button
            .disabled(!model.canUndo)
            .alert("待った確認", isPresented: $showUndoConfirm) {
                Button(model.undoUsed ? "広告を見て戻す" : "戻す（無料）") {
                    guard model.undoUsed else {
                        // 無料の待ったは #526 の前と同じく、アラートを閉じる処理とは別の
                        // 手番で盤を動かす（同じ transaction に乗せると盤の変化が
                        // アラートの終了アニメーションに巻き込まれる）。
                        Task { model.undoLastExchange() }
                        return
                    }
                    // 視聴完了（報酬獲得）したときだけ待ったを許可する。どの局面に対する待ったかを
                    // 広告を出す前に控え、ロード中に対局が入れ替わったり指し進めたりした局面へは乗せない（#729）。
                    let turn = model.aiTurnKey
                    undoRescue.request(
                        services, gameID: model.gameID, purpose: .undo,
                        guardedBy: .checkedByGrant
                    ) {
                        model.undoLastExchange(forTurn: turn)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                // 戻るのは「自分の1手 + CPU の応手」の2手（`undoLastExchange`）。
                // 「直前の1手」とだけ書くと、盤が2手ぶん戻ることが伝わらない（#665）。
                Text(model.undoUsed
                     ? "無料の待ったは使い切りました。\n広告を視聴すると、もう一度あなたの直前の1手（CPU の応手ごと）を取り消せます。"
                     : "あなたの直前の1手を、CPU の応手ごと取り消します。\n無料で使えるのは1回だけです。")
            }
            // 無料の待ったの確認は広告の提示ではないので数えない（#780）。
            .rewardOffer(undoRescue, for: .undo, isPresented: showUndoConfirm && model.undoUsed,
                         services: services, gameID: model.gameID)
            .rewardedRescueAlerts(
                undoRescue,
                notEarned: "待ったは使えませんでした",
                unavailable: RewardUnavailableAlert(
                    title: "待ったは使えませんでした",
                    message: "広告を見ているあいだに新しい対局が始まったか、局面が変わったため、戻せませんでした。"
                )
            )
    }

    @ViewBuilder private var button: some View {
        if usesTapTargetCapsule {
            Button { showUndoConfirm = true } label: {
                Label("待った", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(BoardGameControlCapsuleStyle(fill: Theme.Fill.teal))
        } else {
            Button { showUndoConfirm = true } label: {
                Label("待った", systemImage: "arrow.uturn.backward")
            }
        }
    }
}

// MARK: - ヒントの色

/// ヒントが示す手の印の色（#1118）。3 本とも同じ色で示す。
///
/// **紫にする理由**: ボタンと同じ黄色は、将棋の飴色の盤にも五目並べの榧色の盤にも沈んで読めない。
/// 盤の上で既に意味を持っている色（着手先の `Theme.coral`・王手の `BoardGameCheckColor`）とも
/// 取り違えられない残りの差し色が紫だった。
public enum BoardGameHintColor {
    public static let color = Theme.purple
}

// MARK: - 操作列の「ヒント」

/// ヒントを持つ盤ゲームの Model（将棋・チェス・五目並べ・#1118）。
///
/// `BoardHintButton` が読む分だけを要求する。回数の勘定そのものは 3 本とも
/// `CoreEngine.BoardHintBudget` が持つので、ここでは「いま押せるか」「残りいくつか」だけを見る。
@MainActor
public protocol BoardHintModel: AnyObject {
    /// 残り回数（ボタンの文字に出る）。
    var hintsRemaining: Int { get }
    /// いまヒントを押せるか（人間の手番・対局中・残りが在る・読みが走っていない）。
    var canUseHint: Bool { get }
    /// ヒントの読みの最中か。ボタンの中の合図に使う。
    var isHintThinking: Bool { get }
    /// 最善手を 1 手求めて盤の上に示す。求まらなければ回数は減らさない。
    func requestHint() async
}

/// 操作列の「ヒント」ボタン（#1118）。
///
/// **3 本とも同じ部品・同じ見た目にする**（`feedback_same_widget_same_look` の方針）。`BoardResignButton` の
/// ような見た目の分岐は持たせない — 新しく足す部品なので、片方だけ違う組み方を最初から作らない。
/// 見た目は枠 44pt の共通カプセル（`BoardGameControlCapsuleStyle`）で、黄色 + 電球はナンプレのヒント
/// （`SudokuView`）と同じ。アプリの中で「ヒント」の合図をゲームごとに変えない。
///
/// 将棋・チェスの操作列はカプセルが約 30pt の 1 行なので、**呼び出し側で
/// `.padding(.vertical, -BoardGameControlMetrics.reviewNavLayoutInset)` を掛けて 44pt の枠を
/// レイアウト上だけ詰める**（検討ナビの ◀ ▶ と同じ手。44 − 8 × 2 = 28pt < カプセル）。
/// 詰めないと対局中の操作列だけが 14pt 高くなり、決着の瞬間に盤が縮む（#139・#148）。
/// 五目並べの操作列は元から 44pt のカプセルで組んであるので、そのまま並べる（#711）。
public struct BoardHintButton<Model: BoardHintModel>: View {
    private let model: Model

    public init(model: Model) {
        self.model = model
    }

    public var body: some View {
        Button {
            // 読みは Model の中で `AITurnGuarded` の照合に載せる（押したあとの局面ずれはそこで弾く）。
            Task { await model.requestHint() }
        } label: {
            Label {
                Text("ヒント\(model.hintsRemaining)")
            } icon: {
                // 読みは最長 2 秒ほど掛かる。押したのに何も変わらない間を作らないよう、
                // 電球を回転に差し替える（文字は残すのでボタンの幅はほぼ変わらない）。
                if model.isHintThinking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "lightbulb.fill")
                }
            }
        }
        .buttonStyle(BoardGameControlCapsuleStyle(fill: Theme.Fill.yellow))
        .disabled(!model.canUseHint)
        .accessibilityLabel("ヒント、残り\(model.hintsRemaining)回")
        // 読みの最中も `canUseHint` は false になる。「使えない理由」だけを読ませると、
        // 押した直後の数秒に「あなたの手番ではない」と誤った案内をすることになる（PR #1184 の指摘）。
        .accessibilityHint(hintText)
    }

    /// ボタンの状態ごとの読み上げ説明。
    private var hintText: String {
        if model.isHintThinking { return "CPU が最善手を読んでいます" }
        return model.canUseHint
            ? "CPU の読みで最善手を1手だけ盤の上に示します。ヒントを使った対局は順位表に送りません"
            : "いまは使えません（あなたの手番ではないか、3回とも使い切りました）"
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
///
/// ◀ ▶ は記号だけだと約 17pt 四方で、終局後に棋譜を 1 手ずつ送る連打の的にならない（#713）。
/// - **44pt の枠と `contentShape` はボタンの中（`navSymbol`）に入れる**。帯の高さへの影響は
///   ボタンの**外**の負の余白（`BoardGameControlMetrics.reviewNavLayoutInset`）で打ち消す。
///   枠や形を取ってから中で余白を詰める方法は、macOS のプローブで詰めた外側が反応しなかった
///   （`BoardGameControlCapsuleStyle` の注記と同じ現象）。外で詰める方法は、帯からはみ出した
///   上下 22pt まで反応し、25pt では反応しないと実測した（#713）。
/// - はみ出した部分は、**後ろに並ぶ当たり判定を持つビューに取られる**（同じプローブで、帯の直後に
///   色の面を置くと下側が反応しなかった）。将棋・チェスは帯の直後が `Spacer` なので取られない。
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
            // 44pt の枠の透明な部分が記号と手数の間を空けるので、この 3 つは間隔 0 で並べる。
            HStack(spacing: 0) {
                Button(action: onBack) { Self.navSymbol("backward.frame.fill") }
                    .padding(.vertical, -BoardGameControlMetrics.reviewNavLayoutInset)
                    .disabled(ply <= 0)
                    .accessibilityLabel("1手戻す")
                Text("\(ply)/\(total)手")
                    .themeBody(14).monospacedDigit().foregroundStyle(Theme.ink)
                    .accessibilityLabel("\(total)手中 \(ply)手目")
                Button(action: onForward) { Self.navSymbol("forward.frame.fill") }
                    .padding(.vertical, -BoardGameControlMetrics.reviewNavLayoutInset)
                    .disabled(ply >= total)
                    .accessibilityLabel("1手進める")
            }

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

    /// ◀ ▶ の中身。記号を 44pt の枠の中央に置き、枠の透明な部分でも受ける。
    private static func navSymbol(_ name: String) -> some View {
        Image(systemName: name)
            .frame(minWidth: BoardGameControlMetrics.minTapTarget,
                   minHeight: BoardGameControlMetrics.minTapTarget)
            .contentShape(Rectangle())
    }
}
