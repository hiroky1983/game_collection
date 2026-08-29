import Foundation

/// 効果音の一音。合成に必要な最小限のパラメータだけを持つ。
public struct ToneStep: Equatable, Sendable {
    /// 基本周波数（Hz）。
    public let frequency: Double
    /// 長さ（秒）。
    public let duration: Double
    /// 振幅（0...1）。1 に近づけるほど大きく、割れやすくなる。
    public let amplitude: Double

    public init(frequency: Double, duration: Double, amplitude: Double) {
        self.frequency = frequency
        self.duration = duration
        self.amplitude = amplitude
    }
}

/// 効果音の種類。触覚の `FeedbackImpact` / `FeedbackNotice` と 1 対 1 に対応する。
///
/// 触覚と同じ呼び出し箇所に相乗りさせるための対応表であり、**各ゲームに新しい発火点は作らない**
/// （鳴りすぎの制御も既存の触覚と同じ 1 か所で済む）。
public enum SoundEffect: String, CaseIterable, Sendable {
    /// 軽い操作（1マス開く・カードを1枚めくる）。
    case light
    /// 手応えのある操作（着手・ペア成立・カード配り）。
    case medium
    /// 切り替え系（フラグの着脱・カードや牌の選択）。
    case rigid
    /// 勝ち・クリア。
    case success
    /// 引き分け・無効な操作の拒否。
    case warning
    /// 負け・ゲームオーバー。
    case error

    public init(_ impact: FeedbackImpact) {
        switch impact {
        case .light:  self = .light
        case .medium: self = .medium
        case .rigid:  self = .rigid
        }
    }

    public init(_ notice: FeedbackNotice) {
        switch notice {
        case .success: self = .success
        case .warning: self = .warning
        case .error:   self = .error
        }
    }

    /// 波形の定義。音源ファイルを同梱せずに実行時へ合成するため、
    /// 素材のライセンスとアプリサイズの問題が発生しない。
    ///
    /// いずれも 0.3 秒未満の短い音にしてある（操作のテンポを妨げないため）。
    public var steps: [ToneStep] {
        switch self {
        case .light:
            // めくり・1マス開く。高く短い「コッ」。
            return [ToneStep(frequency: 1046.50, duration: 0.045, amplitude: 0.22)]
        case .medium:
            // 着手・配り・ペア成立。低めで少し長く、手応えを出す。
            return [ToneStep(frequency: 659.25, duration: 0.075, amplitude: 0.32)]
        case .rigid:
            // 旗の着脱・選択のトグル。いちばん短くカチッと。
            return [ToneStep(frequency: 1318.51, duration: 0.035, amplitude: 0.25)]
        case .success:
            // 勝ち・クリア。C5 → E5 → G5 の上昇。
            return [
                ToneStep(frequency: 523.25, duration: 0.085, amplitude: 0.30),
                ToneStep(frequency: 659.25, duration: 0.085, amplitude: 0.30),
                ToneStep(frequency: 783.99, duration: 0.120, amplitude: 0.30),
            ]
        case .warning:
            // 拒否・引き分け。低く短い一音（不快にならない程度に抑える）。
            return [ToneStep(frequency: 233.08, duration: 0.100, amplitude: 0.26)]
        case .error:
            // 負け・ゲームオーバー。G4 → C4 の下降。
            return [
                ToneStep(frequency: 391.99, duration: 0.110, amplitude: 0.30),
                ToneStep(frequency: 261.63, duration: 0.160, amplitude: 0.30),
            ]
        }
    }

    /// そのまま `AVAudioPlayer(data:)` に渡せる WAV バイト列。
    public var wavData: Data { ToneGenerator.wavData(steps: steps) }
}

/// 同じ効果音の連打を間引く（受け入れ条件「連打しても音が重なって割れない」の一方の担保）。
///
/// 再生そのものは App 層（`AVAudioPlayer`）だが、間引きの判定はここに置いてテストできる形にする
/// （App ターゲットにはテストターゲットが無いため、App に置くと自動テストで守れない）。
/// 時刻は呼び出し側から渡す。App 層は**単調増加する時計**（`CACurrentMediaTime()`）を渡すこと。
public struct SoundThrottle {
    /// この間隔より短い連打では鳴らし直さない。
    public let minimumInterval: Double
    private var lastPlayedAt: [SoundEffect: Double] = [:]

    public init(minimumInterval: Double = 0.04) {
        self.minimumInterval = minimumInterval
    }

    /// 鳴らしてよいかを返す。true を返したときだけ発音時刻を記録する。
    ///
    /// - Parameter now: 単調増加する時計の現在値（秒）。
    public mutating func shouldPlay(_ effect: SoundEffect, now: Double) -> Bool {
        if let last = lastPlayedAt[effect], now >= last, now - last < minimumInterval {
            return false
        }
        // now < last（時計が巻き戻った）ときは間引かずに鳴らし、基準を取り直す。
        // 間引き続けて「音が出ない端末」になるより、一度多く鳴るほうが害が小さい。
        lastPlayedAt[effect] = now
        return true
    }
}

/// `ToneStep` の並びを 16bit モノラル PCM の WAV（RIFF）バイト列に合成する。
///
/// 音源ファイルを持たない代わりにこれで作る。UI の効果音は 2kHz 未満しか使わないため
/// サンプリング周波数は 22.05kHz で足りる（データ量は 44.1kHz の半分）。
public enum ToneGenerator {
    /// サンプリング周波数（Hz）。
    public static let sampleRate: Double = 22_050

    /// 立ち上がりの時間（秒）。0 から急に鳴らすとプツッとノイズが乗るため短く傾ける。
    private static let attack: Double = 0.004

    public static func wavData(steps: [ToneStep], sampleRate: Double = ToneGenerator.sampleRate) -> Data {
        var samples: [Int16] = []
        samples.reserveCapacity(steps.reduce(0) { $0 + Int($1.duration * sampleRate) + 1 })

        // 音が切り替わるところで波形が飛ばないよう位相は continuous に保つ。
        var phase = 0.0
        for step in steps {
            let count = Int((step.duration * sampleRate).rounded())
            guard count > 0 else { continue }
            let increment = 2 * .pi * step.frequency / sampleRate
            let attackSamples = max(1.0, attack * sampleRate)
            for i in 0..<count {
                let progress = Double(i) / Double(count)
                let envelope = min(1.0, Double(i) / attackSamples) * pow(1 - progress, 2)
                let value = sin(phase) * step.amplitude * envelope
                samples.append(Int16(clamping: Int((value * 32_767).rounded())))
                phase += increment
            }
            phase.formTruncatingRemainder(dividingBy: 2 * .pi)
        }

        return riff(samples: samples, sampleRate: Int(sampleRate))
    }

    private static func riff(samples: [Int16], sampleRate: Int) -> Data {
        let channels = 1
        let bitsPerSample = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = sampleRate * blockAlign
        let dataBytes = samples.count * blockAlign

        var data = Data()
        data.append(ascii: "RIFF")
        data.append(littleEndian: UInt32(36 + dataBytes))  // 以降のバイト数
        data.append(ascii: "WAVE")
        data.append(ascii: "fmt ")
        data.append(littleEndian: UInt32(16))              // fmt チャンクの長さ（PCM は 16）
        data.append(littleEndian: UInt16(1))               // 1 = リニア PCM
        data.append(littleEndian: UInt16(channels))
        data.append(littleEndian: UInt32(sampleRate))
        data.append(littleEndian: UInt32(byteRate))
        data.append(littleEndian: UInt16(blockAlign))
        data.append(littleEndian: UInt16(bitsPerSample))
        data.append(ascii: "data")
        data.append(littleEndian: UInt32(dataBytes))
        for sample in samples { data.append(littleEndian: UInt16(bitPattern: sample)) }
        return data
    }
}

private extension Data {
    mutating func append(ascii text: String) {
        append(contentsOf: Array(text.utf8))
    }

    mutating func append(littleEndian value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)])
    }

    mutating func append(littleEndian value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xFF),
            UInt8(value >> 8 & 0xFF),
            UInt8(value >> 16 & 0xFF),
            UInt8(value >> 24 & 0xFF),
        ])
    }
}
