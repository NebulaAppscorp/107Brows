//
//  AssetCatalog.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 08/11/26.
//

import Foundation

/// Names of the bundled images that are looked up by string.
enum AssetCatalog {
    static let articleHero = "article_hero"
    static let launchGlyph = "launch_glyph"
    static let launchCanvas = "launch_canvas"
    /// Soft green glow behind the status bar on home, chat and tabs.
    static let topGlow = "top_glow"

    // home site icon
    static func homeSiteIcon(slug: String) -> String { "site_\(slug)" }
}
