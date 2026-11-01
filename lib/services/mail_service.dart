import 'dart:io';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';
import '../models/mail_folder.dart';
import '../models/mail_message.dart';
import 'bmstu_api_service.dart' show BmstuNetworkException;

/// The mail server rejected the login or password.
class MailAuthException implements Exception {
  final String message;
  MailAuthException([this.message = 'Неверный логин или пароль от почты']);
  @override
  String toString() => message;
}

/// student.bmstu.ru refused an operation (no such folder, full mailbox, bad address...).
class MailServerException implements Exception {
  final String message;
  MailServerException(this.message);
  @override
  String toString() => message;
}

// The XIMSS session is gone (idle timeout, server restart): sign in again and retry
class _SessionLost implements Exception {}

/// The signed-in mailbox owner as the server reports them.
class MailIdentity {
  final String email;
  final String realName;
  const MailIdentity({required this.email, this.realName = ''});
}

// The server's answer to one request of a batch: its data messages and the final status
class _Reply {
  final List<XmlElement> data = [];
  bool answered = false;
  String? error;

  void check() {
    if (!answered) throw MailServerException('Почтовый сервер МГТУ не ответил на запрос');
    final text = error;
    if (text != null) throw MailServerException(MailService.describeError(text));
  }
}

/// Student mail on student.bmstu.ru (CommuniGate Pro) over XIMSS, the XML protocol of
/// its Pronto web client: plain HTTPS requests, no long-lived IMAP connection.
///
/// The password is kept in memory only, to renew the session when the server drops it.
class MailService {
  static const host = 'student.bmstu.ru';
  static const pageSize = 30;
  // Header fields the server sends for every message of a folder listing
  static const _viewerFields = ['FLAGS', 'From', 'To', 'Subject', 'INTERNALDATE', 'SIZE', 'Content-Type'];
  // Text parts beyond this total stay on the server (shown as downloadable files)
  static const _readSizeLimit = 512 * 1024;

  final Dio _dio;
  final CookieJar _cookieJar;
  String? _sessionId;
  String? _userName;
  String? _password;
  MailIdentity? _identity;
  // Folders belong to a session: after it is renewed they are opened again
  final Set<String> _openFolders = {};
  Future<void>? _loginInFlight;
  int _requestSeq = 0;
  int _postSeq = 0;

  MailService({CookieJar? cookieJar})
      : _cookieJar = cookieJar ?? CookieJar(),
        _dio = Dio(BaseOptions(
          baseUrl: 'https://$host',
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
          headers: {'User-Agent': 'Mozilla/5.0 BMSTU-neo-Mail/1.0'},
        )) {
    // Pronto sessions can be tied to a cookie besides the session URL
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  @visibleForTesting
  set httpClientAdapter(HttpClientAdapter adapter) => _dio.httpClientAdapter = adapter;

  bool get isSignedIn => _sessionId != null;
  MailIdentity? get identity => _identity;

  /// Opens a mail session. Throws [MailAuthException] for a wrong login or password
  /// and [BmstuNetworkException] when the server can't be reached.
  Future<MailIdentity> login(String userName, String password) async {
    if (_sessionId != null) await logout();
    await _openSession(userName.trim(), password);
    _userName = userName.trim();
    _password = password;
    return _identity!;
  }

  /// Ends the session on the server (best effort) and forgets the credentials;
  /// downloaded attachments are deleted too unless [clearDownloads] is false.
  Future<void> logout({bool clearDownloads = true}) async {
    final sid = _sessionId;
    _sessionId = null;
    _userName = null;
    _password = null;
    _identity = null;
    _openFolders.clear();
    if (sid != null) {
      try {
        await _dio.post<String>(
          '/Session/$sid/sync',
          data: '<XIMSS><bye id="bye"/></XIMSS>',
          options: Options(contentType: 'text/xml; charset=utf-8', responseType: ResponseType.plain),
        );
      } catch (e) {
        debugPrint('[MailService] Logout request failed: $e');
      }
    }
    try {
      await _cookieJar.deleteAll();
    } catch (e) {
      debugPrint('[MailService] Failed to clear mail cookies: $e');
    }
    if (!clearDownloads) return;
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/mail');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('[MailService] Failed to clear downloaded attachments: $e');
    }
  }

  /// Mail mailboxes of the account; contacts, calendars and pure folders are skipped.
  Future<List<MailFolder>> fetchFolders() => _withSession(() async {
        final replies = await _sync([
          _el('mailboxList', {'mailboxClass': '', 'pureFolder': 'no'}),
        ]);
        replies.single.check();
        return parseMailboxes(replies.single.data);
      });

  /// Messages [from]..[from]+[count]-1 of [mailbox], newest first. [reopen] re-sorts
  /// the folder on the server so new mail shows up, and returns the folder counters.
  Future<MailPage> fetchPage(String mailbox, {int from = 0, int count = pageSize, bool reopen = false}) =>
      _withSession(() async {
        final reopening = reopen && _openFolders.contains(mailbox);
        final res = await _inFolder(mailbox, [
          if (reopening)
            _el('folderReopen', {'folder': mailbox, 'sortField': 'INTERNALDATE', 'sortOrder': 'desc'}),
          _el('folderBrowse', {'folder': mailbox}, [
            _el('index', {'from': '$from', 'till': '${from + count - 1}'}),
          ]),
        ]);
        for (final reply in res.replies) {
          reply.check();
        }
        // Counters come with the folder's "init" report, on open or reopen
        final initReport = [...?res.opened?.data, if (reopening) ...res.replies.first.data]
            .where((e) => e.localName == 'folderReport' && _attr(e, 'mode') == 'init')
            .lastOrNull;
        return MailPage(
          total: _intAttr(initReport, 'messages'),
          unseen: _intAttr(initReport, 'unseen'),
          items: res.replies.last.data
              .where((e) => e.localName == 'folderReport')
              .map(parseFolderReport)
              .whereType<MailSummary>()
              .toList(),
        );
      });

  /// Reads the whole message; by default it is marked as read on the server.
  Future<MailMessage> readMessage(String mailbox, int uid, {bool markSeen = true}) => _withSession(() async {
        final res = await _inFolder(mailbox, [
          _el('folderRead', {'folder': mailbox, 'UID': '$uid', 'totalSizeLimit': '$_readSizeLimit'}),
          if (markSeen) _el('messageMark', {'folder': mailbox, 'flags': 'Seen'}, [_uid(uid)]),
        ]);
        res.replies.first.check();
        final email = res.replies.first.data
            .where((e) => e.localName == 'folderMessage')
            .map((e) => e.getElement('EMail'))
            .nonNulls
            .firstOrNull;
        if (email == null) throw MailServerException('Письмо не найдено — возможно, его уже удалили');
        return parseEmail(email, mailbox: mailbox, uid: uid);
      });

  /// Sets or clears a message flag ("Seen", "Flagged"...).
  Future<void> setFlag(String mailbox, int uid, String flag, bool on) => _withSession(() async {
        final res = await _inFolder(mailbox, [
          _el('messageMark', {'folder': mailbox, 'flags': flag, if (!on) 'mode': 'delete'}, [_uid(uid)]),
        ]);
        res.replies.single.check();
      });

  /// Moves the message to Trash; a message already in Trash is deleted for good.
  Future<void> remove(String mailbox, int uid) => _withSession(() async {
        final res = await _inFolder(mailbox, [
          _el('messageRemove', {'folder': mailbox, 'mode': 'Move To Trash'}, [_uid(uid)]),
        ]);
        res.replies.single.check();
      });

  /// Sends [draft]; a copy is kept in [saveToMailbox] ("Sent Items") when given.
  Future<void> send(MailDraft draft, {String? saveToMailbox}) => _withSession(() async {
        final me = _identity;
        final forwarded = draft.forwardOf;
        final copies = forwarded?.attachments ?? const <MailAttachment>[];
        final text = _el('MIME', {'type': 'text', 'subtype': 'plain', 'charset': 'utf-8'}, [
          XmlText(draft.body.replaceAll('\r\n', '\n')),
        ]);
        final inReplyTo = draft.inReplyTo?.replaceAll(RegExp(r'^<|>$'), '').trim();
        final submit = _el('messageSubmit', {
          if (saveToMailbox != null) ...{'targetMailbox': saveToMailbox, 'flags': 'Seen'},
        }, [
          _el('EMail', const {}, [
            if (me != null) _address('From', MailAddress(email: me.email, name: me.realName)),
            for (final a in draft.to) _address('To', a),
            for (final a in draft.cc) _address('Cc', a),
            _el('Subject', const {}, [XmlText(draft.subject)]),
            if (inReplyTo != null && inReplyTo.isNotEmpty) ...[
              _el('In-Reply-To', const {}, [XmlText('<$inReplyTo>')]),
              _el('References', const {}, [XmlText('<$inReplyTo>')]),
            ],
            _el('X-Mailer', const {}, [XmlText('BMSTU neo')]),
            if (copies.isEmpty)
              text
            else
              // Forwarded files are copied on the server, nothing is uploaded
              _el('MIME', {'type': 'multipart', 'subtype': 'mixed'}, [
                text,
                for (final a in copies)
                  _el('copyMIME', {
                    'folder': forwarded!.mailbox,
                    'UID': '${forwarded.uid}',
                    if (a.partId.isNotEmpty) 'partID': a.partId,
                  }),
              ]),
          ]),
        ]);

        final replied = draft.replyingTo;
        final source = copies.isNotEmpty ? forwarded : replied;
        if (source == null) {
          final replies = await _sync([submit]);
          replies.single.check();
          return;
        }
        // copyMIME and the "Answered" mark work on the original's open folder
        final res = await _inFolder(source.mailbox, [
          submit,
          if (replied != null) _el('messageMark', {'folder': replied.mailbox, 'flags': 'Answered'}, [_uid(replied.uid)]),
        ]);
        res.replies.first.check();
      });

  /// Downloads [attachment] of [message] into the temp folder and returns the file.
  Future<File> downloadAttachment(MailMessage message, MailAttachment attachment) => _withSession(() async {
        // Parts are served from folders opened in the current session
        await _inFolder(message.mailbox, const []);
        final url = attachmentPath(_sessionId!, message, attachment);
        final Response<List<int>> resp;
        try {
          resp = await _dio.get<List<int>>(
            url,
            options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 3)),
          );
        } on DioException catch (e) {
          if (e.response?.statusCode == 550) throw _SessionLost();
          throw BmstuNetworkException.fromDio(e);
        }
        final dir = Directory('${(await getTemporaryDirectory()).path}/mail/${message.uid}-${attachment.partId}');
        await dir.create(recursive: true);
        final file = File('${dir.path}/${safeFileName(attachment.fileName)}');
        await file.writeAsBytes(resp.data ?? const []);
        return file;
      });

  /// Server path of the decoded attachment body: `/Session/<id>/MIME/<folder>/<UID>-<partID>-B.<ext>/<name>`.
  @visibleForTesting
  static String attachmentPath(String sessionId, MailMessage message, MailAttachment attachment) {
    final part = attachment.partId.isEmpty ? '' : '${attachment.partId}-';
    return '/Session/$sessionId/MIME/${Uri.encodeComponent(message.mailbox)}/'
        '${message.uid}-${part}B.${attachment.extension}/${Uri.encodeComponent(attachment.fileName)}';
  }

  // ---- Session plumbing ----

  Future<void> _openSession(String userName, String password) async {
    _sessionId = null;
    final Response<String> resp;
    try {
      resp = await _dio.post<String>(
        '/XIMSSLogin/',
        data: {
          'errorAsXML': '1',
          'userName': userName,
          'password': password,
          // Phones hop between Wi-Fi and mobile data: don't pin the session to one IP
          'DisableIPWatch': '1',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
        ),
      );
    } on DioException catch (e) {
      throw BmstuNetworkException.fromDio(e);
    }
    final session = parseLoginResponse(resp.data ?? '');
    _openFolders.clear();
    _postSeq = 0;
    _identity = session.identity;
    _sessionId = session.sessionId;
  }

  // Runs [action], signing in again once if the server dropped the session
  Future<T> _withSession<T>(Future<T> Function() action) async {
    if (_sessionId == null) await _renewSession();
    try {
      return await action();
    } on _SessionLost {
      await _renewSession();
      try {
        return await action();
      } on _SessionLost {
        throw MailServerException('Почтовый сервер МГТУ сбрасывает соединение. Попробуйте позже');
      }
    }
  }

  // Requests that find the session dead together share one login
  Future<void> _renewSession() {
    final pending = _loginInFlight;
    if (pending != null) return pending;

    final login = () async {
      final user = _userName;
      final pass = _password;
      if (user == null || pass == null) throw MailAuthException('Войдите в почту ещё раз');
      await _openSession(user, pass);
    }();
    _loginInFlight = login;
    login.whenComplete(() {
      if (identical(_loginInFlight, login)) _loginInFlight = null;
    }).ignore();
    return login;
  }

  // Sends [requests] to [mailbox], opening it first if this session hasn't yet.
  // [opened] is the folderOpen reply (with the folder counters) when it was sent.
  Future<({_Reply? opened, List<_Reply> replies})> _inFolder(String mailbox, List<XmlElement> requests) async {
    final needsOpen = !_openFolders.contains(mailbox);
    if (!needsOpen && requests.isEmpty) return (opened: null, replies: const <_Reply>[]);
    final replies = await _sync([
      if (needsOpen)
        _el('folderOpen', {
          // The folder is named after its mailbox, so MIME part URLs match either way
          'folder': mailbox,
          'mailbox': mailbox,
          'sortField': 'INTERNALDATE',
          'sortOrder': 'desc',
        }, [
          for (final f in _viewerFields) _el('field', const {}, [XmlText(f)]),
        ]),
      ...requests,
    ]);
    if (!needsOpen) return (opened: null, replies: replies);

    final opened = replies.first;
    final error = opened.error;
    if (opened.answered && (error == null || error.toLowerCase().contains('already'))) {
      _openFolders.add(mailbox);
    } else {
      opened.check();
    }
    return (opened: opened, replies: replies.sublist(1));
  }

  // One HTTP round trip with any number of XIMSS requests
  Future<List<_Reply>> _sync(List<XmlElement> requests) async {
    final sid = _sessionId;
    if (sid == null) throw _SessionLost();
    final ids = <String>[];
    for (final request in requests) {
      final id = 'm${++_requestSeq}';
      request.setAttribute('id', id);
      ids.add(id);
    }
    final Response<String> resp;
    try {
      resp = await _dio.post<String>(
        '/Session/$sid/sync',
        queryParameters: {'reqSeq': '${++_postSeq}'},
        data: XmlElement.tag('XIMSS', children: requests).toXmlString(),
        options: Options(contentType: 'text/xml; charset=utf-8', responseType: ResponseType.plain),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 550 || code == 404) throw _SessionLost();
      throw BmstuNetworkException.fromDio(e);
    }
    final root = _parseXimss(resp.data ?? '');
    // Anything but XIMSS (a login page, an empty body) means the session is not there
    if (root == null) throw _SessionLost();

    final replies = {for (final id in ids) id: _Reply()};
    for (final el in root.childElements) {
      final reply = replies[el.getAttribute('id')];
      // Messages without our id are asynchronous notifications
      if (reply == null) continue;
      if (el.localName == 'response') {
        reply.answered = true;
        final errorText = el.getAttribute('errorText');
        if (errorText != null && errorText.toLowerCase().contains('disconnected')) throw _SessionLost();
        reply.error = errorText ?? (el.getAttribute('errorNum') != null ? 'ошибка ${el.getAttribute('errorNum')}' : null);
      } else {
        reply.data.add(el);
      }
    }
    return [for (final id in ids) replies[id]!];
  }

  // ---- Parsing ----

  @visibleForTesting
  static ({String sessionId, MailIdentity identity}) parseLoginResponse(String body) {
    final root = _parseXimss(body);
    if (root == null) {
      throw MailServerException('Почтовый сервер МГТУ ответил непонятно. Попробуйте позже');
    }
    final first = root.childElements.firstOrNull;
    if (first != null && first.localName == 'session') {
      final id = first.getAttribute('urlID');
      if (id != null && id.isNotEmpty) {
        final user = first.getAttribute('userName') ?? '';
        return (
          sessionId: id,
          identity: MailIdentity(
            email: user.contains('@') ? user : '$user@$host',
            realName: first.getAttribute('realName') ?? '',
          ),
        );
      }
    }
    final error = first != null && first.localName == 'response' ? first.getAttribute('errorText') : null;
    final lower = (error ?? '').toLowerCase();
    if (error == null || lower.contains('password') || lower.contains('unknown') || lower.contains('incorrect')) {
      throw MailAuthException();
    }
    throw MailServerException('Почта МГТУ не пускает: $error');
  }

  /// Russian wording for the server's error texts users are likely to meet.
  static String describeError(String errorText) {
    final lower = errorText.toLowerCase();
    if (lower.contains('quota') || lower.contains('too large')) {
      return 'Почтовый ящик переполнен или письмо слишком большое';
    }
    if (lower.contains('unknown mailbox') || lower.contains('does not exist') || lower.contains('not found')) {
      return 'Папка или письмо не найдены на сервере';
    }
    if (lower.contains('address')) return 'Сервер не принял адрес: $errorText';
    return 'Почтовый сервер МГТУ: $errorText';
  }

  @visibleForTesting
  static List<MailFolder> parseMailboxes(List<XmlElement> data) {
    final folders = <MailFolder>[];
    for (final el in data.where((e) => e.localName == 'mailbox')) {
      final name = el.getAttribute('mailbox');
      if (name == null || name.isEmpty || _attr(el, 'pureFolder') == 'yes') continue;
      // Contacts, calendars, tasks and notes live in mailboxes of their own class
      final cls = _attr(el, 'class') ?? '';
      if (cls.startsWith('IPF.') && cls != 'IPF.Note') continue;
      folders.add(MailFolder(
        name: name,
        total: _intAttr(el, 'messages') ?? 0,
        unseen: _intAttr(el, 'unseen') ?? 0,
      ));
    }
    const order = [
      MailFolderRole.inbox,
      MailFolderRole.sent,
      MailFolderRole.drafts,
      MailFolderRole.other,
      MailFolderRole.junk,
      MailFolderRole.trash,
    ];
    folders.sort((a, b) {
      final byRole = order.indexOf(a.role).compareTo(order.indexOf(b.role));
      return byRole != 0 ? byRole : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return folders;
  }

  @visibleForTesting
  static MailSummary? parseFolderReport(XmlElement report) {
    final uid = _intAttr(report, 'UID');
    if (uid == null || _attr(report, 'mode') == 'error') return null;
    String field(String name) =>
        report.childElements.where((e) => e.localName.toLowerCase() == name.toLowerCase()).map(_text).firstOrNull ?? '';
    return MailSummary(
      uid: uid,
      from: field('From'),
      to: field('To'),
      subject: field('Subject'),
      date: parseXimssDate(field('INTERNALDATE')),
      flags: field('FLAGS').split(',').map((f) => f.trim()).where((f) => f.isNotEmpty).toSet(),
      size: int.tryParse(field('SIZE')) ?? 0,
      hasAttachments: field('Content-Type').toLowerCase().startsWith('multipart/mixed'),
    );
  }

  @visibleForTesting
  static MailMessage parseEmail(XmlElement email, {required String mailbox, required int uid}) {
    List<MailAddress> addresses(String field) => email.childElements
        .where((e) => e.localName == field)
        .map((e) => MailAddress(email: _text(e), name: e.getAttribute('realName')?.trim() ?? ''))
        .where((a) => a.email.isNotEmpty)
        .toList();
    String header(String field) => email.getElement(field) == null ? '' : _text(email.getElement(field)!);

    final files = <MailAttachment>[];
    final mime = email.getElement('MIME');
    final text = mime == null ? '' : _partText(mime, files);
    return MailMessage(
      mailbox: mailbox,
      uid: uid,
      subject: header('Subject'),
      from: addresses('From').firstOrNull,
      to: addresses('To'),
      cc: addresses('Cc'),
      replyTo: addresses('Reply-To').firstOrNull,
      date: parseXimssDate(header('Date')),
      messageId: header('Message-ID').replaceAll(RegExp(r'^<|>$'), ''),
      text: text.trim(),
      attachments: files,
    );
  }

  // Readable text of a MIME part; files met on the way are added to [files]
  static String _partText(XmlElement part, List<MailAttachment> files) {
    final type = (_attr(part, 'type') ?? 'text').toLowerCase();
    final subtype = (_attr(part, 'subtype') ?? 'plain').toLowerCase();
    final children = part.childElements.where((e) => e.localName == 'MIME').toList();

    if (type == 'multipart') {
      if (subtype == 'alternative' && children.isNotEmpty) {
        // The same content in several formats: plain text first, then the richer ones
        final candidates = [
          ...children.where((c) => (_attr(c, 'subtype') ?? '').toLowerCase() == 'plain'),
          ...children.reversed.where((c) => (_attr(c, 'subtype') ?? '').toLowerCase() != 'plain'),
        ];
        for (final candidate in candidates) {
          final found = <MailAttachment>[];
          final text = _partText(candidate, found);
          if (text.trim().isNotEmpty) {
            files.addAll(found);
            return text;
          }
        }
        return '';
      }
      return children.map((c) => _partText(c, files)).where((t) => t.trim().isNotEmpty).join('\n\n');
    }

    final disposition = (_attr(part, 'disposition') ?? '').toLowerCase();
    if (type == 'text' && (subtype == 'plain' || subtype == 'html') && disposition != 'attachment') {
      final body = _text(part, trim: false);
      // No body: the part was over the size limit, so it is offered as a file below
      if (body.trim().isNotEmpty) return subtype == 'html' ? htmlToPlainText(body) : body.trim();
    }
    if (subtype.endsWith('signature')) return '';

    final name = _attr(part, 'Disposition-filename') ?? _attr(part, 'Type-name') ?? '';
    final ext = type == 'message' ? 'eml' : (subtype == 'plain' ? 'txt' : subtype);
    files.add(MailAttachment(
      partId: _attr(part, 'partID') ?? '',
      fileName: name.trim().isNotEmpty
          ? name.trim()
          : type == 'message'
              ? 'Пересланное письмо.eml'
              : 'Вложение ${files.length + 1}.$ext',
      contentType: '$type/$subtype',
      size: _intAttr(part, 'estimatedSize') ?? 0,
    ));
    return '';
  }

  /// "20070830T184318Z" (iCalendar, GMT) in local time.
  @visibleForTesting
  static DateTime? parseXimssDate(String value) {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)').firstMatch(value.trim());
    if (m == null) return DateTime.tryParse(value.trim())?.toLocal();
    final parts = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
    return m.group(7) == 'Z'
        ? DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]).toLocal()
        : DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
  }

  /// A file name that is safe on every platform.
  static String safeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    return cleaned.isEmpty || cleaned == '.' || cleaned == '..' ? 'attachment' : cleaned;
  }

  static XmlElement? _parseXimss(String body) {
    try {
      final root = XmlDocument.parse(body).rootElement;
      return root.localName == 'XIMSS' ? root : null;
    } catch (_) {
      return null;
    }
  }

  // XIMSS writes the same attribute as "MESSAGES" or "messages", "type" or "Type"
  static String? _attr(XmlElement? el, String name) {
    if (el == null) return null;
    final exact = el.getAttribute(name);
    if (exact != null) return exact;
    final lower = name.toLowerCase();
    for (final a in el.attributes) {
      if (a.localName.toLowerCase() == lower) return a.value;
    }
    return null;
  }

  static int? _intAttr(XmlElement? el, String name) => int.tryParse(_attr(el, name) ?? '');

  // The element's own text, without nested elements
  static String _text(XmlElement el, {bool trim = true}) {
    final text = el.children.map((n) => n is XmlText || n is XmlCDATA ? n.value ?? '' : '').join();
    return trim ? text.trim() : text;
  }

  static XmlElement _el(String name, [Map<String, String> attributes = const {}, List<XmlNode> children = const []]) =>
      XmlElement.tag(
        name,
        attributes: [for (final e in attributes.entries) XmlAttribute(XmlName.qualified(e.key), e.value)],
        children: children,
      );

  static XmlElement _uid(int uid) => _el('UID', const {}, [XmlText('$uid')]);

  static XmlElement _address(String field, MailAddress a) =>
      _el(field, {if (a.name.isNotEmpty) 'realName': a.name}, [XmlText(a.email)]);
}

/// Readable plain text of an HTML letter: paragraphs and list items on their own
/// lines, links followed by their address, styles and scripts dropped.
String htmlToPlainText(String html) {
  var s = html
      .replaceAll(RegExp(r'<(head|style|script|title)\b[^>]*>.*?</\1\s*>', caseSensitive: false, dotAll: true), '')
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
      // Source line breaks don't show in HTML
      .replaceAll(RegExp(r'\s+'), ' ');
  s = s.replaceAllMapped(
    RegExp(r'''<a\b[^>]*?\bhref\s*=\s*(?:"([^"]*)"|'([^']*)')[^>]*>(.*?)</a\s*>''', caseSensitive: false, dotAll: true),
    (m) {
      final label = m[3] ?? '';
      var href = _decodeEntities((m[1] ?? m[2] ?? '').trim());
      if (href.isEmpty || href.startsWith('#') || href.toLowerCase().startsWith('javascript:')) return label;
      if (href.toLowerCase().startsWith('mailto:')) href = href.substring(7);
      final labelText = _decodeEntities(label.replaceAll(RegExp(r'<[^>]+>'), '')).trim();
      if (labelText.isEmpty || labelText == href) return href;
      return '$label ($href)';
    },
  );
  s = s
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '\n• ')
      .replaceAll(
        RegExp(r'</?(p|div|tr|table|ul|ol|h[1-6]|blockquote|section|article|header|footer|pre|hr)\b[^>]*>',
            caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'</t[dh]\s*>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  final lines = _decodeEntities(s).split('\n').map((l) => l.replaceAll(RegExp(r'[ \t ]+'), ' ').trim());
  return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

const _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'laquo': '«',
  'raquo': '»',
  'mdash': '—',
  'ndash': '–',
  'hellip': '…',
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'bull': '•',
  'middot': '·',
  'shy': '',
};

String _decodeEntities(String s) => s.replaceAllMapped(RegExp(r'&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
      final entity = m[1]!;
      if (entity.startsWith('#')) {
        final hex = entity.length > 1 && (entity[1] == 'x' || entity[1] == 'X');
        final code = int.tryParse(entity.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
        return code != null && code > 0 && code <= 0x10FFFF ? String.fromCharCode(code) : m[0]!;
      }
      return _namedEntities[entity.toLowerCase()] ?? m[0]!;
    });
