//
//  BrowserHomeView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 06/10/26.
//

import SwiftUI
import WebKit


/// Shortcut tile on the home screen.
struct HomeSite: Identifiable {
    let id = UUID()
    let headingText: String
    let domain: String
    let icon: String
}

/// Start page: greeting, shortcuts and recent pages.
struct BrowserHomeView: View {
    @Environment(BrowserStore.self) private var vault
    @Environment(\.colorScheme) private var interfaceScheme
    @State private var showPrivateDetails = false
    /// Hero title sits 130 pt from the physical top of the screen.
    private static let heroTop: CGFloat = 130
    @State private var homeScrollMinY: CGFloat = 0
    private let sites: [HomeSite] = [
        HomeSite(headingText: "Wikipedia", domain: "wikipedia.org", icon: AssetCatalog.homeSiteIcon(slug: "wikipedia")),
        HomeSite(headingText: "YouTube", domain: "youtube.com", icon: AssetCatalog.homeSiteIcon(slug: "youtube")),
        HomeSite(headingText: "Reddit", domain: "reddit.com", icon: AssetCatalog.homeSiteIcon(slug: "reddit")),
        HomeSite(headingText: "GitHub", domain: "github.com", icon: AssetCatalog.homeSiteIcon(slug: "github")),
        HomeSite(headingText: "Amazon", domain: "amazon.com", icon: AssetCatalog.homeSiteIcon(slug: "amazon")),
        HomeSite(headingText: "Instagram", domain: "instagram.com", icon: AssetCatalog.homeSiteIcon(slug: "instagram")),
        HomeSite(headingText: "Maps", domain: "maps.apple.com", icon: AssetCatalog.homeSiteIcon(slug: "maps")),
        HomeSite(headingText: "Figma", domain: "figma.com", icon: AssetCatalog.homeSiteIcon(slug: "figma")),
    ]
    private let siteColumns = Array(repeating: GridItem(.fixed(60), spacing: 32.67, alignment: .top), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: vault.incognito ? 25 : 24) {
                heading
                if !vault.incognito { homePromptStrip }
                siteGrid
                recentPages.padding(.top, vault.incognito ? -4 : 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, homeTopPadding)
            .padding(.bottom, 150)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .browsScrollEdgeEffectHidden()
        .ignoresSafeArea(.container, edges: .top)
        .background {
            HomeScreenBleed { _, scrollMinY in
                if abs(homeScrollMinY - scrollMinY) > 0.5 { homeScrollMinY = scrollMinY }
            }
        }
        .background { ClearHostBackdrop() }
        .background(Color.clear)
        .onAppear { homeScrollMinY = 0 }
        // sheet for the current route
        .sheet(isPresented: $showPrivateDetails) {
            NavigationStack {
                List {
                    Label("Pages opened here stay out of your history.", systemImage: "hand.raised.fill")
                    Label("AI won’t read pages in private tabs.", systemImage: "sparkles")
                    Label("Trackers stay blocked while you browse.", systemImage: "eye.slash")
                }
                .navigationTitle("Private browsing")
                .navigationBarTitleDisplayMode(.inline)
                .browsLiquidNavBar()
                // native toolbar, so the glass comes for free
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPrivateDetails = false } } }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    /// Window Y of the home scroll content — bleed uses 0 when the scroll is full-screen.
    private var homeTopPadding: CGFloat {
        max(8, Self.heroTop - homeScrollMinY)
    }

    // the heading block
    private var heading: some View {
        VStack(alignment: .leading, spacing: vault.incognito ? 10 : 10) {
            Text(vault.incognito ? "You’re browsing privately" : "Ask any page")
                .font(.ui(34, weight: .regular))
                .tracking(vault.incognito ? 0.4 : 0.05)
                .foregroundStyle(vault.incognito ? .white : .primary)
                .lineLimit(vault.incognito ? 1 : 2)
                .minimumScaleFactor(vault.incognito ? 0.78 : 0.82)
                .frame(minHeight: 41, alignment: .leading)
            Text(
                vault.incognito
                    ? "Pages you open here won’t appear in your history, and AI won’t read them."
                    : "Summarize, pull out key points, or just ask."
            )
            .font(.ui(15))
            .foregroundStyle(vault.incognito ? Palette.rgb(0xEBEBF5).opacity(0.7) : .secondary)
            .fixedSize(horizontal: false, vertical: true)
            if vault.incognito {
                Button("What private mode does") { showPrivateDetails = true }
                    .font(.ui(15, weight: .semibold))
                    .foregroundStyle(Palette.rgb(0x7C5CFF))
                    .padding(.top, 4).padding(.leading, 2)
            }
        }
        .offset(y: vault.incognito ? 0 : -1.5)
    }

    // Home prompt strip section
    private var homePromptStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(["What changed in iOS 26?", "Compare two products", "Explain a topic simply"], id: \.self) { prompt in
                    let chipWidth: CGFloat =
                        prompt == "What changed in iOS 26?" ? 232 : prompt == "Compare two products" ? 216 : 206
                    Button {
                        vault.chromePane = 1
                        vault.composerDraft = prompt
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "message").font(.ui(15)).foregroundStyle(Palette.brandInk).frame(
                                width: 20, height: 18)
                            Text(prompt).font(.ui(15)).foregroundStyle(interfaceScheme == .dark ? .white : .primary)
                        }
                        .padding(.leading, 14)
                        .padding(.trailing, 16)
                        .frame(width: chipWidth, height: 40, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .background(interfaceScheme == .dark ? Palette.raisedFill : .white, in: Capsule())
                }
            }.padding(.horizontal, 20)
        }
        .frame(height: 40)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .padding(.horizontal, -20)
    }

    // Site grid (view)
    private var siteGrid: some View {
        LazyVGrid(columns: siteColumns, alignment: .leading, spacing: 14) {
            ForEach(sites) { site in
                Button {
                    vault.navigateInput(site.domain)
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    vault.incognito
                                        ? Palette.rgb(0x0B0713) : interfaceScheme == .dark ? Palette.raisedFill : .white
                                )
                                .frame(width: 60, height: 60)
                                .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
                                .shadow(color: Color.black.opacity(0.04), radius: 20, y: 8)
                            Image(site.icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        Text(site.headingText)
                            .font(.ui(12))
                            .foregroundStyle(vault.incognito ? Palette.rgb(0xEBEBF5).opacity(0.7) : .secondary)
                            .frame(width: 60, height: 16)
                            .lineLimit(1)
                    }
                    .frame(width: 60)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder private var recentPages: some View {
        if vault.incognito {
            VStack(spacing: 0) {
                privacyRow("History isn’t saved", menuGlyph: "hand.raised")
                privacyRow("AI doesn’t read these pages", menuGlyph: "sparkles")
                privacyRow("Trackers stay blocked", menuGlyph: "eye.slash")
            }
            .padding(.vertical, 6)
            .background(Palette.rgb(0x151027), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if vault.visitLedger.isEmpty {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(Palette.brandWash).frame(width: 64, height: 64)
                    Image(systemName: "clock")
                        .font(.ui(28, weight: .regular))
                        .foregroundStyle(Palette.brandInk)
                }
                Text("No recent pages")
                    .font(.ui(17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.top, 18)
                Text("Pages you visit will show up here.")
                    .font(.ui(15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent").font(.ui(13, weight: .semibold)).foregroundStyle(.tertiary).frame(height: 18)
                VStack(spacing: 2) {
                    ForEach(Array(vault.visitLedger.prefix(3).enumerated()), id: \.element.id) { index, page in
                        HStack(spacing: 10) {
                            Button {
                                vault.navigateInput(page.pageURL.absoluteString)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock").font(.ui(15, weight: .regular)).foregroundStyle(.primary)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(page.pageTitle).font(.ui(17)).foregroundStyle(.primary).lineLimit(1)
                                        Text(
                                            (page.pageURL.host ?? "") + " · "
                                                + (vault.launchScenario != nil
                                                    ? ["Visited 2 hours ago", "Visited yesterday", "Visited 3 days ago"][index]
                                                    : page.recordedAt.formatted(.relative(presentation: .named)))
                                        ).font(.ui(15)).foregroundStyle(.tertiary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }.buttonStyle(.plain)
                            if vault.hasAiAnswer(page.pageURL) {
                                Image(systemName: "sparkle")
                                    .font(.ui(14, weight: .regular))
                                    .foregroundStyle(Palette.brandInk)
                                    .frame(width: 20)
                                    .accessibilityLabel("Saved AI answer")
                            }
                        }.frame(height: 64)
                    }
                }
            }
            .offset(y: 0.2)
        }
    }
}

// MARK: - Private helpers
extension BrowserHomeView {
    // privacy row
    private func privacyRow(_ headingText: String, menuGlyph: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: menuGlyph)
                .font(.ui(15, weight: .regular))
                .foregroundStyle(Palette.rgb(0x7C5CFF))
                .frame(width: 22, height: 22)
            Text(headingText)
                .font(.ui(15))
                .foregroundStyle(Palette.rgb(0xEBEBF5).opacity(0.7))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 42)
    }
}

struct BrowserMenuAction: Identifiable {
    let headingText: String
    let menuGlyph: String
    var action: (() -> Void)? = nil
    var shareURL: URL? = nil
    var id: String { headingText }
}
