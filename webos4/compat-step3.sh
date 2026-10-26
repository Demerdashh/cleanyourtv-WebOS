#!/bin/sh
# compat-step3.sh - Phase 3, step 3 (CleanYourTV backport to webOS 4.5). Can be re-run safely.
#  1. our armhf loader stops reading /etc/ld.so.preload (only our copy in /media/developer/node8 is changed)
#  2. the compatibility folder /media/developer/cytv-compat/bin: node (-> Node 8) and systemctl (-> Upstart)
#  3. read-only tests of both, and of CleanYourTV's own per-TV decisions for this TV
# Writes only in /media/developer/node8, /media/developer/cytv-compat and /tmp. Nothing of LG's is changed.
# Undo: rm -rf /media/developer/cytv-compat ; mv the .orig loader back (see step 1)
#
# Windows (systemctl and compat-step3.sh in the same folder):
#   scp systemctl compat-step3.sh lgtv:/tmp/
#   ssh lgtv "tr -d '\r' < /tmp/compat-step3.sh > /tmp/cs3.sh && sh /tmp/cs3.sh" | Out-File -Encoding utf8 step3.txt

exec 2>&1
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
N=/media/developer/node8
C=/media/developer/cytv-compat
LD=$N/lib/ld-linux-armhf.so.3
REF=5667cd53e31d08e64518a2f50248d5bbd329dca0
RAW=https://raw.githubusercontent.com/lasharor/cleanyourtv-WebOS/$REF
sec() { printf '\n========== %s ==========\n' "$1"; }

sec "1. LOADER: IGNORE /etc/ld.so.preload (our copy only)"
[ -f $LD.orig ] || cp $LD $LD.orig
/usr/bin/node -e '
  var fs = require("fs"), f = process.argv[1], b = fs.readFileSync(f), s = b.toString("binary");
  var from = "/etc/ld.so.preload", to = "/dev/null/preload0";   // same length; /dev/null is not a folder, so the file never exists
  var i = s.indexOf(from);
  if (i < 0) { console.log(s.indexOf(to) >= 0 ? "  already patched" : "  string not found - left alone"); process.exit(0); }
  if (s.indexOf(from, i + 1) >= 0) { console.log("  found twice - left alone"); process.exit(0); }
  b.write(to, i, to.length, "binary");
  fs.writeFileSync(f + ".new", b);
  console.log("  patched at offset " + i);' $LD
if [ -f $LD.new ]; then chmod 755 $LD.new && mv $LD.new $LD; fi
out=$($N/node -v 2>&1)
echo "  node -v: $out"
case "$out" in *ERROR*) echo "  still warning - restoring the original loader"; cp $LD.orig $LD ;; *) echo "  ok    no preload warning" ;; esac

sec "2. COMPAT FOLDER"
mkdir -p $C/bin
[ -f /tmp/systemctl ] || { echo "  /tmp/systemctl missing (scp it first)"; exit 1; }
tr -d '\r' < /tmp/systemctl > $C/bin/systemctl && rm -f /tmp/systemctl
ln -sf $N/node $C/bin/node
chmod 755 $C/bin/systemctl
chmod -R go-w $C $N 2>/dev/null     # root runs these at boot: nobody else may write them
ls -l $C/bin

sec "3a. PATH WITH THE COMPAT FOLDER FIRST"
export PATH=$C/bin:/usr/bin:/usr/sbin:/bin:/sbin
echo "  node      -> $(command -v node): $(node -v 2>&1)"
echo "  systemctl -> $(command -v systemctl)"
node -e '(()=>1)()' && echo "  ok    upstream's Node gate passes"
command -v systemctl >/dev/null && echo "  ok    upstream's systemd gate passes"

sec "3b. SYSTEMCTL SHIM (read-only commands)"
for u in sam webapp-mgr eim preload-manager memorymanager remotelogger service-logger contentminer nudge; do
  a=$(systemctl is-active $u.service); systemctl cat $u.service >/dev/null 2>&1 && c=present || c=absent
  printf '  %-16s %-8s %s\n' "$u" "$c" "$a"
done
echo "  list-units: $(systemctl list-units --no-legend | wc -l) jobs"
systemctl daemon-reload >/dev/null 2>&1 || echo "  ok    unknown command refused"

sec "3c. WEBAPP-MGR API (the stand-in uses it)"
luna-send -n 1 -w 5000 luna://com.palm.webappmanager/listRunningApps '{}' </dev/null | cut -c1-600

sec "3d. CLEANYOURTV'S DECISIONS FOR THIS TV (upstream $REF, run from /tmp)"
P=/tmp/cytv-probe; rm -rf $P; mkdir -p $P/overlay
for f in helper/tvprofile.js scripts/jtool.js; do curl -fsSL -o $P/${f##*/} "$RAW/$f" || echo "  download of $f failed"; done
HA=/usr/palm/applications/com.webos.app.home/appinfo.json
kind=$(node $P/jtool.js kind $HA); echo "  Home kind: $kind"
echo "  Home program: $(node $P/jtool.js exe $HA)"
node $P/tvprofile.js show --sdk 4.10.0 --firmware 05.40.97 --home "$kind"
node $P/jtool.js stage $HA $P/overlay/appinfo.json && node $P/jtool.js wamlaunch $P/overlay/appinfo.json $P/overlay $P/wam.json
echo "  launch request the stand-in would send:"; cat $P/wam.json; echo
rm -rf $P

sec "DONE"
