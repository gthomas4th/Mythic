//
//  SupportView.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 12/9/2023.
//

// Copyright © 2023-2025 vapidinfinity

import SwiftUI
import AppKit
import SwordRPC

struct SupportView: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HubSectionBanner(title: "Support")
            supportPanel("Resources") {
                Button("Documentation") { openLink(urlString: "https://docs.getmythic.app/") }
                Button("FAQ") { openLink(urlString: "https://getmythic.app/faq/") }
                Button("Compatibility List") { openLink(urlString: "https://docs.google.com/spreadsheets/d/1W_1UexC1VOcbP2CHhoZBR5-8koH-ZPxJBDWntwH-tsc/") }
            }
            supportPanel("Receive Help") {
                Button("Report an issue") { openLink(urlString: "https://github.com/MythicApp/Mythic/issues") }
                Button("Create a support ticket") { openLink(urlString: "https://discord.gg/kQKdvjTVqh") }
            }
            Label("Check the resources first; the answer may already be documented.", systemImage: "exclamationmark.bubble")
                .font(.system(size: 15))
            Spacer()
        }
        .padding(28)
        .font(.system(size: 17))
        .foregroundStyle(HubTheme.ink)
        .background(HubTheme.canvas)
        .task(priority: .background) {
            // Set rich presence using SwordRPC
            discordRPC.setPresence({
                var presence = RichPresence()
                presence.details = "Looking for help"
                presence.state = "Viewing Support"
                presence.timestamps.start = .now
                presence.assets.largeImage = "macos_512x512_2x"
                return presence
            }())
        }
        .navigationTitle("Support")
    }
    private func supportPanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased()).font(HubTheme.heading(24)).tracking(1)
            HStack(spacing: 12) { content() }.buttonStyle(.borderedProminent)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(HubTheme.panel, in: .rect(cornerRadius: 14))
    }
}

public class SupportWindowController: NSWindowController {
    static var shared: SupportWindowController?

    convenience init() {
        let supportView = SupportView()
        let hosting = NSHostingController(rootView: supportView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 430),
            styleMask: [
                .titled,
                .closable,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden

        if let zoomButton = window.standardWindowButton(.zoomButton) {
            zoomButton.isEnabled = false
        }

        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .sidebar
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 28),
            hosting.view.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])

        window.contentView = visualEffectView
        window.center()
        self.init(window: window)
    }

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let controller = SupportWindowController()
            shared = controller
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private func openLink(urlString: String) {
    if let url = URL(string: urlString) {
        NSWorkspace.shared.open(url)
    }
}

@ViewBuilder
private func verticalDivider(height: CGFloat) -> some View {
    Divider()
        .frame(width: 1, height: height)
}

#Preview {
    SupportView()
}
