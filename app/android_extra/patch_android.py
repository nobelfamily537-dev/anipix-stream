"""Patches the generated Android project for the AniPix Stream app.

Run from the repository root after `flutter create`:
    python3 app/android_extra/patch_android.py
"""

import os
import re
import sys

BASE = 'app/android/app'
STARTAPP_ID = '210377175'
STARTAPP_SDK = '5.5.0'


def patch_gradle():
    path = os.path.join(BASE, 'build.gradle')
    if not os.path.exists(path):
        # newer Flutter templates use the Kotlin DSL
        alt = os.path.join(BASE, 'build.gradle.kts')
        if os.path.exists(alt):
            path = alt
        else:
            print('!! build.gradle not found')
            return

    s = open(path).read()

    s = re.sub(r'compileSdk\s*=\s*flutter\.compileSdkVersion', 'compileSdk = 36', s)

    # sign with the repo keystore so updates install over previous builds
    if 'anipixrelease' not in s:
        s = s.replace('android {', '''android {
    signingConfigs {
        anipixrelease {
            storeFile file(System.getenv("HOME") + "/.android/debug.keystore")
            storePassword "android"
            keyAlias "androiddebugkey"
            keyPassword "android"
        }
    }
''', 1)
        s = re.sub(r'signingConfig\s*=?\s*signingConfigs\.(getByName\("debug"\)|debug)',
                   'signingConfig = signingConfigs.getByName("anipixrelease")', s)
    s = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23', s)
    s = re.sub(r'compileSdkVersion\s+flutter\.compileSdkVersion', 'compileSdkVersion 36', s)
    s = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 23', s)

    if 'inapp-sdk' not in s:
        dep = ('    implementation("com.startapp:inapp-sdk:%s")' % STARTAPP_SDK
               if path.endswith('.kts')
               else "    implementation 'com.startapp:inapp-sdk:%s'" % STARTAPP_SDK)
        if re.search(r'dependencies\s*\{', s):
            s = re.sub(r'dependencies\s*\{',
                       lambda m: m.group(0) + '\n' + dep, s, count=1)
        else:
            s += '\ndependencies {\n' + dep + '\n}\n'

    if 'sourceCompatibility' not in s and not path.endswith('.kts'):
        s = s.replace('android {',
                      "android {\n    compileOptions {\n"
                      "        sourceCompatibility JavaVersion.VERSION_17\n"
                      "        targetCompatibility JavaVersion.VERSION_17\n"
                      "    }\n", 1)

    open(path, 'w').write(s)
    print('gradle patched:', path)
    for line in s.splitlines():
        if 'compileSdk' in line or 'minSdk' in line or 'inapp-sdk' in line:
            print('   ', line.strip())
    print('   dependencies block present:', 'dependencies' in s)


def patch_manifest():
    path = os.path.join(BASE, 'src/main/AndroidManifest.xml')
    m = open(path).read()

    if 'android.permission.INTERNET' not in m:
        m = re.sub(r'(<application[^>]*>)',
                   r'<uses-permission android:name="android.permission.INTERNET"/>\n    \1', m, count=1)
    if 'android.permission.AD_ID' not in m:
        m = re.sub(r'(<application[^>]*>)',
                   r'<uses-permission android:name="android.permission.AD_ID"/>\n    \1', m, count=1)
    for perm in ['FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_DATA_SYNC', 'POST_NOTIFICATIONS']:
        if 'android.permission.' + perm not in m:
            m = re.sub(r'(<application[^>]*>)',
                       r'<uses-permission android:name="android.permission.' + perm + r'"/>\n    \1', m, count=1)
    if 'UploadService' not in m:
        m = re.sub(r'(<application[^>]*>)',
                   r'\1\n        <service android:name=".UploadService" android:exported="false" android:foregroundServiceType="dataSync" />',
                   m, count=1)
    # --- keep keys across reinstall (Android auto backup) ---
    if 'android:allowBackup' not in m:
        m = re.sub(r'(<application[^>]*?)(\s*>)',
                   r'\1 android:allowBackup="true" android:fullBackupContent="@xml/backup_rules" android:dataExtractionRules="@xml/data_extraction_rules"\2',
                   m, count=1)
    if 'supportsPictureInPicture' not in m:
        m, n_pip = re.subn(r'(<activity[^>]*?android:name="\.MainActivity")',
                           r'\1\n            android:supportsPictureInPicture="true"',
                           m, count=1)
        if n_pip == 0:
            raise SystemExit('PATCH FAILED: could not add supportsPictureInPicture to MainActivity')
        print('PiP enabled on MainActivity')
    if 'com.startapp.sdk.APPLICATION_ID' not in m:
        m = re.sub(r'(<application[^>]*>)',
                   r'\1\n        <meta-data android:name="com.startapp.sdk.APPLICATION_ID" '
                   r'android:value="%s" />' % STARTAPP_ID, m, count=1)

    open(path, 'w').write(m)
    print('manifest patched')
    for line in m.splitlines():
        if 'permission' in line or 'startapp' in line or 'android:label' in line:
            print('   ', line.strip())


def patch_firebase():
    import os, shutil

    # 1) google-services.json next to the app module
    src = os.path.join('app', 'android_extra', 'google-services.json')
    dst = os.path.join(BASE, 'google-services.json')
    if os.path.exists(src):
        shutil.copyfile(src, dst)
        print('google-services.json copied')

    # 2) settings.gradle -> declare the plugin
    for name in ('settings.gradle', 'settings.gradle.kts'):
        p = os.path.join(BASE, '..', name)
        if os.path.exists(p):
            t = open(p, encoding='utf-8').read()
            if 'google-services' not in t:
                if 'plugins {' in t:
                    t = t.replace('plugins {',
                                  'plugins {\n    id "com.google.gms.google-services" version "4.4.2" apply false', 1)
                open(p, 'w', encoding='utf-8').write(t)
                print('settings.gradle patched')

    # 3) app/build.gradle -> apply the plugin
    for name in ('build.gradle', 'build.gradle.kts'):
        p = os.path.join(BASE, name)
        if not os.path.exists(p):
            continue
        t = open(p, encoding='utf-8').read()
        if 'google-services' in t:
            continue
        if 'plugins {' in t:
            t = t.replace('plugins {', 'plugins {\n    id "com.google.gms.google-services"', 1)
        elif t.lstrip().startswith('apply plugin'):
            t = 'apply plugin: "com.google.gms.google-services"\n' + t
        open(p, 'w', encoding='utf-8').write(t)
        print(name, 'patched for Firebase')


def write_backup_rules():
    import os
    d = os.path.join(BASE, 'src', 'main', 'res', 'xml')
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, 'backup_rules.xml'), 'w', encoding='utf-8') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<full-backup-content>
    <include domain="sharedpref" path="."/>
</full-backup-content>
''')
    with open(os.path.join(d, 'data_extraction_rules.xml'), 'w', encoding='utf-8') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup>
        <include domain="sharedpref" path="."/>
    </cloud-backup>
    <device-transfer>
        <include domain="sharedpref" path="."/>
    </device-transfer>
</data-extraction-rules>
''')
    print('backup rules written')


def main():
    if not os.path.isdir(BASE):
        print('!! android folder missing:', BASE)
        sys.exit(1)
    patch_gradle()
    patch_manifest()
    write_backup_rules()
    patch_firebase()


if __name__ == '__main__':
    main()
