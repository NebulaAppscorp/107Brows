import SwiftUI
import StoreKit

struct DocumentAIView: View {
    let fullDocumentText: String
    let pageText: String
    @Environment(BrowserStore.self) private var vault
    @Environment(\.dismiss) private var dismissSheet
    @Environment(\.requestReview) private var requestStoreReview
    @State private var documentAnswer: String?
    @State private var pdfPromptDraft = ""
    @State private var busy = false
    @State private var documentAIWork: Task<Void, Never>?
    @State private var threadRemoteID = UUID().uuidString

    private let promptActions = ["Summarize document", "Key points", "Explain this page"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    introductionCard

                    if busy {
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(Palette.brandInk)
                            Text("Reading the document…")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Stop") {
                                documentAIWork?.cancel()
                                busy = false
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.brandInk)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.canvasView, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }

                    if let documentAnswer {
                        answerCard(documentAnswer)
                    } else {
                        promptActionsCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 16)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Palette.groupedFill.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composerIsland
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }
            .navigationTitle("Ask PDF")
            .navigationBarTitleDisplayMode(.inline)
            .browsLiquidNavBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismissSheet() }
                }
            }
            .onDisappear { documentAIWork?.cancel() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var introductionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask about this document")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.6))
                .frame(height: 1)
            Text("Only readable text is processed when you ask.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.canvasView, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var promptActionsCard: some View {
        VStack(spacing: 0) {
            ForEach(promptActions.indices, id: \.self) { index in
                let title = promptActions[index]
                Button {
                    runDocumentAIPrompt(title)
                } label: {
                    HStack(spacing: 12) {
                        Text(title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Palette.brandInk)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.brandInk.opacity(0.7))
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 18)
                    .frame(minHeight: 52)
                }
                .buttonStyle(.plain)
                .disabled(busy)

                if index < promptActions.count - 1 {
                    Rectangle()
                        .fill(Color(uiColor: .separator).opacity(0.55))
                        .frame(height: 1)
                        .padding(.leading, 18)
                }
            }
        }
        .background(Palette.canvasView, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func answerCard(_ answer: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(answer)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            ShareLink(item: answer) {
                Label("Share answer", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.brandInk)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.canvasView, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var composerIsland: some View {
        HStack(spacing: 10) {
            TextField("Ask about the PDF", text: $pdfPromptDraft, axis: .vertical)
                .lineLimit(1...3)
                .font(.body)
                .submitLabel(.send)
                .onSubmit { sendDraft() }
                .padding(.leading, 8)

            Button {
                sendDraft()
            } label: {
                Image(systemName: busy ? "stop.fill" : "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Palette.brandInk, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!busy && pdfPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(!busy && pdfPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.48 : 1)
            .accessibilityLabel(busy ? "Stop generating" : "Send question")
        }
        .padding(.leading, 16)
        .padding(.trailing, 7)
        .frame(minHeight: 58)
        .browsGlassCapsule()
        .overlay(Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.09), radius: 12, x: 0, y: 5)
    }

    private func sendDraft() {
        if busy {
            documentAIWork?.cancel()
            busy = false
            return
        }
        let prompt = pdfPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        runDocumentAIPrompt(prompt)
    }

    private func runDocumentAIPrompt(_ prompt: String) {
        guard !vault.incognito, !busy else { return }
        let sourceText = prompt == "Explain this page" ? pageText : fullDocumentText
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            vault.bannerText = "This PDF has no selectable text (scanned?)."
            return
        }
        busy = true
        documentAIWork = Task {
            defer { if !Task.isCancelled { busy = false } }
            guard await vault.requireServerSubscription(), !Task.isCancelled else { return }
            do {
                if vault.launchScenario != nil {
                    try await Task.sleep(for: .milliseconds(650))
                    documentAnswer = SampleContent.fixtureSummaryBullets.map { $0.0 + "\n" + $0.1 }.joined(separator: "\n\n")
                } else {
                    let plainTextSourceID = try await vault.aiService.preparePlainText(sourceText)
                    let relayPayload = try await vault.aiService.relayChat(
                        remoteChatID: threadRemoteID,
                        promptText: prompt,
                        photoJPEG: nil,
                        sourceIDs: [plainTextSourceID],
                        webLookupEnabled: false,
                        think: vault.deepThink
                    )
                    try Task.checkCancellation()
                    documentAnswer = relayPayload.assistantBody
                    threadRemoteID = relayPayload.remoteChatID
                }
                try Task.checkCancellation()
                pdfPromptDraft = ""
                requestStoreReview()
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { vault.bannerText = error.localizedDescription }
            }
        }
    }
}
