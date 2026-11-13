//
//  ListComponents.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 09/11/26.
//

import SwiftUI
import QuickLook


/// Icon, title and one line of help.
struct EmptyState: View {
    let symbolName: String
    let headingText: String
    let blurb: String
    var actionTitle: String?
    var tapAction: (() -> Void)?

    init(symbolName: String, headingText: String, blurb: String, actionTitle: String? = nil, tapAction: (() -> Void)? = nil) {
        self.symbolName = symbolName
        self.headingText = headingText
        self.blurb = blurb
        self.actionTitle = actionTitle
        self.tapAction = tapAction
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbolName)
                .font(.ui(28, weight: .regular))
                .foregroundStyle(Palette.brandInk)
                .frame(width: 64, height: 64)
                .background(Palette.brandWash, in: Circle())
            Text(headingText)
                .font(.ui(20, weight: .semibold))
                .browsExactLineHeight(25)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.top, 18)
            Text(blurb)
                .font(.ui(15))
                .browsExactLineHeight(20)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            if let actionTitle, let tapAction {
                Button(actionTitle, action: tapAction)
                    .font(.ui(17, weight: .semibold))
                    .frame(minWidth: 180, minHeight: 48)
                    .browsGlassProminentButtonStyle()
                    .buttonBorderShape(.capsule)
                    .tint(Palette.brandInk)
                    .padding(.top, 22)
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
    }
}

/// Custom swipe-to-delete because List styling fights the glass background.
struct SwipeToDeleteRow<Content: View>: View {
    var height: CGFloat
    var isOpen: Bool
    var rowFill: Color
    var card: Color
    var onOpen: () -> Void
    var onClose: () -> Void
    var onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    private let revealed: CGFloat = 110
    @GestureState private var drag: CGFloat = 0

    private var offset: CGFloat {
        let restingShift: CGFloat = isOpen ? -revealed : 0
        return min(0, max(-160, restingShift + drag))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onDelete) {
                HStack(spacing: 8) {
                    Image(systemName: "trash").font(.ui(16))
                    Text("Delete").font(.ui(13))
                }
                .foregroundStyle(.white)
                .frame(width: 84, height: min(height, 44))
                .background(Palette.rgb(0xFF383C), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
            .opacity(offset < -8 ? 1 : 0)
            .accessibilityLabel("Delete")

            content()
                .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
                // background goes behind everything
                .background {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: offset < -2 ? height / 2 : 0,
                        topTrailingRadius: offset < -2 ? height / 2 : 0,
                        style: .continuous
                    )
                    .fill(card)
                }
                .offset(x: offset)
        }
        .frame(height: height)
        .background(offset < -2 ? rowFill : Color.clear)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 18, coordinateSpace: .local)
                .updating($drag) { slot, state, _ in
                    guard abs(slot.translation.width) > abs(slot.translation.height) else { return }
                    state = slot.translation.width
                }
                .onEnded { slot in
                    guard abs(slot.translation.width) > abs(slot.translation.height) else { return }
                    let projected = (isOpen ? -revealed : 0) + slot.predictedEndTranslation.width
                    if projected < -revealed - 30 {
                        onDelete()
                    } else if projected < -36 {
                        onOpen()
                    } else {
                        onClose()
                    }
                }
        )
    }
}
