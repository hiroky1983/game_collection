import Foundation

/// 長い・複雑な効果音（柵越えおじさんの場面ごとの音・`HomerunSound`）を合成する部品。
///
/// `ToneGenerator`（1 音ずつ並べる正弦波）では作れない、次の 4 つを足したもの:
/// - ノイズを帯域フィルタ（RBJ の 2 次の IIR）に通す（風切り・空気の抜け・擦れ・合成の歓声）
/// - 周波数を滑らかに動かす（指数カーブ・位相は連続）とビブラート
/// - 周波数ごとに減衰の速さを変えた正弦波の重ね合わせ（金属・ベルの鳴り）
/// - 複数の音を時刻をずらして重ね、最後に最大振幅をそろえる
///
/// 式は試作（scratchpad の `homerun-sfx/work/synth.py`）をそのまま移したもの。ノイズの乱数だけは
/// 音ごとに種を固定した決定的な乱数（`SoundSynth(seed:)`）にして、同じ音は毎回同じ波形になるようにしてある
/// （テストで固定でき、起動ごとに音が変わらない）。
///
/// サンプリング周波数は `ToneGenerator` と同じ 22.05kHz（5kHz 程度までの音しか使わない）。
public struct SoundSynth {
    public static let sampleRate = ToneGenerator.sampleRate

    /// ノイズ用の乱数（SplitMix64）。
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    /// 秒 → サンプル数（切り捨て・試作と同じ）。
    public static func count(_ seconds: Double) -> Int {
        max(0, Int(seconds * sampleRate))
    }

    // MARK: 乱数

    private mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// `lower...upper` の一様乱数。
    public mutating func uniform(_ lower: Double, _ upper: Double) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return lower + (upper - lower) * unit
    }

    // MARK: 重ねる・そろえる

    /// `source` を `dst` の `at` 秒の所へ `gain` 倍で足す（足りなければ `dst` を伸ばす）。
    public static func mix(_ dst: inout [Double], _ source: [Double], at seconds: Double = 0, gain: Double = 1) {
        let offset = count(seconds)
        let need = offset + source.count
        if dst.count < need { dst.append(contentsOf: repeatElement(0, count: need - dst.count)) }
        for (i, v) in source.enumerated() { dst[offset + i] += v * gain }
    }

    /// 最大振幅を `peak` にそろえる（無音はそのまま）。
    public static func normalize(_ signal: [Double], peak: Double) -> [Double] {
        let m = signal.reduce(0) { max($0, abs($1)) }
        guard m > 1e-9 else { return signal }
        return signal.map { $0 * peak / m }
    }

    // MARK: 包絡

    /// 立ち上がり `attack` 秒の直線 + 時定数 `decay` 秒の指数減衰（`decay` が 0 以下なら減衰しない）。
    /// 末尾 10ms は 0 へ向けてフェードする（終わりでプツッと鳴らない）。
    public static func exponentialEnvelope(length: Int, attack: Double, decay: Double) -> [Double] {
        let a = Double(max(1, count(attack)))
        let fade = count(0.01)
        return (0..<length).map { i in
            let t = Double(i) / sampleRate
            var e = min(1, Double(i) / a) * (decay > 0 ? exp(-max(0, t - attack) / decay) : 1)
            if fade > 0, i > length - fade { e *= Double(length - i) / Double(fade) }
            return e
        }
    }

    /// 山なりの包絡（風切り・上昇音向け）。`peak` は山の位置（0〜1）、`power` が大きいほど山が尖る。両端は 0。
    public static func bellEnvelope(length: Int, peak: Double, power: Double) -> [Double] {
        (0..<length).map { i in
            let x = Double(i) / Double(length)
            return x < peak ? pow(x / peak, power) : pow((1 - x) / (1 - peak), power)
        }
    }

    // MARK: 正弦波

    public enum Shape: Sendable {
        case sine
        case triangle
    }

    /// 周波数を `from` → `to` へ指数カーブで動かす正弦波（位相は連続）。
    /// `vibrato` は周波数の揺れの深さ（割合）、`vibratoRate` はその速さ（Hz）。
    public static func tone(_ duration: Double, from f0: Double, to f1: Double? = nil, amplitude: Double = 1,
                            attack: Double = 0.003, decay: Double = 0.1,
                            vibrato: Double = 0, vibratoRate: Double = 0, shape: Shape = .sine) -> [Double] {
        let f1 = f1 ?? f0
        let length = count(duration)
        let envelope = exponentialEnvelope(length: length, attack: attack, decay: decay)
        var out = [Double]()
        out.reserveCapacity(length)
        var phase = 0.0
        for i in 0..<length {
            let x = Double(i) / Double(length)
            var f = f0 > 0 && f1 > 0 ? f0 * pow(f1 / f0, x) : f0 + (f1 - f0) * x
            if vibrato != 0 { f *= 1 + vibrato * sin(2 * .pi * vibratoRate * Double(i) / sampleRate) }
            phase += 2 * .pi * f / sampleRate
            var s = sin(phase)
            if shape == .triangle { s = 2 / .pi * asin(s) }
            out.append(s * amplitude * envelope[i])
        }
        return out
    }

    /// 金属・ベル系: 周波数ごとに大きさと減衰の速さを変えた正弦波の重ね合わせ。
    public static func partials(_ duration: Double, _ list: [(frequency: Double, amplitude: Double, decay: Double)],
                                attack: Double = 0.001) -> [Double] {
        var out = [Double](repeating: 0, count: count(duration))
        for p in list {
            mix(&out, tone(duration, from: p.frequency, amplitude: p.amplitude, attack: attack, decay: p.decay))
        }
        return out
    }

    // MARK: ノイズ

    /// RBJ（Audio EQ Cookbook）の 2 次フィルタ。係数は途中で入れ替えられる（中心周波数を動かす）。
    public struct Biquad {
        public enum Kind: Sendable {
            case bandPass
            case lowPass
            case highPass
        }

        private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        private var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0

        public init() {}

        /// 係数を決める。`frequency` は 20Hz〜ナイキストの 0.9 倍に丸める（発散しない範囲）。
        public mutating func set(_ kind: Kind, frequency: Double, q: Double) {
            let f = min(max(frequency, 20), SoundSynth.sampleRate * 0.45)
            let w = 2 * Double.pi * f / SoundSynth.sampleRate
            let c = cos(w), s = sin(w)
            let alpha = s / (2 * q)
            var n0: Double, n1: Double, n2: Double
            switch kind {
            case .bandPass:
                (n0, n1, n2) = (alpha, 0, -alpha)
            case .lowPass:
                (n0, n1, n2) = ((1 - c) / 2, 1 - c, (1 - c) / 2)
            case .highPass:
                (n0, n1, n2) = ((1 + c) / 2, -(1 + c), (1 + c) / 2)
            }
            let a0 = 1 + alpha
            b0 = n0 / a0; b1 = n1 / a0; b2 = n2 / a0
            a1 = -2 * c / a0; a2 = (1 - alpha) / a0
        }

        public mutating func step(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }

    /// フィルタを通したホワイトノイズ。中心（遮断）周波数を `from` → `to` へ指数カーブで動かせる。
    /// `envelope` を渡さなければ `exponentialEnvelope(attack:decay:)`。
    public mutating func noise(_ duration: Double, _ kind: Biquad.Kind, from f0: Double, to f1: Double? = nil, q: Double = 1,
                               amplitude: Double = 1, envelope: [Double]? = nil,
                               attack: Double = 0.002, decay: Double = 0.1) -> [Double] {
        let f1 = f1 ?? f0
        let length = Self.count(duration)
        let e = envelope ?? Self.exponentialEnvelope(length: length, attack: attack, decay: decay)
        var filter = Biquad()
        var out = [Double]()
        out.reserveCapacity(length)
        for i in 0..<length {
            // 係数の計算は重いので 16 サンプルごと（0.7ms）に入れ替える（試作と同じ）。
            if i % 16 == 0 {
                let x = Double(i) / Double(length)
                filter.set(kind, frequency: f0 * pow(f1 / f0, x), q: q)
            }
            out.append(filter.step(uniform(-1, 1)) * amplitude * (i < e.count ? e[i] : 0))
        }
        return out
    }

    /// 打撃の瞬間の短い破裂音（高域のノイズ）。
    public mutating func crack(_ duration: Double = 0.012, amplitude: Double = 1) -> [Double] {
        noise(duration + 0.02, .highPass, from: 2000, q: 0.7, amplitude: amplitude, attack: 0.0005, decay: duration / 2)
    }
}

public extension ToneGenerator {
    /// 合成済みの波形（-1〜1）を 16bit モノラル PCM の WAV バイト列にする（`SoundSynth` で作った音用）。
    static func wavData(samples: [Double], sampleRate: Double = ToneGenerator.sampleRate) -> Data {
        let pcm = samples.map { Int16(clamping: Int(($0 * 32_767).rounded())) }
        return riff(samples: pcm, sampleRate: Int(sampleRate))
    }
}
