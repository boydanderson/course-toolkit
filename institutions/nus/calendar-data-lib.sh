#!/bin/bash
# Utility functions for dynamically fetching Singapore public holidays
# and NUS Academic Calendar data -- institution-specific (NUS/Singapore),
# deliberately kept out of core/ (see core/enrich-lib.sh's is_holiday
# comment: "fetching a real institution's public-holiday calendar is out
# of scope for a generic toolkit"). Lives under institutions/nus/ instead,
# same pattern as backends/ -- a pluggable, optional piece any NUS course
# repo can use, not something core/ assumes or depends on. Ported
# verbatim from cs1101s/course-materials' scripts/fetch-holidays.sh
# (proven against real data.gov.sg/NUS/NUSMods APIs there first), with
# the one CS1101S-specific default (fetch_nusmods_exam_dynamic's
# module_code) removed -- every caller here supplies its own course code.
#
# Usage: source this file, then call:
#   fetch_sg_holidays_dynamic [year...]    - populates SG_HOLIDAYS array
#   fetch_nus_calendar_dynamic [acad_year] - populates NUS_SPECIAL_DATES array;
#                                            also merges NUS-specific holidays into SG_HOLIDAYS
#
# Fetch functions return 0 on success, 1 on failure.
# See fetch-calendar-data.sh for the orchestrator that turns this into a
# course's config/holidays.conf (the format core/enrich-lib.sh's
# is_holiday already reads).
#
# Optional environment variables:
#   DATA_GOV_SG_API_KEY   - API key for data.gov.sg (reduces rate limiting).
#                           Register at https://data.gov.sg to obtain a key.
#   NUS_CALENDAR_PDF_URL  - Override URL for the NUS academic calendar PDF.

fetch_sg_holidays_dynamic() {
    if ! command -v curl &>/dev/null; then
        echo " - Error: curl not available; cannot fetch Singapore holidays." >&2
        return 1
    fi

    local years=("$@")
    if [ ${#years[@]} -eq 0 ]; then
        local cur_year
        cur_year=$(date '+%Y')
        years=("$cur_year" "$((cur_year + 1))")
    fi

    local curl_args=(-s --connect-timeout 10 --max-time 30)
    if [ -n "${DATA_GOV_SG_API_KEY:-}" ]; then
        curl_args+=(-H "x-api-key: ${DATA_GOV_SG_API_KEY}")
    fi

    local base_url="https://data.gov.sg/api/action/datastore_search?resource_id=d_8ef23381f9417e4d4254ee8b4dcdb176&limit=500"
    local response
    response=$(curl "${curl_args[@]}" "$base_url" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$response" ]; then
        echo " - Error: Failed to fetch Singapore public holidays from data.gov.sg." >&2
        return 1
    fi

    local parsed
    local parse_warning=""
    if command -v python3 &>/dev/null; then
        local py_err_file
        py_err_file=$(mktemp)
        parsed=$(echo "$response" | python3 -c "
import json, sys

years = set(sys.argv[1:])
try:
    data = json.load(sys.stdin)
    if 'code' in data and data.get('code') not in (200, None, '200'):
        msg = data.get('errorMsg') or data.get('name') or ('API error code ' + str(data.get('code')))
        sys.stderr.write(msg + '\n')
        sys.exit(1)

    result = data.get('result') or (data.get('data') if isinstance(data.get('data'), dict) else None) or {}
    records = result.get('records', [])
    for r in records:
        date = (r.get('date') or r.get('Date') or '').strip()
        name = (r.get('holiday') or r.get('Holiday') or r.get('name') or r.get('Name') or '').strip()
        if not date or not name:
            continue
        record_year = date[:4]
        if record_year not in years:
            continue
        print(date + '|' + name)
except Exception as e:
    sys.stderr.write(str(e) + '\n')
    sys.exit(1)
" "${years[@]}" 2>"$py_err_file")
        parse_warning=$(cat "$py_err_file" 2>/dev/null || true)
        rm -f "$py_err_file"
    elif command -v jq &>/dev/null; then
        local year_filter
        year_filter=$(printf '"%s",' "${years[@]}")
        year_filter="[${year_filter%,}]"
        parsed=$(echo "$response" | jq -r \
            '(.result // .data // {}).records // [] |
             .[] | select((.date // .Date)[:4] as $y | $yrs | index($y) != null) |
             "\(.date // .Date)|\(.holiday // .Holiday // .name // .Name)"' \
            --argjson yrs "$year_filter" \
            2>/dev/null)
    else
        echo " - Error: Neither python3 nor jq available for JSON parsing." >&2
        return 1
    fi

    if [ -z "$parsed" ]; then
        if [ -n "$parse_warning" ]; then
            echo " - Error: data.gov.sg: $parse_warning" >&2
            echo "  Tip: Set DATA_GOV_SG_API_KEY to avoid rate limits (https://data.gov.sg)." >&2
        else
            echo " - Error: Failed to parse Singapore public holidays response." >&2
        fi
        return 1
    fi

    SG_HOLIDAYS=()
    while IFS= read -r line; do
        [ -n "$line" ] && SG_HOLIDAYS+=("$line")
    done <<< "$parsed"

    if [ ${#SG_HOLIDAYS[@]} -eq 0 ]; then
        echo " - Error: No holidays parsed from response." >&2
        return 1
    fi

    echo " - Fetched ${#SG_HOLIDAYS[@]} Singapore public holidays (years: ${years[*]}) from data.gov.sg" >&2
    return 0
}

fetch_nus_calendar_dynamic() {
    local acad_year="${1:-2025-2026}"

    if ! command -v curl &>/dev/null; then
        echo " - Error: curl not available; cannot fetch NUS calendar dates." >&2
        return 1
    fi

    local year1="${acad_year%%-*}"
    local year2="${acad_year##*-}"

    local pdf_url
    if [ -n "${NUS_CALENDAR_PDF_URL:-}" ]; then
        pdf_url="$NUS_CALENDAR_PDF_URL"
    else
        pdf_url="https://www.nus.edu.sg/registrar/docs/default-source/calendar/ay${year1}-${year2}.pdf"
    fi

    local tmp_pdf
    # Note: BSD mktemp (macOS) requires Xs to be the last characters in the template
    # so we omit the .pdf extension from the template name.
    tmp_pdf=$(mktemp /tmp/nus-acal-XXXXXX)
    local download_ok=false
    local download_url="$pdf_url"
    local http_code content_type

    http_code=$(curl -sSL --connect-timeout 15 --max-time 60 -H "Accept: application/pdf" -A "Mozilla/5.0" -w "%{http_code}" -o "$tmp_pdf" "$download_url" 2>/dev/null)
    content_type=$(file --brief --mime-type "$tmp_pdf" 2>/dev/null)

    if [ "$http_code" = "200" ] && [ "$content_type" = "application/pdf" ]; then
        download_ok=true
    elif [ -z "${NUS_CALENDAR_PDF_URL:-}" ]; then
        local alternate_url="https://nus.edu.sg/registrar/docs/default-source/calendar/ay${year1}-${year2}.pdf"
        http_code=$(curl -sSL --connect-timeout 15 --max-time 60 -H "Accept: application/pdf" -A "Mozilla/5.0" -w "%{http_code}" -o "$tmp_pdf" "$alternate_url" 2>/dev/null)
        content_type=$(file --brief --mime-type "$tmp_pdf" 2>/dev/null)
        if [ "$http_code" = "200" ] && [ "$content_type" = "application/pdf" ]; then
            download_ok=true
        fi
    fi

    if [ "$download_ok" = false ]; then
        rm -f "$tmp_pdf"
        echo " - Error: Failed to download NUS academic calendar PDF." >&2
        return 1
    fi

    local parsed
    parsed=$(_parse_nus_pdf_for_events "$tmp_pdf")
    local parse_status=$?
    rm -f "$tmp_pdf"

    if [ $parse_status -ne 0 ] || [ -z "$parsed" ]; then
        echo " - Error: Failed to parse NUS academic calendar PDF." >&2
        return 1
    fi

    # Split parsed output:
    # - Recess/Reading -> NUS_SPECIAL_DATES
    # - Everything else (incl. NUS Well-Being Day) -> merged into SG_HOLIDAYS
    NUS_SPECIAL_DATES=()
    local nus_holidays_count=0

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local label="${line##*|}"
        case "$label" in
            "Recess Week"|"Reading Week")
                NUS_SPECIAL_DATES+=("$line")
                ;;
            *)
                local hdate="${line%%|*}"
                local already=false
                for existing in "${SG_HOLIDAYS[@]}"; do
                    if [ "${existing%%|*}" = "$hdate" ]; then
                        already=true
                        break
                    fi
                done
                if [ "$already" = false ]; then
                    SG_HOLIDAYS+=("$line")
                    nus_holidays_count=$((nus_holidays_count + 1))
                fi
                ;;
        esac
    done <<< "$parsed"

    if [ ${#NUS_SPECIAL_DATES[@]} -eq 0 ]; then
        echo " - Error: No NUS special dates parsed from PDF." >&2
        return 1
    fi

    echo " - Fetched ${#NUS_SPECIAL_DATES[@]} NUS calendar dates + ${nus_holidays_count} NUS-specific holidays from ${pdf_url}" >&2
    return 0
}

fetch_nusmods_exam_dynamic() {
    # Fetches the final exam date/time for a module from the NUSMods API
    # (https://api.nusmods.com) and converts it from UTC (as NUSMods stores
    # it) to Singapore Time (UTC+8). Populates EXAM_DATE/EXAM_START_TIME/
    # EXAM_END_TIME/EXAM_NAME.
    local module_code="$1"   # e.g. "CS1101S" -- required, no default
    local acad_year="$2"   # e.g. "2026-2027"
    local semester="${3:-1}"

    if [ -z "$module_code" ]; then
        echo " - Error: fetch_nusmods_exam_dynamic requires a module code." >&2
        return 1
    fi

    if ! command -v curl &>/dev/null; then
        echo " - Error: curl not available; cannot fetch NUSMods exam data." >&2
        return 1
    fi

    local url="https://api.nusmods.com/v2/${acad_year}/modules/${module_code}.json"
    local response
    response=$(curl -s --connect-timeout 10 --max-time 30 "$url" 2>/dev/null)

    if [ -z "$response" ]; then
        echo " - Error: Failed to fetch NUSMods data for $module_code ($acad_year)." >&2
        return 1
    fi

    if ! command -v python3 &>/dev/null; then
        echo " - Error: python3 not available; cannot parse NUSMods response." >&2
        return 1
    fi

    local parsed
    parsed=$(echo "$response" | python3 -c "
import json, sys
from datetime import timedelta, datetime

sem = int(sys.argv[1])
try:
    data = json.load(sys.stdin)
    for sd in data.get('semesterData', []):
        if sd.get('semester') != sem:
            continue
        exam_date = sd.get('examDate')
        duration = sd.get('examDuration')
        if not exam_date:
            sys.exit(1)
        # examDate is UTC ISO8601 (e.g. 2026-11-25T01:00:00.000Z);
        # NUSMods times are UTC, Singapore is UTC+8.
        dt_utc = datetime.strptime(exam_date, '%Y-%m-%dT%H:%M:%S.%fZ')
        dt_sgt = dt_utc + timedelta(hours=8)
        end_sgt = dt_sgt + timedelta(minutes=duration or 120)
        print(dt_sgt.strftime('%Y-%m-%d') + '|' + dt_sgt.strftime('%H:%M') + '|' + end_sgt.strftime('%H:%M'))
        sys.exit(0)
    sys.exit(1)
except Exception as e:
    sys.stderr.write(str(e) + chr(10))
    sys.exit(1)
" "$semester" 2>/dev/null)

    if [ -z "$parsed" ]; then
        echo " - Error: No exam date found for $module_code semester $semester ($acad_year)." >&2
        return 1
    fi

    EXAM_DATE=$(echo "$parsed" | cut -d'|' -f1)
    EXAM_START_TIME=$(echo "$parsed" | cut -d'|' -f2)
    EXAM_END_TIME=$(echo "$parsed" | cut -d'|' -f3)
    EXAM_NAME="Final Exam"

    echo " - Fetched exam date for $module_code (Sem $semester, $acad_year): $EXAM_DATE $EXAM_START_TIME-$EXAM_END_TIME SGT" >&2
    return 0
}

calendar_data_dir() {
    echo "${CALENDAR_DATA_DIR:-config/calendar-data}"
}

exam_cache_file() {
    local acad_year="$1"
    echo "$(calendar_data_dir)/exam-${acad_year}.conf"
}

load_exam_cache() {
    local acad_year="$1"
    local file
    file=$(exam_cache_file "$acad_year")
    [ -f "$file" ] || return 1

    local line
    line=$(grep -v '^#' "$file" | grep -v '^$' | head -1)
    [ -z "$line" ] && return 1

    EXAM_DATE=$(echo "$line" | cut -d'|' -f1)
    EXAM_START_TIME=$(echo "$line" | cut -d'|' -f2)
    EXAM_END_TIME=$(echo "$line" | cut -d'|' -f3)
    EXAM_NAME=$(echo "$line" | cut -d'|' -f4)
    return 0
}

save_exam_cache() {
    local acad_year="$1"
    local module_code="$2"
    local file
    file=$(exam_cache_file "$acad_year")
    mkdir -p "$(calendar_data_dir)"
    {
        echo "# ${module_code} final exam date/time, fetched from the NUSMods API"
        echo "# (https://api.nusmods.com/v2/${acad_year}/modules/${module_code}.json)"
        echo "# Generated by institutions/nus/fetch-calendar-data.sh"
        echo "# Format: YYYY-MM-DD|START_TIME|END_TIME|Event Name (times in Singapore Time, UTC+8)"
        echo "${EXAM_DATE}|${EXAM_START_TIME}|${EXAM_END_TIME}|${EXAM_NAME}"
    } > "$file"
    echo " - Saved exam data to $file" >&2
}

sg_holidays_cache_file() {
    local year1="$1"
    local year2="$2"
    echo "$(calendar_data_dir)/sg-holidays-${year1}-${year2}.conf"
}

nus_calendar_cache_file() {
    local acad_year="$1"
    echo "$(calendar_data_dir)/nus-calendar-${acad_year}.conf"
}

load_calendar_data_cache() {
    local year1="$1"
    local year2="$2"
    local acad_year="$3"
    local sg_file
    local nus_file

    sg_file=$(sg_holidays_cache_file "$year1" "$year2")
    nus_file=$(nus_calendar_cache_file "$acad_year")

    if [ ! -f "$sg_file" ]; then
        echo " - Error: Missing cached Singapore holiday data: $sg_file" >&2
        return 1
    fi

    if [ ! -f "$nus_file" ]; then
        echo " - Error: Missing cached NUS calendar data: $nus_file" >&2
        return 1
    fi

    SG_HOLIDAYS=()
    NUS_SPECIAL_DATES=()

    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        SG_HOLIDAYS+=("$line")
    done < "$sg_file"

    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        local label="${line##*|}"
        case "$label" in
            "Recess Week"|"Reading Week")
                NUS_SPECIAL_DATES+=("$line")
                ;;
            *)
                SG_HOLIDAYS+=("$line")
                ;;
        esac
    done < "$nus_file"

    if [ ${#NUS_SPECIAL_DATES[@]} -eq 0 ]; then
        echo " - Error: Cached NUS calendar data has no Recess Week or Reading Week entries: $nus_file" >&2
        return 1
    fi

    echo " - Loaded ${#SG_HOLIDAYS[@]} holidays and ${#NUS_SPECIAL_DATES[@]} NUS special dates from $(calendar_data_dir)" >&2
    return 0
}

save_calendar_data_cache() {
    local year1="$1"
    local year2="$2"
    local acad_year="$3"
    local sg_file
    local nus_file

    sg_file=$(sg_holidays_cache_file "$year1" "$year2")
    nus_file=$(nus_calendar_cache_file "$acad_year")

    mkdir -p "$(calendar_data_dir)"

    {
        echo "# Singapore public holidays"
        echo "# Generated by institutions/nus/fetch-calendar-data.sh"
        echo "# Format: YYYY-MM-DD|Holiday Name"
        printf '%s\n' "${SG_HOLIDAYS[@]}" | sort -u
    } > "$sg_file"

    {
        echo "# NUS academic calendar events"
        echo "# Generated by institutions/nus/fetch-calendar-data.sh"
        echo "# Format: YYYY-MM-DD|Event Name"
        printf '%s\n' "${NUS_SPECIAL_DATES[@]}" | sort -u
    } > "$nus_file"

    echo " - Saved Singapore holiday data to $sg_file" >&2
    echo " - Saved NUS calendar data to $nus_file" >&2
}

_parse_nus_pdf_for_events() {
    local pdf_file="$1"

    if ! command -v python3 &>/dev/null; then
        echo " - Warning: python3 not available for PDF parsing." >&2
        return 1
    fi

    # Ensure pdfminer.six exists
    if ! python3 -c "import pdfminer" 2>/dev/null; then
        if command -v pip3 &>/dev/null; then
            pip3 install --quiet pdfminer.six 2>/dev/null || true
        fi
    fi

    if ! python3 -c "import pdfminer" 2>/dev/null; then
        echo " - Warning: pdfminer.six not installed. Install with: pip3 install pdfminer.six" >&2
        return 1
    fi

    python3 - "$pdf_file" << 'PYEOF'
import sys, re
from datetime import datetime, timedelta
from pdfminer.high_level import extract_pages
from pdfminer.layout import LTTextBox

pdf_file = sys.argv[1]

date_pat = re.compile(r'(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun),\s+\d{1,2}\s+\w+\s+20\d{2}')

# Holiday date with optional trailing "*" after "(Day)"
# e.g. "9 Aug 2026 (Sun)*" -> ('9 Aug 2026', '*')
hol_date_pat = re.compile(r'(\d{1,2}\s+\w+\s+20\d{2})\s*\(\w+\)\s*(\*)?')

# Holiday name lines can be:
#  - bullet format: "• National Day"
#  - lettered format: "(a) National Day"
name_pat = re.compile(r'^(?:•\s*|\([a-z]\)\s*)([^\n\r]+)', re.IGNORECASE)
#name_pat = re.compile(r'^(?:•\s*|\([a-z]\)\s*)(.+)$', re.IGNORECASE)

# Used to strip the first date occurrence out of a "name + date" line
date_strip_pat = re.compile(r'\d{1,2}\s+\w+\s+20\d{2}')

def parse_date(s):     return datetime.strptime(s.strip(), '%a, %d %b %Y')
def parse_hol_date(s): return datetime.strptime(s.strip(), '%d %b %Y')

def following_monday(dt):
    # next Monday strictly after dt
    days = (7 - dt.weekday()) % 7  # Mon=0..Sun=6
    if days == 0:
        days = 7
    return dt + timedelta(days=days)

# Collect text boxes on first page
elements = []
for page_layout in extract_pages(pdf_file):
    if page_layout.pageid != 1:
        continue
    for element in page_layout:
        if isinstance(element, LTTextBox):
            x0 = round(element.bbox[0], 1)
            y1 = round(element.bbox[3], 1)
            elements.append((x0, y1, element.get_text()))

# 1) Recess + Reading Week, for EVERY semester's own table found on the
# page (both Semester 1 and Semester 2 -- NUS courses run in either, and
# a course whose semester start date falls Jan-Jul is a Semester 2
# course, whose recess/reading dates live in a visually separate table
# further down the same page).
#
# Detected generically, not via hardcoded row indices into one
# semester's table (which is what this used to do, and which silently
# broke for Semester 2 -- its table has a different total week count, so
# the same indices landed on the wrong rows entirely): within a
# semester's own region, the weekly Monday-start date columns are walked
# in order, and any entry whose START date ISN'T a Monday is a special
# week -- the regular numbered teaching weeks are always Mon-Fri/Mon-Sat,
# while Recess Week and Reading Week both print as odd Sat-to-Sun/
# Sat-to-Fri spans instead. The first such anomaly in date order is
# Recess Week, the second is Reading Week (recess always precedes
# reading within one semester). Verified against a real AY2025/2026
# calendar PDF: reproduces the previously-hardcoded Semester 1 result
# exactly (Recess 2025-09-20~28, Reading 2025-11-15~21) and correctly
# derives Semester 2's (Recess 2026-02-21~03-01, Reading 2026-04-18~24).
semester_bands = []
semester_headers = sorted(
    ((y1, text.strip()) for x0, y1, text in elements if text.strip() in ('SEMESTER 1', 'SEMESTER 2')),
    key=lambda h: -h[0],
)
page_lower_bound = 0.0
for x0, y1, text in elements:
    if 'SPECIAL TERM' in text.strip():
        page_lower_bound = max(page_lower_bound, y1)
for i, (y1, label) in enumerate(semester_headers):
    lower = semester_headers[i + 1][0] if i + 1 < len(semester_headers) else page_lower_bound
    semester_bands.append((label, lower, y1))

for _sem_label, band_lower, band_upper in semester_bands:
    date_cols = {}
    for x0, y1, text in elements:
        if y1 < band_lower or y1 >= band_upper:
            continue
        text_clean = text.replace('\n', ' ')
        dates = date_pat.findall(text_clean)
        if len(dates) < 5:
            continue
        bucket = round(x0 / 20) * 20
        if bucket not in date_cols or len(dates) > len(date_cols[bucket]):
            date_cols[bucket] = dates

    if len(date_cols) < 2:
        continue
    sorted_buckets = sorted(date_cols.keys())
    start_dates = date_cols[sorted_buckets[0]]
    end_dates   = date_cols[sorted_buckets[1]]

    anomalies = []
    for i in range(min(len(start_dates), len(end_dates))):
        try:
            sdt = parse_date(start_dates[i])
        except ValueError:
            continue
        if sdt.weekday() != 0:  # not a Monday -> a special (non-teaching) week
            try:
                edt = parse_date(end_dates[i])
            except ValueError:
                continue
            anomalies.append((sdt, edt))

    for label, (start, end) in zip(['Recess Week', 'Reading Week'], anomalies):
        cur = start
        while cur <= end:
            print(cur.strftime('%Y-%m-%d') + '|' + label)
            cur += timedelta(days=1)

# 2) University holidays / public holidays:
# Boxes are not reliably separable by x0 alone, so select by content.
hol_candidates = []
for x0, y1, text in elements:
    # Holidays live below the semester table region; keep this loose
    if y1 > 500:
        continue

    t = text.strip()
    if not t:
        continue

    # Keep boxes that look like the holiday list / notes
    if ('Public Holidays' in t) or ('Well-Being' in t) or ('Well-Being' in t) or ('Well-Being' in t):
        hol_candidates.append((x0, y1, text))
        continue
    if '•' in t:
        hol_candidates.append((x0, y1, text))
        continue
    if re.search(r'^\([a-z]\)', t, flags=re.IGNORECASE | re.MULTILINE):
        hol_candidates.append((x0, y1, text))
        continue
    if hol_date_pat.search(t):
        hol_candidates.append((x0, y1, text))
        continue

hol_elements = sorted(
    [(x0, y1, text) for x0, y1, text in elements
     if (x0 > 350) and (
          ('•' in text) or
          hol_date_pat.search(text) or
          re.search(r'^\([a-z]\)', text.strip(), re.IGNORECASE)
     )],
    key=lambda e: -e[1]
)

skip_phrases = [
    'Public Holidays', 'The following', 'observed as', 'academic year',
    'please note', 'official end', 'classes is', 'New Year eve',
    'will be no', 'course instructor', 'make up', 'up-to-date',
    'Ministry of', 'Subject to', 'following Monday', 'public holiday.',
    '**For', 'confirm'
]

current_name = None

for x0, y1, text in hol_elements:
    text_clean = text.strip()
    if not text_clean:
        continue
    if any(kw in text_clean for kw in skip_phrases):
        continue

    # Holiday name line? (• ... OR (a) ...)
    m = name_pat.match(text_clean)
    if m:
        current_name = re.sub(r'\s+', ' ', m.group(1)).strip()

        # The same textbox may contain the date(s) on subsequent line(s),
        # or even on the same line (AY2026-2027 style).
        found = hol_date_pat.findall(text_clean)
        if found:
            for d, star in found:
                try:
                    dt = parse_hol_date(d)
                    print(dt.strftime('%Y-%m-%d') + '|' + current_name)
                    if star:
                        obs = following_monday(dt)
                        print(obs.strftime('%Y-%m-%d') + '|' + current_name + ' (observed)')
                except ValueError:
                    pass
            current_name = None
        continue

    # Date line for a previously seen holiday name
    found = hol_date_pat.findall(text_clean)
    if found and current_name:
        for d, star in found:
            try:
                dt = parse_hol_date(d)
                print(dt.strftime('%Y-%m-%d') + '|' + current_name)
                if star:
                    obs = following_monday(dt)
                    print(obs.strftime('%Y-%m-%d') + '|' + current_name + ' (observed)')
            except ValueError:
                pass
        current_name = None

PYEOF
}
