//
//  SettingsView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 03/11/26.  
//

import SwiftUI
import StoreKit
import WebKit


/// Settings sheet.
struct SettingsView: View {
    // current web lane
    let webLane: WebSession
    @Environment(BrowserStore.self) private var vault
    @Environment(\.dismiss) private var dismissSheet
    @Environment(\.requestReview) private var requestStoreReview
    @Environment(\.colorScheme) private var interfaceScheme
    @State private var checkoutStore = PurchaseStore()
    var body: some View {
        @Bindable var vault = vault
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        settingsSection("Pro") {
                            VStack(spacing: 0) {
                                Button {
                                    dismissSheet()
                                    Task {
                                        do {
                                            // Suspends here
                                            try await Task.sleep(for: .milliseconds(250))
                                        } catch {
                                            logSwallowed(error)
                                        }
                                        // animate the change
                                        withAnimation { vault.paywallUp = true }
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        settingsIcon("sparkles")
                                        if vault.launchScenario == nil, !vault.proEntitlementActive {
                                            VStack(alignment: .leading, spacing: 2) { 
                                                Text("Get Pro").font(.ui(17)).foregroundStyle(Palette.brandInk)
                                                Text("Unlimited answers and photo search").font(.ui(14))
                                                    .foregroundStyle(Palette.brandInk.opacity(0.58)).lineLimit(1)
                                                    .minimumScaleFactor(0.8)
                                            }
                                        } else if vault.launchScenario == nil, vault.proEntitlementActive {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Pro active").font(.ui(17)).foregroundStyle(.primary)
                                                Text("Page AI, chat, and photo search unlocked").font(.ui(14))
                                                    .foregroundStyle(.secondary).lineLimit(2)
                                            }
                                        } else {
                                            Text("Subscription").font(.ui(17)).browsExactLineHeight(22).foregroundStyle(
                                                .primary)
                                            Spacer(minLength: 8)
                                            // FIXME(Aleksandra): hard-coded date, read the real expiry from the entitlement
                                            Text("Active until Mar 12").font(.ui(17)).browsExactLineHeight(22)
                                                .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
                                        }
                                        Spacer(minLength: 0)
                                        if vault.launchScenario != nil {
                                            Image(systemName: "chevron.right").font(.ui(13, weight: .regular))
                                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                        }
                                    }.padding(.horizontal, 16).frame(height: 54)
                                }.buttonStyle(.plain)
                                settingsDivider
                                // plain button, styling comes from the modifiers
                                Button {
                                    Task {
                                        // wait for it before moving on
                                        await checkoutStore.restoreEntitlements()
                                        if let checkoutNotice = checkoutStore.checkoutNotice { vault.bannerText = checkoutNotice }
                                    }
                                } label: {
                                    settingsRowContent("Restore purchases", iconName: "arrow.clockwise", trailing: false)
                                }.buttonStyle(.plain)
                            }
                        }
                        settingsSection("General") {
                            VStack(spacing: 0) {
                                // Tap handler below
                                Button {
                                    // optional link url, may be missing
                                    if let linkURL = URL(string: BrowsSystemSettings.defaultBrowserOrAppSettings) {
                                        UIApplication.shared.open(linkURL)
                                    }
                                } label: {
                                    settingsRowContent("Default browser", iconName: "globe", trailing: true)
                                }.buttonStyle(.plain)
                                settingsDivider
                                NavigationLink {
                                    AIAssistantSettingsView()    
                                } label: {
                                    settingsRowContent("AI assistant", iconName: "bubble.left", trailing: true)
                                }.buttonStyle(.plain)
                            }
                        }
                        settingsSection("Appearance") {
                            Menu {
                                Button("System") { vault.chromeTheme = "System" }
                                Button("Light") { vault.chromeTheme = "Light" }
                                Button("Dark") { vault.chromeTheme = "Dark" }
                            } label: {
                                HStack(spacing: 10) {
                                    settingsIcon("circle.lefthalf.filled")
                                    Text("Theme").font(.ui(17)).browsExactLineHeight(22).foregroundStyle(.primary)
                                    Spacer()
                                    Text(vault.chromeTheme).font(.ui(17)).browsExactLineHeight(22).foregroundStyle(
                                        .secondary)
                                    Image(systemName: "chevron.right").font(.ui(13, weight: .regular)).foregroundStyle(
                                        Color(uiColor: .tertiaryLabel))
                                }.padding(.horizontal, 16).frame(height: 54)
                            }.buttonStyle(.plain)
                        }
                        settingsSection("Data") {
                            NavigationLink {
                                ClearDataView(webLane: webLane)
                            } label: {
                                settingsRowContent("Clear browsing data", iconName: "trash", trailing: true)
                            }.buttonStyle(.plain)
                        }
                        settingsSection("About") {
                            VStack(spacing: 0) {
                                // plain button, styling comes from the modifiers
                                Button(action: jumpToStoreReview) {
                                    settingsRowContent("Rate the app", iconName: "star", trailing: true)
                                }
                                .buttonStyle(.plain)
                                settingsDivider
                                ShareLink(
                                    item: AppMetadata.shareBlurb, subject: Text(AppMetadata.marketingTitle),
                                    message: Text(AppMetadata.shareBlurb)
                                ) {
                                    settingsRowContent("Share the app", iconName: "square.and.arrow.up", trailing: true)
                                } 
                                .buttonStyle(.plain)
                                settingsDivider
                                Button {
                                    vault.contactSupport()
                                } label: {
                                    settingsRowContent("Support", iconName: "questionmark.circle", trailing: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        HStack(spacing: 5) {
                            Text(AppMetadata.versionCaption + " ·")
                            Button("Terms of Use") { vault.openLegal(.terms) }
                                .buttonStyle(.plain)
                            Text("·")
                            Button("Privacy Policy") { vault.openLegal(.privacy) }
                                .buttonStyle(.plain)
                        }
                        .font(.ui(12))
                        .foregroundStyle(.secondary)
                        // size matches the mock
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    // breathing room
                    .padding(.horizontal, 20)
                    // breathing room
                    .padding(.top, 12)
                    // spacing from the design
                    .padding(.bottom, 28)
                }
            }
            // background fill
            .background(
                (interfaceScheme == .dark ? Color(uiColor: .systemGroupedBackground) : Palette.rgb(0xF2F5F3)).ignoresSafeArea()    
            )
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .browsLiquidNavBar()
            // native toolbar, so the glass comes for free
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismissSheet() }
                        .labelStyle(.iconOnly)  
                }
            }
            .onChange(of: vault.chromeTheme) { _, _ in vault.writeShieldPrefs() }
            // follow the value, not the action
            .onChange(of: vault.queryEngine) { _, _ in vault.writeShieldPrefs() }
            .sheet(item: Binding(get: { vault.policySheet }, set: { vault.policySheet = $0 })) { sheet in
                LegalWebSheet(sheetHeading: sheet.sheetHeading, policyURL: sheet.policyURL)
            }
        }
        .presentationDetents([.large])
    }
}


// MARK: Helpers
extension SettingsView {
    // Opens the App Store review page, or the app page if the link is missing.
    private func jumpToStoreReview() {
        // handle link url if it is there
        if let linkURL = AppMetadata.appStoreReviewListingURL {
            Task { await UIApplication.shared.open(linkURL) }
            return
        }
        requestStoreReview()
    }

    private var settingsDivider: some View {
        Rectangle().fill(Palette.rgb(0xD6E2DC)).frame(height: 1).padding(.leading, 56)
    }

    private func settingsIcon(_ iconName: String) -> some View {
        Image(systemName: iconName).font(.ui(14, weight: .regular)).foregroundStyle(Palette.brandInk).frame(
            width: 28, height: 28
        ).background(Palette.brandWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // Settings row content
    private func settingsRowContent(_ headingText: String, iconName: String, trailing: Bool) -> some View {
        HStack(spacing: 10) {
            settingsIcon(iconName)
            Text(headingText).font(.ui(17)).browsExactLineHeight(22).foregroundStyle(.primary)
            Spacer(minLength: 0)
            if trailing {
                Image(systemName: "chevron.right").font(.ui(13, weight: .regular)).foregroundStyle(
                    Color(uiColor: .tertiaryLabel))
            }
        }.padding(.horizontal, 16).frame(height: 54).contentShape(Rectangle())
    }

    // settings section
    private func settingsSection<Content: View>(_ headingText: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headingText).font(.ui(13, weight: .semibold)).browsExactLineHeight(18).foregroundStyle(
                Color(uiColor: .tertiaryLabel))
            VStack(spacing: 0, content: content)
                // background goes behind everything
                .background(
                    interfaceScheme == .dark ? Color(uiColor: .secondarySystemGroupedBackground) : .white,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// AI toolbar toggle.
struct AIAssistantSettingsView: View {
    // injected state
    @Environment(BrowserStore.self) private var vault
    @State private var clear = false
    var body: some View {
        @Bindable var vault = vault
        Form {
            Section {    
                Toggle("Show AI button in toolbar", isOn: $vault.aiOrbVisible)
            } footer: {
                Text("Turn off if you rarely ask about pages — the toolbar gets one button shorter.")
            }
            Section {
                Button("Clear AI data", role: .destructive) { clear = true }
            } footer: {
                Text("Saved answers are removed from your history. Pages themselves stay.")
            }
        }
        .navigationTitle("AI assistant").navigationBarTitleDisplayMode(.inline)
        .browsLiquidNavBar()  
        // follow the value, not the action
        .onChange(of: vault.aiOrbVisible) { _, _ in vault.writeShieldPrefs() }
        .alert("Clear AI data?", isPresented: $clear) {
            Button("Clear AI data", role: .destructive) {
                vault.cancelGeneration() 
                vault.aiThreads.removeAll()
                vault.activeThreadKey = nil
                vault.clearAiAnswers()
                vault.flushSnapshot()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
