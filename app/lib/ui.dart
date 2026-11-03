import 'package:flutter/material.dart';
import 'models.dart';

const Color kBg = Color(0xFF08080B);
const Color kSurface = Color(0xFF12121A);
const Color kSurface2 = Color(0xFF1A1A24);
const Color kLine = Color(0xFF272733);
const Color kBrand = Color(0xFFF47521);
const Color kText = Color(0xFFF3F3F7);
const Color kMuted = Color(0xFF9A9AAB);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    colorScheme: base.colorScheme.copyWith(
      primary: kBrand,
      secondary: kBrand,
      surface: kSurface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w800),
      iconTheme: IconThemeData(color: kText),
    ),
    textTheme: base.textTheme.apply(bodyColor: kText, displayColor: kText),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface2,
      hintStyle: const TextStyle(color: kMuted, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBrand, width: 1.4),
      ),
    ),
  );
}

class PosterCard extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  final double width;

  const PosterCard({super.key, required this.playlist, required this.onTap, this.width = 132});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    playlist.thumb.isNotEmpty
                        ? Image.network(
                            playlist.thumb,
                            fit: BoxFit.cover,
                            cacheWidth: 320,
                            errorBuilder: (_, __, ___) => const _PosterFallback(),
                          )
                        : const _PosterFallback(),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: _Chip(text: playlist.dubLabel, filled: playlist.dub != 'sub'),
                    ),
                    if (playlist.rating > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: _Chip(text: '★ ${playlist.rating.toStringAsFixed(1)}'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              playlist.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.25),
            ),
            const SizedBox(height: 2),
            Text(
              [if (playlist.year > 0) '${playlist.year}', if (playlist.genres.isNotEmpty) playlist.genres.first].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: kMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2140), Color(0xFF12121A)],
        ),
      ),
      child: Center(child: Icon(Icons.movie_outlined, color: Color(0x55FFFFFF), size: 26)),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final bool filled;
  const _Chip({required this.text, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? kBrand : const Color(0xCC08080B),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: .3),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -.2)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: kMuted),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(fontSize: 12.5, color: kMuted, height: 1.5), textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}
