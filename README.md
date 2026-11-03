# AgriGeek Hotspot

> Passerelle Internet Wi-Fi clé en main pour la **Digital Farming School**.
> Configure l'Ethernet, crée un point d'accès Wi-Fi et affiche une page locale avec QR code.

![AgriGeek Hotspot](assets/agrigeek.png)

---

## Sommaire

- [Fonctionnalités](#fonctionnalités)
- [Prérequis](#prérequis)
- [Démarrage rapide](#démarrage-rapide)
- [Comment ça marche](#comment-ça-marche)
- [Structure du projet](#structure-du-projet)
- [Configuration](#configuration)
- [Modes de lancement](#modes-de-lancement)
- [Page web locale](#page-web-locale)
- [Compiler l'application (.exe)](#compiler-lapplication-exe)
- [Dépannage](#dépannage)
- [Licence](#licence)

---

## Fonctionnalités

- **IP fixe sur Ethernet** : `<préfixe>.xx` / `255.255.255.0`, passerelle `<passerelle>`, DNS `8.8.8.8` et `1.1.1.1`.
- **Test de connexion** automatique : passerelle, résolution DNS et accès web, avec nouvel essai si besoin.
- **Point d'accès Wi-Fi Windows** : SSID configurable, WPA2, jusqu'à **128 appareils** (veille désactivée).
- **Partage de connexion Internet (ICS)** configuré et réparé automatiquement (services Windows, pare-feu, redémarrage du partage).
- **Page web locale** (`http://localhost:8080`) : QR code Wi-Fi, identifiants, état du hotspot, appareils connectés et bouton de relance.
- **Application autonome** `AgriGeek-Hotspot.exe` avec icône, plus des raccourcis « AgriGeek Hotspot » et « Réparer le partage Internet ».

## Prérequis

| Élément | Détail |
|---|---|
| Système | Windows 10 ou 11 |
| PowerShell | Windows PowerShell 5.1 |
| Matériel | Une carte Ethernet **et** une carte Wi-Fi compatible point d'accès |
| Droits | Administrateur (élévation automatique) |
| Réseau | Câble Ethernet relié à la passerelle définie dans `$Gateway` |
| Compilation | Connexion Internet au premier lancement (installation du module `ps2exe`) |

## Démarrage rapide

1. Téléchargez la dernière version depuis la page [Releases](../../releases).
2. Décompressez l'archive dans un dossier de votre choix.
3. Double-cliquez sur **`AgriGeek Hotspot.exe`** (ou `Lancer-DFS.bat`).
4. Acceptez l'invite d'élévation administrateur.
5. Saisissez le **numéro de l'appareil** sur le réseau (2 à 254) → l'adresse devient `<préfixe>.xx`.
6. Attendez la validation de la connexion Internet et le démarrage du point d'accès.
7. La page locale s'ouvre : scannez le **QR code** avec un téléphone pour rejoindre le Wi-Fi.

> Le point d'accès reste actif après la fermeture de la fenêtre. Utilisez `Reparer-Partage.bat` pour le relancer sans changer l'IP.

## Comment ça marche

```text
Internet
   │
   ▼
Passerelle du réseau
   │
   ▼
PC Windows ── Ethernet <préfixe>.xx (IP fixe)
   │
   ├── Partage de connexion Internet (ICS)
   │
   ▼
Point d'accès Wi-Fi « <SSID> » ── 192.168.137.1
   │
   ├── Téléphones / tablettes / PC
   └── Page locale http://localhost:8080 (QR code + état)
```

Le script utilise l'API WinRT `NetworkOperatorTetheringManager` pour piloter le point d'accès mobile de Windows, et l'interface COM `HNetCfg.HNetShare` pour configurer le partage de connexion.

## Structure du projet

```text
DFS_AgriGeek_Hotspot/
├── assets/
│   ├── agrigeek.ico          # Icône de l'application
│   └── agrigeek.png          # Logo (README / page)
├── src/
│   └── Configurer-DFS.ps1    # Script principal (tout le système)
├── build/
│   ├── Construire-EXE.ps1    # Compilation ps2exe + création des raccourcis
│   └── Construire-EXE.bat    # Lanceur de compilation
├── Lancer-DFS.bat            # Lancement normal
├── Reparer-Partage.bat       # Réparation du partage Internet
├── README.md
├── CHANGELOG.md
├── LICENSE
└── .gitignore
```

Les binaires (`AgriGeek-Hotspot.exe`, archives) sont exclus de Git et publiés dans les **[Releases](../../releases)**.

## Configuration

Les paramètres se trouvent en haut de [`src/Configurer-DFS.ps1`](src/Configurer-DFS.ps1) :

| Variable | Valeur | Description |
|---|---|---|
| `$Gateway` | `<passerelle>` | Passerelle du réseau Ethernet |
| `$NetPrefix` | `<préfixe>.` | Préfixe de l'adresse IP fixe |
| `$PrefixLen` | `24` | Masque de sous-réseau (`255.255.255.0`) |
| `$DnsServers` | `8.8.8.8`, `1.1.1.1` | Serveurs DNS |
| `$HotspotSsid` | `<SSID>` | Nom du réseau Wi-Fi |
| `$HotspotPass` | *(à définir)* | Mot de passe Wi-Fi (WPA2) |
| `$HotspotMaxPeers` | `128` | Nombre maximum d'appareils |
| `$WebPort` | `8080` | Port de la page locale (ports suivants testés si occupé) |

> ⚠️ Définissez vos propres SSID, mot de passe et adressage dans le script (ne les publiez pas), puis recompilez l'exécutable.

## Modes de lancement

| Commande | Effet |
|---|---|
| `Lancer-DFS.bat` | Configuration complète (IP fixe, test Internet, hotspot, page web) |
| `Lancer-DFS.bat -Reset` | Remet la carte Ethernet en DHCP et réinitialise les DNS |
| `Reparer-Partage.bat` | Relance le hotspot et répare le partage ICS **sans** toucher à l'IP |

Les mêmes modes existent dans l'exécutable : `AgriGeek-Hotspot.exe -Reset` et `AgriGeek-Hotspot.exe -Repair`.

## Page web locale

Une fois le hotspot actif, ouvrez **http://localhost:8080** (ou le port affiché dans la console) :

- QR code Wi-Fi (format `WIFI:T:WPA;S:...;P:...;;`)
- SSID, mot de passe (affichage/masquage) et boutons de copie
- État du point d'accès et bouton **RELANCER**
- Nombre et liste des appareils connectés (actualisation toutes les 4 s)

La page fonctionne uniquement en local, sur la machine qui héberge le hotspot.

## Compiler l'application (.exe)

```bat
build\Construire-EXE.bat
```

Le script :

1. installe le module PowerShell [`ps2exe`](https://github.com/MScholtes/PS2EXE) pour l'utilisateur courant (première fois) ;
2. compile `src/Configurer-DFS.ps1` en `AgriGeek-Hotspot.exe` (icône, métadonnées, élévation admin) ;
3. crée les raccourcis « AgriGeek Hotspot » et « Réparer le partage Internet » dans le dossier du projet et sur le Bureau.

Version actuelle de l'exécutable : **1.0.0.0**.

## Dépannage

| Problème | Piste |
|---|---|
| « Aucune carte Ethernet physique détectée » | Vérifiez le pilote et que la carte n'est pas désactivée. |
| La passerelle ne répond pas | Vérifiez le câble, le switch et la valeur de `$Gateway`. |
| DNS injoignable | Le réseau bloque peut-être `8.8.8.8` / `1.1.1.1` ; changez `$DnsServers`. |
| Partage impossible (`0x80040201`) | Le Pare-feu Windows Defender est souvent remplacé par un antivirus tiers : le partage ICS ne peut pas fonctionner sans lui. |
| Point d'accès impossible | Le Wi-Fi doit être activé et la carte/pilote doit supporter le point d'accès. |
| `NC_ShowSharedAccessUI = 0` | Le partage est bloqué par une stratégie de groupe (poste géré par une organisation). |
| Moins de 128 appareils | Limite imposée par la carte Wi-Fi ou son pilote. |
| QR code absent | La librairie QR est chargée depuis un CDN ; sans Internet, saisissez le SSID et le mot de passe manuellement. |

En cas d'échec, la console affiche un message détaillé (`[!]` avertissement, `[X]` erreur) avant de se fermer.

## Licence

Distribué sous licence **MIT** — voir [LICENSE](LICENSE).

© Digital Farming School
