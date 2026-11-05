package com.anipixstream.anipix_stream;

import android.content.Context;
import android.view.View;

import androidx.annotation.NonNull;

import com.startapp.sdk.ads.banner.Banner;
import com.startapp.sdk.adsbase.Ad;
import com.startapp.sdk.adsbase.StartAppAd;
import com.startapp.sdk.adsbase.adlisteners.AdEventListener;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

/**
 * Start.io (app id 210377175, set in AndroidManifest.xml).
 *   interstitial -> playlist opened
 *   rewarded     -> episode opened
 *   banner       -> native view, used on the home screen
 */
public class MainActivity extends FlutterActivity {

    private static final String CHANNEL = "anipix/ads";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine engine) {
        super.configureFlutterEngine(engine);

        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("interstitial".equals(call.method)) {
                        showFullScreen(StartAppAd.AdMode.AUTOMATIC, result);
                    } else if ("rewarded".equals(call.method)) {
                        showFullScreen(StartAppAd.AdMode.REWARDED_VIDEO, result);
                    } else {
                        result.notImplemented();
                    }
                });

        engine.getPlatformViewsController()
                .getRegistry()
                .registerViewFactory("anipix/banner", new BannerFactory());
    }

    private void showFullScreen(final StartAppAd.AdMode mode, final MethodChannel.Result result) {
        try {
            final StartAppAd ad = new StartAppAd(this);
            ad.loadAd(mode, new AdEventListener() {
                @Override
                public void onReceiveAd(Ad received) {
                    try {
                        ad.showAd();
                        result.success(true);
                    } catch (Throwable t) {
                        result.success(false);
                    }
                }

                @Override
                public void onFailedToReceiveAd(Ad failed) {
                    result.success(false);
                }
            });
        } catch (Throwable t) {
            result.success(false);
        }
    }

    /* ---------------- banner ---------------- */

    static class BannerFactory extends PlatformViewFactory {
        BannerFactory() {
            super(StandardMessageCodec.INSTANCE);
        }

        @NonNull
        @Override
        public PlatformView create(@NonNull Context context, int id, Object args) {
            return new BannerView(context);
        }
    }

    static class BannerView implements PlatformView {
        private final Banner banner;

        BannerView(Context context) {
            banner = new Banner(context);
            try {
                banner.loadAd(320, 50);
            } catch (Throwable ignored) {
            }
        }

        @NonNull
        @Override
        public View getView() {
            return banner;
        }

        @Override
        public void dispose() {
            try {
                banner.hideBanner();
            } catch (Throwable ignored) {
            }
        }
    }
}
