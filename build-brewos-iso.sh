#!/usr/bin/env bash
# ==============================================================================
# build-brewos-iso.sh - builds the BrewOS v0.1 live ISO
#                       (Artix Linux + runit + i3 + VirtualBox integration)
#
#   Linux with Docker or Podman : sudo ./build-brewos-iso.sh
#   Already running Artix       : sudo ./build-brewos-iso.sh --here
#   Check the generated files   : ./build-brewos-iso.sh --selftest   (no root, no network)
#
# Output : ./out/brewos-<version>-<date>-x86_64.iso, a .sha256 file and build.log
# Needs  : ~25 GB free disk, 4 GB+ RAM, internet (first build downloads ~3-5 GB)
# Options (environment variables):
#   BREWOS_VERSION=0.1   BREWOS_INIT=runit
#   BREWOS_STOCK=1       build the unmodified Artix base ISO instead. A quick way to
#                        tell "the toolchain is broken" from "my customisation is".
# ==============================================================================
set -Eeuo pipefail
trap 'printf "\033[1;31m==> FAILED at line %s: %s\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

BREWOS_VERSION="${BREWOS_VERSION:-0.1}"
PROFILE="${BREWOS_PROFILE:-base}"
INIT="${BREWOS_INIT:-runit}"
IMAGE="${BREWOS_IMAGE:-docker.io/artixlinux/artixlinux:base-devel}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
OUT="${BREWOS_OUT:-$HERE/out}"
WORK="${BREWOS_WORK:-$HERE/work}"

# Added on top of Artix's base live image. If a package is ever renamed, pacman
# stops with "target not found" and tells you which one.
DESKTOP_PKGS=(xorg-server xorg-xinit xf86-input-libinput mesa i3-wm i3status i3lock
              dmenu xterm firefox ttf-dejavu virtualbox-guest-utils nftables)
# runit service packages: installed one by one, best effort (the base may have them)
RUNIT_PKGS=(dbus-runit elogind-runit)

log()  { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m==> WARNING: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m==> ERROR: %s\033[0m\n' "$*" >&2; exit 1; }

put() { # put <mode> <path>   (file content comes from stdin)
    mkdir -p "$(dirname "$2")"
    cat >"$2"
    chmod "$1" "$2"
}

enable_svc() { # enable_svc <image-root> <runit-service-name>
    mkdir -p "$1/etc/runit/runsvdir/default"
    ln -sfn "/etc/runit/sv/$2" "$1/etc/runit/runsvdir/default/$2"
}

# ------------------------------------------------------------------------------
# Everything BrewOS adds to the Artix image lives here, as plain files.
# ------------------------------------------------------------------------------
write_overlay() {
    local r=$1

    put 755 "$r/usr/share/brewos/session" <<'EOF'
#!/bin/sh
# BrewOS desktop session, started by startx (see /etc/profile.d/brewos-session.sh).
# VirtualBox guest integration (shared clipboard, auto-resize); harmless elsewhere.
if command -v VBoxClient-all >/dev/null 2>&1; then
    VBoxClient-all >/dev/null 2>&1 &
fi
exec i3 -c /usr/share/brewos/i3/config
EOF

    put 644 "$r/etc/profile.d/brewos-session.sh" <<'EOF'
# BrewOS: start the desktop automatically when a regular user logs in on tty1.
# If it fails you simply land in a shell and can read the error.
if [ -z "${DISPLAY:-}" ] && [ -z "${SSH_TTY:-}" ] && [ "$(id -u)" -ne 0 ] \
   && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    startx /usr/share/brewos/session -- vt1
fi
EOF

    put 644 "$r/usr/share/brewos/i3/config" <<'EOF'
# BrewOS i3 config (v0.1)
# Alt is the modifier because host operating systems often grab the Super key.
# To use Super/Windows instead, change Mod1 to Mod4 on the next line.
set $mod Mod1

font pango:DejaVu Sans Mono 10
floating_modifier $mod
focus_follows_mouse no
default_border pixel 2
hide_edge_borders smart

# start a terminal so the screen is never empty
exec --no-startup-id xterm

# programs
bindsym $mod+Return exec xterm
bindsym $mod+d exec --no-startup-id dmenu_run
bindsym $mod+b exec firefox
bindsym $mod+Shift+q kill

# focus and move windows
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right
bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right

# layout
bindsym $mod+h split h
bindsym $mod+v split v
bindsym $mod+f fullscreen toggle
bindsym $mod+s layout stacking
bindsym $mod+w layout tabbed
bindsym $mod+e layout toggle split
bindsym $mod+Shift+space floating toggle
bindsym $mod+space focus mode_toggle

# workspaces
bindsym $mod+1 workspace number 1
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace number 3
bindsym $mod+4 workspace number 4
bindsym $mod+5 workspace number 5
bindsym $mod+6 workspace number 6
bindsym $mod+7 workspace number 7
bindsym $mod+8 workspace number 8
bindsym $mod+9 workspace number 9
bindsym $mod+Shift+1 move container to workspace number 1
bindsym $mod+Shift+2 move container to workspace number 2
bindsym $mod+Shift+3 move container to workspace number 3
bindsym $mod+Shift+4 move container to workspace number 4
bindsym $mod+Shift+5 move container to workspace number 5
bindsym $mod+Shift+6 move container to workspace number 6
bindsym $mod+Shift+7 move container to workspace number 7
bindsym $mod+Shift+8 move container to workspace number 8
bindsym $mod+Shift+9 move container to workspace number 9

# session
bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart
bindsym $mod+Shift+e exec "i3-nagbar -t warning -m 'Exit the BrewOS desktop?' -B 'Yes, exit' 'i3-msg exit'"
bindsym $mod+Shift+x exec "i3-nagbar -t warning -m 'Power off?' -B 'Power off' 'sudo poweroff'"

mode "resize" {
    bindsym Left  resize shrink width 10 px or 10 ppt
    bindsym Down  resize grow height 10 px or 10 ppt
    bindsym Up    resize shrink height 10 px or 10 ppt
    bindsym Right resize grow width 10 px or 10 ppt
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+r mode "resize"

bar {
    status_command i3status
    position top
}
EOF

    put 644 "$r/etc/brewos/nftables.conf" <<'EOF'
# BrewOS default firewall: drop unsolicited inbound traffic, allow all outbound.
table inet brewos
delete table inet brewos

table inet brewos {
    chain input {
        type filter hook input priority 0; policy drop;
        ct state invalid drop
        ct state established,related accept
        iifname "lo" accept
        ip protocol icmp icmp type { destination-unreachable, time-exceeded, parameter-problem } accept
        ip6 nexthdr icmpv6 icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, parameter-problem, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept
        udp sport 67 udp dport 68 accept
        udp sport 547 udp dport 546 accept
    }
    chain forward {
        type filter hook forward priority 0; policy drop;
    }
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

    put 755 "$r/etc/runit/sv/brewos-firewall/run" <<'EOF'
#!/bin/sh
# BrewOS firewall: load the default-deny ruleset, then idle so runit leaves it alone.
exec 2>&1
nft -f /etc/brewos/nftables.conf || echo "brewos-firewall: FAILED to load /etc/brewos/nftables.conf"
exec sleep 2147483647
EOF

    put 755 "$r/etc/runit/sv/brewos-vbox/run" <<'EOF'
#!/bin/sh
# BrewOS: VirtualBox guest services (time sync, host integration).
# Idles quietly when not running inside VirtualBox.
exec 2>&1
n=0
while [ ! -c /dev/vboxguest ] && [ "$n" -lt 15 ]; do sleep 1; n=$((n + 1)); done
[ -c /dev/vboxguest ] || exec sleep 86400
exec VBoxService -f
EOF

    put 644 "$r/etc/sysctl.d/99-brewos.conf" <<'EOF'
# BrewOS 0.1 - security and privacy defaults that are safe for desktop use
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
kernel.yama.ptrace_scope = 1
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
fs.suid_dumpable = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.use_tempaddr = 2
net.ipv6.conf.default.use_tempaddr = 2
EOF

    put 644 "$r/usr/lib/firefox/distribution/policies.json" <<'EOF'
{
  "policies": {
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "DisableFormHistory": true,
    "DontCheckDefaultBrowser": true,
    "NoDefaultBookmarks": true,
    "OverrideFirstRunPage": "",
    "OverridePostUpdatePage": "",
    "SearchSuggestEnabled": false,
    "EnableTrackingProtection": {
      "Value": true,
      "Cryptomining": true,
      "Fingerprinting": true
    },
    "FirefoxSuggest": {
      "WebSuggestions": false,
      "SponsoredSuggestions": false,
      "ImproveSuggest": false,
      "Locked": true
    },
    "UserMessaging": {
      "WhatsNew": false,
      "ExtensionRecommendations": false,
      "FeatureRecommendations": false,
      "UrlbarInterventions": false,
      "MoreFromMozilla": false,
      "SkipOnboarding": true
    }
  }
}
EOF

    put 644 "$r/etc/brewos/release" <<EOF
NAME=BrewOS
VERSION=$BREWOS_VERSION
CODENAME=first-pour
BASE=Artix Linux ($INIT)
EOF

    put 644 "$r/etc/motd" <<'EOF'

  BrewOS 0.1 "first pour"  -  Artix + runit + i3
  -----------------------------------------------------------------
  The desktop starts by itself on tty1.  Modifier key: Alt
    Alt+Enter  terminal       Alt+d  launcher        Alt+b  Firefox
    Alt+Shift+q  close        Alt+Shift+e  exit      Alt+Shift+x  power off
  Firewall: inbound blocked by default (nftables).  Telemetry: none.

EOF
}

# ------------------------------------------------------------------------------
# Step 2: customise the system image that buildiso has just created.
# ------------------------------------------------------------------------------
customize_rootfs() {
    local root=$1 made_keyring=0 pkg svc
    log "Step 2/4: adding the BrewOS desktop, firewall and privacy defaults"

    # pacman inside the image needs a keyring: borrow ours for the moment
    if [[ ! -e $root/etc/pacman.d/gnupg ]]; then
        mkdir -p "$root/etc/pacman.d/gnupg"
        tar -C /etc/pacman.d/gnupg --exclude='S.*' -cf - . | tar -C "$root/etc/pacman.d/gnupg" -xf -
        made_keyring=1
    fi

    artix-chroot "$root" pacman -Sy --noconfirm --needed "${DESKTOP_PKGS[@]}"
    for pkg in "${RUNIT_PKGS[@]}"; do
        artix-chroot "$root" pacman -S --noconfirm --needed "$pkg" \
            || warn "optional package $pkg could not be installed; continuing"
    done

    write_overlay "$root"

    enable_svc "$root" brewos-firewall
    enable_svc "$root" brewos-vbox
    for svc in dbus elogind; do
        if [[ -d $root/etc/runit/sv/$svc ]]; then
            enable_svc "$root" "$svc"
        else
            warn "runit service '$svc' not found in the image"
        fi
    done

    # keep the ISO small and do not ship a build-time keyring
    rm -rf "$root"/var/cache/pacman/pkg/*
    if (( made_keyring )); then rm -rf "$root/etc/pacman.d/gnupg"; fi
    return 0
}

collect_iso() {
    local iso dest
    iso=$(find "$HOME/artools-workspace/iso" /var/lib/artools -maxdepth 6 -type f -name '*.iso' \
              -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n1 | cut -d' ' -f2- || true)
    [[ -n ${iso:-} && -f $iso ]] || die "the build finished but no .iso file was found"
    mkdir -p "$OUT"
    dest="$OUT/brewos-${BREWOS_VERSION}-$(date +%Y%m%d)-x86_64.iso"
    cp -f "$iso" "$dest"
    (cd "$OUT" && sha256sum "$(basename "$dest")" > "$(basename "$dest").sha256")
    log "DONE: $dest ($(du -h "$dest" | cut -f1))"
}

ensure_profile() {
    local d
    for d in "$HOME/artools-workspace/iso-profiles" /usr/share/artools/iso-profiles; do
        if [[ -d $d/$PROFILE ]]; then return 0; fi
    done
    warn "profile '$PROFILE' not found locally; fetching Artix's iso-profiles with git"
    mkdir -p "$HOME/artools-workspace"
    git clone --depth 1 https://gitea.artixlinux.org/artix/iso-profiles.git "$HOME/artools-workspace/iso-profiles"
    [[ -d $HOME/artools-workspace/iso-profiles/$PROFILE ]] || die "profile '$PROFILE' is still missing"
}

# ------------------------------------------------------------------------------
# The real build. Runs inside the Artix container (or directly on Artix).
# ------------------------------------------------------------------------------
inside_build() {
    export HOME=/root TERM="${TERM:-xterm}"
    [[ $EUID -eq 0 ]] || die "this step must run as root"
    command -v pacman >/dev/null 2>&1 || die "pacman not found: this step must run on Artix (or in the Artix container)"

    log "Installing the Artix ISO toolchain (artools)"
    pacman -Sy --noconfirm --needed artix-keyring
    pacman -Su --noconfirm
    pacman -S --noconfirm --needed artools-iso git squashfs-tools libisoburn dosfstools mtools grub
    pacman -S --noconfirm --needed iso-profiles || warn "package iso-profiles not available; will use git instead"
    command -v buildiso >/dev/null 2>&1 || die "buildiso is missing after installing artools-iso"
    command -v artix-chroot >/dev/null 2>&1 || die "artix-chroot is missing after installing artools-iso"

    # containers often lack loop device nodes; harmless where they already exist
    local i
    for i in $(seq 0 15); do
        [[ -e /dev/loop$i ]] || mknod -m 0660 "/dev/loop$i" b 7 "$i" 2>/dev/null || true
    done

    ensure_profile

    if [[ ${BREWOS_STOCK:-0} == 1 ]]; then
        log "STOCK mode: building the unmodified Artix '$PROFILE' ISO"
        buildiso -p "$PROFILE" -i "$INIT"
        collect_iso
        return 0
    fi

    log "Step 1/4: building the base system (downloads ~3-5 GB - the slow part)"
    buildiso -p "$PROFILE" -i "$INIT" -x

    local root
    root=$(find /var/lib/artools/buildiso -maxdepth 4 -type d -name rootfs -path "*/$PROFILE/*" 2>/dev/null \
               | sort | head -n1 || true)
    if [[ -z $root || ! -d $root/etc ]]; then
        warn "could not locate the rootfs directory; this is what buildiso created:"
        find /var/lib/artools/buildiso -maxdepth 3 -type d 2>/dev/null | head -40 || true
        die "stopping here: send me those lines and the last 30 lines of build.log"
    fi
    [[ -d $root/etc/runit ]] || warn "$root has no /etc/runit - is INIT='$INIT' what you wanted?"
    log "System image found at $root"

    customize_rootfs "$root"

    log "Step 3/4: compressing the system"
    buildiso -p "$PROFILE" -i "$INIT" -sc
    log "Step 4/4: building the boot files and the ISO"
    buildiso -p "$PROFILE" -i "$INIT" -bc
    buildiso -p "$PROFILE" -i "$INIT" -zc
    collect_iso
}

# ------------------------------------------------------------------------------
# Entry points
# ------------------------------------------------------------------------------
host_mode() {
    [[ $EUID -eq 0 ]] || die "Please run as root:  sudo $0"
    mkdir -p "$OUT" "$WORK"
    exec > >(tee -a "$OUT/build.log") 2>&1
    log "BrewOS $BREWOS_VERSION build started $(date -u +%FT%TZ)"
    modprobe loop 2>/dev/null || true
    modprobe overlay 2>/dev/null || true

    local engine
    engine=$(command -v docker || command -v podman || true)
    [[ -n $engine ]] || die "Docker or Podman is required. (On Artix itself use --here; with no Linux machine use the GitHub workflow.)"
    log "Using $(basename "$engine") with image $IMAGE"

    "$engine" run --rm --privileged \
        -v "$SELF:/brewos/build.sh:ro" \
        -v "$WORK:/var/lib/artools" \
        -v "$OUT:/out" \
        -e "BREWOS_VERSION=$BREWOS_VERSION" -e "BREWOS_PROFILE=$PROFILE" \
        -e "BREWOS_INIT=$INIT" -e "BREWOS_STOCK=${BREWOS_STOCK:-0}" -e "BREWOS_OUT=/out" \
        "$IMAGE" bash /brewos/build.sh --inside

    chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$OUT" 2>/dev/null || true
    log "Finished. Your ISO is in $OUT  (the $WORK folder can be deleted with: sudo rm -rf '$WORK')"
}

here_mode() {
    [[ $EUID -eq 0 ]] || die "Please run as root:  sudo $0 --here"
    [[ -f /etc/artix-release ]] || die "--here only works on Artix Linux"
    mkdir -p "$OUT"
    exec > >(tee -a "$OUT/build.log") 2>&1
    log "BrewOS $BREWOS_VERSION build started on this Artix system $(date -u +%FT%TZ)"
    inside_build
    chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$OUT" 2>/dev/null || true
}

selftest() {
    local t f bad=0
    t=$(mktemp -d)
    trap 'rm -rf "$t"' EXIT
    write_overlay "$t"
    enable_svc "$t" brewos-firewall
    enable_svc "$t" brewos-vbox
    for f in usr/share/brewos/session etc/profile.d/brewos-session.sh \
             etc/runit/sv/brewos-firewall/run etc/runit/sv/brewos-vbox/run; do
        sh -n "$t/$f" || { warn "shell syntax error in $f"; bad=1; }
    done
    if command -v python3 >/dev/null 2>&1; then
        python3 -m json.tool "$t/usr/lib/firefox/distribution/policies.json" >/dev/null \
            || { warn "policies.json is not valid JSON"; bad=1; }
    fi
    if command -v nft >/dev/null 2>&1; then
        nft -c -f "$t/etc/brewos/nftables.conf" || { warn "nftables.conf rejected by nft"; bad=1; }
    fi
    [[ -x $t/etc/runit/sv/brewos-vbox/run && -x $t/usr/share/brewos/session ]] || { warn "missing executable bit"; bad=1; }
    [[ -L $t/etc/runit/runsvdir/default/brewos-firewall ]] || { warn "service link missing"; bad=1; }
    (cd "$t" && find . \( -type f -o -type l \) | sort)
    (( bad == 0 )) || die "selftest failed"
    log "selftest OK"
}

case "${1:-}" in
    --inside)   inside_build ;;
    --here)     here_mode ;;
    --selftest) selftest ;;
    -h|--help)  awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$SELF" ;;
    "")         host_mode ;;
    *)          die "unknown option: $1 (try --help)" ;;
esac
