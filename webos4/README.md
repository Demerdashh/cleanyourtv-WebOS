# webOS 4 compatibility layer (this fork)

Upstream CleanYourTV needs webOS 5 or newer: it checks for `systemctl` and for a Node.js that runs ES2015+, and webOS 4
has neither (Upstart, Node 0.12.2). This fork adds a small compatibility folder on the TV and puts it first in the `PATH`
of every script, so upstream's code runs unchanged:

| `/media/developer/cytv-compat/bin/` | what it is |
|---|---|
| `node` | link to `/media/developer/node8/node`: official Node 8.17.0 (armhf), started through its own armhf loader and libraries from Debian 10, because webOS 4 is soft-float (`ld-linux.so.3`). `--library-path`, not `LD_LIBRARY_PATH`, so the programs Node starts keep the TV's own libraries. Our copy of the loader ignores `/etc/ld.so.preload` (LG's soft-float `libSegFault.so`). |
| `systemctl` | shim that translates the few commands the scripts use (`restart`, `start`, `stop`, `is-active`, `cat`, `list-units`, `--no-block`) to Upstart's `initctl`; anything else is refused. Calls are logged to `/tmp/cytv-systemctl.log`. |

On TVs without the folder (webOS 5 and newer) nothing changes: a missing folder in `PATH` is skipped.

`scripts/10-cleanyourtv-home`: webOS 4.5 preloads LG's native Home at boot ("preload":"full"), and that process outlives
the plain `kill` the stand-in takeover sends, so the Home key kept showing LG's Home. When it survives, it is closed
through sam (`closeByAppId`), then `kill -CONT` + `TERM`, then `KILL`. On other TVs the first kill works and this never runs.

Other changes: `compat.json` lists 05.40.97 (55UM7095PVC, webOS 4.5, native Home -> the "standin" takeover), and
`app/src/css/home.css` has a flexbox fallback for the app grid, because Chromium 53 (webOS 4) has no CSS grid.

## Preparing a webOS 4 TV (once, before installing the package)

1. `node8-check.sh` on the TV: downloads Node 8.17.0 armv7l into `/media/developer/node8` (SHA-256 checked).
2. `build-node8-lib.ps1` on Windows (uses `node8-runtime.sh`): the armhf runtime from Debian 10 into `/media/developer/node8/lib`.
3. `compat-step3.sh` on the TV (with `systemctl` copied to `/tmp`): patches our loader copy and creates the compat folder.

Undo: `rm -rf /media/developer/node8 /media/developer/cytv-compat`
