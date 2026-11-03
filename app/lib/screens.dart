import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'api.dart';
import 'models.dart';
import 'scope.dart';
import 'store.dart';
import 'ui.dart';

/* ------------------------------------------------------------------ home */

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = LibScope.of(context);
    final lib = scope.library;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AniPix Stream'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => scope.reload(),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: kBrand,
        backgroundColor: kSurface,
        onRefresh: scope.reload,
        child: _buildBody(context, scope, lib),
      ),
    );
  }

  Widget _buildBody(BuildContext context, LibScope scope, Library? lib) {
    if (scope.loading && lib == null) {
      return const Center(child: CircularProgressIndicator(color: kBrand));
    }
    if (lib == null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          EmptyState(
            icon: Icons.cloud_off,
            title: 'Could not load the library',
            message: scope.error ?? 'Check your internet connection and try again.',
            action: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kBrand, foregroundColor: Colors.white),
              onPressed: () => scope.reload(),
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }
    if (lib.playlists.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          EmptyState(
            icon: Icons.movie_filter_outlined,
            title: 'Nothing here yet',
            message: 'Playlists added on the website will appear here automatically.',
          ),
        ],
      );
    }

    final featured = lib.playlists.where((p) => p.featured).toList();
    final hero = featured.isNotEmpty ? featured.first : lib.playlists.first;
    final recent = List<Playlist>.from(lib.playlists.reversed);
    final top = List<Playlist>.from(lib.playlists)
      ..sort((a, b) => b.rating.compareTo(a.rating));

    return ListView(
      children: [
        _HeroBanner(playlist: hero, library: lib),
        if (recent.isNotEmpty) ...[
          const SectionTitle('Recently added'),
          _Row(items: recent, library: lib),
        ],
        if (top.isNotEmpty) ...[
          const SectionTitle('Top rated'),
          _Row(items: top, library: lib),
        ],
        const SectionTitle('All playlists'),
        _Row(items: lib.playlists, library: lib),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _HeroBanner extends StatelessWidget {
  final Playlist playlist;
  final Library library;
  const _HeroBanner({required this.playlist, required this.library});

  @override
  Widget build(BuildContext context) {
    final img = playlist.banner.isNotEmpty
        ? playlist.banner
        : (playlist.thumb.isNotEmpty ? playlist.thumb : '');
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlaylistScreen(playlistId: playlist.id)),
      ),
      child: Container(
        height: 230,
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: kSurface,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (img.isNotEmpty)
              Image.network(img, fit: BoxFit.cover, cacheWidth: 900,
                  errorBuilder: (_, __, ___) => Container(color: kSurface2)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xF208080B)],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(playlist.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.15)),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (playlist.rating > 0) '★ ${playlist.rating.toStringAsFixed(1)}',
                      playlist.dubLabel,
                      if (playlist.year > 0) '${playlist.year}',
                    ].join('  ·  '),
                    style: const TextStyle(fontSize: 11.5, color: kMuted, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBrand,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          final eps = library.episodesOf(playlist.id);
                          if (eps.isEmpty) return;
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => PlayerScreen(playlist: playlist, episodes: eps, index: 0),
                          ));
                        },
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Play'),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kText,
                          side: const BorderSide(color: kLine),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => PlaylistScreen(playlistId: playlist.id)),
                        ),
                        child: const Text('Details'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final List<Playlist> items;
  final Library library;
  const _Row({required this.items, required this.library});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 236,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => PosterCard(
          playlist: items[i],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PlaylistScreen(playlistId: items[i].id)),
          ),
        ),
      ),
    );
  }
}

/* ---------------------------------------------------------------- browse */

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final lib = LibScope.of(context).library;
    final all = lib?.playlists ?? const <Playlist>[];
    final list = _q.isEmpty
        ? all
        : all
            .where((p) =>
                p.title.toLowerCase().contains(_q.toLowerCase()) ||
                p.genres.any((g) => g.toLowerCase().contains(_q.toLowerCase())))
            .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Browse')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim()),
              style: const TextStyle(fontSize: 13.5),
              decoration: const InputDecoration(
                hintText: 'Search anime, genres…',
                prefixIcon: Icon(Icons.search, size: 19, color: kMuted),
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'Nothing found',
                    message: 'Try a different name or genre.',
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.50,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, i) => PosterCard(
                      playlist: list[i],
                      width: double.infinity,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => PlaylistScreen(playlistId: list[i].id)),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------- playlist */

class PlaylistScreen extends StatefulWidget {
  final String playlistId;
  const PlaylistScreen({super.key, required this.playlistId});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  int? _season;

  @override
  Widget build(BuildContext context) {
    final lib = LibScope.of(context).library;
    final playlist = lib?.byId(widget.playlistId);
    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.error_outline, title: 'Not found', message: 'This playlist is no longer available.'),
      );
    }
    final eps = lib!.episodesOf(playlist.id);
    final seasons = <int>{for (final e in eps) e.season}.toList()..sort();
    final active = _season ?? (seasons.isNotEmpty ? seasons.first : 1);
    final shown = eps.where((e) => e.season == active).toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: playlist.banner.isNotEmpty ? 210 : 120,
            backgroundColor: kBg,
            flexibleSpace: FlexibleSpaceBar(
              background: playlist.banner.isNotEmpty
                  ? Image.network(playlist.banner, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: kSurface2))
                  : Container(color: kSurface2),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(playlist.title,
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.2)),
                  const SizedBox(height: 8),
                  Text(
                    [
                      if (playlist.rating > 0) '★ ${playlist.rating.toStringAsFixed(1)}',
                      playlist.dubLabel,
                      if (playlist.year > 0) '${playlist.year}',
                      if (playlist.audio.isNotEmpty) playlist.audio.join(' · '),
                    ].join('  ·  '),
                    style: const TextStyle(fontSize: 11.5, color: kMuted, fontWeight: FontWeight.w600),
                  ),
                  if (playlist.desc.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(playlist.desc, style: const TextStyle(fontSize: 12.5, color: Color(0xFFB9B9C7), height: 1.55)),
                  ],
                  const SizedBox(height: 18),
                  if (seasons.length > 1)
                    SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: seasons.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final s = seasons[i];
                          final on = s == active;
                          return GestureDetector(
                            onTap: () => setState(() => _season = s),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: on ? kBrand : kSurface2,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: on ? kBrand : kLine),
                              ),
                              child: Text('Season $s',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: on ? Colors.white : kMuted)),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text('Season $active · ${shown.length} episode${shown.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          if (shown.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No episodes in this season yet.',
                    style: TextStyle(color: kMuted, fontSize: 12.5)),
              ),
            )
          else
            SliverList.builder(
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final e = shown[i];
                return ListTile(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      playlist: playlist,
                      episodes: eps,
                      index: eps.indexOf(e),
                    ),
                  )),
                  leading: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kSurface2,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: kLine),
                    ),
                    child: Text('${e.n}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  ),
                  title: Text(e.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    e.sources.isEmpty ? 'No video yet' : '${e.sources.length} source${e.sources.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 11, color: kMuted),
                  ),
                  trailing: const Icon(Icons.play_circle_outline, color: kMuted, size: 22),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 30)),
        ],
      ),
    );
  }
}

/* ---------------------------------------------------------------- player */

class PlayerScreen extends StatefulWidget {
  final Playlist playlist;
  final List<Episode> episodes;
  final int index;

  const PlayerScreen({super.key, required this.playlist, required this.episodes, required this.index});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late int _index = widget.index;
  VideoPlayerController? _video;
  WebViewController? _web;
  int _sourceIndex = 0;
  bool _busy = true;

  Episode get _episode => widget.episodes[_index];
  EpSource? get _source => _episode.sources.isEmpty ? null : _episode.sources[_sourceIndex];

  @override
  void initState() {
    super.initState();
    Store.i.pushHistory(widget.playlist.id, _episode.season, _episode.n);
    WidgetsBinding.instance.addPostFrameCallback((_) => _setup());
  }

  Future<void> _setup() async {
    await _video?.dispose();
    _video = null;
    _web = null;
    _sourceIndex = 0;
    final src = _source;
    if (src == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    setState(() => _busy = true);
    if (src.isFile) {
      final c = VideoPlayerController.networkUrl(Uri.parse(src.url));
      try {
        await c.initialize();
        await c.play();
        if (!mounted) {
          await c.dispose();
          return;
        }
        setState(() {
          _video = c;
          _busy = false;
        });
      } catch (_) {
        await c.dispose();
        if (mounted) setState(() => _busy = false);
      }
    } else {
      _web = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..loadRequest(Uri.parse(src.url));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    if (i < 0 || i >= widget.episodes.length) return;
    setState(() => _index = i);
    Store.i.pushHistory(widget.playlist.id, _episode.season, _episode.n);
    _setup();
  }

  @override
  Widget build(BuildContext context) {
    final ep = _episode;
    final src = _source;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text('S${ep.season} E${ep.n}', style: const TextStyle(fontSize: 15)),
      ),
      body: ListView(
        children: [
          Container(
            color: Colors.black,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: _buildVideoArea(src),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.playlist.title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Season ${ep.season} · Episode ${ep.n}${ep.title.isNotEmpty ? ' · ${ep.title}' : ''}',
                    style: const TextStyle(fontSize: 12, color: kMuted)),
                if (ep.sources.length > 1) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var i = 0; i < ep.sources.length; i++)
                        GestureDetector(
                          onTap: () {
                            setState(() => _sourceIndex = i);
                            _setup();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: i == _sourceIndex ? kBrand : kSurface2,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(color: i == _sourceIndex ? kBrand : kLine),
                            ),
                            child: Text(ep.sources[i].q,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: i == _sourceIndex ? Colors.white : kMuted)),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kText,
                          side: const BorderSide(color: kLine),
                        ),
                        onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                        icon: const Icon(Icons.skip_previous, size: 18),
                        label: const Text('Previous'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBrand,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _index < widget.episodes.length - 1 ? () => _goTo(_index + 1) : null,
                        icon: const Icon(Icons.skip_next, size: 18),
                        label: const Text('Next'),
                      ),
                    ),
                  ],
                ),
                if (ep.downloads.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text('Download', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in ep.downloads)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: kSurface2,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: kLine),
                          ),
                          child: Text('${d.q} · MP4', style: const TextStyle(fontSize: 11.5, color: kMuted)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 26),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SupportScreen()),
                  ),
                  child: const Text('Contact support',
                      style: TextStyle(fontSize: 12, color: kBrand, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoArea(EpSource? src) {
    if (src == null) {
      return const Center(
        child: Text('No video added for this episode yet',
            style: TextStyle(color: kMuted, fontSize: 12.5)),
      );
    }
    if (_busy) {
      return const Center(child: CircularProgressIndicator(color: kBrand));
    }
    if (_video != null && _video!.value.isInitialized) {
      return Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _video!.value.aspectRatio,
              child: VideoPlayer(_video!),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(_video!, allowScrubbing: true, colors: const VideoProgressColors(playedColor: kBrand)),
          ),
          Positioned(
            left: 6,
            bottom: 18,
            child: IconButton(
              icon: Icon(_video!.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
              onPressed: () {
                setState(() {
                  _video!.value.isPlaying ? _video!.pause() : _video!.play();
                });
              },
            ),
          ),
        ],
      );
    }
    if (_web != null) {
      return WebViewWidget(controller: _web!);
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: kMuted),
          const SizedBox(height: 8),
          const Text('This video could not be loaded',
              style: TextStyle(color: kMuted, fontSize: 12.5)),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => WebPageScreen(url: src.url)),
            ),
            child: const Text('Open original', style: TextStyle(color: kBrand)),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------ auth */

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _signup = false;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? err;
    if (_signup) {
      if (_pass.text != _pass2.text) {
        err = 'Passwords do not match.';
      } else {
        err = await Store.i.signUp(_name.text, _email.text, _pass.text);
      }
    } else {
      err = await Store.i.signIn(_email.text, _pass.text);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_signup ? 'Create account' : 'Sign in')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: _TabButton(
                  label: 'Sign in',
                  on: !_signup,
                  onTap: () => setState(() {
                    _signup = false;
                    _error = null;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TabButton(
                  label: 'Sign up',
                  on: _signup,
                  onTap: () => setState(() {
                    _signup = true;
                    _error = null;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (_signup) ...[
            TextField(
              controller: _name,
              style: const TextStyle(fontSize: 13.5),
              decoration: const InputDecoration(hintText: 'Username'),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(fontSize: 13.5),
            decoration: const InputDecoration(hintText: 'Email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            style: const TextStyle(fontSize: 13.5),
            decoration: const InputDecoration(hintText: 'Password'),
          ),
          if (_signup) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _pass2,
              obscureText: true,
              style: const TextStyle(fontSize: 13.5),
              decoration: const InputDecoration(hintText: 'Confirm password'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: Color(0xFFFF9D9D), fontSize: 12.5)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_signup ? 'Create account' : 'Sign in'),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Accounts stay on this device — no server, no email sent.',
            style: TextStyle(fontSize: 11, color: kMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _TabButton({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? kBrand : kSurface2,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: on ? kBrand : kLine),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: on ? Colors.white : kMuted)),
      ),
    );
  }
}

/* --------------------------------------------------------------- profile */

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<void> _auth() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = Store.i.user;
    final lib = LibScope.of(context).library;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: EmptyState(
          icon: Icons.person_outline,
          title: 'You are not signed in',
          message: 'Sign in to keep your watchlist and history on this device.',
          action: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kBrand, foregroundColor: Colors.white),
            onPressed: _auth,
            child: const Text('Sign in'),
          ),
        ),
      );
    }

    final history = Store.i.history;
    final watchlist = Store.i.watchlist;
    final name = (user['name'] ?? 'User').toString();
    final email = (user['email'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: kBrand,
                  child: Text(name.isEmpty ? 'U' : name[0].toUpperCase(),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(email, style: const TextStyle(fontSize: 12, color: kMuted)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await Store.i.signOut();
                    setState(() {});
                  },
                  child: const Text('Sign out', style: TextStyle(color: kBrand, fontSize: 12.5)),
                ),
              ],
            ),
          ),
          const SectionTitle('Continue watching'),
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Nothing watched yet.', style: TextStyle(fontSize: 12.5, color: kMuted)),
            )
          else
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: history.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final h = history[i];
                  final p = lib?.byId((h['pid'] ?? '').toString());
                  if (p == null) return const SizedBox.shrink();
                  final eps = lib!.episodesOf(p.id);
                  final idx = eps.indexWhere(
                      (e) => e.season == (h['season'] ?? 1) && e.n == (h['n'] ?? 1));
                  return GestureDetector(
                    onTap: idx < 0
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => PlayerScreen(playlist: p, episodes: eps, index: idx),
                            )),
                    child: SizedBox(
                      width: 150,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: p.thumb.isNotEmpty
                                  ? Image.network(p.thumb, fit: BoxFit.cover, cacheWidth: 320,
                                      errorBuilder: (_, __, ___) => Container(color: kSurface2))
                                  : Container(color: kSurface2),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(p.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          Text('S${h['season']} E${h['n']}',
                              style: const TextStyle(fontSize: 10.5, color: kMuted)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          SectionTitle('Watchlist (${watchlist.length})'),
          if (watchlist.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Nothing saved yet.', style: TextStyle(fontSize: 12.5, color: kMuted)),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 16,
                children: [
                  for (final id in watchlist)
                    if (lib?.byId(id) != null)
                      PosterCard(
                        playlist: lib!.byId(id)!,
                        width: 108,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => PlaylistScreen(playlistId: id)),
                        ),
                      ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.support_agent, color: kMuted, size: 20),
            title: const Text('Contact support', style: TextStyle(fontSize: 13.5)),
            subtitle: const Text('Telegram', style: TextStyle(fontSize: 11, color: kMuted)),
            trailing: const Icon(Icons.chevron_right, color: kMuted, size: 18),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SupportScreen()),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

/* --------------------------------------------------------------- support */

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact support')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.support_agent, size: 46, color: kBrand),
          const SizedBox(height: 16),
          const Text('Need help?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Report a broken episode, request an anime, or ask about your account.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: kMuted, height: 1.5),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WebPageScreen(url: kSupportUrl)),
              ),
              child: const Text('Open Telegram'),
            ),
          ),
          const SizedBox(height: 10),
          const Text(kSupportUrl,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: kMuted)),
        ],
      ),
    );
  }
}

/// Simple in-app browser used for support links and "open original".
class WebPageScreen extends StatefulWidget {
  final String url;
  const WebPageScreen({super.key, required this.url});

  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadRequest(Uri.parse(widget.url));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: WebViewWidget(controller: _controller),
    );
  }
}
