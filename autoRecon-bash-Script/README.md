# AutoRecon Bash Script

This is a lightweight and beginner-friendly reconnaissance automation script written in Bash for penetration testers, bug bounty hunters, and CTF players. It gathers basic but essential information about a given target IP or domain and organizes the results into structured output files.

## Features

This script automates multiple common recon steps:

- Nmap scan with version and service detection
- Port-based conditional logic (e.g., SSH or Web Server)
- Banner grabbing (SSH)
- WHOIS lookup
- DNS enumeration (via `dig` and `fierce`)
- Subdomain enumeration (via `Sublist3r`)
- Web service fingerprinting (via `WhatWeb`)
- Directory brute-forcing (via `dirb`)
- Web vulnerability scanning (via `Nikto`)
- Clean output structure per target with summaries

##  Requirements

Make sure the following tools are installed:

- `nmap`
- `whois`
- `dig`
- `fierce`
- `sublist3r`
- `whatweb`
- `dirb`
- `nikto`   
- `nc` (netcat)

You can install them on Debian/Ubuntu via:

```bash
sudo apt update
sudo apt install nmap whois dnsutils fierce sublist3r whatweb dirb nikto netcat

                                
