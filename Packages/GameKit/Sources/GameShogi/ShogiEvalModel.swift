import Foundation
#if canImport(CoreML)
import CoreML

/// 学習済み CoreML 評価関数のラッパー。
/// モデルが存在しない場合は nil を返し、呼び出し側がフォールバックする。
final class ShogiEvalModel: @unchecked Sendable {
    static let shared = ShogiEvalModel()

    private let model: MLModel?

    private init() {
        guard let url = Bundle.module.url(forResource: "ShogiEvalNet", withExtension: "mlmodelc")
                     ?? Bundle.module.url(forResource: "ShogiEvalNet", withExtension: "mlpackage") else {
            model = nil
            return
        }
        model = try? MLModel(contentsOf: url)
    }

    var isAvailable: Bool { model != nil }

    /// 局面の評価値を返す（手番視点、正規化済み floatスコア → centipawn換算して Int 返し）
    func evaluate(_ pos: Position) -> Int? {
        guard let model else { return nil }
        let features = PositionFeatures.encode(pos)

        guard let provider = try? ShogiEvalInput(features: features),
              let result = try? model.prediction(from: provider),
              let score = result.featureValue(for: "score")?.multiArrayValue else {
            return nil
        }

        let raw = score[0].floatValue  // [-∞, ∞] 想定
        // 正規化解除: train_eval.py で score / 1000.0 したので × 1000 で centipawn 相当に戻す
        return Int((raw * 1000).clamped(to: -50000...50000))
    }
}

// MARK: - MLFeatureProvider

private final class ShogiEvalInput: MLFeatureProvider {
    let featureNames: Set<String> = ["features"]
    private let array: MLMultiArray

    init(features: [Float]) throws {
        array = try MLMultiArray(shape: [1, NSNumber(value: PositionFeatures.size)], dataType: .float32)
        for (i, v) in features.enumerated() {
            array[i] = NSNumber(value: v)
        }
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        guard featureName == "features" else { return nil }
        return MLFeatureValue(multiArray: array)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#else

// CoreML が使えないプラットフォーム（Linux テスト環境など）用のスタブ
final class ShogiEvalModel: @unchecked Sendable {
    static let shared = ShogiEvalModel()
    var isAvailable: Bool { false }
    func evaluate(_ pos: Position) -> Int? { nil }
}

#endif
