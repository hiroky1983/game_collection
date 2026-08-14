import Testing
import Foundation
import Core

// MARK: - 波形の合成（#116）

@Suite("効果音の波形合成")
struct ToneGeneratorTests {

    @Test("全種類が RIFF/WAVE として正しい長さのバイト列になる", arguments: SoundEffect.allCases)
    func wavHeaderIsWellFormed(effect: SoundEffect) {
        let data = effect.wavData
        #expect(data.count > 44, "ヘッダ 44 バイトのあとに波形が続く")

        func ascii(_ range: Range<Int>) -> String {
            String(decoding: data[range], as: UTF8.self)
        }
        func uint32(at offset: Int) -> UInt32 {
            data[offset..<(offset + 4)].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        }
        func uint16(at offset: Int) -> UInt16 {
            data[offset..<(offset + 2)].reversed().reduce(UInt16(0)) { $0 << 8 | UInt16($1) }
        }

        #expect(ascii(0..<4) == "RIFF")
        #expect(ascii(8..<12) == "WAVE")
        #expect(ascii(12..<16) == "fmt ")
        #expect(ascii(36..<40) == "data")

        #expect(uint16(at: 20) == 1, "リニア PCM")
        #expect(uint16(at: 22) == 1, "モノラル")
        #expect(uint32(at: 24) == UInt32(ToneGenerator.sampleRate))
        #expect(uint16(at: 34) == 16, "16bit")

        // 宣言した長さと実バイト数が食い違うと AVAudioPlayer が読めない。
        #expect(Int(uint32(at: 40)) == data.count - 44, "data チャンクの長さが実体と一致する")
        #expect(Int(uint32(at: 4)) == data.count - 8, "RIFF の長さが実体と一致する")
    }

    @Test("波形の長さが定義した秒数と一致する", arguments: SoundEffect.allCases)
    func durationMatchesDefinition(effect: SoundEffect) {
        let expected = effect.steps.reduce(0) { $0 + Int((($1.duration) * ToneGenerator.sampleRate).rounded()) }
        let actual = (effect.wavData.count - 44) / 2
        #expect(actual == expected)
    }

    @Test("どの効果音も 0.3 秒未満に収まる（操作のテンポを妨げない）", arguments: SoundEffect.allCases)
    func soundsAreShort(effect: SoundEffect) {
        let seconds = effect.steps.reduce(0) { $0 + $1.duration }
        #expect(seconds > 0)
        #expect(seconds < 0.3)
    }

    @Test("振幅が 16bit の範囲に収まり、音が割れない", arguments: SoundEffect.allCases)
    func samplesDoNotClip(effect: SoundEffect) {
        let data = effect.wavData
        var peak = 0
        var index = 44
        while index + 1 < data.count {
            let raw = UInt16(data[index]) | UInt16(data[index + 1]) << 8
            peak = max(peak, abs(Int(Int16(bitPattern: raw))))
            index += 2
        }
        #expect(peak > 0, "無音ではない")
        // 定義した最大振幅（0.32）を超えない = クリップの余地が十分ある。
        let allowed = Int(32_767 * (effect.steps.map(\.amplitude).max() ?? 0)) + 1
        #expect(peak <= allowed, "定義した振幅を超えない（peak=\(peak) allowed=\(allowed)）")
    }

    @Test("先頭と末尾が 0 付近で、プツッというノイズが乗らない", arguments: SoundEffect.allCases)
    func edgesAreSilent(effect: SoundEffect) {
        let data = effect.wavData
        func sample(at i: Int) -> Int {
            let offset = 44 + i * 2
            let raw = UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
            return abs(Int(Int16(bitPattern: raw)))
        }
        let count = (data.count - 44) / 2
        #expect(sample(at: 0) < 100, "立ち上がりが 0 から始まる")
        #expect(sample(at: count - 1) < 100, "減衰しきってから終わる")
    }

    @Test("長さ 0 の指定でも破綻しない（ヘッダだけの WAV になる）")
    func emptyStepsProduceHeaderOnly() {
        let data = ToneGenerator.wavData(steps: [ToneStep(frequency: 440, duration: 0, amplitude: 0.5)])
        #expect(data.count == 44)
    }
}

// MARK: - 触覚との対応

@Suite("効果音と触覚の対応")
struct SoundEffectMappingTests {

    @Test("FeedbackImpact / FeedbackNotice の全ケースが 1 対 1 で対応する")
    func mappingIsOneToOne() {
        let impacts: [FeedbackImpact] = [.light, .medium, .rigid]
        let notices: [FeedbackNotice] = [.success, .warning, .error]
        let mapped = impacts.map(SoundEffect.init) + notices.map(SoundEffect.init)
        #expect(Set(mapped).count == mapped.count, "同じ効果音に潰れていない")
        #expect(Set(mapped) == Set(SoundEffect.allCases), "取りこぼしが無い")
    }
}

// MARK: - オン / オフの保存（受け入れ条件）

@Suite("フィードバック設定の保存")
struct FeedbackPreferenceTests {

    /// テスト間で干渉しないよう、テストごとに使い捨ての UserDefaults を作る。
    private func makeDefaults(_ name: String) -> UserDefaults {
        let suite = "FeedbackPreferenceTests.\(name).\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    @Test("未設定（初回起動）は オン")
    func defaultsToEnabled() {
        let pref = FeedbackPreference(key: "soundEnabled_v1", defaults: makeDefaults("default"))
        #expect(pref.isEnabled)
    }

    @Test("オフにすると保存され、読み直してもオフのまま")
    func persistsDisabled() {
        let defaults = makeDefaults("persist")
        FeedbackPreference(key: "soundEnabled_v1", defaults: defaults).isEnabled = false
        // 別インスタンスから読み直す = アプリを起動し直した状況。
        #expect(FeedbackPreference(key: "soundEnabled_v1", defaults: defaults).isEnabled == false)

        FeedbackPreference(key: "soundEnabled_v1", defaults: defaults).isEnabled = true
        #expect(FeedbackPreference(key: "soundEnabled_v1", defaults: defaults).isEnabled)
    }

    @Test("触覚と効果音は別のキーで、片方を変えてももう片方に影響しない")
    func togglesAreIndependent() {
        let defaults = makeDefaults("independent")
        let haptics = FeedbackPreference(key: "hapticsEnabled_v1", defaults: defaults)
        let sound   = FeedbackPreference(key: "soundEnabled_v1",   defaults: defaults)

        sound.isEnabled = false
        #expect(haptics.isEnabled, "効果音を切っても触覚は残る")

        sound.isEnabled = true
        haptics.isEnabled = false
        #expect(sound.isEnabled, "触覚を切っても効果音は残る")
    }
}
