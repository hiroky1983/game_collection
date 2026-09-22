import SwiftUI

/// リワード広告 1 本と引き換えに救済を 1 つ受け取るまでの段取り（#526）。
///
/// 各ゲームの View に同じ形で書かれていた次の 5 つを 1 か所へ集める:
///
/// 1. 広告のロード〜視聴中の**連打ガード**（2 本目の呼び出しが失敗して、見てもいない広告の
///    失敗アラートが出るのを防ぐ）
/// 2. `GameServices.showRewardedAd(gameID:purpose:)` の呼び出し（= `reward_ad` の計測。#500）
/// 3. **局ガード** — 広告を出す前と後で局が入れ替わっていないかの照合
/// 4. 視聴しなかった・読み込めなかったときのアラート
/// 5. 視聴は完了したのに適用できなかったときのアラート
///
/// 3 を**呼び出しの形として要求する**のがこの型の主目的。`request` は `guardedBy` を
/// 省略できないので、新しい救済を足すときに照合の有無を無自覚に素通りさせられない。
/// 広告のロード中は画面が操作できるため、ここが抜けると「はじめから」「新規ゲーム」で
/// 入れ替わった局へ報酬が乗る（#480 → #509 → #511 と 3 回続けて同じ穴が空いている）。
@MainActor
@Observable
public final class RewardedRescue {

    /// 視聴しなかった・読み込めなかったときの本文。**全ゲーム共通の 1 文**。
    ///
    /// 「広告を見たのに何も起きない」経路を作らないのがリワード広告の契約なので、
    /// 失敗の知らせだけはどのゲームでも同じ言い回しにする。タイトル（何ができなかったか）は
    /// ゲームごとに違うので `rewardedRescueAlerts(_:notEarned:unavailable:)` で受け取る。
    public static let notEarnedMessage =
        "広告を最後まで視聴しなかったか、広告を読み込めませんでした。\nもう一度お試しください。"

    /// 広告のロード〜視聴中。救済ボタンの `disabled` に使う。
    public private(set) var isWatching = false
    /// 視聴しなかった・読み込めなかった。
    public var showsNotEarned = false
    /// 視聴は完了したが、局面が変わっていて適用できなかった。
    public var showsUnavailable = false

    public init() {}

    /// 広告を出し、視聴完了したときだけ `grant` を呼ぶ。
    ///
    /// - Parameters:
    ///   - guardedBy: 局ガードの有無。**省略できない**（この型の要）。
    ///   - whenNotEarned: 視聴しなかったときに、アラートに加えて戻す必要のある状態がある場合に渡す
    ///     （神経衰弱は待ったの確認中に自動めくりを止めているので、ここで再開する）。
    ///   - grant: 報酬の適用。適用できなければ false を返す（→ `showsUnavailable`）。
    ///     照合を持たない面は、適用したうえで true を返す。
    public func request(
        _ services: GameServices,
        gameID: String,
        purpose: RewardPurpose,
        guardedBy: RewardGuard,
        whenNotEarned: (@MainActor () -> Void)? = nil,
        grant: @escaping @MainActor () -> Bool
    ) {
        // 広告のロード〜表示中の連打で 2 本目が失敗し、誤ってアラートが出るのを防ぐ。
        guard !isWatching else { return }
        isWatching = true
        // 画面の世代（#653）。`guardedBy` の局ガードは Model の中だけを見るので、**Model ごと
        // 入れ替わる経路**（ロード中にハブへ戻って開き直す）は弾けない。ここで押さえる。
        let generation = services.screenGeneration.current
        Task {
            if await services.showRewardedAd(gameID: gameID, purpose: purpose) {
                if services.screenGeneration.current != generation {
                    // ハブへ戻られている。この救済が狙っていた画面はもう無く、`grant` を呼ぶと
                    // 捨てられた Model が `PlayLog` や中断データを新しい対局の裏で書き換える。
                    // アラートも出さない（出す先の画面が無いので、次に開いたときに
                    // 身に覚えのないアラートが出るだけになる）。
                } else if !grant() {
                    // 広告を見たのに適用できなかったときは、黙って終わらせない（対価が無い状態を作らない）。
                    // 照合を持たない面（`unchecked`）は false を返さないのが契約。返ってきたら
                    // 宣言と実装が食い違っている（照合を足したのに宣言が古い）。
                    assert(guardedBy.isChecked, "\(gameID) は照合していない宣言なのに grant が false を返した")
                    showsUnavailable = true
                }
            } else {
                showsNotEarned = true
                whenNotEarned?()
            }
            isWatching = false
        }
    }
}

public extension RewardedRescue {
    /// 広告の表示から報酬の適用までを**モデルが 1 本の非同期メソッドで持っている**面で使う（#526）。
    ///
    /// チップ切れ復活（#499）・トビ復活（#338）は、救済できる状態かの判定・広告・適用が
    /// モデルの中で 1 つに繋がっていて分けられない。この形で View に残るのは連打ガードと
    /// 失敗アラートだけなので、共通側が受け持つのもそこだけになる。
    ///
    /// 局ガード（`RewardGuard`）を取らないのは、照合の材料（残高・持ち点）がモデルの中にあり、
    /// `perform` が false を返す形で既に効いているため。計測（`reward_ad`）はモデルが通る
    /// `GameServices.showRewardedAd(gameID:purpose:)` 側で付く。
    ///
    /// - Parameters:
    ///   - perform: 広告を出して報酬を適用するモデルのメソッド。
    ///     視聴しなかった・救済できる状態でなかったときは false を返す。
    ///   - whenGranted: 適用できたあとの続き（麻雀は復活後に CPU の手番を進める）。
    ///     **連打ガードを解いてから**走らせるので、ここが長引いてもボタンは塞がらない。
    func requestHandledByModel(
        _ perform: @escaping @MainActor () async -> Bool,
        whenGranted: (@MainActor () async -> Void)? = nil
    ) {
        guard !isWatching else { return }
        isWatching = true
        Task {
            let applied = await perform()
            isWatching = false
            if applied {
                await whenGranted?()
            } else {
                showsNotEarned = true
            }
        }
    }

    /// `requestHandledByModel(_:whenGranted:)` のうち、**見終えたのに適用できなかった**ことを
    /// 視聴しなかったことと分けて知らせる形（#727）。
    ///
    /// `Bool` の形では、広告のあいだに局が入れ替わって適用しなかったときも
    /// 「広告を最後まで視聴しなかったか…」のアラートが出てしまう。`.unavailable` は
    /// `showsUnavailable` を立てるので、この形を呼ぶ面は `rewardedRescueAlerts(unavailable:)` を
    /// 必ず渡す（`RewardGuardCallSiteTests` がファイル単位で数を突き合わせる）。
    func requestHandledByModel(
        withOutcome perform: @escaping @MainActor () async -> RewardedModelOutcome,
        whenGranted: (@MainActor () async -> Void)? = nil
    ) {
        guard !isWatching else { return }
        isWatching = true
        Task {
            let outcome = await perform()
            isWatching = false
            switch outcome {
            case .granted:     await whenGranted?()
            case .notEarned:   showsNotEarned = true
            case .unavailable: showsUnavailable = true
            }
        }
    }
}

/// 広告ごと抱えているモデルの救済が、どう終わったか（#727）。
public enum RewardedModelOutcome: Sendable, Equatable {
    /// 視聴を完了し、報酬を適用した。
    case granted
    /// 視聴しなかった・読み込めなかった（→ `showsNotEarned`）。
    case notEarned
    /// 救済できる状態ではなかった、または視聴のあいだに局が入れ替わって適用しなかった
    /// （→ `showsUnavailable`）。
    case unavailable
}

/// 広告の前後で局が入れ替わっていないことを、どうやって確かめるか（#526）。
///
/// 値そのものは実行時に何もしない。**書かせること**が目的の型で、
/// `unchecked` を選んだ面の数はソース走査テスト（`RewardGuardTests`）が固定している。
/// 新しい面で照合を省くと、そこで初めてテストが赤くなる。
public enum RewardGuard: Sendable {
    /// `grant` が局を照合し、適用できなければ false を返す。
    /// 何を照合するか（局の通し番号・対象のマスなど）は各モデルが持つ。
    case checkedByGrant
    /// **照合していない**面。局が入れ替わったところへ報酬が乗る余地が残っている。
    /// なぜ現状それで済んでいるかを `note` に書く。
    case unchecked(note: String)

    /// 照合すると宣言しているか。`grant` が false を返せるのはこちらだけ。
    public var isChecked: Bool {
        if case .checkedByGrant = self { return true }
        return false
    }
}

// MARK: - 広告コンティニューの幕

/// 決着した盤に被せる「広告を見て続ける」の幕（#829）。
///
/// 2048・ブロックならべ・ナンプレに、黒の幕・見出し・救済ボタン・二次ボタンという同じ組み方が
/// 写しで置かれていた（#729 の局ガードのコメントごと）。救済ボタンは**局ガード付きの `request` を
/// ここで必ず通す**ので、寄せた面では照合の書き忘れが構造的に起きない（`RewardGuardCallSiteTests`）。
///
/// ゲームごとに違う見た目（見出しの大きさ・幕の角丸・見出しの下の一行・内側の余白）だけを引数で受ける。
/// 失敗のアラート（`rewardedRescueAlerts`）は画面全体に付くものなので、呼び出し側に残す。
public struct RewardedContinueOverlay<Detail: View>: View {
    private let title: LocalizedStringKey
    private let titleFont: Font
    private let cornerRadius: CGFloat
    private let contentPadding: CGFloat
    private let detail: Detail
    private let rescueLabel: LocalizedStringKey
    private let canContinue: Bool
    private let continueRescue: RewardedRescue
    private let services: GameServices
    private let gameID: String
    private let serial: () -> Int
    private let grant: (Int) -> Bool
    private let secondaryTitle: LocalizedStringKey
    private let secondaryAction: () -> Void

    /// - Parameters:
    ///   - detail: 見出しの下の一行（記録の表示や、広告で何が戻るかの説明）。
    ///   - canContinue: 救済ボタンを出すか。1 局 1 回のゲームは使ったら false にする。
    ///   - serial: 局の通し番号。**タップした瞬間に**読んで控え、広告の後に `grant` へ渡す。
    ///   - grant: 控えた通し番号の局へコンティニューを適用する。局が入れ替わっていたら false を返す。
    ///   - secondaryTitle: 救済を選ばないときのボタン（「もう一度」「諦めて答えを見る」）。
    public init(
        title: LocalizedStringKey,
        titleFont: Font = .title2.bold(),
        cornerRadius: CGFloat = 8,
        contentPadding: CGFloat = 0,
        detail: Detail,
        rescueLabel: LocalizedStringKey,
        canContinue: Bool = true,
        rescue: RewardedRescue,
        services: GameServices,
        gameID: String,
        serial: @autoclosure @escaping () -> Int,
        grant: @escaping (Int) -> Bool,
        secondaryTitle: LocalizedStringKey,
        secondaryAction: @escaping () -> Void
    ) {
        self.title = title
        self.titleFont = titleFont
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.detail = detail
        self.rescueLabel = rescueLabel
        self.canContinue = canContinue
        self.continueRescue = rescue
        self.services = services
        self.gameID = gameID
        self.serial = serial
        self.grant = grant
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.black.opacity(0.55))
            VStack(spacing: 12) {
                Text(title).font(titleFont).foregroundStyle(.white)
                detail
                if canContinue {
                    Button {
                        // 視聴完了（報酬獲得）したときだけコンティニューを許可する。どの局に対するものかを
                        // 広告を出す前に控え、ロード中に入れ替わった局へは乗せない（#729）。
                        let game = serial()
                        continueRescue.request(
                            services, gameID: gameID, purpose: .continue,
                            guardedBy: .checkedByGrant
                        ) {
                            grant(game)
                        }
                    } label: {
                        Label(rescueLabel, systemImage: "play.rectangle.fill")
                            .foregroundStyle(Theme.onAccent)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Fill.coral)
                    .disabled(continueRescue.isWatching)
                }
                // 視聴中に「もう一度」「諦めて答えを見る」を押すと局が入れ替わり、見終えた広告が
                // `grant` の局照合で弾かれて見損になる（#911。マインスイーパーの #816 と同型）。
                Button(secondaryTitle) { secondaryAction() }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .disabled(continueRescue.isWatching)
            }
            .padding(contentPadding)
        }
    }
}

/// 視聴は完了したのに適用できなかったときのアラート（#526）。
///
/// 本文が「見ているあいだに何が起きたか」「手持ちはどうなったか」をゲームごとに説明するため、
/// 共通化できるのは出し方だけで文言は各ゲームが持つ。
public struct RewardUnavailableAlert {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

public extension View {
    /// リワード広告の失敗を伝えるアラートを取り付ける（#526）。
    ///
    /// - Parameters:
    ///   - notEarned: 視聴しなかったときのタイトル。本文は `RewardedRescue.notEarnedMessage` 固定。
    ///   - unavailable: 視聴は完了したのに適用できなかったときのアラート。
    ///     `RewardGuard.unchecked` の面では起こらないので nil でよい。
    func rewardedRescueAlerts(
        _ rescue: RewardedRescue,
        notEarned: String,
        unavailable: RewardUnavailableAlert? = nil
    ) -> some View {
        modifier(RewardedRescueAlerts(rescue: rescue, notEarned: notEarned, unavailable: unavailable))
    }
}

private struct RewardedRescueAlerts: ViewModifier {
    @Bindable var rescue: RewardedRescue
    let notEarned: String
    let unavailable: RewardUnavailableAlert?

    func body(content: Content) -> some View {
        content
            .alert(notEarned, isPresented: $rescue.showsNotEarned) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(RewardedRescue.notEarnedMessage)
            }
            // 適用できなかったときのアラートを持たない面（`RewardGuard.unchecked`）では、
            // 万一 `showsUnavailable` が立っても中身の無いアラートを出さない。
            .alert(
                unavailable?.title ?? "",
                isPresented: unavailable == nil ? .constant(false) : $rescue.showsUnavailable
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(unavailable?.message ?? "")
            }
    }
}
