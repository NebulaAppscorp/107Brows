//
//  RecentPhotos.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 05/11/26.
//

import SwiftUI
import PhotosUI
import AVFoundation
import ImageIO


/// Metadata for a photo kept in Recent.
struct RecentPhoto: Identifiable, Codable, Sendable {
    let id: UUID
    let capturedAt: Date
    var prompt: String?
    var answerText: String?
    var savedPages: [SavedPage]?
    var searchPhase: String?

    // Keys are fixed so photos saved by earlier builds still decode.
    private enum CodingKeys: String, CodingKey {
        case id
        case capturedAt = "b107CapturedAt"
        case prompt = "b107Question"
        case answerText = "b107AnswerText"
        case savedPages = "b107SavedPages"
        case searchPhase = "b107SearchPhase"
    }
}

/// Recent photos on disk: a jpg plus a json sidecar.
enum RecentPhotoStore {
    private static var recentPhotoDir: URL {
        let supportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("recent-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportRoot, withIntermediateDirectories: true)
        return supportRoot
    }

    static func listRecentPhotos() -> [RecentPhoto] {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: recentPhotoDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.compactMap { linkURL -> RecentPhoto? in
            guard linkURL.pathExtension == "jpg", let id = UUID(uuidString: linkURL.deletingPathExtension().lastPathComponent)
            else { return nil }
            let date =
                (try? linkURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let metadataURL = recentPhotoDir.appendingPathComponent("\(id.uuidString).json")
            if let data = try? Data(contentsOf: metadataURL), let record = try? JSONDecoder().decode(RecentPhoto.self, from: data)
            {
                return record
            }
            return RecentPhoto(id: id, capturedAt: date, prompt: nil, answerText: nil, savedPages: nil, searchPhase: nil)
        }
        .sorted { $0.capturedAt > $1.capturedAt }
    }

    // saves photo result
    static func savePhotoResult(
        _ bitmap: UIImage, id: UUID, question: String, answer: String?, pages: [SavedPage], phase: VisualSearchState
    ) async {
        let rasterEnvelope = ImagePayload(bitmap)
        let record = RecentPhoto(
            id: id, capturedAt: .now, prompt: question.isEmpty ? nil : question, answerText: answer, savedPages: pages,
            searchPhase: phase.rawValue)
        await Task.detached(priority: .utility) {
            let shotScratchDir = recentPhotoDir
            let imageURL = shotScratchDir.appendingPathComponent("\(id.uuidString).jpg")
            let metadataURL = shotScratchDir.appendingPathComponent("\(id.uuidString).json")
            guard let payloadBytes = rasterEnvelope.bitmap.jpegData(compressionQuality: 0.82) else { return }
            try? payloadBytes.write(to: imageURL, options: .atomic)
            if let data = try? JSONEncoder().encode(record) { try? data.write(to: metadataURL, options: .atomic) }
            for extra in listRecentPhotos().dropFirst(24) {
                try? FileManager.default.removeItem(at: shotScratchDir.appendingPathComponent("\(extra.id.uuidString).jpg"))
                try? FileManager.default.removeItem(at: shotScratchDir.appendingPathComponent("\(extra.id.uuidString).json"))
            }
        }.value
    }

    static func diskPhotoBitmap(_ recentShot: RecentPhoto) -> UIImage? {
        UIImage(contentsOfFile: recentPhotoDir.appendingPathComponent("\(recentShot.id.uuidString).jpg").path)
    }

    // loads recent photo async
    static func loadRecentPhotoAsync(_ recentShot: RecentPhoto) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { diskPhotoBitmap(recentShot) }.value
    }

    // removes recent photo
    static func deleteRecentPhoto(_ recentShot: RecentPhoto) {
        try? FileManager.default.removeItem(at: recentPhotoDir.appendingPathComponent("\(recentShot.id.uuidString).jpg"))
        try? FileManager.default.removeItem(at: recentPhotoDir.appendingPathComponent("\(recentShot.id.uuidString).json"))
    }

    static func deleteAllRecentPhotos() {
        let files = (try? FileManager.default.contentsOfDirectory(at: recentPhotoDir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "jpg" || file.pathExtension == "json" {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

struct RecentPhotosView: View {
    var onPick: (RecentPhoto, UIImage) -> Void
    @Environment(BrowserStore.self) private var vault
    @Environment(\.dismiss) private var dismissSheet
    @State private var recentShots: [RecentPhoto] = []
    @State private var confirmClearAll = false

    var body: some View {
        NavigationStack {
            Group {
                if vault.incognito {
                    empty(headingText: "Photo search is off", emptyBlurb: "Recent photos stay hidden in a private tab.")
                } else if recentShots.isEmpty {
                    empty(headingText: "No recent photos", emptyBlurb: "Photos you take or pick here show up in this list.")
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 12) {
                            ForEach(recentShots) { recentShot in
                                ZStack(alignment: .topTrailing) {
                                    Button {
                                        Task {
                                            guard let image = await RecentPhotoStore.loadRecentPhotoAsync(recentShot) else {
                                                return
                                            }
                                            await MainActor.run {
                                                onPick(recentShot, image)
                                                dismissSheet()
                                            }
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            RecentPhotoThumbnail(recentShot: recentShot)
                                            Text(recentShot.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.ui(12))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        deleteRecentPhoto(recentShot)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.ui(11, weight: .semibold))
                                            .foregroundStyle(Color(uiColor: .label))
                                            .frame(width: 26, height: 26)
                                            .background(.ultraThinMaterial, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                    .accessibilityLabel("Delete photo")
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvasView)
            .navigationTitle("Recent photos")
            .navigationBarTitleDisplayMode(.inline)
            .browsLiquidNavBar()
            // toolbar items
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismissSheet() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            confirmClearAll = true
                        } label: {
                            Label("Delete all recent photos", systemImage: "trash")
                        }
                        .tint(.red)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.ui(19, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .browsGlassCircle()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Recent photos menu")
                    .disabled(recentShots.isEmpty || vault.incognito)
                }
            }
            .task { recentShots = await Task.detached(priority: .utility) { RecentPhotoStore.listRecentPhotos() }.value }
            .confirmationDialog("Delete all recent photos?", isPresented: $confirmClearAll, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) { deleteAllRecentPhotos() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

// MARK: - Subviews
extension RecentPhotosView {
    // empty
    private func empty(headingText: String, emptyBlurb: String) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "clock")
                .font(.ui(28))
                .foregroundStyle(Palette.brandInk)
                .frame(width: 64, height: 64)
                // background goes behind everything
                .background(Palette.brandWash, in: Circle())
            Text(headingText)
                .font(.ui(20, weight: .semibold))
                .padding(.top, 18)
            Text(emptyBlurb)
                .font(.ui(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding(.horizontal, 32)
    }

    // removes recent photo
    private func deleteRecentPhoto(_ record: RecentPhoto) {
        recentShots.removeAll { $0.id == record.id }
        Task.detached(priority: .utility) { RecentPhotoStore.deleteRecentPhoto(record) }
    }

    // removes all recent photos
    private func deleteAllRecentPhotos() {
        recentShots.removeAll()
        Task.detached(priority: .utility) { RecentPhotoStore.deleteAllRecentPhotos() }
    }
}

struct RecentPhotoThumbnail: View {
    let recentShot: RecentPhoto
    // local UI state
    @State private var thumbBitmap: UIImage?

    var body: some View {
        Group {
            if let thumbBitmap {
                Image(uiImage: thumbBitmap)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12))
            }
        }
        .frame(height: 112)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // kicked off here so it cancels with the view
        .task(id: recentShot.id) { thumbBitmap = await RecentPhotoStore.loadRecentPhotoAsync(recentShot) }
    }
}
