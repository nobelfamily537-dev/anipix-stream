import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'scope.dart';
import 'screens.dart';
import 'store.dart';
import 'ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.i.init();
  runApp(const AniPixApp());
}

class AniPixApp extends StatefulWidget {
  const AniPixApp({super.key});

  @override
  State<AniPixApp> createState() => _AniPixAppState();
}

class _AniPixAppState extends State<AniPixApp> {
  Library? _library;
  String? _error;
  bool _loading = true;
  bool _splash = true;
  bool _autoRetried = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
    Timer(const Duration(milliseconds: 1900), () {
      if (mounted) setState(() => _splash = false);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lib = await Api.fetchLibrary();
      if (!mounted) return;
      setState(() {
        _library = lib;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().replaceFirst('Exception: ', '');
      final offline = raw.contains('SocketFailed') ||
          raw.contains('host lookup') ||
          raw.contains('Failed host lookup') ||
          raw.contains('Network is unreachable');
      setState(() {
        _error = offline
            ? 'No internet connection. Check your network and tap Retry.'
            : raw;
        _loading = false;
      });
      if (!_autoRetried) {
        _autoRetried = true;
        Timer(const Duration(seconds: 3), () {
          if (mounted) _load();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_splash) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const SplashScreen(),
      );
    }
    return MaterialApp(
      title: 'AniPix Stream',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: LibScope(
        library: _library,
        loading: _loading,
        error: _error,
        reload: _load,
        child: Builder(
          builder: (context) => Scaffold(
            body: IndexedStack(
              index: _tab,
              children: const [
                HomeScreen(),
                BrowseScreen(),
                MyListScreen(),
                ProfileScreen(),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              backgroundColor: kSurface,
              indicatorColor: kBrand.withOpacity(0.22),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: kBrand), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.search), selectedIcon: Icon(Icons.search, color: kBrand), label: 'Browse'),
                NavigationDestination(icon: Icon(Icons.bookmark_border), selectedIcon: Icon(Icons.bookmark, color: kBrand), label: 'My list'),
                NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: kBrand), label: 'You'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------------------------------------------------------------- my list */

class MyListScreen extends StatefulWidget {
  const MyListScreen({super.key});

  @override
  State<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends State<MyListScreen> {
  @override
  Widget build(BuildContext context) {
    final lib = LibScope.of(context).library;
    final ids = Store.i.watchlist;
    final items = <Playlist>[];
    if (lib != null) {
      for (final id in ids) {
        final p = lib.byId(id);
        if (p != null) items.add(p);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My list')),
      body: items.isEmpty
          ? const EmptyState(
              icon: Icons.bookmark_border,
              title: 'Your list is empty',
              message: 'Open a playlist and tap the bookmark to save it here.',
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                childAspectRatio: 0.50,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) => PosterCard(
                playlist: items[i],
                width: double.infinity,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PlaylistScreen(playlistId: items[i].id)),
                ),
              ),
            ),
    );
  }
}


/* ----------------------------------------------------------------- splash */

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..forward();

  late final Animation<double> _glow =
      Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
  ));
  late final Animation<double> _scale =
      Tween<double>(begin: 0.78, end: 1).animate(CurvedAnimation(
    parent: _c,
    curve: const Interval(0.05, 0.62, curve: Curves.easeOutBack),
  ));
  late final Animation<double> _logoFade =
      CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.35, curve: Curves.easeOut));
  late final Animation<double> _titleFade =
      CurvedAnimation(parent: _c, curve: const Interval(0.40, 0.80, curve: Curves.easeOut));
  late final Animation<Offset> _titleSlide =
      Tween<Offset>(begin: const Offset(0, 0.55), end: Offset.zero).animate(
    CurvedAnimation(parent: _c, curve: const Interval(0.40, 0.88, curve: Curves.easeOutCubic)),
  );
  late final Animation<double> _spacing =
      Tween<double>(begin: 11, end: 3.4).animate(CurvedAnimation(
    parent: _c,
    curve: const Interval(0.40, 1.0, curve: Curves.easeOutCubic),
  ));
  late final Animation<double> _subFade =
      CurvedAnimation(parent: _c, curve: const Interval(0.72, 1.0, curve: Curves.easeOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            kBrand.withOpacity(0.22 * _glow.value),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: _logoFade.value,
                      child: Transform.scale(
                        scale: _scale.value,
                        child: Image.asset('assets/logo.png', width: 152, height: 152),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FadeTransition(
                  opacity: _titleFade,
                  child: SlideTransition(
                    position: _titleSlide,
                    child: Text(
                      'ANIPIX STREAM',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: _spacing.value,
                        color: kText,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FadeTransition(
                  opacity: _subFade,
                  child: const Text(
                    'Powered by AniPix Creator',
                    style: TextStyle(fontSize: 11.5, color: kMuted, letterSpacing: .6),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
