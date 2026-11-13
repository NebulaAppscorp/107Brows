//
//  AddressSearchView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 09/11/26.
//

import SwiftUI
import UIKit

struct SearchTapStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

/// Full-screen address sheet: suggestions, history and the camera shortcut.
struct AddressSearchView: View {
    // from the environment
    @State private var draftText: String
    @Environment(BrowserStore.self) private var vault
    @Environment(\.dismiss) private var dismissSheet
    @Environment(\.colorScheme) private var interfaceScheme
    @FocusState private var queryFocused: Bool
    @State private var ask = false
    @State private var privateSearch = false
    @State private var remoteSuggestions: [SearchSuggestionRow] = []
    @State private var suggestTask: Task<Void, Never>?
    @State private var historyTask: Task<Void, Never>?
    @State private var indexTask: Task<Void, Never>?
    @State private var indexedPages: [IndexedSavedPage] = []
    @State private var rankedHistory: [IndexedSavedPage] = []

    init(initialText: String = "") {
        _draftText = State(initialValue: initialText)
    }

    /// Remote-suggestion rows. Review fixtures stay local; everything else comes from Google.
    private var suggestionRows: [SearchSuggestionRow] {
        #if DEBUG
            if vault.launchScenario == "search" {
                return [
                    SearchSuggestionRow(head: "how to brew coffee ", tail: "without a filter"),
                    SearchSuggestionRow(head: "how to brew coffee ", tail: "french press"),
                ]
            }
        #endif
        return remoteSuggestions
    }

    private var shelfHits: [IndexedSavedPage] {
        #if DEBUG
            if vault.launchScenario == "search" {
                return [
                    IndexedSavedPage(
                        page: SavedPage(
                            pageTitle: "How to brew coffee", pageURL: URL(string: "https://ncausa.org")!,
                            recordedAt: .now.addingTimeInterval(-86400 * 28))),
                    IndexedSavedPage(
                        page: SavedPage(
                            pageTitle: "Coffee brewing temperature guide", pageURL: URL(string: "https://baristahustle.com")!,
                            recordedAt: .now.addingTimeInterval(-86400 * 2))),
                ]
            }
        #endif
        return rankedHistory
    }

    var body: some View {
        ZStack {
            Palette.canvasView.ignoresSafeArea()
            VStack(spacing: 0) {
                sheetHeader
                if privateSearch {
                    VStack(spacing: 0) {
                        Spacer(minLength: 24)
                        privateCard
                            .padding(.horizontal, 20)
                        Spacer(minLength: 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { queryFocused = false }
                } else if draftText.isEmpty {
                    VStack(spacing: 0) {
                        Spacer(minLength: 24)
                        zeroResultsPane
                        Spacer(minLength: 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { queryFocused = false }
                } else {
                    suggestionsList
                }
                queryDeck
                    .padding(.horizontal, 20)
                    .padding(.bottom, 11)
                    .zIndex(2)
                accessoryPills
                    .padding(.horizontal, 20)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                    .zIndex(2)
            }
        }
        .task {
            #if DEBUG
                if vault.launchScenario == "search", draftText.isEmpty {
                    draftText = "how to brew coffee"
                }
            #endif
            privateSearch = vault.incognito || vault.launchScenario == "private"
            if privateSearch, !vault.incognito { vault.toggleIncognito(true) }
            rebuildIndex()
            refreshHistoryMatches(draftText)
            refreshSuggestions(draftText)
            if vault.launchScenario != nil {
                queryFocused = true
            } else {
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled else { return }
                queryFocused = true
            }
        }
        .onChange(of: draftText) { _, newValue in
            scheduleHistoryRefresh(newValue)
            refreshSuggestions(newValue)
        }
        // keep derived state in sync
        .onChange(of: vault.visitLedger) { _, _ in scheduleIndexRebuild() }
        .onChange(of: vault.pinnedPages) { _, _ in scheduleIndexRebuild() }
        // cleanup
        .onDisappear {
            suggestTask?.cancel()
            historyTask?.cancel()
            indexTask?.cancel()
            VoiceDictation.shared.stop()
        }
    }

    // sheet header
    private var sheetHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: dismissAddressSheet) {
                    Image(systemName: "chevron.down")
                        .font(.ui(15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(Palette.raisedFill, in: Circle())
                        .padding(6)
                }
                .buttonStyle(SearchTapStyle())
                .padding(-6)
                .accessibilityLabel("Collapse search")
                Spacer()
                Text("Search")
                    .font(.ui(17, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Helpers
extension AddressSearchView {
    // Closes the sheet and drops the keyboard.
    private func dismissAddressSheet() {
        suggestTask?.cancel()
        VoiceDictation.shared.stop()
        queryFocused = false
        if vault.modalLane == .search {
            vault.modalLane = nil
        } else {
            dismissSheet()
        }
    }

    // layout for accessory pills
    private var accessoryPills: some View {
        HStack(spacing: 0) {
            Button(action: pasteAndGo) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.ui(12, weight: .regular))
                    Text("Paste and go")
                        .font(.ui(12, weight: .regular))
                }
                .foregroundStyle(.white)
                .padding(.leading, 10)
                .padding(.trailing, 12)
                .frame(height: 26)
                // background goes behind everything
                .background(Palette.brandInk, in: Capsule())
                .padding(.vertical, 4)
            }
            .buttonStyle(SearchTapStyle())
            Spacer(minLength: 8)
            Button {
                privateSearch.toggle()
                if privateSearch {
                    vault.toggleIncognito(true)
                    remoteSuggestions = []
                    rankedHistory = []
                } else {
                    if vault.incognito { vault.toggleIncognito(false) }
                    refreshHistoryMatches(draftText)
                    refreshSuggestions(draftText)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.ui(11, weight: .regular))
                    Text("Private")
                        .font(.ui(12, weight: .regular))
                }
                .foregroundStyle(privateSearch ? Color.white : Palette.mutedLabel)
                .padding(.leading, 11.5)
                .padding(.trailing, 12)
                .frame(height: 26)
                .background(privateSearch ? Color.black : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                .padding(.vertical, 4)
            }
            .buttonStyle(SearchTapStyle())
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
    }

    private var zeroResultsPane: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Palette.brandWash).frame(width: 64, height: 64)
                Image(systemName: "magnifyingglass")
                    .font(.ui(28, weight: .regular))
                    .foregroundStyle(Palette.brandInk)
            }
            Text(ask ? "Ask AI anything" : "Start typing")
                .font(.ui(20, weight: .semibold))
                .padding(.top, 18)
            Text(ask ? "Type a question below to start a chat with AI." : "Suggestions and pages you visited will show up here.")
                .font(.ui(15))
                .foregroundStyle(Palette.mutedLabel)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
    }

    // private card row
    private var privateCard: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Color.black).frame(width: 44, height: 44)
                Image(systemName: "hand.raised.fill")
                    .font(.ui(20))
                    .foregroundStyle(.white)
            }
            Text("Private search")
                .font(.ui(17, weight: .semibold))
                .padding(.top, 14)
            Text("This search won’t be saved to history, and the page won’t be sent to AI.")
                .font(.ui(15))
                .foregroundStyle(Palette.mutedLabel)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.horizontal, 8)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        // background fill
        .background(Palette.raisedFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
    }

    // Section header
    private func sectionHeader(_ headingText: String) -> some View {
        Text(headingText)
            .font(.ui(13)).browsExactLineHeight(18)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 15).padding(.bottom, 5)
    }

    // row icon
    private func rowIcon(_ iconName: String) -> some View {
        Image(systemName: iconName).font(.ui(15)).foregroundStyle(.primary).frame(width: 20, height: 20)
    }

    // suggestions list (view)
    private var suggestionsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                sectionHeader(ask ? "Ask" : "Google Suggestions")
                Button(action: submit) {
                    HStack(spacing: 8) {
                        rowIcon(ask ? "sparkle" : "magnifyingglass")
                        Text(ask ? "Ask: \(draftText)" : draftText)
                            .font(.ui(17))
                            .browsExactLineHeight(22)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20).frame(height: 46)
                }
                .buttonStyle(SearchTapStyle())
                if !ask {
                    ForEach(suggestionRows) { row in
                        Button {
                            draftText = row.fullText
                            submit()
                        } label: {
                            HStack(spacing: 8) {
                                rowIcon("magnifyingglass")
                                Text(row.attributedLabel)
                                    .font(.ui(17))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 20).frame(height: 46)
                        }
                        .buttonStyle(SearchTapStyle())
                    }
                }
                if !shelfHits.isEmpty { sectionHeader("Bookmarks and History") }
                ForEach(shelfHits) { item in
                    Button {
                        suggestTask?.cancel()
                        vault.navigateInput(item.urlString)
                    } label: {
                        HStack(spacing: 8) {
                            rowIcon("clock")
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.headingText)
                                    .font(.ui(17))
                                    .browsExactLineHeight(22)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(item.subtitle)
                                    .font(.ui(12))
                                    .browsExactLineHeight(16)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .offset(y: 0.5)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 20).frame(height: 57)
                    }
                    .buttonStyle(SearchTapStyle())
                }
                .offset(y: -0.8)
            }
            .offset(x: 0.3, y: 0.3)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // query deck (view)
    private var queryDeck: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                TextField(ask ? "Ask anything…" : "Search or enter address", text: $draftText)
                    .font(.ui(17))
                    .foregroundStyle(.primary)
                    .keyboardType(ask ? .default : .URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($queryFocused)
                    .submitLabel(.return)
                    .tint(Palette.brandInk)
                    .onSubmit(submit)
                    .frame(maxWidth: .infinity, minHeight: 34)

                VoiceInputButton(
                    draftText: $draftText,
                    onPrepare: { queryFocused = false },
                    onError: { vault.bannerText = $0 }
                )

                if !draftText.isEmpty {
                    Button {
                        draftText = ""
                        queryFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.ui(17))
                            .foregroundStyle(
                                interfaceScheme == .dark ? Color.white.opacity(0.7) : Palette.rgb(0x3C3C43).opacity(0.30)
                            )
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(SearchTapStyle())
                    .accessibilityLabel("Clear text")
                }
            }
            .frame(height: 36)

            HStack(spacing: 6) {
                modeChips
                Spacer(minLength: 4)
                Button(action: openPhotoSearch) {
                    Image(systemName: "camera.viewfinder")
                        .font(.ui(17, weight: .regular))
                        .foregroundStyle(Palette.brandInk)
                        .frame(width: 34, height: 34)
                        .background(Palette.brandWash, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .padding(4)
                }
                .buttonStyle(SearchTapStyle())
                .accessibilityLabel("Search by photo")
                .accessibilityIdentifier("address.camera")

                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.ui(15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        // background goes behind everything
                        .background(Palette.brandInk, in: Circle())
                        .padding(4)
                }
                .buttonStyle(SearchTapStyle())
                .accessibilityIdentifier("address.send")
            }
            .frame(height: 42)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(interfaceScheme == .dark ? Color(white: 0.14) : Color.white)
                .shadow(color: Color.black.opacity(interfaceScheme == .dark ? 0.28 : 0.08), radius: 18, y: 6)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(
                            interfaceScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06),
                            lineWidth: 0.5
                        )
                }
        }
    }

    // Mode chips row
    private var modeChips: some View {
        HStack(spacing: 2) {
            modeChip(headingText: "Search", iconName: "magnifyingglass", selected: !ask) {
                ask = false
                refreshSuggestions(draftText)
            }
            modeChip(headingText: "Ask", iconName: "bubble.left", selected: ask) {
                ask = true
                remoteSuggestions = []
            }
        }
        .padding(3)
        // background goes behind everything
        .background(modeTrack, in: Capsule())
    }

    private var modeTrack: Color {
        interfaceScheme == .dark ? Color.white.opacity(0.10) : Palette.rgb(0xEEF2F0)
    }

    // mode chip
    private func modeChip(headingText: String, iconName: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.ui(11, weight: .regular))
                Text(headingText)
                    .font(.ui(12, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(
                selected
                    ? selectedModeLabel
                    : (interfaceScheme == .dark ? Color.white.opacity(0.55) : Palette.rgb(0x3C3C43).opacity(0.55))
            )
            .padding(.leading, 11)
            .padding(.trailing, 13)
            .frame(height: 30)
            // background goes behind everything
            .background(selected ? selectedModeFill : Color.clear, in: Capsule())
            .shadow(color: selected && interfaceScheme != .dark ? Color.black.opacity(0.06) : .clear, radius: 2, y: 1)
        }
        .buttonStyle(SearchTapStyle())
    }

    private var selectedModeFill: Color {
        interfaceScheme == .dark ? Color.white.opacity(0.18) : .white
    }

    private var selectedModeLabel: Color {
        interfaceScheme == .dark ? .white : .black
    }

    // Opens the photo search
    private func openPhotoSearch() {
        suggestTask?.cancel()
        VoiceDictation.shared.stop()
        queryFocused = false
        vault.enqueueModal(to: .camera)
    }

    // Clipboard → address bar in one tap.
    private func pasteAndGo() {
        guard let string = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            vault.bannerText = "Clipboard is empty."
            return
        }
        draftText = string
        ask = false
        submit()
    }

    // Return key / Go.
    private func submit() {
        let query = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            queryFocused = true
            return
        }
        suggestTask?.cancel()
        VoiceDictation.shared.stop()
        queryFocused = false
        if ask {
            guard !privateSearch, !vault.incognito else {
                vault.bannerText = "AI is off in private tabs."
                return
            }
            vault.chromePane = 1
            vault.composerDraft = query
            vault.modalLane = nil
        } else {
            queryFocused = false
            vault.navigateInput(query)
        }
    }

    // Debounced so typing does not hammer the history search.
    private func scheduleHistoryRefresh(_ raw: String) {
        historyTask?.cancel()
        historyTask = Task {
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled else { return }
            refreshHistoryMatches(raw)
        }
    }

    private func scheduleIndexRebuild() {
        indexTask?.cancel()
        indexTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            rebuildIndex()
            refreshHistoryMatches(draftText)
        }
    }

    // Lower-cased copy of saved pages for quick matching.
    private func rebuildIndex() {
        var seen = Set<String>()
        var combined: [IndexedSavedPage] = []
        combined.reserveCapacity(min(vault.pinnedPages.count + vault.visitLedger.count, 300))
        for page in vault.pinnedPages + vault.visitLedger {
            let key = page.pageURL.absoluteString
            guard seen.insert(key).inserted else { continue }
            combined.append(IndexedSavedPage(page: page))
            if combined.count >= 300 { break }
        }
        indexedPages = combined
    }

    // Asks Google for completions, with a small cache.
    private func refreshSuggestions(_ raw: String) {
        suggestTask?.cancel()
        #if DEBUG
            if vault.launchScenario == "search" { return }
        #endif
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !privateSearch, !ask else {
            if !remoteSuggestions.isEmpty { remoteSuggestions = [] }
            return
        }
        suggestTask = Task {
            if let cached = await GoogleSuggestions.shared.cached(for: query) {
                guard !Task.isCancelled else { return }
                remoteSuggestions = cached
                return
            }
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            let rowBatch = await GoogleSuggestions.shared.fetch(query)
            guard !Task.isCancelled else { return }
            remoteSuggestions = rowBatch
        }
    }

    private func refreshHistoryMatches(_ raw: String) {
        #if DEBUG
            if vault.launchScenario == "search" { return }
        #endif
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty, !privateSearch else {
            if !rankedHistory.isEmpty { rankedHistory = [] }
            return
        }
        var results: [IndexedSavedPage] = []
        results.reserveCapacity(8)
        for entry in indexedPages {
            if entry.lowercasedTitle.contains(query) || entry.lowercasedURL.contains(query) {
                results.append(entry)
                if results.count >= 8 { break }
            }
        }
        rankedHistory = results
    }
}
