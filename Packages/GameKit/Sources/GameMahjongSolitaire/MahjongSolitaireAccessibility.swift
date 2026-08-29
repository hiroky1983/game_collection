import Foundation
import MahjongTiles

/// 牌の VoiceOver 読み上げ文（#188）。
///
/// 盤面では「取れない牌」を暗く落とし、「選択中」「ヒント」を枠の色で表しているため、
/// 画面を見ないと絵柄も取れるかどうかも分からない。読み上げ文はここに集約して
/// 純関数にし、View を組まずにテストできるようにする。
public enum MahjongSolitaireAccessibility {
    /// 牌 1 枚の読み上げ文（例: "筒子の3、取れます、選択中"）。
    public static func tileLabel(
        face: MahjongFace,
        isBlocked: Bool,
        isSelected: Bool,
        isHinted: Bool
    ) -> String {
        var parts = [face.displayName]
        parts.append(isBlocked ? "取れません" : "取れます")
        if isSelected { parts.append("選択中") }
        if isHinted { parts.append("ヒント") }
        return parts.joined(separator: "、")
    }
}
