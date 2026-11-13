//
//  AIClient.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 22/10/26.
//

import Foundation

protocol AIService: Sendable {
    // Sends one chat turn and returns the reply.
    func relayChat(
        remoteChatID: String, promptText: String, photoJPEG: Data?, sourceIDs: [String], webLookupEnabled: Bool, think: Bool
    ) async throws -> AIReply
    // relay chat
    func relayChat(
        remoteChatID: String, promptText: String, additionalPrompt: String?, photoJPEG: Data?, sourceIDs: [String],
        webLookupEnabled: Bool, think: Bool
    ) async throws -> AIReply
    // Cleans the page text before it goes into a prompt.
    func preparePlainText(_ draftText: String) async throws -> String
}

extension AIService {
    // Relay chat
    func relayChat(
        remoteChatID: String, promptText: String, photoJPEG: Data?, sourceIDs: [String], webLookupEnabled: Bool, think: Bool
    ) async throws -> AIReply {
        try await relayChat(
            remoteChatID: remoteChatID, promptText: promptText, additionalPrompt: nil, photoJPEG: photoJPEG, sourceIDs: sourceIDs,
            webLookupEnabled: webLookupEnabled, think: think)
    }
}

/// Decoded answer from the chat endpoint.
struct AIReply: Decodable, Sendable {
    var remoteChatID: String
    var assistantBody: String
    var referenceMarks: [AICitation]?
    var savedSources: [SavedPage] {
        (referenceMarks ?? []).compactMap { citation in
            guard let citationHref = citation.citationHref, let linkURL = URL(string: citationHref),
                ["http", "https"].contains(linkURL.scheme?.lowercased() ?? ""), linkURL.host != nil
            else { return nil }
            return SavedPage(pageTitle: citation.pageTitle, pageURL: linkURL)
        }
    }
    private enum CodingKeys: String, CodingKey {
        case remoteChatID = "chat_id", assistantBody = "assistant_message", referenceMarks = "citations"
    }

    init(remoteChatID: String, assistantBody: String, referenceMarks: [AICitation]? = nil) {
        self.remoteChatID = remoteChatID
        self.assistantBody = assistantBody
        self.referenceMarks = referenceMarks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self) 
        remoteChatID = try container.decode(String.self, forKey: .remoteChatID)
        self.assistantBody = try container.decode(String.self, forKey: .assistantBody)
        referenceMarks = try container.decodeIfPresent([AICitation].self, forKey: .referenceMarks) 
    }
}

/// One source link the assistant cites.  
struct AICitation: Decodable, Sendable { 
    var pageTitle: String
    var citationHref: String?

    private enum CodingKeys: String, CodingKey {
        case pageTitle = "title"
        case citationHref = "url"
    }

    init(pageTitle: String, citationHref: String? = nil) {
        self.pageTitle = pageTitle
        self.citationHref = citationHref
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageTitle = try container.decode(String.self, forKey: .pageTitle)
        citationHref = try container.decodeIfPresent(String.self, forKey: .citationHref)
    }
}


/// Everything that can go wrong talking to the backend, with user-facing text.
enum APIError: LocalizedError, Equatable {
    case misconfigured, storage, unauthorized, balance, rateLimited, invalidResponse, unavailable, tooLarge, processing, network
    var errorDescription: String? {
        switch self {
        case .misconfigured: "AI is not connected yet. Please set up the connection before trying again."
        case .storage: "The connection could not be saved securely. Please try again."
        case .unauthorized: "Your AI connection has expired. Please reconnect."
        case .balance: "There are not enough AI credits for this request."
        case .rateLimited: "Too many requests. Please wait a moment and try again."
        case .invalidResponse: "The answer could not be read. Please try again."
        case .unavailable: "The AI service is temporarily unavailable. Please try again later."
        case .tooLarge: "This message or attachment is too large. Please choose a smaller one."
        case .processing: "The document could not be prepared yet. Please try again later."
        case .network: "The connection was interrupted. Check your internet connection and try again."
        }
    }
}


/// Network client for chat and plain-text prep.
actor AIClient: AIService {
    private let urlPipeline: URLSession
    private let vaultLoader: @Sendable () throws -> APIVault
    private let bundleApplicationID: String
    private var preparedSources: [String: String] = [:]

    init(
        session: URLSession? = nil, bundleApplicationID: String = AppMetadata.shippingApplicationID,
        vaultLoader: @escaping @Sendable () throws -> APIVault = { try APIKeyVault.readFromKeychain() }
    ) {
        if let session {
            self.urlPipeline = session
        } else {
            let ephemeralSession = URLSessionConfiguration.ephemeral
            ephemeralSession.timeoutIntervalForRequest = 90
            ephemeralSession.timeoutIntervalForResource = 120
            ephemeralSession.urlCache = nil
            ephemeralSession.httpCookieStorage = nil
            self.urlPipeline = URLSession(configuration: ephemeralSession, delegate: APIRedirectPolicy(), delegateQueue: nil)
        }
        self.vaultLoader = vaultLoader
        self.bundleApplicationID = bundleApplicationID
    }

    func relayChat(
        remoteChatID: String, promptText: String, additionalPrompt: String? = nil, photoJPEG: Data? = nil,
        sourceIDs: [String] = [], webLookupEnabled: Bool, think: Bool
    ) async throws -> AIReply {
        guard promptText.count <= 8000, (additionalPrompt?.count ?? 0) <= 4000, (photoJPEG?.count ?? 0) <= 5_242_880 else {
            throw APIError.tooLarge
        }
        guard !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photoJPEG != nil,
            remoteChatID.range(of: "^[A-Za-z0-9._:-]{1,128}$", options: .regularExpression) != nil,
            sourceIDs.allSatisfy({ UUID(uuidString: $0) != nil })
        else { throw APIError.invalidResponse }
        let vaultLink = try vaultLoader()
        var outboundRequest = try buildAPIRequest(path: ["v2", "chats", remoteChatID, "messages"], vaultLink: vaultLink)
        outboundRequest.httpMethod = "POST"
        let thinkInstruction =
            think ? "Think carefully through the question before answering. Give a clear, well-reasoned answer." : nil
        let promptLayers = [thinkInstruction, additionalPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }
            .joined(separator: "\n")
        let mergedPromptHint = promptLayers.isEmpty ? nil : promptLayers
        if let photoJPEG {
            var multipartDraft = MultipartBody()
            multipartDraft.add(name: "message", value: promptText)
            multipartDraft.add(name: "web_search", value: webLookupEnabled ? "on" : "off")
            if let mergedPromptHint { multipartDraft.add(name: "additional_prompt", value: mergedPromptHint) }
            for sourceID in sourceIDs { multipartDraft.add(name: "source_ids", value: sourceID) }
            multipartDraft.add(name: "images", filename: "photo.jpg", mime: "image/jpeg", fileBytes: photoJPEG)
            outboundRequest.httpBody = multipartDraft.finish()
            outboundRequest.setValue(multipartDraft.contentType, forHTTPHeaderField: "Content-Type")
        } else {
            let jsonEnvelope = MessagePayload(
                promptBody: promptText, additionalPrompt: mergedPromptHint, sourceIDs: sourceIDs,
                webSearchWire: webLookupEnabled ? "on" : "off")
            outboundRequest.httpBody = try JSONEncoder().encode(jsonEnvelope)
            outboundRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let assistantPayload: AIReply = try await performDecoded(outboundRequest)
        guard !assistantPayload.assistantBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIError.invalidResponse
        }
        return assistantPayload
    }

    // Prepare plain text
    func preparePlainText(_ draftText: String) async throws -> String {
        guard let payloadBytes = draftText.data(using: .utf8), !payloadBytes.isEmpty else { throw APIError.invalidResponse }
        guard payloadBytes.count <= 2_000_000 else { throw APIError.tooLarge }  
        let vaultLink = try vaultLoader()
        let prepareDigest =
            vaultLink.baseEndpoint.absoluteString + vaultLink.remoteUserID
            + vaultLink.resolvedAppID(bundleDefault: bundleApplicationID) + draftText
        if let readySourceID = preparedSources[prepareDigest] { return readySourceID }
        var upload = try buildAPIRequest(path: ["v1", "context", "sources"], vaultLink: vaultLink)
        upload.httpMethod = "POST"
        var multipartDraft = MultipartBody()
        multipartDraft.add(name: "kind", value: "document")
        multipartDraft.add(name: "file", filename: "page.txt", mime: "text/plain; charset=utf-8", fileBytes: payloadBytes)
        upload.setValue(multipartDraft.contentType, forHTTPHeaderField: "Content-Type")
        upload.httpBody = multipartDraft.finish()
        var contextUpload: ContextSource = try await performDecoded(upload)
        guard UUID(uuidString: contextUpload.sourceID) != nil else { throw APIError.invalidResponse }
        for attempt in 0..<45 {
            try Task.checkCancellation()
            if contextUpload.status == "ready" {
                if preparedSources.count >= 8 { preparedSources.removeAll() }
                preparedSources[prepareDigest] = contextUpload.sourceID
                return contextUpload.sourceID
            }
            if ["failed", "error", "cancelled"].contains(contextUpload.status) { throw APIError.processing }
            if attempt == 44 { break }
            try await Task.sleep(for: .seconds(2))
            let poll = try buildAPIRequest(path: ["v1", "context", "sources", contextUpload.sourceID], vaultLink: vaultLink)
            contextUpload = try await performDecoded(poll)
        }
        throw APIError.processing
    }

    // Builds an authorised request from the stored connection.
    private func buildAPIRequest(path: [String], vaultLink: APIVault) throws -> URLRequest {
        try vaultLink.verifyVaultFields()
        var linkURL = vaultLink.baseEndpoint
        for component in path { linkURL.append(path: component) }
        guard var queryParts = URLComponents(url: linkURL, resolvingAgainstBaseURL: false) else { throw APIError.misconfigured }
        let resolvedAppID = vaultLink.resolvedAppID(bundleDefault: bundleApplicationID)
        guard resolvedAppID.range(of: "^[A-Za-z0-9.-]{3,256}$", options: .regularExpression) != nil else {
            throw APIError.misconfigured
        }
        let language = Self.supportedLocale(from: Locale.preferredLanguages.first)
        queryParts.queryItems = [
            URLQueryItem(name: "user_id", value: vaultLink.remoteUserID),
            URLQueryItem(name: "app_id", value: resolvedAppID),
            URLQueryItem(name: "locale", value: language),
        ]
        guard let target = queryParts.url else { throw APIError.misconfigured }
        var outboundRequest = URLRequest(url: target)
        outboundRequest.cachePolicy = .reloadIgnoringLocalCacheData
        outboundRequest.setValue("Bearer " + vaultLink.bearerToken, forHTTPHeaderField: "Authorization")
        outboundRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        outboundRequest.setValue(language, forHTTPHeaderField: "Accept-Language")
        return outboundRequest
    }

    // The backend only knows a few locales, so fall back to English.
    private static func supportedLocale(from preferred: String?) -> String {
        guard let raw = preferred?.lowercased() else { return "en" }
        if raw.hasPrefix("ru") { return "ru" }
        if raw.hasPrefix("zh-hant") || raw.hasPrefix("zh-tw") || raw.hasPrefix("zh-hk") { return "zh-Hant" }
        if raw.hasPrefix("zh") { return "zh-Hans" }
        if raw.hasPrefix("es-mx") { return "es-MX" }
        if raw.hasPrefix("es") { return "es" }
        if raw.hasPrefix("pt") { return "pt" }
        return "en"
    }


    // Runs the request and decodes the JSON, mapping failures to APIError.
    private func performDecoded<T: Decodable & Sendable>(_ outboundRequest: URLRequest) async throws -> T {
        do {
            try Task.checkCancellation()
            let (payloadBytes, response) = try await urlPipeline.data(for: outboundRequest)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            let statusValue = http.statusCode
            if (200..<300).contains(statusValue) {
                // ok
            } else if statusValue == 401 || statusValue == 403 {
                throw APIError.unauthorized
            } else if statusValue == 402 {
                throw APIError.balance
            } else if statusValue == 413 {
                throw APIError.tooLarge
            } else if statusValue == 429 {
                throw APIError.rateLimited
            } else {
                throw APIError.unavailable
            }
            guard payloadBytes.count <= 10_000_000, let decodedPayload = try? JSONDecoder().decode(T.self, from: payloadBytes)
            else { throw APIError.invalidResponse }
            return decodedPayload
        } catch is CancellationError { throw CancellationError() } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as APIError { throw error } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                throw APIError.network
            default:
                throw APIError.unavailable
            }
        } catch { throw APIError.unavailable }
    }
}

/// Refuse redirects so the bearer token never leaves the original host.
// TODO(Aleksandra): same-host redirects could be allowed, haven't needed it yet
private final class APIRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private struct MessagePayload: Encodable {
    var promptBody: String
    var additionalPrompt: String?
    var sourceIDs: [String]
    var webSearchWire: String

    private enum CodingKeys: String, CodingKey {
        case promptBody = "message", additionalPrompt = "additional_prompt", sourceIDs = "source_ids"
        case webSearchWire = "web_search"
    }
}

private struct ContextSource: Decodable, Sendable {
    // source id
    var sourceID: String
    var status: String

    private enum CodingKeys: String, CodingKey {
        case sourceID = "source_id", status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = try container.decode(String.self, forKey: .sourceID)
        self.status = try container.decode(String.self, forKey: .status)
    }
}

/// Minimal multipart/form-data writer for photo uploads.
private struct MultipartBody {
    private let boundary = "Boundary-" + UUID().uuidString
    private var bodyBuffer = Data()
    var contentType: String { "multipart/form-data; boundary=" + boundary }
    mutating func add(name: String, value slot: String) {
        bodyBuffer.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(slot)\r\n".utf8))
    }
    mutating func add(name: String, filename: String, mime: String, fileBytes slot: Data) {
        bodyBuffer.append(
            Data(
                "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n"
                    .utf8))
        bodyBuffer.append(slot)
        bodyBuffer.append(Data("\r\n".utf8))
    }
    mutating func finish() -> Data {
        bodyBuffer.append(Data("--\(boundary)--\r\n".utf8))
        return bodyBuffer
    }
}
