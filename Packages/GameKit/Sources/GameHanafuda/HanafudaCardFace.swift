import SwiftUI
import Core

/// 札 1 枚の絵柄（#495・#2188）。
///
/// 図案は `HanafudaCardImages` の画像（Codex の画像生成が文章の指示だけで描いた伝統図柄）を札いっぱいに敷き、
/// その上に「月と種別の帯」（#602）を重ねる。帯・角丸・暗転・強調は図形描画だった頃
/// （v1.1.11 まで。鶴が楕円＋線、幕が赤白の縞で「全部同じに見える」と指摘された）と同じ。
/// 画像は上端 20% に主役を置かないよう描かせているので、帯に食われる部品が出ない。
///
/// 既存メーカーの札は一切参照しておらず、公有の伝統モチーフを文章で指示して描かせたオリジナル図案。
public struct HanafudaCardFace: View {
    public let card: HanafudaCard
    /// 取れない・選べない札を暗く落とす。
    public let isDimmed: Bool
    /// 選択中・合わせ先候補の強調。
    public let isHighlighted: Bool
    /// 帯の右の種別の文字を出すか。取り札のように札を横に重ねる所では、重なる側の札が隠す札の
    /// 文字を欠けさせるので、最前面の 1 枚以外は消して月の数字だけにする（帯の色は種別を示し続ける・#2336）。
    public let showsKindLabel: Bool
    /// 呼び出し側ですでに幅が決まっているとき（図入りの遊び方・#2044 / #2827）に渡す。渡すと内部の
    /// `GeometryReader` を使わず、この幅で直接描く。`TabView` の「はじめての遊び方」（#2827）でページを
    /// めくるたびに `GeometryReader` を持つ札を何枚も再計測するのが重く、花札こいこいで画面が固まって
    /// クラッシュしていた（#2905）。トランプ（`PlayingCardFace`）は元から固定 pt で組んでおり
    /// `GeometryReader` を持たないので、幅があらかじめ分かる所は同じ作法に合わせる。
    /// 盤面（`LazyVGrid` で幅がレイアウトでしか決まらない手札・場・取り札）は今までどおり `nil` で
    /// `GeometryReader` に任せる。
    public let fixedWidth: CGFloat?

    public init(card: HanafudaCard, isDimmed: Bool = false, isHighlighted: Bool = false,
                showsKindLabel: Bool = true, fixedWidth: CGFloat? = nil) {
        self.showsKindLabel = showsKindLabel
        self.card = card
        self.isDimmed = isDimmed
        self.isHighlighted = isHighlighted
        self.fixedWidth = fixedWidth
    }

    public var body: some View {
        Group {
            if let fixedWidth {
                face(width: fixedWidth)
                    .frame(width: fixedWidth, height: fixedWidth * HanafudaCardArt.aspectRatio)
            } else {
                GeometryReader { geo in
                    face(width: geo.size.width)
                }
                .aspectRatio(1 / HanafudaCardArt.aspectRatio, contentMode: .fit)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(HanafudaSpeech.label(for: card))
    }

    @ViewBuilder
    private func face(width: CGFloat) -> some View {
        let height = width * HanafudaCardArt.aspectRatio
        let corner = width * 0.12
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(CardStyle.faceFill)
            if let image = HanafudaCardImages.image(for: card) {
                // 画像は札と同じ 2:3 なので、札の枠いっぱいに敷けば帯の下に図案がそのまま収まる。
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
            }
            band(width: width, height: height)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(HanafudaCardArt.ink.opacity(0.35), lineWidth: 1)
            if isHighlighted {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Theme.coral, lineWidth: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .opacity(isDimmed ? 0.45 : 1)
    }

    // MARK: - 帯と図案の領域

    /// 上端の帯（月と種別）が占める高さの割合（#602。#2336 で 15% → 20%。取り札の小さい札でも月と種別の文字が読めるように高くした）。
    static let bandRatio: Double = 0.20

    /// 帯を敷く領域。
    static func bandRect(in rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * bandRatio)
    }

    /// 図案の主役が収まる領域。画像自体は札いっぱいに敷くが、主役（鶴の頭・傘の天辺・月の上辺）は
    /// ここより上に置かないよう描かせている（`HanafudaCardImageTests` が 48 枚の上端を検査する）。
    static func artRect(in rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX, y: rect.minY + rect.height * bandRatio,
            width: rect.width, height: rect.height * (1 - bandRatio)
        )
    }

    // MARK: 帯（月と種別）

    /// 上端に「月」と「種別」を並べた帯を敷く（#602）。
    ///
    /// **こいこいで打つ手を決めるのに要る情報はこの 2 つだけ**で、合わせは月でしか起きず、
    /// 役は種別の枚数で決まる。どちらも図案からしか読めない状態では、鶴と鶯の描き分けを
    /// 知らない人が光札とタネ札を区別できない（会長 QA・2026-09-10）。
    /// 帯の色そのものが種別を表すので、取り札の帯のように文字が潰れる小ささでも読み取れる。
    ///
    /// 文字は `Canvas` の `draw(Text)` ではなく普通の `Text` で置く（#2905）。`Canvas` は描き直すたびに
    /// 文字の組版（和文の代替フォント探しまで）をやり直すので、「はじめての遊び方」のページ送りで
    /// 札の描き直しが続くと主スレッドが 10 秒埋まり、監視（0x8BADF00D）に落とされていた。
    private func band(width: CGFloat, height: CGFloat) -> some View {
        let backgroundHex = HanafudaCardArt.kindHex(for: card)
        let bandHeight = height * Self.bandRatio
        let label = Color(hex: HanafudaCardArt.bandLabelHex(on: backgroundHex))
        // 帯の高さに収まる大きさにする。下限を設けて逃がすと、小さく描いたときに文字だけが
        // 帯からはみ出して図案に被る。
        let size = Self.bandFontSize(width: width, bandHeight: bandHeight)
        return VStack(spacing: 0) {
            ZStack {
                Rectangle().fill(Color(hex: backgroundHex))
                HStack(spacing: 0) {
                    Text(verbatim: "\(card.month)").fixedSize()
                    Spacer(minLength: 0)
                    if showsKindLabel {
                        Text(verbatim: card.kind.badgeLabel).fixedSize()
                    }
                }
                .font(.system(size: size, weight: .bold, design: .rounded)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                .foregroundStyle(label)
                .padding(.horizontal, width * 0.05)
            }
            .frame(width: width, height: bandHeight)
            Spacer(minLength: 0)
        }
        .frame(width: width, height: height)
    }

    /// 帯の文字の大きさ。札の幅の 30% と帯の高さの 85% の小さいほう。
    static func bandFontSize(width: CGFloat, bandHeight: CGFloat) -> CGFloat {
        min(width * 0.30, bandHeight * 0.85)
    }
}
