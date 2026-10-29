import UIKit
import Flutter
import receive_sharing_intent

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        registerShareTestChannel()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // Test-only channel for integration_test/share_intent_test.dart. The
    // simulator has no share sheet, so this does what the share extension
    // does: it writes the share payload into the app group, then hands the
    // plugin the ShareMedia-<bundle id> URL the extension opens the app with.
    private func registerShareTestChannel() {
        guard let registrar = self.registrar(forPlugin: "RSIShareTest") else { return }
        let channel = FlutterMethodChannel(
            name: "receive_sharing_intent_example/test",
            binaryMessenger: registrar.messenger())
        channel.setMethodCallHandler { call, result in
            guard call.method == "shareJson", let payload = call.arguments as? String else {
                result(FlutterMethodNotImplemented)
                return
            }
            let bundleId = Bundle.main.bundleIdentifier ?? ""
            let groupId = Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String
                ?? "group.\(bundleId)"
            guard let defaults = UserDefaults(suiteName: groupId),
                  let data = payload.data(using: .utf8),
                  let url = URL(string: "ShareMedia-\(bundleId)://share") else {
                result(FlutterError(code: "share", message: "no app group or URL", details: nil))
                return
            }
            defaults.set(data, forKey: "ShareKey")
            defaults.synchronize()
            let handled = ReceiveSharingIntentPlugin.instance.application(
                UIApplication.shared, open: url, options: [:])
            // Returned to the test (print does not reach the CI log on iOS), so
            // a failed expectation shows what the plugin was given.
            result("handled=\(handled) url=\(url.absoluteString) group=\(groupId) bytes=\(data.count) readback=\(defaults.data(forKey: "ShareKey")?.count ?? -1)")
        }
    }

    // Incoming URLs (including shared media) are now handled through the
    // UIScene lifecycle - see SceneDelegate.swift.
}
