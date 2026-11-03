package com.anipixstream.anipix_stream;

import android.animation.ObjectAnimator;
import android.animation.PropertyValuesHolder;
import android.animation.ValueAnimator;
import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.animation.DecelerateInterpolator;
import android.view.animation.OvershootInterpolator;
import android.widget.ImageView;
import android.widget.TextView;

/**
 * Splash screen with a Netflix/Crunchyroll style intro:
 * logo fades in and pops, the wordmark slides up while its letter spacing
 * tightens, then the tagline fades in.
 */
public class SplashActivity extends Activity {

    private static final long TOTAL_MS = 2200L;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_splash);

        final ImageView logo = findViewById(R.id.logo);
        final TextView title = findViewById(R.id.title);
        final TextView subtitle = findViewById(R.id.subtitle);

        // 1. logo: fade + pop
        logo.setScaleX(0.78f);
        logo.setScaleY(0.78f);
        logo.animate()
                .alpha(1f)
                .scaleX(1f)
                .scaleY(1f)
                .setStartDelay(80)
                .setDuration(760)
                .setInterpolator(new OvershootInterpolator(1.2f))
                .start();

        // 2. wordmark: slide up, fade in, letter spacing tightens
        title.setTranslationY(60f);
        title.animate()
                .alpha(1f)
                .translationY(0f)
                .setStartDelay(420)
                .setDuration(700)
                .setInterpolator(new DecelerateInterpolator())
                .start();

        ValueAnimator spacing = ValueAnimator.ofFloat(0.42f, 0.12f);
        spacing.setStartDelay(420);
        spacing.setDuration(900);
        spacing.setInterpolator(new DecelerateInterpolator());
        spacing.addUpdateListener(new ValueAnimator.AnimatorUpdateListener() {
            @Override
            public void onAnimationUpdate(ValueAnimator animation) {
                title.setLetterSpacing((Float) animation.getAnimatedValue());
            }
        });
        spacing.start();

        // 3. tagline
        subtitle.animate()
                .alpha(1f)
                .setStartDelay(900)
                .setDuration(600)
                .start();

        new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
            @Override
            public void run() {
                startActivity(new Intent(SplashActivity.this, MainActivity.class));
                overridePendingTransition(android.R.anim.fade_in, android.R.anim.fade_out);
                finish();
            }
        }, TOTAL_MS);
    }

    @Override
    public void onBackPressed() {
        // ignore during splash
    }
}
