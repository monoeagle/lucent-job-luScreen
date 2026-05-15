#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# run_csc_docs.sh — LucentScreen Dokumentation
#
# Eigenes .venv-docs, unabhängig von anderen venvs.
# Wird vom Hub als Kindprozess gestartet oder manuell ausgeführt.
# ══════════════════════════════════════════════════════════════════════════════
# Bewusst KEIN `set -e`: wir wollen, dass Fehler in einer Kommando-Funktion
# nur zum Menü zurückkehren, nicht die ganze Shell schließen.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="LucentScreen-Docs"
VENV_DIR="$SCRIPT_DIR/.venv-docs"
PYTHON=""   # wird von _detect_python gesetzt, nach venv-Activate auf venv-Python
PYTHON_VERSION=""
# Zensical ≥ 0.0.34 benötigt Python ≥ 3.10. Ältere Python-Versionen ziehen
# automatisch den 0.0.2-Platzhalter aus PyPI, was schwer zu debuggen ist.
PYTHON_MIN_MAJOR=3
PYTHON_MIN_MINOR=10
PORT=8000

# ── Farben ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

ok()     { echo -e "  ${GREEN}✓${NC} $1"; }
warn()   { echo -e "  ${YELLOW}⚠${NC}  $1"; }
fail()   { echo -e "  ${RED}✗${NC} $1"; }
info()   { echo -e "  ${CYAN}→${NC} $1"; }
header() { echo -e "\n${BOLD}══════════════════════════════════════════${NC}"; \
           echo -e "${BOLD}  $1${NC}"; \
           echo -e "${BOLD}══════════════════════════════════════════${NC}\n"; }

# ── Flags parsen (für Direktaufruf mit Argumenten) ────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --port=*) PORT="${arg#*=}" ;;
  esac
done

# ── Umgebung prüfen und vorbereiten ───────────────────────────────────────────

# Version-Vergleich: gibt 0 zurück wenn $1 >= min-version
_python_meets_min() {
    local ver="$1"
    local major="${ver%%.*}"
    local minor="${ver##*.}"
    if [[ $major -gt $PYTHON_MIN_MAJOR ]]; then return 0; fi
    if [[ $major -eq $PYTHON_MIN_MAJOR && $minor -ge $PYTHON_MIN_MINOR ]]; then return 0; fi
    return 1
}

# Robuste Python-Detection mit Mindestversion.
# Achtung Windows: `python3.exe` im PATH ist oft der Microsoft-Store-AppAlias,
# der zwar mit command -v gefunden wird, aber nur den Store öffnet. Deshalb
# probieren wir tatsächlich den Aufruf aus und akzeptieren nur ≥ 3.10.
_detect_python() {
    local candidates=()
    local os; os="$(uname -s)"
    case "$os" in
        MINGW*|MSYS*|CYGWIN*)
            # Konkrete neue Versionen zuerst, damit wir nicht auf py -3 = 3.9 landen
            candidates=("py -3.13" "py -3.12" "py -3.11" "py -3.10" "py -3" "python" "python3")
            ;;
        *)
            candidates=("python3.13" "python3.12" "python3.11" "python3.10" "python3" "python")
            ;;
    esac

    # Erste Runde: Kandidat muss gültige Version liefern UND Mindestversion erfüllen.
    # Hinweis: der Windows-py-Launcher schreibt bei fehlender Version "Python X.Y
    # not found!" nach STDOUT (nicht stderr) und exit-Code 0 — deshalb müssen wir
    # strikt gegen <major>.<minor> matchen, sonst läuft der Quatsch in den Parser.
    local cand ver
    for cand in "${candidates[@]}"; do
        ver=$($cand -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
        # Nur reine Zahl.Zahl akzeptieren
        [[ "$ver" =~ ^[0-9]+\.[0-9]+$ ]] || continue
        if _python_meets_min "$ver"; then
            PYTHON="$cand"
            PYTHON_VERSION="$ver"
            return 0
        fi
    done
    return 1
}

_check_python() {
    if _detect_python; then
        ok "Python $PYTHON_VERSION ($PYTHON)"
        return 0
    fi

    fail "Kein Python ≥ ${PYTHON_MIN_MAJOR}.${PYTHON_MIN_MINOR} gefunden."
    info "Zensical benötigt Python ≥ ${PYTHON_MIN_MAJOR}.${PYTHON_MIN_MINOR} (aktuelle Version: ${PYTHON_VERSION:-'keine'})."

    # Was haben wir *ansonsten* gefunden — damit der User weiß, was da ist
    local os; os="$(uname -s)"
    local probe ver
    case "$os" in
        MINGW*|MSYS*|CYGWIN*) probe="py -3" ;;
        *)                    probe="python3" ;;
    esac
    ver=$($probe -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
    if [[ "$ver" =~ ^[0-9]+\.[0-9]+$ ]]; then
        info "Gefunden: $probe → Python $ver (zu alt)"
    fi

    echo ""
    case "$os" in
        MINGW*|MSYS*|CYGWIN*)
            info "Installation: winget install Python.Python.3.12"
            info "oder von python.org → Python 3.10+ herunterladen"
            ;;
        *)
            info "Installation: z.B. 'apt install python3.12' oder von python.org"
            ;;
    esac
    return 1
}

_ensure_venv() {
    # Existierende venv? Prüfen, ob sie mit passender Python-Version gebaut
    # wurde — sonst rebuild, weil sonst pip die alte Zensical 0.0.2 zieht.
    if [ -d "$VENV_DIR" ]; then
        local venv_py=""
        if   [ -x "$VENV_DIR/Scripts/python.exe" ]; then venv_py="$VENV_DIR/Scripts/python.exe"
        elif [ -x "$VENV_DIR/bin/python" ];         then venv_py="$VENV_DIR/bin/python"
        fi
        if [ -n "$venv_py" ]; then
            local venv_ver
            venv_ver=$("$venv_py" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
            if [[ ! "$venv_ver" =~ ^[0-9]+\.[0-9]+$ ]] || ! _python_meets_min "$venv_ver"; then
                warn ".venv-docs hat Python ${venv_ver:-?} (benötigt ≥${PYTHON_MIN_MAJOR}.${PYTHON_MIN_MINOR}) — wird neu gebaut"
                rm -rf "$VENV_DIR"
            fi
        else
            warn ".venv-docs unvollständig — wird neu gebaut"
            rm -rf "$VENV_DIR"
        fi
    fi

    if [ ! -d "$VENV_DIR" ]; then
        info ".venv-docs wird mit Python $PYTHON_VERSION angelegt …"
        if ! $PYTHON -m venv "$VENV_DIR"; then
            fail "venv-Erstellung fehlgeschlagen."
            return 1
        fi
        ok ".venv-docs erstellt"
    fi

    # Activate (Windows: Scripts/, Linux/Mac: bin/)
    if [ -f "$VENV_DIR/Scripts/activate" ]; then
        # shellcheck disable=SC1091
        source "$VENV_DIR/Scripts/activate"
    elif [ -f "$VENV_DIR/bin/activate" ]; then
        # shellcheck disable=SC1091
        source "$VENV_DIR/bin/activate"
    else
        fail "venv hat weder Scripts/activate noch bin/activate."
        return 1
    fi

    # Nach Activate: PYTHON auf das venv-eigene Binary umsetzen — auf Windows
    # legt venv nur python.exe, kein python3.exe → sonst greift der Store-Stub
    # im System-PATH wieder durch.
    if [ -x "$VENV_DIR/Scripts/python.exe" ]; then
        PYTHON="$VENV_DIR/Scripts/python.exe"
    elif [ -x "$VENV_DIR/bin/python" ]; then
        PYTHON="$VENV_DIR/bin/python"
    fi
}

_ensure_zensical() {
    # Immer `$PYTHON -m pip` verwenden — direktes `pip` scheitert auf Windows
    # beim Self-Upgrade mit WinError 5 (pip.exe in use by itself).
    # Zensical ist in Alpha (Stand 2026-04: 0.0.34), deshalb keine Versions-
    # prüfung; wir verlassen uns darauf, dass pip bei passender Python-Version
    # die neueste kompatible Version zieht.
    local zen_ver
    zen_ver=$("$PYTHON" -m pip show zensical 2>/dev/null | awk '/^Version:/ {print $2}')

    if [[ -n "$zen_ver" && "$zen_ver" != "0.0.2" ]]; then
        ok "Zensical: $zen_ver"
        return 0
    fi

    if [[ "$zen_ver" == "0.0.2" ]]; then
        warn "Alte Zensical-Version 0.0.2 (PyPI-Platzhalter) erkannt — wird ersetzt"
    else
        info "Zensical wird installiert …"
    fi

    # Pip-Upgrade ist optional — wenn es scheitert (z.B. Netz oder Rechte),
    # trotzdem zensical-Install versuchen.
    if ! "$PYTHON" -m pip install --quiet --upgrade pip 2>/dev/null; then
        warn "pip-Upgrade übersprungen (nicht kritisch)."
    fi

    # --upgrade erzwingt die aktuelle Version falls 0.0.2 installiert war
    if ! "$PYTHON" -m pip install --quiet --upgrade zensical; then
        fail "Zensical-Installation fehlgeschlagen."
        info "Manuell:  $PYTHON -m pip install --upgrade zensical"
        return 1
    fi

    # Nach Install erneut Version ermitteln — als Sanity-Check
    zen_ver=$("$PYTHON" -m pip show zensical 2>/dev/null | awk '/^Version:/ {print $2}')
    ok "Zensical installiert: ${zen_ver:-?}"
}

_prepare() {
    _check_python || return 1
    _ensure_venv    || return 1
    _ensure_zensical || return 1
}

# ── Port-Handling ─────────────────────────────────────────────────────────────
# Liefert die PID, die den Port belegt — leer wenn frei. Cross-platform für
# Git-Bash/MSYS (PowerShell, sprachneutral) und Linux/Mac (lsof/ss/fuser).
_port_pid() {
    local port="$1"
    local os; os="$(uname -s)"
    case "$os" in
        MINGW*|MSYS*|CYGWIN*)
            # PowerShell statt netstat, weil netstat auf deutschen Windows
            # "ABHÖREN" statt "LISTENING" ausgibt und UTF-16 kodiert.
            powershell.exe -NoProfile -Command "
                try {
                    (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop |
                       Select-Object -First 1).OwningProcess
                } catch { }" 2>/dev/null | tr -d '\r\n '
            ;;
        *)
            if command -v lsof &>/dev/null; then
                lsof -ti:"$port" -sTCP:LISTEN 2>/dev/null | head -1
            elif command -v ss &>/dev/null; then
                ss -lntp 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" {print $0}' \
                  | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2
            elif command -v fuser &>/dev/null; then
                fuser "$port/tcp" 2>/dev/null | awk '{print $1}'
            fi
            ;;
    esac
}

_kill_pid() {
    local pid="$1"
    local os; os="$(uname -s)"
    case "$os" in
        MINGW*|MSYS*|CYGWIN*) taskkill //F //PID "$pid" >/dev/null 2>&1 ;;
        *)                    kill -9 "$pid" 2>/dev/null ;;
    esac
}

# Prüft ob der Port frei ist und beendet ansonsten den Halter.
_ensure_port_free() {
    local port="$1"
    local pid; pid=$(_port_pid "$port")
    if [[ -z "$pid" ]]; then
        ok "Port $port ist frei"
        return 0
    fi

    warn "Port $port wird von PID $pid belegt — wird beendet …"
    _kill_pid "$pid"

    # Kurz warten und erneut prüfen (Windows braucht manchmal ein paar ms)
    local tries=0
    while [[ $tries -lt 10 ]]; do
        sleep 0.2
        if [[ -z "$(_port_pid "$port")" ]]; then
            ok "Port $port freigegeben"
            return 0
        fi
        tries=$((tries+1))
    done

    fail "Port $port konnte nicht freigegeben werden (PID $pid hält weiter)."
    info "Tipp: anderen Port wählen mit --port=<n> oder manuell beenden."
    return 1
}

# ── Kommandos ─────────────────────────────────────────────────────────────────

cmd_prereqs() {
    header "$APP_NAME — Voraussetzungen"
    _check_python || { fail "Abgebrochen: python3 fehlt"; return 1; }
    if [ -d "$VENV_DIR" ]; then ok ".venv-docs vorhanden"
    else warn ".venv-docs fehlt — wird beim ersten Start angelegt"; fi
    if [ -f "$SCRIPT_DIR/build_docs.py" ]; then ok "build_docs.py vorhanden"
    else fail "build_docs.py fehlt"; fi
    if [ -f "$SCRIPT_DIR/zensical.toml" ]; then ok "zensical.toml vorhanden"
    else warn "zensical.toml fehlt"; fi
    local doc_count
    doc_count=$(find "$SCRIPT_DIR/docs" -type f -name '*.md' 2>/dev/null | wc -l)
    ok "Markdown-Dateien: $doc_count"
    echo ""
    ok "Voraussetzungen geprüft."
}

cmd_start() {
    header "$APP_NAME — Live-Server (Port $PORT)"
    _prepare                 || return 1
    _ensure_port_free "$PORT" || return 1
    [ -d "$SCRIPT_DIR/site" ] && rm -rf "$SCRIPT_DIR/site"
    echo ""
    echo -e "   ${GREEN}http://127.0.0.1:$PORT${NC}  ${DIM}(Ctrl+C zum Beenden)${NC}"
    echo ""
    # SIGINT (Ctrl+C) soll nur Zensical stoppen, nicht dieses Skript.
    # trap setzt den Handler nur für die Dauer dieses Aufrufs, danach zurück.
    trap ':' INT
    "$PYTHON" build_docs.py --serve --port "$PORT"
    local rc=$?
    trap - INT
    echo ""
    if [[ $rc -ne 0 ]]; then
        info "Server beendet (exit $rc)."
    else
        ok "Server beendet."
    fi
    return 0
}

cmd_build() {
    header "$APP_NAME — Statisches HTML bauen"
    _prepare || return 1
    [ -d "$SCRIPT_DIR/site" ] && rm -rf "$SCRIPT_DIR/site"
    info "Baue statische Dokumentation …"
    if "$PYTHON" build_docs.py; then
        ok "Fertig."
        echo -e "   ${DIM}Öffnen:${NC} ${CYAN}file://$SCRIPT_DIR/site/index.html${NC}"
    else
        fail "Build fehlgeschlagen."
        return 1
    fi
}

cmd_check() {
    header "$APP_NAME — Struktur prüfen"
    _prepare || return 1
    "$PYTHON" build_docs.py --check
}

cmd_clean() {
    header "$APP_NAME — .venv-docs entfernen"
    if [ -d "$VENV_DIR" ]; then
        rm -rf "$VENV_DIR"
        ok ".venv-docs gelöscht"
    else
        warn ".venv-docs nicht vorhanden — nichts zu tun"
    fi
    if [ -d "$SCRIPT_DIR/site" ]; then
        rm -rf "$SCRIPT_DIR/site"
        ok "site/ gelöscht"
    fi
}

cmd_version() {
    if [ -d "$VENV_DIR" ]; then
        # shellcheck disable=SC1091
        source "$VENV_DIR/bin/activate" 2>/dev/null || true
    fi
    local zen_ver
    zen_ver=$(zensical --version 2>/dev/null | head -1 || echo "nicht installiert")
    echo "$APP_NAME — Zensical: $zen_ver"
}

cmd_help() {
    echo -e "\n${BOLD}$APP_NAME${NC} — ${DIM}bash run_luscreen_docs.sh [Kommando]${NC}"
    echo -e "  1 | --check-prereqs       Voraussetzungen prüfen"
    echo -e "  2 |                       Live-Server starten (Default Port 8000)"
    echo -e "  3 | --build               Statisches HTML nach site/"
    echo -e "  4 | --check               Struktur prüfen"
    echo -e "  5 | --clean               .venv-docs und site/ entfernen"
    echo -e "      --port=<n>            Port für Live-Server"
    echo -e "      --version             Zensical-Version anzeigen"
    echo -e "      --help                diese Hilfe"
    echo ""
}

# ── Interaktives Menü ─────────────────────────────────────────────────────────
show_menu() {
    echo ""
    echo -e "${BOLD}┌────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}│${NC}  ${GREEN}●${NC} ${BOLD}LucentScreen — Docs${NC}          ${BOLD}│${NC}"
    echo -e "${BOLD}│${NC}  ${DIM}Zensical · Port $PORT${NC}                       ${BOLD}│${NC}"
    echo -e "${BOLD}├────────────────────────────────────────────┤${NC}"
    echo -e "${BOLD}│${NC}                                            ${BOLD}│${NC}"
    echo -e "${BOLD}│${NC}  ${CYAN}1${NC}  Voraussetzungen prüfen               ${BOLD}│${NC}"
    echo -e "${BOLD}│${NC}  ${CYAN}2${NC}  Live-Server starten                  ${BOLD}│${NC}"
    echo -e "${BOLD}│${NC}  ${CYAN}3${NC}  Statisches HTML bauen                ${BOLD}│${NC}"
    echo -e "${BOLD}│${NC}  ${CYAN}4${NC}  Struktur prüfen                      ${BOLD}│${NC}"
    echo -e "${BOLD}│${NC}  ${CYAN}5${NC}  .venv-docs zurücksetzen              ${BOLD}│${NC}"
    echo -e "${BOLD}│${NC}                                            ${BOLD}│${NC}"
    echo -e "${BOLD}│${NC}  ${DIM}q  Beenden${NC}                              ${BOLD}│${NC}"
    echo -e "${BOLD}│${NC}                                            ${BOLD}│${NC}"
    echo -e "${BOLD}└────────────────────────────────────────────┘${NC}"
    echo ""
}

_interactive_menu() {
    # Ctrl+C im Menü selbst nur fürs aktuelle read schlucken, nicht beenden
    trap ':' INT
    while true; do
        show_menu
        read -rp "  Auswahl: " choice || { echo ""; exit 0; }
        case "$choice" in
            1) cmd_prereqs ;;
            2) cmd_start ;;
            3) cmd_build ;;
            4) cmd_check ;;
            5) cmd_clean ;;
            q|Q|0) echo -e "\n${DIM}Tschüss!${NC}"; exit 0 ;;
            "") continue ;;
            *) warn "Ungültige Auswahl '$choice'" ;;
        esac
        echo ""
        echo -e "${DIM}────────────────────────────────────────────${NC}"
        read -rp "  Enter für Hauptmenü..." _ || { echo ""; exit 0; }
    done
}

# ── Einstiegspunkt ────────────────────────────────────────────────────────────
if [[ $# -ge 1 ]]; then
    # Direktaufruf mit Argumenten — Hub-kompatible Flags
    HANDLED=false
    for arg in "$@"; do
        case "$arg" in
            --check-prereqs|--prereqs|1) cmd_prereqs; HANDLED=true ;;
            --build|3)                   cmd_build;   HANDLED=true ;;
            --check|4)                   cmd_check;   HANDLED=true ;;
            --clean|5)                   cmd_clean;   HANDLED=true ;;
            --version|-v)                cmd_version; HANDLED=true ;;
            --help|-h)                   cmd_help;    HANDLED=true ;;
            --menu|menu)                 _interactive_menu; HANDLED=true ;;
            --port=*)                    : ;;   # bereits oben eingelesen
            2)                           cmd_start;   HANDLED=true ;;
        esac
    done
    # Wenn kein Kommando-Flag dabei war (nur --port= o.ä.): Default = Live-Server
    if [[ "$HANDLED" == false ]]; then
        cmd_start
    fi
else
    # Kein Argument: interaktives Menü wenn Terminal, sonst direktstart
    if [ -t 0 ] && [ -t 1 ]; then
        _interactive_menu
    else
        cmd_start
    fi
fi
