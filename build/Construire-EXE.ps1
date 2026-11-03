<#
  Construire-EXE.ps1 - Digital Farming School
  Transforme Configurer-DFS.ps1 en application AgriGeek-Hotspot.exe avec l'icône agrigeek.ico,
  puis crée deux raccourcis : « AgriGeek Hotspot » et « Réparer le partage Internet ».

  À lancer une seule fois via Construire-EXE.bat (connexion Internet requise au premier lancement).
#>

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$root = Split-Path $PSScriptRoot -Parent
$src  = Join-Path $root 'src\Configurer-DFS.ps1'
$ico  = Join-Path $root 'assets\agrigeek.ico'
$exe  = Join-Path $root 'AgriGeek-Hotspot.exe'

foreach ($f in $src, $ico) {
    if (-not (Test-Path $f)) { Write-Host "Fichier manquant : $f" -ForegroundColor Red; Read-Host 'Entrée pour fermer'; exit 1 }
}

try {
    # 1. Installer le module ps2exe (une seule fois, pour l'utilisateur courant)
    if (-not (Get-Module -ListAvailable -Name ps2exe)) {
        Write-Host '==> Installation du module ps2exe...' -ForegroundColor Cyan
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
        }
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module ps2exe

    # 2. Compiler
    Write-Host '==> Compilation de AgriGeek-Hotspot.exe...' -ForegroundColor Cyan
    Invoke-ps2exe -inputFile $src -outputFile $exe -iconFile $ico -requireAdmin `
        -title 'AgriGeek Hotspot' `
        -description 'Configuration Ethernet et point d''accès Wi-Fi de la Digital Farming School' `
        -product 'AgriGeek Hotspot' -company 'Digital Farming School' `
        -copyright '© Digital Farming School' -version '1.0.0.0'

    if (-not (Test-Path $exe)) { throw 'La compilation n''a pas produit de fichier .exe.' }

    # 3. Raccourcis (dossier courant + Bureau)
    $shell   = New-Object -ComObject WScript.Shell
    $desktop = [Environment]::GetFolderPath('Desktop')
    $links = @(
        @{ Name = 'AgriGeek Hotspot';               Args = '' },
        @{ Name = 'Réparer le partage Internet';    Args = '-Repair' }
    )
    foreach ($dir in $root, $desktop) {
        foreach ($l in $links) {
            $lnk = $shell.CreateShortcut((Join-Path $dir "$($l.Name).lnk"))
            $lnk.TargetPath       = $exe
            $lnk.Arguments        = $l.Args
            $lnk.WorkingDirectory = $root
            $lnk.IconLocation     = "$exe,0"
            $lnk.Save()
        }
    }

    Write-Host ''
    Write-Host "[OK] Application créée : $exe" -ForegroundColor Green
    Write-Host '[OK] Raccourcis créés ici et sur le Bureau : « AgriGeek Hotspot » et « Réparer le partage Internet ».' -ForegroundColor Green
} catch {
    Write-Host "[X] $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ''
Read-Host 'Appuyez sur Entrée pour fermer'
