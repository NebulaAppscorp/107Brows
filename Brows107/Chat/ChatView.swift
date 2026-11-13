//
//  ChatView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 30/10/26.
//

import SwiftUI
import PhotosUI
import AVFoundation

/// Chat tab: composer, mode toggles and the thread.
struct ChatView: View {
    @Environment(BrowserStore.self) private var vault
    @Environment(\.colorScheme) private var interfaceScheme
    @State private var galleryAttachToken: PhotosPickerItem?
    @State private var chatPromptIdeas = [
        "Summarize a link I paste", "Find where this photo is from", "Explain a topic step by step",
    ]
    @FocusState private var composerFocused: Bool
    var body: some View {
        @Bindable var vault = vault
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 13) {
                        // Optional active thread, may be missing
                        if let activeThread = vault.currentThread, !activeThread.threadTurns.isEmpty {
                            ForEach(activeThread.threadTurns) { turn in
                                ChatBubble(turn: turn)
                            }
                            if vault.assistantBusy {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text(vault.webLookup ? "Searching the web…" : "Thinking…")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                                .accessibilityIdentifier("chat.generating")
                            }
                        } else {
                            emptyConversation
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(.horizontal, 20).padding(.top, vault.currentThread?.threadTurns.isEmpty == false ? 10.5 : 0).frame(
                        maxWidth: 700
                    ).frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.immediately)
                .browsScrollEdgeEffectHidden()
                .simultaneousGesture(TapGesture().onEnded { composerFocused = false })
                // keep derived state in sync
                .onChange(of: vault.currentThread?.threadTurns.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                // follow the value, not the action
                .onChange(of: vault.assistantBusy) { _, isBusy in
                    if isBusy { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                }
            }
            inputDeck
                // Spacing from the design
                .padding(.horizontal, 12)
                // breathing room
                .padding(.bottom, Self.keyboardGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // background goes behind everything
        .background {
            ClearHostBackdrop().ignoresSafeArea()
        }
        .overlay(alignment: .bottomLeading) {
            if vault.modalLane == .models {
                ModelPickerView()
                    .padding(.leading, 20).padding(.bottom, 142)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(.smooth(duration: 0.24), value: vault.modalLane == .models)
        .onChange(of: galleryAttachToken) { _, item in
            Task {
                var transferBlob: Data?
                do {
                    transferBlob = try await item?.loadTransferable(type: Data.self)
                } catch {
                    print("gallery attach failed: \(error)")
                }
                if let transferBlob,
                    let pickedBitmap = UIImage(data: transferBlob)
                {
                    vault.attachedPhoto = pickedBitmap
                }
            }
        }
    }

    // keeps keyboard gap
    private static let keyboardGap: CGFloat = 4

    // empty conversation row
    private var emptyConversation: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandMark(assetName: "chat_mark", markSide: 52)
            Text("How can I help?").font(.ui(28)).browsExactLineHeight(34).foregroundStyle(.primary).padding(.top, 18)
            Text("Ask anything, or start from a suggestion below.").font(.ui(15)).browsExactLineHeight(20)
                .foregroundStyle(.secondary).padding(.top, 6)
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // rows are keyed by id so animations stay stable
                    ForEach(chatPromptIdeas, id: \.self) { suggestion in
                        // tap handler below
                        Button {
                            vault.composerDraft = suggestion
                            DispatchQueue.main.async { composerFocused = true }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: promptIdeaIcon(for: suggestion)).font(.ui(15)).foregroundStyle(
                                    Palette.brandInk
                                ).frame(width: 28, height: 28)
                                Text(suggestion).font(.ui(16)).foregroundStyle(.primary).lineLimit(1)
                                Spacer(minLength: 0)
                            }.padding(.horizontal, 16).frame(height: 54).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if suggestion != chatPromptIdeas.last {
                            Rectangle().fill(Color(uiColor: .separator)).frame(height: 1).padding(.leading, 52)
                        }
                    }
                }
                .frame(width: geometry.size.width + 40, height: geometry.size.height)
                // background goes behind everything
                .background(Palette.canvasView, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .offset(x: -20)    
            }
            .frame(height: 164)
            // breathing room 
            .padding(.top, 24)
            // Plain button, styling comes from the modifiers
            Button {
                shufflePromptIdeas()
            } label: {
                Label("Shuffle suggestions", systemImage: "shuffle").font(.ui(13)).foregroundStyle(
                    Color(uiColor: .secondaryLabel))
            }.padding(.top, 14)
        }.padding(.top, 40)
    }

    // input deck row
    private var inputDeck: some View {
        @Bindable var vault = vault
        return VStack(spacing: 0) { 
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if vault.currentThread?.threadTurns.contains(where: { !$0.fromVisitor }) == true {
                        // plain button, styling comes from the modifiers
                        Button {
                            vault.modalLane = .models
                        } label: {
                            HStack(spacing: 8) { 
                                Image(systemName: "chevron.down")
                                    .font(.ui(15, weight: .regular))
                                    .foregroundStyle(Palette.brandInk)
                                Text(vault.assistantModel)
                                    .font(.ui(15))
                                    .tracking(-0.23)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            // Breathing room
                            .padding(.leading, 14)
                            .padding(.trailing, 16)
                            // Fixed size from the design
                            .frame(height: 40)
                            .background(Palette.composerChip, in: Capsule())
                            .shadow(color: Palette.rgb(0x002417).opacity(interfaceScheme == .dark ? 0 : 0.1), radius: 3, y: 2)
                            .shadow(color: Palette.rgb(0x002417).opacity(interfaceScheme == .dark ? 0 : 0.06), radius: 9, y: 8) 
                        }
                        .buttonStyle(.plain)
                    }
                    modeToggle(headingText: "Web search", iconName: "globe", active: vault.webLookup) { vault.webLookup.toggle() }
                    modeToggle(headingText: "Think", iconName: "lightbulb", active: vault.deepThink) { vault.deepThink.toggle() }
                }
                .background(Color.clear)
            }
            .frame(height: 40)
            .scrollContentBackground(.hidden)
            // background goes behind everything
            .background(Color.clear)
            if let attachedBitmap = vault.attachedPhoto {
                HStack {  
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: attachedBitmap)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Button {
                            vault.attachedPhoto = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.ui(10, weight: .bold))
                                .foregroundStyle(.white)
                                // fixed size from the design
                                .frame(width: 18, height: 18)
                                .background(Color.black.opacity(0.55), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .accessibilityLabel("Remove photo")
                    }
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
                // breathing room
                .padding(.top, 12)
            }
            HStack(alignment: .bottom, spacing: 12) {
                PhotosPicker(selection: $galleryAttachToken, matching: .images) {
                    Image(systemName: "plus.circle")
                        .font(.ui(20, weight: .regular))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        // fixed size from the design
                        .frame(width: 24, height: 34)
                }
                TextField("Message", text: $vault.composerDraft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.ui(17))
                    .foregroundStyle(.primary)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { vault.submitComposer() }
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("chat.input")
                Button("Send", systemImage: "arrow.up") {
                    vault.submitComposer()
                    composerFocused = false
                }.labelStyle(.iconOnly).browsGlassProminentButtonStyle().buttonBorderShape(.circle).tint(Palette.brandInk)
                    .disabled(
                        vault.assistantBusy
                            || (vault.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                && vault.attachedPhoto == nil)
                    ).accessibilityIdentifier("chat.send")
            }
            .padding(6)
            // Breathing room
            .padding(.leading, 8)    
            .background(Palette.canvasView, in: Capsule())
            .overlay(Capsule().stroke(Palette.brandInk.opacity(interfaceScheme == .dark ? 0.28 : 0.18)))
            .frame(height: 46)
            // Spacing from the design
            .padding(.top, 12)
            Spacer(minLength: 8).frame(height: 8)
            Text("AI can make mistakes. Check important details.").font(.ui(11)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)    
        // Breathing room
        .padding(.bottom, 10)
        .background(Color.clear)
    }
}

// MARK: Helpers
extension ChatView {
    @ViewBuilder
    private func modeToggle(headingText: String, iconName: String, active: Bool, action: @escaping () -> Void) -> some View {
        // work out the button
        let button = Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.ui(15, weight: .regular))
                    .foregroundStyle(active ? Palette.brandInk : Color(uiColor: .secondaryLabel))
                Text(headingText)
                    .font(.ui(15, weight: active ? .medium : .regular))
                    .tracking(-0.23)
                    .foregroundStyle(active ? Palette.brandInk : Color(uiColor: .secondaryLabel))
                    .lineLimit(1)
            }
            // Breathing room
            .padding(.leading, 14)
            // breathing room
            .padding(.trailing, 16)
            .frame(height: 40)
            .fixedSize(horizontal: true, vertical: false)
            .background(Palette.canvasView, in: Capsule())
            .shadow(color: (interfaceScheme == .dark ? Color.white : Color.black).opacity(0.08), radius: 3, y: 1)
        }
        if headingText == "Think" {
            button.buttonStyle(.plain).contextMenu {
                Button("Choose AI model", systemImage: "sparkles") { vault.modalLane = .models }
            }
        } else {
            button.buttonStyle(.plain)
        }
    }
    // Picks a new set of starter prompts.
    private func shufflePromptIdeas() {
        var nextOrder = chatPromptIdeas.shuffled()
        if nextOrder == chatPromptIdeas, nextOrder.count > 1 {
            nextOrder.append(nextOrder.removeFirst())
        }
        withAnimation(.snappy(duration: 0.2)) { chatPromptIdeas = nextOrder } 
    }


    private func promptIdeaIcon(for suggestion: String) -> String {
        // map the state to what we show
        switch suggestion {
        case "Summarize a link I paste": "link"
        case "Find where this photo is from": "photo.on.rectangle"
        default: "book"
        }
    }
}


/// Turns markdown-ish answers into plain text for copy / share.
enum ChatAnswerText {
    // Plain
    static func plain(_ draftText: String) -> String {
        var slot = draftText
        let patterns = [
            #"\[[^\]]*\]\s*\(https?://[^)]*\)"#,
            #"https?://\S+"#,
            #"\(\s*Source:[^)]*\)"#,
            #"\(\s*\)"#,
        ]
        // one pass over the pattern items
        for pattern in patterns {
            // need expression to go on
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            slot = expression.stringByReplacingMatches(in: slot, range: NSRange(slot.startIndex..., in: slot), withTemplate: "")
        }
        slot = slot.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        slot = slot.replacingOccurrences(of: " +([.,;:!?])", with: "$1", options: .regularExpression)
        slot = slot.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return slot.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Message bubble with actions under assistant replies.  
struct ChatBubble: View {
    // current turn
    let turn: ChatMessage
    @Environment(BrowserStore.self) private var vault
    @State private var expanded = false
    @State private var liked = false
    @State private var feedbackPresented = false
    @StateObject private var speech = NativeSpeechPlayer()
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if turn.fromVisitor {
                HStack {
                    Spacer(minLength: 40)
                    VStack(alignment: .trailing, spacing: 8) {
                        if let payloadBytes = turn.inlinePhotoBytes, let inlineBitmap = UIImage(data: payloadBytes) {
                            Image(uiImage: inlineBitmap).resizable().scaledToFit().frame(maxWidth: 220, maxHeight: 220).clipShape(
                                RoundedRectangle(cornerRadius: 16))
                        }
                        if !turn.messageBody.isEmpty {
                            Text(turn.messageBody)
                                .font(.ui(17))
                                .foregroundStyle(Palette.visitorInk)
                                .padding(.horizontal, 16)
                                // spacing from the design
                                .padding(.vertical, 12)
                                .background(Palette.brandWash, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                // spacing from the design
                                .padding(.trailing, 0.7)
                        }
                    }
                }
            } else {
                if !turn.citationPages.isEmpty {
                    Button {
                        self.expanded.toggle()
                    } label: {
                        HStack(spacing: 6) { 
                            Image(systemName: "link").foregroundStyle(Color(uiColor: .tertiaryLabel))
                            Text("Referenced \(turn.citationPages.count) sources").foregroundStyle(
                                Color(uiColor: .secondaryLabel))
                            Image(systemName: "chevron.down")
                                .font(.ui(11))
                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                        }
                        .font(.ui(12)) 
                    }
                    .buttonStyle(.plain)
                    // fixed size from the design
                    .frame(height: 20, alignment: .leading)
                    if expanded {
                        VStack(spacing: 0) {
                            // Rows are keyed by id so animations stay stable
                            ForEach(Array(turn.citationPages.enumerated()), id: \.element.id) { index, source in
                                if index > 0 {
                                    Rectangle().fill(Color(uiColor: .separator)).frame(height: 1).padding(.leading, 46)
                                }
                                // plain button, styling comes from the modifiers
                                Button {
                                    vault.navigateInput(source.pageURL.absoluteString)
                                } label: {
                                    HStack(spacing: 10) {
                                        Text("\(index + 1)")
                                            .font(.ui(11, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .frame(width: 22, height: 22)
                                            .background(Palette.brandInk, in: RoundedRectangle(cornerRadius: 6))
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(source.pageTitle).font(.ui(15)).tracking(-0.23).foregroundStyle(
                                                .primary
                                            ).lineLimit(2)
                                            Text(source.pageURL.host ?? "").font(.ui(12)).foregroundStyle(
                                                Color(uiColor: .secondaryLabel)
                                            ).lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 14)
                                    // Fixed size from the design
                                    .frame(height: 59)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        // spacing from the design
                        .padding(.top, 8)
                    }
                    Spacer().frame(height: 10)
                }
                Text(ChatAnswerText.plain(turn.messageBody))
                    .font(.ui(17))
                    .browsExactLineHeight(22)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .contextMenu {
                        Button(liked ? "Liked" : "Helpful", systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup") {
                            self.liked.toggle()
                        }
                        .tint(liked ? Palette.brandInk : nil)
                        Button("Report answer", systemImage: "hand.thumbsdown") { feedbackPresented = true }
                    }
                if !turn.citationPages.isEmpty {
                    Spacer().frame(height: 8)
                    HStack(spacing: 4) {
                        // rows are keyed by id so animations stay stable
                        ForEach(Array(turn.citationPages.prefix(3).enumerated()), id: \.offset) { index, citationPage in
                            // tap handler below
                            Button {
                                vault.navigateInput(citationPage.pageURL.absoluteString)
                            } label: {
                                Text("\(index + 1)")
                                    .font(.ui(11))
                                    .foregroundStyle(Palette.brandInk)
                                    // Breathing room
                                    .padding(.horizontal, 5)
                                    .frame(height: 15)
                                    // background fill
                                    .background(Palette.brandWash, in: RoundedRectangle(cornerRadius: 5))
                            }    
                            .buttonStyle(.plain)
                            .accessibilityLabel("Source \(index + 1): \(citationPage.pageTitle)")
                        }
                    }
                }
                Spacer().frame(height: 14)
                HStack(spacing: 8) {
                    actionButton(
                        speech.isSpeaking ? "Stop speaking" : "Read aloud",
                        iconName: speech.isSpeaking ? "stop.fill" : "speaker.wave.2"
                    ) {
                        self.speech.toggle(ChatAnswerText.plain(turn.messageBody))  
                    }
                    ShareLink(item: ChatAnswerText.plain(turn.messageBody)) {
                        actionIcon("Share", iconName: "square.and.arrow.up")
                    }
                    Button("Copy", systemImage: "doc.on.doc") {
                        vault.copyTextToPasteboard(ChatAnswerText.plain(turn.messageBody))
                    }
                    .labelStyle(.iconOnly)
                    .font(.ui(14))
                    // size matches the mock
                    .frame(width: 36, height: 36)
                    .background(Palette.raisedFill, in: Circle())
                    actionButton("Regenerate", iconName: "arrow.clockwise") { vault.regenerateAssistant() }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
        }
        .padding(.vertical, turn.fromVisitor ? 6 : 0)
        .sheet(isPresented: $feedbackPresented) { FeedbackView() }
        // cleanup
        .onDisappear { speech.stop() }
    }
}


// MARK: - Helpers
extension ChatBubble {
    // Action button
    private func actionButton(_ headingText: String, iconName: String, action: @escaping () -> Void) -> some View {
        // plain button, styling comes from the modifiers
        Button(headingText, systemImage: iconName, action: action)
            .labelStyle(.iconOnly)
            .font(.ui(14))
            .foregroundStyle(Color(uiColor: .secondaryLabel))
            .frame(width: 36, height: 36)
            .background(Palette.raisedFill, in: Circle())
    }

    // action icon
    private func actionIcon(_ headingText: String, iconName: String) -> some View {
        Image(systemName: iconName)
            .font(.ui(14))
            .foregroundStyle(Color(uiColor: .secondaryLabel))
            .frame(width: 36, height: 36)
            .background(Palette.raisedFill, in: Circle())
            .accessibilityLabel(headingText)
    }
}

@MainActor
final class NativeSpeechPlayer: NSObject, ObservableObject, @preconcurrency AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // Flips it
    func toggle(_ text: String) {
        if isSpeaking {
            stop()
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        let hasCyrillic = text.unicodeScalars.contains { (0x0400...0x052F).contains($0.value) }
        let language = hasCyrillic ? "ru-RU" : (Locale.preferredLanguages.first ?? Locale.current.identifier)
        utterance.voice = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        synthesizer.speak(utterance)
    } 


    // stops it
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // speech synthesizer
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isSpeaking = false }
    }

    // speech synthesizer  
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isSpeaking = false }
    }
}
