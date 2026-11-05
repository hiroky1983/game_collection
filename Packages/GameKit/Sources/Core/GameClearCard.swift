import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// クリアのカードから共有する中身（ねこさがしのデイリー pt の共有・#3237）。
/// 共有シートに出すのは文と画像。URL（App Store）は文の末尾に添える。
public struct ClearShare {
    /// 共有する短い文（URL は含めない）。
    public let message: String
    /// 共有する画像を描く（共有ボタンが出たときに 1 回だけ呼ぶ）。描けなければ nil で、文だけを共有する。
    public let makeImage: @MainActor () -> CGImage?

    public init(message: String, makeImage: @escaping @MainActor () -> CGImage?) {
        self.message = message
        self.makeImage = makeImage
    }
}

/// 共有シートへ渡す PNG 画像。
public struct ClearShareImage: Transferable {
    let data: Data
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
    }

    public static func png(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}

/// クリアのカードの共有ボタン。`RecordShareContext`（ハブが配る）があるときだけ出る。押すと `share_tap`（自己ベストの共有と同じ）。
struct ClearShareButton: View {
    let share: ClearShare
    let context: RecordShareContext
    @State private var rendered: (data: Data, image: CGImage)?
    @State private var didRender = false

    private var text: String { "\(share.message)\n\(context.url.absoluteString)" }

    var body: some View {
        Group {
            if let rendered {
                ShareLink(item: ClearShareImage(data: rendered.data), message: Text(verbatim: text),
                          preview: SharePreview(share.message, image: Image(decorative: rendered.image, scale: 1))) { label }
            } else {
                ShareLink(item: context.url, subject: Text(tr("あそびば")), message: Text(verbatim: share.message)) { label }
            }
        }
        .buttonStyle(.pop)
        // 画像を描き終えるまでは押せない（描く前に押すと画像の無い共有になる）。描けなかったときは文だけで共有する。
        .disabled(!didRender)
        .simultaneousGesture(TapGesture().onEnded { context.didTap() })
        .accessibilityLabel(tr("今日の pt をシェア"))
        .task(id: share.message) {
            guard !didRender else { return }
            didRender = true
            if let image = share.makeImage(), let data = ClearShareImage.png(image) { rendered = (data, image) }
        }
    }

    private var label: some View {
        Image(systemName: "square.and.arrow.up")
            .scaledFont(16, weight: .bold, maxScale: 1.5)
            .foregroundStyle(Theme.coralText)
            .frame(minWidth: 44, minHeight: 44)
            .background(Capsule().stroke(Theme.coralText, lineWidth: 2))
            .contentShape(Rectangle())
    }
}

/// ソリティア系・ナンプレ・麻雀ソリティアのクリアを盤に重ねて大きく示すカード（#1755）。
///
/// 見た目は `BoardGameResultCard`（オセロ手本の結果カード）と揃え、**5 本で完全に同じ**にする。
/// 載せるのは見出しと各ゲームが持つ記録の行（タイム・手数など）だけ。終局後のボタン（もう一回など）は
/// 盤の下の既存部品（`GameControlArea` / `GameReplayBar`）のままで、ここには置かない。
/// `onClose` があれば「盤を見る」で閉じて盤面を見返せる（麻雀ソリティアは盤が空なので閉じる口を持たない）。
public struct GameClearCard: View {
    private let title: String
    private let details: [String]
    private let stats: [Stat]
    private let record: RecordResult?
    private let onClose: (() -> Void)?
    private let primaryAction: PrimaryAction?
    private let share: ClearShare?
    private let xShareOffer: XShareOffer?
    private let xShareGranted: Bool
    @Environment(\.recordShare) private var recordShare

    /// 「盤を見る」の上に置く、次へ進む動線（ねこさがしのステージの「次のステージへ」・#3048）。無ければ出さない。
    public struct PrimaryAction {
        let title: String
        let hint: String
        let action: () -> Void

        public init(title: String, hint: String, action: @escaping () -> Void) {
            self.title = title
            self.hint = hint
            self.action = action
        }
    }

    /// 詳細の文の下に 1 行で並べる、アイコン付きの数（ねこさがしのライフ・ヒント・餌・#3329）。
    public struct Stat: Equatable {
        public let systemImage: String
        public let text: String

        public init(systemImage: String, text: String) {
            self.systemImage = systemImage
            self.text = text
        }
    }

    /// - Parameter stats: 詳細の下に、アイコン付きで 1 行に並べる数（入りきらない文字サイズでは縦に積む）。
    /// - Parameter record: 自己ベストの行に使う記録（15パズル・つなぎ。無ければ行を出さない・#3059）。
    public init(title: String? = nil, details: [String] = [], stats: [Stat] = [], record: RecordResult? = nil,
                primaryAction: PrimaryAction? = nil, share: ClearShare? = nil,
                xShareOffer: XShareOffer? = nil, xShareGranted: Bool = false, onClose: (() -> Void)? = nil) {
        self.title = title ?? tr("クリア！")
        self.details = details
        self.stats = stats
        self.record = record
        self.primaryAction = primaryAction
        self.share = share
        self.xShareOffer = xShareOffer
        self.xShareGranted = xShareGranted
        self.onClose = onClose
    }

    private var spokenDetails: [String] { details + stats.map(\.text) }

    /// VoiceOver が 1 回で読む文。見出しの「！」は読み上げでは落とす。
    public static func accessibilityLabel(title: String, details: [String]) -> String {
        ([title.replacingOccurrences(of: "！", with: "").replacingOccurrences(of: "!", with: "")] + details).joined(separator: tr("。"))  // i18n-keep: 見出しから「！」「!」を外すだけ
    }

    public var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .scaledFont(40, maxScale: 1.2)
                    .foregroundStyle(Theme.yellowText)
                Text(title)
                    .themeBody(24, weight: .bold, maxScale: 1.5)
                    .foregroundStyle(Theme.tealText)
                ForEach(details, id: \.self) { line in
                    Text(line)
                        .themeBody(15, weight: .semibold, maxScale: 1.5)
                        .foregroundStyle(Theme.ink)
                }
                if !stats.isEmpty { statsRow }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityLabel(title: title, details: spokenDetails))
            // 共有ボタンを持つので、読み上げの塊の外に置く（`BoardGameResultCard` と同じ）。
            if record != nil { RecordLabel(record) }
            if let primaryAction {
                Button(action: primaryAction.action) {
                    Text(primaryAction.title)
                        .themeBody(15, weight: .bold, maxScale: 1.5)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Theme.Fill.coral))
                }
                .accessibilityHint(primaryAction.hint)
            }
            if let share, let recordShare {
                // 読み上げの塊の外（共有ボタンはカードの中の独立した操作）。
                ClearShareButton(share: share, context: recordShare)
            }
            // 「X でポストして特典をもらう」の提案（#3359）。特典を付けるゲームの、条件を満たした結果画面だけ。
            if let xShareOffer { XShareOfferView(xShareOffer, granted: xShareGranted) }
            if let onClose {
                Button(action: onClose) {
                    Text(tr("盤を見る"))
                        .themeBody(15, weight: .bold, maxScale: 1.5)
                        .foregroundStyle(primaryAction == nil ? Theme.onAccent : Theme.coralText)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        // 次へ進む動線があるときは、そちらを塗りにして「盤を見る」は枠だけにする（結果カードの副ボタンと同じ形）。
                        .background {
                            if primaryAction == nil {
                                Capsule().fill(Theme.Fill.coral)
                            } else {
                                Capsule().stroke(Theme.coralText, lineWidth: 2)
                            }
                        }
                }
                .accessibilityHint(tr("クリアの表示を閉じて盤面を見返します"))
            }
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .playStreakCaption()
        .padding(16)
        .resultCardScrollsWhenTall()
        .announcesResultAppearance(Self.accessibilityLabel(title: title, details: spokenDetails))
    }

    /// アイコン付きの数。1 行に収まらない文字サイズでは縦に積む。
    private var statsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { statItems }
            VStack(spacing: 4) { statItems }
        }
    }

    private var statItems: some View {
        ForEach(stats, id: \.text) { stat in
            Label {
                Text(stat.text).themeBody(15, weight: .semibold, maxScale: 1.5)
            } icon: {
                Image(systemName: stat.systemImage).scaledFont(15, weight: .bold, maxScale: 1.5)
            }
            .foregroundStyle(Theme.ink)
            .fixedSize()
        }
    }
}

/// `View.gameClearCard` の本体。「盤を見る」で閉じたかどうかをここが持つので、呼び出し側は
/// `isPresented`（クリアしたか）だけを渡せばよい。`isPresented` が偽に戻ったら（新しい局）閉じた記憶を捨てる。
private struct GameClearCardModifier: ViewModifier {
    let isPresented: Bool
    let title: String?
    let details: [String]
    let record: RecordResult?
    let primaryAction: GameClearCard.PrimaryAction?
    @State private var dismissed = false

    func body(content: Content) -> some View {
        content.overlay {
            // `.gameAnimation` は残り続ける親（この `ZStack`）に置く（`boardGameResultCard` と同じ・#195）。
            ZStack {
                if isPresented && !dismissed {
                    ZStack {
                        Color.black.opacity(0.45)
                        GameClearCard(title: title, details: details, record: record, primaryAction: primaryAction) { dismissed = true }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
                    .transition(.opacity)
                }
            }
            .gameAnimation(.easeOut(duration: 0.25), value: isPresented && !dismissed)
        }
        .onChange(of: isPresented) { _, now in
            if !now { dismissed = false }
        }
    }
}

public extension View {
    /// 盤の上にクリアカードを重ねる（#1755）。`isPresented` が真のあいだ出し、「盤を見る」で閉じられる。
    /// `record` は自己ベストの行、`primaryAction` は「盤を見る」の上に置く動線（15パズル・つなぎの「もう一回」・#3059）。
    func gameClearCard(isPresented: Bool, title: String? = nil, details: [String] = [], record: RecordResult? = nil,
                       primaryAction: GameClearCard.PrimaryAction? = nil) -> some View {
        modifier(GameClearCardModifier(isPresented: isPresented, title: title, details: details,
                                       record: record, primaryAction: primaryAction))
    }
}
