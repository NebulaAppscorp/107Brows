//
//  Brows107App.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 28/10/26.
//

import SwiftUI

@main struct Brows107App: App {
    @State private var vault: BrowserStore
    init() {
        let slot = BrowserStore()
        _vault = State(initialValue: slot)
    }
    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(vault)
                .tint(Palette.brandInk)
        }
    }
}

/// `preferredColorScheme(nil)` leaves the previous dark override in place, so leaving private mode stayed dark. The window override can be set back to the system style.
private struct WindowColorScheme: UIViewRepresentable {
    var windowScheme: ColorScheme?

    func makeUIView(context: Context) -> SchemeView {
        let hostName = SchemeView()
        hostName.isUserInteractionEnabled = false
        hostName.backgroundColor = .clear
        return hostName
    }

    func updateUIView(_ hostName: SchemeView, context: Context) {
        let resolvedStyle: UIUserInterfaceStyle
        if windowScheme == .dark {
            resolvedStyle = .dark
        } else if windowScheme == .light {
            resolvedStyle = .light
        } else {
            resolvedStyle = .unspecified
        }
        if hostName.windowInterfaceStyle != resolvedStyle {
            hostName.windowInterfaceStyle = resolvedStyle
        }
    }

    final class SchemeView: UIView {
        var windowInterfaceStyle: UIUserInterfaceStyle = .unspecified { didSet { paintWindowScheme() } }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            paintWindowScheme()
        }
        // paint window scheme
        private func paintWindowScheme() {
            guard let hostWindow = window else { return }
            hostWindow.overrideUserInterfaceStyle = windowInterfaceStyle
        }
    }
}

/// Root: welcome flow → paywall → browser.
struct AppRootView: View {
    @Environment(BrowserStore.self) private var vault
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var welcomeComplete = false
    @Environment(\.scenePhase) private var lifecyclePhase
    private var welcomeGate: Bool {
        vault.welcomeUp || (vault.launchScenario == "welcome" && !welcomeComplete)
            || (vault.launchScenario == nil && !onboardingComplete && !welcomeComplete)
    }
    private var effectiveColorScheme: ColorScheme? {
        welcomeGate && !vault.paywallUp ? .light : vault.preferredScheme
    }

    var body: some View {
        @Bindable var vault = vault
        ZStack {
            Group {
                if welcomeGate {
                    OnboardingView { withAnimation(.smooth(duration: 0.38)) { vault.paywallUp = true } }
                } else {
                    BrowserRootView()
                }
            }
            .allowsHitTesting(!vault.paywallUp)
            .accessibilityHidden(vault.paywallUp)
            if vault.paywallUp {
                PaywallView {
                    withAnimation(.smooth(duration: 0.38)) {
                        if welcomeGate {
                            vault.openBrowserHome()
                            welcomeComplete = true
                            vault.welcomeUp = false
                            if vault.launchScenario == nil { onboardingComplete = true }
                        }
                        vault.paywallUp = false
                    }
                }
                // enter/leave animation
                .transition(.move(edge: .trailing))
                .zIndex(10)
            }
        }
        .preferredColorScheme(effectiveColorScheme)
        // background goes behind everything
        .background { WindowColorScheme(windowScheme: effectiveColorScheme) }
        // overlay lives outside the layout
        .overlay {
            KeyboardDismissHost(dismissGesturesOn: vault.modalLane != .search).allowsHitTesting(false).accessibilityHidden(true)
        }
        .overlay(alignment: .top) {
            if vault.copyToastVisible {
                Label {
                    Text("Copied")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.brandInk)
                }
                .font(.ui(15, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 17)
                .padding(.vertical, 11)
                // background goes behind everything
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.12), radius: 15, y: 6)
                .padding(.top, 8)
                // enter/leave animation
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(20)
            }
        }
        .animation(.snappy(duration: 0.24), value: vault.copyToastVisible)
        .animation(.smooth(duration: 0.38), value: vault.paywallUp)
        // sheet content is built lazily
        .sheet(item: Binding(get: { vault.policySheet }, set: { vault.policySheet = $0 })) { sheet in
            LegalWebSheet(sheetHeading: sheet.sheetHeading, policyURL: sheet.policyURL)
        }
        // alert, buttons below
        .alert(
            AppMetadata.marketingTitle,
            isPresented: Binding(get: { vault.bannerText != nil }, set: { if !$0 { vault.bannerText = nil } })
        ) {
            Button("OK", role: .cancel) { vault.bannerText = nil }
        } message: {
            Text(vault.bannerText ?? "")
        }
        .alert(
            vault.releaseBanner == .force ? "Update required" : "Update available",
            isPresented: Binding(get: { vault.releaseBanner != nil }, set: { if !$0 { vault.releaseBanner = nil } })
        ) {
            if vault.releaseBanner == .soft { Button("Later", role: .cancel) { vault.releaseBanner = nil } }
            Button("Update") {
                vault.releaseBanner = nil
                if let slot = Bundle.main.object(forInfoDictionaryKey: "AppStoreURL") as? String, let linkURL = URL(string: slot)
                {
                    UIApplication.shared.open(linkURL)
                } else {
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        vault.bannerText = "Can’t open the update right now, try again in a bit."
                    }
                }
            }
        } message: {
            Text(
                vault.releaseBanner == .force
                    ? "This version is no longer supported. Update to keep browsing."
                    : "A new version is ready with faster page loading and better answers.")
        }
        .onChange(of: lifecyclePhase) { _, slot in
            if slot == .background { vault.flushSnapshot() }
        }
        // kicked off here so it cancels with the view
        .task {
            await Task.yield()
            await vault.restorePersistedStateIfNeeded()
            if vault.launchScenario == "paywall" { vault.paywallUp = true }
        }
        // kicked off here so it cancels with the view
        .task(priority: .utility) {
            await Task.yield()
            _ = LinkPulse.singleton
            let setupError = await Task.detached(priority: .utility) { () -> String? in
                #if DEBUG
                    do { try APIKeyVault.installDebugKeychainConnection() } catch { return error.localizedDescription }
                #endif
                APIBootstrap.primeAPIVault()
                return nil
            }.value
            if let setupError { vault.bannerText = setupError }
        }
        .task(priority: .background) {
            ContentBlockerEngine.prewarm()
        }
        .onChange(of: vault.paywallUp) { _, isUp in
            if !isUp { Task { await vault.syncProEntitlement() } }
        }
    }
}
