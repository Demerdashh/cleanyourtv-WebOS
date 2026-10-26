#!/bin/sh
# node8-check.sh - Phase 3, step 1 (CleanYourTV backport to webOS 4.5)
# Installs a standalone Node.js 8 next to LG's system Node and tests it.
# Writes ONLY to /media/developer/node8 (plus a temp folder it deletes).
# LG's /usr/bin/node (0.12.2) is NOT touched. To undo:  rm -rf /media/developer/node8
#
# Windows:
#   scp node8-check.sh lgtv:/tmp/node8-check.sh
#   ssh lgtv "tr -d '\r' < /tmp/node8-check.sh > /tmp/n8.sh && sh /tmp/n8.sh" | Out-File -Encoding utf8 node8.txt

exec 2>&1
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
V=v8.17.0
N=node-$V-linux-armv7l
DST=/media/developer/node8
W=/media/developer/tmp/node8-dl
sec() { printf '\n========== %s ==========\n' "$1"; }

sec "LIBRARIES NODE 8 LINKS AGAINST"
ls -l /usr/lib/libstdc++.so* /lib/libgcc_s.so* /lib/libdl.so* /lib/librt.so* /lib/libpthread.so* /lib/libm.so* 2>&1

sec "BROWSER ENGINE VERSION (read-only scan)"
for f in /usr/bin/WebAppMgr /usr/lib/libcbe.so*; do
  [ -f "$f" ] || continue
  printf '%s: ' "$f"
  /usr/bin/node -e '
    var fs = require("fs"), fd = fs.openSync(process.argv[1], "r"), b = new Buffer(4194304), pos = 0, tail = "", seen = {}, n;
    while ((n = fs.readSync(fd, b, 0, b.length, pos)) > 0) {
      var s = tail + b.toString("binary", 0, n), r = /Chrome\/\d+\.[\d.]+/g, m;
      while ((m = r.exec(s))) seen[m[0]] = 1;
      tail = s.slice(-40); pos += n;
    }
    console.log(Object.keys(seen).join(" ") || "(no Chrome/ string found)");' "$f"
done

sec "DOWNLOAD NODE $V (armv7l)"
mkdir -p "$DST" "$W" && cd "$W" || { echo "cannot create $W"; exit 1; }
curl -fsSL -o $N.tar.gz "https://nodejs.org/dist/$V/$N.tar.gz" || { echo "DOWNLOAD FAILED - nothing installed"; rm -rf "$W"; exit 1; }
want=$(curl -fsSL "https://nodejs.org/dist/$V/SHASUMS256.txt" | grep " $N.tar.gz\$" | cut -d' ' -f1)
got=$(/usr/bin/node -e 'console.log(require("crypto").createHash("sha256").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' $N.tar.gz)
echo "expected sha256: $want"
echo "actual   sha256: $got"
if [ -z "$want" ] || [ "$want" != "$got" ]; then echo "CHECKSUM MISMATCH - nothing installed"; cd /; rm -rf "$W"; exit 1; fi
gzip -dc $N.tar.gz | tar xf - $N/bin/node || { echo "EXTRACT FAILED"; cd /; rm -rf "$W"; exit 1; }
mv $N/bin/node "$DST/node" && chmod 755 "$DST/node"
cd /; rm -rf "$W"
ls -l "$DST/node"; df -h /media/developer

sec "NODE 8 RUNS?"
"$DST/node" -v || { echo "NODE 8 DOES NOT RUN ON THIS TV"; exit 1; }
"$DST/node" -p 'JSON.stringify(process.versions)'

sec "NODE 8 FEATURES THE SERVICE USES"
"$DST/node" -e '
  async function f() { return await Promise.resolve(1); }
  f().then(v => console.log("  ok    async/await"));
  const { URL } = require("url"); console.log("  ok    URL", new URL("http://a/b?c=1").pathname);
  console.log("  ok    Buffer.from", Buffer.from("hi").toString("hex"));
  console.log("  ok    Object.entries", JSON.stringify(Object.entries({ a: 1 })));
  console.log("  ok    template literals", `${1 + 1}`);
  console.log("  RSS at start:", Math.round(process.memoryUsage().rss / 1048576), "MB");'

sec "NODE 8 HTTPS"
for ca in bundled tv; do
  [ $ca = tv ] && export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
  "$DST/node" -e '
    var tag = process.argv[1];
    require("https").get({ host: "api.github.com", path: "/", headers: { "User-Agent": "cytv-test" } }, function (r) {
      console.log("  " + tag + " CAs: api.github.com -> HTTP " + r.statusCode); r.resume();
    }).on("error", function (e) { console.log("  " + tag + " CAs: FAIL " + e.message); });' "$ca"
done
unset NODE_EXTRA_CA_CERTS

sec "DONE"
