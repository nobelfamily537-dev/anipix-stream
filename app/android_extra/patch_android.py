"""Patches the generated Android project for the AniPix Stream app.

Run from the repository root after `flutter create`:
    python3 app/android_extra/patch_android.py
"""

import os
import re
import sys

BASE = 'app/android/app'
STARTAPP_ID = '210377175'
STARTAPP_SDK = '5.4.0'


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


def main():
    if not os.path.isdir(BASE):
        print('!! android folder missing:', BASE)
        sys.exit(1)
    patch_gradle()
    patch_manifest()


if __name__ == '__main__':
    main()
