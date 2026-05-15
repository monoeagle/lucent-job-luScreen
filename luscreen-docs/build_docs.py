#!/usr/bin/env python3
"""
build_docs.py – LucentScreen Dokumentation generieren

Verwendet Zensical (MkDocs Material Wrapper).

Verwendung:
  python3 build_docs.py              # HTML bauen
  python3 build_docs.py --serve      # Live-Server
  python3 build_docs.py --serve --port 8046
  python3 build_docs.py --check      # Nur prüfen
  python3 build_docs.py --ci         # CI-Modus (strict)
"""

import subprocess
import sys
import argparse
import shutil
from pathlib import Path

BASE_DIR    = Path(__file__).resolve().parent
DOCS_DIR    = BASE_DIR / "docs"
SITE_DIR    = BASE_DIR / "site"
CONFIG_FILE = BASE_DIR / "zensical.toml"


def run(cmd, cwd=BASE_DIR):
    print(f"  $ {' '.join(str(c) for c in cmd)}")
    try:
        subprocess.run(cmd, cwd=cwd, check=True)
    except subprocess.CalledProcessError as e:
        print(f"\n❌ Fehler (exit {e.returncode})")
        sys.exit(e.returncode)


def check_zensical(auto_install=False):
    # Bewusst via `python -m zensical` statt bare `zensical`-Command — letzterer
    # bräuchte zensical.exe in PATH, was nur nach venv-Activate der Fall ist.
    # `sys.executable -m zensical` funktioniert auch wenn der Aufrufer den
    # venv-Python direkt aufruft ohne Activate.
    try:
        subprocess.run([sys.executable, "-m", "zensical", "--version"],
                       capture_output=True, check=True)
    except (FileNotFoundError, subprocess.CalledProcessError):
        print("❌ Zensical nicht gefunden.")
        if auto_install:
            print("📦 Installiere Zensical …")
            run([sys.executable, "-m", "pip", "install", "zensical"])
        else:
            print("Installieren mit:  pip install zensical")
            sys.exit(1)


def check_structure(strict=False):
    print("\n🔍 Prüfe Dokumentations-Struktur …")
    errors = 0

    if not DOCS_DIR.is_dir():
        print("  ❌ docs/ Verzeichnis fehlt!")
        errors += 1

    if not CONFIG_FILE.exists():
        print("  ❌ zensical.toml fehlt!")
        errors += 1

    md_files = list(DOCS_DIR.rglob("*.md")) if DOCS_DIR.exists() else []
    print(f"  📄 {len(md_files)} Markdown-Dateien gefunden")

    if not any(f.name == "index.md" for f in md_files):
        print("  ⚠ Kein index.md gefunden")
        if strict:
            errors += 1

    if errors > 0:
        print(f"\n❌ {errors} Fehler gefunden")
        if strict:
            sys.exit(1)
    else:
        print("  ✅ Struktur OK")


def build():
    print("\n🔨 Baue Dokumentation mit Zensical …")
    if SITE_DIR.exists():
        shutil.rmtree(SITE_DIR)
    run([sys.executable, "-m", "zensical", "build", "--clean"])
    index = SITE_DIR / "index.html"
    if index.exists():
        print(f"\n✅ Fertig! Ausgabe: {SITE_DIR}")
        print(f"   Öffnen: file://{index}")
    else:
        print("❌ Build fehlgeschlagen")
        sys.exit(1)


def serve(port: int = 8000):
    print(f"\n🌐 Starte Live-Server auf Port {port} …")
    print(f"   Öffnen: http://127.0.0.1:{port}")
    print("   Beenden: Ctrl+C\n")
    try:
        subprocess.run(
            [sys.executable, "-m", "zensical", "serve",
             "--dev-addr", f"127.0.0.1:{port}"],
            cwd=BASE_DIR
        )
    except KeyboardInterrupt:
        print("\n👋 Server beendet.")


def main():
    parser = argparse.ArgumentParser(description="CodeSigning Commander Docs Builder")
    parser.add_argument("--serve",   action="store_true", help="Live-Server starten")
    parser.add_argument("--port",    type=int, default=8000, help="Port für Live-Server")
    parser.add_argument("--check",   action="store_true", help="Nur Struktur prüfen")
    parser.add_argument("--ci",      action="store_true", help="CI-Modus (strict)")
    parser.add_argument("--install", action="store_true", help="Zensical automatisch installieren")
    args = parser.parse_args()

    check_zensical(auto_install=args.install)
    strict = args.ci

    if args.check:
        check_structure(strict=strict)
    elif args.serve:
        check_structure(strict=strict)
        serve(port=args.port)
    else:
        check_structure(strict=strict)
        build()


if __name__ == "__main__":
    main()
