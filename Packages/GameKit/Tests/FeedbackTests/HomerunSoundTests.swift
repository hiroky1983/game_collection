import Testing
import Foundation
import Core
#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - 合成の部品

@Suite("効果音の合成部品（SoundSynth）")
struct SoundSynthTests {

    /// ゼロ交差の数から周波数を見積もる（Hz）。
    private func zeroCrossingRate(_ s: ArraySlice<Double>) -> Double {
        var crossings = 0
        var previous = s.first ?? 0
        for v in s.dropFirst() {
            if (previous < 0) != (v < 0) { crossings += 1 }
            previous = v
        }
        return Double(crossings) / 2 / (Double(s.count) / SoundSynth.sampleRate)
    }

    @Test("正弦波の周波数は始めから終わりへ滑らかに動く（指数カーブ・位相は連続）")
    func toneSweeps() {
        let s = SoundSynth.tone(1.0, from: 400, to: 1600, decay: 0)
        let n = s.count
        let head = zeroCrossingRate(s[0..<(n / 10)])
        let middle = zeroCrossingRate(s[(n * 45 / 100)..<(n * 55 / 100)])
        let tail = zeroCrossingRate(s[(n * 9 / 10)..<(n - SoundSynth.count(0.011))])
        #expect(abs(head - 400 * pow(4, 0.05)) < 40)
        #expect(abs(middle - 800) < 40, "指数カーブの真ん中は幾何平均（\(middle)Hz）")
        #expect(abs(tail - 1600 * pow(4, -0.05)) < 80)
        // 位相が飛ぶと隣り合うサンプルの差が跳ねる。最大の傾き（2πf/fs）を超えない。
        let jump = zip(s, s.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        #expect(jump <= 2 * .pi * 1600 / SoundSynth.sampleRate + 1e-6)
    }

    @Test("帯域フィルタを通したノイズは中心周波数の付近に集まり、発散しない")
    func bandPassNoise() {
        var synth = SoundSynth(seed: 1)
        let low = synth.noise(1.0, .bandPass, from: 300, q: 4, decay: 0)
        let high = synth.noise(1.0, .bandPass, from: 3000, q: 4, decay: 0)
        #expect(low.allSatisfy(\.isFinite) && high.allSatisfy(\.isFinite))
        #expect((low + high).allSatisfy { abs($0) < 2 })
        let lowRate = zeroCrossingRate(low[...])
        let highRate = zeroCrossingRate(high[...])
        // 狭帯域のノイズのゼロ交差は中心周波数のまわりでばらつくので、帯の上下関係と桁で見る。
        #expect(lowRate > 150 && lowRate < 800, "\(lowRate)Hz")
        #expect(highRate > 2000 && highRate < 4000, "\(highRate)Hz")
    }

    @Test("同じ種のノイズは同じ波形（毎回同じ音になる）")
    func noiseIsDeterministic() {
        var a = SoundSynth(seed: 42)
        var b = SoundSynth(seed: 42)
        var c = SoundSynth(seed: 43)
        let x = a.noise(0.1, .highPass, from: 2000)
        #expect(x == b.noise(0.1, .highPass, from: 2000))
        #expect(x != c.noise(0.1, .highPass, from: 2000))
    }

    @Test("重ねると時刻ぶんずれて足され、足りない長さは伸びる")
    func mixOffsets() {
        var dst = [Double](repeating: 1, count: 10)
        SoundSynth.mix(&dst, [Double](repeating: 1, count: 10), at: 5 / SoundSynth.sampleRate, gain: 2)
        #expect(dst.count == 15)
        #expect(dst[0] == 1 && dst[5] == 3 && dst[14] == 2)
    }

    @Test("周波数ごとに減衰の速さが違う（高い倍音ほど早く消える金属の鳴り）")
    func partialsDecayIndependently() {
        let fast = SoundSynth.partials(0.5, [(1000, 1, 0.02)])
        let slow = SoundSynth.partials(0.5, [(1000, 1, 0.3)])
        let window = SoundSynth.count(0.2)..<SoundSynth.count(0.25)
        let fastLevel = fast[window].map(abs).max() ?? 0
        let slowLevel = slow[window].map(abs).max() ?? 0
        #expect(fastLevel < 0.01)
        #expect(slowLevel > 0.4)
    }
}

// MARK: - 柵越えおじさんの場面の音

@Suite("柵越えおじさんの場面の音（HomerunSound）")
struct HomerunSoundTests {

    @Test("全 18 場面がそろっている（試作の 01〜10 + フェンス・バックスクリーン直撃）")
    func allScenes() {
        #expect(HomerunSound.allCases.count == 18)
    }

    @Test("バットに当たる音は当面すべてジャストミートと同じ波形（会長指示 2026-10-05）", arguments: [HomerunSound.hitJust, .hitGood, .hitWeak])
    func hitSoundsMatchJustMeet(sound: HomerunSound) {
        #expect(sound.samples == HomerunSound.justMeet.samples)
    }

    @Test("フェンス直撃は短く、バックスクリーン直撃は低く重い（フェンスより長い）")
    func wallHits() {
        #expect(HomerunSound.fenceHit.duration < 0.3)
        #expect(HomerunSound.backScreen.duration > HomerunSound.fenceHit.duration)
    }

    @Test("WAV として正しく、長さが波形と一致する", arguments: HomerunSound.allCases)
    func wavIsWellFormed(sound: HomerunSound) {
        let data = sound.wavData
        #expect(String(decoding: data[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        #expect((data.count - 44) / 2 == sound.samples.count)
    }

    /// 長さのルール: `SoundEffect` は `fanfare` 以外 0.3 秒未満。場面の音のうち操作に直結するもの（マシン・風切り・
    /// 詰まり・ミット・たんこぶ・倒れる・怒り）は同じく短く、見せ場の余韻・歓声・上昇音（`longSounds`）だけ例外。
    @Test("操作に直結する音は 0.3 秒未満", arguments: HomerunSound.allCases.filter { !HomerunSound.longSounds.contains($0) })
    func shortSoundsAreShort(sound: HomerunSound) {
        #expect(sound.duration > 0)
        #expect(sound.duration < 0.3, "\(sound) は \(sound.duration) 秒")
    }

    @Test("見せ場の音は長くてよいが、次の球のテンポを崩すほどは長くない（3.5 秒未満）", arguments: Array(HomerunSound.longSounds))
    func longSoundsAreBounded(sound: HomerunSound) {
        #expect(sound.duration >= 0.3)
        #expect(sound.duration < 3.5, "\(sound) は \(sound.duration) 秒")
    }

    @Test("最大でも -6dBFS（0.5）で割れない。無音ではない", arguments: HomerunSound.allCases)
    func peakIsBounded(sound: HomerunSound) {
        let peak = sound.samples.map(abs).max() ?? 0
        #expect(peak > 0.15)
        #expect(peak <= 0.5 + 1e-9)
    }

    @Test("先頭と末尾が 0 付近で、プツッというノイズが乗らない", arguments: HomerunSound.allCases)
    func edgesAreSilent(sound: HomerunSound) {
        let s = sound.samples
        #expect(abs(s.first ?? 1) < 0.01)
        #expect(abs(s.last ?? 1) < 0.01)
    }

    @Test("同じ場面は毎回同じ波形")
    func deterministic() {
        #expect(HomerunSound.homerun.samples == HomerunSound.homerun.samples)
        #expect(HomerunSound.machine.samples != HomerunSound.mitt.samples)
    }

    #if canImport(AVFoundation)
    @Test("合成した WAV を AVAudioPlayer が実際に読める", arguments: HomerunSound.allCases)
    func playerCanDecode(sound: HomerunSound) throws {
        let player = try AVAudioPlayer(data: sound.wavData)
        #expect(abs(player.duration - sound.duration) < 0.01)
    }
    #endif

    @MainActor
    @Test("設定の効果音がオフなら鳴らさず、合成の準備だけは通す")
    func gateFollowsSetting() {
        final class Recorder: HomerunSoundService {
            var played: [HomerunSound] = []
            var prepared = 0
            func play(_ sound: HomerunSound) { played.append(sound) }
            func prepare() { prepared += 1 }
        }
        let recorder = Recorder()
        var enabled = false
        let gated = GatedHomerunSoundService(base: recorder) { enabled }
        gated.play(.machine)
        gated.prepare()
        #expect(recorder.played.isEmpty)
        #expect(recorder.prepared == 1)
        enabled = true
        gated.play(.machine)
        #expect(recorder.played == [.machine])
    }
}
