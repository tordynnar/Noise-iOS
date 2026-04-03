//
// Copyright 2024 Noise Messenger
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreSpotlight
import SignalServiceKit
import UniformTypeIdentifiers

/// Indexes Noise conversations and messages in Spotlight for system-wide search.
class SpotlightIndexManager {

    static let shared = SpotlightIndexManager()
    private let searchableIndex = CSSearchableIndex.default()
    private static let conversationDomain = "com.noise.conversations"
    private static let messageDomain = "com.noise.messages"
    /// Maximum number of recent messages to index per thread during full index.
    private static let messagesPerThread = 50
    /// Maximum number of threads to index during full index.
    private static let maxThreads = 200

    private init() {}

    /// Register as a database change observer for incremental Spotlight updates.
    @MainActor
    func startObservingDatabaseChanges() {
        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)
    }

    // MARK: - Public

    /// Call after app becomes ready to index all visible conversations and their recent messages.
    func indexAllConversations() {
        guard AppReadinessObjcBridge.isAppReady else { return }
        Task {
            await performFullIndex()
        }
    }

    /// Index a single message that was just sent or received.
    func indexMessage(_ message: TSMessage, in thread: TSThread) {
        guard AppReadinessObjcBridge.isAppReady else { return }
        guard let body = message.body, !body.isEmpty else { return }

        let db = DependenciesBridge.shared.db
        let contactManager = SSKEnvironment.shared.contactManagerRef

        let items: [CSSearchableItem] = db.read { tx in
            let conversationName = self.conversationName(for: thread, contactManager: contactManager, tx: tx)
            guard let conversationName else { return [] }

            var result: [CSSearchableItem] = []

            // Index the message itself
            if let messageItem = self.searchableItem(
                forMessage: message,
                conversationName: conversationName,
                threadUniqueId: thread.uniqueId,
                tx: tx
            ) {
                result.append(messageItem)
            }

            // Also update the thread-level item with the latest message preview
            if let threadItem = self.searchableItem(
                forThread: thread,
                name: conversationName,
                lastMessagePreview: body,
                lastMessageDate: Date(millisecondsSince1970: message.timestamp)
            ) {
                result.append(threadItem)
            }

            return result
        }

        guard !items.isEmpty else { return }
        searchableIndex.indexSearchableItems(items) { error in
            if let error {
                Logger.error("Failed to index message in Spotlight: \(error)")
            }
        }
    }

    /// Re-index a specific thread when it changes (name update, etc.).
    func indexThread(_ thread: TSThread) {
        guard AppReadinessObjcBridge.isAppReady else { return }

        let db = DependenciesBridge.shared.db
        let contactManager = SSKEnvironment.shared.contactManagerRef

        let item: CSSearchableItem? = db.read { tx in
            let conversationName = self.conversationName(for: thread, contactManager: contactManager, tx: tx)
            guard let conversationName else { return nil }

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
            } catch {
                Logger.warn("Failed to enumerate interactions for Spotlight thread index: \(error)")
            }

            return self.searchableItem(
                forThread: thread,
                name: conversationName,
                lastMessagePreview: lastMessagePreview,
                lastMessageDate: lastMessageDate
            )
        }

        guard let item else { return }
        searchableIndex.indexSearchableItems([item]) { error in
            if let error {
                Logger.error("Failed to index thread in Spotlight: \(error)")
            }
        }
    }

    /// Remove a thread and all its messages from the Spotlight index.
    func removeThread(uniqueId: String) {
        searchableIndex.deleteSearchableItems(withIdentifiers: [uniqueId]) { error in
            if let error {
                Logger.error("Failed to remove thread from Spotlight: \(error)")
            }
        }
        searchableIndex.deleteSearchableItems(withDomainIdentifiers: ["\(Self.messageDomain).\(uniqueId)"]) { error in
            if let error {
                Logger.error("Failed to remove thread messages from Spotlight: \(error)")
            }
        }
    }

    /// Remove a specific message from the Spotlight index.
    func removeMessage(uniqueId: String) {
        searchableIndex.deleteSearchableItems(withIdentifiers: [uniqueId]) { error in
            if let error {
                Logger.error("Failed to remove message from Spotlight: \(error)")
            }
        }
    }

    /// Handle a Spotlight continuation to open a conversation.
    /// Returns the thread uniqueId if this is a Spotlight activity, nil otherwise.
    static func threadId(from userActivity: NSUserActivity) -> String? {
        guard userActivity.activityType == CSSearchableItemActionType else {
            return nil
        }
        guard let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            return nil
        }
        // Message items encode the thread ID after "msg:" prefix and before the message ID
        // Format: "msg:<threadUniqueId>:<messageUniqueId>"
        if identifier.hasPrefix("msg:") {
            let parts = identifier.dropFirst(4).split(separator: ":", maxSplits: 1)
            return parts.first.map(String.init)
        }
        // Thread-level items use the thread uniqueId directly
        return identifier
    }

    // MARK: - Private

    private func performFullIndex() async {
        let db = DependenciesBridge.shared.db
        let contactManager = SSKEnvironment.shared.contactManagerRef

        let items: [CSSearchableItem] = db.read { tx in
            var results: [CSSearchableItem] = []
            let threadFinder = ThreadFinder()
            var threadCount = 0

            threadFinder.enumerateVisibleThreads(isArchived: false, transaction: tx) { thread in
                guard threadCount < Self.maxThreads else { return }
                threadCount += 1

                let conversationName = self.conversationName(for: thread, contactManager: contactManager, tx: tx)
                guard let conversationName else { return }

                let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)
                var lastMessagePreview: String?
                var lastMessageDate: Date?
                var messageCount = 0

                // Index recent messages for this thread
                do {
                    try interactionFinder.enumerateInteractionsForConversationView(
                        rowIdFilter: .newest,
                        tx: tx,
                        block: { interaction in
                            guard let message = interaction as? TSMessage else { return true }

                            if messageCount == 0 {
                                lastMessagePreview = message.body
                                lastMessageDate = Date(millisecondsSince1970: message.timestamp)
                            }

                            if let item = self.searchableItem(
                                forMessage: message,
                                conversationName: conversationName,
                                threadUniqueId: thread.uniqueId,
                                tx: tx
                            ) {
                                results.append(item)
                            }

                            messageCount += 1
                            return messageCount < Self.messagesPerThread
                        }
                    )
                } catch {
                    Logger.warn("Failed to enumerate messages for Spotlight index in thread \(thread.uniqueId): \(error)")
                }

                // Also add thread-level item for conversation name search
                if let threadItem = self.searchableItem(
                    forThread: thread,
                    name: conversationName,
                    lastMessagePreview: lastMessagePreview,
                    lastMessageDate: lastMessageDate
                ) {
                    results.append(threadItem)
                }
            }
            return results
        }

        guard !items.isEmpty else { return }

        do {
            // Delete old items first to avoid stale entries
            try await searchableIndex.deleteAllSearchableItems()
            try await searchableIndex.indexSearchableItems(items)
            Logger.info("Indexed \(items.count) items in Spotlight")
        } catch {
            Logger.error("Failed to index items in Spotlight: \(error)")
        }
    }

    private func conversationName(
        for thread: TSThread,
        contactManager: any ContactManager,
        tx: DBReadTransaction
    ) -> String? {
        if let contactThread = thread as? TSContactThread {
            return contactManager.displayName(for: contactThread.contactAddress, tx: tx).resolvedValue()
        } else if let groupThread = thread as? TSGroupThread {
            return groupThread.groupNameOrDefault
        }
        return nil
    }

    private func searchableItem(
        forMessage message: TSMessage,
        conversationName: String,
        threadUniqueId: String,
        tx: DBReadTransaction
    ) -> CSSearchableItem? {
        guard let body = message.body, !body.isEmpty else { return nil }

        let attributeSet = CSSearchableItemAttributeSet(contentType: UTType.message)
        attributeSet.displayName = conversationName
        attributeSet.title = conversationName
        attributeSet.contentDescription = body
        attributeSet.textContent = body
        attributeSet.supportsNavigation = true
        attributeSet.contentModificationDate = Date(millisecondsSince1970: message.timestamp)

        if let incomingMessage = message as? TSIncomingMessage {
            let contactManager = SSKEnvironment.shared.contactManagerRef
            let senderName = contactManager.displayName(for: incomingMessage.authorAddress, tx: tx).resolvedValue()
            attributeSet.authorNames = [senderName]
        } else {
            attributeSet.authorNames = ["You"]
        }

        // Use "msg:<threadId>:<messageId>" so we can route taps to the right conversation
        let identifier = "msg:\(threadUniqueId):\(message.uniqueId)"
        let item = CSSearchableItem(
            uniqueIdentifier: identifier,
            domainIdentifier: "\(Self.messageDomain).\(threadUniqueId)",
            attributeSet: attributeSet
        )
        item.expirationDate = Date().addingTimeInterval(30 * 24 * 60 * 60)

        return item
    }

    private func searchableItem(
        forThread thread: TSThread,
        name: String,
        lastMessagePreview: String?,
        lastMessageDate: Date?
    ) -> CSSearchableItem? {
        let attributeSet = CSSearchableItemAttributeSet(contentType: UTType.message)
        attributeSet.displayName = name
        attributeSet.title = name
        attributeSet.contentDescription = lastMessagePreview ?? "Noise conversation"
        attributeSet.supportsNavigation = true
        if let lastMessageDate {
            attributeSet.contentModificationDate = lastMessageDate
        }
        attributeSet.authorNames = [name]

        let item = CSSearchableItem(
            uniqueIdentifier: thread.uniqueId,
            domainIdentifier: Self.conversationDomain,
            attributeSet: attributeSet
        )
        item.expirationDate = Date().addingTimeInterval(30 * 24 * 60 * 60)

        return item
    }
}

// MARK: - DatabaseChangeDelegate

extension SpotlightIndexManager: DatabaseChangeDelegate {
    @MainActor
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        let interactionUniqueIds = databaseChanges.interactionUniqueIds
        guard !interactionUniqueIds.isEmpty else { return }

        Task {
            let db = DependenciesBridge.shared.db
            let contactManager = SSKEnvironment.shared.contactManagerRef

            let items: [CSSearchableItem] = db.read { tx in
                var results: [CSSearchableItem] = []

                for uniqueId in interactionUniqueIds {
                    guard let interaction = TSInteraction.anyFetch(uniqueId: uniqueId, transaction: tx) else {
                        continue
                    }
                    guard let message = interaction as? TSMessage else { continue }
                    guard let body = message.body, !body.isEmpty else { continue }
                    guard let thread = TSThread.fetchViaCache(uniqueId: message.uniqueThreadId, transaction: tx) else {
                        continue
                    }

                    let conversationName = self.conversationName(for: thread, contactManager: contactManager, tx: tx)
                    guard let conversationName else { continue }

                    if let item = self.searchableItem(
                        forMessage: message,
                        conversationName: conversationName,
                        threadUniqueId: thread.uniqueId,
                        tx: tx
                    ) {
                        results.append(item)
                    }
                }

                return results
            }

            guard !items.isEmpty else { return }
            do {
                try await self.searchableIndex.indexSearchableItems(items)
            } catch {
                Logger.error("Failed to incrementally index messages in Spotlight: \(error)")
            }
        }
    }

    @MainActor
    func databaseChangesDidUpdateExternally() {
        // External changes (e.g., from NSE) — trigger a full reindex
        indexAllConversations()
    }

    @MainActor
    func databaseChangesDidReset() {
        indexAllConversations()
    }
}
