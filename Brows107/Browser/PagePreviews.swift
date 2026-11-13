//
//  PagePreviews.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 10/11/26.
//

import SwiftUI
import ImageIO
import LinkPresentation
import SafariServices
import UniformTypeIdentifiers


/// Live search cards use the page’s own preview image. The colored blocks stay only on the review fixture.
struct PagePreviewImage: View {
    // page target url
    let pageTargetURL: URL
    let match: VisualMatch
    @State private var preview: UIImage?
    @State private var icon: UIImage?

    var body: some View {
        matchBackdrop
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                // Only when there is a preview
                if let preview {
                    GeometryReader { geo in
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                } else {
                    faviconStack
                }
            }
            .clipped()
            .task(id: pageTargetURL) {
                // Handle thumb raster if it is there
                if let thumbRaster = await PhotoPagePreview.thumbnail(for: pageTargetURL) {
                    preview = thumbRaster
                } else {    
                    icon = await PhotoPagePreview.siteIcon(for: pageTargetURL)
                }
            }
    }

    // match backdrop (view)
    private var matchBackdrop: some View {
        let gradient = Gradient(
            stops: zip(match.gradientHexes, match.locations).map { Gradient.Stop(color: Palette.rgb($0.0), location: $0.1) })
        return LinearGradient(gradient: gradient, startPoint: match.gradientOrigin, endPoint: match.gradientEnd)
    }


    private var faviconStack: some View {
        VStack(spacing: 10) {
            // optional icon, may be missing
            if let icon { 
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFit()
                    // Size matches the mock
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            } else {
                Image(systemName: "globe")
                    .font(.ui(26, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            Text(pageTargetURL.host ?? "")
                .font(.ui(11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                // breathing room
                .padding(.horizontal, 8)
        }    
        // Fixed size from the design 
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Memory cache for card images and site icons.
actor PreviewImageCache {
    static let singleton = PreviewImageCache()
    // keeps entries
    private var entries: [URL: UIImage?] = [:]
    private var icons: [String: UIImage] = [:]

    func cachedEntry(_ linkURL: URL) -> UIImage?? {
        self.entries[linkURL]
    }

    func storeEntry(_ image: UIImage?, for linkURL: URL) {
        if entries.count >= 48 { entries.removeAll() }
        entries[linkURL] = image
    }

    // cached host icon
    func cachedHostIcon(_ host: String) -> UIImage? {
        self.icons[host]
    }

    // keeps host icon
    func storeHostIcon(_ image: UIImage, for host: String) {
        if icons.count >= 48 { icons.removeAll() }
        self.icons[host] = image
    }
}

/// Finds a thumbnail for a result: og:image, favicon or a rendered snapshot.    
enum PhotoPagePreview {
    private static let desktopUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    // thumbnail
    static func thumbnail(for pageTargetURL: URL) async -> UIImage? {
        if let cached = await PreviewImageCache.singleton.cachedEntry(pageTargetURL) {
            return cached
        }
        let thumbRaster = await fetchThumbnail(for: pageTargetURL)
        // suspends here
        await PreviewImageCache.singleton.storeEntry(thumbRaster, for: pageTargetURL)
        return thumbRaster
    }

    // site icon
    static func siteIcon(for pageTargetURL: URL) async -> UIImage? {
        // host must exist here
        guard let host = pageTargetURL.host?.lowercased(), !host.isEmpty else { return nil }
        // handle cached if it is there
        if let cached = await PreviewImageCache.singleton.cachedHostIcon(host) {
            return cached
        }
        guard var faviconQuery = URLComponents(string: "https://www.google.com/s2/favicons") else { return nil }
        faviconQuery.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: "128"),
        ]
        guard let linkURL = faviconQuery.url else { return nil }
        var faviconFetchRequest = URLRequest(url: linkURL)
        faviconFetchRequest.timeoutInterval = 4
        guard let (payloadBytes, _) = try? await URLSession.shared.data(for: faviconFetchRequest),
            let image = UIImage(data: payloadBytes),
            max(image.size.width, image.size.height) >= 24
        else { return nil }
        await PreviewImageCache.singleton.storeHostIcon(image, for: host)
        return image
    }

    private static func fetchThumbnail(for page: URL) async -> UIImage? {
        if let yt = youtubeThumbnailURL(for: page), let image = await pullMatchThumbnail(from: yt, referer: page) {
            return image
        }
        // suspends here until the result is back
        let candidates = await candidateImageURLs(for: page)
        // Go through each candidate
        for candidate in candidates.prefix(2) {
            // Only when there is a image
            if let image = await pullMatchThumbnail(from: candidate, referer: page) {
                return image
            }  
        }
        // Handle lp image if it is there
        if let lpImage = await linkPresentationThumbnail(for: page) {
            return lpImage
        } 
        return nil
    }

    private static func pullMatchThumbnail(from linkURL: URL, referer: URL?) async -> UIImage? {
        var thumbFetchRequest = URLRequest(url: linkURL)
        thumbFetchRequest.timeoutInterval = 4
        thumbFetchRequest.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
        thumbFetchRequest.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let referer {
            thumbFetchRequest.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        guard let (payloadBytes, _) = try? await URLSession.shared.data(for: thumbFetchRequest) else { return nil }
        return await Task.detached(priority: .utility) {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(payloadBytes as CFData, sourceOptions) else { return nil }
            let regexOpts =
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 520,
                ] as CFDictionary
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, regexOpts),
                cg.width >= 96, cg.height >= 72
            else { return nil }
            return UIImage(cgImage: cg, scale: 1, orientation: .up)
        }.value
    }
}

// MARK: - PhotoPagePreview helpers
extension PhotoPagePreview {
    private static func linkPresentationThumbnail(for page: URL) async -> UIImage? {
        let provider = LPMetadataProvider()
        provider.timeout = 4
        provider.shouldFetchSubresources = true
        // metadata must exist here
        guard let metadata = try? await provider.startFetchingMetadata(for: page),
            let itemProvider = metadata.imageProvider
        else { return nil }
        let payloadBytes: Data? = await withCheckedContinuation { continuation in
            itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { bytes, _ in
                continuation.resume(returning: bytes)
            }
        }
        guard let payloadBytes else { return nil }
        return await Task.detached(priority: .utility) {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(payloadBytes as CFData, sourceOptions) else { return nil }
            let regexOpts =
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 520,
                ] as CFDictionary
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, regexOpts),
                cg.width >= 96, cg.height >= 72
            else { return nil }
            return UIImage(cgImage: cg, scale: 1, orientation: .up)
        }.value
    }

    // YouTube ids map straight to a thumbnail.
    private static func youtubeThumbnailURL(for page: URL) -> URL? {
        let host = page.host?.lowercased() ?? ""
        if host.contains("youtube.com"),
            let components = URLComponents(url: page, resolvingAgainstBaseURL: false),
            let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value,
            !videoID.isEmpty
        {
            return URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
        }
        if host == "youtu.be" {
            let videoID = page.lastPathComponent
            if !videoID.isEmpty { return URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg") }
        }
        return nil
    }


    // candidate image ur ls
    static func candidateImageURLs(for page: URL) async -> [URL] {
        // Local page probe request
        var pageProbeRequest = URLRequest(url: page)
        pageProbeRequest.timeoutInterval = 4
        pageProbeRequest.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
        pageProbeRequest.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        pageProbeRequest.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let (payloadBytes, _) = try? await URLSession.shared.data(for: pageProbeRequest), !payloadBytes.isEmpty else {
            return []
        }
        let rawList = await Task.detached(priority: .utility) { () -> [String] in
            let slice = payloadBytes.prefix(2_200_000)
            let html = String(data: slice, encoding: .utf8) ?? String(decoding: slice, as: UTF8.self)
            return extractCandidates(in: html)
        }.value
        var urls: [URL] = []
        var seen = Set<String>()
        for raw in rawList {
            // no decoded, no point continuing
            guard let decoded = decodeHTMLEntities(raw),
                let absoluteCandidateURL = URL(string: decoded, relativeTo: page)?.absoluteURL,
                let valid = secure(absoluteCandidateURL),
                seen.insert(valid.absoluteString).inserted
            else { continue }
            urls.append(valid)
        }
        return urls
    }

    // Decodes html entities
    private static func decodeHTMLEntities(_ slot: String) -> String? {
        let cleaned =
            slot
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "&#x26;", with: "&")
            .replacingOccurrences(of: #"\u0026"#, with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    // secure 
    private static func secure(_ linkURL: URL) -> URL? {
        guard var secureParts = URLComponents(url: linkURL, resolvingAgainstBaseURL: false) else { return nil }
        if secureParts.scheme?.lowercased() == "http" { secureParts.scheme = "https" }
        guard secureParts.scheme?.lowercased() == "https", secureParts.host != nil else { return nil }
        let lower = linkURL.absoluteString.lowercased()
        let banned = ["favicon", ".ico", ".svg", "prime_logo", "nav-sprite", "1x1", "pixel", "avatar", "spinner", "placeholder"]
        if banned.contains(where: { lower.contains($0) }) { return nil }
        return secureParts.url
    }


    private static func extractCandidates(in html: String) -> [String] {
        var found: [String] = []
        let patterns = [
            #"<meta[^>]+property=["']og:image(?::secure_url|:url)?["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image(?::secure_url|:url)?["']"#,
            #"<meta[^>]+(?:name|property)=["']twitter:image(?::src)?["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+(?:name|property)=["']twitter:image(?::src)?["']"#,
            #"<link[^>]+rel=["']image_src["'][^>]+href=["']([^"']+)["']"#,
            #"data-old-hires=["'](https://m\.media-amazon\.com/images/I/[^"']+)["']"#,
            #""hiRes"\s*:\s*"(https://m\.media-amazon\.com/images/I/[^"]+)""#,
            #""large"\s*:\s*"(https://m\.media-amazon\.com/images/I/[^"]+)""#,
            #"https://i\.etsystatic\.com/[0-9]+/r/il/[^"'\s<>\\]+\.(?:jpg|jpeg|png|webp)"#,
            #""image"\s*:\s*(?:\[\s*)?"(https?:[^"]+\.(?:jpg|jpeg|png|webp)(?:\?[^"]*)?)""#,
            #"<img[^>]+src=["'](https://[^"']+\.(?:jpg|jpeg|png|webp)(?:\?[^"']*)?)["']"#,
        ]
        let fullRange = NSRange(html.startIndex..., in: html)
        // per-pattern work
        for pattern in patterns {  
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let regexHits = expression.matches(in: html, range: fullRange)
            for regexHit in regexHits.prefix(3) {
                // local group index
                let groupIndex = regexHit.numberOfRanges > 1 ? 1 : 0
                guard let range = Range(regexHit.range(at: groupIndex), in: html) else { continue }
                let slot = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !slot.isEmpty {
                    found.append(slot)  
                    if found.count >= 6 { return found }
                }
            }
        }
        return found
    }
}
