import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 盤の拡大と移動の状態（#3238）。12×12 は iPhone SE だと 1 マスが 26pt 前後と小さいので、2 本指で寄って押せるようにする。
///
/// 座標は「盤の枠（正方形）の左上が原点」の点。`offset` は拡大した盤の左上が枠の左上からどれだけずれているか
/// （等倍は `.zero`、拡大中は盤が枠を覆う範囲に収まる 0 以下の値）。拡大した盤は枠の外に出ない。
struct CatPuzzleBoardZoom: Equatable {
    /// 拡大率の下限（等倍）と上限。
    static let minScale: CGFloat = 1
    static let maxScale: CGFloat = 2.5

    private(set) var scale: CGFloat = 1
    private(set) var offset: CGPoint = .zero

    var isZoomed: Bool { scale > Self.minScale }

    /// 枠上の点 `anchor` を動かさないまま、拡大率に `factor` を掛ける（ピンチ）。
    mutating func zoom(by factor: CGFloat, anchor: CGPoint, boardSide: CGFloat) {
        guard factor.isFinite, factor > 0 else { return }
        let next = min(max(scale * factor, Self.minScale), Self.maxScale)
        // アンカーの下にあった盤の点（等倍の座標）が、拡大後も同じ場所に来るように送る。
        let fixed = unzoomed(anchor)
        scale = next
        offset = CGPoint(x: anchor.x - fixed.x * next, y: anchor.y - fixed.y * next)
        clamp(boardSide: boardSide)
    }

    /// 枠の上で `delta` だけ盤を動かす（2 本指のドラッグ）。
    mutating func pan(by delta: CGPoint, boardSide: CGFloat) {
        offset = CGPoint(x: offset.x + delta.x, y: offset.y + delta.y)
        clamp(boardSide: boardSide)
    }

    mutating func reset() {
        self = CatPuzzleBoardZoom()
    }

    /// 枠上の点を、等倍の盤の座標へ戻す。マスの判定（`CatPuzzleModel.cell(at:)`）はこの座標で行う。
    func unzoomed(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.x) / scale, y: (point.y - offset.y) / scale)
    }

    private mutating func clamp(boardSide: CGFloat) {
        let slack = boardSide * (scale - 1)
        offset = CGPoint(x: min(max(offset.x, -slack), 0), y: min(max(offset.y, -slack), 0))
    }
}

#if canImport(UIKit)
/// 盤の上の 2 本指のピンチ（拡大）とドラッグ（移動）を拾う透明な層（#3238）。
///
/// SwiftUI の `DragGesture`（1 本指のタップ・スライド・#3116）と別に UIKit の認識器を使う。1 本指では始まらないので
/// ぶつからず、触れた指はそのまま下の SwiftUI へ届く（この層自身は触れを受けず、認識器を載せる先は所属する画面の
/// 親ビュー）。認識器が動き出したら `onBegan` で知らせ、盤は進行中の 1 本指の操作を取りやめる。
struct CatPuzzleZoomGestureHost: UIViewRepresentable {
    var onBegan: () -> Void
    /// 拡大率に掛ける倍率と、そのときの指の中心（この層＝盤の枠の座標）。
    var onPinch: (CGFloat, CGPoint) -> Void
    var onPan: (CGPoint) -> Void

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.isUserInteractionEnabled = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: HostView, context: Context) {
        view.onBegan = onBegan
        view.onPinch = onPinch
        view.onPan = onPan
    }

    static func dismantleUIView(_ view: HostView, coordinator: ()) {
        view.detach()
    }

    final class HostView: UIView, UIGestureRecognizerDelegate {
        var onBegan: () -> Void = {}
        var onPinch: (CGFloat, CGPoint) -> Void = { _, _ in }
        var onPan: (CGPoint) -> Void = { _ in }

        private lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        private lazy var pan: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 2
            return pan
        }()
        private weak var attachedTo: UIView?

        /// この層は触れを受けない（下の SwiftUI のタップ・スライドに任せる）。
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            guard window != nil, let host = sequence(first: next, next: { $0?.next }).compactMap({ $0 as? UIViewController }).first?.view else { return }
            for recognizer in [pinch, pan] as [UIGestureRecognizer] {
                recognizer.delegate = self
                recognizer.cancelsTouchesInView = false
                host.addGestureRecognizer(recognizer)
            }
            attachedTo = host
        }

        func detach() {
            attachedTo?.removeGestureRecognizer(pinch)
            attachedTo?.removeGestureRecognizer(pan)
            attachedTo = nil
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                onBegan()
            case .changed:
                onPinch(recognizer.scale, recognizer.location(in: self))
                recognizer.scale = 1
            default:
                break
            }
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                onBegan()
            case .changed:
                onPan(recognizer.translation(in: self))
                recognizer.setTranslation(.zero, in: self)
            default:
                break
            }
        }

        // 盤の枠の中で始まった触れだけ拾う。
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            bounds.contains(touch.location(in: self))
        }

        // ピンチと 2 本指のドラッグ、SwiftUI 側の認識器は同時に動いてよい。
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#else
struct CatPuzzleZoomGestureHost: View {
    var onBegan: () -> Void
    var onPinch: (CGFloat, CGPoint) -> Void
    var onPan: (CGPoint) -> Void

    var body: some View { Color.clear.allowsHitTesting(false) }
}
#endif
