# Prints the path of the Lumen OS installer\ that a build bundles. $env:LUMEN_OS_DIR\installer when that variable names
# a local checkout of Project-Lumen-OS/lumen-os; otherwise a sparse checkout of that repository (installer\ only) in
# vendor\lumen-os at $env:LUMEN_OS_REF (main by default), brought up to date on every call. Needs git.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ($env:LUMEN_OS_DIR) {
  if (-not (Test-Path (Join-Path $env:LUMEN_OS_DIR "installer\lumen-install.ps1"))) { throw "no installer\lumen-install.ps1 in $env:LUMEN_OS_DIR" }
  Join-Path $env:LUMEN_OS_DIR "installer"; exit 0
}
$ref = if ($env:LUMEN_OS_REF) { $env:LUMEN_OS_REF } else { "main" }
$dir = Join-Path $root "vendor\lumen-os"
if (-not (Test-Path (Join-Path $dir ".git"))) {
  git clone -q --depth 1 --filter=blob:none --sparse --branch $ref https://github.com/Project-Lumen-OS/lumen-os.git $dir | Out-Null
  git -C $dir sparse-checkout set installer | Out-Null
} else {
  git -C $dir fetch -q --depth 1 origin $ref | Out-Null
  git -C $dir checkout -q --detach FETCH_HEAD | Out-Null
}
Join-Path $dir "installer"
