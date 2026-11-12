package com.anipixstream.anipix_stream;

import android.app.DownloadManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.res.Configuration;
import android.app.PictureInPictureParams;
import android.util.Rational;
import android.content.IntentFilter;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.view.View;

import androidx.annotation.NonNull;

import com.startapp.sdk.ads.banner.Banner;
import com.startapp.sdk.adsbase.Ad;
import com.startapp.sdk.adsbase.StartAppAd;
import com.startapp.sdk.adsbase.StartAppSDK;
import com.startapp.sdk.adsbase.adlisteners.AdEventListener;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import android.content.Intent;
import android.os.Build;
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

    private MethodChannel adsChannel;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        /* Skip Start.io's GDPR consent popup: we report consent ourselves. */
        try {
            StartAppSDK.setUserConsent(this, "pas", System.currentTimeMillis(), true);
        } catch (Throwable ignored) {
        }
        super.onCreate(savedInstanceState);
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine engine) {
        super.configureFlutterEngine(engine);

        adsChannel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        adsChannel
                .setMethodCallHandler((call, result) -> {
                    if ("interstitial".equals(call.method)) {
                        showFullScreen(StartAppAd.AdMode.AUTOMATIC, result);
                    } else if ("rewarded".equals(call.method)) {
                        showFullScreen(StartAppAd.AdMode.REWARDED_VIDEO, result);
                    } else if ("pip".equals(call.method)) {
                        try {
                            boolean ok = enterPipMode();
                            result.success(ok);
                        } catch (Throwable t) {
                            result.success(false);
                        }
                    } else if ("share".equals(call.method)) {
                        final String text = call.argument("text");
                        try {
                            Intent send = new Intent(Intent.ACTION_SEND);
                            send.setType("text/plain");
                            send.putExtra(Intent.EXTRA_TEXT, text);
                            startActivity(Intent.createChooser(send, "Share AniPix Stream"));
                            result.success(true);
                        } catch (Throwable t) {
                            result.success(false);
                        }
                    } else if ("installApk".equals(call.method)) {
                        final String url = call.argument("url");
                        try {
                            downloadAndInstall(url);
                            result.success(true);
                        } catch (Throwable t) {
                            android.util.Log.e("AniPix", "install failed", t);
                            result.success(false);
                        }
                    } else {
                        result.notImplemented();
                    }
                });

        engine.getPlatformViewsController()
                .getRegistry()
                .registerViewFactory("anipix/banner", new BannerFactory());

        /* uploads run in a foreground service so they survive backgrounding */
        final MethodChannel uploadChannel =
                new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "anipix/upload");
        UploadService.channel = uploadChannel;
        uploadChannel.setMethodCallHandler((call, result) -> {
            if ("cancel".equals(call.method)) {
                UploadService.requestCancel();
                result.success(true);
            } else if ("start".equals(call.method)) {
                Intent i = new Intent(this, UploadService.class);
                i.putExtra("path", (String) call.argument("path"));
                i.putExtra("key", (String) call.argument("key"));
                i.putExtra("name", (String) call.argument("name"));
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(i);
                } else {
                    startService(i);
                }
                result.success(true);
            } else {
                result.notImplemented();
            }
        });
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

    /* ---------------- picture in picture ---------------- */

    private boolean enterPipMode() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false;
        try {
            PictureInPictureParams.Builder b = new PictureInPictureParams.Builder();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                b.setAspectRatio(new Rational(16, 9));
            }
            enterPictureInPictureMode(b.build());
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    @Override
    public void onPictureInPictureModeChanged(boolean isInPip, Configuration config) {
        super.onPictureInPictureModeChanged(isInPip, config);
        try {
            final MethodChannel ch = adsChannel;
            if (ch != null) ch.invokeMethod(isInPip ? "pipOn" : "pipOff", null);
        } catch (Throwable ignored) {
        }
    }

    /* ---------------- in-app update: download + install ---------------- */

    private long pendingDownloadId = -1;

    private void downloadAndInstall(final String url) {
        final DownloadManager dm = (DownloadManager) getSystemService(Context.DOWNLOAD_SERVICE);
        if (dm == null) throw new RuntimeException("no download manager");

        DownloadManager.Request req = new DownloadManager.Request(Uri.parse(url));
        req.setTitle("AniPix Stream update");
        req.setMimeType("application/vnd.android.package-archive");
        req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
        req.setDestinationInExternalFilesDir(this, Environment.DIRECTORY_DOWNLOADS, "anipix-update.apk");

        pendingDownloadId = dm.enqueue(req);

        BroadcastReceiver receiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                long id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1);
                if (id != pendingDownloadId) return;
                try {
                    unregisterReceiver(this);
                } catch (Throwable ignored) {
                }
                Uri apk = dm.getUriForDownloadedFile(id);
                if (apk == null) return;
                Intent install = new Intent(Intent.ACTION_VIEW);
                install.setDataAndType(apk, "application/vnd.android.package-archive");
                install.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                install.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(install);
            }
        };
        IntentFilter filter = new IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE);
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED);
        } else {
            registerReceiver(receiver, filter);
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
