//
// Copyright 2024 Noise Messenger
// SPDX-License-Identifier: AGPL-3.0-only
//

import AppIntents
import SignalServiceKit
import SignalUI

/// Allows Siri and Apple Intelligence to send messages via Noise.
@available(iOS 16.0, *)
struct NoiseSendMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Message"
    static let description: IntentDescription = "Send a message to a contact or group via Noise"
    static let openAppWhenRun = false

    @Parameter(title: "Conversation")
    var conversation: NoiseConversationEntity

    @Parameter(title: "Message")
    var message: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let threadUniqueId = conversation.id
        let messageText = message

        let messageBody = try await DependenciesBridge.shared.attachmentContentValidator
            .prepareOversizeTextIfNeeded(MessageBody(text: messageText, ranges: .empty))

        let recipientName: String = try await MainActor.run {
            let db = DependenciesBridge.shared.db
            return try db.write { tx in
                guard let thread = TSThread.fetchViaCache(uniqueId: threadUniqueId, transaction: tx) else {
                    throw IntentError.threadNotFound
                }

                let dmConfigStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                let dmConfig = dmConfigStore.fetchOrBuildDefault(for: .thread(thread), tx: tx)
                let builder: TSOutgoingMessageBuilder = .withDefaultValues(thread: thread)
                builder.expiresInSeconds = dmConfig.durationSeconds
                builder.expireTimerVersion = NSNumber(value: dmConfig.timerVersion)

                let tsMessage = TSOutgoingMessage(
                    outgoingMessageWith: builder,
                    additionalRecipients: [],
                    explicitRecipients: [],
                    skippedRecipients: [],
                    transaction: tx
                )
                let unpreparedMessage = UnpreparedOutgoingMessage.forMessage(tsMessage, body: messageBody)
                let preparedMessage = try unpreparedMessage.prepare(tx: tx)
                SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: tx)
                return self.conversation.displayName
            }
        }
        return .result(dialog: "Message sent to \(recipientName).")
    }

    enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
        case threadNotFound

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .threadNotFound:
                return "Conversation not found."
            }
        }
    }
}
