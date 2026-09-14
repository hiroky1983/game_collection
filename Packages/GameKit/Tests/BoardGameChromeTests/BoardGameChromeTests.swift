import Foundation
import SwiftUI
import Testing
@testable import Core

/// 盤ゲーム（将棋・チェス）の共通の枠（#530）。
///
/// 将棋とチェスに**同じ値・同じ順番**で書かれていたものを Core にまとめたので、
/// 「両方で同じでなければならない」という性質の検証もここに 1 つだけ置く。
/// 各ゲーム側のテストは「共通の実装に乗っていること」だけを見る
/// （`ShogiPieceLayerSourceTests` / `ChessBoardViewSourceTests`）。
@Suite("盤ゲームの共通の枠")
struct BoardGameMotionTests {

    @Test("持ち上げは駒の移動より速い（掴んだ手応えが遅れて見えない）")
    func liftIsFasterThanPieceMove() {
        #expect(BoardGameMotion.pieceLiftResponse < BoardGameMotion.pieceMoveResponse)
        // 秒の定数から `Animation` を組んでいること（定数だけ直しても演出が変わらない、を防ぐ）。
        #expect(BoardGameMotion.pieceLift
                == .spring(response: BoardGameMotion.pieceLiftResponse, dampingFraction: 0.7))
        // 持ち上げ量と拡大は「浮いたと分かる最小限」。隣のマスに被るほど大きくしない。
        #expect(BoardGameMotion.pieceLiftRatio > 0 && BoardGameMotion.pieceLiftRatio <= 0.2)
        #expect(BoardGameMotion.pieceLiftScale > 1 && BoardGameMotion.pieceLiftScale <= 1.15)
    }

    @Test("札の消える速さは駒の移動より短く、合図を出す時間は長い")
    func bannerDurationsBracketPieceMove() {
        // 札が長いと、成った駒が動き出したあとも札が被ったまま残る。
        #expect(BoardGameMotion.promotionPromptDuration < BoardGameMotion.pieceMoveResponse)
        #expect(BoardGameMotion.promotionPrompt
                == .easeOut(duration: BoardGameMotion.promotionPromptDuration))
        // 合図が短いと、王手を掛けた駒がまだ動いている最中に文字が消えて何が起きたか読めない。
        #expect(BoardGameMotion.checkBannerHold > BoardGameMotion.pieceMoveResponse)
        #expect(BoardGameMotion.checkBanner
                == .spring(response: BoardGameMotion.checkBannerResponse, dampingFraction: 0.65))
        #expect(BoardGameMotion.turnChange == .easeInOut(duration: BoardGameMotion.turnChangeDuration))
    }

    /// 白文字を載せる面なので、`Theme` の差し色（#220 で AA 未達）に戻してはいけない。
    @Test("王手の色は白文字と AA を満たす緋色のまま")
    func checkColorKeepsContrast() {
        #expect(BoardGameCheckColor.hex == 0xB3261E)
        #expect(BoardGameCheckColor.color == Color(hex: BoardGameCheckColor.hex))
    }
}

/// 盤の下の操作列のカプセル（オセロ・五目並べの「投了」「待った」・#711）。
@MainActor
@Suite("操作列のカプセルボタン")
struct BoardGameControlCapsuleStyleTests {

    @Test("当たり判定の下限は 44pt")
    func minTapTargetMeetsHIG() {
        #expect(BoardGameControlMetrics.minTapTarget >= 44)
    }

    /// 44pt は**ボタン自身の枠**に入れる。枠の外へはみ出させた当たり判定は、macOS のプローブで
    /// Button のクリックが反応しないと実測した（#711。verifier の指摘を受けて overlay 方式から変更）。
    @Test("ボタンの枠は縦横 44pt 以上")
    func buttonFrameMeetsTapTarget() throws {
        let styled = try Self.render(Self.styledButton(enabled: true))
        #expect(CGFloat(styled.height) >= BoardGameControlMetrics.minTapTarget)
        #expect(CGFloat(styled.width) >= BoardGameControlMetrics.minTapTarget)
        // 既定の文字サイズではカプセル自体は 44pt に届かない（届くなら枠を広げる根拠が無い）。
        #expect(CGFloat(try Self.render(Self.legacyCapsule).height) < BoardGameControlMetrics.minTapTarget)
    }

    /// 枠が 44pt になっても、操作列の余白を詰めて外寸を据え置く（盤の大きさを変えない・#148）。
    /// 比べる相手は #711 以前の操作列（手書きのカプセル + 上下 8pt）。
    /// **一致するのはこの描画（macOS）のフォントの高さでの話**。iPhone SE のスクショでは従来のカプセルが 28.5pt で、
    /// 操作カードは 44.5pt → 46pt と下端が 1.5pt 伸びる（#711 実測。上端と盤の位置は変わらない）。
    @Test("操作列の外寸は従来と同じ")
    func rowHeightMatchesLegacyRow() throws {
        let legacy = try Self.render(
            HStack(spacing: 12) { Self.legacyCapsule }
                .padding(.horizontal, 16).padding(.vertical, 8)
        )
        let styled = try Self.render(
            HStack(spacing: 12) { Self.styledButton(enabled: true) }
                .padding(.horizontal, 16).padding(.vertical, BoardGameControlMetrics.rowVerticalPadding)
        )
        #expect(styled.height == legacy.height)
    }

    @Test("押せないときは面の色が変わる")
    func disabledChangesFill() throws {
        let enabled = try Self.render(Self.styledButton(enabled: true))
        let disabled = try Self.render(Self.styledButton(enabled: false))
        let capsule = try Self.render(Self.legacyCapsule)
        // カプセルは 44pt の枠の縦の中央に描かれる。その上端の余白（6pt）の中央は文字に掛からず面の色だけが出る。
        let x = enabled.width / 2, y = (enabled.height - capsule.height) / 2 + 3
        #expect(Self.pixel(enabled, x: x, y: y) == Self.rgb(Theme.Hex.Fill.teal),
                "押せるときの面が teal ではない")
        #expect(Self.pixel(disabled, x: x, y: y) == Self.rgb(Theme.Hex.fillMuted.light),
                "押せないときの面が fillMuted ではない（.disabled が見た目に出ない）")
    }

    /// 枠の透明な部分で受けるには `contentShape` が要り、カプセルを小さく描くには背景が枠より前に要る。
    /// どちらも描画の大きさには出ないので、並びをソースで固定する。
    @Test("カプセル → 44pt の枠 → 矩形で受ける、の順に組む")
    func hitAreaIsTheWidenedFrame() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Core/BoardGameChrome.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        guard let start = source.range(of: "public struct BoardGameControlCapsuleStyle"),
              let end = source.range(of: "\n}\n", range: start.upperBound..<source.endIndex) else {
            Issue.record("走査の前提が壊れている: BoardGameControlCapsuleStyle が見つからない")
            return
        }
        let body = source[start.lowerBound..<end.upperBound]
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") }
        guard let capsule = body.firstIndex(where: { $0.hasPrefix(".background(Capsule()") }),
              let frame = body.firstIndex(of: ".frame(minWidth: BoardGameControlMetrics.minTapTarget,"),
              let shape = body.firstIndex(of: ".contentShape(Rectangle())") else {
            Issue.record("カプセル / 44pt の枠 / contentShape が見つからない:\n\(body.joined(separator: "\n"))")
            return
        }
        // 枠より後に背景を置くと、カプセルが 44pt の高さに膨らむ。
        #expect(capsule < frame)
        // 形を取るのは枠を広げた後。前に置くと元のカプセルの大きさでしか受けない。
        #expect(frame < shape)
        // 枠の外へはみ出させる方法には戻さない（Button では反応しないと実測済み）。
        #expect(!body.contains(".overlay {"))
        #expect(!body.contains { $0.contains(".padding(.vertical, -") })
    }

    // MARK: - ヘルパー

    /// #711 以前に「投了」へ手書きしていたカプセル。
    private static var legacyCapsule: some View {
        Label("待った", systemImage: "arrow.uturn.backward")
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Theme.Fill.teal))
            .themeBody(14)
    }

    private static func styledButton(enabled: Bool) -> some View {
        Button {} label: {
            Label("待った", systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(BoardGameControlCapsuleStyle(fill: Theme.Fill.teal))
        .disabled(!enabled)
        .themeBody(14)
        .environment(\.colorScheme, .light)
    }

    private static func render(_ view: some View) throws -> CGImage {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 1
        return try #require(renderer.cgImage, "描画できなかった")
    }

    private static func pixel(_ image: CGImage, x: Int, y: Int) -> [Int] {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // 1×1 の文脈に、読みたい画素が原点へ来るようにずらして描く（CGContext は左下原点）。
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return data.prefix(3).map(Int.init)
    }

    private static func rgb(_ hex: UInt32) -> [Int] {
        [Int(hex >> 16 & 0xFF), Int(hex >> 8 & 0xFF), Int(hex & 0xFF)]
    }
}

/// 修飾子の**置き場所**で決まる性質。値としては検証できないのでソース走査で固定する
/// （将棋 `ShogiPieceLayerSourceTests` と同じ流儀）。
@Suite("盤ゲームの共通の枠の組み方")
struct BoardGameChromeSourceTests {

    private static func lines(ofFunction declaration: String) throws -> [String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // BoardGameChromeTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources/Core/BoardGameChrome.swift")
        let all = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = all.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == declaration }) else {
            Issue.record("走査の前提が壊れている: \(declaration) が見つからない")
            return []
        }
        let indent = all[start].prefix { $0 == " " }
        guard let end = all[start...].dropFirst().firstIndex(where: { $0 == indent + "}" }) else {
            Issue.record("走査の前提が壊れている: \(declaration) の終わりが見つからない")
            return []
        }
        return all[start...end].map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// #477 で将棋・チェスの両方に当て直した重なり順。ここが唯一の定義になった。
    @Test("角丸は駒より前、印は駒より後（= 上）に重ねる")
    func boardLayersKeepOrder() throws {
        let lines = try Self.lines(
            ofFunction: "func boardLayers<Pieces: View, Check: View, Targets: View>("
        )
        let clips = lines.enumerated().filter { $0.element.hasPrefix("clipShape(") }
        // 2つ目を後ろに足されると、そちらが駒の層まで丸めてしまう（数も固定する）。
        #expect(clips.count == 1, "角丸が1つではない:\n\(lines.joined(separator: "\n"))")
        guard let clip = clips.first?.offset,
              let pieces = lines.firstIndex(of: ".overlay { pieces() }"),
              let check = lines.firstIndex(of: ".overlay { check() }"),
              let targets = lines.firstIndex(of: ".overlay { targets() }") else {
            Issue.record("角丸 / 3 層が見つからない（走査の前提が壊れている）:\n\(lines.joined(separator: "\n"))")
            return
        }
        // 角丸をあとに置くと、選択して持ち上げた駒（拡大 + 上へ）が盤の上端で切り落とされる（#477）。
        #expect(clip < pieces)
        // 逆にすると、取れる駒を囲む枠や王手の枠が駒の下に潜って読めなくなる（#200・#377）。
        #expect(pieces < check)
        #expect(check < targets)
    }

    /// 「浮いている」ことは駒の下に落ちる影で伝わるので、影を先に描く。
    @Test("持ち上げは 拡大 → 影 → 浮かせ の順（影を先に描く）")
    func pieceLiftKeepsOrder() throws {
        let lines = try Self.lines(ofFunction: "func pieceLift(isLifted: Bool, cell: CGFloat) -> some View {")
        guard let scale = lines.firstIndex(where: { $0.hasPrefix("scaleEffect(") }),
              let shadow = lines.firstIndex(where: { $0.hasPrefix(".shadow(") }),
              let offset = lines.firstIndex(where: { $0.hasPrefix(".offset(") }) else {
            Issue.record("持ち上げの 3 指定が見つからない（走査の前提が壊れている）:\n\(lines.joined(separator: "\n"))")
            return
        }
        #expect(scale < shadow)
        #expect(shadow < offset)
        // アニメーションは呼び出し側の**駒単位**に置く。ここに書くと層全体に掛かってしまう。
        #expect(lines.contains { $0.hasPrefix(".gameAnimation(") } == false,
                "共通の pieceLift にアニメーションが入っている:\n\(lines.joined(separator: "\n"))")
        #expect(lines.contains { $0.hasPrefix(".animation(") } == false)
    }

    /// 記号だけのボタンは VoiceOver が SF Symbols の名前を推測して読む。
    /// **将棋側にはこの指定が無く、チェス側にだけ入っていた**（#530 が防ぐ「片方だけ直した」状態）。
    @Test("検討ナビの記号ボタンには読み上げ文が付く")
    func reviewNavBarLabelsEverySymbolButton() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Core/BoardGameChrome.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        for label in ["1手戻す", "1手進める"] {
            #expect(source.contains(".accessibilityLabel(\"\(label)\")"), "\(label) の読み上げ文が無い")
        }
        #expect(source.contains(".accessibilityLabel(\"\\(total)手中 \\(ply)手目\")"),
                "手数表示の読み上げ文が無い")
    }

    /// 枠や形を取ってから**中で**余白を詰めると、詰めた外側が反応しない（#713 のプローブで実測）。
    /// 描画の大きさには出ないので、置き場所をソースで固定する。
    @Test("検討ナビの ◀ ▶ は 44pt の枠と形をボタンの中に入れ、外で詰める")
    func reviewNavSymbolsWidenHitAreaInsideButton() throws {
        let symbol = try Self.lines(ofFunction: "private static func navSymbol(_ name: String) -> some View {")
        guard let frame = symbol.firstIndex(of: ".frame(minWidth: BoardGameControlMetrics.minTapTarget,"),
              let shape = symbol.firstIndex(of: ".contentShape(Rectangle())") else {
            Issue.record("44pt の枠 / contentShape が見つからない:\n\(symbol.joined(separator: "\n"))")
            return
        }
        #expect(frame < shape)
        #expect(!symbol.contains { $0.contains(".padding(") }, "navSymbol の中で余白を詰めている")

        let body = try Self.lines(ofFunction: "public var body: some View {")
        let inset = ".padding(.vertical, -BoardGameControlMetrics.reviewNavLayoutInset)"
        for name in ["backward.frame.fill", "forward.frame.fill"] {
            guard let button = body.firstIndex(where: { $0.contains("Self.navSymbol(\"\(name)\")") }) else {
                Issue.record("\(name) が navSymbol を通っていない:\n\(body.joined(separator: "\n"))")
                continue
            }
            #expect(body.count > button + 1 && body[button + 1] == inset, "\(name) の直後で詰めていない")
        }
    }
}

/// 検討ナビの ◀ ▶ の当たり判定（#713）。
@MainActor
@Suite("検討ナビの記号ボタン")
struct ReviewNavBarTapTargetTests {

    /// 44pt の枠を入れても、帯の高さは「もう一度」のカプセルで決まったまま（決着で盤が縮まない・#139）。
    @Test("帯の高さは従来と同じ")
    func barHeightMatchesLegacyBar() throws {
        let legacy = try Self.render(Self.legacyBar)
        let bar = try Self.render(
            ReviewNavBar(ply: 3, total: 10, onBack: {}, onForward: {}, onNewGame: {})
        )
        #expect(bar.height == legacy.height)
    }

    @Test("詰めたあとの ◀ ▶ はカプセルより低く、44pt の枠は残る")
    func layoutInsetKeepsCapsuleAsTallest() throws {
        let inset = BoardGameControlMetrics.reviewNavLayoutInset
        #expect(inset >= 0)
        let capsule = try Self.render(Self.legacyCapsule)
        #expect(BoardGameControlMetrics.minTapTarget - inset * 2 <= CGFloat(capsule.height))
    }

    // MARK: - ヘルパー

    /// #713 以前の帯（記号は素の Image）。
    private static var legacyBar: some View {
        HStack(spacing: 12) {
            Button {} label: { Image(systemName: "backward.frame.fill") }
            Text("3/10手").themeBody(14).monospacedDigit()
            Button {} label: { Image(systemName: "forward.frame.fill") }
            Spacer(minLength: 8)
            Button {} label: { legacyCapsule }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 5)
        .popCard(corner: Theme.cornerSmall)
    }

    private static var legacyCapsule: some View {
        Label("もう一度", systemImage: "arrow.clockwise")
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Theme.Fill.coral))
            .themeBody(14)
    }

    /// macOS の既定のボタン（枠付き）は iOS と高さが違うので、iOS の既定に近い枠無しで比べる。
    private static func render(_ view: some View) throws -> CGImage {
        let renderer = ImageRenderer(
            content: view.buttonStyle(.borderless).environment(\.colorScheme, .light)
        )
        renderer.scale = 1
        return try #require(renderer.cgImage, "描画できなかった")
    }
}
