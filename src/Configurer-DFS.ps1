<#
  Configurer-DFS.ps1
  Digital Farming School - AgriGeek Hotspot

  1. Configure la carte Ethernet en IP fixe 172.20.0.xx (xx demandé au lancement)
     Masque 255.255.255.0 - Passerelle 172.20.0.1 - DNS 8.8.8.8 / 1.1.1.1
  2. Teste la connexion Internet (passerelle, DNS, web)
  3. Crée le point d'accès Wi-Fi MY-DFS-HOTSPOT
  4. Ouvre une page web locale (QR code + identifiants) dans le navigateur

  Utilisation : double-cliquer sur Lancer-DFS.bat
  Remettre la carte Ethernet en DHCP : Lancer-DFS.bat -Reset
  Réparer le partage Internet du point d'accès (sans toucher à l'IP) : Reparer-Partage.bat
#>

param([switch]$Reset, [switch]$Repair)

# ===================== PARAMÈTRES =====================
$Gateway     = '172.20.0.1'
$NetPrefix   = '172.20.0.'
$PrefixLen   = 24                      # = 255.255.255.0
$DnsServers  = @('8.8.8.8', '1.1.1.1')
$HotspotSsid = 'MY-DFS-HOTSPOT'
$HotspotPass = '123DFSIFIW'
$HotspotMaxPeers = 128                 # appareils max sur le point d'accès (Windows : 8 par défaut, 128 max)
$WebPort     = 8080
# ======================================================

# ---------- Élévation administrateur + Windows PowerShell 5.1 ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
           [Security.Principal.WindowsBuiltInRole]::Administrator)
$isExe = [string]::IsNullOrEmpty($PSCommandPath)   # vrai quand le script tourne compilé en .exe
if (-not $isAdmin -or $PSVersionTable.PSEdition -eq 'Core') {
    $extra = @()
    if ($Reset)  { $extra += '-Reset' }
    if ($Repair) { $extra += '-Repair' }
    if ($isExe) {
        $self = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($extra.Count) { Start-Process $self -ArgumentList ($extra -join ' ') -Verb RunAs }
        else              { Start-Process $self -Verb RunAs }
    } else {
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" " + ($extra -join ' ')
        Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    }
    exit
}

$Host.UI.RawUI.WindowTitle = 'DFS - AgriGeek Hotspot'
$ErrorActionPreference = 'Stop'

function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "    [!]  $m" -ForegroundColor Yellow }
function Write-Err($m)  { Write-Host "    [X]  $m" -ForegroundColor Red }

function Stop-WithPause($code) {
    Write-Host ''
    Read-Host 'Appuyez sur Entrée pour fermer'
    exit $code
}

Clear-Host
Write-Host '  ____  _____ ____  ' -ForegroundColor Blue
Write-Host ' |  _ \|  ___/ ___| ' -ForegroundColor Blue
Write-Host ' | | | | |_  \___ \ ' -ForegroundColor Blue
Write-Host ' | |_| |  _|  ___) |' -ForegroundColor Green
Write-Host ' |____/|_|   |____/   AgriGeek Hotspot' -ForegroundColor Green
Write-Host ''

# =====================================================================
# 1. CARTE ETHERNET
# =====================================================================
function Select-EthernetAdapter {
    # NdisPhysicalMedium 14 = 802.3 (Ethernet filaire)
    $all = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.NdisPhysicalMedium -eq 14 })
    if ($all.Count -eq 0) { throw 'Aucune carte Ethernet physique détectée sur cette machine.' }

    $up = @($all | Where-Object { $_.Status -eq 'Up' })
    if ($up.Count -eq 0) {
        Write-Warn 'Aucune carte Ethernet connectée : vérifiez que le câble réseau est branché.'
        $list = $all
    } else {
        $list = $up
    }
    if ($list.Count -eq 1) { return $list[0] }

    Write-Host '    Plusieurs cartes Ethernet trouvées :'
    for ($i = 0; $i -lt $list.Count; $i++) {
        Write-Host ('      [{0}] {1} - {2} ({3})' -f ($i + 1), $list[$i].Name, $list[$i].InterfaceDescription, $list[$i].Status)
    }
    do { $c = Read-Host '    Numéro de la carte à configurer' }
    until ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $list.Count)
    return $list[[int]$c - 1]
}

function Read-DeviceNumber {
    while ($true) {
        $v = Read-Host "`n    Numéro de cet appareil sur le réseau (2 à 254) -> 172.20.0.xx"
        if ($v -match '^\d{1,3}$' -and [int]$v -ge 2 -and [int]$v -le 254) { return [int]$v }
        Write-Warn 'Valeur invalide : entrez un nombre entre 2 et 254 (1 = passerelle).'
    }
}

function Clear-IPv4Config($idx) {
    Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    Get-NetRoute -InterfaceIndex $idx -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
}

function Set-StaticIPv4($adapter, $ip) {
    $idx = $adapter.ifIndex
    Set-NetIPInterface -InterfaceIndex $idx -AddressFamily IPv4 -Dhcp Disabled
    Clear-IPv4Config $idx
    New-NetIPAddress -InterfaceIndex $idx -IPAddress $ip -PrefixLength $PrefixLen -DefaultGateway $Gateway | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses $DnsServers

    # Attendre que Windows valide l'adresse (détection de conflit d'IP)
    for ($t = 0; $t -lt 24; $t++) {
        $a = Get-NetIPAddress -InterfaceIndex $idx -IPAddress $ip -ErrorAction SilentlyContinue
        if ($a.AddressState -eq 'Preferred') { return 'OK' }
        if ($a.AddressState -eq 'Duplicate') { return 'Duplicate' }
        Start-Sleep -Milliseconds 500
    }
    return 'Timeout'
}

# =====================================================================
# 2. TEST INTERNET
# =====================================================================
function Test-Internet {
    $r = [ordered]@{ Passerelle = $false; DNS = $false; Web = $false }
    for ($try = 1; $try -le 3; $try++) {
        $r.Passerelle = Test-Connection -ComputerName $Gateway -Count 2 -Quiet -ErrorAction SilentlyContinue
        try { Resolve-DnsName 'www.google.com' -Type A -DnsOnly -ErrorAction Stop | Out-Null; $r.DNS = $true } catch { $r.DNS = $false }
        try {
            $resp = Invoke-WebRequest 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 8
            $r.Web = ($resp.Content -match 'Microsoft Connect Test')
        } catch { $r.Web = $false }
        if ($r.Web) { break }
        if ($try -lt 3) { Write-Host "    Tentative $try échouée, nouvel essai dans 5 s..." -ForegroundColor DarkGray; Start-Sleep 5 }
    }
    return $r
}

# =====================================================================
# 3. POINT D'ACCÈS WI-FI (Point d'accès mobile Windows, API WinRT)
# =====================================================================
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
$null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
$null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringAccessPointConfiguration, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
$null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]

$script:AsTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
$script:AsTaskAction = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and -not $_.IsGenericMethod })[0]

function Await($op, [Type]$resultType) {
    $t = $script:AsTaskGeneric.MakeGenericMethod($resultType).Invoke($null, @($op))
    $t.Wait(-1) | Out-Null
    return $t.Result
}
function AwaitAction($action) {
    $t = $script:AsTaskAction.Invoke($null, @($action))
    $t.Wait(-1) | Out-Null
}

function Get-EthernetProfile($adapter) {
    $guid = $adapter.InterfaceGuid.Trim('{}').ToLower()
    for ($i = 0; $i -lt 15; $i++) {
        $p = [Windows.Networking.Connectivity.NetworkInformation]::GetConnectionProfiles() |
             Where-Object { $_.NetworkAdapter -and $_.NetworkAdapter.NetworkAdapterId.ToString().ToLower() -eq $guid } |
             Select-Object -First 1
        if (-not $p) { $p = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile() }
        if ($p) { return $p }
        Start-Sleep 1
    }
    throw 'Profil réseau Ethernet introuvable (Windows ne voit pas encore la connexion).'
}

# ---------- Partage de connexion Internet (ICS) ----------
# Services dont le partage de connexion Internet a besoin (ordre de démarrage)
$script:IcsServices = @(
    @{ Name = 'BFE';          Label = 'Moteur de filtrage de base';           Start = 'Automatic'; Critical = $true  },
    @{ Name = 'MpsSvc';       Label = 'Pare-feu Windows Defender';            Start = 'Automatic'; Critical = $true  },
    @{ Name = 'Netman';       Label = 'Connexions réseau';                    Start = 'Manual';    Critical = $true  },
    @{ Name = 'netprofm';     Label = 'Service Liste des réseaux';            Start = 'Manual';    Critical = $false },
    @{ Name = 'NlaSvc';       Label = 'Connaissance des emplacements réseau'; Start = 'Automatic'; Critical = $false },
    @{ Name = 'RasMan';       Label = "Gestionnaire des connexions d'accès distant"; Start = 'Manual'; Critical = $false },
    @{ Name = 'SharedAccess'; Label = 'Partage de connexion Internet (ICS)';  Start = 'Manual';    Critical = $true  }
)

function Initialize-SharingServices {
    $allOk = $true
    foreach ($def in $script:IcsServices) {
        $s = Get-Service $def.Name -ErrorAction SilentlyContinue
        if (-not $s) { if ($def.Critical) { Write-Err "Service « $($def.Label) » absent de Windows."; $allOk = $false }; continue }
        try {
            if ($s.StartType -eq 'Disabled') {
                Set-Service $def.Name -StartupType $def.Start -ErrorAction Stop
                Write-Warn "Service « $($def.Label) » réactivé (il était désactivé)."
            }
            if ((Get-Service $def.Name).Status -ne 'Running') {
                Start-Service $def.Name -ErrorAction Stop
                Write-Ok "Service « $($def.Label) » démarré."
            }
        } catch {
            if ($def.Critical) {
                Write-Err "Service « $($def.Label) » ($($def.Name)) impossible à démarrer : $($_.Exception.Message)"
                $allOk = $false
            } else {
                Write-Warn "Service « $($def.Label) » non démarré : $($_.Exception.Message)"
            }
        }
    }
    # Le service icssvc (point d'accès mobile) ne doit pas être désactivé
    $ic = Get-Service icssvc -ErrorAction SilentlyContinue
    if ($ic -and $ic.StartType -eq 'Disabled') {
        try { Set-Service icssvc -StartupType Manual -ErrorAction Stop; Write-Warn "Service « Point d'accès mobile » réactivé." } catch {}
    }

    # Partage bloqué par une stratégie de groupe (poste géré par une organisation) ?
    $pol = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections' -ErrorAction SilentlyContinue
    if ($pol -and $pol.PSObject.Properties['NC_ShowSharedAccessUI'] -and $pol.NC_ShowSharedAccessUI -eq 0) {
        Write-Err "Le partage de connexion Internet est interdit par une stratégie de groupe sur ce PC (NC_ShowSharedAccessUI = 0)."
        $allOk = $false
    }

    if (-not $allOk) {
        Write-Warn "Si le Pare-feu Windows Defender ne démarre pas, un antivirus (Kaspersky, ESET, Avast...) l'a sans doute remplacé : le partage Windows ne peut pas fonctionner sans lui."
    }
    return $allOk
}

function Get-HotspotAdapter {
    for ($i = 0; $i -lt 10; $i++) {
        $ipObj = Get-NetIPAddress -AddressFamily IPv4 -IPAddress '192.168.137.1' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($ipObj) { return Get-NetAdapter -InterfaceIndex $ipObj.InterfaceIndex }
        $a = Get-NetAdapter -ErrorAction SilentlyContinue |
             Where-Object { $_.InterfaceDescription -like '*Wi-Fi Direct*' -and $_.Status -eq 'Up' } |
             Select-Object -First 1
        if ($a) { return $a }
        Start-Sleep 1
    }
    return $null
}

# Partage public sur l'Ethernet, privé sur la carte du point d'accès ; retire tout autre partage
function Enable-IcsSharing($eth, $hs) {
    $mgr = New-Object -ComObject HNetCfg.HNetShare
    $pub = $null; $priv = $null
    foreach ($c in $mgr.EnumEveryConnection) {
        $props = $mgr.NetConnectionProps.Invoke($c)
        $cfg   = $mgr.INetSharingConfigurationForINetConnection.Invoke($c)
        if     ($props.Name -eq $eth.Name) { $pub  = $cfg }
        elseif ($props.Name -eq $hs.Name)  { $priv = $cfg }
        elseif ($cfg.SharingEnabled) {
            $cfg.DisableSharing()
            Write-Warn "Ancien partage retiré de « $($props.Name) »."
        }
    }
    if (-not $pub)  { throw "Connexion Ethernet « $($eth.Name) » introuvable dans le partage Windows." }
    if (-not $priv) { throw "Carte du point d'accès « $($hs.Name) » introuvable dans le partage Windows." }

    $ok = $pub.SharingEnabled -and $pub.SharingConnectionType -eq 0 -and
          $priv.SharingEnabled -and $priv.SharingConnectionType -eq 1
    if ($ok) { return 'OK' }

    $lastErr = $null
    for ($try = 1; $try -le 3; $try++) {
        try {
            if ($pub.SharingEnabled)  { $pub.DisableSharing() }
            if ($priv.SharingEnabled) { $priv.DisableSharing() }
            $pub.EnableSharing(0)    # 0 = connexion partagée (Internet)
            $priv.EnableSharing(1)   # 1 = réseau domestique (point d'accès)
            return 'Repaired'
        } catch {
            $lastErr = $_.Exception
            if ($try -lt 3) {
                # 0x80040201 : un service requis vient souvent de démarrer ou a planté -> on relance et on réessaie
                $null = Initialize-SharingServices
                Restart-Service SharedAccess -Force -ErrorAction SilentlyContinue
                Start-Sleep 3
            }
        }
    }
    if ($lastErr.HResult -eq -2147220991) {   # 0x80040201
        throw "Windows refuse d'activer le partage (0x80040201) : un service requis est arrêté ou bloqué (voir les messages au-dessus, souvent le Pare-feu Windows Defender)."
    }
    throw $lastErr
}

function Test-HotspotSharing($hs) {
    $ips = @(Get-NetIPAddress -InterfaceIndex $hs.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $_.IPAddress })
    if ($ips -contains '192.168.137.1') {
        Write-Ok "Carte du point d'accès « $($hs.Name) » : 192.168.137.1"
    } else {
        Write-Err "La carte du point d'accès n'a pas l'adresse 192.168.137.1 (actuelle : $($ips -join ', ')). Les appareils ne recevront pas d'adresse valide."
    }
    try {
        Resolve-DnsName 'www.google.com' -Server '192.168.137.1' -DnsOnly -QuickTimeout -ErrorAction Stop | Out-Null
        Write-Ok "Relais DNS du point d'accès opérationnel."
    } catch { Write-Warn "Le relais DNS du point d'accès (192.168.137.1) ne répond pas." }
}

function Repair-HotspotSharing($adapter) {
    Start-Sleep 3
    $hs = Get-HotspotAdapter
    if (-not $hs) { Write-Warn "Carte virtuelle du point d'accès introuvable : partage non vérifié."; return }
    try {
        $r = Enable-IcsSharing $adapter $hs
        if ($r -eq 'Repaired') { Write-Ok "Partage Internet réparé : $($adapter.Name) -> $($hs.Name)"; Start-Sleep 3 }
        else                   { Write-Ok "Partage Internet correct : $($adapter.Name) -> $($hs.Name)" }
    } catch { Write-Err "Partage Internet : $($_.Exception.Message)" }
    Test-HotspotSharing $hs
}

function Start-Hotspot($adapter) {
    $null = Initialize-SharingServices

    # Réglages du service Point d'accès mobile (icssvc) :
    #  - PeerlessTimeoutEnabled = 0 : ne s'éteint pas quand aucun appareil n'est connecté
    #  - WifiMaxPeers           : nombre maximum d'appareils (8 par défaut)
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\icssvc\Settings'
    $wanted = [ordered]@{ PeerlessTimeoutEnabled = 0; WifiMaxPeers = $HotspotMaxPeers }
    $changed = $false
    try {
        if (-not (Test-Path $key)) { New-Item $key -Force | Out-Null }
        foreach ($name in $wanted.Keys) {
            $cur = (Get-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue).$name
            if ($cur -ne $wanted[$name]) {
                New-ItemProperty -Path $key -Name $name -Value $wanted[$name] -PropertyType DWord -Force | Out-Null
                $changed = $true
            }
        }
        if ($changed) {
            # Le service doit redémarrer pour prendre en compte les nouvelles valeurs
            Restart-Service icssvc -Force -ErrorAction SilentlyContinue
            Start-Sleep 2
            Write-Ok "Point d'accès réglé pour $HotspotMaxPeers appareils maximum (veille désactivée)."
        } else {
            Write-Ok "Point d'accès déjà réglé pour $HotspotMaxPeers appareils maximum."
        }
    } catch { Write-Warn "Impossible de modifier les réglages du point d'accès : $($_.Exception.Message)" }

    $profile = Get-EthernetProfile $adapter
    $cap = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::GetTetheringCapabilityFromConnectionProfile($profile)
    if ($cap.ToString() -ne 'Enabled') {
        throw "Point d'accès impossible sur cette machine (état : $cap). Vérifiez que le Wi-Fi est activé et que la carte Wi-Fi le permet."
    }

    $tm = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($profile)

    if ($tm.TetheringOperationalState.ToString() -eq 'On') {
        Await ($tm.StopTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult]) | Out-Null
    }

    $cfg = $tm.GetCurrentAccessPointConfiguration()
    $cfg.Ssid       = $HotspotSsid
    $cfg.Passphrase = $HotspotPass
    AwaitAction ($tm.ConfigureAccessPointAsync($cfg))

    $res = Await ($tm.StartTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
    if ($res.Status.ToString() -ne 'Success') {
        throw "Échec du démarrage du point d'accès : $($res.Status) $($res.AdditionalErrorMessage)"
    }
    Repair-HotspotSharing $adapter
    return $tm
}

# =====================================================================
# PROGRAMME PRINCIPAL
# =====================================================================
try {
    Write-Step 'Recherche de la carte Ethernet'
    $adapter = Select-EthernetAdapter
    Write-Ok "$($adapter.Name) - $($adapter.InterfaceDescription)"
} catch { Write-Err $_.Exception.Message; Stop-WithPause 1 }

# ---- Mode -Reset : retour en DHCP ----
if ($Reset) {
    Write-Step 'Retour de la carte Ethernet en mode automatique (DHCP)'
    Clear-IPv4Config $adapter.ifIndex
    Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -Dhcp Enabled
    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses
    Write-Ok 'Configuration automatique rétablie.'
    Stop-WithPause 0
}

# ---- Mode -Repair : relance le point d'accès et répare le partage, sans toucher à l'IP ----
if ($Repair) {
    Write-Step "Relance du point d'accès et réparation du partage Internet"
    try {
        $null = Start-Hotspot $adapter
        Write-Ok "Point d'accès « $HotspotSsid » actif. Déconnectez puis reconnectez les téléphones."
    } catch { Write-Err $_.Exception.Message }
    Stop-WithPause 0
}

$connected = $false
while (-not $connected) {
    $n  = Read-DeviceNumber
    $ip = "$NetPrefix$n"

    Write-Step "Configuration de $($adapter.Name) : $ip / 255.255.255.0 - passerelle $Gateway"
    try { $state = Set-StaticIPv4 $adapter $ip }
    catch { Write-Err $_.Exception.Message; continue }

    if ($state -eq 'Duplicate') {
        Write-Err "L'adresse $ip est déjà utilisée par un autre appareil. Choisissez un autre numéro."
        continue
    }
    Write-Ok "IP $ip - DNS $($DnsServers -join ', ')"

    Write-Step 'Test de la connexion Internet'
    $t = Test-Internet
    foreach ($k in $t.Keys) {
        if ($t[$k]) { Write-Ok "$k joignable" } else { Write-Err "$k injoignable" }
    }

    if ($t.Web) {
        $connected = $true
    } else {
        if (-not $t.Passerelle) { Write-Warn 'La passerelle ne répond pas : vérifiez le câble ou le switch.' }
        elseif (-not $t.DNS)    { Write-Warn 'La passerelle répond mais pas le DNS : le réseau bloque peut-être 8.8.8.8 / 1.1.1.1.' }
        $ans = Read-Host "`n    [R] Réessayer avec un autre numéro   [Q] Quitter"
        if ($ans -match '^[qQ]') { Stop-WithPause 1 }
    }
}
Write-Ok 'Internet fonctionne.'

Write-Step "Création du point d'accès Wi-Fi « $HotspotSsid »"
try {
    $script:Tm = Start-Hotspot $adapter
    Write-Ok "Point d'accès actif - mot de passe : $HotspotPass"
    $max = [int]$script:Tm.MaxClientCount
    if ($max -lt $HotspotMaxPeers) {
        Write-Warn "Windows annonce $max appareils maximum : la carte Wi-Fi (ou son pilote) ne permet pas d'aller jusqu'à $HotspotMaxPeers."
    } else {
        Write-Ok "Capacité annoncée par Windows : $max appareils."
    }
} catch { Write-Err $_.Exception.Message; Stop-WithPause 1 }

# =====================================================================
# 4. SERVEUR WEB LOCAL + PAGE QR CODE
# =====================================================================
function Get-HotspotIp {
    $a = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
         Where-Object { $_.IPAddress -like '192.168.137.*' } | Select-Object -First 1
    if ($a) { return $a.IPAddress } else { return '192.168.137.1' }
}

function Get-HotspotStatus {
    $clients = @()
    try {
        foreach ($c in $script:Tm.GetTetheringClients()) {
            $names = @($c.HostNames | ForEach-Object { $_.DisplayName }) -join ', '
            $clients += [pscustomobject]@{ mac = $c.MacAddress; name = $names }
        }
    } catch {}
    return [ordered]@{
        state   = $script:Tm.TetheringOperationalState.ToString()
        count   = [int]$script:Tm.ClientCount
        max     = [int]$script:Tm.MaxClientCount
        clients = $clients
    }
}

$config = [ordered]@{
    ssid      = $HotspotSsid
    password  = $HotspotPass
    ethernet  = $ip
    gateway   = $Gateway
    dns       = ($DnsServers -join ' · ')
    hotspotIp = (Get-HotspotIp)
    adapter   = $adapter.Name
} | ConvertTo-Json -Compress

$html = @'
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AgriGeek Hotspot · DFS</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;700&family=Space+Mono:wght@400;700&display=swap" rel="stylesheet">
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
<style>
:root{
  --bg:#0b0f1e; --grid:rgba(120,140,220,.07); --card:#121831; --line:#252e55;
  --text:#eef1fb; --muted:#8a93b8; --navy:#232a63; --blue:#4a6bc4; --blue-hi:#7894e8;
  --green:#6cc070; --red:#e06c75;
  --mono:'Space Mono',ui-monospace,Consolas,monospace;
  --sans:'Space Grotesk','Segoe UI',system-ui,sans-serif;
}
*{box-sizing:border-box;margin:0;padding:0}
body{min-height:100vh;background:var(--bg);color:var(--text);font-family:var(--sans);overflow-x:hidden;
  background-image:linear-gradient(var(--grid) 1px,transparent 1px),linear-gradient(90deg,var(--grid) 1px,transparent 1px);
  background-size:72px 72px}
.deco{position:fixed;background:var(--green);z-index:0}
.d1{width:88px;height:88px;left:6%;top:11%}
.d2{width:54px;height:54px;left:36%;top:7%}
.d3{width:36px;height:100px;left:48%;top:18%}
.d4{width:48px;height:124px;right:36%;top:0}
.d5{width:66px;height:66px;left:13%;bottom:12%}
.d6{width:112px;height:38px;left:30%;bottom:6%}
.side{position:fixed;right:-14px;top:50%;transform:translateY(-50%);display:flex;flex-direction:column;gap:90px;z-index:0;opacity:.85}
.side span{font:700 150px/0.8 var(--mono);color:var(--blue)}
.wrap{position:relative;z-index:1;max-width:1280px;margin:0 auto;padding:40px 24px;min-height:100vh;
  display:grid;grid-template-columns:1.15fr .85fr;gap:64px;align-items:center}
.logo{display:flex;align-items:center;gap:6px}
.logo .b{display:grid;place-items:center;font:700 var(--s,30px)/1 var(--mono);color:#fff;width:var(--w,60px);height:var(--w,60px)}
.logo .b1{background:var(--navy);box-shadow:inset 0 0 0 1px #3a4390}
.logo .b2{background:var(--blue)}
.logo .b3{background:var(--green)}
.logo .lt{margin-left:12px;font:700 var(--ts,17px)/1.05 var(--sans);letter-spacing:.02em}
.logo.big{--w:108px;--s:56px;--ts:30px}
.top{position:absolute;top:28px;left:24px}
.eyebrow{font:400 15px var(--mono);letter-spacing:.42em;color:var(--blue-hi);text-transform:uppercase;margin-bottom:22px}
h1{font-size:clamp(40px,5.8vw,82px);font-weight:700;line-height:1.02;letter-spacing:-.025em;margin-bottom:38px}
h1 em{font-style:normal;color:var(--green)}
.lead{margin-top:34px;max-width:540px;font-size:21px;line-height:1.5;color:var(--muted)}
.chips{display:flex;flex-wrap:wrap;gap:10px;margin-top:28px}
.chip{font:400 12px var(--mono);letter-spacing:.08em;border:1px solid var(--line);background:rgba(18,24,49,.7);padding:8px 12px;color:var(--muted)}
.chip b{color:var(--text);font-weight:700}
.card{position:relative;background:var(--card);border:1px solid var(--line);padding:44px;box-shadow:0 30px 80px rgba(0,0,0,.45)}
.card::after{content:"";position:absolute;left:-7px;bottom:-7px;width:30px;height:80px;border-left:7px solid var(--green);border-bottom:7px solid var(--green);width:30px}
.card-h{display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:22px}
.card-h h2{font-size:30px;font-weight:700;letter-spacing:-.01em}
.card-h small{display:block;margin-top:8px;font:400 13px var(--mono);letter-spacing:.32em;color:var(--muted)}
.card-h svg{width:34px;height:34px;color:var(--blue-hi)}
.status{display:flex;align-items:center;gap:12px;padding:16px 20px;border-left:4px solid var(--green);background:rgba(108,192,112,.12);font-size:17px;margin-bottom:26px}
.status .dot{width:10px;height:10px;border-radius:50%;background:var(--green);box-shadow:0 0 0 0 rgba(108,192,112,.6);animation:pulse 1.8s infinite}
.status.off{border-color:var(--red);background:rgba(224,108,117,.13)}
.status.off .dot{background:var(--red);animation:none}
.status button{margin-left:auto}
@keyframes pulse{70%{box-shadow:0 0 0 10px rgba(108,192,112,0)}100%{box-shadow:0 0 0 0 rgba(108,192,112,0)}}
.qr{display:flex;justify-content:center;margin-bottom:26px}
.qr-box{background:#fff;padding:16px;line-height:0}
.qr-box img,.qr-box canvas{display:block}
.qr-fallback{font:400 13px var(--mono);color:#333;width:220px;line-height:1.5;text-align:center;padding:60px 10px}
.field{margin-bottom:14px}
.field label{display:block;font:400 11px var(--mono);letter-spacing:.3em;color:var(--muted);margin-bottom:6px}
.row{display:flex;align-items:center;border:1px solid var(--line);background:#0e1328}
.row .v{flex:1;padding:14px 16px;font:700 18px var(--mono);letter-spacing:.06em;overflow:hidden;text-overflow:ellipsis}
.row.focus{border-color:var(--blue-hi);box-shadow:0 0 0 1px var(--blue-hi)}
.ib{border:0;border-left:1px solid var(--line);background:transparent;color:var(--muted);width:52px;align-self:stretch;cursor:pointer;display:grid;place-items:center}
.ib:hover{color:var(--text);background:#161d3c}
.ib svg{width:18px;height:18px}
.btn{border:0;background:var(--blue);color:#fff;font:700 13px var(--mono);letter-spacing:.3em;padding:10px 16px;cursor:pointer}
.btn:hover{background:#5578d4}
hr{border:0;border-top:1px solid var(--line);margin:24px 0 18px}
.clients-h{display:flex;justify-content:space-between;font-size:16px}
.clients-h span{font:700 15px var(--mono);color:var(--green)}
ul{list-style:none;margin-top:12px;max-height:140px;overflow:auto}
li{display:flex;justify-content:space-between;gap:12px;padding:8px 0;border-bottom:1px dashed var(--line);font-size:14px}
li code{font:400 12px var(--mono);color:var(--muted)}
.empty{color:var(--muted);font-size:14px;margin-top:10px}
.toast{position:fixed;bottom:24px;left:50%;transform:translateX(-50%) translateY(80px);background:var(--green);color:#0b0f1e;font:700 13px var(--mono);letter-spacing:.15em;padding:12px 20px;transition:transform .25s;z-index:10}
.toast.show{transform:translateX(-50%) translateY(0)}
@media (max-width:980px){
  .wrap{grid-template-columns:1fr;gap:40px;padding-top:110px}
  .side,.d3,.d4{display:none}
  .logo.big{--w:72px;--s:38px;--ts:21px}
  .card{padding:28px}
}
</style>
</head>
<body>
<div class="deco d1"></div><div class="deco d2"></div><div class="deco d3"></div>
<div class="deco d4"></div><div class="deco d5"></div><div class="deco d6"></div>
<div class="side"><span>D</span><span>F</span><span>S</span></div>

<div class="top">
  <div class="logo"><span class="b b1">D</span><span class="b b2">F</span><span class="b b3">S</span>
  <span class="lt">DIGITAL<br>FARMING<br>SCHOOL</span></div>
</div>

<main class="wrap">
  <section>
    <p class="eyebrow">Point d'accès Wi-Fi</p>
    <h1>Welcome to The <em>AgriGeek</em> Hotspot Windows.</h1>
    <div class="logo big"><span class="b b1">D</span><span class="b b2">F</span><span class="b b3">S</span>
      <span class="lt">DIGITAL<br>FARMING<br>SCHOOL</span></div>
    <p class="lead">Scannez le QR code avec votre téléphone pour rejoindre le réseau Wi-Fi de la Digital Farming School.</p>
    <div class="chips">
      <span class="chip">ETHERNET <b id="c-eth"></b></span>
      <span class="chip">PASSERELLE <b id="c-gw"></b></span>
      <span class="chip">DNS <b id="c-dns"></b></span>
      <span class="chip">HOTSPOT <b id="c-hs"></b></span>
    </div>
  </section>

  <section class="card">
    <div class="card-h">
      <div><h2>CONNEXION WI-FI</h2><small>SCANNER · REJOINDRE</small></div>
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M2 8.8a15 15 0 0 1 20 0"/><path d="M5 12.5a10 10 0 0 1 14 0"/><path d="M8.5 16a5 5 0 0 1 7 0"/><circle cx="12" cy="19.5" r="1" fill="currentColor"/></svg>
    </div>

    <div class="status" id="status"><span class="dot"></span><span id="status-t">Point d'accès actif</span></div>

    <div class="qr"><div class="qr-box" id="qr"></div></div>

    <div class="field">
      <label>RÉSEAU (SSID)</label>
      <div class="row focus"><span class="v" id="ssid"></span>
        <button class="ib" data-copy="ssid" title="Copier"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="12" height="12" rx="1"/><path d="M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1"/></svg></button>
      </div>
    </div>
    <div class="field">
      <label>MOT DE PASSE</label>
      <div class="row"><span class="v" id="pass"></span>
        <button class="ib" id="eye" title="Afficher / masquer"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12z"/><circle cx="12" cy="12" r="3"/></svg></button>
        <button class="ib" data-copy="password" title="Copier"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="12" height="12" rx="1"/><path d="M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1"/></svg></button>
      </div>
    </div>
    <div class="field">
      <label>SÉCURITÉ</label>
      <div class="row"><span class="v">WPA2 · PERSONNEL</span></div>
    </div>

    <hr>
    <div class="clients-h">Appareils connectés <span id="count">0 / 8</span></div>
    <ul id="clients"></ul>
    <p class="empty" id="empty">Aucun appareil pour le moment.</p>
  </section>
</main>
<div class="toast" id="toast">COPIÉ</div>

<script>
const C = {{CONFIG}};
const $ = id => document.getElementById(id);
$('ssid').textContent = C.ssid;
$('c-eth').textContent = C.ethernet; $('c-gw').textContent = C.gateway;
$('c-dns').textContent = C.dns; $('c-hs').textContent = C.hotspotIp;

let shown = false;
const mask = () => $('pass').textContent = shown ? C.password : '•'.repeat(C.password.length);
mask();
$('eye').onclick = () => { shown = !shown; mask(); };

const toast = msg => { const t = $('toast'); t.textContent = msg; t.classList.add('show'); setTimeout(() => t.classList.remove('show'), 1400); };
document.querySelectorAll('[data-copy]').forEach(b => b.onclick = async () => {
  try { await navigator.clipboard.writeText(C[b.dataset.copy]); toast('COPIÉ'); } catch { toast('COPIE IMPOSSIBLE'); }
});

const esc = s => s.replace(/([\\;,:"])/g, '\\$1');
const wifi = `WIFI:T:WPA;S:${esc(C.ssid)};P:${esc(C.password)};;`;
if (window.QRCode) {
  new QRCode($('qr'), { text: wifi, width: 220, height: 220, colorDark: '#0b0f1e', colorLight: '#ffffff', correctLevel: QRCode.CorrectLevel.M });
} else {
  $('qr').innerHTML = '<div class="qr-fallback">QR code indisponible.<br>Saisissez le nom du réseau et le mot de passe ci-dessous.</div>';
}

const escHtml = s => String(s ?? '').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
async function refresh() {
  try {
    const s = await (await fetch('/api/status', { cache: 'no-store' })).json();
    const on = s.state === 'On';
    $('status').className = 'status' + (on ? '' : ' off');
    $('status-t').innerHTML = on ? "Point d'accès actif" : "Point d'accès arrêté";
    if (!on && !$('restart')) {
      const b = document.createElement('button'); b.id = 'restart'; b.className = 'btn'; b.textContent = 'RELANCER';
      b.onclick = async () => { b.disabled = true; b.textContent = '...'; await fetch('/api/start', { method: 'POST' }); b.remove(); refresh(); };
      $('status').appendChild(b);
    }
    if (on && $('restart')) $('restart').remove();
    $('count').textContent = `${s.count} / ${s.max}`;
    const list = s.clients || [];
    $('clients').innerHTML = list.map(c => `<li><span>${escHtml(c.name || 'Appareil')}</span><code>${escHtml(c.mac)}</code></li>`).join('');
    $('empty').style.display = list.length ? 'none' : 'block';
  } catch {
    $('status').className = 'status off';
    $('status-t').textContent = 'Serveur local arrêté';
  }
}
refresh(); setInterval(refresh, 4000);
</script>
</body>
</html>
'@
$html = $html.Replace('{{CONFIG}}', $config)

# ---- Démarrage du serveur (cherche un port libre à partir de 8080) ----
$listener = $null
for ($p = $WebPort; $p -lt $WebPort + 20; $p++) {
    try {
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("http://localhost:$p/")
        $listener.Start()
        $WebPort = $p
        break
    } catch { $listener = $null }
}
if (-not $listener) { Write-Err 'Aucun port libre pour le serveur web.'; Stop-WithPause 1 }

$url = "http://localhost:$WebPort/"
Write-Step "Page du point d'accès : $url"
Start-Process $url
Write-Host "`n    Laissez cette fenêtre ouverte. Ctrl+C pour arrêter le serveur" -ForegroundColor DarkGray
Write-Host "    (le point d'accès Wi-Fi reste actif après la fermeture)." -ForegroundColor DarkGray

function Send-Response($ctx, [string]$body, [string]$type, [int]$code = 200) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
    $ctx.Response.StatusCode = $code
    $ctx.Response.ContentType = $type
    $ctx.Response.Headers.Add('Cache-Control', 'no-store')
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.OutputStream.Close()
}

try {
    while ($listener.IsListening) {
        $task = $listener.GetContextAsync()
        while (-not $task.AsyncWaitHandle.WaitOne(300)) { }   # permet Ctrl+C
        $ctx = $task.GetAwaiter().GetResult()
        try {
            switch ($ctx.Request.Url.AbsolutePath) {
                '/'           { Send-Response $ctx $html 'text/html; charset=utf-8' }
                '/api/status' { Send-Response $ctx ((Get-HotspotStatus) | ConvertTo-Json -Compress -Depth 4) 'application/json; charset=utf-8' }
                '/api/start'  {
                    try { $script:Tm = Start-Hotspot $adapter; Write-Ok "Point d'accès relancé." } catch { Write-Err $_.Exception.Message }
                    Send-Response $ctx '{"ok":true}' 'application/json; charset=utf-8'
                }
                default       { Send-Response $ctx 'Not found' 'text/plain; charset=utf-8' 404 }
            }
        } catch { Write-Warn "Requête web : $($_.Exception.Message)" }
    }
} finally {
    if ($listener) { $listener.Stop(); $listener.Close() }
    Write-Host "`n    Serveur arrêté. Le point d'accès « $HotspotSsid » reste actif." -ForegroundColor Yellow
}
