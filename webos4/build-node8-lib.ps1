# build-node8-lib.ps1 - Phase 3, step 2 (CleanYourTV backport to webOS 4.5)
# Builds a small hard-float (armhf) runtime for Node 8 from Debian 10 "buster" packages, uploads it to the TV
# and runs node8-runtime.sh there. Needs: node8-runtime.sh in the same folder, and the "lgtv" SSH alias.
#
#   powershell -ExecutionPolicy Bypass -File .\build-node8-lib.ps1

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'          # Invoke-WebRequest is much faster without the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Tar      = "$env:SystemRoot\System32\tar.exe"    # Windows' bsdtar (reads .deb and .xz)
$Base     = 'https://archive.debian.org/debian/pool/main/g'
$Here     = $PSScriptRoot
$Work     = Join-Path $Here 'node8-lib-work'
$Out      = Join-Path $Here 'node8-lib.tar.gz'
$TvScript = Join-Path $Here 'node8-runtime.sh'
$Report   = Join-Path $Here 'node8-runtime.txt'

function Say($m) { Write-Host "[node8-lib] $m" -ForegroundColor Cyan }
function TarQuiet([string[]]$a) {                  # symlinks fail on Windows; we only need the regular files
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & $Tar @a 2>&1 | Out-Null
  $ErrorActionPreference = $old
}

if (-not (Test-Path $TvScript)) { throw "node8-runtime.sh must be in the same folder as this script ($Here)" }
if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
New-Item -ItemType Directory -Path "$Work\debs", "$Work\root", "$Work\lib" | Out-Null

# ---- 1. find and download the three packages (preferred name, else the newest match in the folder) ----
$pkgs = @(
  @{ dir = 'glibc'; want = 'libc6_2.28-10+deb10u1_armhf.deb'; re = 'libc6_2\.28-[^"<>\s]*_armhf\.deb' },
  @{ dir = 'gcc-8'; want = 'libstdc++6_8.3.0-6_armhf.deb';   re = 'libstdc\+\+6_8\.3\.0-[^"<>\s]*_armhf\.deb' },
  @{ dir = 'gcc-8'; want = 'libgcc1_8.3.0-6_armhf.deb';      re = 'libgcc1_8\.3\.0-[^"<>\s]*_armhf\.deb' }
)
$listings = @{}
foreach ($p in $pkgs) {
  if (-not $listings.ContainsKey($p.dir)) {
    Say "reading the Debian archive folder $($p.dir)"
    $html = (Invoke-WebRequest -UseBasicParsing -Uri "$Base/$($p.dir)/").Content
    $listings[$p.dir] = [uri]::UnescapeDataString($html)
  }
  $names = [regex]::Matches($listings[$p.dir], $p.re) | ForEach-Object Value | Sort-Object -Unique
  if (-not $names) { throw "no package matching $($p.re) in $Base/$($p.dir)/" }
  $name = if ($names -contains $p.want) { $p.want } else { $names[-1] }
  Say "downloading $name"
  Invoke-WebRequest -UseBasicParsing -Uri "$Base/$($p.dir)/$name" -OutFile "$Work\debs\$name"
}

# ---- 2. unpack: .deb (ar) -> data.tar.xz -> files ----
foreach ($deb in Get-ChildItem "$Work\debs" -Filter *.deb) {
  Say "unpacking $($deb.Name)"
  $x = Join-Path $Work ("x-" + $deb.BaseName)
  New-Item -ItemType Directory -Path $x | Out-Null
  & $Tar -xf $deb.FullName -C $x
  if ($LASTEXITCODE -ne 0) { throw "could not open $($deb.Name)" }
  $data = Get-ChildItem $x -Filter 'data.tar.*' | Select-Object -First 1
  if (-not $data) { throw "no data.tar in $($deb.Name)" }
  TarQuiet @('-xf', $data.FullName, '-C', "$Work\root")
}

# ---- 3. pick the libraries Node 8 needs, under their soname ----
$map = [ordered]@{
  'ld-linux-armhf.so.3' = 'ld-2.*.so'
  'libc.so.6'           = 'libc-2.*.so'
  'libm.so.6'           = 'libm-2.*.so'
  'libdl.so.2'          = 'libdl-2.*.so'
  'libpthread.so.0'     = 'libpthread-2.*.so'
  'librt.so.1'          = 'librt-2.*.so'
  'libresolv.so.2'      = 'libresolv-2.*.so'      # DNS
  'libnss_dns.so.2'     = 'libnss_dns-2.*.so'     # DNS
  'libnss_files.so.2'   = 'libnss_files-2.*.so'   # /etc/hosts
  'libstdc++.so.6'      = 'libstdc++.so.6.0.*'
  'libgcc_s.so.1'       = 'libgcc_s.so.1'
}
foreach ($so in $map.Keys) {
  $f = Get-ChildItem "$Work\root" -Recurse -File -Filter $map[$so] |
       Where-Object { $_.Length -gt 1000 -and $_.FullName -match 'arm-linux-gnueabihf' } | Select-Object -First 1
  if (-not $f) { throw "library $so ($($map[$so])) not found in the packages" }
  Copy-Item $f.FullName "$Work\lib\$so"
  Say ("  {0,-22} <- {1} ({2:N0} KB)" -f $so, $f.Name, ($f.Length / 1KB))
}

# ---- 4. pack, upload, run the TV part ----
if (Test-Path $Out) { Remove-Item $Out -Force }
& $Tar -czf $Out -C "$Work\lib" .
if ($LASTEXITCODE -ne 0) { throw "packing failed" }
Say ("runtime packed: {0:N0} KB" -f ((Get-Item $Out).Length / 1KB))

Say "uploading to the TV"
scp $Out lgtv:/tmp/node8-lib.tar.gz;    if ($LASTEXITCODE -ne 0) { throw "scp of the runtime failed" }
scp $TvScript lgtv:/tmp/node8-runtime.sh; if ($LASTEXITCODE -ne 0) { throw "scp of node8-runtime.sh failed" }

Say "installing and testing on the TV (about a minute)"
$result = ssh lgtv "tr -d '\r' < /tmp/node8-runtime.sh > /tmp/n8r.sh && sh /tmp/n8r.sh"
$result | Out-File -Encoding utf8 $Report
$result
Remove-Item $Work -Recurse -Force
Say "done - the report is in $Report"
