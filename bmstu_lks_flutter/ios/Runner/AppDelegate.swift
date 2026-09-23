import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let channelName = "ru.bmstu.neo/widget"
  private static let appGroupId = "group.ru.bmstu.neo"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    AppDelegate.registerWidgetChannel(with: engineBridge.pluginRegistry.registrar(forPlugin: "RuBmstuNeoWidgetPlugin"))
  }

  static func registerWidgetChannel(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "updateWidget":
        if let args = call.arguments as? [String: Any],
           let scheduleJson = args["scheduleJson"] as? String {
          saveScheduleData(scheduleJson)
          result(true)
        } else {
          result(FlutterError(code: "INVALID_ARGS", message: "scheduleJson is required", details: nil))
        }
      case "isPinningSupported":
        result(false)
      case "pinWidget":
        result(false)
      case "updateLiveNotification":
        result(true)
      case "isLiveNotificationEnabled":
        result(false)
      case "hasNotificationPermission":
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func saveScheduleData(_ jsonString: String) {
    if let userDefaults = UserDefaults(suiteName: appGroupId) {
      userDefaults.set(jsonString, forKey: "schedule_data")
      userDefaults.synchronize()
      if #available(iOS 14.0, *) {
        WidgetCenter.shared.reloadAllTimelines()
      }
    }
  }
}
