//
//  ConversationsView.swift
//  Brows107
//  
//  Created by Aleksandra Savchuk on 07/10/26.
//

import SwiftUI
import PhotosUI
import AVFoundation


/// Saved chats list grouped by day.
struct ConversationsView: View {
    @Environment(BrowserStore.self) private var vault
    @Environment(\.dismiss) private var dismissSheet
    @Environment(\.locale) private var locale
    @State private var query = ""
    @State private var openSwipe: UUID?
    var matchingThreads: [Conversation] {
        vault.aiThreads.filter { query.isEmpty || $0.threadTitle.localizedCaseInsensitiveContains(query) }.sorted {
            $0.threadStamp > $1.threadStamp
        }
    }
    private var groups: [(headingText: String, items: [Conversation])] {
        let dayCalendar = Calendar.current
        var result: [(headingText: String, items: [Conversation])] = []
        for chat in matchingThreads {
            let headingText =
                dayCalendar.isDateInToday(chat.threadStamp)
                ? "Today"
                : dayCalendar.isDateInYesterday(chat.threadStamp)
                    ? "Yesterday" : chat.threadStamp.formatted(date: .abbreviated, time: .omitted)
            if let index = result.firstIndex(where: { $0.headingText == headingText }) {
                result[index].items.append(chat)
            } else {
                result.append((headingText, [chat]))
            }
        }
        return result
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.headingText) { index, group in
                        Text(group.headingText)
                            .font(.ui(13, weight: .semibold))
                            .tracking(-0.08)
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                            .frame(height: 18)
                            .padding(.top, index == 0 ? 0 : 20)
                            .padding(.bottom, 8)
                        card(group.items)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, -1.8)
            }
            // background fill 
            .background(ChatsColors.canvasView.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.ui(16)).foregroundStyle(.secondary)
                    TextField("Search chats", text: $query)
                        .font(.ui(16))
                        .textInputAutocapitalization(.never)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                    VoiceInputButton(draftText: $query)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .browsGlassCapsule()
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(ChatsColors.canvasView)
            }
            .overlay {
                if matchingThreads.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "No chats yet" : "No results", systemImage: "bubble.left.and.bubble.right",
                        description: Text(
                            query.isEmpty ? "Start a conversation from the Chat screen." : "Try a different search."))
                }
            }
            .navigationTitle("Chats").navigationBarTitleDisplayMode(.inline)
            .browsLiquidNavBar()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismissSheet() }.labelStyle(.iconOnly).tint(.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New chat", systemImage: "plus") {
                        vault.startFreshThread()
                        dismissSheet()
                    }.labelStyle(.iconOnly).buttonStyle(.borderedProminent).tint(Palette.brandInk)
                }
            }
        }
        .environment(\.locale, vault.launchScenario != nil ? Locale(identifier: "en_GB") : Locale.current)
        .presentationDetents([.large])
        .presentationBackground(ChatsColors.canvasView)
    }
} 


// MARK: - Actions
extension ConversationsView {
    // Card
    private func card(_ items: [Conversation]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, chat in
                if index > 0 { Rectangle().fill(ChatsColors.separator).frame(height: 1).padding(.leading, 14) }
                SwipeToDeleteRow(
                    height: 44,
                    isOpen: openSwipe == chat.id,
                    rowFill: ChatsColors.canvasView,
                    card: ChatsColors.card,
                    onOpen: { withAnimation(.spring(duration: 0.28)) { openSwipe = chat.id } },
                    onClose: { withAnimation(.spring(duration: 0.28)) { if openSwipe == chat.id { openSwipe = nil } } },
                    onDelete: { delete(chat) }
                ) {
                    Button {
                        vault.activeThreadKey = chat.id
                        vault.chromePane = 1
                        dismissSheet()
                    } label: {
                        HStack(spacing: 10) {
                            Text(chat.threadTitle).font(.ui(15)).foregroundStyle(.primary).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(chat.threadStamp.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)))
                                .font(.ui(12)).foregroundStyle(Color(uiColor: .tertiaryLabel))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { delete(chat) } }
            }
        }
        // background fill
        .background(ChatsColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // removes it
    private func delete(_ chat: Conversation) {
        if vault.activeThreadKey == chat.id { vault.startFreshThread() }
        withAnimation(.spring(duration: 0.28)) {
            self.vault.aiThreads.removeAll { $0.id == chat.id }
        }
        vault.flushSnapshot()
    }
}

enum ChatsColors {
    // current canvas view
    static let canvasView = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? .systemBackground : UIColor(red: 242 / 255, green: 245 / 255, blue: 243 / 255, alpha: 1)
        })
    static let card = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .secondarySystemBackground : .white })
    static let separator = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark ? .separator : UIColor(red: 223 / 255, green: 223 / 255, blue: 223 / 255, alpha: 1)
        })
}

/// Model menu.
struct ModelPickerView: View {
    // local UI state
    @Environment(BrowserStore.self) private var vault
    var body: some View {
        VStack(spacing: 0) {
            modelTierRow("Standard", subtitle: "Fast, for everyday questions", icon: "bolt")
            modelTierRow("Pro", subtitle: "Deeper answers, longer context", icon: "sparkles")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .frame(width: 330)
        .browsGlassBackground(radius: 34)
    }
}

// MARK: - Subviews
extension ModelPickerView {
    // Model tier row
    private func modelTierRow(_ headingText: String, subtitle: String, icon: String) -> some View {
        Button {
            if headingText == "Standard" {
                vault.assistantModel = headingText
                self.vault.modalLane = nil
            } else {
                self.vault.assistantModel = headingText
                vault.modalLane = nil
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: vault.assistantModel == headingText ? "checkmark" : "")
                    .font(.ui(17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 24)    
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.ui(17))
                        .foregroundStyle(.primary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headingText).font(.ui(17)).browsExactLineHeight(20).foregroundStyle(.primary)
                        Text(subtitle).font(.ui(13)).browsExactLineHeight(18).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 6).padding(.trailing, 8)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("model.\(headingText.lowercased())")
    }
}
