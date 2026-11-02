import Foundation

/// ねこさがしの場面の効果音（#3239）。猫を見つけた・ミス・クリア・鍵が開いた、の 4 場面だけ専用の音を鳴らす。
///
/// 触覚と同じ呼び出し箇所に相乗りさせるため `FeedbackImpact.cat(_:)` として届く（`CardSound` と同じ作り）。
/// 音源ファイルは同梱せず、`SoundSynth` で起動後に合成する（自作のため素材のライセンスは発生しない。`docs/spec-app.md` 参照）。
/// 種は音ごとに固定で、毎回同じ波形になる。
public enum CatSound: String, CaseIterable, Sendable {
    /// 猫を見つけた。続けて見つけてもうるさくならないよう、高さの違う 3 種類を順に鳴らす（`meow(at:)`）。
    case meowA, meowB, meowC
    /// ミス（赤い ×）。軽く残念な下降音。
    case miss
    /// 面のクリア。短いファンファーレのあとに鳴き声。
    case clear
    /// 鍵の面で鍵が開いた。
    case keyOpen

    /// 猫を見つけた音の順番（`count` 回目に見つけた猫の音）。
    public static func meow(at count: Int) -> CatSound {
        let order: [CatSound] = [.meowA, .meowB, .meowC]
        return order[((count % order.count) + order.count) % order.count]
    }

    /// 触覚の強さ。これまでの触覚（見つけた＝手応え）を保つ。ミス・クリアは `notice` で通知型の触覚を使う。
    public var haptic: FeedbackImpact { .medium }

    /// 通知型の触覚を使う場面（ミス＝warning・クリア＝success）。これまでの触覚をそのまま保つ。
    public var notice: FeedbackNotice? {
        switch self {
        case .miss: return .warning
        case .clear: return .success
        case .meowA, .meowB, .meowC, .keyOpen: return nil
        }
    }

    /// そのまま `AVAudioPlayer(data:)` に渡せる WAV バイト列。
    public var wavData: Data { ToneGenerator.wavData(samples: samples) }

    /// 長さ（秒）。
    public var duration: Double { Double(samples.count) / SoundSynth.sampleRate }

    /// 波形（-1〜1）。
    public var samples: [Double] {
        switch self {
        case .meowA: return Self.meow(base: 620, peak: 1.38, duration: 0.34)
        case .meowB: return Self.meow(base: 700, peak: 1.30, duration: 0.28)
        case .meowC: return Self.meow(base: 560, peak: 1.45, duration: 0.40)
        case .miss: return Self.missSamples()
        case .clear: return Self.clearSamples()
        case .keyOpen: return Self.keySamples()
        }
    }

    // MARK: 合成

    /// 「ニャー」。基本周波数を山なりに動かし（上がって下がる）、母音のように共鳴の中心も動かした倍音の重ね合わせ。
    private static func meow(base: Double, peak: Double, duration: Double, amplitude: Double = 0.8) -> [Double] {
        let length = SoundSynth.count(duration)
        let envelope = SoundSynth.exponentialEnvelope(length: length, attack: 0.025, decay: duration * 0.7)
        var out = [Double](repeating: 0, count: length)
        var phase = 0.0
        for i in 0..<length {
            let x = Double(i) / Double(length)
            // 「ニ」で一気に上がり「ァー」で下がっていく。
            let contour = x < 0.3 ? (x / 0.3) : (1 - (x - 0.3) / 0.7 * 0.65)
            let f = base * (1 + (peak - 1) * contour)
            // 共鳴の中心: 「イ」(高い) → 「ア」(低い) へ。
            let formant = 2200 - 1300 * min(1, x / 0.45)
            phase += 2 * .pi * f / SoundSynth.sampleRate
            var sample = 0.0
            var k = 1.0
            while k * f < 5000 {
                let h = k * f
                let resonance = 1 / (1 + pow((h - formant) / 500, 2))
                sample += sin(phase * k) * resonance / k
                k += 1
            }
            out[i] = sample * envelope[i]
        }
        return SoundSynth.normalize(out, peak: amplitude)
    }

    private static func missSamples() -> [Double] {
        // 「ぷー」と力の抜けた 2 音の下降（三角波でやわらかく）。
        var out: [Double] = []
        SoundSynth.mix(&out, SoundSynth.tone(0.14, from: 392, to: 349, amplitude: 0.5, decay: 0.1, shape: .triangle))
        SoundSynth.mix(&out, SoundSynth.tone(0.20, from: 311, to: 233, amplitude: 0.5, decay: 0.12, shape: .triangle), at: 0.14)
        return SoundSynth.normalize(out, peak: 0.55)
    }

    private static func clearSamples() -> [Double] {
        // 駆け上がる 4 音（C5 E5 G5 C6）で締め、そのあとに鳴き声。
        var out: [Double] = []
        let notes: [(Double, Double)] = [(523.25, 0), (659.25, 0.08), (783.99, 0.16), (1046.5, 0.24)]
        for (f, at) in notes {
            SoundSynth.mix(&out, SoundSynth.tone(at == 0.24 ? 0.22 : 0.10, from: f, amplitude: 0.45, decay: 0.08, shape: .triangle), at: at)
        }
        SoundSynth.mix(&out, meow(base: 680, peak: 1.4, duration: 0.36, amplitude: 0.8), at: 0.5)
        return SoundSynth.normalize(out, peak: 0.7)
    }

    private static func keySamples() -> [Double] {
        // 「チャリン」。金属の倍音を 2 回（鍵束が触れ合う感じ）。
        let bell: [(frequency: Double, amplitude: Double, decay: Double)] = [
            (2093, 1.0, 0.10), (3136, 0.6, 0.07), (4186, 0.35, 0.05),
        ]
        var out: [Double] = []
        SoundSynth.mix(&out, SoundSynth.partials(0.3, bell))
        SoundSynth.mix(&out, SoundSynth.partials(0.4, bell.map { ($0.frequency * 1.12, $0.amplitude, $0.decay * 1.4) }), at: 0.09, gain: 0.9)
        return SoundSynth.normalize(out, peak: 0.6)
    }
}
