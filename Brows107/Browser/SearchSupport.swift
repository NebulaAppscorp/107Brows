//
//  SearchSupport.swift 
//  Brows107
//
//  Created by Aleksandra Savchuk on 04/10/26.
//

import SwiftUI
import UIKit


struct SearchSuggestionRow: Identifiable, Equatable, Sendable { 
    let head: String
    let tail: String
    var id: String { head + tail }
    var fullText: String { head + tail }

    var attributedLabel: AttributedString {
        var result = AttributedString(head)
        result.foregroundColor = .primary
        if !tail.isEmpty {
            var suffix = AttributedString(tail)
            suffix.foregroundColor = .secondary
            result.append(suffix)
        }
        return result
    }
}

struct IndexedSavedPage: Identifiable, Equatable {
    // id
    let id: UUID
    let headingText: String
    let urlString: String
    let subtitle: String
    let lowercasedTitle: String
    let lowercasedURL: String


    @MainActor
    private static let relativeFormatter: RelativeDateTimeFormatter = { 
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric
        return formatter
    }()


    @MainActor
    init(page: SavedPage) {
        self.id = page.id
        self.headingText = page.pageTitle
        self.urlString = page.pageURL.absoluteString
        self.lowercasedTitle = page.pageTitle.lowercased()
        self.lowercasedURL = page.pageURL.absoluteString.lowercased()
        let host = page.pageURL.host ?? ""
        let relative = Self.relativeFormatter.localizedString(for: page.recordedAt, relativeTo: .now)
        self.subtitle = "\(host) · Visited \(relative)"
    }
}

/// Fetches and caches search suggestions.
actor GoogleSuggestions {
    static let shared = GoogleSuggestions()


    private let session: URLSession
    private var cache: [String: [SearchSuggestionRow]] = [:]

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 4
        config.urlCache = nil
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config)
    }

    // Cached it
    func cached(for query: String) -> [SearchSuggestionRow]? {
        self.cache[query.lowercased()]
    }

    // fetches it
    func fetch(_ query: String) async -> [SearchSuggestionRow] {
        let key = query.lowercased()
        // Only when there is a existing
        if let existing = cache[key] { return existing }
        var suggestQuery = URLComponents(string: "https://suggestqueries.google.com/complete/search")
        suggestQuery?.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "q", value: query),
        ]
        // Need link url to go on
        guard let linkURL = suggestQuery?.url else { return [] }
        var request = URLRequest(url: linkURL)
        request.timeoutInterval = 3
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        guard let (payloadBytes, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let suggestPayload = try? JSONSerialization.jsonObject(with: payloadBytes) as? [Any],
            suggestPayload.count > 1, let suggestions = suggestPayload[1] as? [String]
        else { return [] }
        let rowBatch = suggestions.compactMap { suggestion -> SearchSuggestionRow? in
            let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.compare(query, options: .caseInsensitive) != .orderedSame else { return nil }    
            if trimmed.lowercased().hasPrefix(key) {
                return SearchSuggestionRow(
                    head: String(trimmed.prefix(query.count)),
                    tail: String(trimmed.dropFirst(query.count))
                )
            }  
            return SearchSuggestionRow(head: trimmed, tail: "")
        }
        .prefix(8)
        .map { $0 }

        if cache.count >= 64 { cache.removeAll() }
        self.cache[key] = rowBatch
        return rowBatch
    }
}
