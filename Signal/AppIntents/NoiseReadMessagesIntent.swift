//
// Copyright 2024 Noise Messenger
// SPDX-License-Identifier: AGPL-3.0-only
//

import AppIntents
import SignalServiceKit

/// Allows Siri and Apple Intelligence to read recent messages from a conversation.
@available(iOS 16.0, *)
struct NoiseReadMessagesIntent: AppIntent {
    static let title: LocalizedStringResource = "Read Messages"
    static let description: IntentDescription = "Read recent messages from a Noise conversation"
    static let openAppWhenRun = false

    @Parameter(title: "Conversation")
    var conversation: NoiseConversationEntity

    @Parameter(title: "Number of Messages", default: 5)
    var count: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let threadUniqueId = conversation.id
        let messageCount = min(count, 20)

        let messages: String = await MainActor.run {
            let db = DependenciesBridge.shared.db
            let contactManager = SSKEnvironment.shared.contactManagerRef
            return db.read { tx in
                guard TSThread.fetchViaCache(uniqueId: threadUniqueId, transaction: tx) != nil else {
                    return "Conversation not found."
                }

                let interactionFinder = InteractionFinder(threadUniqueId: threadUniqueId)
                var messageTexts: [String] = []

                do {
                    try interactionFinder.enumerateInteractionsForConversationView(
                        rowIdFilter: .newest,
                        tx: tx,
                        block: { interaction in
                            guard let message = interaction as? TSMessage else { return true }
                            guard let body = message.body, !body.isEmpty else { return true }

                            let senderName: String
                            if let incomingMessage = message as? TSIncomingMessage {
                                senderName = contactManager.displayName(for: incomingMessage.authorAddress, tx: tx).resolvedValue()
                            } else {
                                senderName = "You"
                            }
                            messageTexts.append("\(senderName): \(body)")
                            if messageTexts.count >= messageCount {
                                return false
                            }
                            return true
                        }
                    )
                } catch {}

                if messageTexts.isEmpty {
                    return "No recent messages in this conversation."
                }
                return messageTexts.reversed().joined(separator: "\n")
            }
        }
        return .result(dialog: "\(messages)")
    }
}
