//
//  AddressResolver.swift  
//  Brows107
//
//  Created by Aleksandra Savchuk on 31/10/26.
//

import Foundation
enum AddressResolver {
    // Coerce navigable url
    static func coerceNavigableURL(_ input: String, engine: String = "Google") -> URL? {
        let addressDraft = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addressDraft.isEmpty else { return nil }
        if let linkURL = URL(string: addressDraft), ["http", "https"].contains(linkURL.scheme?.lowercased() ?? ""),
            linkURL.host != nil
        {
            return linkURL
        }
        if !addressDraft.contains(where: \.isWhitespace), addressDraft.contains("."), !addressDraft.contains("://"),
            let linkURL = URL(string: "https://" + addressDraft), linkURL.host != nil
        {
            return linkURL
        }
        var queryParts = URLComponents(
            string: engine == "DuckDuckGo" ? "https://duckduckgo.com/" : "https://www.google.com/search")
        queryParts?.queryItems = [URLQueryItem(name: "q", value: addressDraft)]
        return queryParts?.url
    }    
}
