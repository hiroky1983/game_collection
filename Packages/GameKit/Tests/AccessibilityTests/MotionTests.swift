import Testing
import Foundation
import SwiftUI
@testable import Core

/// Reduce Motion 追従（#210）の共通レイヤー。
///
/// 「視差効果を減らす」を ON にしたときの見え方そのものはシミュレータでしか確かめられないが、
/// **アニメーションを止めても状態変更は必ず走る**という一番壊れやすい性質は純関数として固定できる。
/// ここを取り違えると「演出が消える」ではなく「盤面が更新されない」退行になる。
@Suite("Reduce Motion 追従", .serialized)
@MainActor
struct MotionTests {

    @Test("OFF のときは要求どおりのアニメーションを通す（既定の見た目を変えない）")
    func passesThroughWhenDisabled() {
        #expect(Motion.resolve(.easeInOut(duration: 0.12), reduceMotion: false) == .easeInOut(duration: 0.12))
        #expect(Motion.resolve(.spring(response: 0.25), reduceMotion: false) == .spring(response: 0.25))
    }

    @Test("ON のときはアニメーションを nil（即時反映）に落とす")
    func dropsAnimationWhenEnabled() {
        #expect(Motion.resolve(.easeInOut(duration: 0.12), reduceMotion: true) == nil)
        #expect(Motion.resolve(.default, reduceMotion: true) == nil)
    }

    @Test("もともとアニメーション無しの指定はどちらの状態でも nil のまま")
    func keepsExplicitNil() {
        #expect(Motion.resolve(nil, reduceMotion: false) == nil)
        #expect(Motion.resolve(nil, reduceMotion: true) == nil)
    }

    @Test("withGameAnimation は ON でも body を必ず実行して結果を返す")
    func runsBodyRegardlessOfSetting() {
        defer { Motion.override = nil }

        for enabled in [false, true] {
            Motion.override = enabled
            var applied = 0
            let result = withGameAnimation(.easeInOut(duration: 0.12)) {
                applied += 1
                return "done"
            }
            #expect(applied == 1, "Reduce Motion = \(enabled) で状態変更が実行されていない")
            #expect(result == "done")
        }
    }

    @Test("override を外すとプラットフォームの設定に戻る")
    func overrideIsRestorable() {
        Motion.override = true
        #expect(Motion.isReduceMotionEnabled == true)
        Motion.override = nil
        // 実機・シミュレータの設定に委ねるので値は問わない。差し替えが残らないことだけを見る。
        _ = Motion.isReduceMotionEnabled
    }

    /// 素の `withAnimation` / `.animation(` を拾う正規表現。`(` の前の空白と行末での折り返しを許す。
    private static let rawAnimationPattern = #"(?:\bwithAnimation|\.animation)\s*(?:\(|$)"#

    /// 規約（`docs/spec-app.md`）の機械的な担保。
    ///
    /// 演出追加の Issue が10件控えており（#195 #199 #200 #201 #202 #203 #204 #206 #208 #209）、
    /// 素の `withAnimation` / `.animation(` が1つでも混じると、その箇所だけ Reduce Motion に
    /// 追従しない = Accessibility Nutrition Labels の申告が虚偽になる。ドキュメントの1行だけでは
    /// 守られないので、ソースを走査して固定する。
    @Test("アニメーションは Core のヘルパー経由でのみ書かれている")
    func noRawAnimationOutsideCore() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AccessibilityTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources")

        let files = try FileManager.default
            .subpathsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") }
            // Core はヘルパーの実装そのものが素の API を呼ぶので対象外。
            .filter { !$0.hasPrefix("Core/") }

        #expect(files.count > 20, "走査対象が見つからない（パスの導出が壊れている可能性）")

        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                // ヘルパー呼び出し（.gameAnimation( / withGameAnimation）を消してから素の API を探す。
                let stripped = trimmed.replacingOccurrences(of: "gameAnimation(", with: "")
                // `.animation (` のように括弧の前に空白を挟む書き方と、`(` が次の行に折り返された
                // 書き方も拾う（単純な部分文字列一致だと素通りしてしまう）。
                if stripped.range(of: Self.rawAnimationPattern, options: .regularExpression) != nil {
                    offenders.append("\(file):\(index + 1) \(trimmed)")
                }
            }
        }

        #expect(
            offenders.isEmpty,
            """
            素の withAnimation / .animation( が残っています。\
            Reduce Motion に追従させるため withGameAnimation(_:_:) / .gameAnimation(_:value:) を使ってください:
            \(offenders.joined(separator: "\n"))
            """
        )
    }
}
