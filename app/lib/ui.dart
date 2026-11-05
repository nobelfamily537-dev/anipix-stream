import 'dart:convert';

import 'package:flutter/material.dart';
import 'models.dart';

const Color kBg = Color(0xFF0A0D10);
const Color kSurface = Color(0xFF141A1F);
const Color kSurface2 = Color(0xFF1C2329);
const Color kLine = Color(0xFF2A3238);
const Color kBrand = Color(0xFF2BD97C);   // MovieBox-style teal
const Color kText = Color(0xFFFFFFFF);
const Color kMuted = Color(0xFF8B949E);

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

/// Shows a remote URL *or* a base64 data-URI (the admin panel stores
/// uploaded posters as data URIs, which Image.network cannot handle).
class AppImage extends StatelessWidget {
  final String src;
  final BoxFit fit;
  final int cacheWidth;
  final Widget? fallback;

  const AppImage({
    super.key,
    required this.src,
    this.fit = BoxFit.cover,
    this.cacheWidth = 320,
    this.fallback,
  });

  static bool isDataUri(String s) => s.startsWith('data:image');

  @override
  Widget build(BuildContext context) {
    final empty = fallback ?? const _PosterFallback();
    if (src.isEmpty) return empty;

    if (isDataUri(src)) {
      try {
        final comma = src.indexOf(',');
        final bytes = base64Decode(src.substring(comma + 1));
        return Image.memory(bytes, fit: fit, gaplessPlayback: true);
      } catch (_) {
        return empty;
      }
    }

    return Image.network(
      src,
      fit: fit,
      cacheWidth: cacheWidth,
      errorBuilder: (_, __, ___) => empty,
    );
  }
}

class HindiBadge extends StatelessWidget {
  final String label;
  const HindiBadge({super.key, this.label = 'Hindi'});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xE60A0D10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }
}

class CategoryChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const CategoryChip({super.key, required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: on ? kBrand : kSurface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? kBrand : kLine),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: on ? Colors.black : kText)),
      ),
    );
  }
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
                    AppImage(src: playlist.thumb),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: HindiBadge(
                        label: playlist.audio.isNotEmpty ? playlist.audio.first : playlist.dubLabel,
                      ),
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
