import SwiftUI
import Core
import CoreEngine
import Observation

// MARK: - 画面に依らない部分

/// 今日のランキング画面（#3236）に出す中身。Game Center の順位表を、画面に出す形へ整えたもの。
struct CatPuzzleRankingContent: Equatable {
    /// 上位の行（順位順）。自分が上位の外なら、末尾に自分の行を足す。
    let rows: [GameCenterBoardRow]
    let myRank: Int?
    let myScore: Int?
    /// 今日の参加人数。取れなければ 0。
    let participants: Int
    /// 昨日の最終順位（前回の回に参加していない・取れなかったときは nil）。
    let yesterdayRank: Int?
    /// 友だちの順位（自分を含む）。友だちがいない・許可が無い・取れなかったときは空で、欄を出さない。
    let friends: [GameCenterBoardRow]

    /// 一覧の件数に数える最大。上位 20 人まで読む。
    static let topCount = 20

    init(board: GameCenterBoard, friends: [GameCenterBoardRow]) {
        var rows = board.rows
        if !rows.contains(where: \.isMe), let rank = board.myRank, let score = board.myScore {
            rows.append(GameCenterBoardRow(id: "me", name: "", score: score, rank: rank, isMe: true))
        }
        self.rows = rows
        myRank = board.myRank
        myScore = board.myScore
        participants = board.participants
        yesterdayRank = board.lastWeekRank
        // 友だちが自分ひとりだけなら、並べる意味が無いので出さない。
        self.friends = friends.contains { !$0.isMe } ? friends : []
    }
}

/// 今日のランキング画面の状態。
enum CatPuzzleRankingState: Equatable {
    /// 読んでいる最中。
    case loading
    /// イベントの期間外（開始前・終了後）。画面には順位を出さない。
    case outOfPeriod
    /// Game Center にサインインしていない。
    case signedOut
    /// 読めなかった（オフライン・Game Center の不調・リーダーボードが未登録）。
    case failed
    case ready(CatPuzzleRankingContent)
}

/// 今日のランキング画面のモデル（#3236）。Game Center への問い合わせは closure で受け、テストでは差し替える。
@MainActor
@Observable
final class CatPuzzleRankingModel {
    private(set) var state: CatPuzzleRankingState = .loading

    @ObservationIgnored private let isSignedIn: @MainActor () -> Bool
    @ObservationIgnored private let loadBoard: @MainActor () async -> GameCenterBoard?
    @ObservationIgnored private let loadFriends: @MainActor () async -> [GameCenterBoardRow]
    @ObservationIgnored private let now: () -> Date

    init(isSignedIn: @escaping @MainActor () -> Bool,
         loadBoard: @escaping @MainActor () async -> GameCenterBoard?,
         loadFriends: @escaping @MainActor () async -> [GameCenterBoardRow],
         now: @escaping () -> Date = { Date() }) {
        self.isSignedIn = isSignedIn
        self.loadBoard = loadBoard
        self.loadFriends = loadFriends
        self.now = now
    }

    /// 本番の入口。`reporter` が無い（Game Center を持たない環境）ときは未サインイン扱い。
    convenience init(reporter: GameCenterReporter?, now: @escaping () -> Date = { Date() }) {
        let gameID = CatPuzzleModel.gameID
        let leaderboardID = GameCenterLeaderboard.catPuzzleEvent
        self.init(
            isSignedIn: { reporter?.isSignedIn ?? false },
            loadBoard: {
                await reporter?.loadWeeklyBoard(gameID: gameID, leaderboardID: leaderboardID,
                                                topCount: CatPuzzleRankingContent.topCount, includesLastWeek: true)
            },
            loadFriends: {
                await reporter?.loadFriendRows(gameID: gameID, leaderboardID: leaderboardID,
                                               topCount: CatPuzzleRankingContent.topCount) ?? []
            },
            now: now
        )
    }

    /// 順位を読み直す。期間外・未サインインのときは問い合わせない。
    func load() async {
        guard CatPuzzleEvent.isActive(now: now()) else { state = .outOfPeriod; return }
        guard isSignedIn() else { state = .signedOut; return }
        state = .loading
        async let board = loadBoard()
        async let friends = loadFriends()
        let (loadedBoard, loadedFriends) = await (board, friends)
        guard !Task.isCancelled else { return }
        guard let loadedBoard else { state = .failed; return }
        let isStale = Self.isPastOccurrence(loadedBoard, now: now())
        state = .ready(CatPuzzleRankingContent(board: Self.today(loadedBoard, now: now()),
                                               friends: isStale ? [] : loadedFriends))
    }

    /// 読んだ表が前の回のもの（回の終わりを過ぎている）か。終わりが取れない表は今日のものとして扱う。
    static func isPastOccurrence(_ board: GameCenterBoard, now: Date) -> Bool {
        guard let end = board.end else { return false }
        return end <= now
    }

    /// 読んだ表が前の回のもの（回の終わりを過ぎている。日付が変わった直後に Game Center が前の回を返した）なら、
    /// 前の日の順位は今日のものとして出さず、「今日はまだ記録がない」表にする。
    static func today(_ board: GameCenterBoard, now: Date) -> GameCenterBoard {
        guard isPastOccurrence(board, now: now) else { return board }
        return GameCenterBoard(rows: [], myRank: nil, myScore: nil, participants: 0,
                               start: nil, end: nil, lastWeekRank: board.myRank, lastWeekStart: board.start)
    }
}

// MARK: - 画面

/// 今日のランキング（#3236）。Game Center の順位表を、アプリの画面の中で見せる。
/// 開始シートのイベントの欄から開く。見た目は結果カード・記録画面と同じ部品（`popCard`・`popBackground`）。
struct CatPuzzleRankingView: View {
    @State var model: CatPuzzleRankingModel
    /// Game Center 本体の画面を開く入口（未サインインのときはサインインの案内になる）。無ければボタンを出さない。
    let onOpenGameCenter: (@MainActor () -> Void)?
    let onClose: () -> Void

    /// iPad で横に伸びすぎない幅の上限（#3181 のゲーム画面と同じ値）。
    static let maxWidth: CGFloat = 560

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    switch model.state {
                    case .loading:
                        statusCard(icon: nil, text: tr("順位を読み込んでいます"))
                    case .outOfPeriod:
                        statusCard(icon: "calendar", text: tr("ランキングイベントの期間外です"))
                    case .signedOut:
                        statusCard(icon: "person.crop.circle.badge.exclamationmark",
                                   text: tr("Game Center にサインインすると、今日のランキングを見られます。サインインしなくても、あそびはすべてそのまま遊べます。"),
                                   actionTitle: onOpenGameCenter == nil ? nil : tr("サインインする")) { onOpenGameCenter?() }
                    case .failed:
                        statusCard(icon: "wifi.slash",
                                   text: tr("ランキングを取得できませんでした。通信状況を確かめて、もう一度お試しください"),
                                   actionTitle: tr("もう一度読み込む")) { Task { await model.load() } }
                    case .ready(let content):
                        CatPuzzleRankingBoard(content: content)
                    }
                    if case .ready = model.state, let onOpenGameCenter {
                        Button { onOpenGameCenter() } label: {
                            Text(tr("Game Center で見る"))
                                .themeBody(15)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered).controlSize(.large)
                    }
                    Text(tr("前日の上位 3 位には、翌日に特典をプレゼント（1 位はヒントと猫を教える、2 位は猫を教える、3 位はヒント）"))
                        .themeCaption(12).foregroundStyle(Theme.inkSubText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Text(tr("毎日 日本時間の 0 時に切り替わります。ランキングは予告なく終了する場合があります"))
                        .themeCaption(11).foregroundStyle(Theme.inkSubText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: Self.maxWidth)
                .padding(Theme.pad)
                .frame(maxWidth: .infinity)
            }
        }
        .popBackground()
        .task { await model.load() }
    }

    private var header: some View {
        HStack {
            Text(tr("今日のランキング")).themeTitle(20)
            Spacer(minLength: 8)
            Button(tr("閉じる")) { onClose() }
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 8)
    }

    private func statusCard(icon: String?, text: String, actionTitle: String? = nil,
                            action: @escaping () -> Void = {}) -> some View {
        VStack(spacing: 12) {
            if let icon {
                Image(systemName: icon).scaledFont(30, weight: .bold).foregroundStyle(Theme.inkSubText)
            } else {
                ProgressView()
            }
            Text(text).themeBody(14).foregroundStyle(Theme.inkSubText).multilineTextAlignment(.center)
            if let actionTitle {
                Button(action: action) {
                    Text(actionTitle).themeBody(15).padding(.horizontal, 12).frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .popCard()
        .accessibilityElement(children: .contain)
    }
}

/// 順位表の本体（読めたとき）。自分の順位・昨日の最終順位・上位・友だち。
struct CatPuzzleRankingBoard: View {
    let content: CatPuzzleRankingContent

    var body: some View {
        VStack(spacing: 14) {
            summary
            list(title: tr("上位"), rows: content.rows)
            if !content.friends.isEmpty {
                list(title: tr("友だち"), rows: content.friends)
            }
        }
    }

    /// 自分の順位と pt、昨日の最終順位。
    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let rank = content.myRank, let score = content.myScore {
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.rankText(rank, of: content.participants)).themeTitle(24).monospacedDigit()
                    Spacer(minLength: 8)
                    Text(tr("%lldpt", score)).themeBody(17).monospacedDigit()
                }
            } else {
                Text(tr("今日はまだ記録がありません。ステージをクリアして pt を貯めよう"))
                    .themeBody(14).foregroundStyle(Theme.inkSubText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let yesterday = content.yesterdayRank {
                Text(tr("昨日の最終順位 %lld位", yesterday))
                    .themeCaption(12).foregroundStyle(Theme.inkSubText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .popCard()
        .accessibilityElement(children: .combine)
    }

    private func list(title: String, rows: [GameCenterBoardRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).themeBody(13).foregroundStyle(Theme.inkSubText).padding(.bottom, 6)
            if rows.isEmpty {
                Text(tr("まだ誰も記録していません")).themeBody(14).foregroundStyle(Theme.inkSubText)
            }
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Text(tr("%lld位", row.rank)).themeBody(14).monospacedDigit()
                        .frame(minWidth: 44, alignment: .leading)
                    Text(Self.displayName(row)).themeBody(15).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(tr("%lldpt", row.score)).themeBody(15).monospacedDigit()
                }
                .padding(.vertical, 8)
                .fontWeight(row.isMe ? .heavy : .regular)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .popCard()
    }

    /// 「3位 / 120人」。人数が取れない（順位より少ない）ときは順位だけ。
    static func rankText(_ rank: Int, of participants: Int) -> String {
        participants >= rank ? tr("%1$lld位 / %2$lld人", rank, participants) : tr("%lld位", rank)
    }

    /// 表示名。空なら自分は「あなた」、他の人は「プレイヤー」。
    static func displayName(_ row: GameCenterBoardRow) -> String {
        row.name.isEmpty ? (row.isMe ? tr("あなた") : tr("プレイヤー")) : row.name
    }
}
