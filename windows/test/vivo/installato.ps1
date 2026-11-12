# Prova l'app INSTALLATA (dall'installer vero) su una macchina Windows: avvio normale con una schermata del desktop, poi i copioni dal
# vivo sull'app installata, ognuno con una cartella di dati nuova, poi la disinstallazione. Pensato per il flusso «Prova dell'installer»
# (.github/workflows/prova-installer.yml), su una macchina usa e getta di GitHub: non va lanciato sul PC di qualcuno (usa %APPDATA%\FocusFriends).
#
# uso:  pwsh windows/test/vivo/installato.ps1 -Installer <Setup.exe> -Out <cartella dei risultati>

param(
  [Parameter(Mandatory = $true)][string]$Installer,
  [Parameter(Mandatory = $true)][string]$Out
)
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$message) { Write-Host "::error::$message"; $failures.Add($message) }

function Shot([string]$path) {
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
  $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $graphics.Dispose(); $bitmap.Dispose()
}

function Stop-App { Get-Process FocusFriends -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep -Seconds 2 }

# 1. L'installazione, senza finestre (/S), per l'utente
Write-Host "== Installazione: $Installer"
$install = Start-Process -FilePath $Installer -ArgumentList "/S" -Wait -PassThru
Write-Host "codice d'uscita dell'installer: $($install.ExitCode)"
Start-Sleep -Seconds 3
Stop-App
# Dove l'ha messa l'installer (i documenti dicono %LOCALAPPDATA%\Programs\FocusFriends: si controlla)
$found = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA "Programs"), $env:ProgramFiles -Filter "FocusFriends.exe" -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $found) { Fail "dopo l'installazione FocusFriends.exe non c'è né in %LOCALAPPDATA%\Programs né in Program Files"; exit 1 }
$exe = $found.FullName
$dir = $found.DirectoryName
Write-Host "installata in $dir"
if ($dir -ne (Join-Path $env:LOCALAPPDATA "Programs\FocusFriends")) { Write-Host "::warning::la cartella non è quella dei documenti (%LOCALAPPDATA%\Programs\FocusFriends): $dir" }
Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "FocusFriends*" } | Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation | Format-List | Out-String | Write-Host
Get-ChildItem $dir | Select-Object Name, Length | Format-Table | Out-String | Write-Host
$startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\FocusFriends.lnk"
if (Test-Path $startMenu) { Write-Host "voce nel menu Start: c'è" } else { Fail "manca la voce nel menu Start ($startMenu)" }
(Get-Item $exe).VersionInfo | Select-Object ProductVersion, FileVersion, ProductName | Format-List | Out-String | Write-Host

# 2. L'avvio normale, come lo fa una persona: niente variabili di prova. Dati veri della macchina usa e getta: %APPDATA%\FocusFriends.
Write-Host "== Avvio normale"
$data = Join-Path $env:APPDATA "FocusFriends"
$app = Start-Process -FilePath $exe -PassThru
Start-Sleep -Seconds 20
if ($app.HasExited) { Fail "l'app si è chiusa da sola (codice $($app.ExitCode))" } else { Write-Host "l'app è aperta dopo 20 secondi (pid $($app.Id))" }
Shot (Join-Path $Out "desktop-avvio.png")
$log = Join-Path $data "registro-app.log"
if (Test-Path $log) {
  Write-Host "-- registro-app.log"; Get-Content $log | Write-Host
  if (Select-String -Path $log -Pattern "ERRORE|errore|eccezione|respinta" -Quiet) { Fail "il registro dell'app ha degli errori all'avvio" }
} else { Fail "manca $log" }
Get-Process FocusFriends -ErrorAction SilentlyContinue | Select-Object Id, @{n = "MB"; e = { [math]::Round($_.WorkingSet64 / 1MB) } } | Format-Table | Out-String | Write-Host
# Un secondo avvio non deve aprire una seconda copia
Start-Process -FilePath $exe | Out-Null
Start-Sleep -Seconds 6
Shot (Join-Path $Out "desktop-secondo-avvio.png")
if (-not (Get-Process -Id $app.Id -ErrorAction SilentlyContinue)) { Fail "il secondo avvio ha chiuso la prima copia" }
Stop-App
if (Test-Path $data) { Copy-Item -Recurse $data (Join-Path $Out "dati-avvio-normale") }

# 3. I copioni dal vivo sull'app installata (FF_SELFTEST; i dati in una cartella nuova per ognuno)
$all = '{"version":1,"introSeen":true,"name":"Prova","firstCompanion":"gattino","unlocked":["pianty","porcellino","ciccio","gattino","riccio","tartaruga"]}'
$scripts = @(
  @{ name = "pacchetto"; seconds = 40 },
  @{ name = "introduzione"; seconds = 60; intro = $true },
  @{ name = "giro"; seconds = 120; intro = $true },
  @{ name = "scheda"; seconds = 40 },
  @{ name = "scheda-pagine"; seconds = 60 },
  @{ name = "scheda-clic"; seconds = 60 },
  @{ name = "timer"; seconds = 60 },
  @{ name = "focus-finito"; seconds = 110 },
  @{ name = "riflessione"; seconds = 110 },
  @{ name = "trascinamento"; seconds = 60 },
  @{ name = "statistiche"; seconds = 110 },
  @{ name = "anno"; seconds = 90 },
  @{ name = "dafare"; seconds = 90 },
  @{ name = "sblocchi"; seconds = 60 },
  @{ name = "audio"; seconds = 90 },
  @{ name = "sicurezza"; seconds = 40 },
  @{ name = "chiusura"; seconds = 100 },
  @{ name = "giardino"; seconds = 130; profile = $all },
  @{ name = "giardino-tartaruga"; seconds = 100; profile = $all },
  @{ name = "giardino-interazioni"; seconds = 200; profile = '{"version":1,"introSeen":true,"firstCompanion":"gattino","unlocked":["gattino"]}' },
  @{ name = "album"; seconds = 90; profile = '{"version":1,"introSeen":true,"name":"Prova","firstCompanion":"gattino","unlocked":["gattino","pianty","porcellino"]}' },
  @{ name = "album-scene"; seconds = 90; profile = '{"version":1,"introSeen":true,"firstCompanion":"gattino","unlocked":["pianty","porcellino","ciccio","gattino"]}' }
)
foreach ($s in $scripts) {
  $name = $s.name
  Write-Host "== Copione $name"
  $o = Join-Path $Out $name
  New-Item -ItemType Directory -Path (Join-Path $o "data") | Out-Null
  Set-Content -Path (Join-Path $o "data\impostazioni.json") -Value "{}" -Encoding utf8NoBOM
  if (-not $s.intro) {
    $p = if ($s.profile) { $s.profile } else { '{"version": 1, "introSeen": true}' }
    Set-Content -Path (Join-Path $o "data\profilo.json") -Value $p -Encoding utf8NoBOM
  }
  $env:FF_SELFTEST = "1"; $env:FF_DATA_DIR = Join-Path $o "data"; $env:FF_SELFTEST_OUT = $o
  $env:FF_SELFTEST_FILE = Join-Path $here "$name.cjs"
  $proc = Start-Process -FilePath $exe -PassThru -RedirectStandardOutput (Join-Path $o "log.txt") -RedirectStandardError (Join-Path $o "errori.txt")
  if (-not $proc.WaitForExit($s.seconds * 1000)) { Fail "$name non ha finito in $($s.seconds) secondi"; Stop-App }
  Remove-Item Env:FF_SELFTEST, Env:FF_DATA_DIR, Env:FF_SELFTEST_OUT, Env:FF_SELFTEST_FILE
  Get-Content (Join-Path $o "log.txt") | Write-Host
  $errors = Get-Content (Join-Path $o "errori.txt") | Where-Object { $_ -notmatch "sandbox_extension|DevTools|GPU|gpu_|viz_main|dxgi|angle" }
  if ($errors) { Write-Host "-- stderr"; $errors | Write-Host }
  if (Select-String -Path (Join-Path $o "log.txt") -Pattern "\[prova\] errore|\[pagina:3\]|processo finito" -Quiet) { Fail "$name : errori nella pagina o nel copione (vedi sopra)" }
}

# 4. La disinstallazione: l'app va via, i dati di studio restano
Write-Host "== Disinstallazione"
$uninstaller = Join-Path $dir "Uninstall FocusFriends.exe"
if (Test-Path $uninstaller) {
  Start-Process -FilePath $uninstaller -ArgumentList "/S" -Wait | Out-Null
  Start-Sleep -Seconds 5
  if (Test-Path $exe) { Fail "dopo la disinstallazione c'è ancora $exe" } else { Write-Host "app tolta" }
  if (Test-Path $data) { Write-Host "i dati sono rimasti: $((Get-ChildItem $data).Name -join ', ')" } else { Fail "la disinstallazione ha tolto anche i dati ($data)" }
} else { Fail "manca il programma di disinstallazione ($uninstaller)" }

Write-Host ""
if ($failures.Count -gt 0) { Write-Host "PROBLEMI ($($failures.Count)):"; $failures | ForEach-Object { Write-Host " - $_" }; exit 1 }
Write-Host "Nessun problema trovato (le schermate e i log sono nei risultati: vanno guardati)."
