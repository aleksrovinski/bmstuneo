import Flutter
import UIKit
import WidgetKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let channelName = "ru.bmstu.neo/widget"
  private static let appGroupId = "group.ru.bmstu.neo"
  private static var isChannelRegistered = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if !AppDelegate.isChannelRegistered {
      if let registrar = self.registrar(forPlugin: "RuBmstuNeoWidgetPlugin") {
        AppDelegate.registerWidgetChannel(with: registrar.messenger())
      }
    }
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if !AppDelegate.isChannelRegistered {
      if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RuBmstuNeoWidgetPlugin") {
        AppDelegate.registerWidgetChannel(with: registrar.messenger())
      }
    }
  }

  static func registerWidgetChannel(with messenger: FlutterBinaryMessenger) {
    guard !isChannelRegistered else { return }
    isChannelRegistered = true
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
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
        if let args = call.arguments as? [String: Any],
           let scheduleJson = args["scheduleJson"] as? String {
          let enabled = args["enabled"] as? Bool ?? true
          if #available(iOS 16.1, *) {
            LiveActivityManager.shared.updateLiveActivity(scheduleJson: scheduleJson, enabled: enabled)
          }
          result(true)
        } else {
          result(true)
        }
      case "cancelLiveNotification":
        if #available(iOS 16.1, *) {
          LiveActivityManager.shared.endAllActivities()
        }
        result(true)
      case "isLiveNotificationEnabled":
        if #available(iOS 16.1, *) {
          result(LiveActivityManager.shared.isEnabled())
        } else {
          result(false)
        }
      case "setLiveNotificationEnabled":
        if let args = call.arguments as? [String: Any],
           let enabled = args["enabled"] as? Bool {
          if #available(iOS 16.1, *) {
            LiveActivityManager.shared.setEnabled(enabled)
          }
          result(true)
        } else {
          result(true)
        }
      case "hasNotificationPermission":
        if #available(iOS 10.0, *) {
          UNUserNotificationCenter.current().getNotificationSettings { settings in
            let granted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            result(granted)
          }
        } else {
          result(true)
        }
      case "requestNotificationPermission":
        if #available(iOS 10.0, *) {
          UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            result(granted)
          }
        } else {
          result(true)
        }
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
