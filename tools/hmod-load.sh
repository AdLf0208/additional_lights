#!/usr/bin/env bash
# Prove the built content package (content/additional_lights.hmod) loads on a
# real game: the shared, unmodded 1d63e0a5 game with `--dev-mod <the .hmod>`
# must register a representative lamp, floor torch and wall torch and their
# items. A second launch of a fresh world WITHOUT --dev-mod is the negative
# control: the same ids must be unknown there, so the check cannot pass
# vacuously.
set -euo pipefail
export LC_ALL=C

CLONE=${CAMPAIGN_ROOT:?set CAMPAIGN_ROOT to a checkout of the ATM10-Horizon campaign tree}
PIN_BIN=$CLONE/ports/_shared/bin/horizon-1d63e0a5
CTL=${CTL:-$PIN_BIN/horizon-ctl}
GAME=${GAME:-$PIN_BIN/horizon-client}
HMOD=${HMOD:-$CLONE/ports/additional_lights/content/additional_lights.hmod}
RES=${RES:-${HORIZON_RES:-.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/additional_lights-hmod-load.sock}

[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL" >&2; exit 1; }
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME" >&2; exit 1; }
[ -f "$HMOD" ] || { echo "missing package: $HMOD" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }

SCRATCH=$(mktemp -d /tmp/opencode/additional_lights-hmod-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")" "$XDG_CONFIG_HOME"
rm -f "$SOCK"
cd "$SCRATCH"

ctl() { "$CTL" --socket "$SOCK" "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

cleanup() {
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$SCRATCH" 2>/dev/null || true
}
trap cleanup EXIT

launch() { # world [extra args...]
    local world=$1; shift
    rm -f "$SOCK"
    "$CTL" --socket "$SOCK" launch \
        --game "$GAME" --world "$world" --seed 20261109 --creative --headless --wait \
        --game-dir "$SCRATCH/game" --resources "$RES" "$@" >/dev/null
    ctl wait-ready 120 >/dev/null
    ctl command "execute in minecraft:the_end run tp @s 0.5 80 2.5" >/dev/null
    ctl wait 20
    ctl command "execute in minecraft:the_end run fill -4 79 -4 8 79 8 minecraft:stone" >/dev/null
    ctl command "execute in minecraft:the_end run fill -4 80 -4 8 88 8 minecraft:air" >/dev/null
    ctl wait 4
}

# x y z block expected-state-prefix [support-x support-z]
LAMP="0 80 0 additional_lights:al_lamp_stone[facing=up] additional_lights:al_lamp_stone"
FLOOR="2 80 0 additional_lights:al_torch_stone additional_lights:al_torch_stone"
WALL="4 80 5 additional_lights:al_wall_torch_stone[facing=south] additional_lights:al_wall_torch_stone"

echo "== launch WITH the package (--dev-mod $HMOD) =="
launch AdditionalLightsHmod --dev-mod "$HMOD"
ctl command "execute in minecraft:the_end run setblock 4 80 4 minecraft:stone" >/dev/null
ctl wait 4
for case_ in "$LAMP" "$FLOOR" "$WALL"; do
    read -r x y z block want <<< "$case_"
    ctl command "execute in minecraft:the_end run setblock $x $y $z $block" >/dev/null
    ctl wait 2
    got=$(ctl block "$x" "$y" "$z" | jq -r '.state // .block // .name // "unknown"')
    echo "block $x,$y,$z = $got"
    case "$got" in
        "$want"*) ;;
        *) fail "the package did not register $block (read '$got')" ;;
    esac
done
ctl give additional_lights:al_lamp_stone 1 >/dev/null
ctl wait 4
ctl inventory | jq -e '[.counts["additional_lights:al_lamp_stone"] // 0] | .[0] >= 1' >/dev/null \
    || fail "the package did not register the al_lamp_stone block item"
echo "item additional_lights:al_lamp_stone = $(ctl inventory | jq -r '.counts["additional_lights:al_lamp_stone"] // 0')"
ctl quit >/dev/null 2>&1 || true
sleep 2

echo "== negative control: the SAME ids without --dev-mod (fresh world) =="
launch AdditionalLightsHmodControl
ctl command "execute in minecraft:the_end run setblock 4 80 4 minecraft:stone" >/dev/null
ctl wait 4
for case_ in "$LAMP" "$FLOOR" "$WALL"; do
    read -r x y z block want <<< "$case_"
    ctl command "execute in minecraft:the_end run setblock $x $y $z $block" >/dev/null 2>&1 || true
    ctl wait 2
    got=$(ctl block "$x" "$y" "$z" | jq -r '.state // .block // .name // "unknown"')
    echo "control block $x,$y,$z = $got"
    [ "$got" = "minecraft:air" ] || fail "$block became '$got' without the package, so the load check is not discriminating"
done
if ctl give additional_lights:al_lamp_stone 1 >/dev/null 2>&1; then
    fail "give additional_lights:al_lamp_stone succeeded without the package"
fi
echo "control: all three ids are unknown without the package"

echo "PASS: the .hmod registers al_lamp_stone, al_torch_stone and al_wall_torch_stone and the lamp item; without it the same ids are refused"
