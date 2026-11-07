# >>> termux-android-dev >>>
export JAVA_HOME=$PREFIX/lib/jvm/java-21-openjdk
export ANDROID_HOME=$HOME/android-sdk
export ANDROID_SDK_ROOT=$ANDROID_HOME
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin
# adb also lists localhost:5555 as emulator-5554; pin one so 'adb shell' isn't ambiguous.
export ANDROID_SERIAL=127.0.0.1:5555
# <<< termux-android-dev <<<
