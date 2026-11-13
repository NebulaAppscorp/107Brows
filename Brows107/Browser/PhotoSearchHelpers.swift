//
//  PhotoSearchHelpers.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 05/11/26.
//

import SwiftUI
import PhotosUI
import AVFoundation
import ImageIO


enum PhotoSearchJPEG {
    // Strips markdown and link noise from the model answer.
    static func cleanVisualAnswer(_ answer: String) -> String {  
        let guidancePhrases = [
            "use this service", "use the service", "try this service", "try this website", "use another website",
            "upload the photo", "upload this photo", "search manually", "search it yourself", "google lens", "tineye", "lenso.ai",
            "используйте этот сервис", "попробуйте этот сервис", "попробуйте этот сайт", "загрузите фото на",
            "ищите через этот сервис", "поищите на сайте",
        ]
        return
            answer
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                let normalized = line.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                return !guidancePhrases.contains(where: normalized.contains)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // Keeps only pages that look related to the question.
    static func filterVisualPages(_ pages: [SavedPage], question: String, answer: String) -> [SavedPage] {
        let guidanceTitles = [
            "product search by image", "image search", "search by image", "visual search", "reverse image", "photo search",
            "image lookup", "image-search", "search-by-image", "find it on ebay", "using photo", "how to", "how-to", "tutorial",
        ]
        let guidanceAddresses = [
            "lensapp.io", "coppedit.app", "innovation.ebayinc.co", "/image-search", "/visual-search", "/reverse-image",
            "/search-by-image", "/guides/", "/guide/", "/tutorial", "/how-to/",
        ]
        let normalizedQuestionAndAnswer = normalizeText(question + " " + answer)
        let categories: [([String], [String])] = [
            (
                ["doll", "кукл"],
                [
                    "doll", "кукл", "barbie", "bratz", "blythe", "monster high", "monster-high", "rainbow high", "rainbow-high",
                    "lol surprise", "lol-surprise",
                ]
            ),
            (
                ["sneaker", "shoe", "footwear", "кроссов", "обув", "туфл", "ботин"],
                ["sneaker", "shoe", "trainer", "boot", "heel", "footwear", "кроссов", "обув", "туфл", "ботин"]
            ),
            (["handbag", "purse", "bag", "сумк", "рюкзак"], ["handbag", "purse", "bag", "tote", "backpack", "сумк", "рюкзак"]),
            (["watch", "wristwatch", "час"], ["watch", "wristwatch", "час"]),
            (["smartphone", "phone", "iphone", "телефон"], ["smartphone", "phone", "iphone", "galaxy", "телефон"]),
            (["camera", "фотоаппарат", "камер"], ["camera", "фотоаппарат", "камер"]),
            (
                ["chair", "sofa", "furniture", "стул", "диван", "мебел"],
                ["chair", "sofa", "furniture", "стул", "диван", "мебел"]
            ),
            (["coffee", "espresso", "кофе"], ["coffee", "espresso", "кофе"]),
            (["lamp", "lighting", "ламп"], ["lamp", "lighting", "ламп"]),
            (
                ["jewelry", "jewellery", "ring", "necklace", "украш", "кольц"],
                ["jewelry", "jewellery", "ring", "necklace", "украш", "кольц"]
            ),
            (["book", "книг"], ["book", "книг"]),
        ]
        let categoryTerms = categories.first { signals, _ in signals.contains(where: normalizedQuestionAndAnswer.contains) }?.1
        return pages.filter { page in
            let title = normalizeText(page.pageTitle)
            let address = normalizeText(page.pageURL.absoluteString.removingPercentEncoding ?? page.pageURL.absoluteString)
            guard !guidanceTitles.contains(where: title.contains), !guidanceAddresses.contains(where: address.contains) else {
                return false
            }
            // nothing to do without this
            guard let categoryTerms else { return true }
            return categoryTerms.contains(where: title.contains) || categoryTerms.contains(where: address.contains)
        }
    }

    // Drops dead links with a quick HEAD request.
    static func verifyVisualPages(_ pages: [SavedPage]) async -> [SavedPage] {
        await withTaskGroup(of: (Int, SavedPage?).self) { group in
            for (index, page) in pages.prefix(6).enumerated() {
                group.addTask { (index, await verifyVisualPage(page)) }
            }
            var verified: [(Int, SavedPage)] = []
            for await (index, page) in group {
                if let page { verified.append((index, page)) }
            }
            return verified.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    // checks visual page
    private static func verifyVisualPage(_ page: SavedPage) async -> SavedPage? {
        guard ["http", "https"].contains(page.pageURL.scheme?.lowercased() ?? ""), page.pageURL.host != nil else { return nil }
        var request = URLRequest(url: page.pageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 7)
        request.httpMethod = "HEAD"
        request.setValue("107Brows/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            // guard first, work after
            guard let httpResponse = response as? HTTPURLResponse else { return page }
            if [404, 410].contains(httpResponse.statusCode) { return nil }
            guard (200..<400).contains(httpResponse.statusCode), let finalURL = response.url,
                ["http", "https"].contains(finalURL.scheme?.lowercased() ?? ""), finalURL.host != nil
            else { return page }
            return SavedPage(
                id: page.id, pageTitle: page.pageTitle, pageURL: finalURL, recordedAt: page.recordedAt,
                shelfLabel: page.shelfLabel)
        } catch {
            return page
        }
    }

    // normalize text 
    private static func normalizeText(_ value: String) -> String {
        value.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }


    // decodes downsampled  
    static func decodeDownsampled(payloadBytes: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(payloadBytes as CFData, sourceOptions) else { return nil }
        let downsampleOptions =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize),
            ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }

    // downsample for display
    static func downsampleForDisplay(_ image: UIImage, maxSide: CGFloat = 1600) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxSide || image.imageOrientation != .up else { return image }
        let ratio = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: max(1, round(pixelWidth * ratio)), height: max(1, round(pixelHeight * ratio)))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // data
    static func data(from image: UIImage) -> Data? {
        let maxSide: CGFloat = 1280
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        let ratio = longest > maxSide ? maxSide / longest : 1
        let size = CGSize(width: max(1, round(pixelWidth * ratio)), height: max(1, round(pixelHeight * ratio)))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: 0.84)
    }

    // cleaned query
    static func cleanedQuery(from raw: String) -> String {
        let firstLine =
            raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        let stripped =
            firstLine
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,:;!?-–—'"))
        return String(stripped.prefix(120))
    }

    // deduplicate
    static func deduplicate(_ items: [SavedPage]) -> [SavedPage] {
        var uniquePages: [SavedPage] = []
        var seen = Set<String>()
        for sourceEntry in items {
            let key = sourceEntry.pageURL.absoluteString.lowercased()
            guard seen.insert(key).inserted else { continue }
            uniquePages.append(sourceEntry)
            if uniquePages.count >= 12 { break }
        }
        return uniquePages
    }

    // Pulls URLs out of citations and the answer text.
    static func savedPagesFromReply(_ assistantPayload: AIReply) -> [SavedPage] {
        var parsedPages: [SavedPage] = []
        var seen = Set<String>()
        func add(_ headingText: String, _ linkURL: URL, requireDeepPath: Bool) {
            guard ["http", "https"].contains(linkURL.scheme?.lowercased() ?? ""), let host = linkURL.host, !host.isEmpty else {
                return
            }
            let path = linkURL.path
            let normalizedHost = host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)).lowercased() : host.lowercased()
            let searchToolHosts = [
                "tineye.com", "lenso.ai", "pimeyes.com", "searchbyimage.com", "reverseimagesearch.com", "lensapp.io",
                "coppedit.app", "innovation.ebayinc.co",
            ]
            guard !searchToolHosts.contains(where: { normalizedHost == $0 || normalizedHost.hasSuffix("." + $0) }),
                !normalizedHost.hasPrefix("google."),
                !normalizedHost.hasSuffix(".google.com"),
                !normalizedHost.hasPrefix("bing."),
                !normalizedHost.hasSuffix(".bing.com"),
                normalizedHost != "duckduckgo.com",
                !normalizedHost.hasSuffix(".duckduckgo.com")
            else { return }
            let normalizedPath = path.lowercased()
            let searchPathFragments = [
                "/search", "/images/search", "/visual-search", "/visual_search", "/reverse-image", "/reverse_image",
                "/search-by-image", "/search_by_image",
            ]
            guard !searchPathFragments.contains(where: { normalizedPath.contains($0) }) else { return }
            let queryKeys = Set(
                (URLComponents(url: linkURL, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { $0.name.lowercased() })
            guard queryKeys.isDisjoint(with: ["q", "query", "search_query", "image_url"]) else { return }
            let isRootOnly = (path.isEmpty || path == "/") && (linkURL.query ?? "").isEmpty
            if requireDeepPath && isRootOnly { return }
            let key = linkURL.absoluteString
            guard seen.insert(key).inserted, parsedPages.count < 12 else { return }
            let name = headingText.trimmingCharacters(in: .whitespacesAndNewlines)
            parsedPages.append(SavedPage(pageTitle: name.isEmpty ? host : name, pageURL: linkURL))
        }
        let draftText = assistantPayload.assistantBody
        if let markdown = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#) {
            let range = NSRange(draftText.startIndex..., in: draftText)
            markdown.enumerateMatches(in: draftText, options: [], range: range) { match, _, _ in
                guard let match, match.numberOfRanges == 3,
                    let titleRange = Range(match.range(at: 1), in: draftText),
                    let urlRange = Range(match.range(at: 2), in: draftText),
                    let linkURL = URL(string: String(draftText[urlRange]))
                else { return }
                add(String(draftText[titleRange]), linkURL, requireDeepPath: true)
            }
        }
        for sourceEntry in assistantPayload.savedSources {
            add(sourceEntry.pageTitle, sourceEntry.pageURL, requireDeepPath: true)
        }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) { 
            let range = NSRange(draftText.startIndex..., in: draftText)
            detector.enumerateMatches(in: draftText, options: [], range: range) { match, _, _ in
                guard let linkURL = match?.url else { return }
                add(linkURL.host ?? "", linkURL, requireDeepPath: true)
            }
        }
        return parsedPages
    }
}
