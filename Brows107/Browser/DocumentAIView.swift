import SwiftUI
import StoreKit

struct DocumentAIView: View {
    let fullDocumentText: String
    let pageText: String
    let documentTitle: String
    let pageCount: Int
    @Environment(BrowserStore.self) private var vault
    @Environment(\.dismiss) private var dismissSheet
    @Environment(\.requestReview) private var requestStoreReview
    @State private var documentAnswer: String?
    @State private var pdfPromptDraft = ""
    @State private var busy = false
    @State private var documentAIWork: Task<Void, Never>?
    @State private var threadRemoteID = UUID().uuidString
    @State private var selectedDetent: PresentationDetent = .height(465)
    @State private var currentAnswerTitle = "Summary"
    @FocusState private var promptFocused: Bool

    private let promptActions = [
        ("Summarize document", "doc.text.magnifyingglass"),
        ("Key points", "list.bullet")
    ]

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.38))
                .frame(width: 58, height: 4)
                .padding(.top, 6)
                .padding(.bottom, 10)

            if busy || documentAnswer != nil {
                answerContent
            } else {
                compactActions
                Spacer(minLength: 0)
            }

            composerIsland
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(465), .large], selection: $selectedDetent)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(44)
        .presentationBackground(.regularMaterial)
        .onChange(of: promptFocused) { _, focused in
            if focused { selectedDetent = .large }
        }
        .onDisappear { documentAIWork?.cancel() }
    }

    private var compactActions: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title: "AI", icon: "checkmark")

            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.brandInk)
                    .frame(width: 20, height: 20)
                Text("\(documentTitle) · \(pageCount) pages")
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Palette.groupedFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 5)

            sectionLabel("Read")
                .padding(.top, 5)

            VStack(spacing: 0) {
                ForEach(promptActions.indices, id: \.self) { index in
                    let action = promptActions[index]
                    Button {
                        currentAnswerTitle = action.0 == "Key points" ? "Key points" : "Summary"
                        runDocumentAIPrompt(action.0)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: action.1)
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(Palette.brandInk)
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(action.0)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text("Select text on the page first")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 6)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)

                    if index < promptActions.count - 1 {
                        Rectangle()
                            .fill(Color(uiColor: .separator).opacity(0.55))
                            .frame(height: 1)
                            .padding(.leading, 52)
                    }
                }
            }
            .background(Palette.canvasView, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 5)

            sectionLabel("Ask")
                .padding(.top, 5)

            Button {
                promptFocused = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Palette.brandInk)
                        .frame(width: 28, height: 28)
                    Text("Ask about this document")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Palette.canvasView, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
    }

    private var answerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(title: currentAnswerTitle, icon: "checkmark")

                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.brandInk)
                        .frame(width: 20, height: 20)
                    Text("\(documentTitle) · \(pageCount) pages")
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.groupedFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if busy {
                    HStack(spacing: 10) {
                        ProgressView().tint(Palette.brandInk)
                        Text("Reading the document…")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    Image(systemName: "link")
                    Text("Referenced 0 sources")
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let documentAnswer {
                    answerCard(documentAnswer)
                }

                Text("AI can make mistakes. Check important details in the document.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func header(title: String, icon: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button {
                dismissSheet()
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Palette.brandInk, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
        }
        .frame(height: 50)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(height: 18, alignment: .leading)
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
            TextField("Ask anything about this document", text: $pdfPromptDraft, axis: .vertical)
                .lineLimit(1...3)
                .font(.body)
                .submitLabel(.send)
                .focused($promptFocused)
                .onSubmit { sendDraft() }
                .padding(.leading, 8)

            Button {
                sendDraft()
            } label: {
                Image(systemName: busy ? "stop.fill" : "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Palette.brandInk, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!busy && pdfPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(!busy && pdfPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.48 : 1)
            .accessibilityLabel(busy ? "Stop generating" : "Send question")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 46)
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
        currentAnswerTitle = "Answer"
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
        selectedDetent = .large
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
                promptFocused = false
                requestStoreReview()
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { vault.bannerText = error.localizedDescription }
            }
        }
    }
}
