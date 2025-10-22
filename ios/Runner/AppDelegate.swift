import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Manually register Iperf3Plugin
    Iperf3Plugin.register(
      with: self.registrar(forPlugin: "Iperf3Plugin")!
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
