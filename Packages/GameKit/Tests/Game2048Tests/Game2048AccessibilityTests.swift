import Testing
@testable import Game2048

/// VoiceOver の読み上げ文と操作名（#712）。
///
/// 「読み上げられるか」自体はシミュレータ上の VoiceOver でしか確かめられないが、
/// **何が読み上げられるか**（位置・値・空き）と**どの操作が並ぶか**は純関数なのでここで固定する。
@Suite("2048 の読み上げ文")
struct Game2048AccessibilityTests {

    @Test("マスは行列と値を読む") func tile() {
        #expect(Game2048Accessibility.tileLabel(row: 1, col: 2, value: 128) == "2行3列、128")
        #expect(Game2048Accessibility.tileLabel(row: 3, col: 3, value: 2) == "4行4列、2")
    }

    @Test("空きマスは値ではなく「空き」と読む") func empty() {
        #expect(Game2048Accessibility.tileLabel(row: 0, col: 0, value: 0) == "1行1列、空き")
    }

    @Test("大きい値も桁区切りを入れずに読む") func largeValue() {
        // 「2,048」のような桁区切りを混ぜず、盤面の表示と同じ数字のまま出す
        #expect(Game2048Accessibility.tileLabel(row: 0, col: 1, value: 2048) == "1行2列、2048")
        #expect(Game2048Accessibility.tileLabel(row: 0, col: 1, value: 16384) == "1行2列、16384")
    }

    @Test("4 方向すべてに別々の操作名がある") func moveActionNames() {
        let names = Direction.allCases.map(Game2048Accessibility.moveActionName)
        #expect(names == ["上へ動かす", "下へ動かす", "左へ動かす", "右へ動かす"])
        #expect(Set(names).count == Direction.allCases.count)
    }
}
