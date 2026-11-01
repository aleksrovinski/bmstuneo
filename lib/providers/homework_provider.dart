import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/homework_note.dart';

/// The student's homework notes. Stored only in SharedPreferences on the device.
class HomeworkProvider with ChangeNotifier {
  static const storageKey = 'homework_notes_v1';
  // Done notes are kept a while so an accidental tick can be undone, then dropped
  static const _keepDone = Duration(days: 14);

  /// Stored notes that could not be read are copied here before anything is saved
  /// over them, so a bad entry never takes the student's other notes with it.
  static const backupKey = 'homework_notes_v1_unreadable';

  final DateTime Function() _clock;
  List<HomeworkNote> _notes = [];
  bool _loaded = false;
  // Storage could not be read at all: saving now would replace notes we never saw
  bool _readFailed = false;
  late final Future<void> _ready;

  HomeworkProvider({DateTime Function()? clock, List<HomeworkNote>? seed}) : _clock = clock ?? DateTime.now {
    _ready = _load(seed);
  }

  bool get isLoaded => _loaded;

  /// Not done yet, soonest first.
  List<HomeworkNote> get pending => _notes.where((n) => !n.done).toList()..sort((a, b) => a.due.compareTo(b.due));

  List<HomeworkNote> get done => _notes.where((n) => n.done).toList()..sort((a, b) => b.due.compareTo(a.due));

  List<HomeworkNote> pendingFor(String disciplineTitle) =>
      pending.where((n) => n.disciplineTitle == disciplineTitle).toList();

  Future<void> _load(List<HomeworkNote>? seed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw != null && raw.isNotEmpty) {
        var unreadable = false;
        try {
          for (final item in jsonDecode(raw) as List) {
            try {
              _notes.add(HomeworkNote.fromJson(item as Map<String, dynamic>));
            } catch (e) {
              unreadable = true;
              debugPrint('[HomeworkProvider] Skipped an unreadable note: $e');
            }
          }
        } catch (e) {
          unreadable = true;
          debugPrint('[HomeworkProvider] Stored notes are unreadable: $e');
        }
        // Keep the original before the next save replaces it
        if (unreadable) await prefs.setString(backupKey, raw);
      } else if (seed != null) {
        _notes = [...seed];
        await _save();
      }
      final cutoff = _clock().subtract(_keepDone);
      _notes.removeWhere((n) => n.done && n.due.isBefore(cutoff));
    } catch (e) {
      _readFailed = true;
      debugPrint('[HomeworkProvider] Failed to load notes: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    if (_readFailed) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(_notes.map((n) => n.toJson()).toList()));
    } catch (e) {
      debugPrint('[HomeworkProvider] Failed to save notes: $e');
    }
  }

  Future<HomeworkNote> add({
    required String disciplineTitle,
    required String text,
    required HomeworkKind kind,
    required DateTime due,
  }) async {
    await _ready;
    final now = _clock();
    final note = HomeworkNote(
      id: '${now.microsecondsSinceEpoch}',
      disciplineTitle: disciplineTitle,
      text: text.trim(),
      kind: kind,
      due: due,
      createdAt: now,
    );
    _notes.add(note);
    notifyListeners();
    await _save();
    return note;
  }

  Future<void> update(HomeworkNote note) async {
    await _ready;
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i < 0) return;
    _notes[i] = note;
    notifyListeners();
    await _save();
  }

  Future<void> setDone(HomeworkNote note, bool done) => update(note.copyWith(done: done));

  Future<void> remove(HomeworkNote note) async {
    await _ready;
    _notes.removeWhere((n) => n.id == note.id);
    notifyListeners();
    await _save();
  }

  /// Puts a deleted note back (undo from a snackbar).
  Future<void> restore(HomeworkNote note) async {
    await _ready;
    if (_notes.any((n) => n.id == note.id)) return;
    _notes.add(note);
    notifyListeners();
    await _save();
  }
}
