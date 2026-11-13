//
//  UIColorProbe.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 04/11/26.
//

import UIKit

enum UIColorProbe {
    // Parses "rgb(r, g, b)" from the page.
    static func fromCSSRGB(_ cssRGB: String) -> UIColor? {
        let numbers = cssRGB.split(whereSeparator: { !$0.isNumber && $0 != "." }).compactMap { Double($0) }
        guard numbers.count >= 3 else { return nil }
        let alphaChannel = numbers.count >= 4 ? numbers[3] : 1
        guard alphaChannel > 0.05 else { return nil }
        return UIColor(red: numbers[0] / 255, green: numbers[1] / 255, blue: numbers[2] / 255, alpha: alphaChannel)
    }

    // Used to pick light or dark status bar content over a page.
    static func isLightBackground(_ color: UIColor) -> Bool {
        var redChannel: CGFloat = 0, greenChannel: CGFloat = 0, blueChannel: CGFloat = 0, alphaChannel: CGFloat = 0
        guard color.getRed(&redChannel, green: &greenChannel, blue: &blueChannel, alpha: &alphaChannel) else { return false }
        return (0.299 * redChannel + 0.587 * greenChannel + 0.114 * blueChannel) > 0.6
    }
}
