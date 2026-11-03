import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

/// Where the published library lives. Change this if the site moves.
const String kBaseUrl = 'https://anipix-stream.netlify.app';
const String kSupportUrl = 'https://t.me/lovelyanime2025';

class Api {
  static Future<Library> fetchLibrary() async {
    final uri = Uri.parse('$kBaseUrl/library.json?t=${DateTime.now().millisecondsSinceEpoch}');
    final res = await http.get(uri).timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) {
      throw Exception('Library not available (HTTP ${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected library format');
    }
    return Library.fromJson(decoded);
  }
}
