#!/bin/sh
# Run by the inputhook when the voice button is pressed: start listening (the service shows the cards).
export PATH=/media/developer/cytv-compat/bin:/usr/bin:/usr/sbin:/bin:/sbin:$PATH   # webOS 4: Node 8 and the systemctl shim first (webos4/README.md)
curl -s -m 5 -X POST http://127.0.0.1:8765/api/voice/listen >/dev/null 2>&1
