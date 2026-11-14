//
//  LinkPulse.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 25/10/26.
// 

import Foundation
import Network
import os

/// Shared reachability for page loads and AI flows.
final class LinkPulse: Sendable {
    static let singleton = LinkPulse()

    // The path callback fires on a background queue, so the flag sits behind a lock
    // instead of being hopped over to the main actor.
    private let satisfiedFlag = OSAllocatedUnfairLock(initialState: true)
    private let pathProbe = NWPathMonitor()

    var linkSatisfied: Bool { satisfiedFlag.withLock { $0 } }


    private init() {
        let flag = satisfiedFlag
        self.pathProbe.pathUpdateHandler = { path in
            let pathLive = path.status == .satisfied
            let changed = flag.withLock { currentValue -> Bool in
                guard currentValue != pathLive else { return false }
                currentValue = pathLive
                return true
            }
            guard changed else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .linkPulseConnectivityChanged,
                    object: nil,
                    userInfo: ["linkSatisfied": pathLive])
            }
        }
        self.pathProbe.start(queue: DispatchQueue(label: "com.brows107.link-pulse"))
    }
}    

extension LinkPulse {
    // reads nicer at call sites than !linkSatisfied
    var linkSevered: Bool { !linkSatisfied }
}

extension Notification.Name {
    static let linkPulseConnectivityChanged = Notification.Name("linkPulseConnectivityChanged")
}
