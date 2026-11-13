//
//  PageAIView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 09/11/26.
//

import SwiftUI

/// Where the page-AI sheet is: asking, generating, answered, failed.
private enum PageAIPhase: Equatable {
    case panel, generating, stopped, offline, answer, error, notOnPage
}

/// Bottom sheet that summarises or asks about the current page.
struct PageAIView: View {
    let webLane: WebSession
    @Environment(BrowserStore.self) private var vault
    @Environment(\.dismiss) private var dismissSheet
    @State private var assistStage: PageAIPhase = .panel
    @State private var pendingAction: String?
    @State private var followUp = ""
    @State private var assistWorkUnit: Task<Void, Never>?
    @State private var feedbackPresented = false
    @State private var harvestedPageText = ""
    @State private var citationsExpanded = false
    @State private var assistReply: AIReply?
    @State private var answerLiked = false
    @State private var remoteChatID = UUID().uuidString
    private static let shortDetent = PresentationDetent.height(443)
    @State private var sheetDetent: PresentationDetent = PageAIView.shortDetent
    @State private var didSeed = false
    @State private var selectedPassage: String?
    @State private var pageTextPrimed = false
    @State private var assistErrorDetail = "Something went wrong on our side. Try again in a moment."

    private var review: String { vault.launchScenario ?? "" }
    private var headingText: String { assistStage == .panel ? "AI" : vault.pageAssistKind }
    private var k: CGFloat { sheetDetent == Self.shortDetent ? 1 / 0.96 : 1 }
    // Scales a design point to the sheet width (sheets render slightly inset).
    private func u(_ v: CGFloat) -> CGFloat { v * k }

    var body: some View {
        VStack(spacing: 0) {
            sheetTitleBar.padding(.top, sheetDetent == Self.shortDetent ? u(19) : 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    contextChip.padding(.bottom, assistStage == .answer ? u(14) : u(5))
                    stageBody
                }.padding(.horizontal, sheetDetent == Self.shortDetent ? u(18) : 20).padding(
                    .top, sheetDetent == Self.shortDetent ? u(5) : 0)
            }
            inputDeck
        }
        .ignoresSafeArea(.container, edges: sheetDetent == Self.shortDetent ? .bottom : [])
        .animation(.smooth(duration: 0.3), value: assistStage)
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
                // background fill
                .background(.regularMaterial, in: Capsule())
                // overlay lives outside the layout
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.12), radius: 15, y: 6)
                .padding(.top, 48)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
                .zIndex(20)
            }
        }
        .sheet(isPresented: $feedbackPresented) { FeedbackView() }
        // kicked off here so it cancels with the view
        .task {
            primeScenarioPhase()
            await primePageText()
        }
        .onDisappear { assistWorkUnit?.cancel() }
        .presentationDetents([Self.shortDetent, .large], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
    }

    private func primeScenarioPhase() {
        guard !didSeed else { return }
        didSeed = true
        switch review {
        case "answer", "answer-sources", "answer-streaming", "feedback", "feedback-sent", "feedback-error":
            assistStage = .answer
            sheetDetent = .large
        case "answer-medium", "answer-citation", "ai-quota":
            assistStage = review == "ai-quota" ? .panel : .answer
            sheetDetent = Self.shortDetent
        case "answer-error":
            assistStage = .error
            sheetDetent = .large
            pendingAction = "Summarize this page"
        case "answer-notonpage":
            assistStage = .notOnPage
            sheetDetent = .large
        case "generating": assistStage = .generating
        case "gen-stopped": assistStage = .stopped
        case "gen-offline", "ai-offline": assistStage = .offline
        default:
            if vault.launchScenario == nil, LinkPulse.singleton.linkSevered { assistStage = .offline }
        }
        if assistStage != .panel { vault.pageAssistKind = "Summary" }
        if review == "answer-sources" { citationsExpanded = true }
        if review.hasPrefix("feedback") { feedbackPresented = true }
        if let selection = vault.quotedSpan?.trimmingCharacters(in: .whitespacesAndNewlines), !selection.isEmpty {
            vault.quotedSpan = nil
            selectedPassage = selection
            pendingAction = "Explain this passage:\n\(selection)"
        }
    }

    // Grabs the readable text once before the first question.
    private func primePageText() async {
        guard vault.launchScenario == nil else { return }
        let fullPageText = await webLane.harvestReadableText()
        let quotedSnippet = await webLane.selectedText()
        if !quotedSnippet.isEmpty { selectedPassage = quotedSnippet }
        harvestedPageText =
            fullPageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (selectedPassage ?? "") : fullPageText
        pageTextPrimed = true
        if assistStage == .panel, let pendingAction {
            runPageAIAction(pendingAction)
        }
    }

    private var sheetTitleBar: some View {
        HStack(spacing: u(10)) {
            Text(headingText).font(.ui(u(20), weight: .regular)).foregroundStyle(.primary)
            Spacer(minLength: u(10))
            Button {
                dismissSheet()
            } label: {
                Image(systemName: "checkmark").font(.ui(u(19), weight: .semibold)).foregroundStyle(.white).frame(
                    width: u(32), height: u(32))
            }
            .browsGlassProminentButtonStyle().buttonBorderShape(.circle).tint(Palette.brandInk).accessibilityLabel("Done")
            .padding(.trailing, -u(5.6))
        }.padding(.horizontal, sheetDetent == Self.shortDetent ? u(18) : 20).frame(
            height: sheetDetent == Self.shortDetent ? u(50) : 64, alignment: .top)
    }

    // Context chip
    private var contextChip: some View {
        HStack(spacing: u(10)) {
            Image(systemName: "globe").font(.ui(u(16))).foregroundStyle(Palette.brandInk).frame(
                width: u(20), height: u(20))
            Text("\(vault.currentTab?.pageTitle ?? "Current page") · \(vault.currentTab?.pageURL?.host ?? "")").font(
                .ui(u(15))
            ).foregroundStyle(.primary).lineLimit(1)
            Spacer(minLength: 0)
        }.padding(.horizontal, u(12)).frame(height: u(40))
            .background(
                assistStage == .panel || assistStage == .generating || assistStage == .stopped || assistStage == .offline
                    ? PageAIColors.panelFill : PageAIColors.chipSoft, in: RoundedRectangle(cornerRadius: u(14)))
    }

    // stage body
    @ViewBuilder private var stageBody: some View {
        switch assistStage {
        case .panel: assistHome
        case .offline: aiOfflineState
        case .generating, .stopped: generatingSteps
        case .answer: answerView
        case .error: aiAnswerErrorState
        case .notOnPage:
            notice(
                "magnifyingglass", "Not on this page", "The page doesn’t cover that. Ask it in chat and AI will search the web.",
                64)
        }
    }

    // the assist home block
    @ViewBuilder private var assistHome: some View {
        switch review {
        case "ai-nocontent":
            notice(
                "doc.text", "Nothing to read here",
                "This page is mostly an image or hidden behind a login, so there’s no text to work with.", 56, retry: false)
        default:
            assistCaptionLine("Read", first: true)
            group {
                row("Summarize this page", "ai_summarize") { runPageAIAction("Summarize this page") }
                separator
                row("Key points", "ai_keypoints") { runPageAIAction("Key points") }
            }
            assistCaptionLine("Ask")
            group {
                row("Find info on this page", "ai_find") { runPageAIAction("Find info on this page") }
                separator
                row(
                    "Explain", "ai_explain", hint: selectedPassage == nil ? "Highlight text on the page, then tap Explain" : nil,
                    disabled: false
                ) {
                    Task { await runExplainFromSelection() }
                }
            }
        }
    }

    // Assist caption line
    private func assistCaptionLine(_ s: String, first: Bool = false) -> some View {
        Text(s).font(.ui(u(13))).foregroundStyle(Color(uiColor: .tertiaryLabel)).frame(height: u(18)).padding(
            .top, first ? 0 : u(5)
        ).padding(.bottom, u(5))
    }
    // group
    private func group<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 0, content: c).background(PageAIColors.panelFill, in: RoundedRectangle(cornerRadius: u(16)))
    }
    // Layout for separator
    private var separator: some View { Rectangle().fill(Palette.rgb(0xBFBFBF)).frame(height: u(1)).padding(.leading, u(52)) }
    private func row(
        _ headingText: String, _ asset: String, hint: String? = nil, disabled: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: u(12)) {
                Image(asset).resizable().frame(width: u(28), height: u(28))
                VStack(alignment: .leading, spacing: u(2)) {
                    Text(headingText).font(.ui(u(16))).foregroundStyle(
                        disabled ? Color(uiColor: .quaternaryLabel) : Color.primary
                    ).frame(height: u(21))
                    if let hint {
                        Text(hint).font(.ui(u(12))).foregroundStyle(Color(uiColor: .tertiaryLabel)).frame(height: u(16))
                    }
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, u(16)).frame(height: u(hint == nil ? 48 : 59)).opacity(disabled ? 0.4 : 1).contentShape(
                Rectangle())
        }.buttonStyle(.plain).disabled(disabled)
    }

    // Generating steps
    private var generatingSteps: some View {
        let steps =
            assistStage == .stopped
            ? ["Read the page", "Stopped before the key points", "Answer not written"]
            : ["Read the page", "Finding the key points", "Writing the answer"]
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 10) {
                    Image(
                        systemName: i == 0
                            ? "checkmark.circle.fill" : i == 1 && assistStage == .generating ? "circle.fill" : "circle"
                    )
                    .font(.ui(17, weight: .medium))
                    .foregroundStyle(
                        i == 0 || i == 1 && assistStage == .generating ? Palette.brandInk : Color(uiColor: .tertiaryLabel)
                    )
                    .frame(width: 18, height: 18)
                    Text(steps[i]).font(.ui(16)).foregroundStyle(
                        i == 1 && assistStage == .generating ? Color.primary : Color.secondary)
                }
            }
            if assistStage == .generating {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach([1.0, 1.0, 0.62], id: \.self) { stageWidth in
                        Capsule().fill(Color(uiColor: .tertiarySystemFill)).frame(height: 12).frame(
                            maxWidth: .infinity, alignment: .leading
                        ).scaleEffect(x: stageWidth, anchor: .leading)
                    }
                }.padding(.top, 10)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(assistStage == .stopped ? "Generation stopped" : "Connection lost").font(
                        .ui(17, weight: .semibold))
                    Text(
                        assistStage == .stopped
                            ? "You stopped before the answer finished." : "Check your connection and try again."
                    ).font(.ui(15)).foregroundStyle(Color(uiColor: .secondaryLabel))
                    Button(assistStage == .stopped ? "Start over" : "Try again") { runPageAIAction("Summarize this page") }
                        .browsGlassProminentButtonStyle().tint(Palette.brandInk)
                }.padding(.top, 6)
            }
        }.padding(.top, 14)
    }

    /// Answer error state.
    private var aiAnswerErrorState: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Palette.rgb(0xFF383C))
                    .frame(width: u(64), height: u(64))
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.ui(u(28)))
                    .foregroundStyle(.white)
            }
            Color.clear.frame(height: u(16))
            Text("Couldn’t finish the answer")
                .font(.ui(u(17), weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
            Color.clear.frame(height: u(6))
            Text(assistErrorDetail)
                .font(.ui(u(15)))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.center)
                .frame(maxWidth: u(290))
            Color.clear.frame(height: u(18))
            Button("Try again", action: retryAfterAnswerError)
                .font(.ui(u(17), weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: u(180), height: u(46))
                // background goes behind everything
                .background(Palette.brandInk, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, u(30))
        .padding(.top, u(4))
    }

    // Same prompt again after a failed answer.
    private func retryAfterAnswerError() {
        guard let pending = pendingAction, !pending.isEmpty else {
            assistStage = .panel
            return
        }
        runPageAIAction(pending)
    }

    /// Offline state: red wifi badge, centred copy, green Try again.
    private var aiOfflineState: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Palette.rgb(0xFF383C))
                    .frame(width: u(56), height: u(56))
                Image(systemName: "wifi.slash")
                    .font(.ui(u(24)))
                    .foregroundStyle(.white)
            }
            Color.clear.frame(height: u(16))
            Text("You’re offline")
                .font(.ui(u(17), weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
            Color.clear.frame(height: u(6))
            Text("AI needs a connection. The page itself stays available.")
                .font(.ui(u(15)))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.center)
                .frame(maxWidth: u(290))
            Color.clear.frame(height: u(18))
            Button("Try again", action: retryAfterOffline)
                .font(.ui(u(17), weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: u(180), height: u(46))
                // background goes behind everything
                .background(Palette.brandInk, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, u(30))
        .padding(.top, u(4))
    }

    // Tries after offline again
    private func retryAfterOffline() {
        guard !LinkPulse.singleton.linkSevered else { return }
        if let pending = pendingAction, !pending.isEmpty {
            runPageAIAction(pending)
        } else {
            assistStage = .panel
        }
    }

    // notice
    private func notice(_ asset: String, _ t: String, _ d: String, _ size: CGFloat, retry: Bool = true) -> some View {
        VStack(spacing: 10) {
            Image(systemName: asset)
                .font(.ui(size * 0.44, weight: .regular))
                .foregroundStyle(Palette.brandInk)
                .frame(width: size, height: size)
                .background(Palette.brandWash, in: Circle())
            Text(t).font(.ui(17, weight: .semibold)).foregroundStyle(.primary)
            Text(d).font(.ui(15)).foregroundStyle(Color(uiColor: .secondaryLabel)).multilineTextAlignment(.center)
            if retry {
                Button("Try again") { assistStage = .panel }.browsGlassProminentButtonStyle().tint(Palette.brandInk).padding(
                    .top, 6)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    // answer view
    private var answerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.smooth) { citationsExpanded.toggle() }
            } label: {
                HStack(spacing: u(6)) {
                    Image(systemName: "link").font(.ui(u(13))).foregroundStyle(Color(uiColor: .secondaryLabel)).frame(
                        width: u(16), height: u(16))
                    Text("Referenced \(assistReply?.savedSources.count ?? 6) sources").font(.ui(u(12))).foregroundStyle(
                        Color(uiColor: .secondaryLabel)
                    ).frame(height: u(16))
                    Image(systemName: "chevron.down").font(.ui(u(11))).foregroundStyle(Color(uiColor: .tertiaryLabel))
                        .rotationEffect(.degrees(citationsExpanded ? 180 : 0))
                }.frame(height: u(20))
            }.buttonStyle(.plain)
            if citationsExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(
                        Array(
                            [
                                ("How to brew coffee", "ncausa.org"), ("Water and extraction", "baristahustle.com"),
                                ("Brewing control chart", "sca.coffee"),
                            ].enumerated()), id: \.offset
                    ) { i, s in
                        HStack(spacing: 8) {
                            citation("\(i + 1)")
                            Text(s.0).font(.ui(15))
                            Text(s.1).font(.ui(13)).foregroundStyle(Color(uiColor: .secondaryLabel))
                        }
                    }
                }.padding(.top, 10)
            }
            if let assistReply {
                Text(assistReply.assistantBody).font(.ui(u(17))).textSelection(.enabled).padding(.top, u(18))
            } else {
                VStack(alignment: .leading, spacing: u(18)) {
                    ForEach(Array(SampleContent.fixtureSummaryBullets.enumerated()), id: \.offset) { index, point in
                        HStack(alignment: .top, spacing: u(12)) {
                            Image(systemName: ["thermometer.medium", "scalemass", "clock"][index])
                                .font(.ui(u(17), weight: .regular))
                                .foregroundStyle(Palette.brandInk)
                                .frame(width: u(26), height: u(26))
                                // background goes behind everything
                                .background(Palette.brandWash, in: Circle())
                            VStack(alignment: .leading, spacing: u(4)) {
                                Text(point.0).font(.ui(u(17), weight: .semibold)).foregroundStyle(.primary)
                                    .browsExactLineHeight(u(22))
                                Text(
                                    review == "answer-streaming" && index == 2
                                        ? "Pour-over takes 3–4 minutes, French press" : point.1
                                ).font(.ui(u(17))).foregroundStyle(Color(uiColor: .secondaryLabel))
                                    .browsExactLineHeight(u(22))
                                if index < 2 {
                                    HStack(spacing: u(4)) {
                                        ForEach(index == 0 ? ["1", "2"] : ["3"], id: \.self) {
                                            citation($0, highlighted: review == "answer-citation" && $0 == "1")
                                        }
                                    }.padding(.top, u(6))
                                }
                            }
                        }.padding(.vertical, u(8))
                    }
                }.padding(.top, u(18))
            }
            Rectangle().fill(Palette.rgb(0xD6E2DC)).frame(height: u(1)).padding(.top, u(18))
            HStack(spacing: u(10)) {
                Button {
                    vault.copyTextToPasteboard(answerPlainText)
                } label: {
                    actionIcon("doc.on.doc")
                }.accessibilityLabel("Copy")
                ShareLink(item: answerPlainText) { actionIcon("square.and.arrow.up") }.accessibilityLabel("Share")
                Button {
                    answerLiked.toggle()
                } label: {
                    actionIcon(answerLiked ? "hand.thumbsup.fill" : "hand.thumbsup", highlighted: answerLiked)
                }
                .accessibilityLabel(answerLiked ? "Helpful, selected" : "Helpful")
                Button {
                    feedbackPresented = true
                } label: {
                    actionIcon("hand.thumbsdown")
                }.accessibilityLabel("Report answer")
                Spacer()
                Button {
                    runPageAIAction("Summary")
                } label: {
                    HStack(spacing: u(6)) {
                        Image(systemName: "arrow.clockwise").font(.ui(u(13), weight: .semibold))
                        Text("Regenerate").font(.ui(u(13)))
                    }
                    .foregroundStyle(Palette.brandInk).padding(.horizontal, u(12)).frame(height: u(36)).background(
                        Palette.brandWash, in: Capsule())
                }
            }.buttonStyle(.plain).padding(.top, u(14))
            Text("AI can make mistakes. Check important details on the page.").font(.ui(u(12))).foregroundStyle(
                Color(uiColor: .tertiaryLabel)
            ).frame(height: u(16)).padding(.top, u(14))
        }
    }
    // action icon
    private func actionIcon(_ name: String, highlighted: Bool = false) -> some View {
        Image(systemName: name).font(.ui(u(15))).foregroundStyle(
            highlighted ? Palette.brandInk : Color(uiColor: .secondaryLabel)
        ).frame(width: u(38), height: u(38)).background(highlighted ? Palette.brandWash : PageAIColors.actionFill, in: Circle())
    }
    private func citation(_ s: String, highlighted: Bool = false) -> some View {
        Text(s).font(.ui(u(11))).foregroundStyle(highlighted ? .white : Palette.brandInk).frame(height: u(15)).padding(
            .horizontal, u(5)
        )
        // background goes behind everything
        .background(highlighted ? Palette.brandInk : Palette.brandWash, in: RoundedRectangle(cornerRadius: u(6)))
    }

    // Input deck
    private var inputDeck: some View {
        HStack(spacing: u(10)) {
            TextField(
                assistStage == .generating
                    ? "Generating…"
                    : assistStage == .panel || assistStage == .stopped || assistStage == .offline
                        ? "Ask anything about this page" : "Ask a follow-up", text: $followUp
            )
            .font(.ui(u(15))).submitLabel(.send).onSubmit { runPageAIAction(followUp) }.disabled(
                assistStage == .generating)
            Button {
                if assistStage == .generating {
                    assistWorkUnit?.cancel()
                    assistStage = .stopped
                } else {
                    runPageAIAction(followUp)
                }
            } label: {
                Image(assistStage == .generating ? "ai_stop" : "ai_send").resizable().frame(width: u(34), height: u(34))
            }.buttonStyle(.plain).accessibilityLabel(assistStage == .generating ? "Stop" : "Send")
                .background(Circle().fill(Palette.brandInk.opacity(0.35)).blur(radius: u(10)).frame(width: u(46), height: u(46)))
        }.padding(.leading, u(16)).padding(.trailing, u(6)).frame(height: u(46))
            .background(Palette.canvasView, in: Capsule()).overlay(Capsule().stroke(Palette.rgb(0xD6E2DC), lineWidth: 1))
            .padding(.horizontal, sheetDetent == Self.shortDetent ? u(18) : 20).padding(.top, u(10)).padding(
                .bottom, sheetDetent == Self.shortDetent ? u(16) : 24)
    }

    private var answerPlainText: String {
        assistReply?.assistantBody ?? SampleContent.fixtureSummaryBullets.map { $0.0 + "\n" + $0.1 }.joined(separator: "\n\n")
    }

    /// Same flow as the web selection menu.
    private func runExplainFromSelection() async {
        let snippet = await webLane.selectedText()
        guard !snippet.isEmpty else {
            selectedPassage = nil
            vault.bannerText = "Select text on the page first."
            return
        }
        selectedPassage = snippet
        runPageAIAction("Explain this passage:\n\(snippet)")
    }

    // Sends the quick action and moves to the generating state.
    private func runPageAIAction(_ action: String) {
        guard !vault.incognito else {
            vault.bannerText = "Page AI isn’t available in private mode."
            return
        }
        guard assistStage != .generating else { return }
        let q = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        assistWorkUnit = Task { @MainActor in
            guard await vault.requireServerSubscription(), !Task.isCancelled else { return }
            if vault.launchScenario == nil, !pageTextPrimed {
                vault.bannerText = "Still reading the page — try again in a second."
                return
            }
            guard vault.launchScenario != nil || !harvestedPageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                vault.bannerText = "Couldn’t find any text to read on this page."
                return
            }
            if vault.launchScenario != "ai-offline", vault.launchScenario != "gen-offline", LinkPulse.singleton.linkSevered {
                pendingAction = q
                assistStage = .offline
                return
            }
            vault.pageAssistKind = q.hasPrefix("Explain") ? "Explain" : q.contains("Summarize") ? "Summary" : q
            pendingAction = q
            assistStage = .generating
            do {
                if vault.launchScenario != nil {
                    try await Task.sleep(for: .milliseconds(800))
                } else {
                    if harvestedPageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        harvestedPageText = await webLane.harvestReadableText()
                    }
                    guard !harvestedPageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        assistErrorDetail = "This page doesn’t have readable text for AI."
                        assistStage = .error
                        return
                    }
                    let plainTextSourceID = try await vault.aiService.preparePlainText(harvestedPageText)
                    let assistPrompt = q == "Summary" || q.contains("Summarize") ? "Summarize the attached page." : q
                    let slot = try await vault.aiService.relayChat(
                        remoteChatID: remoteChatID, promptText: assistPrompt, photoJPEG: nil, sourceIDs: [plainTextSourceID],
                        webLookupEnabled: false, think: vault.deepThink)
                    try Task.checkCancellation()
                    assistReply = slot
                    remoteChatID = slot.remoteChatID
                }
                try Task.checkCancellation()
                pendingAction = nil
                assistStage = .answer
                if let linkURL = vault.currentTab?.pageURL { vault.markAiAnswered(linkURL) }
                sheetDetent = .large
                followUp = ""
            } catch is CancellationError {} catch {
                guard !Task.isCancelled else { return }
                if LinkPulse.singleton.linkSevered {
                    assistStage = .offline
                } else {
                    assistErrorDetail = pageAIErrorBlurb(error)
                    assistStage = .error
                }
            }
        }
    }

    // Short user-facing line for an API error.
    private func pageAIErrorBlurb(_ error: Error) -> String {
        if let api = error as? APIError {
            return api.errorDescription ?? "Something went wrong on our side. Try again in a moment."
        }
        return error.localizedDescription.isEmpty
            ? "Something went wrong on our side. Try again in a moment." : error.localizedDescription
    }
}

private enum PageAIColors {
    static let panelFill = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? .secondarySystemBackground : UIColor(red: 223 / 255, green: 223 / 255, blue: 223 / 255, alpha: 1)
        })
    static let chipSoft = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(Palette.brandWash) : UIColor(red: 231 / 255, green: 239 / 255, blue: 235 / 255, alpha: 1)
        })
    static let actionFill = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? .secondarySystemFill : UIColor(red: 242 / 255, green: 245 / 255, blue: 243 / 255, alpha: 1)
        })
}
