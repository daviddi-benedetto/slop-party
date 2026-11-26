# Re-creates the engine\ folder (which is NOT stored in git because the files
# are larger than GitHub's 100 MB limit). Run this once after cloning.
#
#   powershell -ExecutionPolicy Bypass -File tools\setup_engine.ps1
#   powershell -ExecutionPolicy Bypass -File tools\setup_engine.ps1 -Templates   # also export templates (1.2 GB download)
param([switch]$Templates)

$ErrorActionPreference = 'Stop'
$version = '4.7.2-stable'
$base = "https://github.com/godotengine/godot/releases/download/$version"
$root = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $root 'engine'
New-Item -ItemType Directory -Force $engine | Out-Null

$zip = Join-Path $engine 'godot.zip'
Write-Host "Downloading Godot $version editor (82 MB)..."
curl.exe -sSL -o $zip "$base/Godot_v${version}_win64.exe.zip"
Expand-Archive -Path $zip -DestinationPath $engine -Force
Remove-Item $zip

# "_sc_" turns on Godot's self-contained mode: editor settings and export
# templates live in engine\editor_data instead of %APPDATA%, keeping the whole
# project folder portable. ".gdignore" stops Godot scanning this folder.
foreach ($f in '_sc_', '.gdignore') {
    $p = Join-Path $engine $f
    if (-not (Test-Path $p)) { New-Item -ItemType File $p | Out-Null }
}

if ($Templates) {
    $tpz = Join-Path $engine 'templates.zip'
    $dest = Join-Path $engine 'editor_data\export_templates\4.7.2.stable'
    New-Item -ItemType Directory -Force $dest | Out-Null
    Write-Host "Downloading export templates (1.2 GB)..."
    curl.exe -sSL -o $tpz "$base/Godot_v${version}_export_templates.tpz"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($tpz)
    foreach ($entry in $archive.Entries) {
        if ($entry.Name -match '^(version\.txt|windows_(debug|release)_x86_64(_console)?\.exe|linux_(debug|release)\.x86_64|macos\.zip)$') {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $dest $entry.Name), $true)
        }
    }
    $archive.Dispose()
    Remove-Item $tpz
}
Write-Host "Engine ready. Run Play.bat to play or Edit.bat to open the editor."
