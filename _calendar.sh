#!/bin/bash
# Render daily-note activity as an ASCII calendar.
# Usage: ./_calendar.sh [-t month|year] [-m MM] [-y YYYY] [--layout git|tab] [-c]

DAILY_ROOT="palace/notes/management/daily"

YEAR=$(date +%Y)
MONTH=$(date +%m)
TYPE="month"
LAYOUT="git"
PLOT=0
POSITIONAL=()

while [ $# -gt 0 ]; do
    case "$1" in
        -c|--current)
            YEAR=$(date +%Y); MONTH=$(date +%m); shift ;;
        -m|--month)
            MONTH="$2"; shift 2 ;;
        -y|--year)
            YEAR="$2"; shift 2 ;;
        -t|--type)
            TYPE="$2"; shift 2 ;;
        --layout)
            LAYOUT="$2"; shift 2 ;;
        -p|--plot)
            PLOT=1; shift ;;
        -h|--help)
            cat <<EOF
Usage: $0 [options]

Render daily-note activity from $DAILY_ROOT
as an ASCII calendar with size-based heatmap.

Options:
  -t, --type    month | year     Statistic scope             (default: month)
  --layout      git | tab        Year layout (year only)     (default: tab)
  -m, --month   MM               Month 1–12                  (default: current)
  -y, --year    YY|YYYY          Year; 2-digit (25 → 2025) ok (default: current)
  -c, --current                  Reset to current month/year
  -p, --plot                     Replace heatmap with ASCII line chart
                                 (month: daily bins, year: 7-day bins)
  -h, --help                     This help

Heatmap (by file size):
  ·  empty    ░ <1KB    ▒ 1–4KB    ▓ 4–10KB    █ >10KB

Positional form (mirrors daily — day is ignored for calendar):
  $0 MM                          month MM, current year
  $0 MM YY                       month MM, year YY (2- or 4-digit)
  $0 DD MM YY                    same as MM YY (day discarded)

Examples:
  $0                             current month
  $0 -m 04                       April of current year
  $0 5 24                        May 2024
  $0 5 10 24                     October 2024 (day discarded)
  $0 -m 12 -y 2025               December 2025
  $0 -t year                     current year, tab layout (current month bold)
  $0 -t year --layout git        current year, GitHub-style heatmap
  $0 -t year -y 2024 --layout git
EOF
            exit 0 ;;
        *)
            POSITIONAL+=("$1"); shift ;;
    esac
done

# Positional shape, mirroring daily but day is ignored (calendar shows
# month/year, not a single day):
#   1 arg : MM
#   2 args: MM YY
#   3 args: DD MM YY   (DD parsed, then dropped)
case ${#POSITIONAL[@]} in
    0) ;;
    1) MONTH="${POSITIONAL[0]}" ;;
    2) MONTH="${POSITIONAL[0]}"; YEAR="${POSITIONAL[1]}" ;;
    3) MONTH="${POSITIONAL[1]}"; YEAR="${POSITIONAL[2]}" ;;
    *) echo "Too many positional args" >&2; exit 1 ;;
esac

MONTH=$(printf "%02d" "$((10#$MONTH))")
case "$YEAR" in
    [0-9][0-9]) YEAR="20$YEAR" ;;
esac

sym() {
    local s=$1
    if   [ "$s" -eq 0 ];      then printf "·"
    elif [ "$s" -lt 1024 ];   then printf "░"
    elif [ "$s" -lt 4096 ];   then printf "▒"
    elif [ "$s" -lt 10240 ];  then printf "▓"
    else                           printf "█"
    fi
}

fmt() {
    awk -v b="$1" 'BEGIN{
        if (b<1024) printf "%d B", b;
        else if (b<1048576) printf "%.1f KB", b/1024;
        else printf "%.2f MB", b/1048576;
    }'
}

# ---------- MONTH MODE ----------

render_month() {
    local YEAR=$1 MONTH=$2
    local DIR="$DAILY_ROOT/$YEAR/$MONTH"
    local MONTH_NAME=$(date -j -f "%Y-%m-%d" "$YEAR-$MONTH-01" "+%B %Y")
    local LAST_DAY=$(cal "$((10#$MONTH))" "$YEAR" | awk 'NF{d=$NF} END{print d}')
    local FIRST_DOW=$(date -j -f "%Y-%m-%d" "$YEAR-$MONTH-01" "+%u")

    declare -a SIZES
    for ((d=1; d<=LAST_DAY; d++)); do
        local f=$(printf "%s/%s-%s-%02d.md" "$DIR" "$YEAR" "$MONTH" "$d")
        if [ -f "$f" ]; then SIZES[$d]=$(stat -f%z "$f" 2>/dev/null || echo 0)
        else SIZES[$d]=0
        fi
    done

    declare -a CELLS
    for ((i=0; i<42; i++)); do CELLS[$i]=0; done
    for ((d=1; d<=LAST_DAY; d++)); do
        CELLS[$((FIRST_DOW - 1 + d - 1))]=$d
    done
    local NUM_CELLS=$((FIRST_DOW - 1 + LAST_DAY))
    local NUM_WEEKS=$(( (NUM_CELLS + 6) / 7 ))

    printf "\n              %s\n" "$MONTH_NAME"
    printf "      Mo Tu We Th Fr Sa Su\n"
    for ((w=0; w<NUM_WEEKS; w++)); do
        printf "     "
        for ((dow=0; dow<7; dow++)); do
            local d=${CELLS[$((w*7 + dow))]}
            if [ "$d" -eq 0 ]; then printf "   "
            else printf "%3d" "$d"
            fi
        done
        printf "\n     "
        for ((dow=0; dow<7; dow++)); do
            local d=${CELLS[$((w*7 + dow))]}
            if [ "$d" -eq 0 ]; then printf "   "
            else printf "  "; sym "${SIZES[$d]}"
            fi
        done
        printf "\n"
    done

    printf "\n     Legend:  ·  empty   ░ <1KB   ▒ 1–4KB   ▓ 4–10KB   █ >10KB\n"

    local days_written=0 total=0 longest=0 run=0 best_size=0 best_day=0
    for ((d=1; d<=LAST_DAY; d++)); do
        local s=${SIZES[$d]}
        if [ "$s" -gt 0 ]; then
            days_written=$((days_written + 1))
            total=$((total + s))
            run=$((run + 1))
            [ $run -gt $longest ] && longest=$run
            if [ "$s" -gt "$best_size" ]; then best_size=$s; best_day=$d; fi
        else run=0
        fi
    done

    local end=$LAST_DAY
    [ "$YEAR-$MONTH" = "$(date +%Y-%m)" ] && end=$((10#$(date +%d)))
    local current_run=0
    for ((d=end; d>=1; d--)); do
        if [ "${SIZES[$d]}" -gt 0 ]; then current_run=$((current_run + 1)); else break; fi
    done

    local pct=0
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
}

# ---------- YEAR MODE ----------
# YSIZE[doy] = bytes;  YLAST[m_n] = last day;  YOFF[m_n] = doy of (m_n,1) - 1

declare -a YSIZE
declare -a YLAST
declare -a YOFF
YTOTAL_DAYS=0

collect_year() {
    local y=$1
    local doy=0
    for m_n in 1 2 3 4 5 6 7 8 9 10 11 12; do
        YOFF[$m_n]=$doy
        local m=$(printf "%02d" "$m_n")
        local last=$(cal "$m_n" "$y" | awk 'NF{d=$NF} END{print d}')
        YLAST[$m_n]=$last
        for ((d=1; d<=last; d++)); do
            local dd=$(printf "%02d" "$d")
            local f="$DAILY_ROOT/$y/$m/$y-$m-$dd.md"
            local sz=0
            [ -f "$f" ] && sz=$(stat -f%z "$f" 2>/dev/null || echo 0)
            doy=$((doy + 1))
            YSIZE[$doy]=$sz
        done
    done
    YTOTAL_DAYS=$doy
}

render_year_tab() {
    local y=$1
    printf "\n                              %d activity\n\n" "$y"
    for m_n in 1 2 3 4 5 6 7 8 9 10 11 12; do
        local m=$(printf "%02d" "$m_n")
        local label=$(date -j -f "%Y-%m-%d" "$y-$m-01" "+%b")
        local last=${YLAST[$m_n]}
        local off=${YOFF[$m_n]}
        local mtotal=0 mdays=0
        local b="" r=""
        if [ "$y-$m" = "$(date +%Y-%m)" ]; then b=$'\033[1m'; r=$'\033[0m'; fi
        printf "%s  %s  " "$b" "$label"
        for ((d=1; d<=last; d++)); do
            local sz=${YSIZE[$((off + d))]:-0}
            sym "$sz"
            printf " "
            if [ "$sz" -gt 0 ]; then
                mtotal=$((mtotal + sz))
                mdays=$((mdays + 1))
            fi
        done
        # pad to align right column: max 31 cells × 2 chars = 62
        local consumed=$((last * 2))
        local padlen=$((62 - consumed))
        printf "%*s   %2d/%d   %s%s\n" "$padlen" "" "$mdays" "$last" "$(fmt "$mtotal")" "$r"
    done
    printf "\n  Legend:  ·  empty   ░ <1KB   ▒ 1–4KB   ▓ 4–10KB   █ >10KB\n"
}

render_year_git() {
    local y=$1
    local jan1_dow=$(date -j -f "%Y-%m-%d" "$y-01-01" "+%u")
    local pad=$((jan1_dow - 1))
    local cells=$((pad + YTOTAL_DAYS))
    local weeks=$(( (cells + 6) / 7 ))

    declare -a YC
    for ((i=0; i<weeks*7; i++)); do YC[$i]=0; done
    declare -a MONTH_COL

    local doy=0
    for m_n in 1 2 3 4 5 6 7 8 9 10 11 12; do
        MONTH_COL[$m_n]=$(( (pad + doy) / 7 ))
        local last=${YLAST[$m_n]}
        for ((d=1; d<=last; d++)); do
            doy=$((doy + 1))
            YC[$((pad + doy - 1))]=$doy
        done
    done

    printf "\n                                       %d activity\n" "$y"
    # month labels: 2 chars per week
    printf "      "
    local printed=0
    for m_n in 1 2 3 4 5 6 7 8 9 10 11 12; do
        local target=$(( MONTH_COL[m_n] * 2 ))
        while [ $printed -lt $target ]; do printf " "; printed=$((printed + 1)); done
        local label=$(date -j -f "%Y-%m-%d" "$y-$(printf %02d $m_n)-01" "+%b")
        printf "%s" "$label"
        printed=$((printed + 3))
    done
    printf "\n"

    local dow_labels=(Mo Tu We Th Fr Sa Su)
    for ((row=0; row<7; row++)); do
        printf "  %s  " "${dow_labels[$row]}"
        for ((c=0; c<weeks; c++)); do
            local idx=$((c * 7 + row))
            local d_idx=${YC[$idx]}
            if [ "$d_idx" -eq 0 ]; then
                printf "  "
            else
                local sz=${YSIZE[$d_idx]:-0}
                sym "$sz"
                printf " "
            fi
        done
        printf "\n"
    done
    printf "\n  Legend:  ·  empty   ░ <1KB   ▒ 1–4KB   ▓ 4–10KB   █ >10KB\n"
}

render_year_stats() {
    local y=$1
    local days_written=0 total=0 longest=0 run=0 best_size=0 best_date=""
    local best_m=0 best_m_total=0 best_m_days=0

    for m_n in 1 2 3 4 5 6 7 8 9 10 11 12; do
        local m=$(printf "%02d" "$m_n")
        local last=${YLAST[$m_n]}
        local off=${YOFF[$m_n]}
        local mt=0 md=0
        for ((d=1; d<=last; d++)); do
            local sz=${YSIZE[$((off + d))]:-0}
            if [ "$sz" -gt 0 ]; then
                days_written=$((days_written + 1))
                total=$((total + sz))
                run=$((run + 1))
                [ $run -gt $longest ] && longest=$run
                if [ "$sz" -gt "$best_size" ]; then
                    best_size=$sz
                    best_date=$(printf "%s-%s-%02d" "$y" "$m" "$d")
                fi
                md=$((md + 1))
                mt=$((mt + sz))
            else
                run=0
            fi
        done
        if [ "$mt" -gt "$best_m_total" ]; then
            best_m_total=$mt; best_m_days=$md; best_m=$m_n
        fi
    done

    local end_doy=$YTOTAL_DAYS
    if [ "$y" = "$(date +%Y)" ]; then end_doy=$((10#$(date "+%j"))); fi
    local current_run=0
    for ((dd=end_doy; dd>=1; dd--)); do
        local sz=${YSIZE[$dd]:-0}
        if [ "$sz" -gt 0 ]; then current_run=$((current_run + 1)); else break; fi
    done

    local pct=0
    [ $YTOTAL_DAYS -gt 0 ] && pct=$((days_written * 100 / YTOTAL_DAYS))

    printf "\n  ── Year stats ───────────────────────────\n"
    printf "  Days written : %d / %d   (%d%%)\n" "$days_written" "$YTOTAL_DAYS" "$pct"
    printf "  Total        : %s\n" "$(fmt "$total")"
    if [ "$days_written" -gt 0 ]; then
        printf "  Avg / day    : %s\n" "$(fmt $((total / days_written)))"
    fi
    printf "  Longest run  : %d days\n" "$longest"
    printf "  Current run  : %d days\n" "$current_run"
    if [ "$best_m" -gt 0 ]; then
        local bm_name=$(date -j -f "%Y-%m-%d" "$y-$(printf %02d $best_m)-01" "+%B")
        printf "  Best month   : %-9s (%d days, %s)\n" "$bm_name" "$best_m_days" "$(fmt "$best_m_total")"
    fi
    if [ -n "$best_date" ]; then
        local bd_label=$(date -j -f "%Y-%m-%d" "$best_date" "+%b %-d")
        printf "  Best day     : %s   (%s)\n" "$bd_label" "$(fmt "$best_size")"
    fi
    printf "\n"
}

# ---------- PLOT MODE ----------

# Render an ASCII line chart from a sequence of integer values.
# Args: MAX WIDTH HEIGHT VAL0 VAL1 ... VAL(W-1)
# Uses box-drawing chars: ┼ ┤ ─ │ ╭ ╮ ╰ ╯
draw_line_chart() {
    local max=$1 W=$2 H=$3
    shift 3
    local values=("$@")
    [ "$max" -le 0 ] && max=1

    local -a ROWS
    local i
    for ((i=0; i<W; i++)); do
        local v=${values[$i]:-0}
        ROWS[$i]=$(( (max - v) * (H - 1) / max ))
    done

    local total=$((H * W))
    local -a GRID
    for ((i=0; i<total; i++)); do GRID[$i]=' '; done

    GRID[$(( ROWS[0] * W + 0 ))]='●'
    for ((i=1; i<W; i++)); do
        local r=${ROWS[$i]} prev=${ROWS[$((i-1))]} rr
        if [ "$prev" -eq "$r" ]; then
            GRID[$((r * W + i))]='─'
        elif [ "$prev" -lt "$r" ]; then
            GRID[$((prev * W + i))]='╮'
            for ((rr=prev+1; rr<r; rr++)); do
                GRID[$((rr * W + i))]='│'
            done
            GRID[$((r * W + i))]='╰'
        else
            GRID[$((prev * W + i))]='╯'
            for ((rr=r+1; rr<prev; rr++)); do
                GRID[$((rr * W + i))]='│'
            done
            GRID[$((r * W + i))]='╭'
        fi
    done

    local r c
    for ((r=0; r<H; r++)); do
        local val=$(( max * (H - 1 - r) / (H - 1) ))
        local label
        label=$(fmt "$val")
        if [ "$r" -eq 0 ]; then
            printf "%9s ┼" "$label"
        else
            printf "%9s ┤" "$label"
        fi
        for ((c=0; c<W; c++)); do
            printf "%s" "${GRID[$((r * W + c))]}"
        done
        printf "\n"
    done
    printf "%9s └" "0"
    for ((c=0; c<W; c++)); do printf "─"; done
    printf "\n"
}

render_plot_month() {
    local YEAR=$1 MONTH=$2
    local DIR="$DAILY_ROOT/$YEAR/$MONTH"
    local LAST_DAY MONTH_NAME
    LAST_DAY=$(cal "$((10#$MONTH))" "$YEAR" \
               | awk 'NF{d=$NF} END{print d}')
    MONTH_NAME=$(date -j -f "%Y-%m-%d" \
                 "$YEAR-$MONTH-01" "+%B %Y")

    local -a SIZES vals
    local max=0 d
    for ((d=1; d<=LAST_DAY; d++)); do
        local f
        f=$(printf "%s/%s-%s-%02d.md" \
            "$DIR" "$YEAR" "$MONTH" "$d")
        if [ -f "$f" ]; then
            SIZES[$d]=$(stat -f%z "$f" 2>/dev/null || echo 0)
        else
            SIZES[$d]=0
        fi
        vals[$((d-1))]=${SIZES[$d]}
        [ "${SIZES[$d]}" -gt "$max" ] && max=${SIZES[$d]}
    done

    printf "\n          %s — daily bytes\n\n" "$MONTH_NAME"
    if [ "$max" -eq 0 ]; then
        printf "          (no data)\n"
    else
        draw_line_chart "$max" "$LAST_DAY" 8 "${vals[@]}"
        printf "%11s" ""
        for ((d=1; d<=LAST_DAY; d++)); do
            if [ "$d" -eq 1 ] || [ $((d % 5)) -eq 0 ]; then
                printf "%d" "$d"
                [ "$d" -ge 10 ] && d=$((d + 1))
            else
                printf " "
            fi
        done
        printf "\n"
    fi

    # Stats (same shape as render_month)
    local days_written=0 total=0 longest=0 run=0
    local best_size=0 best_day=0 s
    for ((d=1; d<=LAST_DAY; d++)); do
        s=${SIZES[$d]}
        if [ "$s" -gt 0 ]; then
            days_written=$((days_written + 1))
            total=$((total + s))
            run=$((run + 1))
            [ $run -gt $longest ] && longest=$run
            if [ "$s" -gt "$best_size" ]; then
                best_size=$s; best_day=$d
            fi
        else run=0
        fi
    done
    local end=$LAST_DAY
    [ "$YEAR-$MONTH" = "$(date +%Y-%m)" ] \
        && end=$((10#$(date +%d)))
    local current_run=0
    for ((d=end; d>=1; d--)); do
        if [ "${SIZES[$d]}" -gt 0 ]; then
            current_run=$((current_run + 1))
        else break
        fi
    done
    local pct=0
    [ $LAST_DAY -gt 0 ] \
        && pct=$(( days_written * 100 / LAST_DAY ))
    printf "\n     ── Stats ─────────────────────────\n"
    printf "     Days written : %d / %d   (%d%%)\n" \
        "$days_written" "$LAST_DAY" "$pct"
    printf "     Total        : %s\n" "$(fmt "$total")"
    if [ "$days_written" -gt 0 ]; then
        printf "     Avg / day    : %s\n" \
            "$(fmt $((total / days_written)))"
    else
        printf "     Avg / day    : —\n"
    fi
    printf "     Longest run  : %d days\n" "$longest"
    printf "     Current run  : %d days\n" "$current_run"
    if [ "$best_day" -gt 0 ]; then
        printf "     Best day     : %s %d   (%s)\n" \
            "$(date -j -f "%Y-%m-%d" \
                "$YEAR-$MONTH-$(printf %02d $best_day)" "+%b")" \
            "$best_day" "$(fmt "$best_size")"
    fi
    printf "\n"
}

# Year plot: bins days into fixed 7-day chunks from Jan 1.
render_plot_year() {
    local y=$1
    local nweeks=$(( (YTOTAL_DAYS + 6) / 7 ))
    local -a WEEK_SUMS vals
    local w
    for ((w=0; w<nweeks; w++)); do WEEK_SUMS[$w]=0; done

    local doy sz
    for ((doy=1; doy<=YTOTAL_DAYS; doy++)); do
        local w_idx=$(( (doy - 1) / 7 ))
        sz=${YSIZE[$doy]:-0}
        WEEK_SUMS[$w_idx]=$((WEEK_SUMS[$w_idx] + sz))
    done

    local max=0
    for ((w=0; w<nweeks; w++)); do
        vals[$w]=${WEEK_SUMS[$w]}
        [ "${WEEK_SUMS[$w]}" -gt "$max" ] && max=${WEEK_SUMS[$w]}
    done

    printf "\n          %d — weekly bytes (7-day bins)\n\n" "$y"
    if [ "$max" -eq 0 ]; then
        printf "          (no data)\n\n"
        return
    fi
    draw_line_chart "$max" "$nweeks" 8 "${vals[@]}"

    # Month labels at the week containing day 1 of each month.
    local -a MONTH_WEEK
    local cum=0 m_n
    for m_n in 1 2 3 4 5 6 7 8 9 10 11 12; do
        MONTH_WEEK[$m_n]=$(( cum / 7 ))
        cum=$((cum + YLAST[m_n]))
    done

    printf "%11s" ""
    local printed=0
    for m_n in 1 2 3 4 5 6 7 8 9 10 11 12; do
        local target=${MONTH_WEEK[$m_n]}
        while [ $printed -lt $target ]; do
            printf " "; printed=$((printed + 1))
        done
        local label
        label=$(date -j -f "%Y-%m-%d" \
                "$y-$(printf %02d $m_n)-01" "+%b")
        printf "%s" "$label"
        printed=$((printed + 3))
    done
    printf "\n"
}

# ---------- DISPATCH ----------

case "$TYPE" in
    month)
        if [ "$PLOT" -eq 1 ]; then
            render_plot_month "$YEAR" "$MONTH"
        else
            render_month "$YEAR" "$MONTH"
        fi
        ;;
    year)
        collect_year "$YEAR"
        if [ "$PLOT" -eq 1 ]; then
            render_plot_year "$YEAR"
        else
            case "$LAYOUT" in
                git) render_year_git "$YEAR" ;;
                tab) render_year_tab "$YEAR" ;;
                *)   echo "Unknown layout: $LAYOUT (expected git|tab)" >&2; exit 1 ;;
            esac
        fi
        render_year_stats "$YEAR"
        ;;
    *)
        echo "Unknown type: $TYPE (expected month|year)" >&2; exit 1 ;;
esac
