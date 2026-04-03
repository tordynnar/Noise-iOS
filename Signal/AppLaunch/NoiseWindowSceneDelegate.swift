//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

class NoiseWindowSceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    private var appDelegate: AppDelegate {
        UIApplication.shared.delegate as! AppDelegate
    }

    // MARK: - Scene Connection

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions,
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = OWSWindow(windowScene: windowScene)
        self.window = window
        appDelegate.connectWindow(window)
    }

    // MARK: - Lifecycle

    func sceneDidBecomeActive(_ scene: UIScene) {
        AssertIsOnMainThread()
        if CurrentAppContext().isRunningTests {
            return
        }

        Logger.warn("")

        if appDelegate.didAppLaunchFail {
            return
        }

        appDelegate.appReadiness.runNowOrWhenAppDidBecomeReadySync { self.appDelegate.handleActivation() }

        // Clear all notifications whenever we become active.
        // When opening the app from a notification,
        // AppDelegate.didReceiveLocalNotification will always
        // be called _before_ we become active.
        appDelegate.clearAppropriateNotificationsAndRestoreBadgeCount()

        // On every activation, clear old temp directories.
        OWSFileSystem.clearOldTemporaryDirectories()

        // Ensure that all windows have the correct frame.
        AppEnvironment.shared.windowManagerRef.updateWindowFrames()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        AssertIsOnMainThread()

        Logger.warn("")

        if appDelegate.didAppLaunchFail {
            return
        }

        appDelegate.appReadiness.runNowOrWhenAppDidBecomeReadySync {
            self.appDelegate.refreshConnection(isAppActive: false, shouldRunCron: false)
        }

        appDelegate.clearAppropriateNotificationsAndRestoreBadgeCount()

        let backgroundTask = OWSBackgroundTask(label: #function)
        appDelegate.flushQueue.async {
            defer { backgroundTask.end() }
            Logger.flush()
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        Logger.info("")

        if appDelegate.shouldKillAppWhenBackgrounded {
            Logger.flush()
            exit(0)
        }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        Logger.info("")
    }
}
