import SwiftUI
import Core

/// 札 1 枚の絵柄（#495・#2188）。
///
/// 図案は `HanafudaCardImages` の画像（Codex の画像生成が文章の指示だけで描いた伝統図柄）を札いっぱいに敷き、
/// その上に「月と種別の帯」（#602）を `Canvas` で重ねる。帯・角丸・暗転・強調は図形描画だった頃
/// （v1.1.11 まで。鶴が楕円＋線、幕が赤白の縞で「全部同じに見える」と指摘された）と同じ。
/// 画像は上端 15% に主役を置かないよう描かせているので、帯に食われる部品が出ない。
///
/// 既存メーカーの札は一切参照しておらず、公有の伝統モチーフを文章で指示して描かせたオリジナル図案。
public struct HanafudaCardFace: View {
    public let card: HanafudaCard
    /// 取れない・選べない札を暗く落とす。
    public let isDimmed: Bool
    /// 選択中・合わせ先候補の強調。
    public let isHighlighted: Bool

    public init(card: HanafudaCard, isDimmed: Bool = false, isHighlighted: Bool = false) {
        self.card = card
        self.isDimmed = isDimmed
        self.isHighlighted = isHighlighted
    }

    public var body: some View {
        GeometryReader { geo in
            let corner = geo.size.width * 0.12
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(CardStyle.faceFill)
                if let image = HanafudaCardImages.image(for: card) {
                    // 画像は札と同じ 2:3 なので、札の枠いっぱいに敷けば帯の下に図案がそのまま収まる。
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                Canvas { context, size in
                    HanafudaCardFace.drawBand(card, in: &context, rect: CGRect(origin: .zero, size: size))
                }
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
        .aspectRatio(1 / HanafudaCardArt.aspectRatio, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(HanafudaSpeech.label(for: card))
    }

    // MARK: - 帯と図案の領域

    /// 上端の帯（月と種別）が占める高さの割合（#602）。
    static let bandRatio: Double = 0.15

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
    static func drawBand(_ card: HanafudaCard, in ctx: inout GraphicsContext, rect: CGRect) {
        let backgroundHex = HanafudaCardArt.kindHex(for: card)
        let band = bandRect(in: rect)
        ctx.fill(Path(band), with: .color(Color(hex: backgroundHex)))
        let label = Color(hex: HanafudaCardArt.bandLabelHex(on: backgroundHex))
        // 帯の高さに収まる大きさにする。下限を設けて逃がすと、小さく描いたときに文字だけが
        // 帯からはみ出して図案に被る。
        let size = min(rect.width * 0.21, band.height * 0.82)
        func text(_ string: String) -> Text {
            Text(verbatim: string)
                .font(.system(size: size, weight: .bold, design: .rounded)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                .foregroundStyle(label)
        }
        let inset = band.width * 0.07
        ctx.draw(text("\(card.month)"),
                 at: CGPoint(x: band.minX + inset, y: band.midY), anchor: .leading)
        ctx.draw(text(card.kind.badgeLabel),
                 at: CGPoint(x: band.maxX - inset, y: band.midY), anchor: .trailing)
    }
}
