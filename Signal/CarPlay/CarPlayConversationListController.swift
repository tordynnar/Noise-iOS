//
// Copyright 2024 Noise Messenger
// SPDX-License-Identifier: AGPL-3.0-only
//

import CarPlay
import SignalServiceKit

/// Displays a list of recent conversations in the CarPlay interface.
class CarPlayConversationListController {

    let template: CPListTemplate
    private weak var interfaceController: CPInterfaceController?

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        self.template = CPListTemplate(title: "Noise", sections: [])
        self.template.tabTitle = "Messages"
        self.template.tabSystemItem = .recents

        loadConversations()
    }

    private func loadConversations() {
        guard AppReadinessObjcBridge.isAppReady else {
            let emptySection = CPListSection(items: [
                CPListItem(text: "Loading...", detailText: "Please wait")
            ])
            template.updateSections([emptySection])
            return
        }

        let db = DependenciesBridge.shared.db
        let contactManager = SSKEnvironment.shared.contactManagerRef

        let items: [CPListItem] = db.read { tx in
            var results: [CPListItem] = []
            let threadFinder = ThreadFinder()
            
                threadFinder.enumerateVisibleThreads(isArchived: false, transaction: tx) { thread in
                    guard results.count < 20 else { return }

                    let name: String
                    if let contactThread = thread as? TSContactThread {
                        name = contactManager.displayName(for: contactThread.contactAddress, tx: tx).resolvedValue()
                    } else if let groupThread = thread as? TSGroupThread {
                        name = groupThread.groupNameOrDefault
                    } else {
                        return
                    }

                    // Get last message preview
                    let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)
                    var lastMessagePreview: String?
                    do {
                        try interactionFinder.enumerateInteractionsForConversationView(
                            rowIdFilter: .newest,
                            tx: tx,
                            block: { interaction in
                                if let message = interaction as? TSMessage, let body = message.body {
                                    lastMessagePreview = body
                                }
                                return false
                            }
                        )
                    } catch {}
                    let item = CPListItem(
                        text: name,
                        detailText: lastMessagePreview ?? "No messages"
                    )
                    item.userInfo = ["threadId": thread.uniqueId]
                    item.handler = { [weak self] _, completion in
                        self?.openConversation(threadId: thread.uniqueId, name: name)
                        completion()
                    }
                    results.append(item)
                }
            return results
        }

        let section = CPListSection(items: items)
        template.updateSections([section])
    }

    private func openConversation(threadId: String, name: String) {
        let messageController = CarPlayMessageController(
            threadId: threadId,
            conversationName: name,
            interfaceController: interfaceController
        )
        interfaceController?.pushTemplate(messageController.template, animated: true, completion: nil)
    }
}
