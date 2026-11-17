import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Firebase accounts + per-user plan/usage.
///
/// Everything is wrapped so the app keeps working on the local store if
/// Firebase is not reachable (offline, no config, etc).
class FirebaseService {
  static bool ready = false;

  static FirebaseAuth? get _auth => ready ? FirebaseAuth.instance : null;
  static FirebaseFirestore? get _db => ready ? FirebaseFirestore.instance : null;

  static String get uid => _auth?.currentUser?.uid ?? '';
  static String get email => _auth?.currentUser?.email ?? '';
  static bool get signedIn => _auth?.currentUser != null;

  /// Returns null on success, or an error message.
  static Future<String?> signUp(String name, String mail, String pass) async {
    final a = _auth;
    if (a == null) return 'Firebase not ready';
    try {
      final cred = await a.createUserWithEmailAndPassword(email: mail.trim(), password: pass);
      final user = cred.user;
      if (user != null) {
        await user.updateDisplayName(name.trim());
        try {
          await _db?.collection('users').doc(user.uid).set({
            'name': name.trim(),
            'email': mail.trim().toLowerCase(),
            'plan': 'basic',
            'planUntil': null,
            'createdAt': FieldValue.serverTimestamp(),
            'dailyDate': '',
            'dailyCount': 0,
          });
        } catch (_) {}
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return _msg(e);
    } catch (e) {
      return 'Signup failed: $e';
    }
  }

  static Future<String?> signIn(String mail, String pass) async {
    final a = _auth;
    if (a == null) return 'Firebase not ready';
    try {
      await a.signInWithEmailAndPassword(email: mail.trim(), password: pass);
      return null;
    } on FirebaseAuthException catch (e) {
      return _msg(e);
    } catch (e) {
      return 'Sign in failed: $e';
    }
  }

  static Future<void> signOut() async {
    try {
      await _auth?.signOut();
    } catch (_) {}
  }

  /// {plan, planUntil, dailyCount, dailyDate}
  static Future<Map<String, dynamic>> profile() async {
    final db = _db;
    final id = uid;
    if (db == null || id.isEmpty) return {};
    try {
      final doc = await db.collection('users').doc(id).get();
      return doc.data() ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Counts one episode for today. Returns the new count.
  static Future<int> bumpDaily() async {
    final db = _db;
    final id = uid;
    if (db == null || id.isEmpty) return 0;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    try {
      final ref = db.collection('users').doc(id);
      final doc = await ref.get();
      final data = doc.data() ?? {};
      final sameDay = (data['dailyDate'] ?? '') == today;
      final next = sameDay ? ((data['dailyCount'] as num?)?.toInt() ?? 0) + 1 : 1;
      await ref.set({
        'dailyDate': today,
        'dailyCount': next,
      }, SetOptions(merge: true));
      return next;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> dailyCount() async {
    final p = await profile();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if ((p['dailyDate'] ?? '') != today) return 0;
    return (p['dailyCount'] as num?)?.toInt() ?? 0;
  }

  static String _msg(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already registered. Try signing in.';
      case 'invalid-email':
        return 'That email address looks wrong.';
      case 'weak-password':
        return 'Password is too weak (6+ characters).';
      case 'user-not-found':
        return 'No account with that email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect password.';
      case 'too-many-requests':
        return 'Too many attempts. Try again in a few minutes.';
      case 'network-request-failed':
        return 'No internet connection.';
      default:
        return e.message ?? e.code;
    }
  }
}
