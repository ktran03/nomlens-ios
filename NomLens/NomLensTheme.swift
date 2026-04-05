import SwiftUI

// MARK: - NomLens Brand Colors
//
// Mirrors the design system on nomlens.com.
// Light mode accent: Lacquer 500 (#c63f2b)
// Dark  mode accent: Lacquer 400 (#e05a47)

enum NomTheme {

    // MARK: Lacquer (brand primary — Vietnamese lacquerware red)
    static let lacquer50  = Color(nomHex: 0xfdf2f0)
    static let lacquer100 = Color(nomHex: 0xfce0da)
    static let lacquer200 = Color(nomHex: 0xf7b8ad)
    static let lacquer300 = Color(nomHex: 0xf08070)
    static let lacquer400 = Color(nomHex: 0xe05a47)  // dark-mode accent
    static let lacquer500 = Color(nomHex: 0xc63f2b)  // primary
    static let lacquer600 = Color(nomHex: 0xa8301f)
    static let lacquer700 = Color(nomHex: 0x882516)
    static let lacquer800 = Color(nomHex: 0x661a0e)
    static let lacquer900 = Color(nomHex: 0x451008)

    // MARK: Parchment (warm off-white — aged manuscript paper)
    static let parchment50  = Color(nomHex: 0xfdfaf4)
    static let parchment100 = Color(nomHex: 0xf7f0e0)
    static let parchment200 = Color(nomHex: 0xede0c4)
    static let parchment300 = Color(nomHex: 0xd9c9a3)

    // MARK: Gold (accent — temple gilding)
    static let gold300 = Color(nomHex: 0xd4a84b)
    static let gold400 = Color(nomHex: 0xb8902a)

    // MARK: Stone (neutrals)
    static let stone50  = Color(nomHex: 0xf5f5f4)
    static let stone200 = Color(nomHex: 0xe5e7eb)
    static let stone400 = Color(nomHex: 0x9ca3af)
    static let stone500 = Color(nomHex: 0x6b7280)
    static let stone600 = Color(nomHex: 0x4b5563)
    static let stone700 = Color(nomHex: 0x374151)
    static let stone800 = Color(nomHex: 0x1f2937)
    static let stone900 = Color(nomHex: 0x111827)
    static let stone950 = Color(nomHex: 0x0f172a)  // hero background
}

// MARK: - Convenience hex initialiser

extension Color {
    init(nomHex value: UInt32) {
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8)  & 0xFF) / 255
        let b = Double(value         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
