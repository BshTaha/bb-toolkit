#!/usr/bin/env bash
# Self-contained Android static-analysis toolchain for $BB (~/bugbounty).
# Nothing lands in /usr, /opt or ~/.local.  Verified working on Kali + OpenJDK 25.
set -euo pipefail
BB="${BB:-$HOME/bugbounty}"
M="$BB/opt/mobile"; mkdir -p "$M" "$BB/bin" "$M/apktool-framework"

# 1) jadx 1.5.6 - decompiler (runs fine on JDK 25; needs a REAL JAVA_HOME dir)
[ -d "$M/jadx-1.5.6" ] || {
  curl -L -C - -o "$M/jadx-1.5.6.zip" \
    https://github.com/skylot/jadx/releases/download/v1.5.6/jadx-1.5.6.zip
  unzip -oq "$M/jadx-1.5.6.zip" -d "$M/jadx-1.5.6"; }
ln -sfn "$M/jadx-1.5.6/bin/jadx"     "$BB/bin/jadx"
ln -sfn "$M/jadx-1.5.6/bin/jadx-gui" "$BB/bin/jadx-gui"

# 2) apktool 3.0.3 - AndroidManifest + resources.arsc decode
[ -f "$M/apktool_3.0.3.jar" ] || curl -L -C - -o "$M/apktool_3.0.3.jar" \
  https://github.com/iBotPeaches/Apktool/releases/download/v3.0.3/apktool_3.0.3.jar
cat > "$BB/bin/apktool" <<'SH'
#!/usr/bin/env bash
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-25-openjdk-amd64}"
exec java -jar "$BB/opt/mobile/apktool_3.0.3.jar" \
  --frame-path "$BB/opt/mobile/apktool-framework" "$@"
SH
chmod +x "$BB/bin/apktool"

# 3) apkeep 1.0.0 - APK acquisition (apk-pure | google-play | huawei-app-gallery | f-droid)
[ -f "$M/apkeep" ] || { curl -L -C - -o "$M/apkeep" \
  https://github.com/EFForg/apkeep/releases/download/1.0.0/apkeep-x86_64-unknown-linux-gnu
  chmod +x "$M/apkeep"; }
ln -sfn "$M/apkeep" "$BB/bin/apkeep"

# 4) bundletool - only needed if you take the Play AAB/XAPK split route
[ -f "$M/bundletool.jar" ] || curl -L -C - -o "$M/bundletool.jar" \
  https://github.com/google/bundletool/releases/download/1.18.3/bundletool-all-1.18.3.jar

# 5) pipx tools, redirected into $BB by env.sh (PIPX_HOME/PIPX_BIN_DIR)
export PIPX_HOME="$BB/opt/pipx" PIPX_BIN_DIR="$BB/bin"
pipx install apkleaks   || pipx upgrade apkleaks
pipx install androguard || pipx upgrade androguard   # 'androguard sign' = cert fingerprint check

echo "[+] done. source $BB/scripts/env-mobile.sh before use."
