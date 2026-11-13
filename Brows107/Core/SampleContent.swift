//
//  SampleContent.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 23/10/26.
//

import Foundation

enum SampleContent {
    static let fixturePages: [SavedPage] = [
        SavedPage(pageTitle: "How to brew coffee", pageURL: URL(string: "https://ncausa.org")!),
        SavedPage(
            pageTitle: "Liquid Glass overview", pageURL: URL(string: "https://developer.apple.com")!,
            recordedAt: .now.addingTimeInterval(-86400), shelfLabel: "Design"),
        SavedPage(
            pageTitle: "Product design in 2026", pageURL: URL(string: "https://uxcollective.cc")!,
            recordedAt: .now.addingTimeInterval(-259200), shelfLabel: "Design"),
        SavedPage(
            pageTitle: "SF Symbols 8 release notes", pageURL: URL(string: "https://developer.apple.com/sf-symbols/")!,
            recordedAt: .now.addingTimeInterval(-259200)),
    ]
    static let chatAnswer =
        "iOS 26 introduces Liquid Glass — a material that refracts what is behind it, so bars and sheets read as glass rather than flat panels. Controls got rounder, and the tab bar now floats above content."
    static let fixtureSummaryBullets: [(String, String)] = [
        (
            "Water temperature",
            "The ideal range is 195–205 °F. Hotter water pulls out bitter compounds, cooler water leaves the cup thin."
        ),
        ("Ratio", "Start at 1 : 16 — about 60 g of coffee per litre of water, then adjust to taste."),
        ("Brew time", "Pour-over takes 3–4 minutes, French press 4 minutes before pressing."),
    ]
    static let readerBody = """
        How to brew coffee at home

        Maria Lopez  ·  Aug 12, 2026  ·  6 min read

        Good coffee is mostly about four things: water, ratio, grind and time. Get those right and almost any bean will taste better than it did yesterday.

        Water temperature
        The ideal range is between 195° and 205° F. Above that the coffee turns bitter, below that it tastes thin and sour.

        Boil, then wait 30 seconds before pouring
        Preheat the brewer so it doesn’t steal heat
        Use filtered water — it changes more than the bean

        Start at 1 : 16 — sixty grams of coffee per litre of water — and adjust from there.

        Grind size
        Grind size controls how fast water passes through the bed. Too fine and the cup is harsh; too coarse and it tastes thin. A burr grinder produces an even particle size, which is why the result repeats from cup to cup.
        """
}
