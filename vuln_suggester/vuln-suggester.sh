#!/bin/bash

# vuln_suggester.sh
# Simple Vulnerability Suggestion Script
# Usage: ./vuln_suggester.sh <target_ip_or_nmap_file>
# Example: ./vuln_suggester.sh 10.10.11.123
#          ./vuln_suggester.sh nmap_service.txt

set -euo pipefail  # Safer bash settings: stop on error, unset vars, and pipe failures

# Default values
OUTPUT_FILE=""
USE_SEARCHSPLOIT=true
VERBOSE=false

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -o) OUTPUT_FILE="$2"; shift ;;              # Custom output file
        --no-searchsploit) USE_SEARCHSPLOIT=false ;; # Disable searchsploit lookup
        --verbose) VERBOSE=true ;;                  # Enable verbose logging
        *) INPUT="$1" ;;                           # Treat remaining arg as input (file or IP)
    esac
    shift
done

# If no input is given, show usage and exit
if [ -z "${INPUT:-}" ]; then
    echo "Usage: $0 <target_ip_or_nmap_service_output_file> [-o output_file] [--no-searchsploit] [--verbose]"
    exit 1
fi

# Print a header in the final report
print_header() {
    echo "==========================================="
    echo "      Vuln Suggester Report for $TARGET      "
    echo "      Generated: $(date -u +"%Y-%m-%d %H:%M UTC")"
    echo "==========================================="
    echo
}

# Suggest vulnerabilities based on service name and version
suggestions_for_service() {
    local port_proto="$1"
    local service="$2"
    local version="$3"
    echo "- **$port_proto** - $service ${version:-"(unknown version)"}" >> "$OUTPUT"

    case "$service" in
    ftp)
        echo "  > Suggestion: Try anonymous login: 'ftp $TARGET' or 'curl ftp://$TARGET'." >> "$OUTPUT"
        if [[ "$version" =~ vsftpd[[:space:]]*2\.3\.4 ]]; then
            echo "  > Note: vsftpd 2.3.4 has a known backdoor (CVE-2011-2523) in some builds." >> "$OUTPUT"
        fi
        ;;
    ssh)
        echo "  > Suggestion: Check for weak/default credentials..." >> "$OUTPUT"
        ;;
    http|http-alt|ssl/http|https)
        echo "  > Suggestion: Run directory fuzzing, inspect /robots.txt, check headers, run nikto or whatweb." >> "$OUTPUT"
        echo "  > Suggestion: Look for outdated web servers and known CVEs." >> "$OUTPUT"
        if [[ "$version" =~ Apache/2\.4\.1[0-9] ]]; then
            echo "  > Note: Apache 2.4.18+ may be outdated depending on distro." >> "$OUTPUT"
        fi
        ;;
    smb)
        echo "  > Suggestion: Run enum4linux, smbclient -L //$TARGET..." >> "$OUTPUT"
        ;;
    mysql)
        echo "  > Suggestion: Test default credentials, connect via mysql client, enumerate DBs." >> "$OUTPUT"
        ;;
    ms-sql-s)
        echo "  > Suggestion: Brute-force using sqsh/crackmapexec, check auth." >> "$OUTPUT"
        ;;
    rdp)
        echo "  > Suggestion: Try Ncrack or search for known RDP vulns (BlueKeep etc.)." >> "$OUTPUT"
        ;;
    postgres)
        echo "  > Suggestion: Test default credentials, attempt DB enumeration." >> "$OUTPUT"
        ;;
    smtp)
        echo "  > Suggestion: Test VRFY/EXPN, open relay, analyze banner." >> "$OUTPUT"
        ;;
    dns)
        echo "  > Suggestion: Test zone transfers, check recursion settings." >> "$OUTPUT"
        ;;
    *)
        echo "  > Suggestion: Manual review. Banner grabbing, CVE lookup for '$service $version'." >> "$OUTPUT"
        ;;
    esac

    echo "" >> "$OUTPUT"

    # Optional SearchSploit suggestions
    if [ "$USE_SEARCHSPLOIT" = true ]; then
        if ! command -v searchsploit &> /dev/null; then
            echo "  > Warning: searchsploit not installed." >> "$OUTPUT"
        else
            log "Running searchsploit for $service $version..."
            echo "  > SearchSploit Results:" >> "$OUTPUT"
            timeout 10s searchsploit -j "$service $version" |
            grep -E '"Title":|"CVE":' >> "$OUTPUT" 2>/dev/null || echo "    No relevant exploits found." >> "$OUTPUT"
            echo "" >> "$OUTPUT"
        fi
    fi
}

# Handle input as file or target IP
if [[ -f "$INPUT" ]]; then
    if [[ ! -r "$INPUT" ]]; then
        echo "[!] Error: Cannot read file '$INPUT'."
        exit 1
    fi
    NMAP_RAW="$INPUT"
    TARGET="$(basename "$INPUT" .txt)"
else
    TARGET="$INPUT"
    NMAP_RAW="nmap_service_${TARGET}.txt"
    log "No file provided, running nmap -sV on $TARGET..."

    if ! command -v nmap &> /dev/null; then
        echo "[!] Error: nmap is not installed."
        exit 1
    fi
    if ! nmap -sV --version-intensity 4 -oN "$NMAP_RAW" "$TARGET" >/dev/null 2>&1; then
        echo "[!] Error: Nmap scan failed."
        exit 1
    fi
fi

# Set output file or use default
if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="suggestions_${TARGET}.txt"
fi
OUTPUT="$OUTPUT_FILE"
rm -f "$OUTPUT" 2>/dev/null || true  # Remove old output file if exists

log "Parsing Nmap output from $NMAP_RAW..."

# Read all open service lines
mapfile -t service_lines < <(grep -E "^[0-9]+/(tcp|udp)[[:space:]]+open" "$NMAP_RAW" || true)

# If no services found, print message and quit
if [ ${#service_lines[@]} -eq 0 ]; then
    echo "[!] No open services detected or cannot parse $NMAP_RAW." >> "$OUTPUT"
    cat "$OUTPUT"
    exit 0
fi

# For debug info
echo "[*] Parsing detected services..." >> /dev/stderr

# Associative array to store service per port
declare -A services

# Parse each open port line and suggest vulns
for line in "${service_lines[@]}"; do
    clean=$(echo "$line" | tr -s ' ')                    # Normalize spaces
    port_proto=$(echo "$clean" | awk '{print $1}')       # e.g., 80/tcp
    service=$(echo "$clean" | awk '{print $3}')          # e.g., http
    version=$(echo "$clean" | cut -d' ' -f4-)             # Rest of line as version info

    if [[ "$service" == "-" ]]; then
        service="unknown"
    fi

    svc_lower=$(echo "$service" | tr '[:upper:]' '[:lower:]')
    suggestions_for_service "$port_proto" "$svc_lower" "$version"
    services["$port_proto"]="$service"

done

# Summary section
echo "==== Summary ====" >> "$OUTPUT"
echo "Target: $TARGET" >> "$OUTPUT"
echo "Detected services:" >> "$OUTPUT"
for port_proto in "${!services[@]}"; do
    echo "- $port_proto : ${services[$port_proto]}" >> "$OUTPUT"
done

echo "" >> "$OUTPUT"
echo "Report saved to: $OUTPUT"
cat "$OUTPUT"
