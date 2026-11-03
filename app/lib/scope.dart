import 'package:flutter/material.dart';
import 'models.dart';

/// Shares the fetched library + reload() with every screen.
class LibScope extends InheritedWidget {
  final Library? library;
  final bool loading;
  final String? error;
  final Future<void> Function() reload;

  const LibScope({
    super.key,
    required this.library,
    required this.loading,
    required this.error,
    required this.reload,
    required super.child,
  });

  static LibScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LibScope>();
    assert(scope != null, 'LibScope missing above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(LibScope old) =>
      old.library != library || old.loading != loading || old.error != error;
}
