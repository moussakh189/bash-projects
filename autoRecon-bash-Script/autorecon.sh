#!/bin/bash 


# ===============================
# AutoRecon Script by khanfri,Moussa 
# Modular Bash script for basic recon tasks
# ===============================

# check for required tools 
REQUIRED_TOOLS=(nmap whatweb dirb whois dig nikto fierce sublist3r)
 
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v $tool &> /dev/null; then
        echo "[!] $tool is not installed. Please install it before running this script."
        exit 1
    fi
done
 # colors 

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # no color 

target="$1"
DATE=$(date +"%Y-%m-%d_%H-%M")
OUTPUT_DIR="recon_results"
mkdir -p "$OUTPUT_DIR"

# Ask for the target
target="$1"
if [ -z "$target" ]; then
    read -p "Enter target (domain or IP): " target
fi


# Validate target
if ! [[ $target =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && ! [[ $target =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo -e "${RED}[!] Invalid target! Please provide a valid IP or domain.${NC}"
    exit 1
fi

# Make sure they gave us something
if [ -z "$target" ]; then 
    echo -e "${RED}[!] Hey, you didn’t give me a target! Can’t work with that. Bye!${NC}"
    exit 1
fi 

# nmap scanning 

echo -e "${YELLOW}[+] Firing up Nmap... let’s see what’s open!${NC}"
nmap -sC -sV -Pn -T4 -oN "$OUTPUT_DIR/nmap.txt" "$target"



# FTP Scanning (Port 21)
if grep -q "21/tcp" "$OUTPUT_DIR/nmap.txt"; then
    echo -e "${YELLOW}[*] FTP detected! Checking for anonymous access...${NC}"
    ftp -inv "$target" << END_SCRIPT > "$OUTPUT_DIR/ftp_anon.txt" 2>&1
user anonymous anonymous
ls
quit
END_SCRIPT
    if grep -q "Login successful" "$OUTPUT_DIR/ftp_anon.txt"; then
        echo -e "${GREEN}[+] Anonymous FTP login allowed!${NC}"
    else
        echo -e "${RED}[-] Anonymous FTP login failed.${NC}"
    fi
fi

# Samba Scanning (Ports 139, 445)
if grep -qE "139/tcp|445/tcp" "$OUTPUT_DIR/nmap.txt"; then
    echo -e "${YELLOW}[*] SMB detected! Enumerating shares...${NC}"
    smbclient -L "$target" -N > "$OUTPUT_DIR/smb_shares.txt" 2>&1 || echo -e "${RED}[-] SMB enumeration failed.${NC}"
    echo -e "${YELLOW}[*] Checking for SMB vulnerabilities...${NC}"
    nmap --script smb-vuln* -p 139,445 "$target" > "$OUTPUT_DIR/smb_vulns.txt" 2>&1
fi


# check for https/http 

# Detect a web server (HTTP or HTTPS)
if grep -q "443/tcp" "$OUTPUT_DIR/nmap.txt"; then
    for PROTOCOL in http https; do
        echo -e "${YELLOW}[*] Web server detected on $PROTOCOL. Running WhatWeb...${NC}"
        whatweb "$PROTOCOL://$target" > "$OUTPUT_DIR/whatweb_$PROTOCOL.txt"
        dirb "$PROTOCOL://$target" > "$OUTPUT_DIR/dirs_$PROTOCOL.txt"
        nikto -h "$PROTOCOL://$target" -o "$OUTPUT_DIR/nikto_$PROTOCOL.txt"
    done
elif grep -q "80/tcp" "$OUTPUT_DIR/nmap.txt"; then
    echo -e "${YELLOW}[*] Web server detected on http. Running WhatWeb...${NC}"
    whatweb "http://$target" > "$OUTPUT_DIR/whatweb_http.txt"
    dirb "http://$target" > "$OUTPUT_DIR/dirs_http.txt"
    nikto -h "http://$target" -o "$OUTPUT_DIR/nikto_http.txt"
else
    echo -e "${RED}[-] No web server found. Skipping Web scans.${NC}"
fi



# Check for other ports (like SSH on 22)
if grep -q "22/tcp" "$OUTPUT_DIR/nmap.txt"; then
    echo -e "${YELLOW}[*] SSH detected! Grabbing banner...${NC}"
    nc -v -n "$target" 22 > "$OUTPUT_DIR/ssh_banner.txt" 2>&1 || echo -e "${RED}[-] Couldn’t grab SSH banner, oh well!${NC}"
fi

# scann DNS and whois 
echo -e "${GREEN}[+] Gathering WHOIS info...${NC}"
whois "$target" > "$OUTPUT_DIR/whois.txt"

echo -e "${GREEN}[+] Gathering DNS info...${NC}"
dig "$target" ANY +noall +answer > "$OUTPUT_DIR/dns.txt" 2>/dev/null || echo -e "${RED}[-] Dig failed, no worries!${NC}"


# DNS enumeration with fierce
echo -e "${YELLOW}[*] Running fierce for DNS enumeration...${NC}"
fierce -dns "$target" > "$OUTPUT_DIR/fierce.txt" 2>/dev/null || echo -e "${RED}[-] Fierce stumbled, moving along!${NC}"


# Subdomain enumeration with Sublist3r
echo -e "${YELLOW}[*] Hunting subdomains with Sublist3r...${NC}"
sublist3r -d "$target" -o "$OUTPUT_DIR/subdomains.txt" 2>/dev/null || echo -e "${RED}[-] Sublist3r didn’t pan out, oh well!${NC}"


# Exploit Search
echo -e "${YELLOW}[*] Searching for exploits based on Nmap results...${NC}"
searchsploit --nmap "$OUTPUT_DIR/nmap.txt" > "$OUTPUT_DIR/exploits.txt" 2>/dev/null || echo -e "${RED}[-] Exploit search failed.${NC}"

echo -e "${GREEN}[+] Recon complete! Check results in $OUTPUT_DIR${NC}"
echo -e "${GREEN}[+] Cooking up a summary for ya...${NC}"
{
    echo "=== AutoRecon Summary for $target ==="
    echo "Date: $DATE"
    echo "Nmap Open Ports: $(grep "open" "$OUTPUT_DIR/nmap.txt" | wc -l)"
    echo "Subdomains Found: $(wc -l < "$OUTPUT_DIR/subdomains.txt" 2>/dev/null || echo 'N/A')"
    echo "Web Server: $(grep -qE "80/tcp|443/tcp" "$OUTPUT_DIR/nmap.txt" && echo 'Yes' || echo 'No')"
    echo "Full results in: $OUTPUT_DIR"
} > "$OUTPUT_DIR/summary.txt"



