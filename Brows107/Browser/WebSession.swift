//
//  WebSession.swift
//  Brows107
//  
//  Created by Aleksandra Savchuk on 29/10/26.
//

import SwiftUI
@preconcurrency import WebKit
import Observation
import UIKit

@Observable @MainActor
final class WebSession: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, UIScrollViewDelegate,
    WKScriptMessageHandler
{
    var navPending = false
    var isScrolled = false
    var pageError: PageLoadError?
    var canStepBack = false
    var canGoForward = false
    var readerActive = false
    var findText = ""
    var pageText = ""
    var showFind = false
    var findMatchIndex = 0
    var findMatchCount = 0
    /// True when the loaded page’s own background is light, so the status-bar icons stay readable on it.
    var pageUsesLightBackground = false
    @ObservationIgnored var vaultRef: BrowserStore?
    @ObservationIgnored private var pageSurfaces: [UUID: WKWebView] = [:]
    @ObservationIgnored private var focusedTabKey: UUID?
    @ObservationIgnored private var appliedLoadRevision: [UUID: Int] = [:]
    @ObservationIgnored private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    @ObservationIgnored private var lastTopColorCapture: CFAbsoluteTime = 0
    @ObservationIgnored private var findRevision = 0
    @ObservationIgnored private var findSavedKeyboardDismissMode: UIScrollView.KeyboardDismissMode?

    var liveWebView: WKWebView? { focusedTabKey.flatMap { pageSurfaces[$0] } }

    // Returns the web view for a tab, creating it on first use.
    func hostedWebView(for tab: BrowserTab) -> WKWebView {
        focusedTabKey = tab.id
        if let hostName = pageSurfaces[tab.id] {
            isScrolled = hostName.scrollView.contentOffset.y + hostName.scrollView.adjustedContentInset.top > 12
            if let linkURL = tab.pageURL, appliedLoadRevision[tab.id] != tab.reloadToken {
                appliedLoadRevision[tab.id] = tab.reloadToken
                if !hostName.isLoading { applyURLToWebView(linkURL, in: hostName) }
            }
            refreshNavigationState(from: hostName)
            hideScrollEdges(hostName.scrollView)
            syncTopScrollInset(for: hostName)
            return hostName
        }
        let webConfig = WKWebViewConfiguration()
        if tab.incognitoTab { webConfig.websiteDataStore = .nonPersistent() }
        ContentBlockerEngine.installSelectionAppearance(to: webConfig.userContentController)
        webConfig.userContentController.add(self, name: "browsProtection")
        let hostName = BrowsWebView(frame: .zero, configuration: webConfig)
        hostName.allowsExplain = { [weak self] in self?.vaultRef?.incognito != true }
        hostName.explainHandler = { [weak self] in self?.queueExplainFromSelection() }
        hostName.lookUpHandler = { [weak self] in self?.queueLookupFromSelection() }
        hostName.navigationDelegate = self
        hostName.uiDelegate = self
        hostName.scrollView.delegate = self
        hostName.scrollView.contentInsetAdjustmentBehavior = .never
        hostName.scrollView.contentInset.bottom = 96
        hostName.scrollView.verticalScrollIndicatorInsets.bottom = 96
        hostName.isOpaque = false
        hostName.backgroundColor = .clear
        hostName.tintColor = UIColor(Palette.brandInk)
        hostName.scrollView.backgroundColor = .clear
        hostName.scrollView.isDirectionalLockEnabled = true
        hideScrollEdges(hostName.scrollView)
        hostName.allowsBackForwardNavigationGestures = false
        hostName.isInspectable = false
        isScrolled = false
        pageSurfaces[tab.id] = hostName
        refreshShieldScripts(hostName)
        if let linkURL = tab.pageURL {
            appliedLoadRevision[tab.id] = tab.reloadToken
            applyURLToWebView(linkURL, in: hostName)
        }
        refreshNavigationState(from: hostName)
        return hostName
    }

    // Step history back
    func stepHistoryBack() {
        guard let hostName = liveWebView, hostName.canGoBack else { return }
        hostName.goBack()
        refreshNavigationState(from: hostName)
    }


    // refreshes navigation state
    private func refreshNavigationState(from hostName: WKWebView) {
        guard hostName == liveWebView else { return }
        canStepBack = hostName.canGoBack
        canGoForward = hostName.canGoForward
    }

    // applies url to web view
    private func applyURLToWebView(_ linkURL: URL, in hostName: WKWebView) {
        guard vaultRef?.launchScenario.flatMap(PageLoadError.sampleFailure) == nil else { return }
        if LinkPulse.singleton.linkSevered, !linkURL.isFileURL {
            self.navPending = false
            pageError = .offline
            return
        }
        if linkURL.isFileURL {
            hostName.loadFileURL(linkURL, allowingReadAccessTo: linkURL.deletingLastPathComponent())
        } else {
            hostName.load(URLRequest(url: linkURL))
        }
    }

    // Releases web views of tabs that no longer exist.
    func purgeOrphanWebViews() {
        guard let vaultRef else { return }
        for id in Array(pageSurfaces.keys) where !vaultRef.tabStrip.contains(where: { $0.id == id }) {
            pageSurfaces[id]?.stopLoading()
            pageSurfaces[id]?.navigationDelegate = nil
            pageSurfaces[id]?.uiDelegate = nil
            self.pageSurfaces.removeValue(forKey: id)
            appliedLoadRevision.removeValue(forKey: id)
        }
    }

    // Re-applies the blocking rules after settings change.
    func refreshShieldScripts(_ hostName: WKWebView? = nil) {
        guard let vaultRef else { return }    
        let webViewBatch = hostName.map { [$0] } ?? Array(pageSurfaces.values)    
        let blockAds = vaultRef.shieldAds
        let blockTrackers = vaultRef.shieldTrackers
        let blockRedirects = vaultRef.shieldRedirects
        let exceptions = vaultRef.shieldExceptions
        Task {
            for hostedWebView in webViewBatch {
                let pageHost = hostedWebView.url?.host ?? ""
                let shieldEngaged = !exceptions.contains(pageHost) && !ContentBlockerEngine.isPageSafelisted(pageHost)
                await ContentBlockerEngine.installBlockRules(
                    to: hostedWebView.configuration.userContentController,
                    blockAds: blockAds,
                    blockTrackers: blockTrackers,
                    blockRedirects: blockRedirects,
                    shieldEngaged: shieldEngaged
                )
            }
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navPending = true
        if vaultRef?.launchScenario.flatMap(PageLoadError.sampleFailure) == nil {
            pageError = nil
        }
        pageText = ""
        readerActive = false
        (webView as? BrowsWebView)?.sampledPageColor = nil
        (webView as? BrowsWebView)?.topBleedUnlocked = false
        pageUsesLightBackground = false
        if vaultRef?.launchScenario == nil { vaultRef?.blockedTally = 0 }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive scriptEnvelope: WKScriptMessage) {
        guard scriptEnvelope.name == "browsProtection", let shieldPayload = scriptEnvelope.body as? String else { return }
        vaultRef?.tallyBlockedRequest(shieldPayload)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        refreshNavigationState(from: webView)
        capturePageColor(webView)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let webView = liveWebView, scrollView == webView.scrollView else { return }
        hideScrollEdges(scrollView)
        let comfort = comfortTopInset(for: webView)
        let topEdge = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        let pastScrollThreshold = topEdge > 12
        if isScrolled != pastScrollThreshold { isScrolled = pastScrollThreshold }
        if let brows = webView as? BrowsWebView {
            if !brows.topBleedUnlocked, scrollView.contentOffset.y > -comfort + 10 {
                brows.topBleedUnlocked = true
                syncTopScrollInset(for: webView)
            } else if brows.topBleedUnlocked {
                if topEdge <= 2 || scrollView.contentInset.top > 0.5 {
                    syncTopScrollInset(for: webView)
                }
            }
        }
        let sampleInstant = CFAbsoluteTimeGetCurrent()
        guard sampleInstant - lastTopColorCapture > 0.3 else { return }
        lastTopColorCapture = sampleInstant
        capturePageColor(webView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        finishTopBleedIfNeeded(scrollView)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishTopBleedIfNeeded(scrollView)
    }


    // finish top bleed if needed
    private func finishTopBleedIfNeeded(_ scrollView: UIScrollView) {
        guard let webView = liveWebView, scrollView == webView.scrollView else { return }
        let topEdge = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        guard topEdge <= 2, let brows = webView as? BrowsWebView, brows.topBleedUnlocked else { return }
        brows.topBleedUnlocked = false
        syncTopScrollInset(for: webView)
    }

    // hide scroll edges
    private func hideScrollEdges(_ scrollView: UIScrollView) {
        guard #available(iOS 26.0, *) else { return }
        scrollView.topEdgeEffect.isHidden = true
        scrollView.bottomEdgeEffect.isHidden = true
        scrollView.leftEdgeEffect.isHidden = true
        scrollView.rightEdgeEffect.isHidden = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView == liveWebView else { return }
        navPending = false
        pageError = nil
        refreshNavigationState(from: webView)
        if vaultRef?.launchScenario == "page-scroll" { webView.evaluateJavaScript("window.scrollTo(0, 240)") }
        if let linkURL = webView.url { vaultRef?.logVisit(headingText: webView.title ?? "", url: linkURL) }
        (webView as? BrowsWebView)?.topBleedUnlocked = false
        syncTopScrollInset(for: webView)
        capturePageColor(webView) 
        if showFind, !findText.isEmpty { searchInPage(findText) }
    }

    // Snapshot for the tab switcher.
    func capturePreview(for tabID: UUID) {
        guard let hostName = pageSurfaces[tabID], hostName.url != nil else { return }
        captureTabPreview(for: hostName, tabID: tabID)
    }

    // refreshes visible tab previews
    func refreshVisibleTabPreviews(_ tabs: [BrowserTab]) {
        for tab in tabs where tab.pageURL != nil {
            capturePreview(for: tab.id)
        }
    }

    // captures tab preview
    private func captureTabPreview(for webView: WKWebView, tabID: UUID? = nil) {
        let id = tabID ?? focusedTabKey
        guard let id, webView.url != nil else { return }  
        let snapshotConfig = WKSnapshotConfiguration()
        snapshotConfig.snapshotWidth = NSNumber(value: 480)
        webView.takeSnapshot(with: snapshotConfig) { image, _ in
            guard let image else { return }
            Task {
                TabPreviewStore.singleton.storeThumb(image, for: id)
            }
        }
    }

    /// Top content inset at rest: 0 — page bleeds under the status bar to the lower edge of the island (no black band).
    private func comfortTopInset(for webView: WKWebView) -> CGFloat {
        _ = webView
        return 0
    }

    // Keeps content below the floating address bar. (recieves the inset from the chrome)
    func syncTopScrollInset(for webView: WKWebView) {
        let scroll = webView.scrollView
        let indicatorTop = webView.window?.safeAreaInsets.top ?? 0
        if abs(scroll.verticalScrollIndicatorInsets.top - indicatorTop) > 0.5 {
            scroll.verticalScrollIndicatorInsets.top = indicatorTop
        }
        let comfort = comfortTopInset(for: webView)
        let topEdge = scroll.contentOffset.y + scroll.adjustedContentInset.top
        let atTop = topEdge <= 2
        let userIdle = !scroll.isTracking && !scroll.isDragging && !scroll.isDecelerating
        let brows = webView as? BrowsWebView
        if brows?.topBleedUnlocked == true {
            if atTop, userIdle {
                brows?.topBleedUnlocked = false
            } else {
                if scroll.contentInset.top > 0.5 {
                    let delta = scroll.contentInset.top
                    scroll.contentInset.top = 0
                    let y = scroll.contentOffset.y + delta
                    scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: false)
                }
                return
            }
        }
        guard comfort > 0 else {
            if scroll.contentInset.top > 0.5 { scroll.contentInset.top = 0 }
            return
        }
        if abs(scroll.contentInset.top - comfort) > 0.5 {
            scroll.contentInset.top = comfort
        }    
        let restY = -comfort
        if userIdle, atTop {
            if abs(scroll.contentOffset.y - restY) > 0.5 {
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: restY), animated: false)
            }
        } else if !scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating, scroll.contentOffset.y > restY + 0.5, atTop {
            scroll.contentOffset.y = restY
        }
    }

    /// Bleed under the status bar follows the pixel row actually visible at the top, not `body` (many sites use a dark header on a white page).
    private func capturePageColor(_ webView: WKWebView) {
        let pageColorProbeJS = """
            (() => {
              const opaque = (value) => {
                if (!value || value === 'transparent' || value === 'rgba(0, 0, 0, 0)') return false;
                const m = value.match(/rgba?\\(([^)]+)\\)/);
                if (!m) return true;
                const parts = m[1].split(',').map((part) => parseFloat(part.trim()));
                return parts.length < 4 || parts[3] > 0.05;
              };
              const resolve = (el) => {
                let node = el;
                while (node && node !== document.documentElement.parentElement) {
                  const value = getComputedStyle(node).backgroundColor;
                  if (opaque(value)) return value;
                  node = node.parentElement;
                }
                return '';
              };
              const x = Math.max(1, Math.floor(window.innerWidth / 2));
              const sampleY = 2;
              const top = resolve(document.elementFromPoint(x, sampleY));
              if (top) return top;
              return resolve(document.body) || resolve(document.documentElement);
            })()
            """
        Task {
            // guard first, work after
            guard let slot = try? await webView.evaluateJavaScript(pageColorProbeJS), let draftText = slot as? String,
                let color = UIColorProbe.fromCSSRGB(draftText)
            else { return }
            guard webView == liveWebView else { return }
            (webView as? BrowsWebView)?.sampledPageColor = color
            pageUsesLightBackground = UIColorProbe.isLightBackground(color)
            webView.superview?.setNeedsLayout()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        navPending = false
        guard webView == liveWebView else { return }
        if vaultRef?.launchScenario.flatMap(PageLoadError.sampleFailure) != nil { return }
        pageError = PageLoadError.mapURLError(error, url: webView.url ?? vaultRef?.currentTab?.pageURL)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let linkURL = navigationAction.request.url else {  
            decisionHandler(.cancel)
            return
        }
        let redirectHostKind = ContentBlockerEngine.hostShieldKind(forHost: linkURL.host ?? "")
        guard ["https", "http", "about", "file"].contains(linkURL.scheme ?? "") else {
            decisionHandler(.cancel)
            return
        }
        if redirectHostKind == "redirects", vaultRef?.shieldRedirects == true {
            vaultRef?.tallyBlockedRequest("redirects")
            decisionHandler(.cancel)
            return
        }
        if navigationAction.shouldPerformDownload { decisionHandler(.download) } else { decisionHandler(.allow) }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }


    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let linkURL = navigationAction.request.url,
            ["http", "https"].contains(linkURL.scheme ?? "")
        {
            vaultRef?.navigateInput(linkURL.absoluteString, inNewTab: true)
        }
        return nil
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(
        _ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        let downloadScratchDir = URL.applicationSupportDirectory.appending(
            path: "107Brows/downloads/" + UUID().uuidString, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: downloadScratchDir, withIntermediateDirectories: true)
            let name = (suggestedFilename as NSString).lastPathComponent
            let destination = downloadScratchDir.appending(path: name.isEmpty ? "Download" : name)
            downloadDestinations[ObjectIdentifier(download)] = destination
            completionHandler(destination)
        } catch {
            completionHandler(nil)
            vaultRef?.bannerText = "There is not enough space to save this file."
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let linkURL = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        let bytes = (try? linkURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        vaultRef?.savedDownloads.insert(
            DownloadItem(
                assetLabel: linkURL.lastPathComponent, diskFileURL: linkURL,
                byteSizeLabel: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)), at: 0)
        vaultRef?.flushSnapshot()
        vaultRef?.modalLane = .downloads
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {  
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        vaultRef?.bannerText = "Download failed — tap the link again to retry."
    }


    func queueExplainFromSelection() {
        guard let vaultRef, !vaultRef.incognito, let liveWebView else { return }
        Task {
            let selection = await selectedText(in: liveWebView)
            guard !selection.isEmpty else { return }
            vaultRef.quotedSpan = selection
            vaultRef.pageAssistKind = "Explain"
            vaultRef.modalLane = .ai
        }
    }

    // queue lookup from selection
    func queueLookupFromSelection() {
        guard let vaultRef, let liveWebView else { return }
        let hostName = liveWebView
        Task {
            let picked = await selectedText(in: hostName)
            guard !picked.isEmpty,
                let lookupLink = AddressResolver.coerceNavigableURL(picked, engine: vaultRef.queryEngine)
            else { return }
            hostName.load(URLRequest(url: lookupLink))
        }
    }

    func selectedText(in hostName: WKWebView? = nil) async -> String {
        guard let hostName = hostName ?? liveWebView else { return "" }
        let selectionSnippet = try? await hostName.evaluateJavaScript("window.getSelection().toString()")
        return String((selectionSnippet as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
    }


    func harvestReadableText() async -> String {
        guard vaultRef?.incognito != true, let liveWebView else { return "" }
        let bodyPlainText = try? await liveWebView.evaluateJavaScript("document.body.innerText")
        pageText = String((bodyPlainText as? String ?? "").prefix(60000))
        return pageText
    }

    enum InPageFindDirection { case forward, backward }

    // Find in page: highlights all matches and the active one.
    func searchInPage(_ query: String) {
        findText = query
        findMatchIndex = 0
        self.findMatchCount = 0
        findRevision += 1
        let revisionNumber = findRevision
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clearInPageFind()
            return
        }
        guard let liveWebView else { return }
        if findSavedKeyboardDismissMode == nil {
            findSavedKeyboardDismissMode = liveWebView.scrollView.keyboardDismissMode
        }
        liveWebView.scrollView.keyboardDismissMode = .none
        let encodedQuery =
            (try? JSONSerialization.data(withJSONObject: [query])).flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        let queryLiteral = String(encodedQuery.dropFirst().dropLast())
        let findScript = """
            (() => {
              const requestRevision = \(revisionNumber);
              const currentRevision = Number(window.__findRequestRevision || 0);
              if (requestRevision < currentRevision) return { stale: true, count: 0, index: 0 };
              window.__findRequestRevision = requestRevision;
              const query = \(queryLiteral).toLocaleLowerCase();
              if (!query) return { count: 0, index: 0 };
              const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
              const matches = [];
              const isVisible = (element) => {
                for (let current = element; current; current = current.parentElement) {
                  if (current.hidden || current.getAttribute('aria-hidden') === 'true') return false;
                  const style = getComputedStyle(current);
                  if (style.display === 'none' || style.visibility === 'hidden' || style.visibility === 'collapse' || Number(style.opacity) === 0) return false;
                  if (current === document.body) break;
                }
                return true;
              };
              let node;
              while ((node = walker.nextNode())) {
                if (!node.nodeValue || !node.nodeValue.trim() || node.parentElement?.closest('script,style,noscript,svg,template,[aria-hidden="true"]')) continue;
                const text = node.nodeValue.toLocaleLowerCase();
                if (!text.includes(query) || !isVisible(node.parentElement)) continue;
                let start = 0;
                let position;
                while ((position = text.indexOf(query, start)) !== -1) {
                  const range = document.createRange();
                  range.setStart(node, position);
                  range.setEnd(node, position + query.length);
                  if (range.getClientRects().length) matches.push(range);
                  start = position + query.length;
                }
              }
              window.__findMatches = matches;
              window.__findIndex = matches.length ? 0 : -1;
              const styleId = 'find-highlight-style';
              let style = document.getElementById(styleId);
              if (!style) {
                style = document.createElement('style');
                style.id = styleId;
                document.head.appendChild(style);
              }
              style.textContent = '::highlight(find-all){background:#ffe45c;color:#111}::highlight(find-active){background:#41c99b;color:#111}';
              if (window.CSS?.highlights && window.Highlight) {
                CSS.highlights.delete('find-all');
                CSS.highlights.delete('find-active');
                if (matches.length) {
                  if (matches.length > 1) CSS.highlights.set('find-all', new Highlight(...matches.slice(1)));
                  CSS.highlights.set('find-active', new Highlight(matches[0]));
                }
              }
              if (matches.length) {
                const rect = matches[0].getBoundingClientRect();
                window.scrollTo({ top: window.scrollY + rect.top - window.innerHeight * 0.42, behavior: 'smooth' });
              }
              return { count: matches.length, index: matches.length ? 1 : 0 };
            })()
            """
        Task {
            do {
                try await Task.sleep(for: .milliseconds(110))
            } catch {
                logSwallowed(error)
            }
            guard self.findRevision == revisionNumber, self.findText == query else { return }
            let searchResult = try? await liveWebView.evaluateJavaScript(findScript) as? [String: Any]
            guard self.findRevision == revisionNumber, self.findText == query, searchResult?["stale"] as? Bool != true else {
                return
            }
            self.findMatchCount = searchResult?["count"] as? Int ?? 0
            self.findMatchIndex = searchResult?["index"] as? Int ?? 0
        }
    }

    // Moves on to find
    func advanceFind(direction: InPageFindDirection = .forward) {
        guard !findText.isEmpty else { return }
        guard let liveWebView else { return }
        if findSavedKeyboardDismissMode == nil {
            findSavedKeyboardDismissMode = liveWebView.scrollView.keyboardDismissMode
        }
        liveWebView.scrollView.keyboardDismissMode = .none
        let searchQuery = findText
        let revisionNumber = findRevision
        let step = direction == .forward ? 1 : -1
        let moveScript = """
            (() => {
              if (Number(window.__findRequestRevision || 0) !== \(revisionNumber)) return { stale: true, count: 0, index: 0 };
              const matches = window.__findMatches || [];
              if (!matches.length) return { count: 0, index: 0 };
              const current = Number.isInteger(window.__findIndex) ? window.__findIndex : 0;
              const index = (current + (\(step)) + matches.length) % matches.length;
              window.__findIndex = index;
              if (window.CSS?.highlights && window.Highlight) {
                CSS.highlights.delete('find-all');
                CSS.highlights.delete('find-active');
                const otherMatches = matches.filter((_, matchIndex) => matchIndex !== index);
                if (otherMatches.length) CSS.highlights.set('find-all', new Highlight(...otherMatches));
                CSS.highlights.set('find-active', new Highlight(matches[index]));
              }
              const activeRange = matches[index];
              const rect = activeRange.getBoundingClientRect();
              const startNode = activeRange.startContainer;
              let scrollParent = startNode.nodeType === Node.ELEMENT_NODE ? startNode : startNode.parentElement;
              while (scrollParent && scrollParent !== document.body && scrollParent !== document.documentElement) {
                const style = getComputedStyle(scrollParent);
                if (scrollParent.scrollHeight > scrollParent.clientHeight && /(auto|scroll|overlay)/.test(style.overflowY)) break;
                scrollParent = scrollParent.parentElement;
              }
              if (scrollParent && scrollParent !== document.body && scrollParent !== document.documentElement) {
                const parentRect = scrollParent.getBoundingClientRect();
                scrollParent.scrollTo({ top: scrollParent.scrollTop + rect.top - parentRect.top - scrollParent.clientHeight * 0.42, behavior: 'smooth' });
              } else {
                window.scrollTo({ top: window.scrollY + rect.top - window.innerHeight * 0.42, behavior: 'smooth' });
              }
              return { count: matches.length, index: index + 1 };
            })()
            """
        Task {
            let moveResult = try? await liveWebView.evaluateJavaScript(moveScript) as? [String: Any]
            guard self.findText == searchQuery, self.findRevision == revisionNumber, moveResult?["stale"] as? Bool != true else {
                return
            }
            self.findMatchCount = moveResult?["count"] as? Int ?? self.findMatchCount
            self.findMatchIndex = moveResult?["index"] as? Int ?? self.findMatchIndex
        }
    }

    // clears in page find
    func clearInPageFind() {
        findRevision += 1
        let clearRevision = findRevision
        if let liveWebView, let findSavedKeyboardDismissMode {
            liveWebView.scrollView.keyboardDismissMode = findSavedKeyboardDismissMode
            self.findSavedKeyboardDismissMode = nil
        }
        if let liveWebView {
            Task {
                _ = try? await liveWebView.evaluateJavaScript(
                    """
                    (() => {
                      window.__findRequestRevision = Math.max(Number(window.__findRequestRevision || 0), \(clearRevision));
                      if (window.CSS?.highlights) {
                        CSS.highlights.delete('find-all');
                        CSS.highlights.delete('find-active');
                      }
                      window.__findMatches = [];
                      window.__findIndex = -1;
                      document.getElementById('find-highlight-style')?.remove();
                      return true;
                    })()
                    """)
            }
        }
    }

    // Wipes cookies, cache and storage.
    func clearWebData() async {
        let defaultWebsiteStore = WKWebsiteDataStore.default()
        await defaultWebsiteStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }
}

extension CGRect {
    // almost equal
    func almostEqual(to other: CGRect) -> Bool {
        abs(minX - other.minX) < 0.5 && abs(minY - other.minY) < 0.5 && abs(width - other.width) < 0.5
            && abs(height - other.height) < 0.5
    }
}
