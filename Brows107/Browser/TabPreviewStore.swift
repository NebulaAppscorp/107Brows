//
//  TabPreviewStore.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 07/11/26.
//

import SwiftUI
import UIKit

@MainActor @Observable final class TabPreviewStore {
    static let singleton = TabPreviewStore()

    private(set) var tabThumbnails: [UUID: UIImage] = [:]

    // Thumb for tab
    func thumbForTab(_ id: UUID) -> UIImage? { tabThumbnails[id] }

    // keeps thumb
    func storeThumb(_ image: UIImage, for id: UUID) {
        let thumbPixelExtent = CGSize(width: 360, height: 480)
        let thumbRaster = image.preparingThumbnail(of: thumbPixelExtent) ?? image
        tabThumbnails[id] = thumbRaster
    }

    // drops thumb
    func dropThumb(for id: UUID) {
        tabThumbnails.removeValue(forKey: id)
    }
}

/// Placeholder thumbnails for tabs that have not rendered yet.
enum TabPageSnapshot {
    // works out placeholder thumb
    static func resolvePlaceholderThumb(for linkURL: URL) async -> UIImage? {
        guard let host = linkURL.host?.lowercased(), !host.isEmpty else { return nil }
        if let og = await openGraphPreview(linkURL) { return og }
        return await googleFaviconBitmap(host: host)
    }

    // favicon for page
    static func faviconForPage(_ linkURL: URL) async -> UIImage? {
        guard let host = linkURL.host?.lowercased(), !host.isEmpty else { return nil }
        return await googleFaviconBitmap(host: host)
    }

    // og:image from the page head.
    private static func openGraphPreview(_ page: URL) async -> UIImage? {
        var thumbFetchRequest = URLRequest(url: page)
        thumbFetchRequest.timeoutInterval = 5
        thumbFetchRequest.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (payloadBytes, response) = try? await URLSession.shared.data(for: thumbFetchRequest),
            let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
            let html = String(data: payloadBytes, encoding: .utf8) ?? String(data: payloadBytes, encoding: .isoLatin1)
        else { return nil }
        guard let imageURL = extractOGImage(from: html, base: page) else { return nil }
        return await fetchRemoteThumb(imageURL, referer: page)
    }

    private static func extractOGImage(from html: String, base: URL) -> URL? {
        let patterns = [
            #"property=["']og:image["'][^>]*content=["']([^"']+)["']"#,
            #"content=["']([^"']+)["'][^>]*property=["']og:image["']"#,
            #"<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let htmlScanRange = NSRange(html.startIndex..., in: html)
            guard let match = regex.firstMatch(in: html, options: [], range: htmlScanRange),
                match.numberOfRanges > 1,
                let r = Range(match.range(at: 1), in: html)
            else { continue }
            let hrefToken = String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let absolute = URL(string: hrefToken, relativeTo: base)?.absoluteURL { return absolute }
        }
        return nil
    }

    // fetches remote thumb
    private static func fetchRemoteThumb(_ linkURL: URL, referer: URL) async -> UIImage? {
        var thumbFetchRequest = URLRequest(url: linkURL)
        thumbFetchRequest.timeoutInterval = 5
        thumbFetchRequest.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        guard let (payloadBytes, _) = try? await URLSession.shared.data(for: thumbFetchRequest),
            let thumbBitmap = UIImage(data: payloadBytes),
            max(thumbBitmap.size.width, thumbBitmap.size.height) > 32
        else { return nil }
        return thumbBitmap
    }

    private static func googleFaviconBitmap(host: String) async -> UIImage? {
        let faviconEndpoint = faviconServiceURL(host: host)
        guard let linkURL = faviconEndpoint else { return nil }
        var thumbFetchRequest = URLRequest(url: linkURL)
        thumbFetchRequest.timeoutInterval = 4
        let payloadPair = try? await URLSession.shared.data(for: thumbFetchRequest)
        guard let payloadBytes = payloadPair?.0 else { return nil }
        return UIImage(data: payloadBytes)
    }

    // favicon service url
    private static func faviconServiceURL(host: String) -> URL? {
        guard var faviconQuery = URLComponents(string: "https://www.google.com/s2/favicons") else { return nil }
        faviconQuery.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: "128"),
        ]
        return faviconQuery.url
    }
}
