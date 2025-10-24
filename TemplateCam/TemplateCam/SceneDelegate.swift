//
//  SceneDelegate.swift
//  TemplateCam
//
//  Scene delegate
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // Create window
        let window = UIWindow(windowScene: windowScene)

        // Load seed template or create default
        let template = TemplateStore.shared.loadSeed() ?? Template.defaultSeed()

        // Create and set root view controller
        let cameraViewController = CameraViewController(template: template)
        window.rootViewController = cameraViewController
        window.makeKeyAndVisible()

        self.window = window

        Logger.log("Scene connected, camera view controller initialized")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
    }
}
