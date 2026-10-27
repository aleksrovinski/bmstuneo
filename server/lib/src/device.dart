import 'dart:convert';
import 'package:crypto/crypto.dart';

/// One app installation that asked for silent pushes.
///
/// Holds nothing about the student: a push token, the group UUID (for future
/// schedule-change pushes) and bookkeeping. The installation proves ownership
/// of the record with a secret; only its SHA-256 is stored.
class Device {
  final String installationId;
  final String secretHash;
  final String platform; // 'apns' | 'fcm'
  final String token;
  final String? groupUuid;

  /// APNs environment the token belongs to, learned from Apple's answers:
  /// 'production' (App Store / TestFlight) or 'sandbox' (Xcode builds). Null until known.
  final String? apnsEnvironment;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastPushAt;

  const Device({
    required this.installationId,
    required this.secretHash,
    required this.platform,
    required this.token,
    required this.createdAt,
    required this.updatedAt,
    this.groupUuid,
    this.apnsEnvironment,
    this.lastPushAt,
  });

  static String hashSecret(String secret) => sha256.convert(utf8.encode(secret)).toString();

  /// Constant-time comparison, so response timing doesn't leak the hash.
  bool secretMatches(String secret) {
    final candidate = hashSecret(secret);
    if (candidate.length != secretHash.length) return false;
    var diff = 0;
    for (var i = 0; i < candidate.length; i++) {
      diff |= candidate.codeUnitAt(i) ^ secretHash.codeUnitAt(i);
    }
    return diff == 0;
  }

  Device copyWith({
    String? platform,
    String? token,
    String? groupUuid,
    bool clearGroup = false,
    String? apnsEnvironment,
    bool clearApnsEnvironment = false,
    DateTime? updatedAt,
    DateTime? lastPushAt,
  }) =>
      Device(
        installationId: installationId,
        secretHash: secretHash,
        platform: platform ?? this.platform,
        token: token ?? this.token,
        groupUuid: clearGroup ? null : (groupUuid ?? this.groupUuid),
        apnsEnvironment: clearApnsEnvironment ? null : (apnsEnvironment ?? this.apnsEnvironment),
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        lastPushAt: lastPushAt ?? this.lastPushAt,
      );

  Map<String, dynamic> toJson() => {
        'installationId': installationId,
        'secretHash': secretHash,
        'platform': platform,
        'token': token,
        if (groupUuid != null) 'groupUuid': groupUuid,
        if (apnsEnvironment != null) 'apnsEnvironment': apnsEnvironment,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (lastPushAt != null) 'lastPushAt': lastPushAt!.toIso8601String(),
      };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        installationId: json['installationId'] as String,
        secretHash: json['secretHash'] as String,
        platform: json['platform'] as String,
        token: json['token'] as String,
        groupUuid: json['groupUuid'] as String?,
        apnsEnvironment: json['apnsEnvironment'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        lastPushAt: json['lastPushAt'] == null ? null : DateTime.parse(json['lastPushAt'] as String),
      );
}
