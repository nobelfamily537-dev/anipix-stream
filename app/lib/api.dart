import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

/// Where the published library lives. Change this if the site moves.
const String kBaseUrl = 'https://anipix-stream.animeloverclipedits.workers.dev';

/// Content lives in the GitHub repo — this is the source of truth.
const String kGitHubRaw =
    'https://raw.githubusercontent.com/nobelfamily537-dev/anipix-stream/main/library.json';
const String kSupportUrl = 'https://t.me/lovelyanime2025';

/// Shared when the user taps Share — the site plus the app download.
const String kAppUrl = 'https://anipix.itch.io/anipix-stream';

const String kShareText =
    '🎬 AniPix Stream — anime subbed & dubbed in HD\n'
    'Download the app: $kAppUrl';

/// Shown in the app so you can tell which build is installed.
const String kAppVersion = '2.3.0';

class Api {
  /// Fire-and-forget view counter (Cloudflare KV). Safe to ignore failures.
  static void countView(String episodeId) {
    try {
      http
          .post(
            Uri.parse('$kBaseUrl/api/view'),
            headers: {'content-type': 'application/json'},
            body: '{"id":"$episodeId"}',
          )
          .timeout(const Duration(seconds: 8))
          .catchError((_) => http.Response('', 0));
    } catch (_) {}
  }

  /// Returns episodeId -> views. Empty when the KV namespace is not set up.
  static Future<Map<String, int>> fetchViews() async {
    try {
      final res = await http.get(Uri.parse('$kBaseUrl/api/view')).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return {};
      final j = jsonDecode(res.body);
      final v = (j is Map) ? j['views'] : null;
      if (v is! Map) return {};
      return v.map((k, val) => MapEntry(k.toString(), (val as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  /// The last library JSON as received — the admin screen publishes this back.
  static Map<String, dynamic>? lastRaw;

  /// Reads the live library. Tries the Netlify function first (instant updates
  /// from the admin panel) and falls back to the static file in the repo.
  static Future<Library> fetchLibrary() async {
    final sources = <String>[
      kGitHubRaw,
      '$kBaseUrl/.netlify/functions/library',
      '$kBaseUrl/library.json',
    ];
    Object? lastError;

    for (final src in sources) {
      try {
        final uri = Uri.parse('$src?t=${DateTime.now().millisecondsSinceEpoch}');
        final res = await http.get(uri).timeout(const Duration(seconds: 25));
        if (res.statusCode != 200) {
          lastError = Exception('HTTP ${res.statusCode}');
          continue;
        }
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is! Map<String, dynamic>) {
          lastError = Exception('Unexpected library format');
          continue;
        }
        lastRaw = decoded;
        final lib = Library.fromJson(decoded);
        if (lib.version == 0 && lib.playlists.isEmpty) {
          lastError = Exception('Library is empty');
          continue;
        }
        return lib;
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception(
      lastError?.toString().replaceFirst('Exception: ', '') ?? 'Could not load the library',
    );
  }
}
