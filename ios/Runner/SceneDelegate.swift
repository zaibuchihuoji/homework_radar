import Flutter
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    guard let scene = scene as? UIWindowScene,
          let app = UIApplication.shared.delegate as? AppDelegate else { return }
    let window = UIWindow(windowScene: scene)
    window.rootViewController = FlutterViewController(engine: app.sharedEngine, nibName: nil, bundle: nil)
    self.window = window
    app.window = window
    window.makeKeyAndVisible()
    options.urlContexts.forEach { app.widgetBridge.open($0.url) }
  }
  func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
    guard let app = UIApplication.shared.delegate as? AppDelegate else { return }
    contexts.forEach { app.widgetBridge.open($0.url) }
  }
  func sceneDidBecomeActive(_ scene: UIScene) {
    (UIApplication.shared.delegate as? AppDelegate)?.backgroundRefresh.foreground(true)
  }
  func sceneDidEnterBackground(_ scene: UIScene) {
    (UIApplication.shared.delegate as? AppDelegate)?.backgroundRefresh.foreground(false)
  }
}
