//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BackgroundTasks
public import SignalServiceKit

/**
 * Utility class for managing the BGAppRefreshTask used for polling messages.
 *
 * Since Noise does not use APNs, this task is the primary mechanism for receiving
 * messages when the app is in the background. iOS may throttle execution to every
 * ~15 minutes, so real-time delivery only works via WebSocket when the app is
 * in the foreground.
 */
public class MessageFetchBGRefreshTask {

    private static var _shared: MessageFetchBGRefreshTask?

    public static func getShared(appReadiness: AppReadiness) -> MessageFetchBGRefreshTask? {
        if let _shared {
            return _shared
        }

        guard appReadiness.isAppReady else {
            return nil
        }
        let value = MessageFetchBGRefreshTask(
            backgroundMessageFetcherFactory: DependenciesBridge.shared.backgroundMessageFetcherFactory,
            dateProvider: { Date() },
            ows2FAManager: SSKEnvironment.shared.ows2FAManagerRef,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
        )
        _shared = value
        return value
    }

    // Must be kept in sync with the values in info.plist.
    private static let taskIdentifier = "MessageFetchBGRefreshTask"
    private static let processingTaskIdentifier = "MessageFetchBGProcessingTask"

    private let backgroundMessageFetcherFactory: BackgroundMessageFetcherFactory
    private let dateProvider: DateProvider
    private let ows2FAManager: OWS2FAManager
    private let tsAccountManager: TSAccountManager

    private init(
        backgroundMessageFetcherFactory: BackgroundMessageFetcherFactory,
        dateProvider: @escaping DateProvider,
        ows2FAManager: OWS2FAManager,
        tsAccountManager: TSAccountManager,
    ) {
        self.backgroundMessageFetcherFactory = backgroundMessageFetcherFactory
        self.dateProvider = dateProvider
        self.ows2FAManager = ows2FAManager
        self.tsAccountManager = tsAccountManager
    }

    public static func register(appReadiness: AppReadiness) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil,
            launchHandler: { task in
                appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
                    Self.getShared(appReadiness: appReadiness)!.performTask(task)
                }
            },
        )
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingTaskIdentifier,
            using: nil,
            launchHandler: { task in
                appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
                    Self.getShared(appReadiness: appReadiness)!.performProcessingTask(task)
                }
            },
        )
    }

    public func scheduleTask() {
        // Note: this file only exists in the main app (Signal/src) so we
        // don't check for that. But if this ever moves, it should check
        // appContext.isMainApp.

        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return
        }

        // Poll frequently since we don't use APNs. iOS may throttle this to
        // every ~15 minutes at best, but we request every 2 minutes optimistically.
        let refreshInterval: TimeInterval = 2 * 60 // 2 minutes
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = dateProvider().addingTimeInterval(refreshInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch let error {
            logSchedulingError(error, taskType: "refresh")
        }

        // Also schedule a processing task for longer background execution.
        let processingRequest = BGProcessingTaskRequest(identifier: Self.processingTaskIdentifier)
        processingRequest.earliestBeginDate = dateProvider().addingTimeInterval(5 * 60) // 5 minutes
        processingRequest.requiresNetworkConnectivity = true

        do {
            try BGTaskScheduler.shared.submit(processingRequest)
        } catch let error {
            logSchedulingError(error, taskType: "processing")
        }
    }

    private func logSchedulingError(_ error: Error, taskType: String) {
        let errorCode = (error as NSError).code
        switch errorCode {
        case BGTaskScheduler.Error.Code.notPermitted.rawValue:
            Logger.warn("Skipping bg \(taskType) task; user permission required.")
        case BGTaskScheduler.Error.Code.tooManyPendingTaskRequests.rawValue:
            Logger.error("Too many pending bg \(taskType) tasks.")
        case BGTaskScheduler.Error.Code.unavailable.rawValue:
            Logger.warn("Trying to schedule bg \(taskType) task from an extension or simulator?")
        default:
            Logger.error("Unknown error code scheduling bg \(taskType) task: \(errorCode)")
        }
    }

    private func performTask(_ task: BGTask) {
        Logger.info("performing background fetch")
        Task {
            let backgroundMessageFetcher = self.backgroundMessageFetcherFactory.buildFetcher()
            let result = await Result {
                try await withCooperativeTimeout(seconds: 27) {
                    await backgroundMessageFetcher.start()
                    try await backgroundMessageFetcher.waitForFetchingProcessingAndSideEffects()
                }
            }
            await backgroundMessageFetcher.stopAndWaitBeforeSuspending()
            // Schedule the next run now.
            self.scheduleTask()
            do {
                try result.get()
                Logger.info("success")
                task.setTaskCompleted(success: true)
            } catch {
                Logger.error("Failing task; failed to fetch messages")
                task.setTaskCompleted(success: false)
            }
        }
    }

    /// Processing tasks get more runtime (up to several minutes) and are ideal
    /// for fetching messages without APNs.
    private func performProcessingTask(_ task: BGTask) {
        Logger.info("performing background processing fetch")
        Task {
            let backgroundMessageFetcher = self.backgroundMessageFetcherFactory.buildFetcher()
            let result = await Result {
                // Processing tasks get more time — use up to 120 seconds.
                try await withCooperativeTimeout(seconds: 120) {
                    await backgroundMessageFetcher.start()
                    try await backgroundMessageFetcher.waitForFetchingProcessingAndSideEffects()
                }
            }
            await backgroundMessageFetcher.stopAndWaitBeforeSuspending()
            self.scheduleTask()
            do {
                try result.get()
                Logger.info("processing task success")
                task.setTaskCompleted(success: true)
            } catch {
                Logger.error("Processing task failed to fetch messages")
                task.setTaskCompleted(success: false)
            }
        }
    }
}
