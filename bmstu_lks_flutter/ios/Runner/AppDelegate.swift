import Flutter
import UIKit
import WidgetKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let channelName = "ru.bmstu.neo/widget"
  private static let appGroupId = "group.ru.bmstu.neo"
  private static var isChannelRegistered = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Background progress check (BackgroundSync in Dart); iOS decides when it actually runs
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "ru.bmstu.neo.sync", earliestBeginInSeconds: 3600)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if !AppDelegate.isChannelRegistered {
      if let registrar = self.registrar(forPlugin: "RuBmstuNeoWidgetPlugin") {
        AppDelegate.registerWidgetChannel(with: registrar.messenger())
      }
    }
    // Asking twice for the same plugin key throws "Duplicate plugin key", hence the check
    if !PushChannelPlugin.isRegistered, let registrar = self.registrar(forPlugin: "RuBmstuNeoPushPlugin") {
      PushChannelPlugin.register(with: registrar)
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
    if !PushChannelPlugin.isRegistered,
       let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RuBmstuNeoPushPlugin") {
      PushChannelPlugin.register(with: registrar)
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

/// Silent APNs pushes: the token goes to Dart (for the future push server), and a
/// push with {"type": "sync"} runs BackgroundSync in Dart, then reports to iOS
/// whether new data arrived. The push itself carries no student data.
final class PushChannelPlugin: NSObject, FlutterPlugin {
  private static var shared: PushChannelPlugin?
  static var isRegistered: Bool { shared != nil }

  private let channel: FlutterMethodChannel
  private var pendingTokenResult: FlutterResult?
  private var dartReady = false
  // Pushes that arrive before Dart has attached its handler (cold start from a push)
  private var queuedPushes: [(UIBackgroundFetchResult) -> Void] = []

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    guard shared == nil else { return }
    let channel = FlutterMethodChannel(name: "ru.bmstu.neo/push", binaryMessenger: registrar.messenger())
    let plugin = PushChannelPlugin(channel: channel)
    shared = plugin
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.addApplicationDelegate(plugin)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ready":
      dartReady = true
      let queued = queuedPushes
      queuedPushes.removeAll()
      queued.forEach { runSync(completion: $0) }
      result(nil)
    case "enable":
      pendingTokenResult = result
      UIApplication.shared.registerForRemoteNotifications()
    case "disable":
      UIApplication.shared.unregisterForRemoteNotifications()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    pendingTokenResult?(token)
    pendingTokenResult = nil
  }

  func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    NSLog("[PushChannel] APNs registration failed: \(error.localizedDescription)")
    pendingTokenResult?(nil)
    pendingTokenResult = nil
  }

  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) -> Bool {
    guard (userInfo["type"] as? String) == "sync" else { return false }
    NSLog("[PushChannel] Silent push, Dart ready: \(dartReady)")
    if dartReady {
      runSync(completion: completionHandler)
    } else {
      queuedPushes.append(completionHandler)
    }
    return true
  }

  private func runSync(completion: @escaping (UIBackgroundFetchResult) -> Void) {
    // iOS allows ~30 s; Dart answers with the number of notifications it showed
    channel.invokeMethod("silentPush", arguments: nil) { reply in
      if let count = reply as? Int {
        completion(count > 0 ? .newData : .noData)
      } else {
        completion(.failed)
      }
    }
  }
}
