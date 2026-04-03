//
// Copyright 2024 Noise Messenger
// SPDX-License-Identifier: AGPL-3.0-only
//

import AppIntents

/// Declares Siri App Shortcuts for Noise, enabling "Hey Siri" voice commands.
@available(iOS 16.4, *)
struct NoiseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NoiseSendMessageIntent(),
            phrases: [
                "Send a message in \(.applicationName)",
                "Send a \(.applicationName) message",
                "Message someone in \(.applicationName)",
                "Text someone in \(.applicationName)",
            ],
            shortTitle: "Send Message",
            systemImageName: "paperplane.fill"
        )
        AppShortcut(
            intent: NoiseReadMessagesIntent(),
            phrases: [
                "Read my messages in \(.applicationName)",
                "Read messages in \(.applicationName)",
                "Check my \(.applicationName) messages",
                "What are my latest \(.applicationName) messages",
            ],
            shortTitle: "Read Messages",
            systemImageName: "envelope.open.fill"
        )
        AppShortcut(
            intent: NoiseSearchMessagesIntent(),
            phrases: [
                "Search messages in \(.applicationName)",
                "Find messages in \(.applicationName)",
                "Search \(.applicationName) for",
            ],
            shortTitle: "Search Messages",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: NoiseSummarizeIntent(),
            phrases: [
                "Summarize my \(.applicationName) conversation",
                "Summarize messages in \(.applicationName)",
                "What's happening in my \(.applicationName) chat",
            ],
            shortTitle: "Summarize Conversation",
            systemImageName: "text.alignleft"
        )
    }
}
