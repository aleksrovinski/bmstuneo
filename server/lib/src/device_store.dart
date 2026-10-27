import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'device.dart';

/// Where registered devices live. A JSON file is enough for one server and a few
/// thousand installations; a database-backed store can replace it behind this interface.
abstract class DeviceStore {
  Future<Device?> get(String installationId);
  Future<void> put(Device device);
  Future<void> delete(String installationId);
  Future<List<Device>> all();
}

class InMemoryDeviceStore implements DeviceStore {
  final Map<String, Device> _devices = {};

  @override
  Future<Device?> get(String installationId) async => _devices[installationId];

  @override
  Future<void> put(Device device) async => _devices[device.installationId] = device;

  @override
  Future<void> delete(String installationId) async => _devices.remove(installationId);

  @override
  Future<List<Device>> all() async => _devices.values.toList();
}

/// Keeps everything in memory and rewrites one JSON file on each change.
///
/// Writes go to a temporary file that is then renamed over the old one, so a
/// crash mid-write never leaves a truncated file. Writes are serialized.
class FileDeviceStore implements DeviceStore {
  final File _file;
  final Map<String, Device> _devices;
  Future<void> _lastWrite = Future.value();

  FileDeviceStore._(this._file, this._devices);

  static Future<FileDeviceStore> open(String path) async {
    final file = File(path);
    final devices = <String, Device>{};
    if (await file.exists()) {
      final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      for (final raw in (decoded['devices'] as List).cast<Map<String, dynamic>>()) {
        final device = Device.fromJson(raw);
        devices[device.installationId] = device;
      }
    } else {
      await file.parent.create(recursive: true);
    }
    return FileDeviceStore._(file, devices);
  }

  @override
  Future<Device?> get(String installationId) async => _devices[installationId];

  @override
  Future<void> put(Device device) {
    _devices[device.installationId] = device;
    return _persist();
  }

  @override
  Future<void> delete(String installationId) {
    if (_devices.remove(installationId) == null) return Future.value();
    return _persist();
  }

  @override
  Future<List<Device>> all() async => _devices.values.toList();

  Future<void> _persist() {
    // Snapshot now, write after the previous write finished
    final snapshot = jsonEncode({
      'version': 1,
      'devices': _devices.values.map((d) => d.toJson()).toList(),
    });
    return _lastWrite = _lastWrite.then((_) async {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(snapshot, flush: true);
      await tmp.rename(_file.path);
    });
  }
}
