package com.anipixstream.anipix_stream;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.ProgressBar;

import com.startapp.sdk.adsbase.Ad;
import com.startapp.sdk.adsbase.StartAppAd;
import com.startapp.sdk.adsbase.adlisteners.AdEventListener;

import android.webkit.JavascriptInterface;

public class MainActivity extends Activity {

    private static final String HOME_URL = "https://anipix-stream.animeloverclipedits.workers.dev/";

    private WebView web;
    private ProgressBar progress;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        web = findViewById(R.id.web);
        progress = findViewById(R.id.progress);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setBuiltInZoomControls(false);
        s.setDisplayZoomControls(false);
        s.setJavaScriptCanOpenWindowsAutomatically(true);
        s.setSupportMultipleWindows(false);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            s.setUserAgentString(s.getUserAgentString().replace("; wv", ""));
        }

        // smoother scrolling / compositing
        web.setLayerType(View.LAYER_TYPE_HARDWARE, null);
        web.setOverScrollMode(View.OVER_SCROLL_NEVER);
        web.setBackgroundColor(0xFF08080B);

        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                return handleUrl(url);
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return handleUrl(request.getUrl().toString());
            }

            @Override
            public void onPageStarted(WebView view, String url, Bitmap favicon) {
                progress.setVisibility(View.VISIBLE);
                progress.setProgress(0);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                progress.setVisibility(View.GONE);
            }
        });

        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                progress.setProgress(newProgress);
                progress.setVisibility(newProgress >= 100 ? View.GONE : View.VISIBLE);
            }
        });

        web.addJavascriptInterface(new AdsBridge(), "AnipixAds");

        if (savedInstanceState != null) {
            web.restoreState(savedInstanceState);
        } else {
            web.loadUrl(HOME_URL);
        }
    }

    /* ------------------------------------------------------------------
       Start.io interstitial — the page calls AnipixAds.showInterstitial()
       when a playlist or an episode is tapped.
       ------------------------------------------------------------------ */
    private long lastInterstitialAt = 0;
    private static final long INTERSTITIAL_GAP_MS = 45 * 1000L;

    private class AdsBridge {
        @JavascriptInterface
        public void showInterstitial() {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    maybeShowInterstitial();
                }
            });
        }

        @JavascriptInterface
        public String platform() {
            return "android";
        }
    }

    private void maybeShowInterstitial() {
        long now = System.currentTimeMillis();
        if (now - lastInterstitialAt < INTERSTITIAL_GAP_MS) return;
        lastInterstitialAt = now;
        try {
            final StartAppAd ad = new StartAppAd(this);
            ad.loadAd(StartAppAd.AdMode.AUTOMATIC, new AdEventListener() {
                @Override
                public void onReceiveAd(Ad received) {
                    try { ad.showAd(); } catch (Throwable ignored) { }
                }

                @Override
                public void onFailedToReceiveAd(Ad failed) {
                    /* no fill — carry on */
                }
            });
        } catch (Throwable ignored) {
            /* SDK not ready */
        }
    }

    /** Keep site + ad traffic inside the app, push everything else to the browser. */
    private boolean handleUrl(String url) {
        if (url == null) return false;

        if (url.startsWith("http://") || url.startsWith("https://")) {
            String host = Uri.parse(url).getHost();
            if (host == null) return false;
            // main site and its assets stay in-app
            if (host.endsWith("workers.dev")
                    || host.endsWith("netlify.app")
                    || host.endsWith("githubusercontent.com")
                    || host.endsWith("github.com")
                    || host.endsWith("5gvci.com")
                    || host.endsWith("highrevenueformat.com")
                    || host.endsWith("profitableratecpmnetwork.com")
                    || host.endsWith("acscdn.com")
                    || host.endsWith("youradexchange.com")
                    || host.endsWith("dcengg.org")) {
                return false;
            }
            openExternally(url);
            return true;
        }

        // tg:, mailto:, intent:, tel: ...
        openExternally(url);
        return true;
    }

    private void openExternally(String url) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
        } catch (ActivityNotFoundException e) {
            if (url.startsWith("tg://")) {
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse("https://t.me/lovelyanime2025")));
                } catch (Exception ignored) { }
            }
        }
    }

    @Override
    public void onBackPressed() {
        if (web != null && web.canGoBack()) {
            web.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        if (web != null) web.saveState(outState);
    }

    @Override
    protected void onDestroy() {
        if (web != null) {
            ViewGroup parent = (ViewGroup) web.getParent();
            if (parent != null) parent.removeView(web);
            web.destroy();
            web = null;
        }
        super.onDestroy();
    }
}
