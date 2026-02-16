#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="APKCleaner"
VERSION="1.0"

JSON_FILE="default_list.json"
REVIEW_FILE="review_list.txt"
USER_ID=0
DEVICE_ID=""
MODE="scan"
FILTER="recommended"
BACKUP_APKS=0
DRY_RUN=0
FORCE=0

# ---------- COLORS ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

# ---------- CRITICAL PACKAGES ----------
CRITICAL_PACKAGES=(
    "com.android.settings"
    "com.android.systemui"
    "com.android.packageinstaller"
    "com.android.providers.downloads"
)

# ---------- REQUIREMENTS ----------
command -v adb >/dev/null || { echo "ADB not found."; exit 1; }
command -v jq >/dev/null || { echo "jq required."; exit 1; }
command -v sha256sum >/dev/null || { echo "sha256sum required."; exit 1; }
[[ ! -f "$JSON_FILE" ]] && { echo "Missing $JSON_FILE"; exit 1; }

# ---------- FUNCTIONS ----------

get_installed_packages() {
    adb -s "$DEVICE_ID" shell pm list packages --user "$USER_ID" \
        | sed 's/package://' | tr -d '\r'
}

get_filtered_packages() {
    jq -r --arg filter "$FILTER" '
        to_entries[]
        | select(
            (.value.removal | ascii_downcase) == $filter
            or
            (.value.list | ascii_downcase) == $filter
        )
        | "\(.key)|\(.value.removal)|\(.value.description | gsub("\n"; " "))"
    ' "$JSON_FILE"
}

check_critical_packages() {
    for critical in "${CRITICAL_PACKAGES[@]}"; do
        if grep -Fxq "$critical" "$REVIEW_FILE"; then
            echo -e "${RED}[CRITICAL WARNING] $critical is in removal list!${NC}"
            if [[ "$FORCE" -ne 1 ]]; then
                echo -e "${YELLOW}Use --force to override.${NC}"
                exit 1
            fi
        fi
    done
}

validate_core_apps() {
    echo -e "${BLUE}Validating projected system state...${NC}"

    INSTALLED=$(get_installed_packages)
    TO_REMOVE=$(grep -v '^$' "$REVIEW_FILE" || true)

    REMAINING=$(comm -23 \
        <(echo "$INSTALLED" | sort -u) \
        <(echo "$TO_REMOVE" | sort -u))

resolve_intent_package() {
    local action="$1"
    local category="${2:-}"

    local output

    if [[ -n "$category" ]]; then
        output=$(adb -s "$DEVICE_ID" shell \
            cmd package resolve-activity --brief --user "$USER_ID" \
            -a "$action" -c "$category" 2>/dev/null)
    else
        output=$(adb -s "$DEVICE_ID" shell \
            cmd package resolve-activity --brief --user "$USER_ID" \
            -a "$action" 2>/dev/null)
    fi

    echo "$output" \
        | tr -d '\r' \
        | grep '/' \
        | head -n1 \
        | cut -d '/' -f1
}

    check_launcher() {
        echo -e "${BLUE}Checking launcher...${NC}"

        LAUNCHER=$(resolve_intent_package \
            "android.intent.action.MAIN" \
            "android.intent.category.HOME")

        if [[ -z "$LAUNCHER" ]]; then
            echo -e "${YELLOW}[WARNING] Could not resolve launcher.${NC}"
            return 0
        fi

        if echo "$REMAINING" | grep -qx "$LAUNCHER"; then
            echo -e "${GREEN}[OK] Launcher will remain ($LAUNCHER)${NC}"
        else
            echo -e "${RED}[CRITICAL] Active launcher would be removed! ($LAUNCHER)${NC}"
            return 1
        fi
    }

    check_dialer() {
        echo -e "${BLUE}Checking Dialer...${NC}"

        DIALER=$(resolve_intent_package \
            "android.intent.action.DIAL")

        if [[ -z "$DIALER" ]]; then
            echo -e "${YELLOW}[WARNING] Could not resolve Dialer.${NC}"
            return 0
        fi

        if echo "$REMAINING" | grep -qx "$DIALER"; then
            echo -e "${GREEN}[OK] Dialer will remain ($DIALER)${NC}"
        else
            echo -e "${YELLOW}[WARNING] Active Dialer would be removed! ($DIALER)${NC}"
        fi
    }

    check_browser() {
        echo -e "${BLUE}Checking Browser...${NC}"

        BROWSER=$(resolve_intent_package \
            "android.intent.action.VIEW" \
            "android.intent.category.BROWSABLE")

        if [[ -z "$BROWSER" ]]; then
            echo -e "${YELLOW}[WARNING] Could not resolve Browser.${NC}"
            return 0
        fi

        if echo "$REMAINING" | grep -qx "$BROWSER"; then
            echo -e "${GREEN}[OK] Browser will remain ($BROWSER)${NC}"
        else
            echo -e "${YELLOW}[WARNING] Active Browser would be removed! ($BROWSER)${NC}"
        fi
    }

    FAIL=0

    check_launcher || FAIL=1
    check_dialer
    check_browser

    return $FAIL
}

backup_apks() {
    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    BACKUP_DIR="apk_backups/$TIMESTAMP"

    mkdir -p "$BACKUP_DIR"

    echo -e "${BLUE}Backing up APKs to $BACKUP_DIR${NC}"
    echo ""

    while IFS= read -r pkg <&3; do
        [[ -z "$pkg" ]] && continue

        echo -e "${YELLOW}Backing up $pkg${NC}"

        PKG_DIR="$BACKUP_DIR/$pkg"
        mkdir -p "$PKG_DIR"

        PATHS=$(adb -s "$DEVICE_ID" shell pm path "$pkg" 2>/dev/null \
            | sed 's/package://' \
            | tr -d '\r')

        if [[ -z "$PATHS" ]]; then
            echo -e "${RED}  Could not retrieve APK path for $pkg${NC}"
            continue
        fi

        APK_COUNT=0

        while IFS= read -r apkpath; do
            [[ -z "$apkpath" ]] && continue

            if adb -s "$DEVICE_ID" pull "$apkpath" "$PKG_DIR/" >/dev/null 2>&1; then
                echo -e "${GREEN}  Pulled $(basename "$apkpath")${NC}"
                ((++APK_COUNT))
            else
                echo -e "${RED}  Failed to pull $(basename "$apkpath")${NC}"
            fi
        done <<< "$PATHS"

        if [[ "$APK_COUNT" -eq 0 ]]; then
            echo -e "${RED}  No APKs successfully pulled for $pkg${NC}"
        fi

        echo ""

    done 3< "$REVIEW_FILE"

    echo -e "${BLUE}Generating global restore bundle...${NC}"
    echo ""

    cd "$BACKUP_DIR" || exit 1

    # ---------- GLOBAL SHA256SUMS ----------
    echo -e "${BLUE}Generating SHA256SUMS...${NC}"

    find . -type f -name "*.apk" -print0 \
        | sort -z \
        | xargs -0 sha256sum > SHA256SUMS

    echo -e "${GREEN}  SHA256SUMS created.${NC}"

    # ---------- VERIFY SCRIPT ----------
    cat > verify.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "Verifying APK integrity..."
sha256sum -c SHA256SUMS
echo "Verification complete."
EOF

    chmod +x verify.sh
    echo -e "${GREEN}  verify.sh created.${NC}"

    # ---------- INSTALL SCRIPT ----------
    cat > install.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail

DEVICE_ID="${DEVICE_ID}"
USER_ID="${USER_ID}"

echo "Starting full restore..."
echo ""

cd "\$(dirname "\$0")"

for pkgdir in */; do
    [[ ! -d "\$pkgdir" ]] && continue

    echo "Processing \$pkgdir"

    shopt -s nullglob
    apks=( "\$pkgdir"/*.apk )

    if (( \${#apks[@]} == 0 )); then
        echo "  No APKs found."
        continue
    fi

    if (( \${#apks[@]} == 1 )); then
        echo "  Installing single APK..."
        adb -s "\$DEVICE_ID" install -r "\${apks[0]}"
    else
        echo "  Installing split APK package..."
        adb -s "\$DEVICE_ID" install-multiple -r "\${apks[@]}"
    fi

    echo ""
done

echo "Full restore complete."
EOF

    chmod +x install.sh
    echo -e "${GREEN}  install.sh created.${NC}"

    cd - >/dev/null || exit 1

    echo ""
    echo -e "${GREEN}APK backup complete.${NC}"
    echo ""
}

show_help() {
    echo -e "${GREEN}
⢀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⡀⠀⠀⠀⠀
⠀⠙⢷⣤⣤⣴⣶⣶⣦⣤⣤⡾⠋⠀⠀⠀⠀⠀
⠀⣴⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣦⠀⠀⠀⠀⠀
⣼⣿⣿⣉⣹⣿⣿⣿⣿⣏⣉⣿⣿⣧⠀⠀⠀⠀
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇${NC}"
    echo -e "${BLUE}${TOOL_NAME} v${VERSION}${NC}"
    echo -e "${BLUE}----------------------------------------${NC}"
    echo ""
    echo -e "${GREEN}Core Modes:${NC}"
    echo -e "  ${YELLOW}--scan${NC}        Scan and build review list"
    echo -e "  ${YELLOW}--apply${NC}       Remove all selected packages"
    echo -e "  ${YELLOW}--edit${NC}        Edit entries in review list"
    echo -e "  ${YELLOW}--restore${NC}     Restore from review list"
    echo -e "  ${YELLOW}--verify${NC}      Verify latest backup integrity"
    echo -e "  ${YELLOW}--install${NC}     Install from latest backup"
    echo -e "  ${YELLOW}--analyze${NC}     Post-debloat system analysis"
    echo ""
    echo -e "${GREEN}Filters:${NC}"
    echo -e "  ${YELLOW}--filter recommended|advanced|oem${NC}"
    echo ""
    echo -e "${GREEN}Modifiers:${NC}"
    echo -e "  ${YELLOW}--dry-run${NC}     Simulate removal"
    echo -e "  ${YELLOW}--force${NC}       Bypass any guardrails"
    echo -e "  ${YELLOW}--extract${NC}     Extract APKs before removal"
    echo ""
    echo -e "${GREEN}Device Selection:${NC}"
    echo -e "  ${YELLOW}-s DEVICE_ID${NC}  Specify target device"
    echo ""
}

main() {

    # ---------- ARG PARSE ----------
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s) DEVICE_ID="$2"; shift 2 ;;
            --scan) MODE="scan"; shift ;;
            --apply) MODE="apply"; shift ;;
            --edit) MODE="edit"; shift ;;
            --restore) MODE="restore"; shift ;;
            --analyze) MODE="analyze"; shift ;;
            --install) MODE="install"; shift ;;
            --verify) MODE="verify"; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            --force) FORCE=1; shift ;;
            --filter) FILTER="$2"; shift 2 ;;
            --extract) BACKUP_APKS=1; shift ;;
            --help|-h) show_help; exit 0 ;;
            --version) echo -e "${BLUE}${TOOL_NAME} v${VERSION}${NC}"; exit 0 ;;
            *)
                echo -e "${RED}Invalid option: $1${NC}"
                echo ""
                show_help
                exit 1
                ;;
        esac
    done

    # ---------- DEVICE DETECT ----------
    if [[ -z "$DEVICE_ID" ]]; then
        DEVICE_ID=$(adb devices | awk '$2=="device" {print $1; exit}')
    fi

    [[ -z "$DEVICE_ID" ]] && {
        echo "No device detected."
        exit 1
    }

    # ---------- MODES ----------

    case "$MODE" in

        scan)
            echo -e "${BLUE}${TOOL_NAME} v${VERSION}${NC}"
            echo "Scanning device..."
            echo "Filter: $FILTER"
            echo ""

            INSTALLED=$(get_installed_packages)
            MATCHES=$(get_filtered_packages)

            : > "$REVIEW_FILE"

            while IFS="|" read -r pkg removal desc; do
                if echo "$INSTALLED" | grep -qx "$pkg"; then
                    echo -e "${GREEN}[MATCH]${NC} $pkg"
                    echo "  Removal: $removal"
                    echo "  Desc: ${desc:0:100}..."
                    echo "$pkg" >> "$REVIEW_FILE"
                fi
            done <<< "$MATCHES"

            COUNT=$(wc -l < "$REVIEW_FILE")
            echo ""
            echo -e "${BLUE}Matched $COUNT packages.${NC}"
            echo "Saved list to $REVIEW_FILE"
            ;;

        apply)
            [[ ! -f "$REVIEW_FILE" ]] && {
                echo "Run --scan first."
                exit 1
            }

            echo ""
            echo -e "${YELLOW}Packages scheduled for removal:${NC}"
            cat "$REVIEW_FILE"
            echo ""

            check_critical_packages

            if [[ "$FORCE" -ne 1 ]]; then
                validate_core_apps || {
                    echo -e "${RED}Core validation failed. Aborting.${NC}"
                    exit 1
                }
            fi

            if [[ "$BACKUP_APKS" -eq 1 ]]; then
                backup_apks
            fi

            read -rp "Apply removal of packages in $REVIEW_FILE? (y/N): " ans
            [[ "$ans" =~ ^[Yy]$ ]] || exit 0

            while IFS= read -r pkg <&3; do
                echo -e "${YELLOW}Removing $pkg${NC}"
                if [[ "$DRY_RUN" -eq 0 ]]; then
                    adb -s "$DEVICE_ID" shell pm uninstall --user "$USER_ID" "$pkg"
                else
                    echo -e "${BLUE}[DRY RUN] Would remove $pkg${NC}"
                fi
            done 3< "$REVIEW_FILE"

            echo -e "${GREEN}Done.${NC}"
            ;;

        restore)
            [[ ! -f "$REVIEW_FILE" ]] && {
                echo "No review file."
                exit 1
            }

            while IFS= read -r pkg <&3; do
                echo "Restoring $pkg"
                adb -s "$DEVICE_ID" shell cmd package install-existing "$pkg"
            done 3< "$REVIEW_FILE"

            echo "Restore complete."
            ;;

        verify)
            echo -e "${BLUE}Running verification on latest backup...${NC}"

            LATEST_BACKUP=$(ls -dt apk_backups/* 2>/dev/null | head -n1)

            if [[ -z "${LATEST_BACKUP:-}" ]]; then
                echo -e "${RED}No backup directories found.${NC}"
                exit 1
            fi

            if [[ ! -f "$LATEST_BACKUP/verify.sh" ]]; then
                echo -e "${RED}verify.sh not found in $LATEST_BACKUP${NC}"
                exit 1
            fi

            echo -e "${GREEN}Using backup:${NC} $LATEST_BACKUP"
            echo ""

            ( cd "$LATEST_BACKUP" && ./verify.sh )
            ;;

        install)
            echo -e "${BLUE}Running install from latest backup...${NC}"

            LATEST_BACKUP=$(ls -dt apk_backups/* 2>/dev/null | head -n1)

            if [[ -z "${LATEST_BACKUP:-}" ]]; then
                echo -e "${RED}No backup directories found.${NC}"
                exit 1
            fi

            if [[ ! -f "$LATEST_BACKUP/install.sh" ]]; then
                echo -e "${RED}install.sh not found in $LATEST_BACKUP${NC}"
                exit 1
            fi

            echo -e "${GREEN}Using backup:${NC} $LATEST_BACKUP"
            echo ""

            read -rp "Proceed with full restore? (y/N): " ans
            [[ "$ans" =~ ^[Yy]$ ]] || exit 0

            ( cd "$LATEST_BACKUP" && ./install.sh )
            ;;

        analyze)
            echo -e "${BLUE}Post-Debloat Analysis${NC}"
            echo ""

            validate_core_apps

            echo ""
            echo -e "${BLUE}Checking Captive Portal Handler...${NC}"
            if ! adb -s "$DEVICE_ID" shell pm list packages | grep -q captiveportal; then
                echo -e "${YELLOW}Captive portal handler not detected.${NC}"
            else
                echo -e "${GREEN}Captive portal handler present.${NC}"
            fi

            echo ""
            echo -e "${BLUE}Checking Google Play Services...${NC}"
            if adb -s "$DEVICE_ID" shell pm list packages | grep -q "com.google.android.gms"; then
                echo -e "${GREEN}Google Play Services present.${NC}"
            else
                echo -e "${YELLOW}Google Play Services not detected.${NC}"
            fi

            echo ""
            echo -e "${GREEN}Analysis complete.${NC}"
            ;;

    esac
}

main "$@"
