import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

/// Where the published library lives. Change this if the site moves.
const String kBaseUrl = 'https://anipix-stream.netlify.app';
const String kSupportUrl = 'https://t.me/lovelyanime2025';

class Api {
  /// Reads the live library. Tries the Netlify function first (instant updates
  /// from the admin panel) and falls back to the static file in the repo.
  static Future<Library> fetchLibrary() async {
    final sources = <String>[
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
