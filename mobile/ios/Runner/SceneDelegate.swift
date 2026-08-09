import Flutter
import GoogleSignIn
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
      if GIDSignIn.sharedInstance.handle(context.url) {
        return
      }
    }

    super.scene(scene, openURLContexts: URLContexts)
  }
}
