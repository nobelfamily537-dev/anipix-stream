import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local storage: accounts, session, watchlist, history.
/// Everything stays on the device — there is no server behind this build.
class Store {
  Store._();
  static final Store i = Store._();

  SharedPreferences? _p;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  static String hash(String s) => sha256.convert(utf8.encode(s)).toString();

  /* The site owner's account is built in, so it works on any device. */
  static const String adminEmail = 'animeloverclipedits@gmail.com';
  static const String _adminHash =
      'e87bcbae7c2c19af1894700eedebf67f21bfdb7b267ccf40f16b1598137188a7';

  bool get isAdmin => (user?['email'] ?? '').toString().toLowerCase() == adminEmail;

  List<Map<String, dynamic>> get _users {
    final raw = _p?.getString('users');
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _saveUsers(List<Map<String, dynamic>> u) async {
    await _p?.setString('users', jsonEncode(u));
  }

  String? get sessionEmail => _p?.getString('session');

  Map<String, dynamic>? get user {
    final email = sessionEmail;
    if (email == null) return null;
    for (final u in _users) {
      if ((u['email'] ?? '').toString().toLowerCase() == email.toLowerCase()) return u;
    }
    return null;
  }

  bool get signedIn => user != null;

  Future<String?> signUp(String name, String email, String pass) async {
    final n = name.trim();
    final e = email.trim().toLowerCase();
    if (!RegExp(r'^[a-zA-Z0-9_.]{3,18}$').hasMatch(n)) {
      return 'Username: 3-18 letters, numbers, _ or .';
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(e)) {
      return 'Enter a valid email address.';
    }
    if (pass.length < 8) return 'Password must be at least 8 characters.';
    final users = _users;
    if (users.any((u) => (u['email'] ?? '').toString().toLowerCase() == e)) {
      return 'That email is already registered.';
    }
    users.add({
      'name': n,
      'email': e,
      'pass': hash(pass),
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    await _saveUsers(users);
    await _p?.setString('session', e);
    return null;
  }

  Future<String?> signIn(String email, String pass) async {
    final e = email.trim().toLowerCase();
    for (final u in _users) {
      if ((u['email'] ?? '').toString().toLowerCase() == e) {
        if ((u['pass'] ?? '') == hash(pass)) {
          await _p?.setString('session', e);
          return null;
        }
        return 'Incorrect password.';
      }
    }
    /* first sign-in of the owner account on this device */
    if (e == adminEmail && hash(pass) == _adminHash) {
      final users = _users;
      users.add({
        'name': 'AniPixAdmin',
        'email': adminEmail,
        'pass': _adminHash,
        'admin': true,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      await _saveUsers(users);
      await _p?.setString('session', e);
      return null;
    }

    return 'No account on this device with that email. Tap Sign up to create one.';
  }

  Future<void> signOut() async {
    await _p?.remove('session');
  }

  List<String> get watchlist => _p?.getStringList('watchlist') ?? <String>[];

  bool inWatchlist(String id) => watchlist.contains(id);

  Future<void> toggleWatchlist(String id) async {
    final list = watchlist;
    if (list.contains(id)) {
      list.remove(id);
    } else {
      list.add(id);
    }
    await _p?.setStringList('watchlist', list);
  }

  List<Map<String, dynamic>> get history {
    final raw = _p?.getString('history');
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> pushHistory(String playlistId, int season, int n) async {
    final list = history.where((h) => h['pid'] != playlistId || h['season'] != season || h['n'] != n).toList();
    list.insert(0, {
      'pid': playlistId,
      'season': season,
      'n': n,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    await _p?.setString('history', jsonEncode(list.take(100).toList()));
  }
}
