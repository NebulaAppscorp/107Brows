//
//  DownloadsView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 05/11/26.
//

import SwiftUI
import QuickLook


/// Downloads list with pause / resume.
struct DownloadsView: View {
    var pdfOnly = false
    @Environment(BrowserStore.self) private var vault
    @Environment(\.dismiss) private var dismissSheet
    @State private var previewURL: URL?
    @State private var deleting: DownloadItem?
    @State private var clearingAll = false
    @State private var openSwipe: UUID?
    private let rowSeparator = Palette.rgb(0xD6E2DC)
    private var items: [DownloadItem] {
        let downloadSource: [DownloadItem]
        if !vault.savedDownloads.isEmpty { 
            downloadSource = vault.savedDownloads
        } else if vault.launchScenario != nil {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)
            let brewing = DownloadItem(
                assetLabel: "Brewing Standards 2026.pdf",
                byteSizeLabel: "2.4 MB · PDF",
                transferProgress: vault.launchScenario == "downloads-paused" || vault.launchScenario == "downloads-active"
                    ? 0.5 : 1,
                transferPaused: vault.launchScenario == "downloads-paused",
                bytesReceivedDisplay: vault.launchScenario == "downloads-paused" || vault.launchScenario == "downloads-active"
                    ? "1.2 MB" : nil,
                bytesTotalDisplay: vault.launchScenario == "downloads-paused" || vault.launchScenario == "downloads-active"
                    ? "2.4 MB" : nil,
                etaSeconds: vault.launchScenario == "downloads-active" ? 40 : nil
            )
            downloadSource = [
                brewing,
                DownloadItem(assetLabel: "Liquid Glass overview.pdf", byteSizeLabel: "8.1 MB · PDF"),
                DownloadItem(assetLabel: "coffee-grind-chart.png", byteSizeLabel: "640 KB · PNG", downloadedAt: yesterday),
                DownloadItem(assetLabel: "sf-symbols-8.zip", byteSizeLabel: "24.6 MB · ZIP", downloadedAt: yesterday),
            ]
        } else {
            downloadSource = []
        }
        guard pdfOnly else { return downloadSource }
        return downloadSource.filter { $0.assetLabel.lowercased().hasSuffix(".pdf") }
    }
    private var groups: [(headingText: String, items: [DownloadItem])] {
        let dayCalendar = Calendar.current
        let groupedFill = Dictionary(grouping: items) { item in
            dayCalendar.startOfDay(for: item.downloadedAt ?? .distantPast)
        }
        return groupedFill.keys.sorted(by: >).map { day in
            let headingText: String
            if dayCalendar.isDateInToday(day) {
                headingText = "Today"
            } else if dayCalendar.isDateInYesterday(day) {
                headingText = "Yesterday"
            } else {
                headingText =
                    day == dayCalendar.startOfDay(for: .distantPast)
                    ? "Earlier" : day.formatted(date: .abbreviated, time: .omitted)
            }
            return (headingText, groupedFill[day] ?? [])
        }
    }  
    var body: some View {
        NavigationStack {
            ZStack {    
                Palette.canvasView.ignoresSafeArea()
                if items.isEmpty {
                    VStack(spacing: 0) {
                        Image("downloads_empty")
                            .resizable()
                            .frame(width: 64, height: 64)
                        Text(pdfOnly ? "No PDF downloads" : "No downloads")
                            .font(.ui(17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.top, 18)
                        Text(pdfOnly ? "Downloaded PDF files will show up here." : "Files you download will show up here.")
                            .font(.ui(15))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)  
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(groups, id: \.headingText) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(group.headingText)
                                        .font(.ui(13))
                                        .foregroundStyle(.tertiary)
                                        .frame(height: 18)
                                        .padding(.horizontal, 20)
                                    VStack(spacing: 0) {
                                        ForEach(Array(group.items.enumerated()), id: \.element.id) { _, item in
                                            downloadListRow(item)
                                            if item.id != group.items.last?.id {
                                                Rectangle()
                                                    .fill(rowSeparator)
                                                    .frame(height: 1)
                                                    .padding(.leading, 68)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }
                        .padding(.top, 18)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle(pdfOnly ? "Downloaded PDFs" : "Downloads").navigationBarTitleDisplayMode(.inline)
            .browsLiquidNavBar()
            .toolbar {
                IsolatedToolbarItem {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismissSheet()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.ui(17, weight: .medium))
                                .foregroundStyle(Color(uiColor: .label))
                                .frame(width: 44, height: 44)
                                .browsGlassCircle()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }
                }
                IsolatedToolbarItem {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu { 
                            Button(role: .destructive) {
                                clearingAll = true
                            } label: {
                                DestructiveMenuLabel(headingText: pdfOnly ? "Clear PDF downloads" : "Clear downloads")
                            }
                            .tint(.red)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.ui(18, weight: .semibold))
                                .foregroundStyle(Color.primary)
                                .frame(width: 44, height: 44)
                                .browsGlassCircle()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("More download options")
                    }
                }
            }
            .quickLookPreview($previewURL)
            .confirmationDialog(
                pdfOnly ? "Delete all downloaded PDFs?" : "Delete all downloads?", isPresented: $clearingAll,
                titleVisibility: .visible
            ) {
                Button(pdfOnly ? "Delete all PDFs" : "Delete all downloads", role: .destructive) {
                    let itemsToDelete =
                        pdfOnly
                        ? vault.savedDownloads.filter { $0.assetLabel.lowercased().hasSuffix(".pdf") } : vault.savedDownloads
                    for item in itemsToDelete {
                        if let linkURL = item.diskFileURL { try? FileManager.default.removeItem(at: linkURL) }
                    }
                    if pdfOnly {
                        vault.savedDownloads.removeAll { $0.assetLabel.lowercased().hasSuffix(".pdf") }
                    } else {
                        vault.savedDownloads.removeAll()
                    }
                    self.vault.flushSnapshot()
                }
            }
            .confirmationDialog(
                "Delete this file?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete file", role: .destructive) {
                    if let item = deleting { delete(item) }
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            }
        }.presentationDetents([.large]).presentationDragIndicator(.visible).presentationBackground(Palette.canvasView)
    }
}

// MARK: - Actions
extension DownloadsView {
    // download list row
    private func downloadListRow(_ item: DownloadItem) -> some View {
        let label = Button {
            guard item.transferProgress >= 1, !item.transferPaused else { return }
            if let linkURL = item.diskFileURL {
                self.previewURL = linkURL
            } else if vault.launchScenario != nil {
                vault.modalLane = .pdf
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: iconName(for: item))
                    .font(.ui(18))
                    .foregroundStyle(Palette.brandInk)
                    .frame(width: 40, height: 40)
                    // background goes behind everything
                    .background(Palette.brandWash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.assetLabel)
                        .font(.ui(17))
                        .browsExactLineHeight(22)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(item.statusSubtitle())
                        .font(.ui(15))
                        .browsExactLineHeight(20)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                trailingAccessory(for: item)
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if item.transferProgress >= 1, let linkURL = item.diskFileURL { ShareLink(item: linkURL) }
            if item.downloadInFlight {
                Button(item.transferPaused ? "Resume" : "Pause", systemImage: item.transferPaused ? "play.fill" : "pause.fill") {
                    togglePause(for: item)
                }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = item }
        }

        return SwipeToDeleteRow(
            height: 64,
            isOpen: openSwipe == item.id,
            rowFill: Palette.canvasView,
            card: Palette.canvasView,
            onOpen: { withAnimation(.spring(duration: 0.28)) { openSwipe = item.id } },
            onClose: { withAnimation(.spring(duration: 0.28)) { if openSwipe == item.id { openSwipe = nil } } },
            onDelete: { delete(item) }
        ) { label }
    }

    @ViewBuilder
    private func trailingAccessory(for item: DownloadItem) -> some View {
        if item.downloadInFlight {
            HStack(spacing: 10) {
                if !item.transferPaused {
                    ProgressView(value: item.transferProgress)
                        .progressViewStyle(.circular)
                        .frame(width: 20, height: 20)
                }
                Button {
                    togglePause(for: item)
                } label: {
                    Image(systemName: item.transferPaused ? "play.fill" : "pause.fill")
                        .font(.ui(15, weight: .semibold))
                        .foregroundStyle(Palette.brandInk)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.transferPaused ? "Resume download" : "Pause download")
            }
        } else if item.transferProgress >= 1 {
            Image(systemName: "chevron.right")
                .font(.ui(13, weight: .regular))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
        }
    }

    // Pause or resume a transfer.
    private func togglePause(for item: DownloadItem) {
        guard let index = vault.savedDownloads.firstIndex(where: { $0.id == item.id }) else { return }
        vault.savedDownloads[index].transferPaused.toggle()
        vault.flushSnapshot()
    }

    private func delete(_ item: DownloadItem) {
        if let linkURL = item.diskFileURL { try? FileManager.default.removeItem(at: linkURL) }
        self.vault.savedDownloads.removeAll { $0.id == item.id }
        vault.flushSnapshot()
        if openSwipe == item.id { openSwipe = nil }
        deleting = nil
    }

    // icon name
    private func iconName(for item: DownloadItem) -> String {
        if item.assetLabel.lowercased().hasSuffix(".pdf") { return "doc.text" }
        if [".png", ".jpg", ".jpeg", ".heic"].contains(where: item.assetLabel.lowercased().hasSuffix) { return "photo" }
        return "archivebox"
    }
}
