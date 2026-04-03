//
// Copyright 2024 Noise Messenger
// SPDX-License-Identifier: AGPL-3.0-only
//

import AppIntents
import SignalServiceKit

/// Allows Siri and Apple Intelligence to search messages by keyword.
@available(iOS 16.0, *)
struct NoiseSearchMessagesIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Messages"
    static let description: IntentDescription = "Search for messages containing a keyword in Noise"
    static let openAppWhenRun = false

    @Parameter(title: "Search Query")
    var query: String

    @Parameter(title: "Conversation", default: nil)
    var conversation: NoiseConversationEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let searchQuery = query.lowercased()

        let results: String = await MainActor.run {
            let db = DependenciesBridge.shared.db
            let contactManager = SSKEnvironment.shared.contactManagerRef
            return db.read { tx in
                var matchingMessages: [String] = []

                let threadIds: [String]
                if let conversation {
                    threadIds = [conversation.id]
                } else {
                    var ids: [String] = []
                    let threadFinder = ThreadFinder()
                    
                        threadFinder.enumerateVisibleThreads(isArchived: false, transaction: tx) { thread in
                            guard ids.count < 50 else { return }
                            ids.append(thread.uniqueId)
                        }
                    threadIds = ids
                }

                for threadId in threadIds {
                    let interactionFinder = InteractionFinder(threadUniqueId: threadId)
                    do {
                        try interactionFinder.enumerateInteractionsForConversationView(
                            rowIdFilter: .newest,
                            tx: tx,
                            block: { interaction in
                                guard let message = interaction as? TSMessage else { return true }
                                guard let body = message.body, body.lowercased().contains(searchQuery) else { return true }

                                let senderName: String
                                if let incomingMessage = message as? TSIncomingMessage {
                                    senderName = contactManager.displayName(for: incomingMessage.authorAddress, tx: tx).resolvedValue()
                                } else {
                                    senderName = "You"
                                }
                                matchingMessages.append("\(senderName): \(body)")
                                if matchingMessages.count >= 10 {
                                    return false
                                }
                                return true
                            }
                        )
                    } catch {}
                    if matchingMessages.count >= 10 { break }
                }

                if matchingMessages.isEmpty {
                    return "No messages found matching \"\(self.query)\"."
                }
                return "Found \(matchingMessages.count) message(s):\n\(matchingMessages.joined(separator: "\n"))"
            }
        }
        return .result(dialog: "\(results)")
    }
}
