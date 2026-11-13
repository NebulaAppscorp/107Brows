//
//  SampleDataInstaller.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 05/11/26. 
//

import SwiftUI

@MainActor
enum SampleDataInstaller {
    // page aiscenarios
    static let pageAIScenarios: Set<String> = [
        "ai", "ai-quota", "ai-last", "ai-nocontent", "ai-offline", "generating", "gen-stopped", "gen-offline",
        "answer", "answer-medium", "answer-error", "answer-notonpage", "answer-streaming", "answer-sources",
        "answer-citation", "feedback", "feedback-sent", "feedback-error",
    ]


    // Applies the scenario named in the -scenario launch argument.
    static func apply(on vault: BrowserStore) {
        if vault.launchScenario == "site" { vault.blockedTally = 4 }
        if vault.launchScenario == "models" { vault.modalLane = .models }
        if vault.launchScenario == "update-soft" { vault.releaseBanner = .soft }
        if vault.launchScenario == "update-force" { vault.releaseBanner = .force }
        vault.tabStrip = [BrowserTab()]
        vault.activeTabKey = vault.tabStrip[0].id
        vault.incognito = false
        vault.chromePane = 0
        vault.aiThreads = []
        vault.activeThreadKey = nil
        if vault.launchScenario == "chat-dark" {
            vault.chromeTheme = "Dark"
            vault.chromePane = 1
        }
        if vault.launchScenario == "home-dark" {
            vault.chromeTheme = "Dark"
            vault.visitLedger = [
                SavedPage(pageTitle: "Wikipedia", pageURL: URL(string: "https://www.wikipedia.org")!),
                SavedPage(pageTitle: "APOD: 2026 July 11 - Messier 24", pageURL: URL(string: "https://apod.nasa.gov")!),
            ]
        }
        if vault.launchScenario == "wiki" {
            vault.tabStrip[0].pageTitle = "Wikipedia"
            vault.tabStrip[0].pageURL = URL(string: "https://ru.wikipedia.org")
        }
        if vault.launchScenario == "live" {
            let fixtureCacheDir = URL.cachesDirectory.appending(path: "BrowserCheck", directoryHint: .isDirectory)
            do {
                try FileManager.default.createDirectory(at: fixtureCacheDir, withIntermediateDirectories: true)
                let leadFixtureURL = fixtureCacheDir.appending(path: "first.html")
                let secondFixtureURL = fixtureCacheDir.appending(path: "second.html")
                try
                    "<html><head><title>Local browser check</title></head><body><h1>Local browser check</h1><a href='second.html'>Open second page</a></body></html>"
                    .write(to: leadFixtureURL, atomically: true, encoding: .utf8) 
                try "<html><head><title>Second local page</title></head><body><h1>Second local page</h1></body></html>".write(
                    to: secondFixtureURL, atomically: true, encoding: .utf8)
                vault.tabStrip[0].pageURL = leadFixtureURL
            } catch { vault.bannerText = "Couldn’t set up the local test pages." }
        }
        if ["find-live", "find-live-no-keyboard"].contains(vault.launchScenario ?? "") {
            let fixtureCacheDir = URL.cachesDirectory.appending(path: "BrowserCheck", directoryHint: .isDirectory)
            do {
                try FileManager.default.createDirectory(at: fixtureCacheDir, withIntermediateDirectories: true)
                let findFixtureURL = fixtureCacheDir.appending(path: "find.html")
                let findFixtureHTML =
                    "<html><head><meta name='viewport' content='width=device-width, initial-scale=1'><title>Find test page</title><style>body{font:22px -apple-system;padding:24px;line-height:1.5}p{margin:32px 0}</style></head><body><h1>Find in this page</h1><p>Coffee appears here in the first paragraph.</p><p>Try another cup of coffee with a finer grind.</p><p>Good coffee is mostly about water and time.</p><p>This paragraph has coffee again.</p></body></html>"
                try findFixtureHTML.write(to: findFixtureURL, atomically: true, encoding: .utf8)
                vault.tabStrip[0].pageURL = findFixtureURL
                vault.tabStrip[0].pageTitle = "Find test page"
            } catch { vault.bannerText = "Couldn’t set up the local find test page." }
        }
        if vault.launchScenario == "xcom" || vault.launchScenario == "xcom-unshielded" {
            vault.tabStrip[0].pageTitle = "X"
            vault.tabStrip[0].pageURL = URL(string: "https://x.com")
        }
        if vault.launchScenario == "xcom-unshielded" {
            vault.shieldAds = false
            vault.shieldTrackers = false
            vault.shieldRedirects = false
        }
        if vault.launchScenario == "page-scroll" {
            let fixtureCacheDir = URL.cachesDirectory.appending(path: "BrowserCheck", directoryHint: .isDirectory)
            do {
                try FileManager.default.createDirectory(at: fixtureCacheDir, withIntermediateDirectories: true)
                let scrollFixtureURL = fixtureCacheDir.appending(path: "scroll.html")
                let scrollFixtureBlocks = (0..<16).map { index in
                    "<section><h1>Section \(index + 1)</h1><p>Scroll to see the browser toolbar remain clear while the page moves beneath it.</p></section>"
                }.joined()
                let html =
                    "<html><head><meta name='viewport' content='width=device-width, initial-scale=1'><style>body{font:20px -apple-system;padding:24px;color:#111}section{height:360px;border-bottom:1px solid #ddd}h1{color:#00875a}</style></head><body>\(scrollFixtureBlocks)</body></html>"
                try html.write(to: scrollFixtureURL, atomically: true, encoding: .utf8)
                vault.tabStrip[0].pageURL = scrollFixtureURL
                vault.tabStrip[0].pageTitle = "Scroll behavior"
            } catch { vault.bannerText = "Couldn’t set up the local scroll page." }
        }
        vault.visitLedger = SampleContent.fixturePages
        vault.pinnedPages = SampleContent.fixturePages
        if vault.launchScenario == "library" {
            vault.visitLedger = [
                SampleContent.fixturePages[0],
                SampleContent.fixturePages[1],
                SavedPage(pageTitle: "Vintage steel thermos", pageURL: URL(string: "https://etsy.com")!),
                SampleContent.fixturePages[2],
                SampleContent.fixturePages[3],
            ]
            vault.pinnedPages = [
                SampleContent.fixturePages[0],
                SampleContent.fixturePages[1],
                SampleContent.fixturePages[2],
                SampleContent.fixturePages[3],
                SavedPage(
                    pageTitle: "Choosing a burr grinder", pageURL: URL(string: "https://baristahustle.com/burr-grinder")!,
                    shelfLabel: "Read later"),
                SavedPage(
                    pageTitle: "How water hardness changes taste", pageURL: URL(string: "https://sca.coffee/hardness")!,
                    shelfLabel: "Read later"),
            ]
        }
        if ["page", "ai", "answer", "reader", "find", "find-keyboard", "find-no-keyboard", "site", "edit"].contains(
            vault.launchScenario ?? "") || pageAIScenarios.contains(vault.launchScenario ?? "")
        {
            vault.tabStrip[0].pageTitle = "How to brew coffee"
            vault.tabStrip[0].pageURL = URL(string: "https://ncausa.org")
        }
        if ["chat", "chat-answer", "chats", "models"].contains(vault.launchScenario ?? "") { vault.chromePane = 1 }
        if vault.launchScenario == "b107TabStrip" {
            vault.tabStrip = [
                BrowserTab(pageTitle: "How to brew coffee", pageURL: URL(string: "https://ncausa.org")),
                BrowserTab(pageTitle: "Liquid Glass overview", pageURL: URL(string: "https://developer.apple.com")),
                BrowserTab(pageTitle: "Product design in 2026", pageURL: URL(string: "https://uxcollective.cc")),
                BrowserTab(pageTitle: "Visual search results", pageURL: URL(string: "https://images.example.com")),
                BrowserTab(pageTitle: "Wikipedia", pageURL: URL(string: "https://wikipedia.org")),
                BrowserTab(pageTitle: "SF Symbols 8", pageURL: URL(string: "https://developer.apple.com/sf-symbols/")),
            ]
            vault.activeTabKey = vault.tabStrip[0].id
        } 
        if vault.launchScenario == "private" { vault.toggleIncognito(true) }
        if vault.launchScenario == "menu" { vault.modalLane = .menu }
        if vault.launchScenario == "tabs" { vault.modalLane = .tabs }
        if ["chat-answer", "chats", "models"].contains(vault.launchScenario ?? "") {
            let seedConversation = Conversation(
                threadTitle: "What changed in iOS 26?",
                threadTurns: [
                    ChatMessage(messageBody: "What changed in iOS 26?", fromVisitor: true),
                    ChatMessage(
                        messageBody: SampleContent.chatAnswer, fromVisitor: false,
                        citationPages: Array(SampleContent.fixturePages.prefix(3))),
                ]
            )    
            vault.aiThreads = [seedConversation]
            vault.activeThreadKey = seedConversation.id
        } 
        if vault.launchScenario == "chats" {
            let fixtureCalendar = Calendar.current
            // fixture chat timestamp
            func fixtureChatTimestamp(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
                // day anchor
                let dayAnchor = fixtureCalendar.date(byAdding: .day, value: -day, to: Date()) ?? Date()
                return fixtureCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayAnchor) ?? dayAnchor
            }
            let seedThread = vault.aiThreads[0]
            vault.aiThreads = [
                Conversation(
                    id: seedThread.id, threadTitle: seedThread.threadTitle, threadStamp: fixtureChatTimestamp(0, 11, 4),
                    threadTurns: seedThread.threadTurns),
                Conversation(threadTitle: "Compare two coffee grinders", threadStamp: fixtureChatTimestamp(0, 9, 20)),
                Conversation(threadTitle: "Explain Liquid Glass in simple words", threadStamp: fixtureChatTimestamp(1, 18, 47)),
                Conversation(threadTitle: "Where is this thermos from?", threadStamp: fixtureChatTimestamp(1, 14, 12)),
                Conversation(threadTitle: "Summarize this article for me", threadStamp: fixtureChatTimestamp(1, 8, 35)),
            ]
        }
    }    
}
