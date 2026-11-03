# Changelog

Toutes les modifications notables de ce projet sont documentées dans ce fichier.
Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le projet adhère au [Semantic Versioning](https://semver.org/lang/fr/).

## [1.0.0] - 2026-11-03

### Ajouté

- Configuration automatique de la carte Ethernet en IP fixe `172.20.0.xx` (passerelle `172.20.0.1`).
- Test de connexion Internet (passerelle, DNS, accès web) avec nouvelle tentative.
- Création du point d'accès Wi-Fi `MY-DFS-HOTSPOT` (WPA2) via l'API Windows `NetworkOperatorTetheringManager`.
- Réglage du point d'accès à 128 appareils maximum et désactivation de la veille.
- Configuration et réparation automatiques du partage de connexion Internet (ICS).
- Page web locale avec QR code Wi-Fi, identifiants, état du hotspot et liste des appareils connectés.
- Modes `-Reset` (retour en DHCP) et `-Repair` (réparation du partage sans toucher à l'IP).
- Application `AgriGeek-Hotspot.exe` (ps2exe), icône personnalisée et raccourcis Bureau.
- Documentation (`README.md`), licence MIT et structure de projet GitHub.
