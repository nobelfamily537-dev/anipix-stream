import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';
import 'scope.dart';
import 'store.dart';
import 'ui.dart';

/// Publishes changes straight to the site (same endpoint the admin panel uses).
class AdminService {
  static const String _keyPref = 'anipix_publish_key';

  static Future<String?> savedKey() async {
    final p = await SharedPreferences.getInstance();
    final k = p.getString(_keyPref);
    return (k == null || k.isEmpty) ? null : k;
  }

  static Future<void> saveKey(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyPref, key);
  }

  /// Merges [episode] into the current library and publishes it.
  static Future<String> publishEpisode({
    required Map<String, dynamic> episode,
    required String key,
  }) async {
    final raw = Api.lastRaw;
    if (raw == null) return 'Library not loaded yet. Pull to refresh and try again.';

    final next = Map<String, dynamic>.from(raw);
    final episodes = List<dynamic>.from((next['episodes'] as List?) ?? const []);
    episodes.removeWhere((e) => e is Map && e['id'] == episode['id']);
    episodes.add(episode);
    next['episodes'] = episodes;
    next['version'] = DateTime.now().millisecondsSinceEpoch;

    try {
      final res = await http
          .post(
            Uri.parse('$kBaseUrl/api/library'),
            headers: {
              'content-type': 'application/json',
              'x-publish-key': key,
            },
            body: jsonEncode(next),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) return 'Server said HTTP ${res.statusCode}.';
      final j = jsonDecode(res.body);
      if (j is Map && j['ok'] == true) {
        Api.lastRaw = next;
        return '';
      }
      return (j is Map ? (j['error'] ?? 'Publish failed') : 'Publish failed').toString();
    } catch (e) {
      return 'Network error: $e';
    }
  }
}

/// Uploads a video to UFOLOAD and returns the embed link.
class UfoloadService {
  static const String _keyPref = 'ufoload_api_key';

  static Future<String?> savedKey() async {
    final p = await SharedPreferences.getInstance();
    final k = p.getString(_keyPref);
    return (k == null || k.isEmpty) ? null : k;
  }

  static Future<void> saveKey(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyPref, key.trim());
  }

  /// Returns the embed url, or throws with a readable message.
  static Future<String> upload(String path, String key) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('https://ufoload.com/api/v1/files?folder_id=root'),
    );
    req.headers['Authorization'] = 'Bearer ${key.trim()}';
    req.files.add(await http.MultipartFile.fromPath('file', path));

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode == 401) throw 'API key galat hai (401).';
    if (streamed.statusCode == 413) throw 'File plan limit se badi hai (413).';
    if (streamed.statusCode == 409) throw 'Storage full (409).';
    if (streamed.statusCode != 200 && streamed.statusCode != 201) {
      throw 'Upload failed (${streamed.statusCode}).';
    }

    final j = jsonDecode(body);
    final file = (j is Map) ? j['file'] : null;
    final pid = (file is Map) ? (file['public_id'] ?? '') : '';
    if (pid.toString().isEmpty) throw 'Upload hua par public_id nahi mila.';

    /* status moves uploading -> queued -> processing -> ready */
    return 'https://iframe.andromedans.live/e/$pid';
  }
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _key = TextEditingController();
  final _epNo = TextEditingController(text: '1');
  final _title = TextEditingController();
  final _url = TextEditingController();
  final _quality = TextEditingController(text: '720p');
  final _ufoKey = TextEditingController();
  bool _uploading = false;
  String? _uploadInfo;

  String? _playlistId;
  int _season = 1;
  String _kind = 'embed';
  bool _busy = false;
  String? _message;
  bool _messageOk = false;

  @override
  void initState() {
    super.initState();
    AdminService.savedKey().then((k) {
      if (k != null && mounted) setState(() => _key.text = k);
    });
    UfoloadService.savedKey().then((k) {
      if (k != null && mounted) setState(() => _ufoKey.text = k);
    });
  }

  @override
  void dispose() {
    _key.dispose();
    _epNo.dispose();
    _title.dispose();
    _url.dispose();
    _quality.dispose();
    _ufoKey.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final lib = LibScope.of(context).library;
    if (lib == null) return;

    final pid = _playlistId;
    final n = int.tryParse(_epNo.text.trim()) ?? 0;
    final url = _url.text.trim();

    if (pid == null) return _fail('Pick a playlist.');
    if (n <= 0) return _fail('Episode number must be 1 or more.');
    if (!url.startsWith('http')) return _fail('Paste a full link (https://…).');
    if (_key.text.trim().isEmpty) return _fail('Publish key is required.');

    setState(() {
      _busy = true;
      _message = null;
    });

    final episode = {
      'id': 'e${DateTime.now().millisecondsSinceEpoch}',
      'playlistId': pid,
      'season': _season,
      'n': n,
      'title': _title.text.trim(),
      'at': DateTime.now().millisecondsSinceEpoch,
      'sources': [
        {'q': _quality.text.trim().isEmpty ? 'HD' : _quality.text.trim(), 'url': url, 'kind': _kind}
      ],
      'downloads': <Map<String, String>>[],
    };

    final err = await AdminService.publishEpisode(episode: episode, key: _key.text.trim());
    if (!mounted) return;

    if (err.isEmpty) {
      await AdminService.saveKey(_key.text.trim());
      setState(() {
        _busy = false;
        _messageOk = true;
        _message = 'Published — site and app both updated.';
        _url.clear();
        _title.clear();
      });
      await LibScope.of(context).reload();
    } else {
      setState(() {
        _busy = false;
        _messageOk = false;
        _message = err;
      });
    }
  }

  Future<void> _pickAndUpload() async {
    if (_ufoKey.text.trim().isEmpty) {
      setState(() {
        _uploadInfo = 'Pehle UFOLOAD API key daalo (ufo_...).';
      });
      return;
    }
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.video);
      final path = picked?.files.single.path;
      if (path == null) return;

      setState(() {
        _uploading = true;
        _uploadInfo = 'Uploading… bada file hai to kuch minute lagenge.';
      });

      final embed = await UfoloadService.upload(path, _ufoKey.text);
      await UfoloadService.saveKey(_ufoKey.text);

      if (!mounted) return;
      setState(() {
        _uploading = false;
        _url.text = embed;
        _kind = 'embed';
        _uploadInfo = 'Upload ho gaya. Convert hone mein 5-15 min — phir link chalega.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadInfo = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _fail(String msg) {
    setState(() {
      _messageOk = false;
      _message = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lib = LibScope.of(context).library;
    final playlists = lib?.playlists ?? const <Playlist>[];
    if (_playlistId == null && playlists.isNotEmpty) {
      _playlistId = playlists.first.id;
    }
    final seasons = <int>{1, if (lib != null && _playlistId != null)
      ...lib.episodesOf(_playlistId!).map((e) => e.season)};

    return Scaffold(
      appBar: AppBar(title: const Text('Admin — add episode')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Publish key',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
          const SizedBox(height: 6),
          TextField(
            controller: _key,
            obscureText: true,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(hintText: 'anipix-pub-…'),
          ),
          const SizedBox(height: 18),

          const Text('Playlist',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: kSurface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kLine),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _playlistId,
                isExpanded: true,
                dropdownColor: kSurface,
                items: [
                  for (final p in playlists)
                    DropdownMenuItem(value: p.id, child: Text(p.title, style: const TextStyle(fontSize: 13))),
                ],
                onChanged: (v) => setState(() => _playlistId = v),
              ),
            ),
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Season',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: kSurface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kLine),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _season,
                          isExpanded: true,
                          dropdownColor: kSurface,
                          items: [
                            for (final s in seasons.toList()..sort())
                              DropdownMenuItem(value: s, child: Text('Season $s', style: const TextStyle(fontSize: 13))),
                          ],
                          onChanged: (v) => setState(() => _season = v ?? 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Episode no.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _epNo,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          const Text('Episode title (optional)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
          const SizedBox(height: 6),
          TextField(
            controller: _title,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(hintText: 'e.g. The witch awakens'),
          ),
          const SizedBox(height: 14),

          /* ---------- UFOLOAD ---------- */
          const Text('UFOLOAD API key (ufo_…)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
          const SizedBox(height: 6),
          TextField(
            controller: _ufoKey,
            obscureText: true,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(hintText: 'ufo_…'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: kBrand.withOpacity(0.6)),
                foregroundColor: kBrand,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _uploading ? null : _pickAndUpload,
              icon: _uploading
                  ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_outlined, size: 17),
              label: Text(_uploading ? 'Uploading…' : 'Pick video & upload to UFOLOAD',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ),
          if (_uploadInfo != null) ...[
            const SizedBox(height: 6),
            Text(_uploadInfo!, style: const TextStyle(fontSize: 11.5, color: kMuted, height: 1.4)),
          ],
          const SizedBox(height: 16),

          const Text('Video link',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
          const SizedBox(height: 6),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(hintText: 'https://…'),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Quality',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
                    const SizedBox(height: 6),
                    TextField(controller: _quality, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Type',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: kSurface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kLine),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _kind,
                          isExpanded: true,
                          dropdownColor: kSurface,
                          items: const [
                            DropdownMenuItem(value: 'embed', child: Text('Embed (iframe)', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'file', child: Text('Direct MP4', style: TextStyle(fontSize: 13))),
                          ],
                          onChanged: (v) => setState(() => _kind = v ?? 'embed'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          SizedBox(
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrand,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Publish episode', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),

          if (_message != null) ...[
            const SizedBox(height: 14),
            Text(_message!,
                style: TextStyle(
                    fontSize: 12.5, color: _messageOk ? kBrand : const Color(0xFFFF9D9D))),
          ],

          const SizedBox(height: 20),
          const Text(
            'Publishing writes library.json to the repo. The website and every app pick it up on the next refresh.',
            style: TextStyle(fontSize: 11, color: kMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
