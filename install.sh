#!/usr/bin/env bash
# ============================================================================
#  Vexyon installer (3.0)
#  OUT OF THE BOX: installs and configures EVERY dependency of every feature,
#  optional modules included (virtual machines, Bluetooth, screen recording),
#  so nothing afterwards needs a package install, a systemctl or a config edit.
#  Optional modules are on by default and are switched in Settings → Modules.
#  Installs dependencies and deploys the shell into the standard locations:
#    config/vexyon  -> ~/.config/vexyon
#    config/hypr    -> ~/.config/hypr        (an existing hyprland.lua is backed up)
#    share/vexyon   -> ~/.local/share/vexyon
#    config/vexyon/bin/* -> ~/.local/bin
#  Idempotent; safe to re-run to update.
#
#  Salida: en pantalla solo un paso por línea (spinner + ✓/✗); el detalle
#  completo de cada comando (pacman incluido) va a /tmp/vexyon-install.log.
#  Si un paso obligatorio falla, el instalador PARA, lo dice en rojo y
#  enseña las últimas líneas del log. ANSI puro — sin dependencias extra.
# ============================================================================
set -Eeuo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VEXYON_VERSION="3.0"

# El uploader web de GitHub (drag & drop) QUITA el bit ejecutable — todo llega
# como 100644 venga como venga. Re-asegurar +x ANTES de que nada los invoque,
# acotado a config/vexyon/bin: ese directorio contiene SOLO helpers ejecutables
# (install.sh ejecuta vexyon-gpu-detect directamente desde el repo; el resto se
# despliega con +x vía link_helpers / install -Dm755). Nada más lo necesita:
# QML/confs/JSON se copian como datos y el bridge se invoca con `python3`.
chmod +x "$SRC"/config/vexyon/bin/* 2>/dev/null || true

# --- Log --------------------------------------------------------------------
LOG="/tmp/vexyon-install.log"
if ! { : > "$LOG"; } 2>/dev/null; then
  # p.ej. un run previo con sudo dejó el fichero de root
  LOG="$(mktemp /tmp/vexyon-install.XXXXXX.log)"
fi
{ echo "Vexyon install — $(date)"; uname -a; echo; } >> "$LOG"

# --- Presentación (colores solo en TTY, NO_COLOR respetado) -----------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  TTY=1
  C_A=$'\033[1;35m'  # acento (magenta Vexyon)
  C_G=$'\033[1;32m'  # éxito
  C_R=$'\033[1;31m'  # error
  C_Y=$'\033[1;33m'  # aviso
  C_D=$'\033[2m'     # secundario
  C_B=$'\033[1m'     # negrita
  C_0=$'\033[0m'
else
  TTY=0
  C_A='' C_G='' C_R='' C_Y='' C_D='' C_B='' C_0=''
fi

WARNINGS=0
SUMMARY=()

note() { printf '  %s·%s %s\n' "$C_D" "$C_0" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$C_G" "$C_0" "$*"; }
warn() {
  printf '  %s!%s %s%s%s\n' "$C_Y" "$C_0" "$C_Y" "$*" "$C_0"
  WARNINGS=$((WARNINGS + 1))
  echo "WARN: $*" >> "$LOG"
}

section() {
  local t=" $* " line n
  n=$(( 56 - ${#t} )); [ "$n" -lt 3 ] && n=3
  line="$(printf '─%.0s' $(seq 1 "$n"))"
  printf '\n%s──%s%s%s%s%s\n' "$C_A" "$C_0$C_B" "$t" "$C_0" "$C_A$line" "$C_0"
  printf '\n===== %s =====\n' "$*" >> "$LOG"
}

die() {
  printf '\n  %s✗ %s%s\n' "$C_R" "$*" "$C_0"
  if [ -s "$LOG" ]; then
    printf '  %sLast log lines:%s\n' "$C_D" "$C_0"
    tail -n 12 "$LOG" | sed "s/^/  ${C_D}│${C_0} /"
  fi
  printf '  %sFull output: %s%s\n' "$C_D" "$LOG" "$C_0"
  exit 1
}

# _run <fatal|soft> <label> <hint-si-falla> <cmd...>
#   Ejecuta cmd con la salida entera en $LOG; en pantalla, spinner + ✓/✗.
#   fatal → die (para el instalador); soft → warn y sigue.
_run() {
  local mode="$1" label="$2" hint="$3" rc=0
  shift 3
  printf '\n>>> %s\n' "$label" >> "$LOG"
  if [ "$TTY" = 1 ]; then
    ( trap - ERR; "$@" ) >> "$LOG" 2>&1 &
    local pid=$! i=0
    local f=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    printf '\033[?25l'
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r  %s%s%s %s' "$C_A" "${f[i % 10]}" "$C_0" "$label"
      i=$((i + 1))
      sleep 0.08
    done
    wait "$pid" || rc=$?
    printf '\033[?25h'
    if [ "$rc" -eq 0 ]; then
      printf '\r  %s✓%s %s\n' "$C_G" "$C_0" "$label"
    else
      printf '\r  %s✗%s %s\n' "$C_R" "$C_0" "$label"
    fi
  else
    ( trap - ERR; "$@" ) >> "$LOG" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then printf '  ✓ %s\n' "$label"; else printf '  ✗ %s\n' "$label"; fi
  fi
  if [ "$rc" -ne 0 ]; then
    if [ "$mode" = fatal ]; then
      die "\"$label\" failed (exit $rc)."
    else
      warn "$label failed${hint:+ — $hint}"
    fi
  fi
}
step()     { _run fatal "$1" "" "${@:2}"; }   # obligatorio: si falla, para
try_step() { _run soft "$1" "$2" "${@:3}"; }  # opcional: si falla, avisa y sigue

cleanup() {
  [ -n "${SUDO_PID:-}" ] && kill "$SUDO_PID" 2>/dev/null || true
  [ "$TTY" = 1 ] && printf '\033[?25h' || true
}
trap cleanup EXIT
trap 'st=$?; printf "\n  %s✗ Install aborted (exit %s) at: %s%s\n" "$C_R" "$st" "$BASH_COMMAND" "$C_0"; printf "  %sFull output: %s%s\n" "$C_D" "$LOG" "$C_0"' ERR

# --- Banner -----------------------------------------------------------------
printf '\n'
printf '  %s╭───╮%s\n' "$C_A" "$C_0"
printf '  %s│ V │%s  %sVexyon %s%s — desktop shell for Hyprland\n' "$C_A" "$C_0" "$C_B" "$VEXYON_VERSION" "$C_0"
printf '  %s╰───╯%s  %sinstaller · full log: %s%s\n' "$C_A" "$C_0" "$C_D" "$LOG" "$C_0"

# --- Privileges -------------------------------------------------------------
SUDO_PID=""
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || die "sudo is required (packages, /etc/pam.d, greetd)."
  printf '\n'
  note "Some steps need administrator rights — sudo may ask for your password now."
  sudo -v || die "sudo authentication failed."
  # Mantener la credencial viva durante pasos largos (pacman en mirror lento)
  ( while sudo -n true 2>/dev/null; do sleep 50; done ) &
  SUDO_PID=$!
fi

# --- Dependencies ----------------------------------------------------------
PKGS=(
  hyprland quickshell jq hyprsunset ghostty fish
  python python-pillow
  qt6-base qt6-declarative qt6-svg
  # qt6-imageformats: lector WebP de Qt. qt6-base solo trae PNG/JPEG/GIF/BMP y
  # el selector de foto de perfil ofrece *.webp: sin él un avatar WebP no carga
  # y Ajustes / Super+C / bloqueo enseñan solo la inicial. En NixOS lo exporta
  # la sesión del módulo (QT_PLUGIN_PATH).
  qt6-imageformats
  # xdg-desktop-portal-gtk: backend del portal Settings (fallback declarado en
  # hyprland-portals.conf) — expone org.freedesktop.appearance color-scheme
  # para que apps y navegadores sigan el modo claro/oscuro del tema activo.
  polkit-kde-agent xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  cliphist wl-clipboard grim libnotify
  networkmanager pipewire wireplumber pipewire-pulse
  brightnessctl ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji
  papirus-icon-theme fastfetch
  # Temas de cursor del selector de Ajustes (appearance.cursorTheme). Solo son
  # ficheros en /usr/share/icons, ningún proceso. Los cuatro están en repos
  # OFICIALES — Bibata (lo que usa el port de NixOS) es solo AUR, así que
  # "pretty"/"black" los cubre breeze-cursors con las mismas dos formas.
  # Ninguno puede faltar: si XCURSOR_THEME apunta a un tema que no se resuelve,
  # Hyprland dibuja su cursor EMBEBIDO, que tiene forma de su logo.
  adwaita-cursors breeze-cursors xcursor-vanilla-dmz capitaine-cursors
  zip unzip glib2 xdg-utils
  # udisks2: servicio estándar de medios extraíbles (el que usan
  # Nautilus/Dolphin/Thunar). D-Bus-activado: no se habilita nada, arranca
  # solo cuando el gestor de ficheros lo llama. Sin él no hay automontaje
  # de USB/SSD externos con permisos correctos y sin sudo.
  udisks2
  # --- energía -------------------------------------------------------------
  # Los dos widgets de energía del shell son clientes D-Bus de estos dos
  # servicios; NO son opcionales, igual que en el módulo de NixOS:
  #   upower                -> services/Battery.qml (Quickshell.Services.UPower)
  #   power-profiles-daemon -> modules/BatteryPanel.qml (singleton PowerProfiles,
  #                            interfaz org.freedesktop.UPower.PowerProfiles)
  # En CachyOS los dos suelen venir ya instalados de forma transitiva, y por eso
  # una sesión anterior concluyó (mal) que en Arch no hacían falta. Se declaran
  # aquí para no depender de los defectos de la distro.
  upower power-profiles-daemon
  sshfs openssh
  # --- 3.0: what features already used but nothing installed ---------------
  #   hyprpicker      the color-picker bar widget
  #   pacman-contrib  `checkupdates`, the update widget's counter
  #   libpulse        `pactl`: Settings → Audio device lists, privacy widget
  #   psmisc          `fuser`: the privacy widget's camera check
  hyprpicker pacman-contrib libpulse psmisc
  # --- File Manager --------------------------------------------------------
  #   xdg-user-dirs   the sidebar's Desktop/Documents/Downloads… at the paths
  #                   user-dirs.dirs configures (~/Documentos…); when that file
  #                   does not exist yet, the File Manager runs
  #                   xdg-user-dirs-update once, as every desktop does at login.
  #   (wl-clipboard, already above, carries the system clipboard: copy/cut/
  #   paste between File Manager windows and with other programs.)
  xdg-user-dirs
)

# --- Optional modules' packages (Settings → Modules) --------------------------
# Installed always, like everything else: a module turned off keeps its
# packages, so turning it back on never needs a download. Only its services
# stop starting (see "Optional modules" below).
MOD_PKGS=(
  # Screen recording: the encoder; runs only while recording.
  wf-recorder
  # Bluetooth: bluetoothd (starts only when an adapter is present).
  bluez
  # Virtual machines: libvirt, its NAT/DHCP (dnsmasq), the display window,
  # TPM for Windows 11, shared folders, UEFI firmware.
  libvirt dnsmasq virt-viewer swtpm virtiofsd edk2-ovmf
)
# QEMU: qemu-desktop, unless some QEMU is already installed. qemu-full and
# qemu-base conflict with it, and `pacman --noconfirm` answers "no" to the
# replacement question — the whole transaction would fail.
command -v qemu-system-x86_64 >/dev/null 2>&1 || MOD_PKGS+=(qemu-desktop)
# libvirt's NAT needs a firewall command; nearly every system has one.
{ command -v nft || command -v iptables; } >/dev/null 2>&1 || MOD_PKGS+=(nftables)

# Wallpaper daemon: upstream renamed `swww` to `awww` (Arch extra y CachyOS ya
# solo empaquetan awww, que hace Provides=swww). Instalar el que exista para
# soportar mirrors antiguos sin depender del resolvedor de providers.
if command -v pacman >/dev/null 2>&1; then
  if pacman -Si awww >/dev/null 2>&1; then PKGS+=(awww); else PKGS+=(swww); fi
else
  PKGS+=(awww)
fi

section "Dependencies"
if [ "${VEXYON_SKIP_PKGS:-0}" = "1" ]; then
  note "VEXYON_SKIP_PKGS=1 — skipping package install"
elif command -v pacman >/dev/null 2>&1; then
  missing=()
  while IFS= read -r p; do [ -n "$p" ] && missing+=("$p"); done \
    < <(pacman -T "${PKGS[@]}" || true)
  if [ "${#missing[@]}" -eq 0 ]; then
    ok "All ${#PKGS[@]} packages already installed"
    SUMMARY+=("Dependencies: all ${#PKGS[@]} packages already present")
  else
    note "${#missing[@]} of ${#PKGS[@]} packages to install:"
    printf '%s\n' "${missing[*]}" | fold -s -w 62 | sed "s/^/      ${C_D}/;s/\$/${C_0}/"
    step "Installing ${#missing[@]} packages (pacman)" \
      sudo pacman -S --noconfirm --needed "${missing[@]}"
    SUMMARY+=("Dependencies: ${#missing[@]} packages installed (${#PKGS[@]} total)")
  fi
  # Module packages in their own transaction: if one cannot be installed
  # (a conflict with something the user chose), the rest of Vexyon still is,
  # and the module's Settings page says exactly what is missing.
  mod_missing=()
  while IFS= read -r p; do [ -n "$p" ] && mod_missing+=("$p"); done \
    < <(pacman -T "${MOD_PKGS[@]}" || true)
  if [ "${#mod_missing[@]}" -eq 0 ]; then
    ok "All ${#MOD_PKGS[@]} optional-module packages already installed"
  else
    note "${#mod_missing[@]} optional-module packages to install:"
    printf '%s\n' "${mod_missing[*]}" | fold -s -w 62 | sed "s/^/      ${C_D}/;s/\$/${C_0}/"
    try_step "Installing ${#mod_missing[@]} optional-module packages (pacman)" \
      "a module may report missing pieces in Settings" \
      sudo pacman -S --noconfirm --needed "${mod_missing[@]}"
  fi
else
  warn "pacman not found — install these manually: ${PKGS[*]} ${MOD_PKGS[*]}"
fi

# --- System integration -----------------------------------------------------
section "System integration"

# PAM config for the lock screen.
# NOTE: rsync-only deploys never touch /etc, so the lock screen's PAM service
# can go missing there. The file is also shipped into the deploy tree
# (~/.config/vexyon/pam/vexyon) and can be (re)installed any time with the
# helper `vexyon-lock-pam-setup`.
if [ -f "$SRC/config/pam/vexyon" ]; then
  try_step "PAM config for the lock screen (/etc/pam.d/vexyon)" \
    "run 'vexyon-lock-pam-setup' later" \
    sudo install -Dm644 "$SRC/config/pam/vexyon" /etc/pam.d/vexyon
fi

# Polkit rule for the power menu. Sin esto, Suspender/Reiniciar/Apagar fallan
# con "interactive authentication required": el shell lanza el comando
# desatendido (execDetached hace setsid) y polkit no puede pedir contraseña.
# La regla concede las acciones de energía de login1 al grupo `wheel`.
if [ -f "$SRC/config/polkit/49-vexyon-power.rules" ]; then
  try_step "Polkit power rule (/etc/polkit-1/rules.d)" \
    "power menu may ask for a password" \
    sudo install -Dm644 "$SRC/config/polkit/49-vexyon-power.rules" \
      /etc/polkit-1/rules.d/49-vexyon-power.rules
  if ! id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx wheel; then
    warn "User $USER is not in the 'wheel' group — the power menu will ask for"
    warn "a password. Add it with:  sudo usermod -aG wheel $USER"
  fi
fi

# --- Power services ---------------------------------------------------------
# upower: sin él Battery.present es false y el indicador de batería de la barra
# no existe. Los dos servicios se activan por D-Bus, así que en la práctica
# arrancarían solos en cuanto el shell los llame; se habilitan de todas formas
# para que el estado sea explícito y no dependa de que el fichero de activación
# D-Bus esté donde toca.
try_step "Enabling upower.service" \
  "battery indicator will be missing" \
  sudo systemctl enable --now upower.service

# power-profiles-daemon: OJO, su propia unit declara
#   Conflicts=tuned.service tlp.service auto-cpufreq.service system76-power.service
# así que habilitarla a ciegas PARARÍA el gestor de energía que el usuario ya
# tenga puesto. Eso no es decisión del instalador de un shell: si hay un rival
# activo se respeta y se avisa de lo que implica (la píldora de perfiles del
# panel de batería no podrá cambiar de perfil), en vez de tocarlo por detrás.
PPD_RIVAL=""
for svc in tlp.service tuned.service auto-cpufreq.service system76-power.service; do
  if systemctl is-enabled "$svc" >/dev/null 2>&1 || systemctl is-active "$svc" >/dev/null 2>&1; then
    PPD_RIVAL="$svc"
    break
  fi
done
if [ -n "$PPD_RIVAL" ]; then
  warn "$PPD_RIVAL is already managing power — NOT enabling power-profiles-daemon"
  warn "(they are mutually exclusive; ppd's unit would stop $PPD_RIVAL)."
  warn "The battery panel's profile pill will not be able to switch profiles."
  warn "To use it instead, run:  sudo systemctl disable --now $PPD_RIVAL"
  warn "  && sudo systemctl enable --now power-profiles-daemon.service"
  SUMMARY+=("Power profiles: skipped (kept $PPD_RIVAL)")
else
  try_step "Enabling power-profiles-daemon.service" \
    "battery panel profile pill will not switch profiles" \
    sudo systemctl enable --now power-profiles-daemon.service
  SUMMARY+=("Power: upower + power-profiles-daemon enabled")
fi

# Notification daemon guard: only one process may own
# org.freedesktop.Notifications. Stop/disable rivals so the Vexyon
# notification service can claim it cleanly.
for svc in mako dunst swaync; do
  if pgrep -x "$svc" >/dev/null 2>&1; then
    warn "Stopping rival notification daemon: $svc"
    pkill -x "$svc" || true
  fi
  systemctl --user disable --now "$svc.service" >/dev/null 2>&1 || true
done

# --- Optional modules: system part (Settings → Modules) ---------------------
# 3.0. Virtual machines and Bluetooth are OPTIONAL MODULES: installed and on
# by default, switched off in Settings → Modules without any command. The
# switch never stops anything mid-session; it decides whether the module's
# services may start at the NEXT boot:
#   /usr/local/lib/vexyon/vexyon-modules      root-owned helper — the ONLY
#                                             thing the shell can run as root,
#                                             through pkexec + this action:
#   /usr/share/polkit-1/actions/org.vexyon.modules.policy   (admin password)
#   /etc/systemd/system/vexyon-modules.service              once per boot,
#                                             before sysinit.target
#   /etc/systemd/system/<unit>.d/50-vexyon-modules.conf     on every service
#                                             of a module:
#                                             ConditionPathExists=!…/<id>.gated
# The choice lives in /var/lib/vexyon/modules (root, 0755). Packages stay
# installed, so turning a module back on needs no download. Same design as the
# NixOS module; see PROJECT_STATE.md → Vexyon 3.0.
section "Optional modules"
MOD_HELPER=/usr/local/lib/vexyon/vexyon-modules
MOD_STATE=/var/lib/vexyon/modules
# Every unit libvirt starts by itself (systemd-machined, the firewall and
# NetworkManager are shared and never gated), and BlueZ's daemon. A drop-in
# for a unit that does not exist is inert.
VM_UNITS=(libvirtd.service libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket
          libvirtd-tcp.socket libvirtd-tls.socket
          virtlogd.service virtlogd.socket virtlogd-admin.socket
          virtlockd.service virtlockd.socket virtlockd-admin.socket
          libvirt-guests.service virt-secret-init-encryption.service)
BT_UNITS=(bluetooth.service)

write_gate() {   # <unit> <module id> <module name>
  sudo install -d -m 0755 "/etc/systemd/system/$1.d"
  printf '%s\n' \
    "# Vexyon modules (written by install.sh): Settings → Modules → $3" \
    "# decides at boot whether this unit may start. See vexyon-modules.service." \
    "[Unit]" \
    "Wants=vexyon-modules.service" \
    "After=vexyon-modules.service" \
    "ConditionPathExists=!/run/vexyon/modules/$2.gated" |
    sudo tee "/etc/systemd/system/$1.d/50-vexyon-modules.conf" >/dev/null
}

install_modules_system() {
  local u
  sudo install -D -m 0755 -o root -g root "$SRC/config/vexyon/bin/vexyon-modules" "$MOD_HELPER"
  sudo install -D -m 0644 -o root -g root "$SRC/config/polkit/org.vexyon.modules.policy" \
    /usr/share/polkit-1/actions/org.vexyon.modules.policy
  sudo install -d -m 0755 -o root -g root /var/lib/vexyon "$MOD_STATE"
  sudo tee /etc/systemd/system/vexyon-modules.service >/dev/null <<'UNIT'
# Vexyon modules (written by install.sh). Once per boot, before any socket or
# service of a module can start: freezes this boot's choices from
# /var/lib/vexyon/modules into /run/vexyon/modules and gates the services of
# modules that are off. Run later it does nothing: module changes always take
# effect at the next boot, never mid-session.
[Unit]
Description=Vexyon modules: apply this boot's module choices
DefaultDependencies=no
After=local-fs.target
Before=sysinit.target shutdown.target
Conflicts=shutdown.target
RequiresMountsFor=/var/lib/vexyon

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/lib/vexyon/vexyon-modules boot-apply

[Install]
WantedBy=sysinit.target
UNIT
  for u in "${VM_UNITS[@]}"; do write_gate "$u" vm "Virtual machines"; done
  for u in "${BT_UNITS[@]}"; do write_gate "$u" bluetooth "Bluetooth"; done
  # Only reloads unit files: nothing running is restarted.
  sudo systemctl daemon-reload
  sudo systemctl enable vexyon-modules.service
}
MODULES_OK=0
try_step "Modules: helper, polkit action, boot unit and service conditions" \
  "Settings → Modules will not be able to switch modules" \
  install_modules_system && [ -x "$MOD_HELPER" ] && MODULES_OK=1

# One-time migration from 2.x: the VM switch lived in shell.json
# (`virtualization.enabled`, off by default). Off stays off; anything else
# gets 3.0's default (on). Once only, so a later choice in Settings is never
# overridden by a re-run of this installer.
if [ "$MODULES_OK" = 1 ] && [ ! -e "$MOD_STATE/.migrated-3.0" ]; then
  if [ -s "$HOME/.config/vexyon/shell.json" ] &&
     jq -e '.virtualization.enabled == false' "$HOME/.config/vexyon/shell.json" >/dev/null 2>&1; then
    # The log is the user's file: the redirect is meant to run unprivileged.
    # shellcheck disable=SC2024
    if sudo "$MOD_HELPER" set vm off >> "$LOG" 2>&1; then
      note "Virtual machines module kept off, as it was before 3.0 (Settings → Modules turns it on)"
    fi
  fi
  sudo touch "$MOD_STATE/.migrated-3.0"
fi
vm_wanted() { [ ! -e "$MOD_STATE/vm.disabled" ]; }
bt_wanted() { [ ! -e "$MOD_STATE/bluetooth.disabled" ]; }
[ "$MODULES_OK" = 1 ] && SUMMARY+=("Modules: virtual machines $(vm_wanted && echo on || echo off), Bluetooth $(bt_wanted && echo on || echo off), screen recording on — Settings → Modules")

# --- Virtual machines (module "vm") -------------------------------------------
section "Virtual machines"
LOGIN_AGAIN=0
if ! command -v virsh >/dev/null 2>&1; then
  warn "libvirt is not installed — Settings → Virtualization will show what is missing"
elif systemctl is-enabled virtqemud.socket >/dev/null 2>&1 || systemctl is-active virtqemud.socket >/dev/null 2>&1; then
  # The user already runs libvirt's modular daemons (virtqemud & co.). That
  # setup is theirs: left exactly as it is, and never gated by the module.
  note "libvirt already runs with its modular daemons (virtqemud) — left as it is"
  SUMMARY+=("VMs: your libvirt setup (modular daemons) left as it is")
else
  if [ "$(systemctl is-enabled libvirtd.service 2>/dev/null || true)" = masked ]; then
    warn "libvirtd.service is masked — the VM manager cannot work until it is unmasked"
  else
    # The daemon at boot (it starts VMs marked to start with the computer,
    # then exits after 120 s idle — LIBVIRTD_ARGS=--timeout 120 in its unit),
    # and its sockets (Also= in its unit) bring it back on demand.
    try_step "Enabling libvirt (daemon at boot, sockets on demand)" \
      "the VM manager will report libvirtd as missing" \
      sudo systemctl enable libvirtd.service
    if vm_wanted; then
      try_step "Starting libvirt's sockets" "they start with the next boot instead" \
        sudo systemctl start libvirtd.socket virtlogd.socket virtlockd.socket
    fi
  fi
  # VMs without a password: libvirt's own polkit rule trusts the libvirt group.
  if getent group libvirt >/dev/null 2>&1 && ! id -nG "$USER" | tr ' ' '\n' | grep -qx libvirt; then
    try_step "Adding $USER to the libvirt group" "the VM manager will ask for a password" \
      sudo usermod -aG libvirt "$USER"
    LOGIN_AGAIN=1
  fi
  # Docker and ufw set a DROP policy in the iptables tables, which libvirt's
  # nftables rules (another table) cannot override: VMs lose the internet and
  # DHCP. libvirt's iptables backend writes into the same tables, ahead of
  # theirs (measured: PROJECT_STATE.md, VM networking session). Only when
  # nothing chose a backend yet — a firewall_backend line someone wrote is
  # never touched.
  if command -v dockerd >/dev/null 2>&1 || command -v ufw >/dev/null 2>&1; then
    nconf=/etc/libvirt/network.conf
    cur_be=$(sed -n 's/^[[:space:]]*firewall_backend[[:space:]]*=[[:space:]]*"\{0,1\}\([a-z]*\).*/\1/p' "$nconf" 2>/dev/null | tail -n 1)
    if [ -z "$cur_be" ]; then
      set_libvirt_iptables() {
        printf '\n%s\n%s\n%s\n' \
          "# Vexyon (install.sh): Docker/ufw drop forwarded traffic in the iptables" \
          "# tables, which libvirt's nftables rules cannot override." \
          'firewall_backend = "iptables"' | sudo tee -a "$nconf" >/dev/null
      }
      try_step "libvirt firewall: iptables backend (Docker or ufw is installed)" \
        "VMs may get no network while Docker/ufw is active" \
        set_libvirt_iptables
      note "libvirt reads it when it next starts (at the latest, the next boot); running VMs are not touched"
    elif [ "$cur_be" != iptables ]; then
      warn "/etc/libvirt/network.conf sets firewall_backend = \"$cur_be\" and Docker/ufw is installed —"
      warn "left as you set it. If VMs get no network, Diagnose networks in the VM manager says why."
    fi
  fi
  # libvirt's default NAT network ships defined (and set to autostart) with
  # the package. Defined here only if it is missing; never started here: the
  # VM manager starts a VM's networks when the VM starts.
  ensure_default_net() {
    sudo virsh -c qemu:///system net-info default >/dev/null 2>&1 && return 0
    local t rc=0
    t=$(mktemp)
    cat > "$t" <<'XML'
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp><range start='192.168.122.2' end='192.168.122.254'/></dhcp>
  </ip>
</network>
XML
    sudo virsh -c qemu:///system net-define "$t" || rc=$?
    rm -f "$t"
    return "$rc"
  }
  if vm_wanted && systemctl is-active libvirtd.socket >/dev/null 2>&1; then
    try_step "libvirt's default NAT network" "create it from the VM manager's Host networks tab" \
      ensure_default_net
  fi
  [ -e /dev/kvm ] || warn "No /dev/kvm: turn on VT-x / AMD-V (SVM) in the firmware settings to run VMs"
  SUMMARY+=("VMs: libvirt + QEMU ready ($(vm_wanted && echo 'module on' || echo 'module off — Settings → Modules'))")
fi

# --- Bluetooth (module "bluetooth") -----------------------------------------
section "Bluetooth"
if [ ! -e /usr/lib/systemd/system/bluetooth.service ]; then
  warn "BlueZ is not installed — the Bluetooth module has nothing to run"
else
  case "$(systemctl is-enabled bluetooth.service 2>/dev/null || true)" in
    masked)
      warn "bluetooth.service is masked — Bluetooth stays off until it is unmasked" ;;
    enabled|enabled-runtime)
      ok "Bluetooth service already enabled" ;;
    *)
      # bluetoothd only starts when an adapter is present (its own condition).
      try_step "Enabling Bluetooth" "Bluetooth controls will show no adapter" \
        sudo systemctl enable bluetooth.service
      if bt_wanted; then
        try_step "Starting Bluetooth" "it starts with the next boot instead" \
          sudo systemctl start bluetooth.service
      fi
      ;;
  esac
fi

# --- Network: NetworkManager --------------------------------------------------
# The network panel, Wi-Fi and the DNS selector all drive NetworkManager
# (nmcli). The package was always installed but the service was never
# enabled. It is enabled only when nothing else manages the network — two
# managers on one interface cut the connection — and only from the next boot:
# the connection in use right now is not touched.
NM_RIVAL=""
for svc in systemd-networkd.service connman.service dhcpcd.service iwd.service netctl.service wicd.service; do
  if systemctl is-enabled "$svc" >/dev/null 2>&1 || systemctl is-active "$svc" >/dev/null 2>&1; then
    NM_RIVAL="$svc"
    break
  fi
done
if systemctl is-enabled NetworkManager.service >/dev/null 2>&1; then
  ok "NetworkManager already enabled"
elif [ -n "$NM_RIVAL" ]; then
  warn "$NM_RIVAL already manages the network — NetworkManager NOT enabled."
  warn "Vexyon's network panel and DNS selector need NetworkManager."
else
  try_step "Enabling NetworkManager (from the next boot)" "the network panel will not work" \
    sudo systemctl enable NetworkManager.service
fi

# --- Shell files ------------------------------------------------------------
section "Shell files"
mkdir -p "$HOME/.config/vexyon" "$HOME/.config/hypr" \
         "$HOME/.local/share/vexyon" "$HOME/.local/bin" \
         "$HOME/Pictures/Wallpapers" "$HOME/Pictures/Screenshots"

# Upgrade path: Vexyon used to generate a hyprlang (.conf) config set. Hyprland
# >= 0.55 prefers hyprland.lua and 0.57 drops hyprlang entirely, so retire our
# old .conf files instead of leaving them to rot next to the Lua ones. Only
# files carrying the VEXYON marker (or our generated header) are touched.
retire_conf() {
  local f stamp; stamp=$(date +%s)
  for f in hyprland.conf vexyon-env.conf vexyon-rules.conf vexyon-monitors.conf \
           vexyon-keybinds.conf vexyon-settings.conf vexyon-gpu.conf; do
    [ -f "$HOME/.config/hypr/$f" ] || continue
    grep -qi "vexyon" "$HOME/.config/hypr/$f" 2>/dev/null || continue
    mv "$HOME/.config/hypr/$f" "$HOME/.config/hypr/$f.pre-lua.$stamp"
  done
}
retire_conf
# Same for a non-Vexyon hyprland.lua (Hyprland >= 0.55 prefers .lua when it
# exists, so an alien one would shadow Vexyon's config entirely).
if [ -f "$HOME/.config/hypr/hyprland.lua" ] && \
   ! grep -q "VEXYON" "$HOME/.config/hypr/hyprland.lua" 2>/dev/null; then
  bak="$HOME/.config/hypr/hyprland.lua.pre-vexyon.$(date +%s)"
  warn "Backing up existing hyprland.lua -> $bak"
  cp "$HOME/.config/hypr/hyprland.lua" "$bak"
fi

# Deploy the code tree but PRESERVE the user's shell.json on re-runs: the
# blanket cp would clobber their settings with the repo seed (the seed-if-
# absent guard below never fired because the cp had already replaced it).
deploy_trees() {
  local user_cfg=""
  if [ -s "$HOME/.config/vexyon/shell.json" ]; then
    user_cfg="$(mktemp)"
    cp "$HOME/.config/vexyon/shell.json" "$user_cfg"
  fi
  cp -r "$SRC/config/vexyon/." "$HOME/.config/vexyon/"
  # bytecode cache del working copy del repo — no desplegarlo
  rm -rf "$HOME/.config/vexyon/bridge/__pycache__"
  if [ -n "$user_cfg" ]; then
    mv "$user_cfg" "$HOME/.config/vexyon/shell.json"
  fi
  cp -r "$SRC/config/hypr/."   "$HOME/.config/hypr/"
  # fish: conf.d/vexyon-theme.fish y conf.d/vexyon-greeting.fish los GENERA el
  # bridge (--oneshot más abajo) desde shell.json; el repo ya no trae config/fish.
  cp -r "$SRC/share/vexyon/."  "$HOME/.local/share/vexyon/"
  # Seed default config if absent (never overwrite a user's edited one)
  if [ ! -s "$HOME/.config/vexyon/shell.json" ]; then
    cp "$SRC/config/vexyon/shell.json" "$HOME/.config/vexyon/shell.json"
  fi
}
step "Deploying shell to ~/.config and ~/.local/share/vexyon" deploy_trees

link_helpers() {
  local f
  for f in "$HOME/.config/vexyon/bin/"*; do
    [ -f "$f" ] || continue
    chmod +x "$f"
    ln -sf "$f" "$HOME/.local/bin/$(basename "$f")"
  done
  chmod +x "$HOME/.config/vexyon/bridge/vexyon-bridge.py"

  # ~/.local/bin en el PATH de las shells interactivas: el shell objetivo es
  # Fish → fish_add_path en config.fish, idempotente (guard por grep, sin
  # duplicar en re-runs; deploy_trees no pisa config.fish — fish solo recibe
  # los conf.d/ que genera el bridge). Los binds de Hyprland (Super+B) NO pasan por fish: su PATH lo
  # cubre vexyon-start (export al arrancar la sesión).
  local fish_cfg="$HOME/.config/fish/config.fish"
  mkdir -p "$HOME/.config/fish"
  [ -f "$fish_cfg" ] || : > "$fish_cfg"
  if ! grep -Eq 'fish_add_path[^#]*\.local/bin' "$fish_cfg"; then
    printf '\n# Vexyon: helper scripts (~/.local/bin) en PATH\nfish_add_path %s/.local/bin\n' "$HOME" >> "$fish_cfg"
  fi
}
step "Linking helper scripts into ~/.local/bin" link_helpers
SUMMARY+=("Shell deployed to ~/.config/vexyon (existing shell.json preserved)")

# Distribución de teclado: Hyprland NO hereda la elegida en el instalador del
# sistema (por defecto "us"). Si shell.json aún no tiene la clave, sembrarla
# desde la config del OS (X11/localectl o vconsole); a partir de ahí manda
# Ajustes → Comportamiento (behavior.keyboardLayout, aplicada por el bridge).
if ! jq -e '.behavior.keyboardLayout' "$HOME/.config/vexyon/shell.json" >/dev/null 2>&1; then
  kb=""
  if [ -f /etc/X11/xorg.conf.d/00-keyboard.conf ]; then
    kb=$(awk -F'"' 'toupper($0) ~ /XKBLAYOUT/ { print $4; exit }' /etc/X11/xorg.conf.d/00-keyboard.conf | cut -d, -f1)
  fi
  if [ -z "$kb" ] && [ -f /etc/vconsole.conf ]; then
    kb=$(sed -n 's/^XKBLAYOUT=//p' /etc/vconsole.conf | tr -d '"' | cut -d, -f1)
    if [ -z "$kb" ]; then
      # KEYMAP de consola: el prefijo suele coincidir con el layout XKB
      # (es, de-latin1 → de); uk es la excepción (XKB usa gb)
      kb=$(sed -n 's/^KEYMAP=//p' /etc/vconsole.conf | tr -d '"' | cut -d- -f1)
      [ "$kb" = "uk" ] && kb=gb
    fi
  fi
  case "$kb" in
    latam|ara|[a-z][a-z]) : ;;   # códigos XKB plausibles; el resto se descarta
    *) kb="" ;;
  esac
  if [ -n "$kb" ] && [ "$kb" != "us" ]; then
    tmp_kb=$(mktemp)
    if jq --arg kb "$kb" '.behavior.keyboardLayout = $kb' \
         "$HOME/.config/vexyon/shell.json" > "$tmp_kb" 2>/dev/null && [ -s "$tmp_kb" ]; then
      mv "$tmp_kb" "$HOME/.config/vexyon/shell.json"
      note "Keyboard layout seeded from the system: $kb (Settings → Behavior to change)"
    else
      rm -f "$tmp_kb"
    fi
  fi
fi

# Binds NUEVOS: instalaciones previas conservan su shell.json (no se pisa), así
# que un bind añadido después de su instalación no les llegaría nunca — ni las
# teclas multimedia en su día, ni ahora Super+V para el gestor de VMs. Sembrar
# UNA vez cada bind de la lista cuyo id no exista aún — sin tocar nada más y
# saltando combos que el usuario ya use para otra cosa.
#
# La lista es EXPLÍCITA a propósito: sembrar "todo default que falte" devolvería
# a la vida cualquier bind que el usuario haya borrado a conciencia.
seed_media_keybinds() {
  python3 - "$HOME/.config/vexyon/shell.json" \
             "$HOME/.local/share/vexyon/defaults/keybinds.json" <<'PYEOF'
import json, os, sys
sj, dk = sys.argv[1], sys.argv[2]
cfg = json.load(open(sj))
defaults = json.load(open(dk))
kbs = cfg.setdefault("keybinds", [])
before = list((cfg.get("state") or {}).get("migrations") or []) if isinstance(cfg.get("state"), dict) else []
have_ids = {k.get("id") for k in kbs}
combos = {(tuple(sorted(k.get("mods", []))), k.get("key")) for k in kbs}
# 3.0: the recorder's default moved from Super+Shift+R to Super+Shift+V.
# An existing bind moves only while it still sits on the old default and V is
# free, and only once: a later deliberate choice of R is never undone.
MIG = "recorder-super-shift-v"
state = cfg.get("state")
if not isinstance(state, dict):
    state = cfg["state"] = {}
done = state.get("migrations")
if not isinstance(done, list):
    done = state["migrations"] = []
moved = False
if MIG not in done:
    for k in kbs:
        if k.get("id") == "recorder" and sorted(k.get("mods", [])) == ["SHIFT", "SUPER"] and k.get("key") == "R":
            if (("SHIFT", "SUPER"), "V") not in combos:
                k["key"] = "V"
                moved = True
            break
    done.append(MIG)
    combos = {(tuple(sorted(k.get("mods", []))), k.get("key")) for k in kbs}
added = []
LATE = {"vmmanager", "calculator", "recorder"}  # ids anadidos despues de la primera version
for k in defaults:
    if k.get("category") != "Media" and k.get("id") not in LATE:
        continue
    if k.get("id") in have_ids:
        continue
    if (tuple(sorted(k.get("mods", []))), k.get("key")) in combos:
        continue  # el usuario ya usa esa tecla para otra cosa
    kbs.append(k)
    added.append(k["id"])
if added or MIG not in before:
    tmp = sj + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, sj)
    if added:
        print("seeded: " + ", ".join(added))
    if moved:
        print("recorder moved from Super+Shift+R to Super+Shift+V")
PYEOF
}
try_step "Seeding new keybinds (media keys, Super+V VM manager, Super+Shift+C calculator, Super+Shift+V recorder)" \
  "shell.json unreadable — skipped" \
  seed_media_keybinds

# --- Theme & config generation ---------------------------------------------
section "Theme & config generation"

# Pre-genera el fondo por defecto del tema activo para que el primer arranque
# nunca quede sin fondo (el seed behavior.wallpaper = "vexyon:default" hace
# que el servicio Wallpaper lo aplique al entrar en sesión; aquí solo se
# calienta el cache). Fuera de sesión el generador cae a 2560x1440; al primer
# login se regenera a la resolución real del monitor (clave distinta de cache).
try_step "Pre-generating the default wallpaper" \
  "python-pillow missing? — will retry at login" \
  python3 "$HOME/.config/vexyon/bin/vexyon-wallpaper-gen"

try_step "Generating Hyprland keybinds/settings from shell.json" \
  "ok if not in a session yet" \
  python3 "$HOME/.config/vexyon/bridge/vexyon-bridge.py" --oneshot

# --- GPU: pin DINÁMICO del shell a la GPU integrada -------------------------
# Requisito: en híbridas (iGPU + Nvidia) el shell corre SIEMPRE en la iGPU y
# la dGPU duerme; al conectar en caliente un monitor externo cableado a la
# dGPU la sesión reacciona SOLA (sin reboot ni re-login): udev dispara
# vexyon-gpu-hotplug, que levanta el pin y reinicia únicamente el compositor
# (vexyon-start lo relanza dentro de la MISMA sesión de login; el greeter lo
# respawnea greetd). Al desenchufar, el mismo camino vuelve al pin de iGPU.
# La decisión vive en config/vexyon/bin/vexyon-gpu-detect (COMPARTIDA entre
# este instalador y el handler): sysfs, boot_vga/vendor ranking, Nvidia nunca
# candidata, y estado de conectores para el modo actual.
#
# El número /dev/dri/cardN NO es estable entre boots y las rutas by-path
# llevan ':' — ilegal en AQ_DRM_DEVICES (separador). Solución de la wiki de
# Hyprland: regla udev con symlink estable por slot PCI /dev/dri/vexyon-igpu.
#
# El pin es SOLO del entorno de la sesión: prime-run/DRI_PRIME del usuario
# siguen funcionando (prime-run pisa las tres vars de Nvidia por aplicación).
section "GPU"
GPU_LINK="${VEXYON_GPU_LINK:-/dev/dri/vexyon-igpu}"
GPU_RULE=/etc/udev/rules.d/90-vexyon-gpu.rules
GPU_HOT_RULE=/etc/udev/rules.d/91-vexyon-gpu-hotplug.rules
GPU_LUA="$HOME/.config/hypr/vexyon-gpu.lua"
GPU_DETECT="$SRC/config/vexyon/bin/vexyon-gpu-detect"

# NUNCA eval-ear la salida a ciegas: si detect falla (p.ej. sin +x tras un
# upload web, sysfs raro), el subshell hereda el trap ERR (set -E) y su banner
# "✗ Install aborted (exit N)…" sale por STDOUT → eval lo parsearía como
# código ("error de sintaxis cerca de `('" — el crash real reportado).
# Comprobar rc + salida no vacía; el pin de GPU no es critical-path.
gpu_rc=0
gpu_env="$("$GPU_DETECT" env 2>>"$LOG")" || gpu_rc=$?
if [ "$gpu_rc" -eq 0 ] && [ -n "$gpu_env" ]; then
  eval "$gpu_env"   # VEXYON_GPU_MODE/_WHY/_SLOT/_CARD/_NAME/_NVIDIA
  # El conf se escribe ANTES de instalar reglas: el `udevadm trigger` de abajo
  # dispara el handler, que compara contra este conf y sale sin hacer nada.
  "$GPU_DETECT" lua > "$GPU_LUA"
else
  warn "GPU: vexyon-gpu-detect failed (exit $gpu_rc) — GPU pinning skipped, default device selection will be used"
  VEXYON_GPU_MODE=detect-failed
  VEXYON_GPU_WHY="vexyon-gpu-detect failed (exit $gpu_rc)"
  VEXYON_GPU_NVIDIA=0
  {
    echo "-- Vexyon — GPU pin (GENERATED; do not edit — managed by install.sh and"
    echo "-- vexyon-gpu-hotplug, which rewrites it on iGPU/dGPU display hotplug)"
    echo "-- No GPU pin: $VEXYON_GPU_WHY"
  } > "$GPU_LUA"
fi

case "$VEXYON_GPU_MODE" in
  pin|nopin-external)
    install_gpu_dynamic() {
      sudo install -Dm755 "$GPU_DETECT" /usr/local/bin/vexyon-gpu-detect
      sudo install -Dm755 "$SRC/config/vexyon/bin/vexyon-gpu-hotplug" /usr/local/bin/vexyon-gpu-hotplug
      printf 'SUBSYSTEM=="drm", SUBSYSTEMS=="pci", KERNEL=="card[0-9]*", KERNELS=="%s", SYMLINK+="dri/vexyon-igpu"\n' \
        "$VEXYON_GPU_SLOT" | sudo tee "$GPU_RULE" >/dev/null
      # Reacción al hotplug: un cambio de conectores en CUALQUIER card corre
      # el handler (one-shot, con el $HOME del usuario horneado). Sin filtro
      # HOTPLUG: el handler es barato e idempotente, mejor no perder eventos.
      printf 'ACTION=="change", SUBSYSTEM=="drm", KERNEL=="card[0-9]*", RUN+="/usr/local/bin/vexyon-gpu-hotplug %s"\n' \
        "$HOME" | sudo tee "$GPU_HOT_RULE" >/dev/null
      sudo udevadm control --reload
      sudo udevadm trigger /sys/class/drm/"$VEXYON_GPU_CARD"   # crea el symlink ya
      udevadm settle --timeout=5 2>/dev/null || true
      [ -e "$GPU_LINK" ]
    }
    try_step "GPU pin + hotplug handler ($GPU_LINK -> $VEXYON_GPU_NAME @ $VEXYON_GPU_SLOT)" \
      "pin skipped this run" install_gpu_dynamic
    if [ -e "$GPU_LINK" ]; then
      if [ "$VEXYON_GPU_MODE" = pin ]; then
        SUMMARY+=("GPU: shell pinned to the integrated $VEXYON_GPU_NAME GPU ($VEXYON_GPU_SLOT); display hotplug handled by udev")
      else
        note "GPU: a display is connected to the discrete GPU right now — pin lifted for this state"
        SUMMARY+=("GPU: external display on the discrete GPU — pin lifted; reverts automatically on unplug")
      fi
    else
      # sin symlink, un pin dejaría la sesión sin GPU: degradar
      {
        echo "-- Vexyon — GPU pin (GENERATED; do not edit — managed by install.sh and"
        echo "-- vexyon-gpu-hotplug, which rewrites it on iGPU/dGPU display hotplug)"
        echo "-- No GPU pin: udev symlink $GPU_LINK did not appear — pin skipped to avoid a session with no GPU"
      } > "$GPU_LUA"
      SUMMARY+=("GPU: no pin (udev symlink $GPU_LINK did not appear)")
    fi
    ;;
  static-nvidia)
    warn "GPU: displays run on the Nvidia dGPU — iGPU pin skipped (shell will use the dGPU)"
    SUMMARY+=("GPU: no pin ($VEXYON_GPU_WHY)")
    ;;
  static-none)
    warn "GPU: could not identify an integrated GPU — pin skipped"
    SUMMARY+=("GPU: no pin ($VEXYON_GPU_WHY)")
    ;;
  detect-failed)
    # aviso ya emitido arriba; NO tocar reglas udev existentes (el fallo puede
    # ser transitorio y una híbrida ya instalada no debe perder su pin)
    SUMMARY+=("GPU: no pin ($VEXYON_GPU_WHY)")
    ;;
  *)
    note "GPU: single GPU (or none) — no pin needed, no hotplug machinery installed"
    SUMMARY+=("GPU: no pin ($VEXYON_GPU_WHY)")
    ;;
esac
if [[ "$VEXYON_GPU_MODE" == static-* ]]; then
  # reglas rancias de un hardware anterior: fuera (el symlink dejaría de casar
  # y el handler de hotplug no pinta nada en una máquina no híbrida)
  sudo rm -f "$GPU_RULE" "$GPU_HOT_RULE" /usr/local/bin/vexyon-gpu-hotplug
  sudo udevadm control --reload
fi

# --- Greeter (greetd) -------------------------------------------------------
# Pantalla de login gráfica de Vexyon: greetd + Hyprland kiosco + greeter
# Quickshell propio. Corre ANTES de la sesión de usuario (como el usuario
# `greeter`), así que todo lo que necesita vive en /etc/greetd/vexyon-greeter:
#   shell.qml      el greeter (Quickshell.Services.Greetd)
#   hyprland.lua   compositor kiosco que lo lanza (Lua root, Hyprland >= 0.55)
#   theme.json     snapshot estático del tema — propiedad del usuario: el
#                  bridge lo re-sincroniza solo al cambiar de tema (manual:
#                  vexyon-greeter-sync-theme)
#   cursor.lua     tema de cursor — también propiedad del usuario, mismo motivo
#   greeter.json   usuario por defecto
# Desactivable con VEXYON_GREETER=0 (deja el login por TTY/lo que hubiera).
if [ "${VEXYON_GREETER:-1}" != "0" ]; then
  section "Login screen (greetd)"
  if command -v pacman >/dev/null 2>&1; then
    if ! pacman -Q greetd >/dev/null 2>&1; then
      step "Installing greetd (pacman)" sudo pacman -S --noconfirm --needed greetd
    fi
  fi
  # theme snapshot: el tema activo del usuario si existe; si no, el seed
  greeter_theme="$SRC/config/greeter/theme.json"
  active_theme=$(jq -r '.theme.active // empty' "$HOME/.config/vexyon/shell.json" 2>/dev/null || true)
  if [ -n "$active_theme" ] && [ -f "$HOME/.local/share/vexyon/themes/$active_theme.json" ]; then
    greeter_theme="$HOME/.local/share/vexyon/themes/$active_theme.json"
  fi
  # idioma del greeter: el del shell (appearance.language); default inglés
  greeter_lang=$(jq -r '.appearance.language // "en"' "$HOME/.config/vexyon/shell.json" 2>/dev/null || echo en)
  [ "$greeter_lang" = "es" ] || greeter_lang="en"
  # teclado del greeter = el de la sesión (la contraseña debe teclearse igual)
  greeter_kb=$(jq -r '.behavior.keyboardLayout // "us"' "$HOME/.config/vexyon/shell.json" 2>/dev/null || echo us)
  case "$greeter_kb" in latam|ara|[a-z][a-z]) : ;; *) greeter_kb=us ;; esac
  # config.toml de greetd: respeta uno ajeno (backup), instala el de Vexyon
  if [ -f /etc/greetd/config.toml ] && ! grep -q "Vexyon greeter" /etc/greetd/config.toml; then
    warn "Backing up existing /etc/greetd/config.toml -> config.toml.pre-vexyon"
    sudo cp /etc/greetd/config.toml /etc/greetd/config.toml.pre-vexyon
  fi
  install_greeter() {
    # Kiosco en Lua (greetd lanza --config .../hyprland.lua). La sustitución
    # de kb_layout conserva las comillas y la coma de la gramática Lua.
    local kconf; kconf=$(mktemp)
    sed "s/^\([[:space:]]*kb_layout = \).*/\1\"${greeter_kb}\",/" \
      "$SRC/config/greeter/hyprland-greeter.lua" > "$kconf"
    sudo install -Dm644 "$SRC/config/greeter/shell.qml" /etc/greetd/vexyon-greeter/shell.qml
    # El kiosco usa el MISMO pin de GPU que la sesión, como fichero APARTE
    # (hyprland-greeter.lua lo requiere): vexyon-gpu-hotplug lo reescribe en
    # caliente sin tocar el resto de la config del kiosco. Siempre existe —
    # en máquinas de una GPU es un comentario informativo.
    sudo install -Dm644 "$GPU_LUA" /etc/greetd/vexyon-greeter/vexyon-gpu.lua
    # Restos de instalaciones anteriores a la migración Lua: ya no los lee nadie
    sudo rm -f /etc/greetd/vexyon-greeter/hyprland.conf \
               /etc/greetd/vexyon-greeter/vexyon-gpu.conf
    sudo install -Dm644 "$kconf" /etc/greetd/vexyon-greeter/hyprland.lua
    rm -f "$kconf"
    # theme.json queda PROPIEDAD DEL USUARIO (el dir sigue siendo de root):
    # así el bridge lo re-sincroniza solo en cada cambio de tema, sin sudo y
    # sin demonios nuevos. Solo contiene colores; el greeter lo parsea con
    # fallback, un contenido raro como mucho re-colorea el login.
    sudo install -Dm644 -o "$USER" "$greeter_theme" /etc/greetd/vexyon-greeter/theme.json
    # cursor.lua: mismo trato que theme.json (propiedad del usuario) para que el
    # bridge lo reescriba sin sudo en cada cambio de cursor. Se siembra con la
    # elección actual del usuario; hyprland-greeter.lua lo carga con pcall, así
    # que un fichero ausente o raro nunca tumba el login.
    greeter_cursor=$(jq -r '.appearance.cursorTheme // "pretty"' "$HOME/.config/vexyon/shell.json" 2>/dev/null || echo pretty)
    case "$greeter_cursor" in
      default|system) greeter_cursor_theme="Adwaita" ;;
      black)          greeter_cursor_theme="breeze_cursors" ;;
      dmz)            greeter_cursor_theme="Vanilla-DMZ" ;;
      capitaine)      greeter_cursor_theme="capitaine-cursors" ;;
      *)              greeter_cursor_theme="Breeze_Light" ;;
    esac
    printf -- '-- Vexyon — greeter cursor (GENERATED by install.sh)\nhl.env("XCURSOR_THEME", "%s")\nhl.env("XCURSOR_SIZE", "24")\n' \
      "$greeter_cursor_theme" | sudo tee /etc/greetd/vexyon-greeter/cursor.lua >/dev/null
    sudo chown "$USER" /etc/greetd/vexyon-greeter/cursor.lua
    printf '{ "user": "%s", "lang": "%s" }\n' "$USER" "$greeter_lang" | sudo tee /etc/greetd/vexyon-greeter/greeter.json >/dev/null
    sudo install -Dm644 "$SRC/config/greetd/config.toml" /etc/greetd/config.toml
    # Sesión Vexyon: vexyon-start en un PATH de sistema (el Exec= de un .desktop
    # de sesión no puede depender de ~/.local/bin) + entrada en wayland-sessions
    # para que el greeter la ofrezca. vexyon-start pasa por start-hyprland
    # (watchdog de Hyprland >= 0.51) — sin el aviso de binario lanzado a pelo.
    sudo install -Dm755 "$SRC/config/vexyon/bin/vexyon-start" /usr/local/bin/vexyon-start
    sudo install -Dm644 "$SRC/config/greetd/vexyon.desktop" /usr/share/wayland-sessions/vexyon.desktop
  }
  step "Installing greeter files (/etc/greetd, wayland-sessions)" install_greeter
  # greetd sustituye a getty en el VT1 (Conflicts=getty@tty1 en su unit).
  # Si tenías autologin en tty1, deja de aplicar: el login pasa por el greeter.
  step "Enabling greetd.service" sudo systemctl enable greetd.service
  SUMMARY+=("Login screen: greetd enabled — the Vexyon greeter appears on next boot")
else
  note "VEXYON_GREETER=0 — login screen left untouched"
fi

# --- Summary ----------------------------------------------------------------
section "Done"
for s in "${SUMMARY[@]}"; do ok "$s"; done
if command -v fish >/dev/null 2>&1 && [ "${SHELL##*/}" != "fish" ]; then
  note "Fish is installed. Set it as your login shell with:  chsh -s $(command -v fish)"
fi
if [ "$WARNINGS" -gt 0 ]; then
  warn "$WARNINGS warning(s) above — details in $LOG"
fi

printf '\n  %sNext steps%s\n' "$C_B" "$C_0"
note 'Reboot — the Vexyon login screen appears; pick the "Vexyon" session and log in.'
if [ "$LOGIN_AGAIN" = 1 ]; then
  note "You were added to the libvirt group: it applies from your next login (the reboot covers it)."
fi
note "Or start it from a TTY with:  vexyon-start"
if [ "${VEXYON_GPU_NVIDIA:-0}" = 1 ] && [ "${VEXYON_GPU_MODE:-}" = pin ]; then
  note "Verify the iGPU pin afterwards:  nvidia-smi  (no Hyprland/quickshell process expected)"
fi
printf '\n  %sFull install log: %s%s\n\n' "$C_D" "$LOG" "$C_0"
