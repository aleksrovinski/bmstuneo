import 'device.dart';

enum PushOutcome {
  /// Accepted by APNs/FCM.
  delivered,

  /// The token is dead (app removed, notifications turned off): forget the device.
  invalidToken,

  /// Temporary problem (rate limit, server error, network): try again later.
  retryLater,
}

class PushResult {
  final PushOutcome outcome;

  /// For APNs: the environment that accepted the token, to remember on the device.
  final String? apnsEnvironment;
  final String? detail;

  const PushResult(this.outcome, {this.apnsEnvironment, this.detail});

  @override
  String toString() => '${outcome.name}${detail == null ? '' : ' ($detail)'}';
}

/// Sends the silent "check now" push: {"type": "sync"}, no student data.
abstract class PushSender {
  Future<PushResult> sendSync(Device device);
}
