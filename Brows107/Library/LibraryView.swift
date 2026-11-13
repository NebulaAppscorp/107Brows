//
//  LibraryView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 29/10/26.
//

import SwiftUI
import QuickLook

/// Menu rows where destructive copy and icon must both render red (accent would tint the symbol green).
struct DestructiveMenuLabel: View {
    let headingText: String
    var iconName: String = "trash"

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .symbolRenderingMode(.monochrome)
            Text(headingText)
        }
        .foregroundStyle(Color.red)
    }
}

enum TabsScreenLayout {
    /// Tabs layout: nav bar at y=62, controls inset 8, grid from y=136, bottom bar at y=780 on an 874 pt screen. 
    static let navBarTop: CGFloat = 62
    static let navControlTop: CGFloat = 8
    static let navControlSize: CGFloat = 46
    static let gridTop: CGFloat = 136
    static let bottomBarTop: CGFloat = 780
    /// Plus, done and the Private/tabs pill share one height.
    static let bottomControl: CGFloat = 46
    static let bottomBarHeight: CGFloat = 46
    /// Bottom bar offset: 780 + 52 on the 874 pt screen.
    static var bottomBarBottom: CGFloat { bottomBarTop + bottomBarHeight }
    static let tabCloseSize: CGFloat = 26
    static let tabCloseInset: CGFloat = 8
}

/// Tab switcher grid.
struct TabsView: View {
    // local UI state
    @Environment(BrowserStore.self) private var vault
    @Environment(WebSession.self) private var webLane
    @Environment(\.colorScheme) private var interfaceScheme
    @Environment(\.dismiss) private var dismissSheet
    @State private var confirmClose = false
    private let gridHorizontal: CGFloat = 15
    private let columnSpacing: CGFloat = 14
    private let masonryGap: CGFloat = 20
    private let placeholderGradients: [[Color]] = [
        [Palette.rgb(0xE0EDE5), Palette.rgb(0xA8CCBA)],
        [Palette.rgb(0xDEE5F7), Palette.rgb(0xB2C2EB)],
        [Palette.rgb(0xFAEBDD), Palette.rgb(0xF0C99E)],
        [Palette.rgb(0xF0F0F2), Palette.rgb(0xCCD1D9)],
        [Palette.rgb(0xF7E0EB), Palette.rgb(0xE8B5C9)],
        [Palette.rgb(0xDBF0F2), Palette.rgb(0xA1D4D9)],
    ]

    var body: some View {
        GeometryReader { geo in
            // Positions are absolute from the top of the 402×874 screen (status bar included).
            let tabCardWidth = floor((geo.size.width - gridHorizontal * 2 - columnSpacing) / 2)
            let tabThumbHeight = tabCardWidth * (236 / 179)
            let masonryLanes = [
                GridItem(.fixed(tabCardWidth), spacing: columnSpacing, alignment: .top),
                GridItem(.fixed(tabCardWidth), spacing: columnSpacing, alignment: .top),
            ]
            let layoutScale = geo.size.height / 874
            let bottomBarLift = max(24, geo.safeAreaInsets.bottom - 6)
            let shelfClearance = bottomBarLift + TabsScreenLayout.bottomBarHeight + 12
            ZStack {
                ArtworkBackdrop(
                    assetName: AssetCatalog.topGlow,
                    useArtwork: vault.prefersLightBackdropArt(systemScheme: interfaceScheme)
                ) {
                    Palette.canvasView.ignoresSafeArea()
                }
                if vault.visibleTabs.isEmpty {
                    EmptyState(
                        symbolName: "square.on.square", headingText: "No open tabs",
                        blurb: "Start browsing and your tabs will show up here."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, TabsScreenLayout.gridTop * layoutScale)
                } else {
                    ScrollView {
                        LazyVGrid(columns: masonryLanes, spacing: masonryGap) {
                            ForEach(Array(vault.visibleTabs.enumerated()), id: \.element.id) { index, tab in
                                tabCard(tab, index: index, tabCardWidth: tabCardWidth, tabThumbHeight: tabThumbHeight)
                            }
                        }
                        .padding(.horizontal, gridHorizontal)
                        .padding(.top, TabsScreenLayout.gridTop * layoutScale)
                        .padding(.bottom, shelfClearance)
                    }
                    .scrollIndicators(.hidden)
                    .browsScrollEdgeEffectHidden()
                }
                VStack {
                    tabsTopBar
                        .padding(.top, (TabsScreenLayout.navBarTop + TabsScreenLayout.navControlTop) * layoutScale)
                    Spacer(minLength: 0)
                }
                VStack {
                    Spacer(minLength: 0)
                    tabsBottomBar
                        .padding(.bottom, bottomBarLift)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { webLane.refreshVisibleTabPreviews(vault.visibleTabs) }
        .alert("Close all \(vault.visibleTabs.count) tabs?", isPresented: $confirmClose) {
            Button("Cancel", role: .cancel) {}
            Button("Close All", role: .destructive) { for browserTab in vault.visibleTabs { vault.closeTabByID(browserTab.id) } }
        } message: {
            Text("Open pages will be closed. Bookmarks stay.")
        }
        .presentationBackground(.clear)
    }

    // layout for tabs top bar
    private var tabsTopBar: some View {
        HStack {
            Menu {
                Button(role: .destructive) {
                    confirmClose = true
                } label: {
                    DestructiveMenuLabel(headingText: "Close all tabs", iconName: "xmark")
                }
                .tint(.red)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.ui(19, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: TabsScreenLayout.navControlSize, height: TabsScreenLayout.navControlSize)    
                    .browsGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tabs menu")
            Spacer(minLength: 0)
            Button {
                vault.enqueueModal(to: .search)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.ui(18, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: TabsScreenLayout.navControlSize, height: TabsScreenLayout.navControlSize)
                    .browsGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search tabs")
        }
        .padding(.horizontal, 20)
    }

    /// Plus · segmented control · done, spread edge to edge with a 12 pt inset.
    private var tabsBottomBar: some View {
        HStack(spacing: 0) {
            Button {
                self.vault.spawnTab()
                dismissSheet()
            } label: {
                Image(systemName: "plus")
                    .font(.ui(17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: TabsScreenLayout.bottomControl, height: TabsScreenLayout.bottomControl)
                    .contentShape(Circle())
                    .browsGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New tab")
            .accessibilityIdentifier("tabs.new")

            Spacer(minLength: 0)

            tabsPrivacySegment

            Spacer(minLength: 0)

            Button {
                dismissSheet()
            } label: {
                Image(systemName: "checkmark")
                    .font(.ui(17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: TabsScreenLayout.bottomControl, height: TabsScreenLayout.bottomControl)
                    .background(Palette.brandInk, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
        }
        .frame(maxWidth: .infinity)
        .frame(height: TabsScreenLayout.bottomBarHeight)
        .padding(.horizontal, 12)
    }


    // tabs privacy segment section
    private var tabsPrivacySegment: some View {
        HStack(spacing: 0) {
            Button("Private") { vault.toggleIncognito(true) }
                .foregroundStyle(vault.incognito ? Color(uiColor: .label) : Color(uiColor: .secondaryLabel))
                .frame(width: 80, height: 38)
                // background fill
                .background {
                    if vault.incognito {
                        Capsule().fill(Palette.rgb(0x767680).opacity(0.12))
                    }
                }
            Button("\(vault.visibleTabs.count) tabs") { vault.toggleIncognito(false) }
                .foregroundStyle(vault.incognito ? Color(uiColor: .secondaryLabel) : Color(uiColor: .label))
                .frame(width: 80, height: 38)
                .background {
                    if !vault.incognito {
                        Capsule().fill(Palette.rgb(0x767680).opacity(0.12))
                    } 
                }
        }
        .font(.ui(14, weight: .medium))
        .tracking(-0.23)
        .padding(.horizontal, 4)
        .frame(width: 172, height: TabsScreenLayout.bottomControl)
        .browsGlassCapsule()
    }
}

// MARK: - Private helpers
extension TabsView {
    // tab card
    private func tabCard(_ browserTab: BrowserTab, index: Int, tabCardWidth: CGFloat, tabThumbHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Button {
                    self.vault.activeTabKey = browserTab.id
                    vault.chromePane = 0
                    dismissSheet()
                } label: {
                    TabPreviewCard(browserTab: browserTab, index: index, gradients: placeholderGradients)
                        .frame(width: tabCardWidth, height: tabThumbHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: Palette.rgb(0x001A12).opacity(0.1), radius: 10, y: 3)
                        .shadow(color: Palette.rgb(0x001A12).opacity(0.06), radius: 26, y: 12)
                }
                .buttonStyle(.plain)
                tabCloseButton { vault.closeTabByID(browserTab.id) }
                    .zIndex(1)
            }
            .frame(width: tabCardWidth, height: tabThumbHeight)
            HStack(spacing: 6) {
                TabHostIcon(linkURL: browserTab.pageURL)
                Text(browserTab.pageTitle).font(.ui(15, weight: .semibold)).tracking(-0.23).foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
            .frame(width: tabCardWidth, height: 20, alignment: .leading)
        }
        .frame(width: tabCardWidth, alignment: .top)
    }

    // tab close button
    private func tabCloseButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.ui(11, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.85))
                .frame(width: TabsScreenLayout.tabCloseSize, height: TabsScreenLayout.tabCloseSize)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5) }
        }
        .buttonStyle(.plain) 
        .padding(TabsScreenLayout.tabCloseInset)
        .accessibilityLabel("Close tab")
    }
}


/// Thumbnail with a title and a close button.
struct TabPreviewCard: View {
    // current browser tab
    let browserTab: BrowserTab
    let index: Int
    let gradients: [[Color]]
    // local UI state
    @State private var remote: UIImage?
    private var previewStore = TabPreviewStore.singleton

    var body: some View {
        let snapshot = previewStore.tabThumbnails[browserTab.id]
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: gradients[index % gradients.count],
                        startPoint: UnitPoint(x: 0.044, y: 0.249),
                        endPoint: UnitPoint(x: 0.948, y: 0.747)
                    ))
            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if let remote {
                Image(uiImage: remote)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if browserTab.pageURL == nil {
                Image(systemName: "sparkles")
                    .font(.ui(20, weight: .medium))
                    .foregroundStyle(Palette.brandInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(17)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task(id: browserTab.id) {
            guard previewStore.tabThumbnails[browserTab.id] == nil, let linkURL = browserTab.pageURL else { return }
            if let loaded = await TabPageSnapshot.resolvePlaceholderThumb(for: linkURL) {
                remote = loaded
            }
        }
    }
}


struct TabHostIcon: View {
    let linkURL: URL?
    @State private var icon: UIImage?

    var body: some View {
        Group {
            if let icon {
                Image(uiImage: icon).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color(uiColor: .tertiarySystemFill))
            }
        }
        .frame(width: 16, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        // runs once when the view appears
        .task(id: linkURL?.absoluteString) {
            guard let linkURL else { return }
            icon = await TabPageSnapshot.faviconForPage(linkURL)
        }
    }
}

/// Bookmarks and history.
struct LibraryView: View {
    @Environment(BrowserStore.self) private var vault
    @Environment(\.dismiss) private var dismissSheet
    @State private var category = 0
    @State private var query = ""
    @State private var activeShelf: String?
    @State private var editing: SavedPage?
    @State private var confirmClear = false
    @State private var confirmClearBookmarks = false
    @State private var historyWasCleared = false
    @State private var openSwipe: UUID?
    private var shelfEntries: [SavedPage] {
        (category == 0 ? vault.visitLedger : vault.pinnedPages).filter {
            (activeShelf == nil || $0.shelfLabel == activeShelf)
                && (query.isEmpty || $0.pageTitle.localizedCaseInsensitiveContains(query)
                    || $0.pageURL.absoluteString.localizedCaseInsensitiveContains(query))
        }
    }
    private var bookmarkFolders: [(shelfTitle: String, count: Int)] {
        let groupedFill = Dictionary(grouping: vault.pinnedPages.filter { $0.shelfLabel != nil }) { $0.shelfLabel! }
        return groupedFill.keys.sorted().map { (shelfTitle: $0, count: groupedFill[$0]?.count ?? 0) }
    }
    private var showsFolderBrowser: Bool { category == 1 && activeShelf == nil && query.isEmpty }
    private var searchPlaceholder: String {
        if category == 0 { return "Search history" }
        if let activeShelf { return "Search in \(activeShelf)" }
        return "Search bookmarks"
    }
    private var groups: [(headingText: String, shelfEntries: [SavedPage])] {
        if category == 1 {
            if let activeShelf { return [(activeShelf, shelfEntries)] }
            if !query.isEmpty { return [("Bookmarks", shelfEntries)] }
            let unfoldered = shelfEntries.filter { $0.shelfLabel == nil }
            return unfoldered.isEmpty ? [] : [("All bookmarks", unfoldered)]
        }
        if vault.launchScenario == "library" {
            return [("Today", Array(shelfEntries.prefix(3))), ("Yesterday", Array(shelfEntries.dropFirst(3)))].filter {
                !$0.shelfEntries.isEmpty
            }
        }
        let dayCalendar = Calendar.current
        let byDay = Dictionary(grouping: shelfEntries) { dayCalendar.startOfDay(for: $0.recordedAt) }
        return byDay.keys.sorted(by: >).map { day in
            let headingText =
                dayCalendar.isDateInToday(day)
                ? "Today" : dayCalendar.isDateInYesterday(day) ? "Yesterday" : day.formatted(date: .abbreviated, time: .omitted)
            return (headingText, byDay[day] ?? [])
        }
    }
    var body: some View {
        ZStack {
            Palette.canvasView.ignoresSafeArea()
            VStack(spacing: 0) {
                shelfHeader.padding(.top, 20)
                searchField.padding(.horizontal, 20).padding(.top, 16)
                if category == 1, let activeShelf {
                    folderBackRow(activeShelf).padding(.top, 12)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if category == 1 && shelfEntries.isEmpty && (showsFolderBrowser ? bookmarkFolders.isEmpty : true) {
                            if query.isEmpty {
                                EmptyState(
                                    symbolName: "bookmark", headingText: "No bookmarks yet",
                                    blurb: "Save a page from the menu and it lands here."
                                )
                                .padding(.top, 120)
                            } else {
                                EmptyState(
                                    symbolName: "magnifyingglass", headingText: "No results for “\(query)”",
                                    blurb: "Try a shorter word, or search the web instead.", actionTitle: "Search the web"
                                ) {
                                    vault.navigateInput(query)
                                    dismissSheet()
                                }
                                .padding(.top, 120)
                            }
                        } else if category == 0 && shelfEntries.isEmpty && query.isEmpty {
                            EmptyState(
                                symbolName: "clock",
                                headingText: historyWasCleared ? "History cleared" : "Nothing here yet",
                                blurb: historyWasCleared
                                    ? "New pages you visit will show up here." : "Pages you visit will show up here."
                            )
                            .padding(.top, 120)
                        } else if !query.isEmpty && shelfEntries.isEmpty {
                            EmptyState(
                                symbolName: "magnifyingglass", headingText: "No results for “\(query)”",
                                blurb: "Try a shorter word, or search the web instead.", actionTitle: "Search the web"
                            ) {
                                vault.navigateInput(query)
                                dismissSheet()
                            }
                            .padding(.top, 120)
                        } else {
                            if showsFolderBrowser, !bookmarkFolders.isEmpty {
                                foldersSection.padding(.bottom, 4)
                            }
                            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(group.headingText).font(.ui(13)).foregroundStyle(.tertiary).frame(height: 18)
                                        .padding(.horizontal, 20)
                                    VStack(spacing: 0) {
                                        ForEach(Array(group.shelfEntries.enumerated()), id: \.element.id) { index, shelfEntry in
                                            pageRow(shelfEntry, index: index)
                                            if shelfEntry.id != group.shelfEntries.last?.id {
                                                Rectangle().fill(Color(uiColor: .separator)).frame(height: 1).padding(
                                                    .leading, 56)
                                            }
                                        }
                                    }.padding(.horizontal, 16)
                                }
                            }
                        } 
                    }
                    .padding(.top, 22)
                    .padding(.bottom, 20)
                }
            }
        }
        // action sheet style confirmation
        .confirmationDialog("Clear browsing history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) {
                vault.visitLedger.removeAll()
                historyWasCleared = true
                vault.removeXcomTabs()
                vault.openBrowserHome()
                vault.flushSnapshot()
            }
        } message: {
            Text("Your bookmarks and downloads will stay.")
        }
        .confirmationDialog("Delete all bookmarks?", isPresented: $confirmClearBookmarks, titleVisibility: .visible) {
            Button("Delete all bookmarks", role: .destructive) {
                vault.pinnedPages.removeAll()
                vault.flushSnapshot()
                activeShelf = nil
                openSwipe = nil
            }
        } message: {
            Text("This can’t be undone.")
        }
        // sheet for the current route  
        .sheet(item: $editing) { shelfEntry in
            EditBookmarkView(bookmarkEntry: shelfEntry)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.canvasView)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.canvasView)
    }

    private var shelfHeader: some View {
        HStack(spacing: 0) {
            Button {
                dismissSheet()
            } label: {
                Image(systemName: "xmark").font(.ui(17, weight: .medium)).foregroundStyle(Color(uiColor: .label)).frame(
                    width: 44, height: 44
                ).browsGlassCircle()
            }.buttonStyle(.plain).accessibilityLabel("Close library")
            Spacer(minLength: 0)
            HStack(spacing: 0) { 
                categoryButton("History", value: 0)
                categoryButton("Bookmarks", value: 1)
            }
            .frame(width: 210, height: 38).padding(3).browsGlassCapsule()
            Spacer(minLength: 0)
            Menu {
                if category == 0 {
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: { 
                        DestructiveMenuLabel(headingText: "Clear history")
                    }
                    .tint(.red)
                } else {
                    Button(role: .destructive) {
                        self.confirmClearBookmarks = true
                    } label: {
                        DestructiveMenuLabel(headingText: "Delete all bookmarks")
                    }
                    .tint(.red)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.ui(17, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 40, height: 40)
            }
            .browsGlassButtonStyle()
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .accessibilityLabel("Library actions")
        }
        .padding(.horizontal, 20).padding(.top, 0)
    }
}

// MARK: Helpers 
extension LibraryView {
    // category button
    private func categoryButton(_ headingText: String, value slot: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                category = slot
                activeShelf = nil
            }
        } label: {
            Text(headingText).font(.ui(16, weight: category == slot ? .medium : .regular))
                .foregroundStyle(category == slot ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity).frame(height: 38)
                // background fill
                .background(category == slot ? Palette.raisedFill : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }

    // layout for search field
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.ui(18)).foregroundStyle(.primary)
            TextField(searchPlaceholder, text: $query).font(.ui(16)).textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            VoiceInputButton(draftText: $query)
        }
        .padding(.horizontal, 14).frame(height: 48).browsGlassCapsule()
    }


    // folder back row
    private func folderBackRow(_ name: String) -> some View {
        Button {
            withAnimation { activeShelf = nil }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.ui(17, weight: .semibold))
                Text(name)
                    .font(.ui(17, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // the folders section block
    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Folders")
                .font(.ui(13))
                .foregroundStyle(.tertiary)
                .frame(height: 18)
                .padding(.horizontal, 20)
            VStack(spacing: 0) {
                ForEach(bookmarkFolders, id: \.shelfTitle) { folder in
                    Button {
                        withAnimation { activeShelf = folder.shelfTitle }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder")
                                .font(.ui(17))
                                .foregroundStyle(.primary)
                                .frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.shelfTitle)
                                    .font(.ui(17))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(height: 22)
                                Text("\(folder.count) bookmarks")
                                    .font(.ui(15))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .frame(height: 20)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.ui(13, weight: .semibold))
                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 64)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if folder.shelfTitle != bookmarkFolders.last?.shelfTitle {
                        Rectangle()
                            .fill(Color(uiColor: .separator))
                            .frame(height: 1)
                            .padding(.leading, 50)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // Page row
    private func pageRow(_ shelfEntry: SavedPage, index: Int) -> some View {
        let label = HStack(spacing: 10) {
            Button {
                vault.navigateInput(shelfEntry.pageURL.absoluteString)
                dismissSheet()
            } label: {
                HStack(spacing: 10) {
                    if category == 0 {
                        Image(systemName: "clock")
                            .font(.ui(15))
                            .foregroundStyle(.primary)
                            .frame(width: 22, height: 22)
                    } else {
                        TabHostIcon(linkURL: shelfEntry.pageURL)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shelfEntry.pageTitle).font(.ui(17)).foregroundStyle(.primary).lineLimit(1).frame(
                            height: 22)
                        Text(shelfEntry.pageURL.host ?? shelfEntry.pageURL.absoluteString).font(.ui(15))
                            .foregroundStyle(.tertiary).lineLimit(1).frame(height: 20)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 64)

        return Group {
            if category == 0 {
                SwipeToDeleteRow(
                    height: 64,
                    isOpen: openSwipe == shelfEntry.id,
                    rowFill: Palette.canvasView,
                    card: Palette.canvasView,
                    onOpen: { withAnimation(.spring(duration: 0.28)) { openSwipe = shelfEntry.id } },
                    onClose: { withAnimation(.spring(duration: 0.28)) { if openSwipe == shelfEntry.id { openSwipe = nil } } },
                    onDelete: { delete(shelfEntry) }
                ) { label }
            } else {
                SwipeToDeleteRow(
                    height: 64,
                    isOpen: openSwipe == shelfEntry.id,
                    rowFill: Palette.canvasView,
                    card: Palette.canvasView,
                    onOpen: { withAnimation(.spring(duration: 0.28)) { openSwipe = shelfEntry.id } },
                    onClose: { withAnimation(.spring(duration: 0.28)) { if openSwipe == shelfEntry.id { openSwipe = nil } } },
                    onDelete: { delete(shelfEntry) }
                ) { label }
            }
        }
        .contextMenu {
            Button("Open in new tab", systemImage: "plus.square") {
                vault.navigateInput(shelfEntry.pageURL.absoluteString, inNewTab: true)
                dismissSheet()
            }
            if category == 1 { Button("Edit bookmark", systemImage: "pencil") { editing = shelfEntry } }
            ShareLink(item: shelfEntry.pageURL)
            Button("Delete", systemImage: "trash", role: .destructive) { delete(shelfEntry) }
        }
    }

    // Removes it
    private func delete(_ shelfEntry: SavedPage) {
        if category == 0 {
            vault.visitLedger.removeAll { $0.id == shelfEntry.id }
        } else {
            vault.pinnedPages.removeAll { $0.id == shelfEntry.id }
        }
        vault.flushSnapshot()
    }
}
