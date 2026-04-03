//
// Copyright 2024 Noise Messenger
// SPDX-License-Identifier: AGPL-3.0-only
//

import CarPlay
import SignalServiceKit

/// Manages the CarPlay scene lifecycle and template navigation.
class NoiseCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?
    private var conversationListController: CarPlayConversationListController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let listController = CarPlayConversationListController(interfaceController: interfaceController)
        self.conversationListController = listController

        interfaceController.setRootTemplate(listController.template, animated: true, completion: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        self.conversationListController = nil
    }
}
