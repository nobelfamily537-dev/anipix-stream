import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';
import 'scope.dart';
import 'ui.dart';

/// Publishes the library straight to the site.
class AdminService {
  static const String _keyPref = 'anipix_publish_key';

  /// Latest key typed in the admin screen (used by the reports list).
  static String currentKey = '';

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

/// One upload, tracked app-wide so it keeps showing while you navigate.
class UploadJob {
  final String name;
  int total;
  int sent;
  double bps;      // bytes per second
  String status;   // uploading | done | failed | cancelled
  String? url;
  UploadJob({required this.name, this.total = 0, this.sent = 0, this.bps = 0, this.status = 'uploading', this.url});

  String get speed {
    if (bps <= 0) return '';
    if (bps >= 1048576) return '${(bps / 1048576).toStringAsFixed(1)} MB/s';
    return '${(bps / 1024).toStringAsFixed(0)} KB/s';
  }

  int get percent => total <= 0 ? 0 : ((sent * 100) / total).clamp(0, 100).round();
  String get mb => '${(sent / 1048576).toStringAsFixed(1)} / ${(total / 1048576).toStringAsFixed(1)} MB';
}

class UploadTracker extends ChangeNotifier {
  UploadTracker._();
  static final UploadTracker i = UploadTracker._();

  final List<UploadJob> jobs = [];
  bool get busy => jobs.any((j) => j.status == 'uploading');

  void add(UploadJob job) {
    jobs.insert(0, job);
    notifyListeners();
  }

  UploadJob? current() {
    for (final j in jobs) {
      if (j.status == 'uploading') return j;
    }
    return null;
  }

  void progress(int percent, int sent, int total, {double bps = 0}) {
    final job = current();
    if (job == null) return;
    job.sent = sent;
    job.total = total;
    if (bps > 0) job.bps = bps;
    notifyListeners();
  }

  void cancel() {
    final job = current();
    if (job == null) return;
    job.status = 'cancelled';
    notifyListeners();
  }

  void done(String url) {
    final job = current();
    if (job == null) return;
    job.status = 'done';
    job.url = url;
    job.sent = job.total;
    notifyListeners();
  }

  void fail(String message) {
    final job = current();
    if (job == null) return;
    job.status = 'failed';
    notifyListeners();
  }

  void clearFinished() {
    jobs.removeWhere((j) => j.status != 'uploading');
    notifyListeners();
  }
}

/// Native foreground-service uploader: progress + notification + survives backgrounding.
class VideoUploader {
  static const MethodChannel _ch = MethodChannel('anipix/upload');
  static void Function(int percent)? onProgress;
  static void Function(String embedUrl)? onDone;
  static void Function(String message)? onError;

  static bool _listening = false;

  static void listen() {
    if (_listening) return;
    _listening = true;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'uploadProgress':
          final m = call.arguments;
          if (m is Map) {
            final p = (m['percent'] as num?)?.toInt() ?? 0;
            final sent = (m['sent'] as num?)?.toInt() ?? 0;
            final total = (m['total'] as num?)?.toInt() ?? 0;
            final bps = (m['bps'] as num?)?.toDouble() ?? 0;
            UploadTracker.i.progress(p, sent, total, bps: bps);
            onProgress?.call(p);
          }
          break;
        case 'uploadDone':
          final m = call.arguments;
          final url = m is Map ? (m['url'] ?? '').toString() : m.toString();
          UploadTracker.i.done(url);
          onDone?.call(url);
          break;
        case 'uploadError':
          UploadTracker.i.fail(call.arguments.toString());
          onError?.call(call.arguments.toString());
          break;
      }
      return null;
    });
  }

  static Future<void> cancel() async {
    try {
      await _ch.invokeMethod('cancel');
    } catch (_) {}
  }

  static Future<bool> start({required String path, required String key, required String name}) async {
    listen();
    try {
      final ok = await _ch.invokeMethod<bool>('start', {'path': path, 'key': key, 'name': name});
      return ok == true;
    } catch (_) {
      return false;
    }
  }
}

class UfoAccount {
  final String name;
  final String key;
  const UfoAccount({required this.name, required this.key});

  Map<String, dynamic> toJson() => {'name': name, 'key': key};

  factory UfoAccount.fromJson(Map<String, dynamic> j) =>
      UfoAccount(name: (j['name'] ?? '').toString(), key: (j['key'] ?? '').toString());

  String get masked {
    if (key.length <= 8) return '••••';
    return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
  }
}

/// Uploads a video to UFOLOAD and returns the embed link.
class UfoloadService {
  static const String _keyPref = 'ufoload_api_key';       // legacy single key
  static const String _accountsPref = 'ufoload_accounts'; // list of accounts

  static Future<List<UfoAccount>> accounts() async {
    final p = await SharedPreferences.getInstance();
    final out = <UfoAccount>[];
    final raw = p.getString(_accountsPref);
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final e in jsonDecode(raw) as List) {
          if (e is Map) out.add(UfoAccount.fromJson(Map<String, dynamic>.from(e)));
        }
      } catch (_) {}
    }
    if (out.isEmpty) {
      final old = p.getString(_keyPref);
      if (old != null && old.trim().isNotEmpty) {
        out.add(UfoAccount(name: 'Account 1', key: old.trim()));
        await saveAccounts(out);
      }
    }
    return out;
  }

  static Future<void> saveAccounts(List<UfoAccount> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_accountsPref, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  static Future<void> addAccount(String name, String key) async {
    final list = await accounts();
    list.add(UfoAccount(
      name: name.trim().isEmpty ? 'Account ${list.length + 1}' : name.trim(),
      key: key.trim(),
    ));
    await saveAccounts(list);
  }

  static Future<void> removeAccount(int index) async {
    final list = await accounts();
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    await saveAccounts(list);
  }

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
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final _key = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _ok = false;

  Timer? _keyTimer;

  @override
  void initState() {
    super.initState();
    AdminService.savedKey().then((k) {
      if (k != null && mounted && _key.text.isEmpty) {
        setState(() => _key.text = k);
        AdminService.currentKey = k;
      }
    });
    _key.addListener(_scheduleSave);
  }

  void _scheduleSave() {
    _keyTimer?.cancel();
    _keyTimer = Timer(const Duration(milliseconds: 500), () {
      final v = _key.text.trim();
      AdminService.currentKey = v;
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
          isScrollable: true,
          tabs: const [
            Tab(text: 'Playlists'),
            Tab(text: 'Episodes'),
            Tab(text: 'Uploader'),
            Tab(text: 'Settings'),
          ],
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
                      const _UploaderTab(),
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
  int _season = 1;
  final _epNo = TextEditingController(text: '1');
  final _title = TextEditingController();
  final _w480 = TextEditingController();
  final _w720 = TextEditingController();
  final _d480 = TextEditingController();
  final _d720 = TextEditingController();

  List<UfoAccount> _accounts = [];
  int _accIdx = 0;
  String? _info;
  bool _uploading = false;
  String? _editingId;
  Map<String, int> _views = {};

  @override
  void initState() {
    super.initState();
    UfoloadService.accounts().then((list) {
      if (mounted) setState(() => _accounts = list);
    });
    Api.fetchViews().then((v) {
      if (mounted) setState(() => _views = v);
    });
    VideoUploader.listen();
    UploadTracker.i.addListener(_onTracker);
  }

  void _onTracker() {
    if (!mounted) return;
    final job = UploadTracker.i.current();
    if (job == null && _uploading) {
      setState(() => _uploading = false);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    UploadTracker.i.removeListener(_onTracker);
    _epNo.dispose();
    _title.dispose();
    _w480.dispose();
    _w720.dispose();
    _d480.dispose();
    _d720.dispose();
    super.dispose();
  }

  void _syncFromExisting() {
    final pid = _pid;
    final n = int.tryParse(_epNo.text.trim()) ?? 0;
    if (pid == null || n <= 0) return;
    Episode? found;
    for (final e in widget.lib.episodesOf(pid)) {
      if (e.n == n && e.season == _season) {
        found = e;
        break;
      }
    }
    if (found == null) {
      if (_editingId != null) {
        _editingId = null;
        _w480.clear();
        _w720.clear();
        _d480.clear();
        _d720.clear();
        _title.clear();
        setState(() {});
      }
      return;
    }

    _editingId = found.id;
    _title.text = found.title;
    _w480.text = '';
    _w720.text = '';
    _d480.text = '';
    _d720.text = '';
    for (final src in found.sources) {
      if (src.q.startsWith('480')) _w480.text = src.url;
      if (src.q.startsWith('720')) _w720.text = src.url;
    }
    for (final d in found.downloads) {
      if (d.q.startsWith('480')) _d480.text = d.url;
      if (d.q.startsWith('720')) _d720.text = d.url;
    }
    setState(() {});
  }

  void _resetForm() {
    _editingId = null;
    _title.clear();
    _w480.clear();
    _w720.clear();
    _d480.clear();
    _d720.clear();
    _epNo.text = '1';
    setState(() {});
  }

  Future<void> _upload() async {
    if (_accounts.isEmpty) {
      setState(() => _info = 'Add a UFOLOAD account first (Settings tab).');
      return;
    }
    if (_accIdx >= _accounts.length) _accIdx = 0;
    final acc = _accounts[_accIdx];

    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.video);
      final path = picked?.files.single.path;
      if (path == null) return;

      UploadTracker.i.add(UploadJob(name: path.split('/').last));
      setState(() {
        _uploading = true;
        _info = 'Uploading — Uploader tab par live progress dekho';
      });

      final started = await VideoUploader.start(
        path: path,
        key: acc.key,
        name: path.split('/').last,
      );
      if (!started) {
        UploadTracker.i.fail('Could not start');
        setState(() {
          _uploading = false;
          _info = 'Upload could not start.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _info = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _save() {
    final pid = _pid;
    final n = int.tryParse(_epNo.text.trim()) ?? 0;
    if (pid == null) return setState(() => _info = 'Pick a playlist.');
    if (n <= 0) return setState(() => _info = 'Episode number must be 1 or more.');

    final sources = <Map<String, String>>[];
    final downloads = <Map<String, String>>[];
    if (_w480.text.trim().startsWith('http')) {
      sources.add({'q': '480p', 'url': _w480.text.trim(), 'kind': 'embed'});
    }
    if (_w720.text.trim().startsWith('http')) {
      sources.add({'q': '720p', 'url': _w720.text.trim(), 'kind': 'embed'});
    }
    if (_d480.text.trim().startsWith('http')) {
      downloads.add({'q': '480p', 'url': _d480.text.trim()});
    }
    if (_d720.text.trim().startsWith('http')) {
      downloads.add({'q': '720p', 'url': _d720.text.trim()});
    }
    if (sources.isEmpty) {
      return setState(() => _info = 'Kam se kam ek watch link daalo (480p ya 720p).');
    }

    final id = _editingId ?? 'e${DateTime.now().millisecondsSinceEpoch}';
    final ep = {
      'id': id,
      'playlistId': pid,
      'season': _season,
      'n': n,
      'title': _title.text.trim(),
      'at': DateTime.now().millisecondsSinceEpoch,
      'sources': sources,
      'downloads': downloads,
    };

    widget.onPublish((raw) {
      final es = List<dynamic>.from(raw['episodes'] ?? const []);
      es.removeWhere((x) => x is Map && x['id'] == id);
      es.add(ep);
      raw['episodes'] = es;
    }, _editingId == null ? 'Episode published.' : 'Episode updated.');

    setState(() => _info = null);
    _resetForm();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final playlists = widget.lib.playlists;
    if (_pid == null && playlists.isNotEmpty) _pid = playlists.first.id;
    final episodes = _pid == null ? <Episode>[] : widget.lib.episodesOf(_pid!);
    final seasons = <int>{1, for (final e in episodes) e.season};

    for (final j in UploadTracker.i.jobs) {
      if (j.status == 'done' && j.url != null) {
        final u = j.url!;
        if (_w480.text != u && _w720.text != u) {
          if (_w480.text.trim().isEmpty) {
            _w480.text = u;
          } else if (_w720.text.trim().isEmpty) {
            _w720.text = u;
          }
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
      children: [
        const Text('Playlist',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
        const SizedBox(height: 6),
        _dropdown<String>(
          value: _pid,
          items: [for (final p in playlists) MapEntry(p.id, p.title)],
          onChanged: (v) {
            setState(() {
              _pid = v;
              _editingId = null;
            });
            _syncFromExisting();
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Season',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
                  const SizedBox(height: 6),
                  _dropdown<int>(
                    value: _season,
                    items: [for (final s in seasons.toList()..sort()) MapEntry(s, 'Season $s')],
                    onChanged: (v) {
                      setState(() => _season = v ?? 1);
                      _syncFromExisting();
                    },
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
                    onChanged: (_) => _syncFromExisting(),
                  ),
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

        if (_editingId != null)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: kBrand.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBrand.withOpacity(0.45)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 15, color: kBrand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Yeh episode pehle se hai — iske links neeche bhar diye hain. Save karne par update ho jayega.',
                    style: const TextStyle(fontSize: 11.5, color: kText, height: 1.35),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Upload video',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
            const Spacer(),
            if (_uploading)
              TextButton(
                onPressed: () {
                  VideoUploader.cancel();
                  UploadTracker.i.cancel();
                },
                child: const Text('Cancel upload',
                    style: TextStyle(fontSize: 12, color: Color(0xFFFF8A8A))),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (_accounts.isEmpty)
          const Text('No UFOLOAD account yet — add one in the Settings tab.',
              style: TextStyle(fontSize: 11.5, color: kMuted))
        else
          _dropdown<int>(
            value: _accIdx < _accounts.length ? _accIdx : 0,
            items: [
              for (var i = 0; i < _accounts.length; i++)
                MapEntry(i, '${_accounts[i].name}  (${_accounts[i].masked})'),
            ],
            onChanged: (v) => setState(() => _accIdx = v ?? 0),
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

        const SizedBox(height: 18),
        const Text('Watch links', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Embed link paste karo — jo quality doge wahi app mein dikhegi.',
            style: TextStyle(fontSize: 11, color: kMuted)),
        const SizedBox(height: 10),
        _linkField('480p link', _w480, 'https://…480p'),
        const SizedBox(height: 10),
        _linkField('720p link', _w720, 'https://…720p'),

        const SizedBox(height: 20),
        const Text('Download links (optional)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Sirf yahan jo daaloge wahi quality Download menu mein aayegi.',
            style: TextStyle(fontSize: 11, color: kMuted)),
        const SizedBox(height: 10),
        _linkField('480p download link', _d480, 'https://…480p.mp4'),
        const SizedBox(height: 10),
        _linkField('720p download link', _d720, 'https://…720p.mp4'),

        const SizedBox(height: 18),
        SizedBox(
          height: 46,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kBrand,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _save,
            child: Text(_editingId == null ? 'Save episode' : 'Update episode',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
        if (_editingId != null)
          Center(
            child: TextButton(
              onPressed: _resetForm,
              child: const Text('Cancel editing', style: TextStyle(fontSize: 12, color: kMuted)),
            ),
          ),

        const SizedBox(height: 24),
        const Text('Existing episodes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (episodes.isEmpty)
          const Text('No episodes yet.', style: TextStyle(fontSize: 12, color: kMuted))
        else
          for (final e in episodes) _episodeTile(e),
      ],
    );
  }

  Widget _linkField(String label, TextEditingController c, String hint) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.url,
      style: const TextStyle(fontSize: 12.5),
      decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
    );
  }

  Widget _episodeTile(Episode e) {
    final watch = e.sources.map((s) => s.q).toList();
    final dls = e.downloads.map((d) => d.q).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kSurface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kLine),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: kBrand.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('S${e.season} E${e.n}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kBrand)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (e.title.isNotEmpty)
                  Text(e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final q in watch) _badge('$q · WATCH', kBrand),
                    for (final q in dls) _badge('$q · DL', const Color(0xFF7FB2FF)),
                  ],
                ),
                const SizedBox(height: 3),
                Text('👁 ${_views[e.id] ?? 0} views',
                    style: const TextStyle(fontSize: 10.5, color: kMuted)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 17, color: kMuted),
            onPressed: () {
              setState(() {
                _season = e.season;
                _epNo.text = e.n.toString();
              });
              _syncFromExisting();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 17, color: Color(0xFFFF8A8A)),
            onPressed: () => widget.onPublish((raw) {
              final es = List<dynamic>.from(raw['episodes'] ?? const []);
              es.removeWhere((x) => x is Map && x['id'] == e.id);
              raw['episodes'] = es;
            }, 'Episode deleted.'),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color)),
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

/* -------------------------------------------------------------- uploader */

class _UploaderTab extends StatefulWidget {
  const _UploaderTab();

  @override
  State<_UploaderTab> createState() => _UploaderTabState();
}

class _UploaderTabState extends State<_UploaderTab> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: UploadTracker.i,
      builder: (context, _) {
        final jobs = UploadTracker.i.jobs;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
          children: [
            Row(
              children: [
                const Text('Uploads', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton(
                  onPressed: () => UploadTracker.i.clearFinished(),
                  child: const Text('Clear finished', style: TextStyle(fontSize: 12, color: kMuted)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Upload background mein chalta rehta hai — app se bahar jaao ya screen lock karo, phir bhi chalta rahega.',
              style: TextStyle(fontSize: 11.5, color: kMuted, height: 1.4),
            ),
            const SizedBox(height: 16),
            if (jobs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text('No uploads yet. Episodes tab se video upload karo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: kMuted)),
              )
            else
              for (final j in jobs) _jobCard(j),
          ],
        );
      },
    );
  }

  Widget _jobCard(UploadJob j) {
    final done = j.status == 'done';
    final failed = j.status == 'failed';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: failed ? const Color(0xFFFF8A8A) : (done ? kBrand.withOpacity(0.5) : kLine)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                done ? Icons.check_circle : (failed ? Icons.error_outline : Icons.cloud_upload),
                size: 18,
                color: done ? kBrand : (failed ? const Color(0xFFFF8A8A) : kMuted),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(j.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              Text(
                done ? 'Done' : (failed ? 'Failed' : (j.status == 'cancelled' ? 'Cancelled' : '${j.percent}%')),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: done ? kBrand : (failed ? const Color(0xFFFF8A8A) : kText)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: done ? 1 : (j.total > 0 ? j.sent / j.total : null),
              minHeight: 6,
              backgroundColor: kLine,
              valueColor: AlwaysStoppedAnimation<Color>(
                  failed ? const Color(0xFFFF8A8A) : kBrand),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(j.mb, style: const TextStyle(fontSize: 11, color: kMuted)),
              if (j.speed.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(j.speed, style: const TextStyle(fontSize: 11, color: kBrand)),
              ],
              const Spacer(),
              if (j.status == 'uploading')
                TextButton(
                  onPressed: () {
                    VideoUploader.cancel();
                    UploadTracker.i.cancel();
                  },
                  child: const Text('Cancel',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFFFF8A8A))),
                )
              else if (done && j.url != null)
                const Text('Link ready', style: TextStyle(fontSize: 11, color: kBrand))
              else if (j.status == 'cancelled')
                const Text('Cancelled', style: TextStyle(fontSize: 11, color: kMuted)),
            ],
          ),
        ],
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
  final _accName = TextEditingController();
  final _accKey = TextEditingController();
  List<UfoAccount> _ufo = [];
  bool _ufoLoaded = false;
  List<Map<String, dynamic>> _reports = [];
  late String _heroId = widget.lib.home.heroId;

  @override
  void initState() {
    super.initState();
    UfoloadService.accounts().then((l) {
      if (mounted) setState(() {
        _ufo = l;
        _ufoLoaded = true;
      });
    });
  }

  @override
  void dispose() {
    _accName.dispose();
    _accKey.dispose();
    super.dispose();
  }

  Future<void> _backup(BuildContext context) async {
    final accs = await UfoloadService.accounts();
    final data = {
      'publishKey': AdminService.currentKey,
      'accounts': accs.map((a) => {'name': a.name, 'key': a.key}).toList(),
    };
    final code = base64Encode(utf8.encode(jsonEncode(data)));
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Backup code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Isse kahin save kar lo (notes, Telegram saved messages).',
                style: TextStyle(fontSize: 12, color: kMuted)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kSurface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kLine),
              ),
              child: SelectableText(code,
                  maxLines: 6,
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: kText)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied — save it somewhere safe.')),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context) async {
    final ctrl = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Restore keys', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          decoration: const InputDecoration(hintText: 'Paste the backup code', isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
        ],
      ),
    );
    if (go != true) return;
    try {
      final j = jsonDecode(utf8.decode(base64Decode(ctrl.text.trim())));
      final list = <UfoAccount>[];
      for (final a in (j['accounts'] as List? ?? const [])) {
        if (a is Map) list.add(UfoAccount(name: (a['name'] ?? 'Account').toString(), key: (a['key'] ?? '').toString()));
      }
      await UfoloadService.saveAccounts(list);
      final pk = (j['publishKey'] ?? '').toString();
      if (pk.isNotEmpty) await AdminService.saveKey(pk);
      if (!mounted) return;
      setState(() => _ufo = list);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restored ${list.length} account(s).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid backup code.')),
      );
    }
  }

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
        const SizedBox(height: 30),
        const Text('UFOLOAD accounts',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text(
          'Har account ka apna free quota hota hai — jitne chaho add karo, upload karte waqt chun lo.',
          style: TextStyle(fontSize: 11.5, color: kMuted, height: 1.4),
        ),
        const SizedBox(height: 12),
        if (!_ufoLoaded)
          const Text('Loading…', style: TextStyle(fontSize: 12, color: kMuted))
        else if (_ufo.isEmpty)
          const Text('No account added yet.', style: TextStyle(fontSize: 12, color: kMuted))
        else
          for (var i = 0; i < _ufo.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kSurface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kLine),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_ufo[i].name,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        Text(_ufo[i].masked,
                            style: const TextStyle(fontSize: 11, color: kMuted)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFFF8A8A)),
                    onPressed: () async {
                      await UfoloadService.removeAccount(i);
                      final l = await UfoloadService.accounts();
                      if (mounted) setState(() => _ufo = l);
                    },
                  ),
                ],
              ),
            ),
        const SizedBox(height: 10),
        TextField(
          controller: _accName,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'Account name',
            hintText: 'Account 2',
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _accKey,
          obscureText: true,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'API key (ufo_…)',
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 42,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: kBrand.withOpacity(0.6)),
              foregroundColor: kBrand,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.add, size: 17),
            label: const Text('Add account', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            onPressed: () async {
              if (_accKey.text.trim().isEmpty) return;
              await UfoloadService.addAccount(_accName.text, _accKey.text);
              _accName.clear();
              _accKey.clear();
              final l = await UfoloadService.accounts();
              if (mounted) setState(() => _ufo = l);
            },
          ),
        ),
        const SizedBox(height: 30),
        Row(
          children: [
            const Text('Broken link reports',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton(
              onPressed: () async {
                final r = await Api.fetchReports(AdminService.currentKey);
                if (mounted) setState(() => _reports = r);
              },
              child: const Text('Load', style: TextStyle(fontSize: 12, color: kBrand)),
            ),
          ],
        ),
        if (_reports.isEmpty)
          const Text('No reports loaded. Tap Load.',
              style: TextStyle(fontSize: 11.5, color: kMuted))
        else
          for (final r in _reports.take(20))
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: kSurface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kLine),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r['playlistId']} · ${r['episodeId']}',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                  if ((r['note'] ?? '').toString().isNotEmpty)
                    Text(r['note'].toString(),
                        style: const TextStyle(fontSize: 11, color: kMuted)),
                  Text(r['at'].toString(),
                      style: const TextStyle(fontSize: 10, color: kMuted)),
                ],
              ),
            ),
        const SizedBox(height: 22),
        const Text('Backup & restore',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text(
          'Reinstall karne par Android app ka data delete kar deta hai. Yeh code save kar lo — '
          'naye install par paste karke saari keys wapas aa jayengi.',
          style: TextStyle(fontSize: 11.5, color: kMuted, height: 1.4),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: kBrand.withOpacity(0.55)),
                  foregroundColor: kBrand,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.save_alt, size: 17),
                label: const Text('Backup keys', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                onPressed: () => _backup(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: kBrand.withOpacity(0.55)),
                  foregroundColor: kBrand,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.restore, size: 17),
                label: const Text('Restore keys', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                onPressed: () => _restore(context),
              ),
            ),
          ],
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
