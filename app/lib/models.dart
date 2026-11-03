class EpSource {
  final String q;
  final String url;
  final String kind; // 'file' | 'embed'
  const EpSource({required this.q, required this.url, required this.kind});

  factory EpSource.fromJson(Map<String, dynamic> j) => EpSource(
        q: (j['q'] ?? 'HD').toString(),
        url: (j['url'] ?? '').toString(),
        kind: (j['kind'] ?? 'embed').toString(),
      );

  bool get isFile => kind == 'file';
}

class Episode {
  final String id;
  final String playlistId;
  final String title;
  final int season;
  final int n;
  final List<EpSource> sources;
  final List<EpSource> downloads;

  const Episode({
    required this.id,
    required this.playlistId,
    required this.title,
    required this.season,
    required this.n,
    required this.sources,
    required this.downloads,
  });

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        id: (j['id'] ?? '').toString(),
        playlistId: (j['playlistId'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        season: (j['season'] as num?)?.toInt() ?? 1,
        n: (j['n'] as num?)?.toInt() ?? 1,
        sources: ((j['sources'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => EpSource.fromJson(Map<String, dynamic>.from(e)))
            .where((s) => s.url.isNotEmpty)
            .toList(),
        downloads: ((j['downloads'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => EpSource.fromJson(Map<String, dynamic>.from(e)))
            .where((s) => s.url.isNotEmpty)
            .toList(),
      );

  String get label => title.isNotEmpty ? title : 'Episode $n';
}

class Playlist {
  final String id;
  final String title;
  final String desc;
  final String type;
  final String studio;
  final String dub; // sub | official | fan
  final int year;
  final double rating;
  final List<String> genres;
  final List<String> audio;
  final String thumb;
  final String banner;
  final bool featured;

  const Playlist({
    required this.id,
    required this.title,
    required this.desc,
    required this.type,
    required this.studio,
    required this.dub,
    required this.year,
    required this.rating,
    required this.genres,
    required this.audio,
    required this.thumb,
    required this.banner,
    required this.featured,
  });

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? 'Untitled').toString(),
        desc: (j['desc'] ?? '').toString(),
        type: (j['type'] ?? 'TV').toString(),
        studio: (j['studio'] ?? '').toString(),
        dub: (j['dub'] ?? 'sub').toString(),
        year: (j['year'] as num?)?.toInt() ?? 0,
        rating: (j['rating'] as num?)?.toDouble() ?? 0,
        genres: ((j['genres'] as List?) ?? const []).map((e) => e.toString()).toList(),
        audio: ((j['audio'] as List?) ?? const []).map((e) => e.toString()).toList(),
        thumb: (j['thumb'] ?? '').toString(),
        banner: (j['banner'] ?? '').toString(),
        featured: j['featured'] == true,
      );

  String get dubLabel {
    if (dub == 'official') return 'DUB';
    if (dub == 'fan') return 'FANDUB';
    return 'SUB';
  }
}

class Library {
  final int version;
  final List<Playlist> playlists;
  final List<Episode> episodes;

  const Library({required this.version, required this.playlists, required this.episodes});

  factory Library.fromJson(Map<String, dynamic> j) => Library(
        version: (j['version'] as num?)?.toInt() ?? 0,
        playlists: ((j['playlists'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        episodes: ((j['episodes'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Episode.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  List<Episode> episodesOf(String playlistId) {
    final list = episodes.where((e) => e.playlistId == playlistId).toList()
      ..sort((a, b) {
        final s = a.season.compareTo(b.season);
        return s != 0 ? s : a.n.compareTo(b.n);
      });
    return list;
  }

  Playlist? byId(String id) {
    for (final p in playlists) {
      if (p.id == id) return p;
    }
    return null;
  }
}
