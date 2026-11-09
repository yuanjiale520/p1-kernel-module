#!/usr/bin/env bash
set -euo pipefail
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
out=${P2_RESULTS:?}
export DISPLAY=:91
export XDG_CURRENT_DESKTOP=XFCE
export DESKTOP_SESSION=xfce
export XDG_SESSION_TYPE=x11

if [[ "${1:-}" == --desktop ]]; then
    mkdir -p "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    if [[ -r /etc/xdg/xfce4/panel/default.xml ]]; then
        cp /etc/xdg/xfce4/panel/default.xml \
            "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    fi
    xfce4-session > "$out/logs/xfce-session.log" 2>&1 &
    desktop_pid=$!
    trap 'kill "$desktop_pid" 2>/dev/null || true' EXIT
    ready=0
    for n in $(seq 1 40); do
        if wmctrl -m 2>/dev/null | grep -qi xfwm; then ready=1; break; fi
        sleep 0.5
    done
    (( ready )) || { cat "$out/logs/xfce-session.log"; exit 1; }
    xterm -geometry 156x51+60+70 -fn 9x15 -b 6 \
        -bg '#10141c' -fg '#e6edf3' -cr '#58a6ff' \
        -title 'P2 - GitHub cloud Ubuntu - real QEMU and TigerVNC session' \
        -e bash -c 'set +e; bash "$1/demo.sh" > >(tee "$2/logs/terminal.log") 2>&1; status=$?; printf "%s\n" "$status" > "$2/logs/demo-exit-code.txt"; exit "$status"' \
        bash "$project" "$out"
    test "$(cat "$out/logs/demo-exit-code.txt")" = 0
    exit 0
fi

Xtigervnc :91 -localhost yes -SecurityTypes None -geometry 1600x1000 \
    -depth 24 -rfbport 5991 -nolisten tcp -ac \
    > "$out/logs/tigervnc.log" 2>&1 &
vnc_pid=$!
trap 'kill "$vnc_pid" 2>/dev/null || true' EXIT
ready=0
for n in $(seq 1 40); do
    if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then ready=1; break; fi
    sleep 0.5
done
(( ready )) || { cat "$out/logs/tigervnc.log"; exit 1; }
dbus-run-session -- bash "$project/session.sh" --desktop
test "$(cat "$out/logs/demo-exit-code.txt")" = 0
grep -q P2_GUEST_SUCCESS "$out/logs/qemu-console.log"
for screenshot in 01_build_files 02_qemu_guest_kernel 03_optional_guest_module 04_xfce_neofetch 05_xsession_configuration; do
    test -s "$out/screenshots/$screenshot.png"
done
printf 'P2_SESSION_VERIFIED\n'
