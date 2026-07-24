<#
.SYNOPSIS
  MitFahrBar als Web-App bauen und im Standardbrowser öffnen (Windows).

.DESCRIPTION
  Baut die App als Release und liefert sie lokal aus. Für macOS und Linux
  liegt daneben `run_web.sh`.

  Beenden mit Strg-C; der Server wird dabei mit beendet.

.PARAMETER Port
  Port des lokalen Servers. Standard: 8080.

.EXAMPLE
  .\tool\run_web.ps1

.EXAMPLE
  .\tool\run_web.ps1 -Port 9000
#>
[CmdletBinding()]
param(
    [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'

$Host_ = '127.0.0.1'
$Url = "http://${Host_}:${Port}"

Set-Location (Split-Path $PSScriptRoot -Parent)

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    Write-Error @"
'flutter' ist nicht im PATH.
Flutter installieren (https://flutter.dev) oder das SDK in den PATH aufnehmen:
  `$env:Path = 'C:\Pfad\zu\flutter\bin;' + `$env:Path
"@
    exit 1
}

Write-Host "MitFahrBar wird gebaut und auf $Url ausgeliefert ..."
Write-Host "(Der erste Build dauert etwa eine halbe Minute.)"

$process = Start-Process -FilePath $flutter.Source -ArgumentList @(
    'run', '-d', 'web-server', '--release',
    '--web-port', $Port, '--web-hostname', $Host_
) -PassThru -NoNewWindow

try {
    # Warten, bis wirklich ausgeliefert wird - nicht bloss, bis der Port
    # belegt ist.
    $opened = $false
    foreach ($attempt in 1..180) {
        if ($process.HasExited) {
            Write-Error 'Der Build wurde vorzeitig beendet.'
            exit 1
        }
        try {
            Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2 | Out-Null
            Write-Host 'Bereit - oeffne den Standardbrowser.'
            Start-Process $Url   # oeffnet den im System hinterlegten Browser
            $opened = $true
            break
        } catch {
            Start-Sleep -Seconds 1
        }
    }

    if (-not $opened) {
        Write-Error @"
Zeitueberschreitung: $Url antwortet nicht.
Laeuft dort vielleicht schon etwas anderes? Dann anderen Port waehlen:
  .\tool\run_web.ps1 -Port 9000
"@
        exit 1
    }

    Write-Host 'Laeuft. Zum Beenden Strg-C druecken.'
    Wait-Process -Id $process.Id
} finally {
    if (-not $process.HasExited) {
        # Den ganzen Prozessbaum beenden: 'flutter' ist nur ein Starter,
        # ausgeliefert wird von einem Dart-Kindprozess. Stop-Process allein
        # liesse den weiterlaufen - der Port bliebe belegt.
        & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host ''
    Write-Host 'Server beendet.'
}
