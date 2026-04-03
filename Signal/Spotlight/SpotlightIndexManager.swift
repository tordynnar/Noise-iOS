//
// Copyright 2024 Noise Messenger
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreSpotlight
import SignalServiceKit
import UniformTypeIdentifiers

/// Indexes Noise conversations in Spotlight for system-wide search.
class SpotlightIndexManager {

    static let shared = SpotlightIndexManager()
    private let searchableIndex = CSSearchableIndex.default()

    private init() {}

    /// Call after app becomes ready to index all visible conversations.
    func indexAllConversations() {
        guard AppReadinessObjcBridge.isAppReady else { return }

        Task {
            await performFullIndex()
        }
    }

    /// Re-index a specific thread when it changes.
    func indexThread(_ thread: TSThread) {
        guard AppReadinessObjcBridge.isAppReady else { return }

        let db = DependenciesBridge.shared.db
        let contactManager = SSKEnvironment.shared.contactManagerRef

        let item: CSSearchableItem? = db.read { tx in
            return self.searchableItem(for: thread, contactManager: contactManager, tx: tx)
        }

        guard let item else { return }
        searchableIndex.indexSearchableItems([item]) { error in
            if let error {
                Logger.error("Failed to index thread in Spotlight: \(error)")
            }
        }
    }

    /// Remove a thread from the Spotlight index.
    func removeThread(uniqueId: String) {
        searchableIndex.deleteSearchableItems(withIdentifiers: [uniqueId]) { error in
            if let error {
                Logger.error("Failed to remove thread from Spotlight: \(error)")
            }
        }
    }

    // MARK: - Private

    private func performFullIndex() async {
        let db = DependenciesBridge.shared.db
        let contactManager = SSKEnvironment.shared.contactManagerRef

        let items: [CSSearchableItem] = db.read { tx in
            var results: [CSSearchableItem] = []
            let threadFinder = ThreadFinder()
            
                threadFinder.enumerateVisibleThreads(isArchived: false, transaction: tx) { thread in
                    guard results.count < 500 else { return }
                    if let item = self.searchableItem(for: thread, contactManager: contactManager, tx: tx) {
                        results.append(item)
                    }
                }
            return results
        }

        guard !items.isEmpty else { return }

        do {
            try await searchableIndex.indexSearchableItems(items)
            Logger.info("Indexed \(items.count) conversations in Spotlight")
        } catch {
            Logger.error("Failed to index conversations in Spotlight: \(error)")
        }
    }

    private func searchableItem(
        for thread: TSThread,
        contactManager: any ContactManager,
        tx: DBReadTransaction
    ) -> CSSearchableItem? {
        let name: String
        if let contactThread = thread as? TSContactThread {
            name = contactManager.displayName(for: contactThread.contactAddress, tx: tx).resolvedValue()
        } else if let groupThread = thread as? TSGroupThread {
            name = groupThread.groupNameOrDefault
        } else {
            return nil
        }

        // Get last message preview
        let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)
        var lastMessagePreview: String?
        var lastMessageDate: Date?

        do {
            try interactionFinder.enumerateInteractionsForConversationView(
                rowIdFilter: .newest,
                tx: tx,
                block: { interaction in
                    if let message = interaction as? TSMessage {
                        lastMessagePreview = message.body
                        lastMessageDate = Date(millisecondsSince1970: message.timestamp)
                    }
                    return false
                }
            )
        } catch {}

        let attributeSet = CSSearchableItemAttributeSet(contentType: UTType.message)
        attributeSet.title = name
        attributeSet.contentDescription = lastMessagePreview ?? "Noise conversation"
        attributeSet.supportsNavigation = true
        if let lastMessageDate {
            attributeSet.contentModificationDate = lastMessageDate
        }
        // Mark as communication for better integration
        attributeSet.authorNames = [name]

        let item = CSSearchableItem(
            uniqueIdentifier: thread.uniqueId,
            domainIdentifier: "com.noise.conversations",
            attributeSet: attributeSet
        )
        // Keep items in index for 30 days
        item.expirationDate = Date().addingTimeInterval(30 * 24 * 60 * 60)

        return item
    }

    /// Handle a Spotlight continuation to open a conversation.
    /// Returns the thread uniqueId if this is a Spotlight activity, nil otherwise.
    static func threadId(from userActivity: NSUserActivity) -> String? {
        guard userActivity.activityType == CSSearchableItemActionType else {
            return nil
        }
        return userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
    }
}
