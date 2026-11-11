package com.anipixstream.anipix_stream;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;

import androidx.annotation.Nullable;

import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Scanner;

import io.flutter.plugin.common.MethodChannel;

/**
 * Uploads a video to UFOLOAD as a foreground service:
 *  - keeps going when the app is in the background
 *  - shows a notification with the live percentage
 *  - streams the file as a raw body (the fastest route the API offers)
 */
public class UploadService extends Service {

    public static final String CHANNEL_ID = "anipix_upload";
    public static final int NOTIF_ID = 4211;

    public static MethodChannel channel;   // set by MainActivity

    private volatile boolean cancelled = false;

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_NOT_STICKY;

        final String path = intent.getStringExtra("path");
        final String key = intent.getStringExtra("key");
        final String name = intent.getStringExtra("name");

        createChannel();
        startForeground(NOTIF_ID, buildNotification("Preparing upload…", 0, true));

        new Thread(() -> upload(path, key, name)).start();
        return START_NOT_STICKY;
    }

    private void createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm != null && nm.getNotificationChannel(CHANNEL_ID) == null) {
                NotificationChannel ch = new NotificationChannel(
                        CHANNEL_ID, "Video upload", NotificationManager.IMPORTANCE_LOW);
                ch.setDescription("Shows upload progress");
                ch.setShowBadge(false);
                nm.createNotificationChannel(ch);
            }
        }
    }

    private Notification buildNotification(String text, int percent, boolean ongoing) {
        Intent open = new Intent(this, MainActivity.class);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags |= PendingIntent.FLAG_IMMUTABLE;
        PendingIntent pi = PendingIntent.getActivity(this, 0, open, flags);

        Notification.Builder b;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            b = new Notification.Builder(this, CHANNEL_ID);
        } else {
            b = new Notification.Builder(this);
        }

        b.setContentTitle("AniPix Stream")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.stat_sys_upload)
                .setContentIntent(pi)
                .setOnlyAlertOnce(true)
                .setOngoing(ongoing);

        if (percent >= 0) {
            b.setProgress(100, percent, false);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) b.setSubText(percent + "%");
        } else {
            b.setProgress(0, 0, true);
        }
        return b.build();
    }

    private void notifyProgress(int percent, String text) {
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) nm.notify(NOTIF_ID, buildNotification(text, percent, true));
    }

    private void finish(String text) {
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) nm.notify(NOTIF_ID, buildNotification(text, -1, false));
        stopForeground(false);
        stopSelf();
    }

    private void send(String method, Object arg) {
        final MethodChannel ch = channel;
        if (ch == null) return;
        try {
            ch.invokeMethod(method, arg);
        } catch (Throwable ignored) {
        }
    }

    private void upload(String path, String key, String name) {
        HttpURLConnection conn = null;
        try {
            File file = new File(path);
            long total = file.length();
            if (total <= 0) {
                finish("Upload failed");
                send("uploadError", "File not readable");
                return;
            }

            URL url = new URL("https://ufoload.com/api/v1/files?folder_id=root");
            conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("POST");
            conn.setDoOutput(true);
            conn.setConnectTimeout(60000);
            conn.setReadTimeout(900000);
            conn.setFixedLengthStreamingMode(total);
            conn.setRequestProperty("Authorization", "Bearer " + key);
            conn.setRequestProperty("X-File-Name", name);
            conn.setRequestProperty("Content-Type", "application/octet-stream");
            conn.setRequestProperty("Accept", "application/json");
            conn.connect();

            OutputStream out = conn.getOutputStream();
            InputStream in = new FileInputStream(file);
            byte[] buf = new byte[1024 * 1024];   // 1 MB chunks = fewer syscalls = faster
            long sent = 0;
            int lastPercent = -1;
            long lastNotify = 0;
            int read;
            while ((read = in.read(buf)) != -1) {
                if (cancelled) break;
                out.write(buf, 0, read);
                sent += read;
                int percent = (int) (sent * 100 / total);
                long now = System.currentTimeMillis();
                if (percent != lastPercent && (now - lastNotify > 350 || percent == 100)) {
                    lastPercent = percent;
                    lastNotify = now;
                    notifyProgress(percent, "Uploading " + percent + "%  ·  "
                            + (sent / (1024 * 1024)) + " / " + (total / (1024 * 1024)) + " MB");
                    java.util.HashMap<String, Object> ev = new java.util.HashMap<>();
                    ev.put("percent", percent);
                    ev.put("sent", sent);
                    ev.put("total", total);
                    ev.put("name", name == null ? "video" : name);
                    send("uploadProgress", ev);
                }
            }
            in.close();
            out.flush();
            out.close();

            int code = conn.getResponseCode();
            InputStream resStream = (code >= 200 && code < 300) ? conn.getInputStream() : conn.getErrorStream();
            String body = "";
            if (resStream != null) {
                Scanner sc = new Scanner(resStream, StandardCharsets.UTF_8.name()).useDelimiter("\\A");
                body = sc.hasNext() ? sc.next() : "";
                sc.close();
            }

            if (code != 200 && code != 201) {
                finish("Upload failed (" + code + ")");
                send("uploadError", "Upload failed (" + code + "). " + body);
                return;
            }

            JSONObject j = new JSONObject(body);
            String publicId = j.optJSONObject("file") != null
                    ? j.optJSONObject("file").optString("public_id", "")
                    : "";
            if (publicId.isEmpty()) {
                finish("Upload finished, no id");
                send("uploadError", "Uploaded but no public_id came back.");
                return;
            }

            finish("Upload complete — encoding starts now");
            java.util.HashMap<String, Object> doneEv = new java.util.HashMap<>();
            doneEv.put("url", "https://iframe.andromedans.live/e/" + publicId);
            doneEv.put("name", name == null ? "video" : name);
            doneEv.put("total", total);
            send("uploadDone", doneEv);

        } catch (Throwable t) {
            finish("Upload failed");
            send("uploadError", String.valueOf(t.getMessage()));
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    @Override
    public void onDestroy() {
        cancelled = true;
        super.onDestroy();
    }
}
