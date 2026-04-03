//
// Copyright 2024 Noise Messenger
// SPDX-License-Identifier: AGPL-3.0-only
//

import AppIntents
import SignalServiceKit

/// Provides conversation content for Apple Intelligence summarization.
@available(iOS 16.0, *)
struct NoiseSummarizeIntent: AppIntent {
    static let title: LocalizedStringResource = "Summarize Conversation"
    static let description: IntentDescription = "Get a summary of recent messages in a Noise conversation"
    static let openAppWhenRun = false

    @Parameter(title: "Conversation")
    var conversation: NoiseConversationEntity

    @Parameter(title: "Number of Messages", default: 25)
    var count: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let threadUniqueId = conversation.id
        let messageCount = min(count, 50)

        let summary: String = await MainActor.run {
            let db = DependenciesBridge.shared.db
            let contactManager = SSKEnvironment.shared.contactManagerRef
            return db.read { tx in
                guard TSThread.fetchViaCache(uniqueId: threadUniqueId, transaction: tx) != nil else {
                    return "Conversation not found."
                }

                let interactionFinder = InteractionFinder(threadUniqueId: threadUniqueId)
                var messageTexts: [String] = []
                var participantNames = Set<String>()

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
                            participantNames.insert(senderName)
                            messageTexts.append("\(senderName): \(body)")
                            if messageTexts.count >= messageCount {
                                return false
                            }
                            return true
                        }
                    )
                } catch {}

                if messageTexts.isEmpty {
                    return "No messages to summarize in \(self.conversation.displayName)."
                }

                let reversed = messageTexts.reversed()
                let conversationName = self.conversation.displayName
                let participantList = participantNames.sorted().joined(separator: ", ")
                return "Conversation: \(conversationName)\nParticipants: \(participantList)\nRecent messages (\(messageTexts.count)):\n\(reversed.joined(separator: "\n"))"
            }
        }
        return .result(dialog: "\(summary)")
    }
}
