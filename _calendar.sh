#!/bin/bash
# Render current month's daily-note activity as an ASCII calendar.
# Usage: ./_calendar.sh [YYYY] [MM]

DAILY_ROOT="palace/notes/management/daily"

YEAR=${1:-$(date +%Y)}
MONTH=${2:-$(date +%m)}
MONTH=$(printf "%02d" "$((10#$MONTH))")

DIR="$DAILY_ROOT/$YEAR/$MONTH"

MONTH_NAME=$(date -j -f "%Y-%m-%d" "$YEAR-$MONTH-01" "+%B %Y")
LAST_DAY=$(cal "$((10#$MONTH))" "$YEAR" | awk 'NF{d=$NF} END{print d}')
FIRST_DOW=$(date -j -f "%Y-%m-%d" "$YEAR-$MONTH-01" "+%u")

declare -a SIZES
for ((d=1; d<=LAST_DAY; d++)); do
    f=$(printf "%s/%s-%s-%02d.md" "$DIR" "$YEAR" "$MONTH" "$d")
    if [ -f "$f" ]; then
        SIZES[$d]=$(stat -f%z "$f" 2>/dev/null || echo 0)
    else
        SIZES[$d]=0
    fi
done

sym() {
    local s=$1
    if   [ "$s" -eq 0 ];      then printf "·"
    elif [ "$s" -lt 1024 ];   then printf "░"
    elif [ "$s" -lt 4096 ];   then printf "▒"
    elif [ "$s" -lt 10240 ];  then printf "▓"
    else                           printf "█"
    fi
}

declare -a CELLS
for ((i=0; i<42; i++)); do CELLS[$i]=0; done
for ((d=1; d<=LAST_DAY; d++)); do
    CELLS[$((FIRST_DOW - 1 + d - 1))]=$d
done
NUM_CELLS=$((FIRST_DOW - 1 + LAST_DAY))
NUM_WEEKS=$(( (NUM_CELLS + 6) / 7 ))

printf "\n              %s\n" "$MONTH_NAME"
printf "      Mo Tu We Th Fr Sa Su\n"

for ((w=0; w<NUM_WEEKS; w++)); do
    printf "     "
    for ((dow=0; dow<7; dow++)); do
        d=${CELLS[$((w*7 + dow))]}
        if [ "$d" -eq 0 ]; then printf "   "
        else                    printf "%3d" "$d"
        fi
    done
    printf "\n     "
    for ((dow=0; dow<7; dow++)); do
        d=${CELLS[$((w*7 + dow))]}
        if [ "$d" -eq 0 ]; then
            printf "   "
        else
            printf "  "
            sym "${SIZES[$d]}"
        fi
    done
    printf "\n"
done

printf "\n     Legend:  ·  empty   ░ <1KB   ▒ 1–4KB   ▓ 4–10KB   █ >10KB\n"

days_written=0; total=0; longest=0; run=0; best_size=0; best_day=0
for ((d=1; d<=LAST_DAY; d++)); do
    s=${SIZES[$d]}
    if [ "$s" -gt 0 ]; then
        days_written=$((days_written + 1))
        total=$((total + s))
        run=$((run + 1))
        [ $run -gt $longest ] && longest=$run
        if [ "$s" -gt "$best_size" ]; then best_size=$s; best_day=$d; fi
    else
        run=0
    fi
done

end=$LAST_DAY
[ "$YEAR-$MONTH" = "$(date +%Y-%m)" ] && end=$((10#$(date +%d)))
current_run=0
for ((d=end; d>=1; d--)); do
    if [ "${SIZES[$d]}" -gt 0 ]; then current_run=$((current_run + 1)); else break; fi
done

fmt() {
    awk -v b="$1" 'BEGIN{
        if (b<1024) printf "%d B", b;
        else if (b<1048576) printf "%.1f KB", b/1024;
        else printf "%.2f MB", b/1048576;
    }'
}

pct=0
[ $LAST_DAY -gt 0 ] && pct=$(( days_written * 100 / LAST_DAY ))

printf "\n     ── Stats ─────────────────────────\n"
printf "     Days written : %d / %d   (%d%%)\n" "$days_written" "$LAST_DAY" "$pct"
printf "     Total        : %s\n" "$(fmt "$total")"
if [ "$days_written" -gt 0 ]; then
    printf "     Avg / day    : %s\n" "$(fmt $((total / days_written)))"
else
    printf "     Avg / day    : —\n"
fi
printf "     Longest run  : %d days\n" "$longest"
printf "     Current run  : %d days\n" "$current_run"
if [ "$best_day" -gt 0 ]; then
    printf "     Best day     : %s %d   (%s)\n" \
        "$(date -j -f "%Y-%m-%d" "$YEAR-$MONTH-$(printf %02d $best_day)" "+%b")" \
        "$best_day" "$(fmt "$best_size")"
fi
printf "\n"
