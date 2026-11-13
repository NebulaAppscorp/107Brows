//
//  EditBookmarkView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 07/11/26.
//

import SwiftUI
import QuickLook


/// Edit bookmark form: name, address, folder, delete button.
struct EditBookmarkView: View {
    let bookmarkEntry: SavedPage
    @Environment(BrowserStore.self) private var vault
    @Environment(\.dismiss) private var dismissSheet
    @Environment(\.colorScheme) private var interfaceScheme
    @State private var headingText = ""
    @State private var bookmarkDraft = ""
    @State private var shelfDraft = ""
    @State private var showFolderPicker = false
    @State private var showDeleteConfirm = false
    private let separator = Palette.rgb(0xD6E2DC)
    private var cardFill: Color {
        interfaceScheme == .dark ? Color(uiColor: .secondarySystemGroupedBackground) : .white
    }
    private var folderOptions: [String] {
        Array(Set(vault.pinnedPages.compactMap(\.shelfLabel) + (shelfDraft.isEmpty ? [] : [shelfDraft]))).sorted()
    }
    private var canSave: Bool {
        !headingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && AddressResolver.coerceNavigableURL(bookmarkDraft) != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    labeledField("Name", text: $headingText)
                    rowDivider
                    labeledField("Address", text: $bookmarkDraft, addressStyle: true)
                    rowDivider
                    Button {
                        showFolderPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Text("Folder")
                                .font(.ui(17))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            Text(shelfDraft.isEmpty ? "None" : shelfDraft)
                                .font(.ui(17))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.ui(13, weight: .semibold))
                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 54)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .background(cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Button("Delete bookmark", role: .destructive) {
                    showDeleteConfirm = true
                }
                .font(.ui(17))
                .frame(maxWidth: .infinity)
                .padding(.top, 24)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.canvasView.ignoresSafeArea())
            .navigationTitle("Edit bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .browsLiquidNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismissSheet() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: commitBookmarkDraft).disabled(!canSave)
                }
            }
            // sheet for the current route
            .sheet(isPresented: $showFolderPicker) {
                BookmarkFolderPicker(selection: $shelfDraft, folderChoices: folderOptions)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert("Delete this bookmark?", isPresented: $showDeleteConfirm) {
                Button("Delete bookmark", role: .destructive) {
                    vault.pinnedPages.removeAll { $0.id == bookmarkEntry.id }
                    vault.flushSnapshot()
                    dismissSheet()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can’t be undone.")
            }
            .onAppear {
                headingText = bookmarkEntry.pageTitle
                bookmarkDraft = EditBookmarkView.displayAddress(for: bookmarkEntry.pageURL)
                shelfDraft = bookmarkEntry.shelfLabel ?? ""
            }
        }
    }

    // layout for row divider
    private var rowDivider: some View {
        Rectangle().fill(separator).frame(height: 1).padding(.leading, 16)
    }
}

// MARK: - Helpers
extension EditBookmarkView {
    // labeled field
    private func labeledField(_ label: String, text draftText: Binding<String>, addressStyle: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.ui(13))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
            Group {
                if addressStyle {
                    TextField(label, text: draftText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } else {
                    TextField(label, text: draftText)
                }
            }
            .font(.ui(17))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // commits bookmark draft
    private func commitBookmarkDraft() {
        guard let linkURL = AddressResolver.coerceNavigableURL(bookmarkDraft),
            let index = vault.pinnedPages.firstIndex(where: { $0.id == bookmarkEntry.id })
        else { return }
        let trimmed = headingText.trimmingCharacters(in: .whitespacesAndNewlines)
        vault.pinnedPages[index].pageTitle = trimmed
        vault.pinnedPages[index].pageURL = linkURL
        vault.pinnedPages[index].shelfLabel = shelfDraft.isEmpty ? nil : shelfDraft
        vault.flushSnapshot()
        dismissSheet()
    }

    static func displayAddress(for linkURL: URL) -> String {
        let host = linkURL.host ?? ""
        let path = linkURL.path
        if path.isEmpty || path == "/" { return host }
        return host + path
    }
}

/// Folder chooser inside the edit sheet.
struct BookmarkFolderPicker: View {
    // from the environment
    @Binding var selection: String
    let folderChoices: [String]
    @Environment(\.dismiss) private var dismissSheet
    @State private var newFolder = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selection = ""
                        dismissSheet()
                    } label: {
                        HStack {
                            Text("None")
                            Spacer()
                            if selection.isEmpty {
                                Image(systemName: "checkmark").foregroundStyle(Palette.brandInk)
                            }
                        }
                    }
                    ForEach(folderChoices, id: \.self) { name in
                        Button {
                            selection = name
                            dismissSheet()
                        } label: {
                            HStack {
                                Text(name)
                                Spacer()
                                if selection == name {
                                    Image(systemName: "checkmark").foregroundStyle(Palette.brandInk)
                                }
                            }
                        }
                    }
                }
                Section("New folder") {
                    HStack {
                        TextField("Folder name", text: $newFolder)
                            .textInputAutocapitalization(.words)
                        Button("Add") {
                            let trimmed = newFolder.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            selection = trimmed
                            dismissSheet()
                        }
                        .disabled(newFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Folder")
            .navigationBarTitleDisplayMode(.inline)
            .browsLiquidNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismissSheet() } }
            }
        }
    }
}
