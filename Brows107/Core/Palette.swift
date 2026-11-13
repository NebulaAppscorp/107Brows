//
//  Palette.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 28/10/26.
//

import SwiftUI

enum Palette {
    static func rgb(_ slot: Int) -> Color {
        Color(
            red: Double((slot >> 16) & 255) / 255,
            green: Double((slot >> 8) & 255) / 255,
            blue: Double(slot & 255) / 255
        )
    }

    static let brandInk = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 39 / 255, green: 200 / 255, blue: 141 / 255, alpha: 1)
                : UIColor(red: 0, green: 135 / 255, blue: 90 / 255, alpha: 1)
        })
    static let brandWash = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 20 / 255, green: 72 / 255, blue: 56 / 255, alpha: 1)
                : UIColor(red: 230 / 255, green: 245 / 255, blue: 239 / 255, alpha: 1)
        })
    static let visitorInk = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? .white : .label
        })
    static let groupedFill = Color(uiColor: .systemGroupedBackground)
    static let canvasView = Color(uiColor: .systemBackground)
    static let raisedFill = Color(uiColor: .secondarySystemBackground)
    static let paywallUnselected = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .secondarySystemBackground
                : UIColor(red: 242 / 255, green: 245 / 255, blue: 243 / 255, alpha: 1)
        })
    static let paywallUnselectedStroke = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .separator
                : UIColor(red: 214 / 255, green: 226 / 255, blue: 220 / 255, alpha: 1)
        })
    static let chromeTrack = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.tertiarySystemFill
                : UIColor(red: 239 / 255, green: 245 / 255, blue: 242 / 255, alpha: 0.5)
        })
    static let toolbarFade = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.systemBackground.withAlphaComponent(0.72)
                : UIColor.white.withAlphaComponent(0.18)
        })
    static let readerChrome = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 28 / 255, green: 30 / 255, blue: 29 / 255, alpha: 1)
                : UIColor(red: 242 / 255, green: 245 / 255, blue: 243 / 255, alpha: 1)
        })
    static let mutedLabel = Color(uiColor: .secondaryLabel)
    static let surfaceChipSelected = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 58 / 255, green: 58 / 255, blue: 60 / 255, alpha: 1)
                : .white
        })
    static let composerChip = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? .tertiarySystemFill : .white
        })
}
