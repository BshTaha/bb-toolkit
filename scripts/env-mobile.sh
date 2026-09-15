#!/usr/bin/env bash
# source AFTER env.sh.  Fixes the broken system JAVA_HOME (points at the java
# BINARY, not the JDK dir) which makes jadx/apktool refuse to start.
export BB="${BB:-$HOME/bugbounty}"
export JAVA_HOME="/usr/lib/jvm/java-25-openjdk-amd64"        # JDK21 fallback: java-21-openjdk-amd64
export PATH="$BB/bin:$JAVA_HOME/bin:$PATH"
export ANDROID_SDK_HOME="$BB/opt/mobile/androidsdk"          # keep any SDK state out of $HOME
echo "[bb-mobile] JAVA_HOME=$JAVA_HOME  jadx=$(command -v jadx)"
