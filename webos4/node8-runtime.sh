#!/bin/sh
# node8-runtime.sh - Phase 3, step 2 (TV side). Run by build-node8-lib.ps1; can be re-run safely.
# Installs the armhf runtime into /media/developer/node8/lib, keeps the real binary as node.bin and makes
# /media/developer/node8/node a wrapper that starts it through its own loader. Then tests it.
# Writes only in /media/developer/node8. To undo everything: rm -rf /media/developer/node8

exec 2>&1
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
D=/media/developer/node8
sec() { printf '\n========== %s ==========\n' "$1"; }

sec "INSTALL ARMHF RUNTIME"
[ -f /tmp/node8-lib.tar.gz ] || { echo "missing /tmp/node8-lib.tar.gz"; exit 1; }
[ -f $D/node.bin ] || [ -f $D/node ] || { echo "the Node 8 binary is missing in $D (run node8-check.sh first)"; exit 1; }
rm -rf $D/lib && mkdir -p $D/lib
gzip -dc /tmp/node8-lib.tar.gz | tar xf - -C $D/lib || { echo "EXTRACT FAILED"; exit 1; }
chmod 755 $D/lib/*
rm -f /tmp/node8-lib.tar.gz
# the real binary becomes node.bin (only the first time: on a re-run, node is already the small wrapper)
if [ ! -f $D/node.bin ] && [ "$(wc -c < $D/node)" -gt 1000000 ]; then mv $D/node $D/node.bin; fi
cat > $D/node <<'EOF'
#!/bin/sh
# Node 8 is built hard-float (armhf); this webOS is soft-float. Start it through its own loader and libraries.
# --library-path, not LD_LIBRARY_PATH: programs Node starts (sh, luna-send, curl) must keep the TV's own libraries.
D=/media/developer/node8
exec $D/lib/ld-linux-armhf.so.3 --library-path $D/lib $D/node.bin "$@"
EOF
chmod 755 $D/node $D/node.bin
ls -l $D $D/lib
du -sh $D; df -h /media/developer

sec "NODE 8 RUNS?"
$D/node -v || { echo "NODE 8 STILL DOES NOT RUN"; $D/lib/ld-linux-armhf.so.3 --list --library-path $D/lib $D/node.bin; exit 1; }
$D/node -p 'JSON.stringify(process.versions)'

sec "FEATURES THE SERVICE USES"
$D/node -e '
  async function f() { return await Promise.resolve(1); }
  f().then(() => console.log("  ok    async/await"));
  const { URL } = require("url"); console.log("  ok    URL", new URL("http://a/b?c=1").pathname);
  console.log("  ok    Buffer.from", Buffer.from("hi").toString("hex"));
  console.log("  ok    Object.entries", JSON.stringify(Object.entries({ a: 1 })));
  console.log("  ok    crypto sha256", require("crypto").createHash("sha256").update("x").digest("hex").slice(0, 12));
  console.log("  ok    template literals", `${1 + 1}`);'

sec "DNS + HTTPS"
$D/node -e 'require("dns").lookup("github.com", function (e, a) { console.log("  dns.lookup github.com ->", e ? "FAIL " + e.message : a); })'
for ca in bundled tv; do
  [ $ca = tv ] && export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
  $D/node -e '
    var tag = process.argv[1];
    require("https").get({ host: "api.github.com", path: "/", headers: { "User-Agent": "cytv-test" } }, function (r) {
      console.log("  " + tag + " CAs: api.github.com -> HTTP " + r.statusCode); r.resume();
    }).on("error", function (e) { console.log("  " + tag + " CAs: FAIL " + e.message); });' "$ca"
done
unset NODE_EXTRA_CA_CERTS

sec "CHILD PROCESSES KEEP THE TV'S OWN LIBRARIES"
$D/node -e '
  var cp = require("child_process");
  function t(name, cmd, ok) {
    try { var o = cp.execSync(cmd, { timeout: 15000 }).toString(); console.log("  " + (ok(o) ? "ok  " : "FAIL") + "  " + name + (ok(o) ? "" : ": " + o.slice(0, 200))); }
    catch (e) { console.log("  FAIL  " + name + ": " + e.message.slice(0, 200)); }
  }
  t("sh", "echo hello", function (o) { return /hello/.test(o); });
  t("luna-send", "luna-send -n 1 -f luna://com.webos.service.tv.systemproperty/getSystemInfo \x27{\"keys\":[\"sdkVersion\"]}\x27", function (o) { return /"returnValue": *true/.test(o); });
  t("curl", "curl -s -o /dev/null -w %{http_code} https://github.com", function (o) { return o === "200"; });
  console.log("  LD_LIBRARY_PATH in children:", process.env.LD_LIBRARY_PATH || "(not set - good)");'

sec "MEMORY"
$D/node -e 'setTimeout(function () { console.log("  Node 8 idle RSS:", Math.round(process.memoryUsage().rss / 1048576), "MB"); }, 500)'
free -m

sec "DONE"
