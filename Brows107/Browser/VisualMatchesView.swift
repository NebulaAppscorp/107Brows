//
//  VisualMatchesView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 24/10/26.
//

import SwiftUI
import ImageIO
import LinkPresentation
import SafariServices
import UniformTypeIdentifiers

/// One result card.
struct VisualMatch: Identifiable {
    let tileKey: Int
    var id: Int { tileKey }
    let headingText: String
    let sourceHost: String
    var linkURL: String? = nil
    let tileHeight: CGFloat
    let gradientHexes: [Int]
    let locations: [Double]
    let gradientOrigin: UnitPoint
    let gradientEnd: UnitPoint
    var radialBackdrop = false
    static let review = [
        VisualMatch(
            tileKey: 0, headingText: "Vintage steel thermos", sourceHost: "etsy.com", tileHeight: 224,
            gradientHexes: [0xedf1ef, 0xb9c7c1, 0x6f837b], locations: [0, 0.55, 1], gradientOrigin: UnitPoint(x: 0.04, y: 0.25),
            gradientEnd: UnitPoint(x: 0.76, y: 0.94)),
        VisualMatch(
            tileKey: 1, headingText: "Thermos flask, 1970s", sourceHost: "ebay.com", tileHeight: 140,
            gradientHexes: [0xb9c7c1, 0xedf1ef], locations: [0, 1], gradientOrigin: .leading, gradientEnd: .trailing),
        VisualMatch(
            tileKey: 2, headingText: "Retro green thermos", sourceHost: "pinterest.com", tileHeight: 166,
            gradientHexes: [0xedf1ef, 0x6f837b], locations: [0, 1], gradientOrigin: .center, gradientEnd: .center,
            radialBackdrop: true),
        VisualMatch(
            tileKey: 3, headingText: "Stanley Classic 1.4 L", sourceHost: "amazon.com", tileHeight: 166,
            gradientHexes: [0xb9c7c1, 0x6f837b], locations: [0, 1], gradientOrigin: .top, gradientEnd: .bottom),
        VisualMatch(
            tileKey: 4, headingText: "Insulated bottle, 1 L", sourceHost: "rei.com", tileHeight: 224,
            gradientHexes: [0x6f837b, 0xedf1ef], locations: [0, 1], gradientOrigin: UnitPoint(x: 0.19, y: 1),
            gradientEnd: UnitPoint(x: 0.92, y: 0.30)),
        VisualMatch(
            tileKey: 5, headingText: "Vacuum flask, steel", sourceHost: "alibaba.com", tileHeight: 140,
            gradientHexes: [0xb9c7c1, 0xedf1ef], locations: [0, 1], gradientOrigin: UnitPoint(x: 0.04, y: 0.25),
            gradientEnd: UnitPoint(x: 0.76, y: 0.94)),
    ]

    /// Pages returned by `POST /v2/chats/{chat_id}/messages` with the photo and `web_search=on`.
    static func fromSavedPages(_ savedPages: [SavedPage]) -> [VisualMatch] {
        let masonryHeights: [CGFloat] = [188, 152, 168, 168, 188, 152]
        let gradientPalettes: [[Int]] = [
            [0xedf1ef, 0xb9c7c1, 0x6f837b],
            [0xb9c7c1, 0xedf1ef],
            [0xedf1ef, 0x6f837b],
            [0xb9c7c1, 0x6f837b],
        ]
        return savedPages.enumerated().map { index, fixtureHit in
            VisualMatch(
                tileKey: index,
                headingText: fixtureHit.pageTitle.isEmpty ? (fixtureHit.pageURL.host ?? "Page") : fixtureHit.pageTitle,
                sourceHost: fixtureHit.pageURL.host ?? fixtureHit.pageURL.absoluteString,
                linkURL: fixtureHit.pageURL.absoluteString,
                tileHeight: masonryHeights[index % masonryHeights.count],
                gradientHexes: gradientPalettes[index % gradientPalettes.count],
                locations: index % gradientPalettes.count == 0 ? [0, 0.55, 1] : [0, 1],
                gradientOrigin: .topLeading,
                gradientEnd: .bottomTrailing
            )
        }
    }
}

enum VisualSearchState: String { case results, empty, unreadable, offline, loading }


struct PhotoPageTarget: Identifiable {
    let id = UUID()
    let url: URL
}

struct InAppPhotoPage: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .done
        controller.preferredControlTintColor = UIColor(Palette.brandInk)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}


/// Grid of pages found for the photo.
struct VisualMatchesView: View {
    // keeps query snapshot
    var querySnapshot: UIImage?
    var searchPhase: VisualSearchState = .results
    /// Nil keeps the review fixture grid. A real search passes the pages the API returned.
    var visualHits: [VisualMatch]?
    var answerText: String? = nil
    var questionMode = false
    var tapRetry: (() -> Void)?
    var retake: (() -> Void)?
    @Environment(BrowserStore.self) private var vault
    @Environment(\.dismiss) private var dismissSheet
    @State private var categoryFilter = "All"
    @State private var fullAnswerPresented = false
    @State private var presentedPage: PhotoPageTarget?
    private var visualCatalog: [VisualMatch] { visualHits ?? VisualMatch.review }
    private var visibleTiles: [VisualMatch] {
        switch categoryFilter {
        case "Shopping": return visualCatalog.filter { shopping($0) }
        case "Similar photos": return visualCatalog.filter { visual($0) || !shopping($0) }
        case "Pages": return visualCatalog.filter { !shopping($0) }
        default: return visualCatalog
        }
    }
    // keeps shopping hosts
    private static let shoppingHosts = [
        "amazon.", "ebay.", "etsy.", "walmart.", "aliexpress.", "alibaba.", "rei.", "target.", "bestbuy.",
        "store.", "shop.", "shopify.", "temu.", "ozon.", "wildberries.", "market.yandex.", "ikea.", "wayfair.", "newegg.",
        "bhphotovideo.",
    ]
    private static let photoHosts = [
        "pinterest.", "instagram.", "flickr.", "unsplash.", "pexels.", "shutterstock.", "gettyimages.",
        "youtube.", "youtu.be", "reddit.", "facebook.", "tiktok.", "behance.", "dribbble.", "makerworld.", "printables.",
        "thingiverse.",
    ]
    // shopping
    private func shopping(_ match: VisualMatch) -> Bool {
        let matchHost = match.sourceHost.lowercased()
        let linkURL = (match.linkURL ?? "").lowercased()
        if Self.shoppingHosts.contains(where: { matchHost.contains($0) }) { return true }
        return linkURL.contains("/products/") || linkURL.contains("/product/") || linkURL.contains("/shop/")
            || linkURL.contains("/dp/") || linkURL.contains("/item/")
    }
    private func visual(_ match: VisualMatch) -> Bool {
        let matchHost = match.sourceHost.lowercased()
        return Self.photoHosts.contains { matchHost.contains($0) }
    }
    private var matchBlurb: String {
        if questionMode {
            return visualCatalog.isEmpty ? "No direct matches" : "\(visualCatalog.count) direct matches"
        }
        return switch searchPhase {
        case .results: visualHits == nil ? "42 visual matches found" : "\(visualCatalog.count) visual matches found"
        case .empty: "No visual matches"
        case .unreadable: "Couldn’t read this image"
        case .offline: "Not sent yet"
        case .loading: "Looking for matches…"
        }
    }
    private var masonryVisible: Bool { searchPhase == .results || searchPhase == .loading }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Group {
                        if let querySnapshot {
                            Image(uiImage: querySnapshot).resizable().scaledToFill()
                        } else {
                            LinearGradient(
                                colors: [Palette.rgb(0xedf1ef), Palette.rgb(0x6f837b)], startPoint: UnitPoint(x: 0.04, y: 0.25),
                                endPoint: UnitPoint(x: 0.76, y: 0.94))
                        }
                    }.frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Your photo").font(.ui(15, weight: .semibold))
                        Text(matchBlurb).font(.ui(12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(.horizontal, 16).padding(.top, masonryVisible ? -5 : 10)
                if let answer = answerText?.trimmingCharacters(in: .whitespacesAndNewlines), !answer.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(answer)
                            .font(.ui(15))
                            .lineSpacing(3)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if answer.count > 240 {
                            Button("Read full answer") { fullAnswerPresented = true }
                                .font(.ui(13, weight: .semibold))
                                .foregroundStyle(Palette.brandInk)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                if masonryVisible {
                    ScrollView(.horizontal) { 
                        HStack(spacing: 8) {
                            ForEach(["All", "Shopping", "Similar photos", "Pages"], id: \.self) { slot in
                                Button {
                                    self.categoryFilter = slot
                                } label: {
                                    Text(slot).font(.ui(13, weight: .semibold)).tracking(-0.08).padding(.horizontal, 14)
                                        .frame(height: 34)  
                                        .foregroundStyle(categoryFilter == slot ? Color.white : Color(uiColor: .secondaryLabel))
                                }.buttonStyle(.plain).background(
                                    categoryFilter == slot
                                        ? Palette.brandInk
                                        : Color(
                                            uiColor: UIColor {
                                                $0.userInterfaceStyle == .dark
                                                    ? .secondarySystemBackground
                                                    : UIColor(red: 242 / 255, green: 245 / 255, blue: 243 / 255, alpha: 1)
                                            }), in: Capsule())
                            }
                        }.padding(.horizontal, 16)
                    }.scrollIndicators(.hidden).padding(.top, 21.33).padding(.bottom, 19.67)
                    ScrollView {
                        Group {
                            if searchPhase == .loading {
                                loadingGrid
                            } else {
                                let masonrySet = visibleTiles
                                let leftColumn = masonrySet.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
                                let rightColumn = masonrySet.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element)
                                HStack(alignment: .top, spacing: 12) {
                                    LazyVStack(spacing: 16) { ForEach(leftColumn) { card($0) } }
                                        .frame(maxWidth: .infinity)
                                    LazyVStack(spacing: 16) { ForEach(rightColumn) { card($0) } }
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .disabled(searchPhase == .loading)
                } else {
                    stateBlock
                }
            }
            .navigationTitle(questionMode ? "Photo answer" : "Visual matches").navigationBarTitleDisplayMode(.inline)
            .browsLiquidNavBar()
            // native toolbar, so the glass comes for free
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back", systemImage: "chevron.left") {
                        if let retake { retake() } else { dismissSheet() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New photo", systemImage: "camera") { if let retake { retake() } else { dismissSheet() } }
                }
            }
        }
        .sheet(isPresented: $fullAnswerPresented) {
            NavigationStack {
                ScrollView {
                    Text(answerText ?? "")
                        .font(.ui(16))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
                .navigationTitle("Photo answer")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { fullAnswerPresented = false }
                    }
                }
            }
        }
        // sheet for the current route
        .sheet(item: $presentedPage) { target in
            InAppPhotoPage(url: target.url)
                .ignoresSafeArea()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
    /// Empty, not recognised and offline states.
    private var stateBlock: some View {
        let unreadable = searchPhase == .unreadable
        let offline = searchPhase == .offline
        return VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(offline || unreadable ? Palette.rgb(0xFF383C) : Palette.brandWash)
                    .frame(width: 64, height: 64)
                Image(systemName: unreadable ? "exclamationmark.triangle.fill" : offline ? "wifi.slash" : "magnifyingglass")
                    .font(.ui(28))
                    .foregroundStyle(offline || unreadable ? .white : Palette.brandInk)
            }
            Text(unreadable ? "Couldn’t read this image" : offline ? "You’re offline" : "Nothing matched this photo")
                .font(.ui(20, weight: .semibold)).browsExactLineHeight(25)
                .padding(.top, 18)
            Text(
                unreadable
                    ? "The photo is too blurry or too dark. Take another one."
                    : offline
                        ? "The photo stays on your phone until you’re back online."
                        : "Try a clearer shot, or get closer to the object."
            )
            .font(.ui(15)).browsExactLineHeight(20).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
            .padding(.horizontal, unreadable ? 8 : 0)
            if let answer = answerText?.trimmingCharacters(in: .whitespacesAndNewlines), !answer.isEmpty {
                Text(answer) 
                    .font(.ui(15))
                    .lineLimit(5)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                if answer.count > 240 {
                    Button("Read full answer") { fullAnswerPresented = true }
                        .font(.ui(13, weight: .semibold))
                        .foregroundStyle(Palette.brandInk)
                        .padding(.top, 6)
                }
            }
            if unreadable {
                Button {
                    if let retake { retake() } else { dismissSheet() }
                } label: {
                    Text("Retake").font(.ui(17, weight: .semibold)).frame(width: 180, height: 48)
                }
                .browsGlassProminentButtonStyle().tint(Palette.brandInk)
                .controlSize(.small)
                .padding(.top, 22)
            } else if offline {
                Button {
                    tapRetry?()
                } label: {
                    Text("Try again").font(.ui(17, weight: .semibold)).frame(width: 180, height: 48)
                }
                .browsGlassProminentButtonStyle().tint(Palette.brandInk)
                .controlSize(.small)
                .padding(.top, 22)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: unreadable || offline ? 5 : 0)
        // enter/leave animation
        .transition(.opacity)
    }

    // the loading grid block
    private var loadingGrid: some View {
        let masonryHeights: [CGFloat] = [188, 152, 168, 168, 188, 152]
        let leftHeights = masonryHeights.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)    
        let rightLaneHeights = masonryHeights.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element)
        let fill = Color(uiColor: .secondarySystemFill) 
        return HStack(alignment: .top, spacing: 12) {
            LazyVStack(spacing: 16) {
                ForEach(Array(leftHeights.enumerated()), id: \.offset) { _, laneHeight in
                    skeletonCard(imageHeight: laneHeight, fill: fill)
                }
            }
            .frame(maxWidth: .infinity)
            LazyVStack(spacing: 16) {
                ForEach(Array(rightLaneHeights.enumerated()), id: \.offset) { _, laneHeight in
                    skeletonCard(imageHeight: laneHeight, fill: fill)
                }
            } 
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Private helpers
extension VisualMatchesView {
    // Skeleton card
    private func skeletonCard(imageHeight: CGFloat, fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 14)
                .fill(fill)
                .frame(maxWidth: .infinity)
                .frame(height: imageHeight)
            RoundedRectangle(cornerRadius: 4)
                .fill(fill)
                .frame(height: 20)
            RoundedRectangle(cornerRadius: 4)
                .fill(fill)
                .frame(width: 72, height: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }


    // card
    private func card(_ match: VisualMatch) -> some View {
        Button {
            openVisualMatch(match)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let matchAddress = match.linkURL, let matchPageURL = URL(string: matchAddress) {
                        PagePreviewImage(pageTargetURL: matchPageURL, match: match)
                    } else {
                        matchArtwork(match)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: cardImageHeight(match))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.headingText).font(.ui(15)).browsExactLineHeight(20).lineLimit(1).foregroundStyle(
                        .primary)
                    Text(match.sourceHost).font(.ui(12)).browsExactLineHeight(16).foregroundStyle(
                        Color(uiColor: .tertiaryLabel))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    // card image height
    private func cardImageHeight(_ match: VisualMatch) -> CGFloat {
        visualHits == nil ? match.tileHeight : min(max(match.tileHeight, 148), 188)
    }

    // Opens the visual match
    private func openVisualMatch(_ match: VisualMatch) {
        let raw = match.linkURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let openURL: String
        if let linkURL = URL(string: raw), ["http", "https"].contains(linkURL.scheme?.lowercased() ?? ""), linkURL.host != nil {
            openURL = linkURL.absoluteString
        } else if let host = URL(string: "https://\(match.sourceHost)")?.host {
            openURL = "https://\(host)"
        } else {
            vault.bannerText = "This link couldn’t be opened."
            return
        }
        guard let destination = URL(string: openURL) else {
            self.vault.bannerText = "This link couldn’t be opened."
            return
        }
        self.presentedPage = PhotoPageTarget(url: destination)
    }

    // match artwork
    private func matchArtwork(_ match: VisualMatch) -> some View {
        GeometryReader { geo in
            let gradient = Gradient(
                stops: zip(match.gradientHexes, match.locations).map { Gradient.Stop(color: Palette.rgb($0.0), location: $0.1) })
            Group {
                if match.radialBackdrop {
                    RadialGradient(gradient: gradient, center: .center, startRadius: 0, endRadius: 71)
                } else {
                    LinearGradient(gradient: gradient, startPoint: match.gradientOrigin, endPoint: match.gradientEnd)
                }
            }
            .frame(width: 100, height: 100)
            .scaleEffect(x: geo.size.width / 100, y: geo.size.height / 100, anchor: .topLeading)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}
