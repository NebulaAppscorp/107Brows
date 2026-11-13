//
//  DocumentView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 05/11/26.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import StoreKit


private enum DocumentSheet: String, Identifiable {
    case ai
    case pdfHistory

    var id: String { rawValue }
}

/// PDF viewer with a thumbnails strip and the AI button.
struct DocumentView: View {
    @Environment(BrowserStore.self) private var vault
    @Environment(\.dismiss) private var dismissSheet
    @Environment(\.requestReview) private var requestStoreReview
    @State private var loadedPdf: PDFDocument?
    @State private var loadFailed = false
    @State private var documentTitle = "PDF Document"
    @State private var filePickerPresented = false
    @State private var thumbRailVisible = false
    @State private var visiblePageIndex = 1
    @State private var jump = false
    @State private var jumpDraft = ""
    @State private var presentedSheet: DocumentSheet?


    private var showsChrome: Bool { loadedPdf != nil || loadFailed }
    private var navCaption: String {
        // optional loaded pdf, may be missing
        if let loadedPdf {
            return loadedPdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? documentTitle
        }
        return documentTitle
    }

    var body: some View {
        NavigationStack {
            Group {
                if loadFailed {
                    pdfErrorState
                } else if let loadedPdf {
                    HStack(spacing: 0) {
                        if thumbRailVisible {
                            PDFThumbnails(pdfDocument: loadedPdf, visiblePageIndex: $visiblePageIndex).frame(width: 90)
                        }
                        NativePDFView(
                            pdfDocument: loadedPdf, pageNumber: $visiblePageIndex,
                            freezesPagePosition: vault.launchScenario != nil && vault.launchScenario != "pdf-error"
                        ).padding(.top, vault.launchScenario != nil && vault.launchScenario != "pdf-error" ? 11 : 0)
                    }
                } else {
                    ContentUnavailableView { 
                        Label("Open a PDF", systemImage: "doc.richtext")
                    } description: { 
                        Text("Choose a document to read or ask about.")
                    } actions: {
                        Button("Choose file") { filePickerPresented = true }.browsGlassProminentButtonStyle()
                    }
                }
            }
            // background fill
            .background(PDFColors.canvasView.ignoresSafeArea())
            .navigationTitle(navCaption).navigationBarTitleDisplayMode(.inline)
            .browsLiquidNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "chevron.left") { dismissSheet() }.labelStyle(.iconOnly).tint(.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Document actions", systemImage: "ellipsis") {
                        Button("Open PDF", systemImage: "folder") { filePickerPresented = true }
                        Button("Downloaded PDFs", systemImage: "arrow.down.doc") { presentedSheet = .pdfHistory }
                        if let loadedPdf {
                            Button("Thumbnails", systemImage: "square.grid.2x2") { thumbRailVisible.toggle() }
                            if let linkURL = loadedPdf.documentURL { ShareLink(item: linkURL) }
                        }
                    }.tint(.primary)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsChrome { pdfBottomChrome(interactive: loadedPdf != nil) }
            }
            .fileImporter(isPresented: $filePickerPresented, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let linkURL):
                    documentTitle = linkURL.lastPathComponent
                    Task {
                        // async hop, keep the work above it cheap
                        let openedPdfPayload = await Task.detached(priority: .userInitiated) {
                            // Work out the scoped resource access
                            let scopedResourceAccess = linkURL.startAccessingSecurityScopedResource()
                            defer { if scopedResourceAccess { linkURL.stopAccessingSecurityScopedResource() } }
                            // payload bytes must exist here
                            guard let payloadBytes = try? Data(contentsOf: linkURL) else { return PDFDocumentPayload(nil) }
                            guard let pdfDocument = PDFDocument(data: payloadBytes) else { return PDFDocumentPayload(nil) }
                            // local archive directory
                            let archiveDirectory = URL.applicationSupportDirectory.appending(
                                path: "107Brows/downloads/" + UUID().uuidString, directoryHint: .isDirectory)
                            let originalName = linkURL.lastPathComponent
                            let archiveName = originalName.lowercased().hasSuffix(".pdf") ? originalName : originalName + ".pdf"
                            let archiveLocation = archiveDirectory.appending(path: archiveName)
                            do {
                                try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
                                try payloadBytes.write(to: archiveLocation, options: .atomic) 
                                return PDFDocumentPayload(pdfDocument, archiveURL: archiveLocation, byteCount: payloadBytes.count) 
                            } catch {
                                return PDFDocumentPayload(pdfDocument, archiveError: error.localizedDescription)
                            } 
                        }.value
                        // No slot, no point continuing
                        guard let slot = openedPdfPayload.document else {
                            loadedPdf = nil
                            loadFailed = true
                            return
                        }
                        loadFailed = false
                        loadedPdf = slot
                        visiblePageIndex = 1
                        // handle heading text if it is there
                        if let headingText = slot.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
                            !headingText.isEmpty
                        {
                            self.documentTitle = headingText
                        }
                        // optional archive location, may be missing
                        if let archiveLocation = openedPdfPayload.archiveURL {
                            // work out the size label
                            let sizeLabel = ByteCountFormatter.string(
                                fromByteCount: Int64(openedPdfPayload.byteCount), countStyle: .file)
                            vault.savedDownloads.removeAll { $0.diskFileURL == archiveLocation }
                            vault.savedDownloads.insert(
                                DownloadItem(
                                    assetLabel: archiveLocation.lastPathComponent, diskFileURL: archiveLocation,
                                    byteSizeLabel: sizeLabel), at: 0)
                            self.vault.flushSnapshot()
                        } else if let archiveFailure = openedPdfPayload.archiveError {
                            vault.bannerText = "PDF opened, but it couldn’t be saved to Downloads: \(archiveFailure)"
                        }
                        requestStoreReview()
                    }
                // when failure
                case .failure:
                    loadFailed = true
                }
            }
            .alert("Go to page", isPresented: $jump) {
                TextField("Page number", text: $jumpDraft).keyboardType(.numberPad)
                Button("Go") {
                    if let jumpIndex = Int(jumpDraft), jumpIndex >= 1, jumpIndex <= (loadedPdf?.pageCount ?? 0) {
                        visiblePageIndex = jumpIndex
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            // sheet content is built lazily
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                // ai case
                case .ai:
                    DocumentAIView(
                        fullDocumentText: loadedPdf?.string ?? "",
                        pageText: loadedPdf?.page(at: visiblePageIndex - 1)?.string ?? "")
                case .pdfHistory:
                    DownloadsView(pdfOnly: true)
                }
            }
            .task {
                if vault.launchScenario == "pdf-error" {
                    documentTitle = "Brewing Standards 2026.pdf"
                    loadFailed = true
                    return
                }
                if vault.launchScenario != nil {
                    visiblePageIndex = 12
                    loadedPdf = Self.fixtureDocument()
                    documentTitle = "Brewing Standards 2026.pdf"
                }
            }
        }
    }

    /// Red doc badge, copy, Try again; bottom bar dimmed.
    private var pdfErrorState: some View {
        VStack(spacing: 0) {
            ZStack {  
                Circle()
                    .fill(Palette.rgb(0xFF383C))
                    // Size matches the mock
                    .frame(width: 64, height: 64)
                Image(systemName: "doc.fill")
                    .font(.ui(28))
                    .foregroundStyle(.white)
            }
            Color.clear.frame(height: 18)
            Text("Can’t open this file")
                .font(.ui(20, weight: .semibold))
                .browsExactLineHeight(25)
                .multilineTextAlignment(.center)
            Color.clear.frame(height: 8)
            Text("The document may be damaged or password-protected.")
                .font(.ui(15))
                .browsExactLineHeight(20)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 322)
            Color.clear.frame(height: 22)
            Button("Try again") { filePickerPresented = true }
                .font(.ui(17, weight: .semibold))
                .foregroundStyle(.white)
                // size matches the mock
                .frame(width: 180, height: 48)
                // background fill 
                .background(Palette.brandInk, in: Capsule())
        }
        // fixed size from the design
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Spacing from the design
        .padding(.horizontal, 40)
        .accessibilityElement(children: .combine)
    }


    private let barCircle: CGFloat = 40
    private let barControl: CGFloat = 50
}

// MARK: - Helpers
extension DocumentView {
    /// Bottom bar matches `BrowserBottomBar` control sizes (40/50 glass circles, 48pt page pill).
    private func pdfBottomChrome(interactive: Bool) -> some View {
        HStack(spacing: 6) {
            iconCircle("square.grid.2x2", label: "Thumbnails", interactive: interactive) { thumbRailVisible.toggle() }
            Button {
                jumpDraft = "\(visiblePageIndex)"
                jump = true
            } label: {
                Text(interactive ? "Page \(visiblePageIndex) of \(loadedPdf?.pageCount ?? 0)" : "—")
                    .font(.ui(13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    // size matches the mock
                    .frame(maxWidth: .infinity)
                    // size matches the mock
                    .frame(height: 48)
                    .contentShape(Capsule())
            }
            .browsGlassButtonStyle()
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            // drawn on top of the content
            .overlay(Capsule().stroke(Color.primary.opacity(0.22), lineWidth: 1))
            .accessibilityIdentifier("pdf.page")
            .disabled(!interactive)
            if interactive, let loadedPdf, let shareBytes = loadedPdf.dataRepresentation() {
                ShareLink(item: shareBytes, preview: SharePreview(navCaption)) {
                    shareCircle
                }
                .browsGlassButtonStyle()
                .buttonBorderShape(.circle)
                .controlSize(.small)
                // fixed size from the design
                .frame(width: barControl, height: barControl)
                // drawn on top of the content
                .overlay(Circle().stroke(Color.primary.opacity(0.22), lineWidth: 1))
                .accessibilityLabel("Share")
            } else {
                shareCircle
                    .browsGlassButtonStyle()
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .frame(width: barControl, height: barControl)
                    // drawn on top of the content
                    .overlay(Circle().stroke(Color.primary.opacity(0.22), lineWidth: 1))
                    .accessibilityLabel("Share")
                    .allowsHitTesting(false) 
            }  
            Button {
                openAI()
            } label: {
                Image(systemName: "sparkles")
                    .font(.ui(16, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
                    // size matches the mock
                    .frame(width: barCircle, height: barCircle)
                    .contentShape(Circle())
            }
            .browsGlassProminentButtonStyle()
            .buttonBorderShape(.circle)
            .controlSize(.small)
            // Size matches the mock
            .frame(width: barControl, height: barControl)
            .tint(Palette.brandInk)
            .accessibilityLabel("Ask PDF")
            .disabled(!interactive || vault.incognito)
        }
        .opacity(interactive ? 1 : 0.4)
        // Breathing room
        .padding(.horizontal, 24)
        // breathing room
        .padding(.top, 8)
        // breathing room
        .padding(.bottom, 8)    
        // background goes behind everything
        .background(PDFColors.canvasView.ignoresSafeArea(edges: .bottom))
    }


    // Opens the document AI sheet unless the PDF is unreadable.
    // TODO(Aleksandra): page jump alert is numeric only, no way to jump by bookmark yet
    private func openAI() {
        presentedSheet = .ai
    }

    private var shareCircle: some View {
        Image(systemName: "square.and.arrow.up")
            .font(.ui(17, weight: .semibold))
            .foregroundStyle(.primary)
            // fixed size from the design
            .frame(width: barCircle, height: barCircle)
            .contentShape(Circle())
    }

    @ViewBuilder
    private func iconCircle(_ iconName: String, label: String, interactive: Bool, action: @escaping () -> Void) -> some View {
        // Plain button, styling comes from the modifiers
        Button(action: action) {
            Image(systemName: iconName)
                .font(.ui(17, weight: .semibold))
                .foregroundStyle(.primary) 
                // fixed size from the design
                .frame(width: barCircle, height: barCircle)
                .contentShape(Circle())
        }
        .browsGlassButtonStyle()
        .buttonBorderShape(.circle)
        .controlSize(.small)
        // Fixed size from the design
        .frame(width: barControl, height: barControl)
        .overlay(Circle().stroke(Color.primary.opacity(0.22), lineWidth: 1))
        .accessibilityLabel(label)
        .disabled(!interactive)
    }
    // fixture document
    private static func fixtureDocument() -> PDFDocument? {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 362, height: 506))
        // Style 
        func style(_ lineHeight: CGFloat, _ alignment: NSTextAlignment = .left) -> NSMutableParagraphStyle {
            let slot = NSMutableParagraphStyle()
            slot.minimumLineHeight = lineHeight
            slot.maximumLineHeight = lineHeight
            slot.alignment = alignment
            return slot
        }
        let faint = UIColor(red: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: 0.3)
        // work out the soft
        let soft = UIColor(red: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: 0.6)
        let ruleStroke = UIColor(red: 214 / 255, green: 226 / 255, blue: 220 / 255, alpha: 1)
        let grid = UIColor(red: 191 / 255, green: 191 / 255, blue: 191 / 255, alpha: 1)
        func draftText(
            _ slot: String, _ rect: CGRect, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor, lineHeight: CGFloat,
            alignment: NSTextAlignment = .left, kern: CGFloat? = nil, dy: CGFloat = 0, dx: CGFloat = 0
        ) {
            // The design sets text without SF dynamic tracking; cancel it so line breaks match.
            let tracking: CGFloat = kern ?? (size < 12 ? -0.12 : size < 20 ? -0.2 : 0)
            slot.draw(
                in: rect.offsetBy(dx: dx, dy: dy),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
                    .paragraphStyle: style(lineHeight, alignment), .kern: tracking,
                ])
        }
        let payloadBytes = renderer.pdfData { context in
            // one pass over the index items
            for index in 0..<48 {
                context.beginPage()
                draftText(
                    "SPECIALTY COFFEE ASSOCIATION   ·   STANDARD 2026", CGRect(x: 26, y: 26, width: 310, height: 12), size: 8,
                    weight: .semibold, color: faint, lineHeight: 12, kern: 0.28, dy: -0.6)
                let heading =
                    index == 11
                    ? "3.  Brewing"
                    : index == 12
                        ? "4.  Cupping protocol" : index == 0 ? "Brewing Standards 2026" : "\(index + 1).  Brewing standards"
                draftText(
                    heading, CGRect(x: 26, y: 48, width: 310, height: 21), size: 16, weight: .semibold, color: .black,
                    lineHeight: 21, kern: 0.3, dy: -0.6, dx: 0.3)
                guard index == 11 else { continue }
                ruleStroke.setFill()
                UIRectFill(CGRect(x: 26, y: 79, width: 310, height: 1))
                draftText(
                    "3.2  Water temperature", CGRect(x: 26, y: 94, width: 310, height: 15), size: 11, weight: .semibold,
                    color: .black, lineHeight: 15, dy: -0.9, dx: 0.5)
                draftText(
                    "The brew water shall be held between 195 °F and 205 °F (90.6 °C to 96.1 °C) throughout extraction. Water below this range under-extracts the bed and produces a thin, sour cup; water above it strips bitter compounds from the grounds.",
                    CGRect(x: 26, y: 115, width: 310, height: 60), size: 10, color: soft, lineHeight: 15, dy: -1.2)
                draftText(
                    "3.3  Brew ratio", CGRect(x: 26, y: 187, width: 310, height: 15), size: 11, weight: .semibold, color: .black,
                    lineHeight: 15, dy: -0.9, dx: 0.5)
                draftText(
                    "The reference ratio is 1 : 16 by mass — 60 g of ground coffee per litre of water — measured before brewing. Deviations of more than ±10 % shall be recorded in the cupping form.",
                    CGRect(x: 26, y: 208, width: 310, height: 45), size: 10, color: soft, lineHeight: 15, dy: -1.2)
                UIColor(red: 242 / 255, green: 245 / 255, blue: 243 / 255, alpha: 1).setFill()
                UIRectFill(CGRect(x: 26, y: 267.67, width: 310, height: 26))
                grid.setStroke()
                let table = UIBezierPath(rect: CGRect(x: 26.5, y: 268.17, width: 309, height: 106))
                table.lineWidth = 1
                table.stroke()
                grid.setFill()
                // Go through each row
                for row in 1...3 { UIRectFill(CGRect(x: 26, y: 267.67 + CGFloat(row) * 27 - 1, width: 310, height: 1)) }
                let rowBatch = [
                    ["Method", "Ratio", "Time"], ["Pour-over", "1 : 16", "3–4 min"], ["French press", "1 : 15", "4 min"],
                    ["Espresso", "1 : 2", "25–30 s"],
                ]
                for (r, cells) in rowBatch.enumerated() {
                    for (c, cell) in cells.enumerated() {
                        draftText(
                            cell, CGRect(x: 36 + CGFloat(c) * 96.67, y: 273 + CGFloat(r) * 27, width: 96.67, height: 14),
                            size: 9.5, weight: r == 0 ? .semibold : .regular, color: r == 0 ? .black : soft, lineHeight: 14,
                            alignment: c == 0 ? .left : .right, dy: 0.77) 
                    }
                } 
                draftText(
                    "Where equipment cannot hold the stated range, the deviation shall be declared in the report together with the measured value.",
                    CGRect(x: 26, y: 388, width: 310, height: 30), size: 10, color: soft, lineHeight: 15, dy: -1.2)
                draftText(
                    "12", CGRect(x: 26, y: 476, width: 310, height: 12), size: 9, color: faint, lineHeight: 12, alignment: .right,
                    dy: -0.3)
            }
        }
        guard let document = PDFDocument(data: payloadBytes) else { return nil }
        document.documentAttributes = [PDFDocumentAttribute.titleAttribute: "Brewing Standards 2026.pdf"]
        return document
    }
}


private final class PDFDocumentPayload: @unchecked Sendable {
    // document
    let document: PDFDocument?
    let archiveURL: URL?
    let byteCount: Int
    let archiveError: String?

    init(_ document: PDFDocument?, archiveURL: URL? = nil, byteCount: Int = 0, archiveError: String? = nil) {
        self.document = document
        self.archiveURL = archiveURL
        self.byteCount = byteCount
        self.archiveError = archiveError
    }
}

/// PDFKit wrapper; keeps page position while sheets animate.
struct NativePDFView: UIViewRepresentable {
    // keeps pdf document
    let pdfDocument: PDFDocument
    // injected state
    @Binding var pageNumber: Int
    var freezesPagePosition = false
    private static let fixtureScrollDelta: CGFloat = 63
    func makeUIView(context: Context) -> PDFView {
        let hostName = PDFView()
        hostName.document = pdfDocument
        hostName.displayMode = .singlePageContinuous
        hostName.backgroundColor = UIColor {
            $0.userInterfaceStyle == .dark
                ? .secondarySystemBackground : UIColor(red: 231 / 255, green: 239 / 255, blue: 235 / 255, alpha: 1)
        }
        if freezesPagePosition {
            hostName.autoScales = false
            hostName.scaleFactor = 1
            hostName.pageBreakMargins = UIEdgeInsets(top: 9, left: 0, bottom: 9, right: 0)
            hostName.pageOverlayViewProvider = context.coordinator.corners
        } else {
            hostName.autoScales = true
        }
        context.coordinator.freezesPagePosition = freezesPagePosition
        if let pdfLeaf = pdfDocument.page(at: pageNumber - 1) {
            context.coordinator.expectedPage = pageNumber
            DispatchQueue.main.async { [weak hostName] in
                hostName?.go(to: pdfLeaf)
                // DEBUG fixture: align the first page under the glass navigation bar like the design.
                if freezesPagePosition {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        guard
                            let scroll = hostName?.subviews.compactMap({ $0 as? UIScrollView }).first
                                ?? hostName?.subviews.flatMap({ $0.subviews }).compactMap({ $0 as? UIScrollView }).first
                        else { return }
                        scroll.contentOffset.y += Self.fixtureScrollDelta
                    }
                }
            }
        }
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged, object: hostName, queue: .main
        ) { [weak hostName] _ in
            MainActor.assumeIsolated {
                // host name must exist here
                guard let hostName, let pdfLeaf = hostName.currentPage, let document = hostName.document else { return }
                guard !context.coordinator.freezesPagePosition else { return }
                let index = document.index(for: pdfLeaf) + 1
                // optional expected page, may be missing
                if let expectedPage = context.coordinator.expectedPage {
                    guard index == expectedPage else { return }
                    context.coordinator.expectedPage = nil
                }
                context.coordinator.parent.pageNumber = index
            }
        }
        return hostName
    }
} 

// MARK: - NativePDFView helpers
extension NativePDFView {
    func updateUIView(_ hostName: PDFView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.freezesPagePosition = freezesPagePosition
        if hostName.document != pdfDocument { hostName.document = pdfDocument }
        // handle pdf leaf if it is there
        if let pdfLeaf = pdfDocument.page(at: pageNumber - 1), hostName.currentPage != pdfLeaf {
            context.coordinator.expectedPage = pageNumber
            DispatchQueue.main.async { [weak hostName] in hostName?.go(to: pdfLeaf) }
        }
    }
    // Dismantle ui view
    static func dismantleUIView(_ uiView: PDFView, coordinator: PDFScrollRelay) {
        // Only when there is a observer
        if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
        coordinator.observer = nil
    }
    func makeCoordinator() -> PDFScrollRelay { PDFScrollRelay(self) }
    /// Rounds the page corners (radius 6) by covering the square corners with the canvas colour.
    final class RoundedCornersView: UIView {
        private let shape = CAShapeLayer()
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            shape.fillRule = .evenOdd
            layer.addSublayer(shape)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() {
            super.layoutSubviews()
            let path = UIBezierPath(rect: bounds)
            path.append(UIBezierPath(roundedRect: bounds, cornerRadius: 6))
            shape.frame = bounds
            shape.path = path.cgPath
            shape.fillColor = UIColor(red: 231 / 255, green: 239 / 255, blue: 235 / 255, alpha: 1).cgColor
        }
    }  
    final class CornersProvider: NSObject, PDFPageOverlayViewProvider {
        func pdfView(_ hostName: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            MainActor.assumeIsolated { RoundedCornersView() }
        }
    }
    final class PDFScrollRelay {
        let corners = CornersProvider()
        var parent: NativePDFView
        var observer: NSObjectProtocol?
        var expectedPage: Int?
        var freezesPagePosition = false
        init(_ parent: NativePDFView) { self.parent = parent }
    }
}

/// Thumbnails sheet.
struct PDFThumbnails: View {
    // keeps pdf document
    let pdfDocument: PDFDocument
    @Binding var visiblePageIndex: Int
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // one row per element
                ForEach(0..<pdfDocument.pageCount, id: \.self) { index in
                    // handle pdf leaf if it is there
                    if let pdfLeaf = pdfDocument.page(at: index) {
                        Button {
                            self.visiblePageIndex = index + 1
                        } label: {
                            VStack {
                                Image(uiImage: pdfLeaf.thumbnail(of: CGSize(width: 100, height: 140), for: .mediaBox)).resizable()
                                    .scaledToFit().overlay(
                                        Rectangle().stroke(
                                            visiblePageIndex == index + 1 ? Palette.brandInk : .clear, lineWidth: 2))
                                Text("\(index + 1)").font(.caption)
                            }.padding(8)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.background(Palette.groupedFill)
    }
}

private enum PDFColors {
    // canvas view
    static let canvasView = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? .secondarySystemBackground : UIColor(red: 231 / 255, green: 239 / 255, blue: 235 / 255, alpha: 1)    
        })
}
