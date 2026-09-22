// モック用の最小スタブ。本物の Core / GameChess の型を、この単体バイナリが要る分だけ再現する。
import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

public enum ChessColor: Int, CaseIterable { case white, black }
enum ChessPieceType: Int, CaseIterable { case pawn, knight, bishop, rook, queen, king }
struct ChessPiece: Equatable {
    var type: ChessPieceType
    var color: ChessColor
}

enum ChessBoardStyle {
    static let lightSquare = Color(hex: 0xF2DFBB)
    static let darkSquare = Color(hex: 0xB2884F)
    static let whitePieceTop = Color(hex: 0xFEFAF0)
    static let whitePieceBottom = Color(hex: 0xE4D3B2)
    static let whitePieceLine = Color(hex: 0x4A3524)
    static let blackPieceTop = Color(hex: 0x50443A)
    static let blackPieceBottom = Color(hex: 0x22190F)
    static let blackPieceLine = Color(hex: 0xEFE2C6)
}
