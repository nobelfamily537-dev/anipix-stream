import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final heroHeight = (MediaQuery.sizeOf(context).height * 0.44).clamp(260.0, 420.0);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlaylistScreen(playlistId: playlist.id)),
      ),
      child: Container(
        height: heroHeight,
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: kSurface,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AppImage(src: img, cacheWidth: 900, fallback: Container(color: kSurface2)),
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
  String? _lang;
  int _tab = 0;

  static const Color kTeal = Color(0xFF22C55E);

  @override
  Widget build(BuildContext context) {
    final lib = LibScope.of(context).library;
    final playlist = lib?.byId(widget.playlistId);
    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.error_outline,
          title: 'Not found',
          message: 'This playlist is no longer available.',
        ),
      );
    }

    final eps = lib!.episodesOf(playlist.id);
    final seasons = <int>{for (final e in eps) e.season}.toList()..sort();
    final active = _season ?? (seasons.isEmpty ? 1 : seasons.first);
    final seasonEps = eps.where((e) => e.season == active).toList();
    final lang = _lang ?? (playlist.audio.isNotEmpty ? playlist.audio.first : 'Original');
    final others = lib.playlists.where((x) => x.id != playlist.id).toList();
    final inList = Store.i.inWatchlist(playlist.id);

    return Scaffold(
      backgroundColor: kBg,
      body: CustomScrollView(
        slivers: [
          /* ---------- banner ---------- */
          SliverToBoxAdapter(
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: AppImage(
                    src: playlist.banner.isNotEmpty ? playlist.banner : playlist.thumb,
                    cacheWidth: 900,
                    fallback: Container(color: kSurface2),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withOpacity(0.35), kBg],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),

          /* ---------- title + meta ---------- */
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${playlist.title} [${lang}]',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.2),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 13, color: Color(0xFFF5C518)),
                      const SizedBox(width: 4),
                      Text(playlist.rating.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 11.5, color: kMuted, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 10),
                      Text(
                        [
                          if (playlist.year > 0) '${playlist.year}',
                          'Anime',
                          if (seasons.length > 1) '${seasons.length} seasons',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 11.5, color: kMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  /* ---------- action chips ---------- */
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _ActionChip(
                          icon: inList ? Icons.check : Icons.add,
                          label: inList ? 'In list' : 'Add to list',
                          onTap: () async {
                            await Store.i.toggleWatchlist(playlist.id);
                            setState(() {});
                          },
                        ),
                        const SizedBox(width: 8),
                        _ActionChip(
                          icon: Icons.share_outlined,
                          label: 'Share',
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: '$kBaseUrl/#/detail/${playlist.id}'));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Link copied'), duration: Duration(seconds: 2)),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        _ActionChip(
                          icon: Icons.download_outlined,
                          label: 'Download',
                          onTap: () => _openDownloads(context, playlist, eps),
                        ),
                        const SizedBox(width: 8),
                        _ActionChip(
                          icon: Icons.video_library_outlined,
                          label: 'View downloads',
                          onTap: () => _openDownloads(context, playlist, eps),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  /* ---------- resources ---------- */
                  const Text('Resources',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  const Text('Uploaded by AniPix',
                      style: TextStyle(fontSize: 11, color: kMuted)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _DropChip(
                        label: playlist.audio.length > 1 ? lang : '$lang dub',
                        onTap: () => _pickLang(context, playlist, lang),
                      ),
                      const SizedBox(width: 10),
                      _DropChip(
                        label: 'Season ${active.toString().padLeft(2, '0')}',
                        onTap: () => _pickSeason(context, seasons, active),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          /* ---------- episode chips ---------- */
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: seasonEps.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final isAll = i == 0;
                  final ep = isAll ? null : seasonEps[i - 1];
                  return GestureDetector(
                    onTap: () {
                      if (ep == null) return;
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PlayerScreen(
                          playlist: playlist,
                          episodes: eps,
                          index: eps.indexOf(ep),
                        ),
                      ));
                    },
                    child: Container(
                      width: isAll ? 62 : 76,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: kSurface2,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: kLine),
                      ),
                      child: Text(
                        isAll ? 'All' : ep!.n.toString().padLeft(2, '0'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kText),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          /* ---------- tabs ---------- */
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
              child: Row(
                children: [
                  _Tab(label: 'For you', on: _tab == 0, onTap: () => setState(() => _tab = 0)),
                  const SizedBox(width: 22),
                  _Tab(label: 'Episodes', on: _tab == 1, onTap: () => setState(() => _tab = 1)),
                ],
              ),
            ),
          ),

          if (_tab == 0)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
              sliver: others.isEmpty
                  ? const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Text('More anime will appear here.',
                            style: TextStyle(fontSize: 12.5, color: kMuted)),
                      ),
                    )
                  : SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.48,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => PosterCard(
                          playlist: others[i],
                          width: double.infinity,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => PlaylistScreen(playlistId: others[i].id),
                          )),
                        ),
                        childCount: others.length,
                      ),
                    ),
            )
          else
            SliverList.builder(
              itemCount: seasonEps.length,
              itemBuilder: (context, i) {
                final e = seasonEps[i];
                return ListTile(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PlayerScreen(playlist: playlist, episodes: eps, index: eps.indexOf(e)),
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
        ],
      ),
    );
  }

  void _pickSeason(BuildContext context, List<int> seasons, int active) {
    if (seasons.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${seasons.length} seasons',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final s in seasons)
                    GestureDetector(
                      onTap: () {
                        setState(() => _season = s);
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        width: 150,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: s == active ? kBrand : kSurface2,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: s == active ? kBrand : kLine),
                        ),
                        child: Text('Season ${s.toString().padLeft(2, '0')}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: s == active ? Colors.white : kText)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickLang(BuildContext context, Playlist playlist, String active) {
    final langs = playlist.audio.isEmpty ? ['Original'] : playlist.audio;
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select language',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final l in langs)
                    GestureDetector(
                      onTap: () {
                        setState(() => _lang = l);
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        width: 150,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: l == active ? kBrand : kSurface2,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: l == active ? kBrand : kLine),
                        ),
                        child: Text('$l dub',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: l == active ? Colors.white : kText)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDownloads(BuildContext context, Playlist playlist, List<Episode> eps) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) {
        final withDownloads = eps.where((e) => e.downloads.isNotEmpty).toList();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Download', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                if (withDownloads.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('Downloads will be available in a future update.',
                        style: TextStyle(fontSize: 12.5, color: kMuted)),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final e in withDownloads)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('S${e.season} E${e.n}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              e.downloads.map((d) => d.q).join(' · '),
                              style: const TextStyle(fontSize: 11, color: kMuted),
                            ),
                            trailing: const Icon(Icons.download, size: 18, color: kBrand),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: kSurface2,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: kLine),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: kText),
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _DropChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DropChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: kSurface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kLine),
        ),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down, size: 16, color: kMuted),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Tab({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: on ? kText : kMuted)),
          const SizedBox(height: 5),
          Container(
            height: 2.5,
            width: 26,
            decoration: BoxDecoration(
              color: on ? kBrand : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
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
    setState(() {
      _index = i;
      _sourceIndex = 0;
    });
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

                /* quick episode switcher, Moviebox style */
                if (widget.episodes.any((x) => x.season == ep.season)) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.episodes.where((x) => x.season == ep.season).length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final sameSeason =
                            widget.episodes.where((x) => x.season == ep.season).toList();
                        final target = sameSeason[i];
                        final on = target.n == ep.n;
                        return GestureDetector(
                          onTap: () => _goTo(widget.episodes.indexOf(target)),
                          child: Container(
                            width: 62,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: on ? kBrand : kSurface2,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(color: on ? kBrand : kLine),
                            ),
                            child: Text(
                              target.n.toString().padLeft(2, '0'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: on ? Colors.white : kText,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],

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
                              child: AppImage(src: p.thumb, fallback: Container(color: kSurface2)),
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
          const SizedBox(height: 18),
          Center(
            child: Text('AniPix Stream · v$kAppVersion',
                style: const TextStyle(fontSize: 11, color: Color(0xFF5C5C6B))),
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
