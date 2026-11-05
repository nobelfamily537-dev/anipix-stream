import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Start.io ads — the Android side implements the channel.
class Ads {
  static const MethodChannel _ch = MethodChannel('anipix/ads');

  /// Full screen ad when opening a playlist.
  static Future<bool> interstitial() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('interstitial') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Rewarded video when an episode is opened.
  static Future<bool> rewarded() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('rewarded') ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Start.io banner, hosted by a native view.
class StartioBanner extends StatelessWidget {
  final double height;
  const StartioBanner({super.key, this.height = 50});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    return Container(
      height: height,
      alignment: Alignment.center,
      color: Colors.transparent,
      child: const AndroidView(
        viewType: 'anipix/banner',
        creationParams: <String, dynamic>{},
        creationParamsCodec: StandardMessageCodec(),
      ),
    );
  }
}
