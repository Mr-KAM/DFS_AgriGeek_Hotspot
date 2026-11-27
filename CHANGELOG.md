# Changelog

Toutes les modifications notables de ce projet sont documentées dans ce fichier.
Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le projet adhère au [Semantic Versioning](https://semver.org/lang/fr/).

## [1.1.0] - 2026-11-27

### Ajouté

- Version Linux (`linux/`) pour Manjaro / Arch avec NetworkManager (testée sous i3) :
  - `agrigeek-hotspot.sh` : IP fixe Ethernet (profil `DFS-Ethernet`), test Internet forcé sur l'Ethernet,
    point d'accès `DFS-Hotspot` en mode partagé NetworkManager sur `192.168.137.1`, modes `--repair`, `--reset`, `--stop`, `--page`.
  - Choix automatique d'un numéro libre (`--auto`) avec détection de conflit d'adresse (ACD NetworkManager).
  - Vérification du lien Ethernet : détection des coupures, désactivation de l'EEE puis limitation à 100 Mb/s.
  - Ouverture du pare-feu (ufw, ou chaîne `DOCKER-USER` si Docker seul) pour le DHCP, le DNS et le routage du point d'accès.
  - `web/server.py` : même page locale (QR code, état, appareils) servie par Python (bibliothèque standard).
  - `install.sh` : commande `agrigeek-hotspot` et lanceurs `.desktop` (i3-dmenu-desktop, rofi).

## [1.0.0] - 2026-11-03

### Ajouté

- Configuration automatique de la carte Ethernet en IP fixe `<préfixe>.xx` (passerelle `<passerelle>`).
- Test de connexion Internet (passerelle, DNS, accès web) avec nouvelle tentative.
- Création du point d'accès Wi-Fi (WPA2) via l'API Windows `NetworkOperatorTetheringManager`.
- Réglage du point d'accès à 128 appareils maximum et désactivation de la veille.
- Configuration et réparation automatiques du partage de connexion Internet (ICS).
- Page web locale avec QR code Wi-Fi, identifiants, état du hotspot et liste des appareils connectés.
- Modes `-Reset` (retour en DHCP) et `-Repair` (réparation du partage sans toucher à l'IP).
- Application `AgriGeek-Hotspot.exe` (ps2exe), icône personnalisée et raccourcis Bureau.
- Documentation (`README.md`), licence MIT et structure de projet GitHub.
