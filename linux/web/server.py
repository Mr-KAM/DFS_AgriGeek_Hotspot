#!/usr/bin/env python3
"""
server.py - Digital Farming School - AgriGeek Hotspot (Linux)

Page web locale du point d'accès : QR code Wi-Fi, identifiants, état du hotspot
et appareils connectés. Équivalent du serveur HttpListener de Configurer-DFS.ps1.

Lancé par agrigeek-hotspot.sh :
    server.py --config '<json>' [--port 8080] [--hotspot-con DFS-Hotspot] [--wifi-dev wlo1] [--open]

Routes :
    GET  /            page HTML (index.html, {{CONFIG}} remplacé par la configuration)
    GET  /api/status  {"state": "On"|"Off", "count": n, "max": null, "clients": [{"mac", "name"}]}
    POST /api/start   relance le point d'accès (nmcli connection up)
"""

import argparse
import json
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent


def run(cmd, timeout=10):
    """Lance une commande, renvoie sa sortie standard ('' en cas d'échec)."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout if r.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def lease_names(wifi_dev):
    """MAC -> nom d'hôte, d'après le fichier de baux du dnsmasq lancé par NetworkManager."""
    names = {}
    path = Path(f"/var/lib/NetworkManager/dnsmasq-{wifi_dev}.leases")
    try:
        for line in path.read_text().splitlines():
            # <expiration> <mac> <ip> <nom|*> <client-id>
            parts = line.split()
            if len(parts) >= 4 and parts[3] != "*":
                names[parts[1].lower()] = parts[3]
    except OSError:
        pass
    return names


def hotspot_status(con, wifi_dev):
    state = run(["nmcli", "-g", "GENERAL.STATE", "connection", "show", con]).strip()
    on = state == "activated"
    clients = []
    if on:
        names = lease_names(wifi_dev)
        for line in run(["iw", "dev", wifi_dev, "station", "dump"]).splitlines():
            if line.startswith("Station "):
                mac = line.split()[1].lower()
                clients.append({"mac": mac, "name": names.get(mac, "")})
    return {"state": "On" if on else "Off", "count": len(clients), "max": None, "clients": clients}


def make_handler(html, con, wifi_dev):
    class Handler(BaseHTTPRequestHandler):
        def send(self, body, ctype, code=200):
            data = body.encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            path = self.path.split("?", 1)[0]
            if path == "/":
                self.send(html, "text/html; charset=utf-8")
            elif path == "/api/status":
                self.send(json.dumps(hotspot_status(con, wifi_dev)), "application/json; charset=utf-8")
            else:
                self.send("Not found", "text/plain; charset=utf-8", 404)

        def do_POST(self):
            if self.path.split("?", 1)[0] == "/api/start":
                ok = run(["nmcli", "connection", "up", con], timeout=60) != ""
                print(f"    [{'OK' if ok else 'X'}] Relance du point d'accès depuis la page web.", flush=True)
                self.send(json.dumps({"ok": ok}), "application/json; charset=utf-8")
            else:
                self.send("Not found", "text/plain; charset=utf-8", 404)

        def log_message(self, *args):  # pas de journal HTTP dans la console
            pass

    return Handler


def main():
    ap = argparse.ArgumentParser(description="Page locale AgriGeek Hotspot")
    ap.add_argument("--config", required=True, help="configuration JSON injectée dans la page")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--hotspot-con", default="DFS-Hotspot")
    ap.add_argument("--wifi-dev", default="wlo1")
    ap.add_argument("--open", action="store_true", help="ouvrir la page dans le navigateur")
    args = ap.parse_args()

    config = json.loads(args.config)
    html = (HERE / "index.html").read_text(encoding="utf-8")
    html = html.replace("{{CONFIG}}", json.dumps(config, ensure_ascii=False))
    handler = make_handler(html, args.hotspot_con, args.wifi_dev)

    server = None
    for port in range(args.port, args.port + 20):  # cherche un port libre à partir de 8080
        try:
            server = ThreadingHTTPServer(("127.0.0.1", port), handler)
            break
        except OSError:
            continue
    if server is None:
        print("    [X]  Aucun port libre pour le serveur web.", file=sys.stderr)
        sys.exit(1)

    url = f"http://localhost:{port}/"
    print(f"\n==> Page du point d'accès : {url}", flush=True)
    if args.open:
        subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    print("\n    Laissez cette fenêtre ouverte. Ctrl+C pour arrêter le serveur", flush=True)
    print("    (le point d'accès Wi-Fi reste actif après la fermeture).", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        print(f"\n    Serveur arrêté. Le point d'accès « {config.get('ssid', '')} » reste actif.", flush=True)


if __name__ == "__main__":
    main()
