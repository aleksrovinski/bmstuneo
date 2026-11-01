import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/mail_folder.dart';
import '../models/mail_message.dart';
import '../constants/app_mode.dart';
import '../services/auth_storage.dart';
import '../services/background_sync.dart';
import '../services/mail_credentials_storage.dart';
import '../services/mail_service.dart';

enum MailStatus {
  /// No mail login yet (or it was rejected): the login form is shown
  signedOut,
  signingIn,
  /// Saved login exists, but the server couldn't be reached
  unavailable,
  ready,
}

/// Student mail state: session, folders, the open folder's message list.
class MailProvider with ChangeNotifier {
  final MailService mailService;
  final MailCredentialsStorage storage;
  /// LKS credentials, offered for the first mail sign-in (usually the same account)
  final AuthStorage authStorage;

  MailProvider({
    required this.mailService,
    required this.storage,
    required this.authStorage,
  });

  MailStatus _status = MailStatus.signedOut;
  String? _loginError;
  String? _listError;
  String? _savedLogin;
  String? _lksLogin;
  Future<void>? _restoring;
  bool _restored = false;
  bool _signingInSaved = false;
  bool? _wasAuthenticated;

  List<MailFolder> _folders = const [];
  String _mailbox = 'INBOX';
  final List<MailSummary> _messages = [];
  int? _total;
  bool _endReached = false;
  bool _listLoaded = false;
  bool _loadingList = false;
  bool _loadingMore = false;
  // Grows on every folder switch / refresh: late pages of the old list are dropped
  int _listGeneration = 0;

  MailStatus get status => _status;
  /// The saved login has been looked up (until then the screen shows a spinner, not the form)
  bool get restored => _restored;
  /// Signing in with the remembered login (no form to show meanwhile)
  bool get signingInSaved => _status == MailStatus.signingIn && _signingInSaved;
  String? get loginError => _loginError;
  String? get listError => _listError;
  /// The mail login last used on this device, to prefill the form
  String? get savedLogin => _savedLogin;
  /// LKS login with a saved password, offered as a one-tap mail sign-in
  String? get lksLogin => _lksLogin;
  MailIdentity? get identity => mailService.identity;

  List<MailFolder> get folders => _folders;
  String get mailbox => _mailbox;
  MailFolder get currentFolder =>
      _folders.where((f) => f.name == _mailbox).firstOrNull ?? MailFolder(name: _mailbox);
  List<MailSummary> get messages => List.unmodifiable(_messages);
  bool get isLoadingList => _loadingList;
  bool get isLoadingMore => _loadingMore;
  bool get listLoaded => _listLoaded;
  bool get hasMore => !_endReached && (_total == null || _messages.length < _total!);

  int get inboxUnseen => _folders.where((f) => f.role == MailFolderRole.inbox).firstOrNull?.unseen ?? 0;

  MailFolder? folderOf(MailFolderRole role) => _folders.where((f) => f.role == role).firstOrNull;

  /// Called by the AuthProvider proxy: signing out of the app signs out of mail too.
  void onAuthChanged(bool authenticated) {
    if (_wasAuthenticated == true && !authenticated) {
      // Not during the provider update itself: signOut notifies listeners
      Future.microtask(signOut);
    }
    _wasAuthenticated = authenticated;
  }

  /// Signs in with the saved mail login, once per app run. Safe to call often.
  Future<void> restore() => _restoring ??= _restore();

  Future<void> _restore() async {
    final saved = await storage.read();
    _savedLogin = saved.username;
    final lks = await authStorage.getCredentials();
    final lksUser = lks['username'];
    _lksLogin = lksUser != null && lksUser.isNotEmpty && (lks['password'] ?? '').isNotEmpty ? lksUser : null;
    _restored = true;

    final user = saved.username;
    final pass = saved.password;
    if (_status == MailStatus.ready || user == null || user.isEmpty || pass == null || pass.isEmpty) {
      notifyListeners();
      return;
    }
    await _signIn(user, pass, remember: false, fromSaved: true);
  }

  /// Signs in with the login and password typed into the mail form.
  Future<bool> login(String username, String password) => _signIn(username.trim(), password, remember: true);

  /// Signs in with the saved LKS login and password.
  Future<bool> loginWithLks() async {
    final lks = await authStorage.getCredentials();
    final user = lks['username'];
    final pass = lks['password'];
    if (user == null || user.isEmpty || pass == null || pass.isEmpty) {
      _lksLogin = null;
      _loginError = 'Пароль ЛКС не сохранён на этом устройстве — введите данные почты';
      notifyListeners();
      return false;
    }
    return _signIn(user.trim(), pass, remember: true);
  }

  Future<bool> _signIn(String user, String pass, {required bool remember, bool fromSaved = false}) async {
    _status = MailStatus.signingIn;
    _signingInSaved = fromSaved;
    _loginError = null;
    notifyListeners();
    try {
      await mailService.login(user, pass);
      if (remember) await storage.save(user, pass);
      _savedLogin = user;
      _status = MailStatus.ready;
      _listLoaded = false;
      notifyListeners();
      await refreshFolders();
      return true;
    } on MailAuthException catch (e) {
      if (fromSaved) {
        // The password was changed on the server: ask for the new one
        await storage.forgetPassword();
        _loginError = 'Пароль от почты не подошёл — возможно, его сменили. Войдите заново';
      } else {
        _loginError = e.message;
      }
      _status = MailStatus.signedOut;
    } catch (e) {
      _loginError = e.toString();
      _status = fromSaved ? MailStatus.unavailable : MailStatus.signedOut;
    }
    notifyListeners();
    return false;
  }

  /// Tries the saved login again after a network failure.
  Future<void> retry() {
    _restoring = null;
    return restore();
  }

  Future<void> signOut() async {
    _listGeneration++;
    await mailService.logout();
    await storage.clear();
    // No mail login left to check in the background
    if (!AppMode.isDemo) {
      try {
        if (await BackgroundSync.isMailEnabled()) await BackgroundSync.setMailEnabled(false);
      } catch (e) {
        debugPrint('[MailProvider] Failed to turn off mail notifications: $e');
      }
    }
    _status = MailStatus.signedOut;
    _restoring = null;
    _savedLogin = null;
    _loginError = null;
    _listError = null;
    _folders = const [];
    _mailbox = 'INBOX';
    _messages.clear();
    _total = null;
    _endReached = false;
    _listLoaded = false;
    _loadingList = false;
    _loadingMore = false;
    notifyListeners();
  }

  /// Folder list with counters (the inbox badge on the home screen).
  Future<void> refreshFolders() async {
    if (_status != MailStatus.ready) return;
    try {
      _folders = await mailService.fetchFolders();
      notifyListeners();
    } catch (e) {
      _handleError(e, silent: true);
    }
  }

  /// Loads the open folder once; later visits keep the list until a pull-to-refresh.
  Future<void> ensureListLoaded() async {
    if (_status != MailStatus.ready || _listLoaded || _loadingList) return;
    await refresh();
  }

  Future<void> openFolder(String mailbox) async {
    if (mailbox == _mailbox && _listLoaded) return;
    _mailbox = mailbox;
    _messages.clear();
    _total = null;
    _endReached = false;
    _listLoaded = false;
    await refresh();
  }

  /// First page of the open folder, with new mail; folder counters are updated too.
  Future<void> refresh() async {
    if (_status != MailStatus.ready) return;
    final generation = ++_listGeneration;
    _loadingList = true;
    _listError = null;
    notifyListeners();
    try {
      final page = await mailService.fetchPage(_mailbox, reopen: true);
      if (generation != _listGeneration) return;
      _messages
        ..clear()
        ..addAll(page.items);
      _total = page.total;
      _endReached = page.items.length < MailService.pageSize;
      _listLoaded = true;
      if (page.total != null) _updateFolder(_mailbox, total: page.total, unseen: page.unseen);
      unawaited(refreshFolders());
    } catch (e) {
      if (generation == _listGeneration) _handleError(e);
    } finally {
      if (generation == _listGeneration) {
        _loadingList = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (_status != MailStatus.ready || _loadingMore || _loadingList || !hasMore || !_listLoaded) return;
    final generation = _listGeneration;
    _loadingMore = true;
    notifyListeners();
    try {
      final page = await mailService.fetchPage(_mailbox, from: _messages.length);
      if (generation != _listGeneration) return;
      // A message may come twice if the folder was reopened after a reconnect
      final known = _messages.map((m) => m.uid).toSet();
      _messages.addAll(page.items.where((m) => !known.contains(m.uid)));
      if (page.items.length < MailService.pageSize) _endReached = true;
    } catch (e) {
      if (generation == _listGeneration) _handleError(e);
    } finally {
      if (generation == _listGeneration) {
        _loadingMore = false;
        notifyListeners();
      }
    }
  }

  /// Reads the full message; the server marks it as read, and so does the list.
  Future<MailMessage> readMessage(String mailbox, MailSummary summary) async {
    try {
      final message = await mailService.readMessage(mailbox, summary.uid);
      if (!summary.isSeen) _setLocalFlag(mailbox, summary.uid, 'Seen', true);
      return message;
    } on MailAuthException catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  Future<void> setSeen(MailSummary summary, bool seen) async {
    final mailbox = _mailbox;
    _setLocalFlag(mailbox, summary.uid, 'Seen', seen);
    try {
      await mailService.setFlag(mailbox, summary.uid, 'Seen', seen);
    } catch (e) {
      _setLocalFlag(mailbox, summary.uid, 'Seen', !seen);
      _handleError(e, silent: true);
      rethrow;
    }
  }

  /// Moves the message to Trash (deletes it for good when already there).
  Future<void> delete(String mailbox, int uid) async {
    await mailService.remove(mailbox, uid);
    if (mailbox == _mailbox) {
      final index = _messages.indexWhere((m) => m.uid == uid);
      if (index >= 0) {
        final removed = _messages.removeAt(index);
        if (_total != null) _total = _total! - 1;
        final folder = currentFolder;
        _updateFolder(mailbox,
            total: folder.total > 0 ? folder.total - 1 : 0,
            unseen: !removed.isSeen && folder.unseen > 0 ? folder.unseen - 1 : folder.unseen);
      }
      notifyListeners();
    }
    unawaited(refreshFolders());
  }

  Future<void> send(MailDraft draft) async {
    await mailService.send(draft, saveToMailbox: folderOf(MailFolderRole.sent)?.name);
    final replied = draft.replyingTo;
    if (replied != null) _setLocalFlag(replied.mailbox, replied.uid, 'Answered', true);
    if (currentFolder.role == MailFolderRole.sent) {
      unawaited(refresh());
    } else {
      unawaited(refreshFolders());
    }
  }

  Future<File> downloadAttachment(MailMessage message, MailAttachment attachment) =>
      mailService.downloadAttachment(message, attachment);

  void _setLocalFlag(String mailbox, int uid, String flag, bool on) {
    if (mailbox == _mailbox) {
      final index = _messages.indexWhere((m) => m.uid == uid);
      if (index >= 0) {
        final before = _messages[index];
        _messages[index] = before.withFlag(flag, on);
        if (flag == 'Seen' && before.isSeen != on) {
          final folder = currentFolder;
          _updateFolder(mailbox, unseen: (folder.unseen + (on ? -1 : 1)).clamp(0, 1 << 30));
        }
      }
    }
    notifyListeners();
  }

  void _updateFolder(String mailbox, {int? total, int? unseen}) {
    _folders = [
      for (final f in _folders) f.name == mailbox ? f.copyWith(total: total, unseen: unseen) : f,
    ];
  }

  void _handleError(Object e, {bool silent = false}) {
    debugPrint('[MailProvider] $e');
    if (e is MailAuthException) {
      // The session couldn't be renewed with the remembered password
      _status = MailStatus.signedOut;
      _loginError = e.message;
      unawaited(storage.forgetPassword());
    } else if (!silent) {
      _listError = e.toString();
    }
    notifyListeners();
  }
}
