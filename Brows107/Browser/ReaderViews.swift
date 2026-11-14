//
//  ReaderViews.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 07/11/26.
//

import SwiftUI
import UIKit


/// Reader mode controls.
struct ReaderChromeView: View {
    var headingText: String
    var pageText: String
    var onShowOriginal: () -> Void
    @State private var bodyFontSize: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Reader")
                    .font(.ui(15, weight: .semibold))
                    .foregroundStyle(Palette.mutedLabel)
                Spacer()
                HStack(spacing: 18) {
                    Menu {
                        Button {
                            bodyFontSize = max(14, bodyFontSize - 2)
                        } label: {
                            Label("Smaller Text", systemImage: "textformat.size.smaller")
                        }
                        Button {
                            bodyFontSize = 18
                        } label: {
                            Label("Default Text Size", systemImage: "textformat")
                        }
                        Button {
                            bodyFontSize = min(30, bodyFontSize + 2)
                        } label: {
                            Label("Larger Text", systemImage: "textformat.size.larger")
                        }
                    } label: {
                        Image(systemName: "textformat.size")
                            .font(.ui(17))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    Button("Show original", action: onShowOriginal)
                        .font(.ui(15, weight: .semibold))
                        .foregroundStyle(Palette.brandInk)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            // background goes behind everything
            .background(Palette.readerChrome.ignoresSafeArea(edges: .top))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(headingText.isEmpty ? "Reader" : headingText)
                        .font(.ui(30, weight: .semibold))
                        .tracking(-0.45)
                        .lineSpacing(6)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 36)
                        .padding(.bottom, 18)
                    if pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("This page doesn’t contain readable text.")
                            .font(.system(size: bodyFontSize))
                            .foregroundStyle(Palette.mutedLabel)
                    } else {
                        Text(pageText)
                            .font(.system(size: bodyFontSize))
                            .tracking(-0.3)
                            .lineSpacing(bodyFontSize * 0.35)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 120)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Palette.readerChrome.ignoresSafeArea())
    }
}

/// Demo article used for reader screens in debug builds.
struct SampleArticleView: View {
    var highlight: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("N")
                        .font(.ui(12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        // background fill
                        .background(Palette.brandInk, in: Circle())
                    Text("National Coffee Association")
                        .font(.ui(13, weight: .regular))
                    Spacer(minLength: 0)
                    Image(systemName: "magnifyingglass")
                        .font(.ui(15))
                        .foregroundStyle(Palette.mutedLabel)
                    Image(systemName: "line.3.horizontal")
                        .font(.ui(15))
                        .foregroundStyle(Palette.mutedLabel)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(height: 48)

                Rectangle()
                    .fill(Palette.rgb(0xd6e2dc))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 0) {
                    Text("COFFEE BASICS")
                        .font(.ui(12))
                        .foregroundStyle(Palette.brandInk)
                        .frame(height: 16, alignment: .top)
                        .padding(.top, 20)
                    Text("How to brew coffee at home")
                        .font(.ui(28, weight: .regular))
                        .browsExactLineHeight(34)
                        .offset(y: -0.5)
                        .padding(.top, 8)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Palette.brandWash)
                            .frame(width: 22, height: 22)
                        Text("Maria Lopez  ·  Aug 12, 2026  ·  6 min read")
                            .font(.ui(12))  
                            .foregroundStyle(Palette.mutedLabel)
                    }
                    .padding(.top, 12)

                    Image(AssetCatalog.articleHero)
                        .resizable()
                        .frame(height: 196)
                        .padding(.top, 18)

                    Text("A pour-over gives you the most control over the result.")
                        .font(.ui(12))
                        .foregroundStyle(Palette.mutedLabel.opacity(0.55))
                        .padding(.top, 8)

                    highlightedText(
                        "Good coffee is mostly about four things: water, ratio, grind and time. Get those right and almost any bean will taste better than it did yesterday.",
                        size: 17
                    )
                    .browsExactLineHeight(22)
                    .padding(.top, 22)

                    Text("Water temperature")
                        .font(.ui(20, weight: .regular))
                        .browsExactLineHeight(25)
                        .padding(.top, 24)
                    highlightedText(
                        "The ideal range is between 195° and 205° F. Above that the coffee turns bitter, below it the cup tastes thin and sour.",
                        size: 17, color: Palette.mutedLabel
                    )
                    .browsExactLineHeight(22)  
                    .padding(.top, 10)

                    VStack(alignment: .leading, spacing: 8) {
                        bullet("Boil, then wait 30 seconds before pouring")
                        bullet("Preheat the brewer so it doesn’t steal heat")
                        bullet("Use filtered water — it changes more than the bean")
                    }
                    .padding(.top, 14)

                    HStack(alignment: .top, spacing: 14) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Palette.brandInk)
                            .frame(width: 3, height: 44)
                        highlightedText(
                            "Start at 1 : 16 — sixty grams of coffee per litre of water — and adjust from there.", size: 17
                        )
                        .browsExactLineHeight(22)
                    }
                    .padding(.top, 16)

                    Text("Grind size")
                        .font(.ui(20, weight: .regular))
                        .browsExactLineHeight(25)
                        .padding(.top, 24)
                    highlightedText(
                        "Grind size controls how fast water passes through the bed. Too fine and the cup is harsh; too coarse and it tastes thin. A burr grinder produces an even particle size, which is why the result repeats from cup to cup.",
                        size: 17, color: Palette.mutedLabel
                    )
                    .browsExactLineHeight(22)
                    .padding(.top, 10)

                    Text("Read next")
                        .font(.ui(13))
                        .foregroundStyle(Palette.mutedLabel.opacity(0.55))
                        .padding(.top, 28)
                    readNextRow("Choosing a burr grinder")
                    Rectangle().fill(Palette.rgb(0xd6e2dc)).frame(height: 1)
                    readNextRow("How water hardness changes taste")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
                .offset(y: -0.5)
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .browsScrollEdgeEffectHidden()
        .safeAreaPadding(.top, 0)
        .background(Palette.canvasView.ignoresSafeArea(edges: .top))
        .ignoresSafeArea(.container, edges: .top)
    }
}

// MARK: - Subviews
extension SampleArticleView {
    // bullet
    private func bullet(_ draftText: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Palette.brandInk).frame(width: 6, height: 6).padding(.top, 8)
            highlightedText(draftText, size: 17, color: Palette.mutedLabel).browsExactLineHeight(22)    
        }
    }

    private func readNextRow(_ headingText: String) -> some View {
        HStack {
            Text(headingText).font(.ui(15))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.ui(12, weight: .semibold))
                .foregroundStyle(Palette.mutedLabel.opacity(0.55))
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func highlightedText(
        _ string: String, size: CGFloat, weight: Font.Weight = .regular, color: Color = .primary
    ) -> some View {
        if let highlight, !highlight.isEmpty {
            Text(highlightedAttributed(string, size: size, weight: weight, color: color))
        } else {
            Text(string).font(.ui(size, weight: weight)).foregroundColor(color)
        }
    }

    private func highlightedAttributed(_ string: String, size: CGFloat, weight: Font.Weight, color: Color) -> AttributedString {
        var attributed = AttributedString(string)
        attributed.font = .ui(size, weight: weight)
        attributed.foregroundColor = color
        let lower = string.lowercased()
        let needle = (highlight ?? "").lowercased()
        var searchStart = lower.startIndex
        while let range = lower.range(of: needle, range: searchStart..<lower.endIndex) {
            if let attrStart = AttributedString.Index(range.lowerBound, within: attributed),
                let attrEnd = AttributedString.Index(range.upperBound, within: attributed)
            {
                attributed[attrStart..<attrEnd].backgroundColor = Color(red: 1, green: 0.9, blue: 0.2)
            }
            searchStart = range.upperBound
        }
        return attributed
    } 
}
