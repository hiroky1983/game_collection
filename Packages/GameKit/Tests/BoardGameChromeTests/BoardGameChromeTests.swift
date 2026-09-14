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

    /// 当たり判定を広げても操作列が高くならないこと（決着の瞬間に盤が伸び縮みしない・#148）。
    /// 比べる相手は #711 以前に「投了」へ手書きしていたカプセル。
    @Test("外寸は従来の手書きのカプセルと同じで、44pt はレイアウトに入らない")
    func layoutSizeMatchesLegacyCapsule() throws {
        let styled = try Self.render(Self.styledButton(enabled: true))
        let legacy = try Self.render(
            Label("待った", systemImage: "arrow.uturn.backward")
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Theme.Fill.teal))
                .themeBody(14)
        )
        #expect(styled.width == legacy.width)
        #expect(styled.height == legacy.height)
        // 既定の文字サイズではカプセル自体は 44pt に届かない（届くなら当たり判定を広げる根拠が無い）。
        #expect(CGFloat(styled.height) < BoardGameControlMetrics.minTapTarget)
    }

    @Test("押せないときは面の色が変わる")
    func disabledChangesFill() throws {
        let enabled = try Self.render(Self.styledButton(enabled: true))
        let disabled = try Self.render(Self.styledButton(enabled: false))
        // 上端の余白（6pt）の中央は文字に掛からず面の色だけが出る。
        let x = enabled.width / 2, y = 3
        #expect(Self.pixel(enabled, x: x, y: y) == Self.rgb(Theme.Hex.Fill.teal),
                "押せるときの面が teal ではない")
        #expect(Self.pixel(disabled, x: x, y: y) == Self.rgb(Theme.Hex.fillMuted.light),
                "押せないときの面が fillMuted ではない（.disabled が見た目に出ない）")
    }

    /// 44pt の当たり判定は `overlay` の中にあり描画にもレイアウトにも出ないので、置き方をソースで固定する。
    @Test("当たり判定は下限つきの透明な面を overlay で重ねて取る")
    func hitAreaIsOverlaidWithMinimumFrame() throws {
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
        guard let overlay = body.firstIndex(of: ".overlay {"),
              let minHeight = body.firstIndex(of: "minHeight: BoardGameControlMetrics.minTapTarget)"),
              let shape = body.firstIndex(of: ".contentShape(Rectangle())") else {
            Issue.record("overlay / 44pt の下限 / contentShape が見つからない:\n\(body.joined(separator: "\n"))")
            return
        }
        #expect(overlay < minHeight)
        // 形を取るのは下限を付けた後。前に置くと元のカプセルの大きさでしか受けない。
        #expect(minHeight < shape)
    }

    // MARK: - ヘルパー

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
}
