//
//  ToolbarGlassItem.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 25/10/26.
//

import SwiftUI

struct IsolatedToolbarItem<Content: ToolbarContent>: ToolbarContent {
    @ToolbarContentBuilder private let barItems: Content

    init(@ToolbarContentBuilder barItems: () -> Content) {
        self.barItems = barItems()
    }

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.barItems.sharedBackgroundVisibility(.hidden)
        } else {
            barItems
        }
    }
}
