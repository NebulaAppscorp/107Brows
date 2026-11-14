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

    var ruleListName: String { "Brows107.v4." + rawValue }
}

@MainActor
enum ContentBlockerEngine {
    private static var ruleStore: WKContentRuleListStore { WKContentRuleListStore.default() }
    private static var resolvedRuleLists: [String: WKContentRuleList] = [:]
    private static var pendingRuleLists: [String: Task<WKContentRuleList?, Never>] = [:]


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

        async let adsTask: WKContentRuleList? = blockAds ? ruleList(.ads) : nil
        async let trackersTask: WKContentRuleList? = blockTrackers ? ruleList(.trackerList) : nil
        async let redirectsTask: WKContentRuleList? = blockRedirects ? ruleList(.redirects) : nil
        let (adsList, trackersList, redirectsList) = await (adsTask, trackersTask, redirectsTask)
        if let adsList { controller.add(adsList) }
        if let trackersList { controller.add(trackersList) }
        if let redirectsList { controller.add(redirectsList) }
        if blockAds || blockTrackers { controller.addUserScript(cosmeticScript) }
        if blockAds || blockTrackers || blockRedirects {
            controller.addUserScript(
                counterScript(blockAds: blockAds, blockTrackers: blockTrackers, blockRedirects: blockRedirects))
        }
    }

    // sets up selection appearance
    static func installSelectionAppearance(to controller: WKUserContentController) {
        controller.addUserScript(selectionAppearanceScript)
    }

    // Which shield (ads, trackers, redirects) a host belongs to, if any.
    static func hostShieldKind(forHost host: String) -> String? {
        // local bare
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
        // bail out early if there is nothing to do
        guard let rules = sourceRules(named: named) else {
            domainCache[named] = []
            return []
        } 
        for rule in rules {
            guard let trigger = rule["trigger"] as? [String: Any],
                let domains = trigger["if-domain"] as? [String]
            else { continue }
            // one pass over the host items
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
        // local remainder
        var remainder = host
        while let dot = remainder.firstIndex(of: ".") {
            remainder = String(remainder[remainder.index(after: dot)...])
            if remainder.contains("."), domains.contains(remainder) { return true }
        }
        return false
    }


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

    // counter script
    private static func counterScript(blockAds: Bool, blockTrackers: Bool, blockRedirects: Bool) -> WKUserScript {
        var counterLists: [String: [String]] = [:]
        if blockAds { counterLists["ads"] = Array(domains(named: "blocklist-ads")) }
        if blockTrackers { counterLists["trackers"] = Array(domains(named: "blocklist-trackers")) }
        if blockRedirects { counterLists["redirects"] = Array(domains(named: "blocklist-redirects")) }
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
            function record(value){
              if(!value)return;
              let parsed;
              try{parsed=new URL(value,location.href);}catch(e){return;}
              const matched=kind(parsed.hostname);
              if(!matched)return;
              const token=matched+'|'+parsed.href;
              if(seen.has(token))return;
              seen.add(token);
              try{webkit.messageHandlers.browsProtection.postMessage(matched);}catch(e){}
            }
            function inspect(node){
              if(!node||node.nodeType!==1)return;
              const tag=node.tagName;
              const linkResource=tag==='LINK'&&/stylesheet|preload|modulepreload|icon/i.test(node.rel||'');
              if(!linkResource&&!['IMG','SCRIPT','IFRAME','FRAME','SOURCE','VIDEO','AUDIO','TRACK','EMBED','OBJECT'].includes(tag))return;
              const value=node.currentSrc||node.src||node.href||node.poster||node.data||node.getAttribute('src')||node.getAttribute('href')||node.getAttribute('poster')||node.getAttribute('data');
              record(value);
            }
            function scan(root){
              if(!root)return;
              if(root.nodeType===1)inspect(root);
              if(root.querySelectorAll)root.querySelectorAll('img[src],script[src],iframe[src],frame[src],source[src],video[poster],audio[src],track[src],embed[src],object[data],link[href]').forEach(inspect);
            }
            document.addEventListener('error',function(event){if(event.target)inspect(event.target);},true);
            scan(document);
            new MutationObserver(records=>{
              for(const change of records){
                if(change.type==='attributes')inspect(change.target);
                for(const node of change.addedNodes)scan(node);
              }
            }).observe(document,{childList:true,subtree:true,attributes:true,attributeFilter:['src','href','poster','data']});
            })();
            """
        return WKUserScript(source: scriptBody, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    // Compile the lists at launch so the first page load is not blocked.
    static func prewarm() {
        Task(priority: .utility) {
            async let ads = ruleList(.ads)
            async let trackerList = ruleList(.trackerList)
            async let redirectRuleList = ruleList(.redirects)
            _ = await (ads, trackerList, redirectRuleList)
        }
    }

    private static func ruleList(_ catalog: ContentBlockerCatalog) async -> WKContentRuleList? {
        let ruleListName = catalog.ruleListName
        if let ready = resolvedRuleLists[ruleListName] { return ready }
        if let pending = pendingRuleLists[ruleListName] { return await pending.value }
        let task = Task<WKContentRuleList?, Never> { @MainActor in
            if let cached = await cachedRuleList(ruleListName) { return cached }
            guard let bundleRulesText = bundleJSON(named: catalog.rawValue) else { return nil }
            return await compileRuleList(bundleRulesText, ruleListName: ruleListName)
        }
        pendingRuleLists[ruleListName] = task
        let resolved = await task.value
        pendingRuleLists[ruleListName] = nil
        if let resolved { resolvedRuleLists[ruleListName] = resolved }
        return resolved
    }

    // cached rule list
    private static func cachedRuleList(_ ruleListName: String) async -> WKContentRuleList? {
        // wait for it before moving on
        await withCheckedContinuation { continuation in
            ruleStore.lookUpContentRuleList(forIdentifier: ruleListName) { list, _ in
                continuation.resume(returning: list)
            }
        }
    }

    // compile rule list
    private static func compileRuleList(_ rulesPayload: String, ruleListName: String) async -> WKContentRuleList? {  
        // suspends here
        await withCheckedContinuation { continuation in
            ruleStore.compileContentRuleList(forIdentifier: ruleListName, encodedContentRuleList: rulesPayload) { list, _ in
                continuation.resume(returning: list)
            }
        }
    }

    // Hosts the user or the built-in list excludes from blocking.
    static func isPageSafelisted(_ host: String) -> Bool {
        // normalized host
        let normalizedHost = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(
            in: CharacterSet(charactersIn: "."))
        return blockedPageSafelist.contains { normalizedHost == $0 || normalizedHost.hasSuffix("." + $0) }
    }

    // keeps blocked page safelist
    private static let blockedPageSafelist: Set<String> = [
        "x.com", "twitter.com", "apple.com", "google.com", "youtube.com", "reddit.com",
        "wikipedia.org", "github.com", "amazon.com", "facebook.com", "instagram.com",
        "microsoft.com", "bing.com", "duckduckgo.com", "figma.com", "cloudflare.com",
        "linkedin.com", "netflix.com", "spotify.com", "yahoo.com", "twitch.tv",
    ]

    // bundle json
    private static func bundleJSON(named: String) -> String? {
        guard let rules = sourceRules(named: named) else { return nil }
        var compiledRules: [[String: Any]] = []
        for rule in rules {
            guard var trigger = rule["trigger"] as? [String: Any],
                let action = rule["action"] as? [String: Any],
                let domains = trigger["if-domain"] as? [String],
                !domains.isEmpty
            else { continue }
            trigger.removeValue(forKey: "if-domain")
            trigger["url-filter"] = urlFilter(for: domains)
            compiledRules.append(["trigger": trigger, "action": action])
        }
        guard let payloadBytes = try? JSONSerialization.data(withJSONObject: compiledRules),
            let sanitizedRulesJSON = String(data: payloadBytes, encoding: .utf8)
        else { return nil }
        return sanitizedRulesJSON
    }

    private static func sourceRules(named: String) -> [[String: Any]]? {
        guard
            let linkURL = Bundle.main.url(forResource: named, withExtension: "json", subdirectory: "Blocklists")
                ?? Bundle.main.url(forResource: named, withExtension: "json"),
            let payloadBytes = try? Data(contentsOf: linkURL),
            payloadBytes.count <= 6_000_000
        else { return nil }
        return try? JSONSerialization.jsonObject(with: payloadBytes) as? [[String: Any]]
    }

    private static func urlFilter(for domains: [String]) -> String {
        let escapedDomains = domains.compactMap { value -> String? in
            let host = value.hasPrefix("*") ? String(value.dropFirst()) : value
            let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            guard !normalized.isEmpty else { return nil }
            return NSRegularExpression.escapedPattern(for: normalized)
        }
        return "^https?://(?:[A-Za-z0-9-]+\\.)*(?:\(escapedDomains.joined(separator: "|")))(?::[0-9]+)?(?:[/?#]|$)"
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
