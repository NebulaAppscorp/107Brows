//
//  BrowserStore.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 27/10/26.
//

import SwiftUI
import Observation
import UIKit

@Observable @MainActor final class BrowserStore {
    var tabStrip: [BrowserTab] = [BrowserTab()]
    var activeTabKey: UUID?
    var visitLedger: [SavedPage] = []
    var pinnedPages: [SavedPage] = []
    var aiThreads: [Conversation] = []
    var savedDownloads: [DownloadItem] = []
    var chromePane = 0
    var modalLane: ModalRoute?
    var pendingModal: ModalRoute?
    var paywallUp = false
    var welcomeUp = false
    var releaseBanner: UpdateNotice?
    var incognito = false
    var webLookup = true
    var deepThink = false
    var assistantModel = "Standard"
    var composerDraft = ""
    var pageAssistKind = "Summary"
    var quotedSpan: String?
    var activeThreadKey: UUID?
    var assistantBusy = false
    var attachedPhoto: UIImage?
    var bannerText: String?
    var copyToastVisible = false
    var policySheet: LegalSheet?
    var chromeTheme = UserDefaults.standard.string(forKey: "b107ChromeTheme") ?? "System"
    var queryEngine = UserDefaults.standard.string(forKey: "b107QueryEngine") ?? "Google"
    var aiOrbVisible = UserDefaults.standard.object(forKey: "b107AiOrbVisible") as? Bool ?? true
    var shieldAds = UserDefaults.standard.object(forKey: "b107ShieldAds") as? Bool ?? true
    var shieldTrackers = UserDefaults.standard.object(forKey: "b107ShieldTrackers") as? Bool ?? true
    var shieldRedirects = UserDefaults.standard.object(forKey: "b107ShieldRedirects") as? Bool ?? true
    var shieldExceptions: [String] = UserDefaults.standard.stringArray(forKey: "b107ShieldExceptions") ?? []
    var launchScenario: String?
    var blockedTally = 0
    var tallyAds = UserDefaults.standard.integer(forKey: "protection.ads")
    var tallyTrackers = UserDefaults.standard.integer(forKey: "protection.trackers")
    var tallyRedirects = UserDefaults.standard.integer(forKey: "protection.redirects")
    var answeredPageKeys = Set(UserDefaults.standard.stringArray(forKey: "ai.b107AnsweredPageKeys") ?? [])
    var proEntitlementActive = false
    var currentTab: BrowserTab? { tabStrip.first { $0.id == activeTabKey } }
    var visibleTabs: [BrowserTab] { tabStrip.filter { $0.incognitoTab == incognito } }
    var currentThread: Conversation? { aiThreads.first { $0.id == activeThreadKey } }
    var preferredScheme: ColorScheme? {
        incognito ? .dark : chromeTheme == "Dark" ? .dark : chromeTheme == "Light" ? .light : nil
    }

    /// Settings → Appearance. Private mode can still use the light purple backdrop.
    func prefersLightBackdropArt(systemScheme: ColorScheme) -> Bool {
        switch chromeTheme {
        case "Light": return true
        case "Dark": return false
        default: return systemScheme == .light
        }
    }
    let aiService: any AIService
    private let storageURL: URL
    private var generationFlight: Task<Void, Never>?
    private var copyToastTask: Task<Void, Never>?
    private let maxImageBytes = 5 * 1024 * 1024
    private var persistenceTick = 0
    @ObservationIgnored private var restoreStarted = false

    init(storageURL: URL? = nil, aiService: any AIService = AIClient()) {
        self.aiService = aiService
        self.storageURL = storageURL ?? URL.applicationSupportDirectory.appending(path: "107Brows/state.json")
        activeTabKey = tabStrip.first?.id
        #if DEBUG
            let launchArguments = ProcessInfo.processInfo.arguments
            if let position = launchArguments.firstIndex(of: "-review"), launchArguments.indices.contains(position + 1) {
                launchScenario = launchArguments[position + 1]
                if launchScenario != "welcome" { SampleDataInstaller.apply(on: self) }
            }
        #endif
    }

    // Loads tabs, history and chats from disk once, off the main thread.
    func restorePersistedStateIfNeeded() async {
        guard !restoreStarted, launchScenario == nil else { return }
        restoreStarted = true
        let snapshotURL = storageURL
        let restored = await Task.detached(priority: .utility) { () -> PersistedLoad? in
            guard let payloadBytes = try? Data(contentsOf: snapshotURL),
                let persistedBundle = try? JSONDecoder().decode(PersistedState.self, from: payloadBytes)
            else { return nil }
            let savedTabs = persistedBundle.tabStrip
            var openTabs = savedTabs.filter { openTab in
                guard let hostName = openTab.pageURL?.host?.lowercased() else { return true }
                return hostName != "x.com" && !hostName.hasSuffix(".x.com")
            }
            let removedXcomTab = openTabs.count != savedTabs.count
            if openTabs.isEmpty { openTabs = [BrowserTab()] }
            if removedXcomTab && openTabs.first(where: { !$0.incognitoTab && $0.pageURL == nil }) == nil {
                openTabs.insert(BrowserTab(), at: 0)
            }
            let downloadList = persistedBundle.savedDownloads.filter {
                $0.diskFileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            }
            return PersistedLoad(
                tabStrip: openTabs,
                visitLedger: persistedBundle.visitLedger,
                pinnedPages: persistedBundle.pinnedPages,
                aiThreads: persistedBundle.aiThreads,
                savedDownloads: downloadList,
                removedXcomTab: removedXcomTab
            )
        }.value
        guard let restored,
            persistenceTick == 0,
            !incognito,
            tabStrip.count == 1,
            currentTab?.pageURL == nil,
            visitLedger.isEmpty,
            pinnedPages.isEmpty,
            aiThreads.isEmpty,
            savedDownloads.isEmpty
        else { return }
        tabStrip = restored.tabStrip
        activeTabKey = tabStrip.first?.id
        visitLedger = restored.visitLedger
        pinnedPages = restored.pinnedPages
        aiThreads = restored.aiThreads
        savedDownloads = restored.savedDownloads
        if restored.removedXcomTab { flushSnapshot() }
    }

    // Writes state.json now (called when the app goes to background).
    func flushSnapshot() {
        guard launchScenario == nil else { return }
        let persistedBundle = PersistedState(
            tabStrip: tabStrip.filter { !$0.incognitoTab }, visitLedger: visitLedger, pinnedPages: pinnedPages,
            aiThreads: aiThreads, savedDownloads: savedDownloads)
        persistenceTick += 1
        let snapshotRevision = persistenceTick
        let linkURL = storageURL
        Task { [weak self] in
            do {
                try await BrowserStateWriter.singleton.writeSnapshotFile(
                    persistedBundle, to: linkURL, snapshotRevision: snapshotRevision)
            } catch {
                self?.bannerText = "Couldn’t save your changes — your device may be low on storage."
            }
        }
    }

    // copy text to pasteboard
    func copyTextToPasteboard(_ text: String) {
        UIPasteboard.general.string = text
        copyToastTask?.cancel()
        copyToastVisible = true
        copyToastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.copyToastVisible = false
        }
    }

    // Write shield prefs
    func writeShieldPrefs() {
        let shieldPrefEntries: [String: Any] = [
            "b107ChromeTheme": chromeTheme, "b107QueryEngine": queryEngine, "b107AiOrbVisible": aiOrbVisible,
            "b107ShieldAds": shieldAds, "b107ShieldTrackers": shieldTrackers, "b107ShieldRedirects": shieldRedirects,
            "b107ShieldExceptions": shieldExceptions,
        ]
        for (key, prefValue) in shieldPrefEntries { UserDefaults.standard.set(prefValue, forKey: key) }
    }

    // Queues a sheet while another one is still dismissing.
    func enqueueModal(to modalDestination: ModalRoute) {
        if modalLane == nil || modalLane == modalDestination {
            pendingModal = nil
            modalLane = modalDestination
        } else {
            pendingModal = modalDestination
            modalLane = nil
        }
    }

    // Presents the next queued sheet, if any.
    func drainModalQueue() {
        guard modalLane == nil, let next = pendingModal else { return }
        pendingModal = nil
        modalLane = next
    }

    // Turns whatever was typed into a URL or a search and opens it.
    func navigateInput(_ addressDraft: String, inNewTab: Bool = false) {
        guard let linkURL = AddressResolver.coerceNavigableURL(addressDraft, engine: queryEngine) else { return }
        if inNewTab || currentTab == nil { spawnTab() }
        if let index = tabStrip.firstIndex(where: { $0.id == activeTabKey }) {
            tabStrip[index].pageURL = linkURL
            tabStrip[index].pageTitle = linkURL.host ?? "Page"
            tabStrip[index].reloadToken += 1
        }
        chromePane = 0
        modalLane = nil
        flushSnapshot()
    }

    func openBrowserHome() {
        cancelGeneration()
        attachedPhoto = nil
        incognito = false
        if let browserTab = tabStrip.first(where: { !$0.incognitoTab && $0.pageURL == nil }) {
            activeTabKey = browserTab.id
        } else {
            let browserTab = BrowserTab()
            tabStrip.append(browserTab)
            activeTabKey = browserTab.id
        }
        chromePane = 0
        modalLane = nil
        flushSnapshot()
    }

    // x.com tabs are dropped on restore.
    func removeXcomTabs() {
        let originalCount = tabStrip.count
        tabStrip.removeAll(where: Self.isXcomTab)
        guard tabStrip.count != originalCount else { return }
        if tabStrip.first(where: { !$0.incognitoTab && $0.pageURL == nil }) == nil {
            tabStrip.append(BrowserTab())
        }
        activeTabKey = tabStrip.first(where: { !$0.incognitoTab && $0.pageURL == nil })?.id ?? tabStrip.first?.id
        flushSnapshot()
    }

    // True when xcom tab
    private static func isXcomTab(_ openTab: BrowserTab) -> Bool {
        guard let host = openTab.pageURL?.host?.lowercased() else { return false }
        return host == "x.com" || host.hasSuffix(".x.com")
    }

    // Opens a blank tab and makes it current.
    func spawnTab() {
        let browserTab = BrowserTab(incognitoTab: incognito)
        tabStrip.append(browserTab)
        activeTabKey = browserTab.id
        chromePane = 0
        modalLane = nil
        flushSnapshot()
    }

    // closes tab by id
    func closeTabByID(_ id: UUID) {
        TabPreviewStore.singleton.dropThumb(for: id)
        tabStrip.removeAll { $0.id == id }
        if activeTabKey == id { activeTabKey = visibleTabs.first?.id }
        flushSnapshot()
    }

    // Flips incognito
    func toggleIncognito(_ slot: Bool) {
        cancelGeneration()
        attachedPhoto = nil
        incognito = slot
        activeTabKey = visibleTabs.first?.id
        if activeTabKey == nil { spawnTab() }
    }

    // Adds a page to history, newest first.
    func logVisit(headingText: String, url linkURL: URL) {
        guard let index = tabStrip.firstIndex(where: { $0.id == activeTabKey }) else { return }
        tabStrip[index].pageTitle = headingText.isEmpty ? linkURL.host ?? "Page" : headingText
        tabStrip[index].pageURL = linkURL
        if !tabStrip[index].incognitoTab {
            visitLedger.removeAll { $0.pageURL == linkURL }
            visitLedger.insert(SavedPage(pageTitle: tabStrip[index].pageTitle, pageURL: linkURL), at: 0)
            if visitLedger.count > 500 { visitLedger.removeLast(visitLedger.count - 500) }
        }
        flushSnapshot()
    }

    func pinCurrentPage() {
        guard let browserTab = currentTab, let linkURL = browserTab.pageURL else { return }
        if !pinnedPages.contains(where: { $0.pageURL == linkURL }) {
            pinnedPages.insert(SavedPage(pageTitle: browserTab.pageTitle, pageURL: linkURL), at: 0)
        }
        flushSnapshot()
    }

    // mark ai answered
    func markAiAnswered(_ linkURL: URL) {
        answeredPageKeys.insert(linkURL.absoluteString)
        UserDefaults.standard.set(Array(answeredPageKeys), forKey: "ai.b107AnsweredPageKeys")
    }

    // true when ai answer
    func hasAiAnswer(_ linkURL: URL) -> Bool {
        answeredPageKeys.contains(linkURL.absoluteString)
    }

    // Keeps pro entitlement in sync
    func syncProEntitlement() async {
        guard launchScenario == nil else { return }
        await ApphudBootstrap.awaitApphudBootstrapped(maxWait: .seconds(2))
        proEntitlementActive = await ProEntitlement.isSubscribed()
    }

    // require server subscription
    func requireServerSubscription() async -> Bool {
        guard launchScenario == nil else { return true }
        await syncProEntitlement()
        guard proEntitlementActive else {
            presentProPaywall()
            return false
        }
        return true
    }

    // Shows the pro paywall
    func presentProPaywall() {
        modalLane = nil
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation { paywallUp = true }
        }
    }

    func clearAiAnswers() {
        answeredPageKeys = []
        UserDefaults.standard.removeObject(forKey: "ai.b107AnsweredPageKeys")
    }

    // Starts fresh thread
    func startFreshThread() {
        cancelGeneration()
        activeThreadKey = nil
        composerDraft = ""
        chromePane = 1
    }

    // Sends the chat draft.
    func submitComposer() {
        let composerPlainText = composerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !composerPlainText.isEmpty || attachedPhoto != nil, !assistantBusy else { return }
        guard !incognito else {
            bannerText = "AI is off in private tabs."
            return
        }
        guard composerPlainText.count <= 8000 else {
            bannerText = APIError.tooLarge.localizedDescription
            return
        }
        let imagePayload = attachedPhoto.map(ImagePayload.init)
        assistantBusy = true
        let search = webLookup
        let reasoning = deepThink
        generationFlight = Task {
            defer { if !Task.isCancelled { assistantBusy = false } }
            guard await requireServerSubscription(), !Task.isCancelled else { return }
            if activeThreadKey == nil {
                let newThread = Conversation(
                    threadTitle: composerPlainText.isEmpty ? "Photo question" : String(composerPlainText.prefix(70)))
                aiThreads.insert(newThread, at: 0)
                activeThreadKey = newThread.id
            }
            guard let index = aiThreads.firstIndex(where: { $0.id == activeThreadKey }) else { return }
            composerDraft = ""
            attachedPhoto = nil
            let threadKey = aiThreads[index].id
            let chatRelayID = aiThreads[index].remoteChatID ?? threadKey.uuidString
            do {
                let outgoingJPEG: Data? =
                    if let imagePayload {
                        await Task.detached(priority: .userInitiated) { imagePayload.bitmap.jpegData(compressionQuality: 0.7) }
                            .value
                    } else {
                        nil
                    }
                guard imagePayload == nil || outgoingJPEG != nil, (outgoingJPEG?.count ?? 0) <= maxImageBytes else {
                    bannerText = APIError.tooLarge.localizedDescription
                    return
                }
                guard let currentIndex = aiThreads.firstIndex(where: { $0.id == threadKey }) else { return }
                aiThreads[currentIndex].threadTurns.append(
                    ChatMessage(messageBody: composerPlainText, fromVisitor: true, inlinePhotoBytes: outgoingJPEG))
                flushSnapshot()
                let assistantPayload: AIReply
                if launchScenario != nil {
                    try await Task.sleep(for: .milliseconds(650))
                    assistantPayload = AIReply(
                        remoteChatID: chatRelayID, assistantBody: SampleContent.chatAnswer,
                        referenceMarks: SampleContent.fixturePages.prefix(3).map {
                            AICitation(pageTitle: $0.pageTitle, citationHref: $0.pageURL.absoluteString)
                        })
                } else {
                    assistantPayload = try await aiService.relayChat(
                        remoteChatID: chatRelayID, promptText: composerPlainText, photoJPEG: outgoingJPEG, sourceIDs: [],
                        webLookupEnabled: search, think: reasoning)
                }
                try Task.checkCancellation()
                guard let currentIndex = aiThreads.firstIndex(where: { $0.id == threadKey }) else { return }
                aiThreads[currentIndex].remoteChatID = assistantPayload.remoteChatID
                aiThreads[currentIndex].threadTurns.append(
                    ChatMessage(
                        messageBody: assistantPayload.assistantBody, fromVisitor: false,
                        citationPages: assistantPayload.savedSources))
                flushSnapshot()
            } catch is CancellationError {} catch {
                guard !Task.isCancelled,
                    let currentIndex = aiThreads.firstIndex(where: { $0.id == threadKey })
                else { return }
                aiThreads[currentIndex].threadTurns.append(
                    ChatMessage(
                        messageBody: "I couldn’t get a response. \(error.localizedDescription)",
                        fromVisitor: false
                    ))
                flushSnapshot()
            }
        }
    }

    // Stops the in-flight request and keeps what was already shown.
    func cancelGeneration() {
        generationFlight?.cancel()
        generationFlight = nil
        assistantBusy = false
    }

    // Re-asks the last user message.
    func regenerateAssistant() {
        guard !assistantBusy,
            let conversationID = activeThreadKey,
            let index = aiThreads.firstIndex(where: { $0.id == conversationID }),
            let answerIndex = aiThreads[index].threadTurns.lastIndex(where: { !$0.fromVisitor }),
            let prompt = aiThreads[index].threadTurns[..<answerIndex].last(where: { $0.fromVisitor })?.messageBody
        else { return }
        assistantBusy = true
        let search = webLookup
        let reasoning = deepThink
        generationFlight = Task {
            defer { if !Task.isCancelled { assistantBusy = false } }
            guard await requireServerSubscription(), !Task.isCancelled,
                let currentIndex = aiThreads.firstIndex(where: { $0.id == conversationID }),
                let currentAnswerIndex = aiThreads[currentIndex].threadTurns.lastIndex(where: { !$0.fromVisitor })
            else { return }
            aiThreads[currentIndex].threadTurns.removeSubrange(currentAnswerIndex...)
            let chatRelayID = aiThreads[currentIndex].remoteChatID ?? conversationID.uuidString
            flushSnapshot()
            do {
                let assistantPayload: AIReply
                if launchScenario != nil {
                    try await Task.sleep(for: .milliseconds(650))
                    assistantPayload = AIReply(
                        remoteChatID: chatRelayID, assistantBody: SampleContent.chatAnswer,
                        referenceMarks: SampleContent.fixturePages.prefix(3).map {
                            AICitation(pageTitle: $0.pageTitle, citationHref: $0.pageURL.absoluteString)
                        })
                } else {
                    assistantPayload = try await aiService.relayChat(
                        remoteChatID: chatRelayID, promptText: prompt, photoJPEG: nil, sourceIDs: [], webLookupEnabled: search,
                        think: reasoning)
                }
                try Task.checkCancellation()
                guard let currentIndex = aiThreads.firstIndex(where: { $0.id == conversationID }) else { return }
                aiThreads[currentIndex].remoteChatID = assistantPayload.remoteChatID
                aiThreads[currentIndex].threadTurns.append(
                    ChatMessage(
                        messageBody: assistantPayload.assistantBody, fromVisitor: false,
                        citationPages: assistantPayload.savedSources))
                flushSnapshot()
            } catch is CancellationError {} catch {
                guard !Task.isCancelled,
                    let currentIndex = aiThreads.firstIndex(where: { $0.id == conversationID })
                else { return }
                aiThreads[currentIndex].threadTurns.append(
                    ChatMessage(
                        messageBody: "I couldn’t get a response. \(error.localizedDescription)",
                        fromVisitor: false
                    ))
                flushSnapshot()
            }
        }
    }

    // Counts ads / trackers / redirects for the protection screen.
    func tallyBlockedRequest(_ kind: String) {
        guard launchScenario == nil else { return }
        switch kind {
        case "ads":
            tallyAds += 1
            UserDefaults.standard.set(tallyAds, forKey: "protection.ads")
        case "trackers":
            tallyTrackers += 1
            UserDefaults.standard.set(tallyTrackers, forKey: "protection.trackers")
        case "redirects":
            tallyRedirects += 1
            UserDefaults.standard.set(tallyRedirects, forKey: "protection.redirects")
        default:
            return
        }
        blockedTally += 1
    }

    enum LegalPage {
        case terms, privacy

        var heading: String { self == .terms ? "Terms of Use" : "Privacy Policy" }
        var link: URL? { self == .terms ? AppMetadata.termsOfUseLink : AppMetadata.privacyPolicyLink }
    }

    // Opens the legal
    func openLegal(_ page: LegalPage) {
        guard let linkURL = page.link else {
            bannerText = "\(page.heading) is not available right now."
            return
        }
        policySheet = LegalSheet(sheetHeading: page.heading, policyURL: linkURL)
    }

    // Contact support
    func contactSupport() {
        Task { @MainActor in
            await ApphudBootstrap.awaitApphudBootstrapped()
            let apphudID = ApphudBootstrap.apphudUserID()
            let supportUserRef = apphudID.isEmpty ? AppMetadata.apphudUserID() : apphudID
            guard let linkURL = AppMetadata.supportMailtoURL(apphudUserID: supportUserRef) else {
                bannerText = "Support contact is not available right now."
                return
            }
            await UIApplication.shared.open(linkURL)
        }
    }
}

/// What goes into state.json.
private struct PersistedState: Codable, Sendable {
    var tabStrip: [BrowserTab]
    var visitLedger: [SavedPage]
    var pinnedPages: [SavedPage]
    var aiThreads: [Conversation]
    var savedDownloads: [DownloadItem]

    private enum CodingKeys: String, CodingKey {
        case tabStrip = "tabs"
        case visitLedger = "history"
        case pinnedPages = "bookmarks"
        case aiThreads = "conversations"
        case savedDownloads = "downloads"
    }

    init(
        tabStrip: [BrowserTab],
        visitLedger: [SavedPage],
        pinnedPages: [SavedPage],
        aiThreads: [Conversation],
        savedDownloads: [DownloadItem]
    ) {
        self.tabStrip = tabStrip
        self.visitLedger = visitLedger
        self.pinnedPages = pinnedPages
        self.aiThreads = aiThreads
        self.savedDownloads = savedDownloads
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabStrip = try container.decode([BrowserTab].self, forKey: .tabStrip)
        visitLedger = try container.decode([SavedPage].self, forKey: .visitLedger)
        pinnedPages = try container.decode([SavedPage].self, forKey: .pinnedPages)
        aiThreads = try container.decode([Conversation].self, forKey: .aiThreads)
        savedDownloads = try container.decode([DownloadItem].self, forKey: .savedDownloads)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tabStrip, forKey: .tabStrip)
        try container.encode(visitLedger, forKey: .visitLedger)
        try container.encode(pinnedPages, forKey: .pinnedPages)
        try container.encode(aiThreads, forKey: .aiThreads)
        try container.encode(savedDownloads, forKey: .savedDownloads)
    }
}

private struct PersistedLoad: Sendable {
    var tabStrip: [BrowserTab]
    var visitLedger: [SavedPage]
    var pinnedPages: [SavedPage]
    var aiThreads: [Conversation]
    var savedDownloads: [DownloadItem]
    var removedXcomTab: Bool
}

/// Serialises disk writes so an older snapshot never overwrites a newer one.
private actor BrowserStateWriter {
    static let singleton = BrowserStateWriter()
    private var latestRevision = 0

    // write snapshot file
    func writeSnapshotFile(_ persistedBundle: PersistedState, to linkURL: URL, snapshotRevision: Int) throws {
        guard snapshotRevision >= latestRevision else { return }
        try FileManager.default.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(persistedBundle).write(to: linkURL, options: .atomic)
        latestRevision = snapshotRevision
    }
}
