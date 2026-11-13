//
//  BrowserRootView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 11/11/26.
//

import SwiftUI
import WebKit

/// Owns the page, the chrome and every modal route.
struct BrowserRootView: View {
    // view state
    @Environment(BrowserStore.self) private var vault
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var webLane = WebSession()
    @State private var omniboxDraft = ""
    @State private var keyboardVisible = false

    private var hasPage: Bool { vault.currentTab?.pageURL != nil }
    private var showTopChrome: Bool { vault.chromePane == 1 || (vault.chromePane == 0 && !hasPage) }
    private var showBrowserBottom: Bool { vault.chromePane == 0 }
    private var showsAIOnBar: Bool { hasPage && vault.aiOrbVisible && !vault.incognito }
    private var isBrowserMenuPresented: Bool { vault.modalLane == .menu }
    private var pageTopUsesLightColor: Bool { (vault.preferredScheme ?? systemColorScheme) == .light }
    private var pageTopColor: Color { pageTopUsesLightColor ? .white : .black }

    var body: some View {
        @Bindable var vault = vault
        ZStack {
            backdrop.ignoresSafeArea()
            TabView(selection: surfaceBinding) {
                NavigationStack {
                    browser
                        .navigationBarTitleDisplayMode(.inline)
                        .browsLiquidNavBar(hidesBackground: true)
                        // native toolbar, so the glass comes for free
                        .toolbar((vault.chromePane == 0 && !hasPage) ? .visible : .hidden, for: .navigationBar)
                        .safeAreaPadding(.top, 0)
                        // background fill
                        .background(Color.clear)
                        .toolbarColorScheme(hasPage ? (pageTopUsesLightColor ? .light : .dark) : nil, for: .navigationBar)
                        // background goes behind everything
                        .background {
                            if hasPage { PageStatusBar(lightBackground: pageTopUsesLightColor).frame(width: 0, height: 0) }
                        }
                        // toolbar items
                        .toolbar { browserNavBar }
                }
                .browsBrowserBottomToolbar(shows: showBrowserBottom && !webLane.showFind) {
                    browserBottomBar
                        // animate only on this value
                        .animation(nil, value: vault.modalLane)
                }
                .browsScrollEdgeEffectHidden(.bottom)
                .ignoresSafeArea(.container, edges: .top)
                .tag(0)
                NavigationStack {
                    ChatView()
                        .navigationBarTitleDisplayMode(.inline)
                        .browsLiquidNavBar(hidesBackground: true)
                        // toolbar items
                        .toolbar { browserNavBar }
                }
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.clear)
            .overlay(alignment: .bottom) {
                if showBrowserBottom, vault.modalLane != .menu, webLane.showFind, hasPage {
                    FindOnPageBar(
                        draftText: $webLane.findText,
                        matchIndex: webLane.findMatchIndex,
                        matchCount: webLane.findMatchCount,
                        autoFocus: vault.launchScenario != "find-no-keyboard" && vault.launchScenario != "find-live-no-keyboard",
                        onQueryChange: { webLane.searchInPage($0) },
                        onSubmit: { webLane.advanceFind(direction: .forward) },
                        onPrev: { webLane.advanceFind(direction: .backward) },
                        onNext: { webLane.advanceFind(direction: .forward) },
                        onDone: {
                            webLane.clearInPageFind()
                            webLane.showFind = false
                            webLane.findText = ""
                            webLane.findMatchIndex = 0
                            webLane.findMatchCount = 0
                        }
                    )
                    .padding(.bottom, keyboardVisible ? 8 : 88)
                    .zIndex(2)
                }
                // Site panel: compact popover floating above the toolbar, no dim.
                // The anchor only exists while the panel is up, so an idle popover host never competes with sheets/covers.
                if vault.modalLane == .site {
                    Color.clear.frame(width: 1, height: 1)
                        // small popover anchored to the control
                        .popover(isPresented: siteCover, arrowEdge: .bottom) {
                            SitePanelView(webLane: webLane)
                                .presentationCompactAdaptation(.popover)
                        }
                        .padding(.bottom, 70)
                }
            }
            .onChange(of: webLane.showFind) { _, isShown in
                if !isShown {
                    keyboardVisible = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) {
                notification in
                guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                let keyWindow = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                    .first(where: \.isKeyWindow)
                let inset: CGFloat
                if let keyWindow {
                    let keyboardFrame = keyWindow.convert(frame, from: keyWindow.screen.coordinateSpace)
                    inset = max(0, keyWindow.bounds.maxY - keyboardFrame.minY)
                } else {
                    inset = max(0, UIScreen.main.bounds.maxY - frame.minY)
                }
                let isKeyboardVisible = inset > 20
                if keyboardVisible != isKeyboardVisible { keyboardVisible = isKeyboardVisible }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                if !webLane.showFind { keyboardVisible = false }
            }
            // full screen on purpose, it has its own chrome
            .fullScreenCover(isPresented: searchCover, onDismiss: { vault.drainModalQueue() }) {
                AddressSearchView(initialText: omniboxDraft)
            }
            .fullScreenCover(isPresented: cameraCover, onDismiss: { vault.drainModalQueue() }) {
                PhotoSearchView()
            }
            .fullScreenCover(isPresented: tabsCover, onDismiss: { vault.drainModalQueue() }) {
                TabsView()
            }
            .fullScreenCover(item: fullScreenPresentation, onDismiss: { vault.drainModalQueue() }) { item in
                switch item {
                case .library: LibraryView()
                case .settings: SettingsView(webLane: webLane)
                case .downloads: DownloadsView()
                case .protection: ProtectionView(webLane: webLane)
                default: EmptyView()
                }
            }
            // full screen on purpose, it has its own chrome
            .fullScreenCover(isPresented: pdfCover, onDismiss: { vault.drainModalQueue() }) {
                DocumentView()
            }
            // presented as a sheet
            .sheet(item: sheetPresentation, onDismiss: { vault.drainModalQueue() }) { item in
                switch item {
                case .tabs: TabsView()
                case .library: LibraryView()
                case .settings: SettingsView(webLane: webLane)
                case .camera: PhotoSearchView()
                case .visualMatches:
                    VisualMatchesView(
                        searchPhase: vault.launchScenario == "matches-empty"
                            ? .empty
                            : vault.launchScenario == "matches-unreadable"
                                ? .unreadable : vault.launchScenario == "matches-offline" ? .offline : .results)
                case .downloads: DownloadsView()
                case .protection: ProtectionView(webLane: webLane)
                case .site: EmptyView()
                case .ai: PageAIView(webLane: webLane)
                case .menu: EmptyView()
                case .chats: ConversationsView()
                case .models: EmptyView()
                case .pdf: DocumentView()
                case .search: EmptyView()
                }
            }
            // react to the change here
            .onChange(of: vault.tabStrip) { _, _ in webLane.purgeOrphanWebViews() }
            // react to the change here
            .onChange(of: vault.shieldAds) { _, _ in
                webLane.refreshShieldScripts()
                vault.writeShieldPrefs()
            }
            .onChange(of: vault.shieldRedirects) { _, _ in
                webLane.refreshShieldScripts()
                vault.writeShieldPrefs()
            }
            .onChange(of: vault.shieldTrackers) { _, _ in
                webLane.refreshShieldScripts()
                vault.writeShieldPrefs()
            }
            // react to the change here
            .onChange(of: vault.shieldExceptions) { _, _ in
                webLane.refreshShieldScripts()
                vault.writeShieldPrefs()
            }
            .task { await applyLaunchScenario() }
            .environment(webLane)
        }
        .overlay {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    browserMenuScrim
                        .opacity(isBrowserMenuPresented ? 1 : 0)
                        .allowsHitTesting(isBrowserMenuPresented)
                        .accessibilityHidden(!isBrowserMenuPresented)
                    browserMenuOverlay
                        .compositingGroup()
                        .offset(y: isBrowserMenuPresented ? 0 : geometry.size.height)
                        .allowsHitTesting(isBrowserMenuPresented)
                        .accessibilityHidden(!isBrowserMenuPresented)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                // animate only on this value
                .animation(.spring(response: 0.42, dampingFraction: 0.9), value: isBrowserMenuPresented)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            if vault.launchScenario == "menu" { vault.modalLane = .menu }
        }
    }

    // browser nav bar
    @ToolbarContentBuilder private var browserNavBar: some ToolbarContent {
        if showTopChrome {
            IsolatedToolbarItem {
                ToolbarItem(placement: .principal) {
                    SurfaceSwitch(chromePaneIndex: surfaceBinding, isPrivate: vault.incognito)
                }
            }
            if vault.chromePane == 1 {
                IsolatedToolbarItem {
                    ToolbarItem(placement: .topBarLeading) {
                        HamburgerGlassButton(a11yTitle: "Chats", onTap: presentChats)
                    }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: revealCameraSheet) {
                        Image(systemName: "camera.viewfinder")
                            .foregroundStyle(.primary)
                    }
                    .tint(.primary)
                    .accessibilityLabel("Search by photo")
                }
            }
        }
    }

    private var surfaceBinding: Binding<Int> {
        Binding(get: { vault.chromePane }, set: { vault.chromePane = $0 })
    }

    // reveal camera sheet
    private func revealCameraSheet() {
        vault.modalLane = .camera
    }

    // shows the chats
    private func presentChats() { vault.modalLane = .chats }

    private var pdfCover: Binding<Bool> {
        Binding(
            get: { vault.modalLane == .pdf },
            set: { if !$0, vault.modalLane == .pdf { vault.modalLane = nil } }
        )
    }

    private var cameraCover: Binding<Bool> {
        Binding(
            get: { vault.modalLane == .camera },
            set: { if !$0, vault.modalLane == .camera { vault.modalLane = nil } }
        )
    }

    private var tabsCover: Binding<Bool> {
        Binding(
            get: { vault.modalLane == .tabs },
            set: { if !$0, vault.modalLane == .tabs { vault.modalLane = nil } }
        )
    }

    /// Sample data only: pretend there is history so the back chevron is active on the site panel.
    private var reviewShowsBackEnabled: Bool {
        #if DEBUG
            return vault.launchScenario == "site"
        #else
            return false
        #endif
    }

    private var siteCover: Binding<Bool> {
        Binding(
            get: { vault.modalLane == .site },
            set: { if !$0, vault.modalLane == .site { vault.modalLane = nil } }
        )
    }

    private var searchCover: Binding<Bool> {
        Binding(
            get: { vault.modalLane == .search },
            set: { if !$0, vault.modalLane == .search { vault.modalLane = nil } }
        )
    }

    private var sheetPresentation: Binding<ModalRoute?> {
        Binding(
            get: {
                switch vault.modalLane {
                case .search, .pdf, .camera, .tabs, .settings, .downloads, .protection, .models, .site, .menu: nil
                default: vault.modalLane
                }
            }, set: { vault.modalLane = $0 })
    }

    private var fullScreenPresentation: Binding<ModalRoute?> {
        Binding(
            get: {
                switch vault.modalLane {
                case .settings, .downloads, .protection: vault.modalLane
                default: nil
                }
            }, set: { vault.modalLane = $0 })
    }

    // Layout for browser menu scrim
    private var browserMenuScrim: some View {
        Color.clear
            // background goes behind everything
            .background(.ultraThinMaterial.opacity(0.12))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { vault.modalLane = nil }
            .accessibilityLabel("Dismiss menu")
            .accessibilityAddTraits(.isButton)
    }

    // browser menu overlay row
    private var browserMenuOverlay: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(uiColor: .tertiaryLabel))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 6)
            browserMenuPanel
        }
        .frame(maxWidth: .infinity)
        .background {
            Palette.canvasView
                .ignoresSafeArea(edges: .bottom)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 38,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 38,
                style: .continuous
            )
        )
        .shadow(color: .black.opacity(0.08), radius: 16, y: -4)
        .contentShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 38,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 38,
                style: .continuous
            )
        )
        .accessibilityAddTraits(.isModal)
    }

    // the browser menu panel block
    private var browserMenuPanel: some View {
        let actions = menuActions
        let actionRows = stride(from: 0, to: actions.count, by: 5).map { start in
            Array(actions[start..<min(start + 5, actions.count)])
        }
        return
            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: vault.currentTab?.pageURL == nil ? "safari" : "globe")
                        .font(.ui(19, weight: .medium))
                        .foregroundStyle(Palette.brandInk)
                        .frame(width: 42, height: 42)
                        .browsGlassBackground(radius: 14)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(vault.currentTab?.pageURL?.host ?? "New tab")
                            .font(.ui(16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if vault.currentTab?.pageURL?.scheme?.lowercased() == "https" {
                            Label("Connection is secure", systemImage: "lock.fill")
                                .font(.ui(11))
                                .foregroundStyle(.secondary)
                        } else if let headingText = vault.currentTab?.pageTitle, vault.currentTab?.pageURL != nil {
                            Text(headingText).font(.ui(11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Button("Done") { vault.modalLane = nil }
                        .font(.ui(14, weight: .medium))
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .browsGlassCapsule()
                }
                .padding(.horizontal, 4)

                VStack(spacing: 16) {
                    ForEach(Array(actionRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 6) {
                            ForEach(row) { action in
                                menuActionTile(action)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Privacy and settings")
                        .font(.ui(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                    VStack(spacing: 0) {
                        menuSettingRow("Protection", menuGlyph: "shield.lefthalf.filled") { vault.modalLane = .protection }
                        menuRowSeparator
                        menuSettingRow(vault.incognito ? "Exit private mode" : "Private mode", menuGlyph: "hand.raised") {
                            vault.toggleIncognito(!vault.incognito)
                            vault.modalLane = nil
                        }
                        menuRowSeparator
                        menuSettingRow("Home", menuGlyph: "house") { vault.openBrowserHome() }
                        menuRowSeparator
                        menuSettingRow("Settings", menuGlyph: "gearshape") { vault.modalLane = .settings }
                    }
                    .padding(.horizontal, 14)
                    .browsGlassBackground(radius: 24)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 2)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .top)
    }

    private var menuActions: [BrowserMenuAction] {
        var actions = [
            BrowserMenuAction(headingText: "New tab", menuGlyph: "plus", action: { vault.spawnTab() }),
            BrowserMenuAction(headingText: "Tabs", menuGlyph: "square.on.square", action: { vault.modalLane = .tabs }),
            BrowserMenuAction(headingText: "Library", menuGlyph: "book", action: { vault.modalLane = .library }),
            BrowserMenuAction(headingText: "Downloads", menuGlyph: "arrow.down.circle", action: { vault.modalLane = .downloads }),
            BrowserMenuAction(headingText: "Open PDF", menuGlyph: "doc.richtext", action: { vault.modalLane = .pdf }),
        ]
        if let linkURL = vault.currentTab?.pageURL {
            actions.append(BrowserMenuAction(headingText: "Share", menuGlyph: "square.and.arrow.up", shareURL: linkURL))
            actions.append(
                BrowserMenuAction(
                    headingText: "Add bookmark", menuGlyph: "bookmark",
                    action: {
                        vault.pinCurrentPage()
                        vault.modalLane = nil
                    }))
            actions.append(
                BrowserMenuAction(
                    headingText: "Find on page", menuGlyph: "doc.text.magnifyingglass",
                    action: {
                        webLane.clearInPageFind()
                        webLane.showFind = true
                        webLane.findText = ""
                        webLane.findMatchIndex = 0
                        webLane.findMatchCount = 0
                        vault.modalLane = nil
                    }))
            actions.append(
                BrowserMenuAction(
                    headingText: "Reader", menuGlyph: "doc.plaintext",
                    action: {
                        Task {
                            if vault.launchScenario != nil {
                                webLane.pageText = SampleContent.readerBody
                            } else {
                                _ = await webLane.harvestReadableText()
                            }
                            webLane.readerActive = true
                            vault.modalLane = nil
                        }
                    }))
            actions.append(
                BrowserMenuAction(
                    headingText: "Reload", menuGlyph: "arrow.clockwise",
                    action: {
                        webLane.liveWebView?.reload()
                        vault.modalLane = nil
                    }))
        }
        return actions
    }

    // menu action tile
    @ViewBuilder private func menuActionTile(_ action: BrowserMenuAction) -> some View {
        if let linkURL = action.shareURL {
            ShareLink(item: linkURL) { menuActionLabel(action) }
                .buttonStyle(.plain)
        } else {
            Button {
                action.action?()
            } label: {
                menuActionLabel(action)
            }
            .buttonStyle(.plain)
        }
    }

    // menu action label
    private func menuActionLabel(_ action: BrowserMenuAction) -> some View {
        VStack(spacing: 6) {
            Image(systemName: action.menuGlyph)
                .font(.ui(18, weight: .medium))
                .foregroundStyle(Color(uiColor: .label))
                .frame(width: 46, height: 46)
                .browsGlassBackground(radius: 14)
            Text(action.headingText)
                .font(.ui(10.5, weight: .regular))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    // Menu row separator
    private var menuRowSeparator: some View {
        Rectangle().fill(Color(uiColor: .separator).opacity(0.35)).frame(height: 0.5).padding(.leading, 48)
    }

    // menu setting row
    private func menuSettingRow(_ headingText: String, menuGlyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: menuGlyph)
                    .font(.ui(17, weight: .regular))
                    .foregroundStyle(Color(uiColor: .label))
                    .frame(width: 24)
                Text(headingText)
                    .font(.ui(16))
                    .foregroundStyle(Color(uiColor: .label))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.ui(12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // the backdrop block
    @ViewBuilder private var backdrop: some View {
        let browserHome = vault.chromePane == 0 && vault.currentTab?.pageURL == nil
        let chatPane = vault.chromePane == 1
        if browserHome || chatPane {
            ShellBackdrop()
        } else {
            pageTopColor.ignoresSafeArea()
        }
    }

    // the browser block
    @ViewBuilder private var browser: some View {
        if let tab = vault.currentTab, tab.pageURL != nil {
            ZStack {
                if webLane.readerActive {
                    ReaderChromeView(headingText: tab.pageTitle) { webLane.readerActive = false }
                } else if vault.launchScenario != nil,
                    ![
                        "live", "find-live", "find-live-no-keyboard", "xcom", "xcom-unshielded", "page-scroll", "page-offline",
                        "page-not-responding", "page-not-found", "offline", "not-responding", "not-found",
                    ].contains(vault.launchScenario ?? "")
                {
                    SampleArticleView(highlight: webLane.showFind ? webLane.findText : nil)
                } else {
                    WebPageView(tab: tab, webSession: webLane).id(tab.id).ignoresSafeArea()
                }
                if let pageError = webLane.pageError {
                    pageTopColor
                        .ignoresSafeArea()
                    PageErrorStateView(loadFault: pageError) {
                        resolvePageErrorPrimary(pageError)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
        } else {
            BrowserHomeView()
        }
    }

    // browser bottom bar
    private var browserBottomBar: some View {
        BrowserBottomBar(
            canStepBack: (webLane.canStepBack && hasPage) || reviewShowsBackEnabled,
            isPrivate: vault.incognito,
            isDark: !pageTopUsesLightColor && !vault.incognito,
            addressTitle: hasPage ? (vault.currentTab?.pageURL?.host ?? "") : "",
            addressSpinner: webLane.navPending,
            showsShield: vault.modalLane == .site,
            showsAI: showsAIOnBar,
            onBack: { webLane.stepHistoryBack() },
            onAddress: {
                omniboxDraft = vault.currentTab?.pageURL?.absoluteString ?? ""
                vault.modalLane = .search
            },
            onAI: presentAI,
            onMenu: { vault.modalLane = .menu }
        )
    }

    // shows the ai
    private func presentAI() {
        guard !vault.incognito else {
            vault.bannerText = "AI is off in private tabs."
            return
        }
        guard vault.currentTab?.pageURL != nil else {
            vault.chromePane = 1
            return
        }
        vault.modalLane = .ai
    }

    @MainActor
    private func applyLaunchScenario() async {
        webLane.vaultRef = vault
        guard let review = vault.launchScenario else { return }
        let sheets: [String: ModalRoute] = [
            "tabs": .tabs, "library": .library, "settings": .settings, "camera": .camera,
            "matches": .visualMatches, "matches-empty": .visualMatches, "matches-unreadable": .visualMatches,
            "matches-offline": .visualMatches,
            "downloads": .downloads, "downloads-active": .downloads, "downloads-paused": .downloads,
            "protection": .protection, "ai": .ai, "answer": .ai,
            "chats": .chats, "models": .models, "pdf": .pdf, "pdf-error": .pdf, "site": .site, "menu": .menu,
        ]
        if review == "private" {
            vault.toggleIncognito(true)
            vault.modalLane = nil
        } else if review == "search" {
            #if DEBUG
                omniboxDraft = "how to brew coffee"
            #endif
            vault.modalLane = .search
        } else {
            vault.modalLane = SampleDataInstaller.pageAIScenarios.contains(review) ? .ai : sheets[review]
        }
        if review == "reader" {
            webLane.pageText = SampleContent.readerBody
            webLane.readerActive = true
        }
        if review == "find" || review == "find-keyboard" || review == "find-no-keyboard" || review == "find-live"
            || review == "find-live-no-keyboard"
        {
            webLane.showFind = true
            webLane.findText = ""
            webLane.findMatchIndex = 0
            webLane.findMatchCount = 0
        }
        if let fixture = PageLoadError.sampleFailure(review) {
            webLane.pageError = fixture
            webLane.navPending = false
        }
    }

    // Primary button on the page error screen (retry / edit address).
    private func resolvePageErrorPrimary(_ error: PageLoadError) {
        switch error {
        case .notFound:
            omniboxDraft = vault.currentTab?.pageURL?.absoluteString ?? ""
            vault.modalLane = .search
        case .offline, .notResponding:
            webLane.pageError = nil
            if LinkPulse.singleton.linkSevered {
                webLane.pageError = .offline
                return
            }
            webLane.liveWebView?.reload()
        }
    }
}
