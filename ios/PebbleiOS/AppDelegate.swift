// Pebble for iPad / iPhone — UIKit app + scene lifecycle. The game itself is
// PebbleApp's GameRuntime, hosted by GameViewController.

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var game: GameViewController? { window?.rootViewController as? GameViewController }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: ws)
        w.rootViewController = GameViewController()
        w.makeKeyAndVisible()
        window = w
    }

    /// Control Center, an incoming call, the app switcher: stop drawing,
    /// drop held input and open the pause screen
    func sceneWillResignActive(_ scene: UIScene) {
        game?.appWillResignActive()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        game?.appDidBecomeActive()
    }

    /// iOS may kill a backgrounded app without warning: write the world now
    func sceneDidEnterBackground(_ scene: UIScene) {
        let app = UIApplication.shared
        var task = UIBackgroundTaskIdentifier.invalid
        task = app.beginBackgroundTask(withName: "save world") {
            app.endBackgroundTask(task)
            task = .invalid
        }
        game?.appDidEnterBackground()
        if task != .invalid { app.endBackgroundTask(task) }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        game?.appWillEnterForeground()
    }
}
