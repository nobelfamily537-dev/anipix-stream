import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'ui.dart';

/// Reads the latest GitHub release and compares it with the installed version.
class UpdateInfo {
  final String version;
  final String url;
  final String notes;
  const UpdateInfo({required this.version, required this.url, required this.notes});
}

const String _releasesUrl =
    'https://api.github.com/repos/nobelfamily537-dev/anipix-stream/releases/latest';

List<int> _parts(String v) => v
    .replaceAll(RegExp(r'[^0-9.]'), '')
    .split('.')
    .map((e) => int.tryParse(e) ?? 0)
    .toList();

bool _isNewer(String remote, String local) {
  final a = _parts(remote);
  final b = _parts(local);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x > y) return true;
    if (x < y) return false;
  }
  return false;
}

Future<UpdateInfo?> checkForUpdate() async {
  try {
    final res = await http.get(
      Uri.parse(_releasesUrl),
      headers: {'accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;

    final j = jsonDecode(res.body);
    if (j is! Map) return null;

    final tag = (j['tag_name'] ?? '').toString().replaceFirst('v', '');
    if (tag.isEmpty) return null;
    if (!_isNewer(tag, kAppVersion)) return null;

    var url = '';
    for (final a in (j['assets'] as List? ?? const [])) {
      if (a is Map && (a['name'] ?? '').toString().toLowerCase().endsWith('.apk')) {
        url = (a['browser_download_url'] ?? '').toString();
        break;
      }
    }
    if (url.isEmpty) return null;

    return UpdateInfo(version: tag, url: url, notes: (j['body'] ?? '').toString());
  } catch (_) {
    return null;
  }
}

Future<void> openUpdate(UpdateInfo info) async {
  final uri = Uri.parse(info.url);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    await launchUrl(uri);
  }
}

/// Blocking prompt shown when the app opens on an old version.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Update available', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A newer version (v${info.version}) is available.\nYou are on v$kAppVersion.',
            style: const TextStyle(fontSize: 13, height: 1.5, color: kMuted),
          ),
          if (info.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(info.notes.trim(),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.45, color: Color(0xFFB9B9C7))),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Later', style: TextStyle(color: kMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kBrand, foregroundColor: Colors.white),
          onPressed: () {
            Navigator.of(ctx).pop();
            openUpdate(info);
          },
          child: const Text('Update now'),
        ),
      ],
    ),
  );
}
