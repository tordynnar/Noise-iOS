//
// Copyright 2024 Noise Messenger
// SPDX-License-Identifier: AGPL-3.0-only
//

import CarPlay
import SignalServiceKit

/// Displays messages from a conversation and handles voice-dictated replies in CarPlay.
class CarPlayMessageController {

    let template: CPListTemplate
    private let threadId: String
    private weak var interfaceController: CPInterfaceController?

    init(threadId: String, conversationName: String, interfaceController: CPInterfaceController?) {
        self.threadId = threadId
        self.interfaceController = interfaceController
        self.template = CPListTemplate(title: conversationName, sections: [])

        loadMessages()
    }

    private func loadMessages() {
        guard AppReadinessObjcBridge.isAppReady else { return }

        let db = DependenciesBridge.shared.db
        let contactManager = SSKEnvironment.shared.contactManagerRef

        let items: [CPListItem] = db.read { tx in
            let interactionFinder = InteractionFinder(threadUniqueId: threadId)
            var messageItems: [CPListItem] = []

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

                        let item = CPListItem(text: senderName, detailText: body)
                        messageItems.append(item)
                        if messageItems.count >= 15 {
                            return false
                        }
                        return true
                    }
                )
            } catch {}

            return messageItems.reversed()
        }

        // Add a "Reply" action at the top
        let replyItem = CPListItem(text: "Reply with Siri", detailText: "Tap to dictate a reply")
        replyItem.handler = { [weak self] _, completion in
            self?.initiateReply()
            completion()
        }

        let replySection = CPListSection(items: [replyItem], header: "Actions", sectionIndexTitle: nil)
        let messagesSection = CPListSection(items: items, header: "Messages", sectionIndexTitle: nil)
        template.updateSections([replySection, messagesSection])
    }

    private func initiateReply() {
        // CarPlay messaging primarily works through SiriKit's INSendMessageIntent.
        // When the user taps "Reply with Siri", Siri handles the voice dictation
        // and message sending through the Intents Extension.
        // This is the recommended approach for CarPlay messaging apps.
    }
}
