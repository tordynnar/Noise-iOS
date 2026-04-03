//
// Copyright 2024 Noise Messenger
// SPDX-License-Identifier: AGPL-3.0-only
//

import AppIntents
import SignalServiceKit

/// An AppEntity representing a contact in Noise, used for Siri resolution.
@available(iOS 16.0, *)
struct NoisePersonEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Contact")
    static let defaultQuery = NoisePersonQuery()

    let id: String
    let displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
}

@available(iOS 16.0, *)
struct NoisePersonQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [NoisePersonEntity] {
        let db = DependenciesBridge.shared.db
        let contactManager = SSKEnvironment.shared.contactManagerRef
        return db.read { tx in
            identifiers.compactMap { uniqueId -> NoisePersonEntity? in
                guard let thread = TSContactThread.fetchViaCache(uniqueId: uniqueId, transaction: tx) else {
                    return nil
                }
                let name = contactManager.displayName(for: thread.contactAddress, tx: tx).resolvedValue()
                return NoisePersonEntity(id: uniqueId, displayName: name)
            }
        }
    }

    func suggestedEntities() async throws -> [NoisePersonEntity] {
        let db = DependenciesBridge.shared.db
        let contactManager = SSKEnvironment.shared.contactManagerRef
        return db.read { tx in
            var results: [NoisePersonEntity] = []
            let threadFinder = ThreadFinder()
            
                threadFinder.enumerateVisibleThreads(isArchived: false, transaction: tx) { thread in
                    guard let contactThread = thread as? TSContactThread else { return }
                    guard results.count < 20 else { return }
                    let name = contactManager.displayName(for: contactThread.contactAddress, tx: tx).resolvedValue()
                    results.append(NoisePersonEntity(id: contactThread.uniqueId, displayName: name))
                }
            return results
        }
    }
}
