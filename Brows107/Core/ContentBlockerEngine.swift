//
//  ContentBlockerEngine.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 25/10/26.
//

import WebKit

private enum ContentBlockerCatalog: String {
    case ads = "blocklist-ads"
    case trackerList = "blocklist-trackers"
    case redirects = "blocklist-redirects"

    var ruleListName: String { "Brows107.v3." + rawValue }
}

@MainActor
enum ContentBlockerEngine {
    private static var ruleStore: WKContentRuleListStore { WKContentRuleListStore.default() }

    // Attaches the enabled rule lists to a web view.
    static func installBlockRules(
        to controller: WKUserContentController,
        blockAds: Bool,
        blockTrackers: Bool,
        blockRedirects: Bool,
        shieldEngaged: Bool
    ) async {
        controller.removeAllContentRuleLists()
        controller.removeAllUserScripts()
        controller.addUserScript(selectionAppearanceScript)
        guard shieldEngaged else { return }

        if blockAds, let list = await ruleList(.ads) { controller.add(list) }
        if blockTrackers, let list = await ruleList(.trackerList) { controller.add(list) }
        if blockRedirects, let list = await ruleList(.redirects) { controller.add(list) }
        if blockAds || blockTrackers { controller.addUserScript(cosmeticScript) }
        if blockAds || blockTrackers || blockRedirects { controller.addUserScript(counterScript) }
    }

    // sets up selection appearance
    static func installSelectionAppearance(to controller: WKUserContentController) {
        controller.addUserScript(selectionAppearanceScript)
    }

    // Which shield (ads, trackers, redirects) a host belongs to, if any.
    static func hostShieldKind(forHost host: String) -> String? {
        let bare = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bare.isEmpty, !isPageSafelisted(bare) else { return nil }
        if domainMatches(bare, domains(named: "blocklist-redirects")) { return "redirects" }
        if domainMatches(bare, domains(named: "blocklist-ads")) { return "ads" }
        if domainMatches(bare, domains(named: "blocklist-trackers")) { return "trackers" }
        return nil
    }

    private static var domainCache: [String: Set<String>] = [:]

    // domains
    private static func domains(named: String) -> Set<String> {
        if let cached = domainCache[named] { return cached }
        var catalogHosts = Set<String>()
        guard let bundleRulesText = bundleJSON(named: named),
            let payloadBytes = bundleRulesText.data(using: .utf8),
            let rules = try? JSONSerialization.jsonObject(with: payloadBytes) as? [[String: Any]]
        else {
            domainCache[named] = []
            return []
        }
        for rule in rules {
            guard let trigger = rule["trigger"] as? [String: Any],
                let domains = trigger["if-domain"] as? [String]
            else { continue }
            for host in domains {
                let bare = host.hasPrefix("*") ? String(host.dropFirst()) : host
                let bareHost = bare.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                if !bareHost.isEmpty { catalogHosts.insert(bareHost) }
            }
        }
        domainCache[named] = catalogHosts
        return catalogHosts
    }

    private static func domainMatches(_ host: String, _ domains: Set<String>) -> Bool {
        if domains.contains(host) { return true }
        var remainder = host
        while let dot = remainder.firstIndex(of: ".") {
            remainder = String(remainder[remainder.index(after: dot)...])
            if remainder.contains("."), domains.contains(remainder) { return true }
        }
        return false
    }

    private static var cachedCounter: WKUserScript?
    private static var selectionAppearanceScript: WKUserScript {
        WKUserScript(
            source: """
                (() => {
                  const styleId = 'selection-color';
                  const apply = () => {
                    const root = document.documentElement;
                    if (!root || document.getElementById(styleId)) return;
                    const style = document.createElement('style');
                    style.id = styleId;
                    style.textContent = 'body :not(button):not(button *):not(input):not(input *):not(textarea):not(textarea *):not(select):not(select *):not(option):not([role="button"]):not([role="button"] *):not([contenteditable="true"]):not([contenteditable="true"] *){-webkit-user-select:text!important;user-select:text!important}::selection{background:rgba(0,135,90,.5)!important;color:inherit!important}::-webkit-selection{background:rgba(0,135,90,.5)!important;color:inherit!important}';
                    (document.head || root).appendChild(style);
                  };
                  apply();
                  const observer = new MutationObserver(apply);
                  observer.observe(document, { childList: true, subtree: true });
                  document.addEventListener('DOMContentLoaded', () => observer.disconnect(), { once: true });
                })();
                """, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    private static var counterScript: WKUserScript {
        if let cachedCounter { return cachedCounter }
        let counterLists: [String: [String]] = [
            "ads": Array(domains(named: "blocklist-ads")),
            "trackers": Array(domains(named: "blocklist-trackers")),
            "redirects": Array(domains(named: "blocklist-redirects")),
        ]
        let payloadBytes = (try? JSONSerialization.data(withJSONObject: counterLists)) ?? Data("{}".utf8)
        let counterPayloadJSON = String(data: payloadBytes, encoding: .utf8) ?? "{}"
        let scriptBody = """
            (function(){
            if(window.__brows107Count)return;window.__brows107Count=true;
            const lists=\(counterPayloadJSON);
            const seen=new Set();
            const sets={};
            Object.keys(lists).forEach(k=>sets[k]=new Set(lists[k]));
            function kind(host){
              host=(host||'').toLowerCase();
              if(!host)return'';
              let rest=host;
              while(rest){
                for(const key of ['redirects','ads','trackers']){if(sets[key]&&sets[key].has(rest))return key;}
                const dot=rest.indexOf('.');
                if(dot<0)break;
                rest=rest.slice(dot+1);
                if(!rest.includes('.'))break;
              }
              return'';
            }
            document.addEventListener('error',function(event){
              const node=event.target;
              if(!node||!node.src)return;
              let host='';
              try{host=new URL(node.src,location.href).hostname;}catch(e){return;}
              const matched=kind(host);
              if(!matched)return;
              const token=matched+'|'+node.src;
              if(seen.has(token))return;
              seen.add(token);
              try{webkit.messageHandlers.browsProtection.postMessage(matched);}catch(e){}
            },true);
            })();
            """
        let counterUserScript = WKUserScript(source: scriptBody, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        cachedCounter = counterUserScript
        return counterUserScript
    }

    // Compile the lists at launch so the first page load is not blocked.
    static func prewarm() {
        Task(priority: .utility) { @MainActor in
            async let ads = ruleList(.ads)
            async let trackerList = ruleList(.trackerList)
            async let redirectRuleList = ruleList(.redirects)
            _ = await (ads, trackerList, redirectRuleList)
        }
    }

    private static func ruleList(_ catalog: ContentBlockerCatalog) async -> WKContentRuleList? {
        if let cached = await cachedRuleList(catalog.ruleListName) { return cached }
        guard let bundleRulesText = bundleJSON(named: catalog.rawValue) else { return nil }
        return await compileRuleList(bundleRulesText, ruleListName: catalog.ruleListName)
    }

    // cached rule list
    private static func cachedRuleList(_ ruleListName: String) async -> WKContentRuleList? {
        await withCheckedContinuation { continuation in
            ruleStore.lookUpContentRuleList(forIdentifier: ruleListName) { list, _ in
                continuation.resume(returning: list)
            }
        }
    }

    // compile rule list
    private static func compileRuleList(_ rulesPayload: String, ruleListName: String) async -> WKContentRuleList? {
        await withCheckedContinuation { continuation in
            ruleStore.compileContentRuleList(forIdentifier: ruleListName, encodedContentRuleList: rulesPayload) { list, _ in
                continuation.resume(returning: list)
            }
        }
    }

    // Hosts the user or the built-in list excludes from blocking.
    static func isPageSafelisted(_ host: String) -> Bool {
        let normalizedHost = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(
            in: CharacterSet(charactersIn: "."))
        return blockedPageSafelist.contains { normalizedHost == $0 || normalizedHost.hasSuffix("." + $0) }
    }

    private static let blockedPageSafelist: Set<String> = [
        "x.com", "twitter.com", "apple.com", "google.com", "youtube.com", "reddit.com",
        "wikipedia.org", "github.com", "amazon.com", "facebook.com", "instagram.com",
        "microsoft.com", "bing.com", "duckduckgo.com", "figma.com", "cloudflare.com",
        "linkedin.com", "netflix.com", "spotify.com", "yahoo.com", "twitch.tv",
    ]

    // bundle json
    private static func bundleJSON(named: String) -> String? {
        guard
            let linkURL = Bundle.main.url(forResource: named, withExtension: "json", subdirectory: "Blocklists")
                ?? Bundle.main.url(forResource: named, withExtension: "json"),
            let payloadBytes = try? Data(contentsOf: linkURL),
            payloadBytes.count <= 6_000_000
        else { return nil }
        guard let rules = try? JSONSerialization.jsonObject(with: payloadBytes) as? [[String: Any]] else { return nil }
        var sanitized: [[String: Any]] = []
        for rule in rules {
            guard var trigger = rule["trigger"] as? [String: Any],
                let action = rule["action"] as? [String: Any],
                let domains = trigger["if-domain"] as? [String]
            else { continue }
            let eligibleHosts = domains.filter { host in
                let bare = host.hasPrefix("*") ? String(host.dropFirst()) : host
                return !isPageSafelisted(bare)
            }
            guard !eligibleHosts.isEmpty else { continue }
            trigger["if-domain"] = eligibleHosts
            sanitized.append(["trigger": trigger, "action": action])
        }
        guard let payloadBytes = try? JSONSerialization.data(withJSONObject: sanitized),
            let sanitizedRulesJSON = String(data: payloadBytes, encoding: .utf8)
        else { return nil }
        return sanitizedRulesJSON
    }

    private static var cosmeticScript: WKUserScript {
        let scriptBody = """
            (function(){if(window.__brows107Cosmetic)return;window.__brows107Cosmetic=true;
            const selectors=['.adsbygoogle','[id^=\"google_ads\" i]','[class*=\"ad-slot\" i]','[class*=\"advertisement\" i]','iframe[src*=\"doubleclick\" i]','iframe[src*=\"googlesyndication\" i]','[data-ad-slot]','[data-ad]'];
            const selector=selectors.join(',');
            const hide=root=>{if(!(root instanceof Element))return;if(root.matches(selector))root.style.setProperty('display','none','important');root.querySelectorAll(selector).forEach(n=>n.style.setProperty('display','none','important'));};
            hide(document.documentElement);
            new MutationObserver(records=>{for(const record of records)for(const node of record.addedNodes)hide(node);}).observe(document.documentElement,{childList:true,subtree:true});})();
            """
        return WKUserScript(source: scriptBody, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }
}
