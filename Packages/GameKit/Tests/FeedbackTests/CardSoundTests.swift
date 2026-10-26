import Testing
import Foundation
import Core
#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - トランプの効果音（#2697）

@Suite("トランプの効果音（同梱ファイル）")
struct CardSoundTests {

    @Test("4 場面の音が同梱され、ファイルが見つかる", arguments: CardSound.allCases)
    func bundledFileExists(sound: CardSound) throws {
        let url = try #require(sound.url, "\(sound) の同梱ファイルが見つからない")
        #expect(url.pathExtension == CardSound.fileExtension)
    }

    @Test("同梱ファイルは全部で 200KB 以内")
    func totalSizeWithinBudget() throws {
        let total = try CardSound.allCases.reduce(0) { sum, sound in
            let url = try #require(sound.url)
            return sum + (try Data(contentsOf: url)).count
        }
        #expect(total <= 200_000)
    }

    #if canImport(AVFoundation)
    @Test("配る・めくる・出すは 0.3 秒未満、切るは 1 秒以内")
    func durations() throws {
        for sound in CardSound.allCases {
            let file = try AVAudioFile(forReading: try #require(sound.url))
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            #expect(seconds > 0.1, "\(sound) が短すぎる")
            if sound == .shuffle {
                #expect(seconds <= 1.0)
            } else {
                #expect(seconds < 0.3)
            }
        }
    }

    @Test("音量がそろっていて、割れていない（ピーク -8dB 〜 -1dB）")
    func levelsAreConsistentAndUnclipped() throws {
        for sound in CardSound.allCases {
            let file = try AVAudioFile(forReading: try #require(sound.url))
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                         frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let samples = UnsafeBufferPointer(start: buffer.floatChannelData?[0], count: Int(buffer.frameLength))
            let peak = samples.map { abs($0) }.max() ?? 0
            let db = 20 * log10(Double(peak))
            #expect(db > -8 && db < -1, "\(sound) のピークが \(db)dB")
        }
    }
    #endif

    @Test("触覚の強さは、配る・切る・出す＝手応え、めくる＝軽い")
    func hapticMapping() {
        #expect(CardSound.deal.haptic == .medium)
        #expect(CardSound.shuffle.haptic == .medium)
        #expect(CardSound.place.haptic == .medium)
        #expect(CardSound.flip.haptic == .light)
    }

    @Test("カードの音は効果音の対象（選ぶだけの操作とは違う）")
    func cardImpactHasSound() {
        for sound in CardSound.allCases {
            #expect(FeedbackImpact.card(sound).hasSound)
        }
    }

    @Test("同じカードの音の連打は間引かれ、別の音・別の種類は鳴る")
    func throttleThinsRepeatedCardSounds() {
        var throttle = SoundThrottle(minimumInterval: 0.04)
        let first = throttle.shouldPlay(CardSound.deal, now: 1.0)
        let repeated = throttle.shouldPlay(CardSound.deal, now: 1.01)
        let otherCard = throttle.shouldPlay(CardSound.flip, now: 1.01)
        let synthesized = throttle.shouldPlay(SoundEffect.medium, now: 1.01)
        let afterInterval = throttle.shouldPlay(CardSound.deal, now: 1.05)
        #expect(first)
        #expect(!repeated, "連続で配る音は重ねない")
        #expect(otherCard, "別のカードの音は鳴る")
        #expect(synthesized, "合成音と間引きの記録を共有しない")
        #expect(afterInterval)
    }
}
