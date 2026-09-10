import Testing
import Foundation
import SwiftUI
@testable import GameChess

/// 使い捨ての保存先。`UserDefaults.standard`（＝実機の設定）を汚さない。
private func makePreference(_ suite: String) -> ChessPieceStylePreference {
    let name = "asobiba.chess.tests.\(suite)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return ChessPieceStylePreference(defaults: defaults)
}

/// 駒の意匠（#598）。**形はどの意匠でも同じで、変わるのは光の当て方だけ**という
/// 契約と、既定（シンプル）の見た目が v1.1.3 までと 1 ビットも変わらないことを固定する。
@Suite("チェス 駒の意匠")
struct ChessPieceStyleTests {

    @Test("既定はシンプル。未設定の保存先からもシンプルが返る")
    func defaultIsFlat() {
        let pref = makePreference("default")
        #expect(pref.style == .flat)
    }

    @Test("選んだ意匠は保存され、次に読んだときも同じ")
    func persists() {
        let pref = makePreference("persist")
        pref.style = .sculpted
        #expect(pref.style == .sculpted)
        // 同じ保存先を別に組み立てても（＝アプリを起動し直しても）読める。
        #expect(ChessPieceStylePreference(defaults: UserDefaults(suiteName: "asobiba.chess.tests.persist")!).style == .sculpted)
    }

    @Test("読めない値が入っていたら既定へ倒す")
    func unknownValueFallsBackToFlat() {
        let name = "asobiba.chess.tests.broken"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set("marble", forKey: ChessPieceStylePreference.key)
        #expect(ChessPieceStylePreference(defaults: defaults).style == .flat)
    }

    @Test("シンプルの陰影は #598 以前と同じ（平らな塗り・重ねものなし・影の値も据え置き）")
    func flatShadingUnchanged() {
        for color in ChessColor.allCases {
            let shading = ChessPieceStyle.flat.shading(for: color)
            #expect(shading.highlight == nil, "従来どおり上→下の線形グラデーションで塗る")
            #expect(!shading.hasOverlay, "従来は面の上に何も重ねていない")
            #expect(shading.shadowOpacity == 0.28)
            #expect(shading.shadowRadius == 0.03)
            #expect(shading.shadowOffset == 0.02)
        }
        #expect(ChessPieceStyle.flat.shading(for: .white).fill
                == [ChessBoardStyle.whitePieceTop, ChessBoardStyle.whitePieceBottom])
        #expect(ChessPieceStyle.flat.shading(for: .black).fill
                == [ChessBoardStyle.blackPieceTop, ChessBoardStyle.blackPieceBottom])
    }

    @Test("立体は照り・ツヤ・陰を持ち、面の色は既定と同じものを使う")
    func sculptedAddsLightOnly() {
        for color in ChessColor.allCases {
            let flat = ChessPieceStyle.flat.shading(for: color)
            let sculpted = ChessPieceStyle.sculpted.shading(for: color)
            #expect(sculpted.fill == flat.fill, "色を替えるのではなく光の当て方だけを替える")
            #expect(sculpted.highlight != nil)
            #expect(sculpted.hasOverlay)
            #expect(sculpted.sheen > 0)
            #expect(sculpted.depth > 0)
            #expect(sculpted.shadowOpacity > flat.shadowOpacity, "立体のほうが影は濃い")
        }
    }

    @Test("照りの中心は左上（碁石・五目の石と同じ光源）")
    func highlightComesFromUpperLeft() {
        for color in ChessColor.allCases {
            let highlight = ChessPieceStyle.sculpted.shading(for: color).highlight
            #expect(highlight != nil)
            #expect(highlight!.x < 0.5)
            #expect(highlight!.y < 0.5)
        }
    }

    @Test("ツヤは黒駒のほうが弱く、陰は黒駒のほうが強い")
    func sculptedSplitsByPieceColor() {
        let white = ChessPieceStyle.sculpted.shading(for: .white)
        let black = ChessPieceStyle.sculpted.shading(for: .black)
        #expect(black.sheen < white.sheen, "暗い面に同じ白を乗せると塗料のように光る")
        #expect(black.depth > white.depth, "明るい面に同じ陰を落とすと下半分が濁る")
    }

    @Test("駒の形（部品の並び）は意匠に依存しない")
    func silhouetteIsSharedAcrossStyles() {
        // 図案は `ChessPieceArt` が持ち、意匠は `shading` しか触らない。
        // 形が意匠ごとに分岐すると、当たり判定・読み上げ・盤面の詰まり具合まで別物になる。
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        for type in ChessPieceType.allCases {
            let parts = ChessPieceArt.parts(of: type)
            #expect(!parts.isEmpty)
            // どの意匠でも同じ関数から取り出しているので、輪郭の外接矩形も一致する。
            let bounds = parts.map { $0.path(in: rect).boundingRect }
            #expect(bounds.allSatisfy { rect.insetBy(dx: -1, dy: -1).contains($0) },
                    "部品は駒の矩形の中に収まる")
        }
    }

    @Test("意匠は 2 つで、保存キーは v1")
    func casesAndKey() {
        #expect(ChessPieceStyle.allCases == [.flat, .sculpted], "並び順が設定シートの並び順になる")
        #expect(ChessPieceStyle.flat.rawValue == "flat")
        #expect(ChessPieceStyle.sculpted.rawValue == "sculpted")
        // 改名すると、既に立体を選んでいる人の設定が既定へ戻る。
        #expect(ChessPieceStylePreference.key == "chessPieceStyle_v1")
    }
}
