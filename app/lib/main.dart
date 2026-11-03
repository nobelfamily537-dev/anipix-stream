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
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
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
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
