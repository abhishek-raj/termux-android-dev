# Termux Android Dev

Build, install and debug Android apps on the same phone, from Termux, with no PC
and no root. It sets up a JDK, Gradle, Kotlin and the Android SDK. Then it connects `adb` to
the phone itself over wireless debugging, so `installDebug`, `logcat` and `jdb` breakpoints
work as they would from a computer.

Tested on a Samsung Galaxy (Android 17, aarch64) with Termux 0.118 from F-Droid.

## Install

```bash
pkg install -y git
git clone https://github.com/abhishek-raj/termux-android-dev.git ~/p/termux-android-dev
cd ~/p/termux-android-dev
bash install.sh
source ~/.bashrc
```

Safe to re-run. It needs about 2 GB of space for packages, the SDK and Gradle downloads.

| Installed | Where |
|---|---|
| OpenJDK 21, Gradle, Kotlin | Termux packages |
| `aapt2`, `adb`, `fastboot`, `d8`, `apksigner` | Termux packages (native arm64 builds) |
| SDK command-line tools, platform 36, build-tools 36.0.0, platform-tools | `~/android-sdk` |
| `adb-local`, `adb-debug` helper commands | `$PREFIX/bin` |
| `JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SERIAL` | a marked block in `~/.bashrc` |
| `android.aapt2FromMavenOverride` | `~/.gradle/gradle.properties` |

Other versions: `SDK_PLATFORM=35 BUILD_TOOLS=35.0.0 bash install.sh`.

### Why the workarounds

- Google's SDK binaries are x86_64 and won't run on the phone. The installer links Termux's
  native `aapt2`, `adb` and `fastboot` into the SDK, and points Gradle at the native `aapt2`.
- The SDK scripts start with `#!/usr/bin/env sh`, which doesn't exist in Termux. The installer
  rewrites that line. Re-run `install.sh` after updating the command-line tools.

## Build the sample

```bash
cd sample/HelloAndroid
./gradlew assembleDebug        # APK: app/build/outputs/apk/debug/app-debug.apk
```

The first build downloads Gradle and the Android Gradle Plugin, which takes several minutes.

## Connect adb to this phone

Termux is an ordinary app, so it can't install or debug other apps by itself (`pm install`
fails with a SecurityException). It goes through `adb` over wireless debugging instead.

**One-time pairing** (needs Wi-Fi; any network works, even one without internet):

1. Settings → About phone → Software information → tap **Build number** 7 times
   to turn on Developer options.
2. Developer options → turn on **Wireless debugging** → **Pair device with pairing code**.
   Use split-screen with Termux: closing the dialog cancels pairing.
3. Pair, using the port and code from that dialog:
   ```bash
   adb-local pair <pairing-port> <code>
   ```
4. Connect, using the port shown under **IP address & Port** on the Wireless debugging screen
   (it is different from the pairing port):
   ```bash
   adb-local <port>
   ```
   Tap **Allow** if a debugging prompt appears.

`adb-local <port>` also switches `adb` to `127.0.0.1:5555`, which keeps working **on cellular
or with Wi-Fi off, until the phone reboots**. After that, just run:

```bash
adb-local
```

**After a reboot:** turn on Wi-Fi and Wireless debugging, then run `adb-local <port>` again.
Pairing is remembered, so only the new port is needed.

Port 5555 stays open until you reboot or run `adb usb`. Other devices on the network still
need your approval on the phone before they can connect.

## Install, run and debug

```bash
cd sample/HelloAndroid
./gradlew installDebug
adb shell am start -n com.example.hello/.MainActivity
adb logcat --pid=$(adb shell pidof com.example.hello)
```

Breakpoints with `jdb`:

```bash
adb-debug com.example.hello            # restart the app, stop in its launcher Activity's onCreate
adb-debug com.example.hello "stop at com.example.hello.MainActivity:12"
adb-debug --attach com.example.hello   # attach to the app while it's running
```

`adb-debug` starts the app waiting for a debugger, forwards its JDWP port and sets the
breakpoints before the app resumes. Then you're in `jdb`: `where`, `locals`, `print x`,
`step`, `next`, `cont`, `list`, `exit`. Run it from the project folder so `list` can show source.
The app must be debuggable (debug builds are).

Without `adb-debug`:

```bash
adb shell am start -D -n com.example.hello/.MainActivity
adb forward tcp:8700 jdwp:$(adb shell pidof com.example.hello)
jdb -attach localhost:8700      # type the 'stop in ...' line right away, before onCreate runs
```

## Troubleshooting

| Problem | Fix |
|---|---|
| `more than one device/emulator` | `adb` lists `127.0.0.1:5555` twice (also as `emulator-5554`). The installer sets `ANDROID_SERIAL=127.0.0.1:5555`; run `source ~/.bashrc`. |
| `adb-local` can't connect after a reboot | Turn on Wi-Fi and Wireless debugging, then run `adb-local <port>`. |
| Device stays `unauthorized` / `offline` | Accept the prompt on screen. If none appears, toggle Wireless debugging off and on, then retry. |
| Termux gets killed during builds or debugging | Android killed it for low memory. Run `termux-wake-lock`, close other apps, or lower `org.gradle.jvmargs` in `~/.gradle/gradle.properties`. |
| `jdb` replies slowly | Normal when the phone is busy. Wait a few seconds after each command. |
| `sdkmanager: bad interpreter` | Re-run `bash install.sh` (restores the shebang fix). |
| AGP downloads build-tools that won't run | Re-run `bash install.sh` to link native `aapt2` into every `build-tools/*`. |

## Why not without adb?

- **Root:** none of this is needed with root, but most phones aren't rooted.
- **Sharing Termux's identity (`sharedUserId`):** F-Droid builds of Termux are signed with
  F-Droid's private key, so your app can't share Termux's user ID. Check yours with
  `apksigner verify --print-certs $(pm path com.termux | cut -d: -f2)`.
- **Without pairing:** only the app's own logs and crash reports are reachable, with no
  breakpoints.
