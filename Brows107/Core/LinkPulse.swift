//
//  LinkPulse.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 25/10/26.
//

import Foundation
import Network

/// Shared reachability for page loads and AI flows.
@MainActor
final class LinkPulse {
    static let singleton = LinkPulse()

    private(set) var linkSatisfied = true
    private let pathProbe = NWPathMonitor()

    private init() {
        pathProbe.pathUpdateHandler = { path in
            let pathLive = path.status == .satisfied
            Task { @MainActor in
                LinkPulse.singleton.linkSatisfied = pathLive
            }
        }
        pathProbe.start(queue: DispatchQueue(label: "com.brows107.link-pulse"))
    }

    var linkSevered: Bool { !linkSatisfied }
}
