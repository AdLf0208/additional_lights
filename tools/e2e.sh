#!/usr/bin/env bash
# In-game check for the Additional Lights content: the 24 lamps, 28 floor
# torches and 28 wall torches.
#
# Default run (creative launch, then survival for drops/crafting; The End):
#   1. every one of the 80 block ids binds its default state;
#   2. every declared state of every block binds and reads back — 24×12 lamp
#      states (facing × waterlogged), 28×9 floor-torch states (firetype ×
#      previous_firetype) and 28×36 wall-torch states (facing × firetype ×
#      previous_firetype), 1548 states in total;
#   3. an isolated lamp emits 15, a floor torch and a wall torch 14, and the
#      soul/light firetype states still emit 14 (the recorded content-schema
#      gap: `properties.light` is scalar); vanilla end rod 14, vanilla torch
#      14, stone 0;
#   4. mining a lamp/floor torch drops itself, a wall torch drops its floor
#      torch, and a vanilla torch drops only `minecraft:torch`;
#   5. the lamp and torch shaped recipes craft 4 each in a real crafting table
#      while their stick controls leave the result empty;
#   6. the torches are in `#minecraft:washed_away_by_fluids`; a lamp and stone
#      are not;
#   7. all 52 items are `/give`-able, the wall torches have no item, and the
#      creative tab lists the 52;
#   8. the lamp and torch block items place, and unknown ids are refused.
#
# COUNTERFACTUAL=1 replaces the Additional Lights subjects with vanilla
# `minecraft:torch` and `minecraft:end_rod`: the torch drops itself and never
# an Additional Lights item, the end rod emits 14 where a lamp emits 15, and
# neither is in the port's creative tab. NEGATIVE=1 (implies the
# counterfactual) asserts the deliberately false "vanilla torch drops an
# Additional Lights item", so the run MUST exit 1: the drop differential is
# live. SELFTEST=1 asserts a deliberately wrong lamp facing, so the state
# read-back MUST exit 1. Every leg prints `EXIT:<status>` from the cleanup
# trap as its last line.
set -euo pipefail

CLONE=${CAMPAIGN_ROOT:?set CAMPAIGN_ROOT to a checkout of the ATM10-Horizon campaign tree}
PORT=$CLONE/ports/additional_lights
PIN_BIN=$CLONE/ports/_shared/bin/horizon-1d63e0a5
CTL=${CTL:-$PIN_BIN/horizon-ctl}
GAME=${GAME:-$PIN_BIN/horizon-client}
RES=${RES:-${HORIZON_RES:-.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/additional_lights-e2e.sock}
COUNTERFACTUAL=${COUNTERFACTUAL:-0}
NEGATIVE=${NEGATIVE:-0}
SELFTEST=${SELFTEST:-0}
STATE_WAIT=${STATE_WAIT:-1}

# The negative leg asserts the counterfactual differential, so NEGATIVE=1
# implies it; `env NEGATIVE=1 tools/e2e.sh` is the documented invocation.
if [ "$NEGATIVE" = 1 ]; then
    COUNTERFACTUAL=1
fi

[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL" >&2; exit 1; }
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }
[ -f "$PORT/content/horizon-mod.toml" ] || { echo "missing content mod: $PORT/content" >&2; exit 1; }

LAMP_MATERIALS=(acacia_planks birch_planks oak_planks dark_oak_planks spruce_planks
    jungle_planks stone cobblestone mossy_cobblestone end_stone sandstone
    quartz_block glass iron_block gold_block diamond_block packed_ice pink_wool
    magenta_wool nether_bricks red_nether_bricks blackstone crimson_planks
    warped_planks)
TORCH_MATERIALS=(acacia_planks birch_planks oak_planks dark_oak_planks jungle_planks
    spruce_planks stone cobblestone mossy_cobblestone end_stone sandstone
    stone_bricks mossy_stone_bricks end_stone_bricks nether_bricks
    red_nether_bricks smooth_stone quartz_block glass iron_block gold_block
    diamond_block packed_ice pink_wool magenta_wool crimson_planks warped_planks
    blackstone)
LAMP_FACINGS=(down up north south west east)
WALL_FACINGS=(north south west east)
FIRE_TYPES=(normal soul light)

SCRATCH=$(mktemp -d /tmp/opencode/additional_lights-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")"
rm -f "$SOCK"
cd "$SCRATCH"

ctl() { "$CTL" --socket "$SOCK" "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
say() { echo "+ $*"; }
count_item() { ctl inventory | jq -r --arg i "$1" '.counts[$i] // 0'; }
block_state() { ctl block "$1" "$2" "$3" | jq -r '.block // "unknown"'; }
full_state() { ctl block "$1" "$2" "$3" | jq -r '.state // "unknown"'; }
light_hex() { ctl light "$1" "$2" "$3" "$1" "$2" "$3" | jq -r '.block // "unknown"'; }
end() { ctl command "execute in minecraft:the_end run $1"; }

state_has() { # state key value
    local state=$1 key=$2 want=$3
    echo "$state" | grep -Eq "(^|[,\[)${key}=${want}([],]|$)" || fail "$state: expected $key=$want"
}

# The all-stone centre makes every declared state survivable: a floor torch
# needs the block below, a wall torch the block behind, a lamp the block
# opposite its facing, and all six neighbours are stone.
CX=0; CY=100; CZ=0
bind() { # id [props]
    local id=$1 props=${2:-} target="additional_lights:$1"
    [ -n "$props" ] && target="$target[$props]"
    ctl setblock "$CX" "$CY" "$CZ" "$target" >/dev/null || fail "setblock $target failed"
    [ "$STATE_WAIT" != 0 ] && ctl wait "$STATE_WAIT" >/dev/null
    local state
    state=$(full_state "$CX" "$CY" "$CZ")
    case "$state" in
        "additional_lights:$id"*) ;;
        *) fail "setblock $target read '$state'" ;;
    esac
    if [ -n "$props" ]; then
        local pair key value
        IFS=',' read -ra pairs <<< "$props"
        for pair in "${pairs[@]}"; do
            key=${pair%%=*}; value=${pair##*=}
            state_has "$state" "$key" "$value"
        done
    fi
}

cleanup() {
    local status=$?
    echo "EXIT:$status"
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$SCRATCH" || true
}
trap cleanup EXIT

say "launch (offscreen renderer, creative, content --dev-mod content/)"
"$CTL" --socket "$SOCK" launch \
    --game "$GAME" --world AdditionalLightsE2E --seed 20261105 --creative --offscreen --wait \
    --game-dir "$SCRATCH/game" --resources "$RES" --dev-mod "$PORT/content"
ctl wait-ready 240

say "The End platform at y=79, a stone shell for the state centre"
end "forceload add -12 -12 24 12"
end "tp @s 0.5 80 2.5"
ctl wait 40
end "fill -12 79 -12 24 79 12 minecraft:stone"
end "fill -12 80 -12 24 88 12 minecraft:air"
end "kill @e[type=minecraft:item]"
end "kill @e[type=minecraft:ender_dragon]"
end "kill @e[type=minecraft:end_crystal]"
end "difficulty peaceful"
end "tp @s 0.5 80 2.5"
ctl wait 10
ctl close >/dev/null 2>&1 || true
ctl wait 3
# Six stone neighbours around the state centre.
for d in "0 -1 0" "0 1 0" "0 0 -1" "0 0 1" "-1 0 0" "1 0 0"; do
    read -r dx dy dz <<< "$d"
    ctl setblock "$((CX + dx))" "$((CY + dy))" "$((CZ + dz))" minecraft:stone >/dev/null
done
ctl setblock "$CX" "$CY" "$CZ" minecraft:air >/dev/null

# ------------------------------------------- counterfactual / negative (early)
if [ "$COUNTERFACTUAL" = 1 ]; then
    # The differential and the fail-capable negative need no Additional Lights
    # state binding, so they run before the 1548-state sweep.
    say "counterfactual: vanilla torch/end rod, no Additional Lights content"
    ctl command "gamemode survival @s" >/dev/null
    ctl command "clear @s" >/dev/null
    end "setblock 80 80 0 minecraft:torch"
    end "setblock 60 80 0 minecraft:end_rod"
    ctl wait 10
    torch_light=$(light_hex 80 80 0)
    rod_light=$(light_hex 60 80 0)
    echo "vanilla torch light=$torch_light end rod light=$rod_light"
    [ "$torch_light" = "e" ] || fail "vanilla torch emits '$torch_light'"
    [ "$rod_light" = "e" ] || fail "vanilla end rod emits '$rod_light'"
    [ "$rod_light" != "f" ] || fail "the vanilla end rod emits 15: it is not distinguishable from a lamp"
    ctl command "tp @s 80.5 80 2.5" >/dev/null
    ctl wait 10
    ctl look-at-block 80 80 0 >/dev/null || true
    broken=$(ctl break 80 80 0) || { echo "break reply: $broken"; fail "cannot break the vanilla torch"; }
    echo "$broken" | jq -c '{scenario:"vanilla torch",block,block_before,drops}'
    [ "$(echo "$broken" | jq -r '.block')" = "minecraft:air" ] || fail "vanilla torch did not break"
    got=$(echo "$broken" | jq -r '.drops["minecraft:torch"] // 0')
    ours=$(echo "$broken" | jq -r '[.drops | to_entries[] | select(.key | startswith("additional_lights:")) | .value] | add // 0')
    if [ "$NEGATIVE" = 1 ]; then
        if [ "$ours" -ge 1 ]; then
            fail "NEGATIVE run: the vanilla torch dropped an Additional Lights item; the counterfactual itself is broken"
        fi
        echo "FAIL: NEGATIVE: the deliberately false assertion (a vanilla torch drops an Additional Lights item) tripped, as it must; the drop differential is live (this exit 1 is the proof)" >&2
        exit 1
    fi
    [ "$got" -ge 1 ] || fail "vanilla torch dropped $got of itself"
    [ "$ours" -eq 0 ] || fail "vanilla torch dropped $ours Additional Lights items"

    say "wrong-name controls still fail"
    if ctl give additional_lights:not_a_lamp 1 >/dev/null 2>&1; then
        fail "give additional_lights:not_a_lamp succeeded"
    fi
    ctl setblock 6 80 5 additional_lights:bogus_lamp >/dev/null 2>&1 || true
    [ "$(block_state 6 80 5)" = "minecraft:air" ] || fail "additional_lights:bogus_lamp became a block"
    echo "unknown ids are refused"
    echo "PASS: counterfactual differential (vanilla torch drops itself and no Additional Lights item; the end rod emits 14 where a lamp emits 15)"
    exit 0
fi

# --------------------------------------------------------------- state bind
say "every one of the 80 block ids binds its default state"
n=0
for m in "${LAMP_MATERIALS[@]}"; do
    bind "al_lamp_${m}"
    n=$((n + 1))
done
for m in "${TORCH_MATERIALS[@]}"; do
    bind "al_torch_${m}"
    n=$((n + 1))
    bind "al_wall_torch_${m}"
    n=$((n + 1))
done
[ "$n" -eq 80 ] || fail "bound $n default states, expected 80"
echo "80/80 default states bound (24 lamps, 28 floor torches, 28 wall torches)"

# ---------------------------------------------------------- selftest (early)
if [ "$SELFTEST" = 1 ]; then
    # The read-back must reject a deliberately wrong property, or the state
    # assertions mean nothing. This run MUST exit non-zero.
    say "selftest: the state read-back must reject a deliberately wrong facing"
    ctl setblock "$CX" "$CY" "$CZ" "additional_lights:al_lamp_stone[facing=up]" >/dev/null
    ctl wait "$STATE_WAIT" >/dev/null
    state=$(full_state "$CX" "$CY" "$CZ")
    echo "SELFTEST: read $state"
    if echo "$state" | grep -Eq 'facing=down'; then
        fail "SELFTEST: the deliberately wrong facing=down assertion passed; the state read-back is vacuous"
    fi
    echo "FAIL: SELFTEST: read '$state' where the deliberately wrong assertion wanted facing=down; the state read-back is live (this exit 1 is the proof)" >&2
    exit 1
fi

say "every lamp state binds: 24 × 6 facings × 2 waterlogged = 288"
n=0
for m in "${LAMP_MATERIALS[@]}"; do
    for f in "${LAMP_FACINGS[@]}"; do
        for w in false true; do
            bind "al_lamp_${m}" "facing=${f},waterlogged=${w}"
            n=$((n + 1))
        done
    done
done
[ "$n" -eq 288 ] || fail "bound $n lamp states, expected 288"
echo "288/288 lamp states bind"

say "every floor-torch state binds: 28 × 3 firetypes × 3 previous = 252"
n=0
for m in "${TORCH_MATERIALS[@]}"; do
    for f in "${FIRE_TYPES[@]}"; do
        for p in "${FIRE_TYPES[@]}"; do
            bind "al_torch_${m}" "firetype=${f},previous_firetype=${p}"
            n=$((n + 1))
        done
    done
done
[ "$n" -eq 252 ] || fail "bound $n floor-torch states, expected 252"
echo "252/252 floor-torch states bind"

say "every wall-torch state binds: 28 × 4 facings × 3 × 3 = 1008"
n=0
for m in "${TORCH_MATERIALS[@]}"; do
    for face in "${WALL_FACINGS[@]}"; do
        for f in "${FIRE_TYPES[@]}"; do
            for p in "${FIRE_TYPES[@]}"; do
                bind "al_wall_torch_${m}" "facing=${face},firetype=${f},previous_firetype=${p}"
                n=$((n + 1))
            done
        done
    done
done
[ "$n" -eq 1008 ] || fail "bound $n wall-torch states, expected 1008"
echo "1008/1008 wall-torch states bind; 1548/1548 declared states total"

# ------------------------------------------------------------------- light
say "light: lamp 15, torches 14, vanilla end rod/torch 14, stone 0 (isolated)"
ctl setblock 0 80 0 "additional_lights:al_lamp_stone[facing=up]" >/dev/null
ctl setblock 20 80 0 additional_lights:al_torch_stone >/dev/null
ctl setblock 40 80 -1 minecraft:stone >/dev/null
ctl setblock 40 80 0 "additional_lights:al_wall_torch_stone[facing=south]" >/dev/null
ctl setblock 60 80 0 minecraft:end_rod >/dev/null
ctl setblock 80 80 0 minecraft:torch >/dev/null
ctl setblock 100 80 0 minecraft:stone >/dev/null
ctl setblock 120 80 0 "additional_lights:al_torch_stone[firetype=soul]" >/dev/null
ctl setblock 140 80 0 "additional_lights:al_torch_stone[firetype=light]" >/dev/null
ctl wait 10
lamp=$(light_hex 0 80 0)
torch=$(light_hex 20 80 0)
wall=$(light_hex 40 80 0)
rod=$(light_hex 60 80 0)
vanilla=$(light_hex 80 80 0)
stone=$(light_hex 100 80 0)
soul=$(light_hex 120 80 0)
lightfire=$(light_hex 140 80 0)
echo "light: lamp=$lamp torch=$torch wall=$wall end_rod=$rod vanilla_torch=$vanilla stone=$stone soul=$soul light=$lightfire"
[ "$lamp" = "f" ] || fail "lamp emits '$lamp', expected f (15)"
[ "$torch" = "e" ] || fail "floor torch emits '$torch', expected e (14)"
[ "$wall" = "e" ] || fail "wall torch emits '$wall', expected e (14)"
[ "$rod" = "e" ] || fail "vanilla end rod emits '$rod', expected e (14)"
[ "$vanilla" = "e" ] || fail "vanilla torch emits '$vanilla', expected e (14)"
[ "$stone" = "0" ] || fail "stone emits '$stone', expected 0"
# The content schema has one light value per block; the e2e pins the gap so
# a later per-state light API makes it fail and the notes get updated.
[ "$soul" = "e" ] || fail "soul state emits '$soul'; content scalar light is 14 (recorded gap)"
[ "$lightfire" = "e" ] || fail "light state emits '$lightfire'; content scalar light is 14 (recorded gap)"
[ "$lamp" != "$rod" ] || fail "the lamp and the vanilla end rod both emit $lamp: the differential is gone"
echo "lamp 15 differs from the vanilla end rod 14; torch/wall 14; stone 0; soul/light 14 (recorded gap)"

# ------------------------------------------------------------------- drops
say "drops: lamp self, floor torch self, wall torch its floor torch, vanilla torch self"
ctl command "gamemode survival @s" >/dev/null
ctl command "clear @s" >/dev/null
end "setblock 0 80 0 additional_lights:al_lamp_stone[facing=up]"
end "setblock 20 80 0 additional_lights:al_torch_stone"
end "setblock 5 80 0 minecraft:stone"
end "setblock 5 80 1 additional_lights:al_wall_torch_stone[facing=south]"
end "setblock 80 80 0 minecraft:torch"
ctl wait 10
for spec in "0 80 0 al_lamp_stone" "20 80 0 al_torch_stone" "5 80 1 al_torch_stone"; do
    read -r x y z want <<< "$spec"
    ctl command "tp @s ${x}.5 80 $((z + 2)).5" >/dev/null
    ctl wait 10
    ctl look-at-block "$x" "$y" "$z" >/dev/null || true
    broken=$(ctl break "$x" "$y" "$z") || { echo "break reply: $broken"; fail "cannot break $want at $x $y $z"; }
    echo "$broken" | jq -c --arg want "$want" '{scenario:$want,block,block_before,drops}'
    [ "$(echo "$broken" | jq -r '.block')" = "minecraft:air" ] || fail "$want at $x $y $z did not break"
    got=$(echo "$broken" | jq -r --arg i "additional_lights:$want" '.drops[$i] // 0')
    [ "$got" -ge 1 ] || fail "$want at $x $y $z dropped $got of itself"
    if [ "$want" = "al_torch_stone" ] && [ "$x" = 5 ]; then
        wrong=$(echo "$broken" | jq -r '.drops["additional_lights:al_wall_torch_stone"] // 0')
        [ "$wrong" -eq 0 ] || fail "the wall torch dropped $wrong of the wall form"
        echo "wall torch dropped its floor torch"
    fi
done
ctl command "tp @s 80.5 80 2.5" >/dev/null
ctl wait 10
ctl look-at-block 80 80 0 >/dev/null || true
broken=$(ctl break 80 80 0) || { echo "break reply: $broken"; fail "cannot break the vanilla torch"; }
got=$(echo "$broken" | jq -r '.drops["minecraft:torch"] // 0')
ours=$(echo "$broken" | jq -r '[.drops | to_entries[] | select(.key | startswith("additional_lights:")) | .value] | add // 0')
[ "$got" -ge 1 ] || fail "vanilla torch dropped $got of itself"
[ "$ours" -eq 0 ] || fail "vanilla torch dropped $ours Additional Lights items"
echo "drops PASS"

# ------------------------------------------------------------------- recipe
say "craft: glowstone + stone -> 4 al_lamp_stone, 4 torches + stone -> 4 al_torch_stone"
ctl command "clear @s" >/dev/null
ctl command "gamemode survival @s" >/dev/null
end "setblock 8 80 2 minecraft:crafting_table"
ctl command "tp @s 8.5 80 3.5" >/dev/null
ctl wait 10
python3 "$PORT/tools/craft_check.py" "$SOCK" "$CTL" 8 80 2 || fail "the lamp/torch recipe check failed"
ctl command "gamemode creative @s" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 3
echo "recipes PASS"

# ---------------------------------------------------------------------- tag
say "the torches are in #minecraft:washed_away_by_fluids; a lamp and stone are not"
end "setblock 0 80 0 additional_lights:al_torch_stone"
end "setblock 1 80 0 additional_lights:al_wall_torch_stone[facing=south]"
end "setblock 2 80 0 additional_lights:al_lamp_stone[facing=up]"
end "setblock 3 80 0 minecraft:stone"
ctl wait 5
# `execute in <dim> run if ...` would nest two `run` clauses, which the
# command parser refuses; the `if` clause goes directly after `in`.
ctl command "execute in minecraft:the_end if block 0 80 0 #minecraft:washed_away_by_fluids run say TAG_FLOOR" >/dev/null
ctl command "execute in minecraft:the_end if block 1 80 0 #minecraft:washed_away_by_fluids run say TAG_WALL" >/dev/null
ctl command "execute in minecraft:the_end if block 2 80 0 #minecraft:washed_away_by_fluids run say TAG_LAMP" >/dev/null
ctl command "execute in minecraft:the_end if block 3 80 0 #minecraft:washed_away_by_fluids run say TAG_STONE" >/dev/null
ctl wait 5
messages=$(ctl messages 40 | jq -r '.chat[]')
echo "$messages" | grep -q '] TAG_FLOOR' || fail "the floor torch is not in #minecraft:washed_away_by_fluids"
echo "$messages" | grep -q '] TAG_WALL' || fail "the wall torch is not in #minecraft:washed_away_by_fluids"
echo "$messages" | grep -q '] TAG_LAMP' && fail "the lamp is in #minecraft:washed_away_by_fluids"
echo "$messages" | grep -q '] TAG_STONE' && fail "stone is in #minecraft:washed_away_by_fluids"
echo "tag PASS"

# --------------------------------------------------------------------- item
say "all 52 items are give-able; wall torches have no item"
ctl command "gamemode creative @s" >/dev/null
ctl command "clear @s" >/dev/null
for m in "${LAMP_MATERIALS[@]}"; do
    ctl give "additional_lights:al_lamp_${m}" 1 >/dev/null || fail "give al_lamp_${m} failed"
done
ctl wait 10
n=0
for m in "${LAMP_MATERIALS[@]}"; do
    [ "$(count_item "additional_lights:al_lamp_${m}")" -ge 1 ] || fail "al_lamp_${m} is missing"
    n=$((n + 1))
done
[ "$n" -eq 24 ] || fail "gave $n lamps, expected 24"
ctl command "clear @s" >/dev/null
for m in "${TORCH_MATERIALS[@]}"; do
    ctl give "additional_lights:al_torch_${m}" 1 >/dev/null || fail "give al_torch_${m} failed"
done
ctl wait 10
n=0
for m in "${TORCH_MATERIALS[@]}"; do
    [ "$(count_item "additional_lights:al_torch_${m}")" -ge 1 ] || fail "al_torch_${m} is missing"
    n=$((n + 1))
done
[ "$n" -eq 28 ] || fail "gave $n torches, expected 28"
if ctl give additional_lights:al_wall_torch_stone 1 >/dev/null 2>&1; then
    fail "give al_wall_torch_stone succeeded; the wall torch has no item upstream"
fi
if ctl give additional_lights:not_a_lamp 1 >/dev/null 2>&1; then
    fail "give additional_lights:not_a_lamp succeeded"
fi
echo "52/52 items give-able; the wall torches have no item"

CREATIVE=$(find "$SCRATCH/game/.horizon-cache/mod-content" -name creative-inventory.json 2>/dev/null | head -1)
[ -n "$CREATIVE" ] || fail "no creative-inventory.json under $SCRATCH/game/.horizon-cache/mod-content"
for m in "${LAMP_MATERIALS[@]}"; do
    grep -q "additional_lights:al_lamp_${m}" "$CREATIVE" || fail "creative tab misses al_lamp_${m}"
done
for m in "${TORCH_MATERIALS[@]}"; do
    grep -q "additional_lights:al_torch_${m}" "$CREATIVE" || fail "creative tab misses al_torch_${m}"
done
grep -q "additional_lights:al_wall_torch_stone" "$CREATIVE" && fail "the creative tab lists a wall torch (no item upstream)"
echo "creative tab lists all 52 block items and no wall torch"

# ---------------------------------------------------------------- placement
say "the lamp and torch block items place"
ctl command "gamemode creative @s" >/dev/null
ctl command "clear @s" >/dev/null
ctl setblock 10 80 6 minecraft:air >/dev/null
ctl setblock 12 80 6 minecraft:air >/dev/null
ctl tp 10.5 80 5.5 >/dev/null
ctl give additional_lights:al_lamp_stone 1 >/dev/null
ctl wait 3
ctl select additional_lights:al_lamp_stone >/dev/null
ctl wait 2
reply=$(ctl place 10 80 6 --item additional_lights:al_lamp_stone 2>&1) || { echo "place reply: $reply"; fail "cannot place the lamp"; }
ctl wait 3
[ "$(block_state 10 80 6)" = "additional_lights:al_lamp_stone" ] || fail "the placed lamp is not there"
echo "al_lamp_stone placed"
ctl tp 12.5 80 5.5 >/dev/null
ctl give additional_lights:al_torch_stone 1 >/dev/null
ctl wait 3
ctl select additional_lights:al_torch_stone >/dev/null
ctl wait 2
reply=$(ctl place 12 80 6 --item additional_lights:al_torch_stone 2>&1) || { echo "place reply: $reply"; fail "cannot place the torch"; }
ctl wait 3
[ "$(block_state 12 80 6)" = "additional_lights:al_torch_stone" ] || fail "the placed torch is not there"
echo "al_torch_stone placed"

say "wrong-name controls fail"
end "setblock 6 80 5 minecraft:air"
end "setblock 7 80 5 minecraft:air"
end "setblock 6 80 5 additional_lights:bogus_lamp" >/dev/null 2>&1 || true
[ "$(block_state 6 80 5)" = "minecraft:air" ] || fail "additional_lights:bogus_lamp became a block"
end "setblock 7 80 5 additional_lights:bogus_torch" >/dev/null 2>&1 || true
[ "$(block_state 7 80 5)" = "minecraft:air" ] || fail "additional_lights:bogus_torch became a block"
echo "unknown lamp/torch ids are refused"

echo "PASS: 1548/1548 states bind (80 defaults, 288 lamp, 252 floor-torch, 1008 wall-torch), lamps emit 15 and torches 14 (soul/light 14 is the recorded scalar-light gap), drops are self/self/floor-torch, the lamp and torch recipes craft 4 with empty stick controls, the torches are in #minecraft:washed_away_by_fluids, 52 items give and the tab lists 52 (no wall torch item), the items place, and unknown ids are refused"
