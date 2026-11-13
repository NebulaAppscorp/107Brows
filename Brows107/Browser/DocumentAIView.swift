//    
//  DocumentAIView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 03/11/26.
//

import SwiftUI

struct DocumentAIView: View {
    // whole text of the PDF, used when the question is about the document
    let fullDocumentText: String
    // only the page that is on screen
    let pageText: String
    @Environment(BrowserStore.self) private var vault
    @Environment(\.dismiss) private var dismissSheet
    // answer state
    @State private var documentAnswer: String?
    @State private var pdfPromptDraft = ""
    // true while a request is running
    @State private var busy = false
    @State private var documentAIWork: Task<Void, Never>?
    // one remote thread id per sheet, so follow-ups stay together    
    @State private var threadRemoteID = UUID().uuidString


    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        Text("Ask about this document").font(.title3.weight(.semibold))
                        Text("Only readable text is processed when you ask.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if busy {  
                        HStack {
                            ProgressView()
                            Text("Reading the document…")
                            Spacer()
                            Button("Stop") {
                                documentAIWork?.cancel()
                                busy = false
                            }
                        }
                    }
                    // handle document answer if it is there
                    if let documentAnswer {
                        Section {
                            Text(documentAnswer).textSelection(.enabled)
                            ShareLink(item: documentAnswer)
                        }
                    } else {
                        ForEach(["Summarize document", "Key points", "Explain this page"], id: \.self) { headingText in
                            Button(headingText) { runDocumentAIPrompt(headingText) }.disabled(busy)
                        }
                    }
                }
                HStack {
                    TextField("Ask about the PDF", text: $pdfPromptDraft, axis: .vertical).lineLimit(1...4)
                    Button("Send", systemImage: "arrow.up") { runDocumentAIPrompt(pdfPromptDraft) }.labelStyle(.iconOnly)
                        .browsGlassProminentButtonStyle().disabled(
                            busy || pdfPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding().browsGlassCapsule().padding() 
            }
            .navigationTitle("Ask PDF").navigationBarTitleDisplayMode(.inline)
            .browsLiquidNavBar()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismissSheet() } } }
            .onDisappear { documentAIWork?.cancel() }
        }.presentationDetents([.medium, .large])
    }
}

// MARK: Helpers
extension DocumentAIView {
    // Runs document ai prompt
    private func runDocumentAIPrompt(_ prompt: String) {
        guard !vault.incognito, !busy else { return }
        let sourceText = prompt == "Explain this page" ? pageText : fullDocumentText
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.vault.bannerText = "This PDF has no selectable text (scanned?)."
            return
        }
        busy = true
        documentAIWork = Task {
            defer { if !Task.isCancelled { busy = false } }
            guard await vault.requireServerSubscription(), !Task.isCancelled else {
                dismissSheet()
                return
            }
            do {
                if vault.launchScenario != nil {
                    // Wait for it before moving on
                    try await Task.sleep(for: .milliseconds(650))
                    documentAnswer = SampleContent.fixtureSummaryBullets.map { $0.0 + "\n" + $0.1 }.joined(separator: "\n\n")
                } else {
                    // Suspends here until the result is back
                    let plainTextSourceID = try await vault.aiService.preparePlainText(sourceText)
                    // Async hop, keep the work above it cheap
                    let relayPayload = try await vault.aiService.relayChat(
                        remoteChatID: threadRemoteID, promptText: prompt, photoJPEG: nil, sourceIDs: [plainTextSourceID],
                        webLookupEnabled: false, think: vault.deepThink)
                    try Task.checkCancellation()
                    documentAnswer = relayPayload.assistantBody
                    self.threadRemoteID = relayPayload.remoteChatID
                }
                try Task.checkCancellation()
                self.pdfPromptDraft = ""
            } catch is CancellationError {} catch { if !Task.isCancelled { vault.bannerText = error.localizedDescription } }
        }
    }
}
