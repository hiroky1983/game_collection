import Testing
import Foundation
import Core
#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - 盤ゲームの着手音（#2767）

@Suite("盤ゲームの着手音（同梱ファイル）")
struct BoardSoundTests {

    @Test("5 つの音が同梱され、ファイルが見つかる", arguments: BoardSound.allCases)
    func bundledFileExists(sound: BoardSound) throws {
        let url = try #require(sound.url, "\(sound) の同梱ファイルが見つからない")
        #expect(url.pathExtension == BoardSound.fileExtension)
    }

    @Test("同梱ファイルは全部で 200KB 以内")
    func totalSizeWithinBudget() throws {
        let total = try BoardSound.allCases.reduce(0) { sum, sound in
            sum + (try Data(contentsOf: try #require(sound.url))).count
        }
        #expect(total <= 200_000)
    }

    #if canImport(AVFoundation)
    @Test("0.3 秒未満で、頭に無音が無く、ピークが -8dB 〜 -1dB")
    func durationLevelAndLeadingSilence() throws {
        for sound in BoardSound.allCases {
            let file = try AVAudioFile(forReading: try #require(sound.url))
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            #expect(seconds > 0.1 && seconds < 0.3, "\(sound) の長さが \(seconds) 秒")
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                         frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData?[0], count: Int(buffer.frameLength)))
            let peak = samples.map { abs($0) }.max() ?? 0
            let db = 20 * log10(Double(peak))
            #expect(db > -8 && db < -1, "\(sound) のピークが \(db)dB")
            // 先頭 10ms（無音の頭を詰めてあれば、もう音が立ち上がっている）
            let head = Int(file.processingFormat.sampleRate * 0.01)
            let headPeak = samples.prefix(head).map { abs($0) }.max() ?? 0
            #expect(headPeak > peak * 0.02, "\(sound) の頭に無音が残っている")
        }
    }
    #endif

    @Test("触覚は従来どおり手応え（medium）で、音の対象")
    func hapticAndSound() {
        for sound in BoardSound.allCases {
            #expect(sound.haptic == .medium)
            #expect(FeedbackImpact.board(sound).hasSound)
        }
        #expect(SoundEffect(FeedbackImpact.board(.goStone)) == .medium)
    }

    @Test("同じ盤の音の連打は間引かれ、別の音は鳴る")
    func throttle() {
        var throttle = SoundThrottle(minimumInterval: 0.04)
        let first = throttle.shouldPlay(BoardSound.goStone, now: 1.0)
        let repeated = throttle.shouldPlay(BoardSound.goStone, now: 1.01)
        let other = throttle.shouldPlay(BoardSound.chessPiece, now: 1.01)
        let after = throttle.shouldPlay(BoardSound.goStone, now: 1.05)
        #expect(first && !repeated && other && after)
    }

    @MainActor
    @Test("音と触覚の設定がオフなら、盤の音は下位サービスへ届かない")
    func disabledSettingSilencesBoardSound() {
        final class Spy: FeedbackService {
            var impacts: [FeedbackImpact] = []
            func impact(_ style: FeedbackImpact) { impacts.append(style) }
            func notify(_ type: FeedbackNotice) {}
        }
        let spy = Spy()
        var enabled = false
        let gated = GatedFeedbackService(base: spy, isEnabled: { enabled })
        gated.impact(.board(.shogiPiece))
        #expect(spy.impacts.isEmpty)
        enabled = true
        gated.impact(.board(.shogiPiece))
        #expect(spy.impacts == [.board(.shogiPiece)])
    }
}
