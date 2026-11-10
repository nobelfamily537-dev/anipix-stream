import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';
import 'scope.dart';
import 'ui.dart';

/// Publishes the library straight to the site.
class AdminService {
  static const String _keyPref = 'anipix_publish_key';

  static Future<String?> savedKey() async {
    final p = await SharedPreferences.getInstance();
    final k = p.getString(_keyPref);
    return (k == null || k.isEmpty) ? null : k;
  }

  static Future<void> saveKey(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyPref, key.trim());
  }

  /// Uploads an image to the repo through the worker and returns its URL.
  static Future<String> uploadImage(String path) async {
    final key = await savedKey() ?? '';
    if (key.isEmpty) return '';
    final bytes = await File(path).readAsBytes();
    final name = path.split('/').last;
    try {
      final res = await http
          .post(
            Uri.parse('$kBaseUrl/api/media'),
            headers: {'content-type': 'application/json', 'x-publish-key': key},
            body: jsonEncode({'name': name, 'data': base64Encode(bytes)}),
          )
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) return '';
      final j = jsonDecode(res.body);
      return (j is Map && j['ok'] == true) ? (j['url'] ?? '').toString() : '';
    } catch (_) {
      return '';
    }
  }

  /// Applies [mutate] to the raw library JSON and publishes it.
  static Future<String> publish(String key, void Function(Map<String, dynamic> raw) mutate) async {
    final raw = Api.lastRaw;
    if (raw == null) return 'Library not loaded. Pull to refresh and try again.';

    final next = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    mutate(next);
    next['version'] = DateTime.now().millisecondsSinceEpoch;

    try {
      final res = await http
          .post(
            Uri.parse('$kBaseUrl/api/library'),
            headers: {'content-type': 'application/json', 'x-publish-key': key},
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

  static Future<String> upload(String path, String key) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('https://ufoload.com/api/v1/files?folder_id=root'),
    );
    req.headers['Authorization'] = 'Bearer ${key.trim()}';
    req.files.add(await http.MultipartFile.fromPath('file', path));

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode == 401) throw 'API key is wrong (401).';
    if (streamed.statusCode == 413) throw 'File is bigger than your plan allows (413).';
    if (streamed.statusCode == 409) throw 'Storage full (409).';
    if (streamed.statusCode != 200 && streamed.statusCode != 201) {
      throw 'Upload failed (${streamed.statusCode}).';
    }

    final j = jsonDecode(body);
    final file = (j is Map) ? j['file'] : null;
    final pid = (file is Map) ? (file['public_id'] ?? '') : '';
    if (pid.toString().isEmpty) throw 'Uploaded, but no public_id came back.';
    return 'https://iframe.andromedans.live/e/$pid';
  }
}

/* ================================================================== admin */

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _key = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _ok = false;

  Timer? _keyTimer;

  @override
  void initState() {
    super.initState();
    AdminService.savedKey().then((k) {
      if (k != null && mounted && _key.text.isEmpty) setState(() => _key.text = k);
    });
    _key.addListener(_scheduleSave);
  }

  void _scheduleSave() {
    _keyTimer?.cancel();
    _keyTimer = Timer(const Duration(milliseconds: 500), () {
      final v = _key.text.trim();
      if (v.isNotEmpty) AdminService.saveKey(v);
    });
  }

  @override
  void dispose() {
    _keyTimer?.cancel();
    _tabs.dispose();
    _key.dispose();
    super.dispose();
  }

  void _say(String msg, {bool ok = false}) {
    setState(() {
      _message = msg;
      _ok = ok;
    });
  }

  Future<void> _publish(void Function(Map<String, dynamic> raw) mutate, String doneMsg) async {
    if (_key.text.trim().isEmpty) {
      _say('Enter the publish key first.');
      return;
    }
    setState(() => _busy = true);
    final err = await AdminService.publish(_key.text.trim(), mutate);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err.isEmpty) {
      await AdminService.saveKey(_key.text.trim());
      _say(doneMsg, ok: true);
      await LibScope.of(context).reload();
    } else {
      _say(err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = LibScope.of(context).library;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin console'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: kBrand,
          unselectedLabelColor: kMuted,
          indicatorColor: kBrand,
          tabs: const [Tab(text: 'Playlists'), Tab(text: 'Episodes'), Tab(text: 'Settings')],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: _key,
              obscureText: true,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Publish key',
                hintText: 'anipix-pub-…',
                isDense: true,
              ),
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_message!,
                    style: TextStyle(fontSize: 12, color: _ok ? kBrand : const Color(0xFFFF9D9D))),
              ),
            ),
          if (_busy) const LinearProgressIndicator(color: kBrand, minHeight: 2),
          Expanded(
            child: lib == null
                ? const Center(child: CircularProgressIndicator(color: kBrand))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _PlaylistsTab(lib: lib, onPublish: _publish),
                      _EpisodesTab(lib: lib, onPublish: _publish),
                      _SettingsTab(lib: lib, onPublish: _publish),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------- playlists */

class _PlaylistsTab extends StatefulWidget {
  final Library lib;
  final Future<void> Function(void Function(Map<String, dynamic>), String) onPublish;
  const _PlaylistsTab({required this.lib, required this.onPublish});

  @override
  State<_PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends State<_PlaylistsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late List<Playlist> _list = List<Playlist>.from(widget.lib.playlists);

  Library get lib => widget.lib;
  Future<void> Function(void Function(Map<String, dynamic>), String) get onPublish => widget.onPublish;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_list.length != lib.playlists.length) _list = List<Playlist>.from(lib.playlists);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kBrand,
        foregroundColor: Colors.black,
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('New playlist', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
        itemCount: _list.length,
        onReorder: (oldIndex, newIndex) {
          if (newIndex > oldIndex) newIndex -= 1;
          final moved = _list.removeAt(oldIndex);
          _list.insert(newIndex, moved);
          setState(() {});
          onPublish((raw) {
            final ps = List<dynamic>.from(raw['playlists'] ?? const []);
            final byId = {for (final p in ps) if (p is Map) p['id']: p};
            final out = <dynamic>[];
            for (var i = 0; i < _list.length; i++) {
              final src = byId[_list[i].id];
              if (src is Map) {
                final m = Map<String, dynamic>.from(src);
                m['order'] = i;
                out.add(m);
              }
            }
            raw['playlists'] = out;
          }, 'Order saved.');
        },
        itemBuilder: (context, i) {
          final p = _list[i];
          return ListTile(
            key: ValueKey(p.id),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.drag_handle, size: 16, color: kMuted),
                const SizedBox(width: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 42,
                    height: 56,
                    child: AppImage(src: p.thumb, cacheWidth: 160, fallback: Container(color: kSurface2)),
                  ),
                ),
              ],
            ),
            title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            subtitle: Text('${p.year} · ${p.genres.take(2).join(', ')}',
                style: const TextStyle(fontSize: 11, color: kMuted)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18, color: kMuted),
                  onPressed: () => _edit(context, p),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFFF8A8A)),
                  onPressed: () async {
                    final sure = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: kSurface,
                        title: const Text('Delete playlist?'),
                        content: Text('“${p.title}” and its episodes will be removed.',
                            style: const TextStyle(fontSize: 13, color: kMuted)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (sure != true) return;
                    await onPublish((raw) {
                      final ps = List<dynamic>.from(raw['playlists'] ?? const []);
                      ps.removeWhere((e) => e is Map && e['id'] == p.id);
                      raw['playlists'] = ps;
                      final es = List<dynamic>.from(raw['episodes'] ?? const []);
                      es.removeWhere((e) => e is Map && e['playlistId'] == p.id);
                      raw['episodes'] = es;
                    }, 'Playlist deleted.');
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  int createdAtOf(String? id) {
    if (id != null) {
      final ps = (Api.lastRaw?['playlists'] as List?) ?? const [];
      for (final e in ps) {
        if (e is Map && e['id'] == id) {
          return (e['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
        }
      }
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  void _edit(BuildContext context, Playlist? existing) {
    final title = TextEditingController(text: existing?.title ?? '');
    final year = TextEditingController(text: (existing?.year ?? DateTime.now().year).toString());
    final rating = TextEditingController(text: (existing?.rating ?? 0).toString());
    final genres = TextEditingController(text: existing?.genres.join(', ') ?? '');
    final thumb = TextEditingController(text: existing?.thumb ?? '');
    final banner = TextEditingController(text: existing?.banner ?? '');
    final audio = TextEditingController(text: existing?.audio.join(', ') ?? 'Hindi');
    String dub = existing?.dub ?? 'official';
    bool featured = existing?.featured ?? false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing == null ? 'New playlist' : 'Edit playlist',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              _field('Title', title, hint: 'Release that witch'),
              _field('Year', year, number: true),
              _field('Rating', rating, number: true),
              _field('Genres (comma separated)', genres, hint: 'Fantasy, Action'),
              _field('Audio (comma separated)', audio, hint: 'Hindi, Japanese'),
              _fieldWithUpload('Thumbnail', thumb),
              _fieldWithUpload('Banner', banner),
              Row(
                children: [
                  const Text('Dub:', style: TextStyle(fontSize: 12.5, color: kMuted)),
                  const SizedBox(width: 10),
                  DropdownButton<String>(
                    value: dub,
                    dropdownColor: kSurface,
                    items: const [
                      DropdownMenuItem(value: 'official', child: Text('Official', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'sub', child: Text('Sub', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'fan', child: Text('Fan', style: TextStyle(fontSize: 13))),
                    ],
                    onChanged: (v) => dub = v ?? 'official',
                  ),
                  const Spacer(),
                  const Text('Featured', style: TextStyle(fontSize: 12.5, color: kMuted)),
                  Switch(
                    value: featured,
                    activeColor: kBrand,
                    onChanged: (v) => featured = v,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 44,
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrand,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    if (title.text.trim().isEmpty) return;
                    final id = existing?.id ?? 'p${DateTime.now().millisecondsSinceEpoch}';
                    final item = {
                      'id': id,
                      'title': title.text.trim(),
                      'year': int.tryParse(year.text) ?? 0,
                      'rating': double.tryParse(rating.text) ?? 0,
                      'type': existing?.type ?? 'TV',
                      'genres': genres.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                      'audio': audio.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                      'dub': dub,
                      'thumb': thumb.text.trim(),
                      'banner': banner.text.trim(),
                      'featured': featured,
                      'createdAt': createdAtOf(existing?.id),
                      'desc': existing?.desc ?? '',
                      'hue': 21,
                    };
                    Navigator.pop(ctx);
                    onPublish((raw) {
                      final ps = List<dynamic>.from(raw['playlists'] ?? const []);
                      ps.removeWhere((e) => e is Map && e['id'] == id);
                      ps.add(item);
                      raw['playlists'] = ps;
                    }, existing == null ? 'Playlist created.' : 'Playlist saved.');
                  },
                  child: Text(existing == null ? 'Create playlist' : 'Save playlist',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldWithUpload(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: c,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: label,
                hintText: 'https://… or upload',
                isDense: true,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Upload from phone',
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 20, color: kBrand),
            onPressed: () async {
              final picked = await FilePicker.platform.pickFiles(type: FileType.image);
              final path = picked?.files.single.path;
              if (path == null) return;
              final url = await AdminService.uploadImage(path);
              if (url.isNotEmpty) {
                c.text = url;
                if (mounted) setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, {String? hint, bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
      ),
    );
  }
}

/* -------------------------------------------------------------- episodes */

class _EpisodesTab extends StatefulWidget {
  final Library lib;
  final Future<void> Function(void Function(Map<String, dynamic>), String) onPublish;
  const _EpisodesTab({required this.lib, required this.onPublish});

  @override
  State<_EpisodesTab> createState() => _EpisodesTabState();
}

class _EpisodesTabState extends State<_EpisodesTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String? _pid;
  final _epNo = TextEditingController(text: '1');
  final _title = TextEditingController();
  final _url = TextEditingController();
  final _quality = TextEditingController(text: '720p');
  final _ufoKey = TextEditingController();
  int _season = 1;
  String _kind = 'embed';
  bool _uploading = false;
  String? _info;
  Map<String, int> _views = {};

  @override
  void initState() {
    super.initState();
    UfoloadService.savedKey().then((k) {
      if (k != null && mounted && _ufoKey.text.isEmpty) setState(() => _ufoKey.text = k);
    });
    _ufoKey.addListener(_scheduleSaveKey);
    Api.fetchViews().then((v) {
      if (mounted) setState(() => _views = v);
    });
  }

  Timer? _ufoTimer;

  void _scheduleSaveKey() {
    _ufoTimer?.cancel();
    _ufoTimer = Timer(const Duration(milliseconds: 500), () {
      final v = _ufoKey.text.trim();
      if (v.isNotEmpty) UfoloadService.saveKey(v);
    });
  }

  @override
  void dispose() {
    _ufoTimer?.cancel();
    _epNo.dispose();
    _title.dispose();
    _url.dispose();
    _quality.dispose();
    _ufoKey.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    if (_ufoKey.text.trim().isEmpty) {
      setState(() => _info = 'Paste your UFOLOAD API key first (ufo_…).');
      return;
    }
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.video);
      final path = picked?.files.single.path;
      if (path == null) return;
      setState(() {
        _uploading = true;
        _info = 'Uploading… a big file can take a few minutes.';
      });
      final embed = await UfoloadService.upload(path, _ufoKey.text);
      await UfoloadService.saveKey(_ufoKey.text);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _url.text = embed;
        _kind = 'embed';
        _info = 'Uploaded. Encoding takes 5-15 min, then the link plays.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _info = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final playlists = widget.lib.playlists;
    if (_pid == null && playlists.isNotEmpty) _pid = playlists.first.id;
    final episodes = _pid == null ? <Episode>[] : widget.lib.episodesOf(_pid!);
    final seasons = <int>{1, for (final e in episodes) e.season};

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
      children: [
        const Text('Playlist', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
        const SizedBox(height: 6),
        _dropdown<String>(
          value: _pid,
          items: [for (final p in playlists) MapEntry(p.id, p.title)],
          onChanged: (v) => setState(() => _pid = v),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Season', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
                  const SizedBox(height: 6),
                  _dropdown<int>(
                    value: _season,
                    items: [for (final s in seasons.toList()..sort()) MapEntry(s, 'Season $s')],
                    onChanged: (v) => setState(() => _season = v ?? 1),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Episode no.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
                  const SizedBox(height: 6),
                  TextField(controller: _epNo, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(labelText: 'Episode title (optional)', isDense: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ufoKey,
          obscureText: true,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(labelText: 'UFOLOAD API key (ufo_…)', isDense: true),
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
            onPressed: _uploading ? null : _upload,
            icon: _uploading
                ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_upload_outlined, size: 17),
            label: Text(_uploading ? 'Uploading…' : 'Pick video & upload to UFOLOAD',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ),
        if (_info != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_info!, style: const TextStyle(fontSize: 11.5, color: kMuted, height: 1.4)),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(labelText: 'Video link', hintText: 'https://…', isDense: true),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _quality,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(labelText: 'Quality', isDense: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _dropdown<String>(
                value: _kind,
                items: const [
                  MapEntry('embed', 'Embed (iframe)'),
                  MapEntry('file', 'Direct MP4'),
                ],
                onChanged: (v) => setState(() => _kind = v ?? 'embed'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 46,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kBrand,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final pid = _pid;
              final n = int.tryParse(_epNo.text.trim()) ?? 0;
              final url = _url.text.trim();
              if (pid == null) return setState(() => _info = 'Pick a playlist.');
              if (n <= 0) return setState(() => _info = 'Episode number must be 1 or more.');
              if (!url.startsWith('http')) return setState(() => _info = 'Paste a full link (https://…).');

              final ep = {
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
              widget.onPublish((raw) {
                final es = List<dynamic>.from(raw['episodes'] ?? const []);
                es.add(ep);
                raw['episodes'] = es;
              }, 'Episode published.');
              _url.clear();
              _title.clear();
            },
            child: const Text('Publish episode', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 22),
        const Text('Existing episodes',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (episodes.isEmpty)
          const Text('No episodes yet.', style: TextStyle(fontSize: 12, color: kMuted))
        else
          for (final e in episodes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              onTap: () => _editEpisode(e),
              title: Text('S${e.season} E${e.n}${e.title.isNotEmpty ? ' · ${e.title}' : ''}',
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                  '${e.sources.map((s) => s.q).join(' · ')}  ·  👁 ${_views[e.id] ?? 0} views',
                  style: const TextStyle(fontSize: 11, color: kMuted)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFFF8A8A)),
                onPressed: () => widget.onPublish((raw) {
                  final es = List<dynamic>.from(raw['episodes'] ?? const []);
                  es.removeWhere((x) => x is Map && x['id'] == e.id);
                  raw['episodes'] = es;
                }, 'Episode deleted.'),
              ),
            ),
      ],
    );
  }

  /// Edit an existing episode (link, quality, title) in place.
  void _editEpisode(Episode e) {
    final first = e.sources.isNotEmpty ? e.sources.first : null;
    final title = TextEditingController(text: e.title);
    final url = TextEditingController(text: first?.url ?? '');
    final quality = TextEditingController(text: first?.q ?? '720p');
    String kind = first?.kind ?? 'embed';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit S${e.season} E${e.n}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(
                controller: title,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(labelText: 'Episode title', isDense: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(labelText: 'Video link', isDense: true),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: quality,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(labelText: 'Quality', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<String>(
                      value: kind,
                      isExpanded: true,
                      dropdownColor: kSurface,
                      items: const [
                        DropdownMenuItem(value: 'embed', child: Text('Embed', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'file', child: Text('Direct MP4', style: TextStyle(fontSize: 13))),
                      ],
                      onChanged: (v) => kind = v ?? 'embed',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 44,
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrand,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    final u = url.text.trim();
                    if (!u.startsWith('http')) {
                      setState(() => _info = 'Paste a full link (https://…).');
                      return;
                    }
                    Navigator.pop(ctx);
                    widget.onPublish((raw) {
                      final es = List<dynamic>.from(raw['episodes'] ?? const []);
                      for (var i = 0; i < es.length; i++) {
                        final m = es[i];
                        if (m is Map && m['id'] == e.id) {
                          final updated = Map<String, dynamic>.from(m);
                          updated['title'] = title.text.trim();
                          updated['sources'] = [
                            {
                              'q': quality.text.trim().isEmpty ? 'HD' : quality.text.trim(),
                              'url': u,
                              'kind': kind,
                            }
                          ];
                          es[i] = updated;
                        }
                      }
                      raw['episodes'] = es;
                    }, 'Episode updated.');
                  },
                  child: const Text('Save changes', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required T? value,
    required List<MapEntry<T, String>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: kSurface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kLine),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: kSurface,
          items: [
            for (final e in items)
              DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------- settings */

class _SettingsTab extends StatefulWidget {
  final Library lib;
  final Future<void> Function(void Function(Map<String, dynamic>), String) onPublish;
  const _SettingsTab({required this.lib, required this.onPublish});

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final _tabs = TextEditingController(text: widget.lib.home.tabs.join(', '));
  late final _cats = TextEditingController(text: widget.lib.home.categories.join(', '));
  late final _secs = TextEditingController(
    text: widget.lib.home.sections.map((s) => '${s.title} | ${s.source} | ${s.limit}').join('\n'),
  );
  late final _ann = TextEditingController(text: widget.lib.home.announcement);
  late String _heroId = widget.lib.home.heroId;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
      children: [
        const Text('Home layout — app + website',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        TextField(
          controller: _tabs,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(labelText: 'Tabs (comma separated)', isDense: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _cats,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(labelText: 'Categories (comma separated)', isDense: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _secs,
          maxLines: 5,
          style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            labelText: 'Sections — one per line: Title | source | limit',
            hintText: 'Trending Now 🔥 | recent | 12',
            isDense: true,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('source: recent · rating · featured · continue · genre:Action',
              style: TextStyle(fontSize: 11, color: kMuted)),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _ann,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'Announcement banner (home)',
            hintText: 'Har Friday naya episode',
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),
        const Text('Hero playlist (big banner)',
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
              value: widget.lib.playlists.any((p) => p.id == _heroId) ? _heroId : '',
              isExpanded: true,
              dropdownColor: kSurface,
              items: [
                const DropdownMenuItem(value: '', child: Text('Auto (featured)', style: TextStyle(fontSize: 13))),
                for (final p in widget.lib.playlists)
                  DropdownMenuItem(value: p.id, child: Text(p.title, style: const TextStyle(fontSize: 13))),
              ],
              onChanged: (v) => setState(() => _heroId = v ?? ''),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 46,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kBrand,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final tabs = _tabs.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
              final cats = _cats.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
              final secs = <Map<String, dynamic>>[];
              for (final line in _secs.text.split('\n')) {
                final parts = line.split('|').map((e) => e.trim()).toList();
                if (parts.isEmpty || parts[0].isEmpty) continue;
                secs.add({
                  'title': parts[0],
                  'source': parts.length > 1 && parts[1].isNotEmpty ? parts[1] : 'recent',
                  'limit': parts.length > 2 ? (int.tryParse(parts[2]) ?? 10) : 10,
                });
              }
              widget.onPublish((raw) {
                final prev = (raw['home'] is Map) ? Map<String, dynamic>.from(raw['home'] as Map) : <String, dynamic>{};
                raw['home'] = {
                  ...prev,
                  'tabs': tabs,
                  'categories': cats,
                  'sections': secs,
                  'announcement': _ann.text.trim(),
                  'heroId': _heroId,
                };
              }, 'Home layout saved.');
            },
            child: const Text('Save home layout', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 26),
        const Text('About the app icon',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'Android does not allow changing the launcher icon from inside the app — the icon is part of the APK. '
          'To use a new icon, the app has to be rebuilt; every user then gets it through the in-app update prompt.',
          style: TextStyle(fontSize: 11.5, color: kMuted, height: 1.5),
        ),
      ],
    );
  }
}
