//
//  PersistenceModels.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 24/10/26.
//

import Foundation
import UIKit

/// A tab in the strip; thumbnails live in TabPreviewStore.
struct BrowserTab: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var pageTitle = "New Tab"
    var pageURL: URL?
    var incognitoTab = false
    /// Bumped on every navigate; the web view reloads only when this changes, not on in-page navigation.
    var reloadToken = 0

    private enum CodingKeys: String, CodingKey {
        case stableID = "id"
        case pageTitle = "title"
        case pageURL = "url"
        case incognitoTab = "isPrivate"
        case reloadToken = "loadRevision"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageTitle = try container.decode(String.self, forKey: .pageTitle)
        id = try container.decode(UUID.self, forKey: .stableID)
        reloadToken = try container.decodeIfPresent(Int.self, forKey: .reloadToken) ?? 0
        pageURL = try container.decodeIfPresent(URL.self, forKey: .pageURL)
        incognitoTab = try container.decodeIfPresent(Bool.self, forKey: .incognitoTab) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pageTitle, forKey: .pageTitle)
        try container.encode(id, forKey: .stableID)
        try container.encode(incognitoTab, forKey: .incognitoTab)
        try container.encode(reloadToken, forKey: .reloadToken)
        try container.encodeIfPresent(pageURL, forKey: .pageURL)
    }

    init(id: UUID = UUID(), pageTitle: String = "New Tab", pageURL: URL? = nil, incognitoTab: Bool = false, reloadToken: Int = 0)
    {
        self.id = id
        self.pageTitle = pageTitle
        self.pageURL = pageURL
        self.incognitoTab = incognitoTab
        self.reloadToken = reloadToken
    }
}

/// Bookmark / history entry.
struct SavedPage: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var pageTitle: String
    var pageURL: URL
    var recordedAt = Date()
    var shelfLabel: String?

    private enum CodingKeys: String, CodingKey {
        case stableID = "id"
        case pageTitle = "title"
        case pageURL = "url"
        case shelfLabel = "folder"
        case recordedAt = "date"
    }

    init(id: UUID = UUID(), pageTitle: String, pageURL: URL, recordedAt: Date = .now, shelfLabel: String? = nil) {
        self.id = id
        self.pageTitle = pageTitle
        self.pageURL = pageURL
        self.recordedAt = recordedAt
        self.shelfLabel = shelfLabel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .stableID)
        pageTitle = try container.decode(String.self, forKey: .pageTitle)
        pageURL = try container.decode(URL.self, forKey: .pageURL)
        recordedAt = try container.decodeIfPresent(Date.self, forKey: .recordedAt) ?? .now
        shelfLabel = try container.decodeIfPresent(String.self, forKey: .shelfLabel)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .stableID)
        try container.encode(pageTitle, forKey: .pageTitle)
        try container.encode(pageURL, forKey: .pageURL)
        try container.encode(recordedAt, forKey: .recordedAt)
        try container.encodeIfPresent(shelfLabel, forKey: .shelfLabel)
    }
}

/// One bubble in a conversation.
struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var messageBody: String
    var fromVisitor: Bool
    var citationPages: [SavedPage] = []
    var inlinePhotoBytes: Data?

    private enum CodingKeys: String, CodingKey {
        case stableID = "id"
        case messageBody = "text"
        case citationPages = "sources"
        case fromVisitor = "isUser"
        case inlinePhotoBytes = "imageData"
    }

    init(
        id: UUID = UUID(), messageBody: String, fromVisitor: Bool, citationPages: [SavedPage] = [], inlinePhotoBytes: Data? = nil
    ) {
        self.id = id
        self.messageBody = messageBody
        self.fromVisitor = fromVisitor
        self.citationPages = citationPages
        self.inlinePhotoBytes = inlinePhotoBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .stableID)
        messageBody = try container.decode(String.self, forKey: .messageBody)
        fromVisitor = try container.decode(Bool.self, forKey: .fromVisitor)
        citationPages = try container.decodeIfPresent([SavedPage].self, forKey: .citationPages) ?? []
        inlinePhotoBytes = try container.decodeIfPresent(Data.self, forKey: .inlinePhotoBytes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .stableID)
        try container.encode(messageBody, forKey: .messageBody)
        try container.encode(fromVisitor, forKey: .fromVisitor)
        try container.encode(citationPages, forKey: .citationPages)
        try container.encodeIfPresent(inlinePhotoBytes, forKey: .inlinePhotoBytes)
    }
}

/// A saved chat thread.
struct Conversation: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var threadTitle: String
    var threadStamp = Date()
    var threadTurns: [ChatMessage] = []
    var remoteChatID: String?

    private enum CodingKeys: String, CodingKey {
        case stableID = "id"
        case threadTitle = "title"
        case remoteChatID = "remoteID"
        case threadTurns = "messages"
        case threadStamp = "date"
    }

    init(
        id: UUID = UUID(), threadTitle: String, threadStamp: Date = .now, threadTurns: [ChatMessage] = [],
        remoteChatID: String? = nil
    ) {
        self.id = id
        self.threadTitle = threadTitle
        self.threadStamp = threadStamp
        self.threadTurns = threadTurns
        self.remoteChatID = remoteChatID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .stableID)
        threadTitle = try container.decode(String.self, forKey: .threadTitle)
        threadStamp = try container.decodeIfPresent(Date.self, forKey: .threadStamp) ?? .now
        threadTurns = try container.decodeIfPresent([ChatMessage].self, forKey: .threadTurns) ?? []
        remoteChatID = try container.decodeIfPresent(String.self, forKey: .remoteChatID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .stableID)
        try container.encode(threadTitle, forKey: .threadTitle)
        try container.encode(threadStamp, forKey: .threadStamp)
        try container.encode(threadTurns, forKey: .threadTurns)
        try container.encodeIfPresent(remoteChatID, forKey: .remoteChatID)
    }
}
/// A file in Downloads, including paused state.
struct DownloadItem: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var assetLabel: String
    var diskFileURL: URL?
    var byteSizeLabel: String
    var transferProgress: Double = 1
    var transferFailed = false
    var transferPaused = false
    /// Shown as «1.2 MB of 2.4 MB» while a download is running or paused.
    var bytesReceivedDisplay: String?
    var bytesTotalDisplay: String?
    var etaSeconds: Int?
    var downloadedAt: Date? = .now

    var downloadInFlight: Bool { transferProgress < 1 && !transferFailed }

    private enum CodingKeys: String, CodingKey {
        case stableID = "id"
        case byteSizeLabel = "size"
        case transferProgress = "progress"
        case transferPaused = "paused"
        case assetLabel = "name"
        case diskFileURL = "localURL"
        case transferFailed = "failed"
        case bytesReceivedDisplay, bytesTotalDisplay, etaSeconds, downloadedAt
    }

    init(
        id: UUID = UUID(),
        assetLabel: String,
        diskFileURL: URL? = nil,
        byteSizeLabel: String,
        transferProgress: Double = 1,
        transferFailed: Bool = false,
        transferPaused: Bool = false,
        bytesReceivedDisplay: String? = nil,
        bytesTotalDisplay: String? = nil,
        etaSeconds: Int? = nil,
        downloadedAt: Date? = .now
    ) {
        self.id = id
        self.assetLabel = assetLabel
        self.diskFileURL = diskFileURL
        self.byteSizeLabel = byteSizeLabel
        self.transferProgress = transferProgress
        self.transferFailed = transferFailed
        self.transferPaused = transferPaused
        self.bytesReceivedDisplay = bytesReceivedDisplay
        self.bytesTotalDisplay = bytesTotalDisplay
        self.etaSeconds = etaSeconds
        self.downloadedAt = downloadedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .stableID)
        assetLabel = try container.decode(String.self, forKey: .assetLabel)
        diskFileURL = try container.decodeIfPresent(URL.self, forKey: .diskFileURL)
        byteSizeLabel = try container.decode(String.self, forKey: .byteSizeLabel)
        transferProgress = try container.decodeIfPresent(Double.self, forKey: .transferProgress) ?? 1
        transferFailed = try container.decodeIfPresent(Bool.self, forKey: .transferFailed) ?? false
        transferPaused = try container.decodeIfPresent(Bool.self, forKey: .transferPaused) ?? false
        bytesReceivedDisplay = try container.decodeIfPresent(String.self, forKey: .bytesReceivedDisplay)
        bytesTotalDisplay = try container.decodeIfPresent(String.self, forKey: .bytesTotalDisplay)
        etaSeconds = try container.decodeIfPresent(Int.self, forKey: .etaSeconds)
        downloadedAt = try container.decodeIfPresent(Date.self, forKey: .downloadedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .stableID)
        try container.encode(assetLabel, forKey: .assetLabel)
        try container.encodeIfPresent(diskFileURL, forKey: .diskFileURL)
        try container.encode(byteSizeLabel, forKey: .byteSizeLabel)
        try container.encode(transferProgress, forKey: .transferProgress)
        try container.encode(transferFailed, forKey: .transferFailed)
        try container.encode(transferPaused, forKey: .transferPaused)
        try container.encodeIfPresent(bytesReceivedDisplay, forKey: .bytesReceivedDisplay)
        try container.encodeIfPresent(bytesTotalDisplay, forKey: .bytesTotalDisplay)
        try container.encodeIfPresent(etaSeconds, forKey: .etaSeconds)
        try container.encodeIfPresent(downloadedAt, forKey: .downloadedAt)
    }

    // «1.2 MB of 2.4 MB» style line under the file name.
    func statusSubtitle() -> String {
        if transferPaused, let received = bytesReceivedDisplay, let total = bytesTotalDisplay {
            return "Paused · \(received) of \(total)"
        }
        if downloadInFlight, let received = bytesReceivedDisplay, let total = bytesTotalDisplay {
            if let eta = etaSeconds {
                return "\(received) of \(total) · \(eta) s left"
            }
            return "\(received) of \(total)"
        }
        return byteSizeLabel
    }
}

/// Every sheet the root view can present.
enum ModalRoute: String, Identifiable {
    case tabs, library, settings, camera, visualMatches = "matches", downloads, protection, ai, chats, models, pdf, site, search,
        menu
    var id: String { rawValue }
}

enum UpdateNotice { case soft, force }

/// JPEG bytes plus mime type for the upload.
final class ImagePayload: @unchecked Sendable {
    let bitmap: UIImage

    init(_ bitmap: UIImage) {
        self.bitmap = bitmap
    }
}
