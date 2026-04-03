//
// Copyright 2024 Noise Messenger
// SPDX-License-Identifier: AGPL-3.0-only
//

import AppIntents
import SignalServiceKit

/// An AppEntity representing a conversation thread in Noise.
@available(iOS 16.0, *)
struct NoiseConversationEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Conversation")
    static let defaultQuery = NoiseConversationQuery()

    let id: String
    let displayName: String
    let isGroup: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
}

@available(iOS 16.0, *)
struct NoiseConversationQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [NoiseConversationEntity] {
        let db = DependenciesBridge.shared.db
        let contactManager = SSKEnvironment.shared.contactManagerRef
        return db.read { tx in
            identifiers.compactMap { uniqueId -> NoiseConversationEntity? in
                guard let thread = TSThread.fetchViaCache(uniqueId: uniqueId, transaction: tx) else {
                    return nil
                }
                let name: String
                if let contactThread = thread as? TSContactThread {
                    name = contactManager.displayName(for: contactThread.contactAddress, tx: tx).resolvedValue()
                } else if let groupThread = thread as? TSGroupThread {
                    name = groupThread.groupNameOrDefault
                } else {
                    name = "Unknown"
                }
                return NoiseConversationEntity(
                    id: uniqueId,
                    displayName: name,
                    isGroup: thread is TSGroupThread
                )
            }
        }
    }

    func suggestedEntities() async throws -> [NoiseConversationEntity] {
        let db = DependenciesBridge.shared.db
        let contactManager = SSKEnvironment.shared.contactManagerRef
        return db.read { tx in
            var results: [NoiseConversationEntity] = []
            let threadFinder = ThreadFinder()
            
                threadFinder.enumerateVisibleThreads(isArchived: false, transaction: tx) { thread in
                    guard results.count < 30 else { return }
                    let name: String
                    if let contactThread = thread as? TSContactThread {
                        name = contactManager.displayName(for: contactThread.contactAddress, tx: tx).resolvedValue()
                    } else if let groupThread = thread as? TSGroupThread {
                        name = groupThread.groupNameOrDefault
                    } else {
                        return
                    }
                    results.append(NoiseConversationEntity(
                        id: thread.uniqueId,
                        displayName: name,
                        isGroup: thread is TSGroupThread
                    ))
                }
            return results
        }
    }
}
