#!/usr/bin/env bash

OS="$(uname -s)"

echo "==============================================="
echo "       SERVER PERFORMANCE STATS ($OS)          "
echo "==============================================="

# --- NEW: System Information (OS, Uptime, Load, Users) ---
echo -e "\n--- System Information ---"
if [ "$OS" = "Linux" ]; then
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "OS Version: $PRETTY_NAME"
    else
        echo "OS Version: Linux (Distribution unknown)"
    fi
elif [ "$OS" = "Darwin" ]; then
    echo "OS Version: $(sw_vers -productName) $(sw_vers -productVersion)"
fi

# The 'uptime' command universally outputs current time, uptime duration, logged in users, and load averages.
UPTIME_OUT=$(uptime)
echo "Uptime & Load: $UPTIME_OUT"

echo -e "\n--- Logged In Sessions ---"
who | awk '{print $1 " connected on " $2 " from " $3}'

# --- ORIGINAL: Hardware Stats ---
if [ "$OS" = "Linux" ]; then
    # Total CPU usage (Linux)
    echo -e "\n--- Total CPU Usage ---"
    read -r cpu user nice system idle iowait irq softirq steal _ < /proc/stat
    PREV_TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
    PREV_IDLE=$((idle + iowait))
    sleep 1
    read -r cpu user nice system idle iowait irq softirq steal _ < /proc/stat
    TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
    IDLE=$((idle + iowait))
    
    TOTAL_DIFF=$((TOTAL - PREV_TOTAL))
    IDLE_DIFF=$((IDLE - PREV_IDLE))
    CPU_USAGE=$((100 * (TOTAL_DIFF - IDLE_DIFF) / TOTAL_DIFF))
    echo "CPU Usage: ${CPU_USAGE}%"

    # Total memory usage (Linux)
    echo -e "\n--- Total Memory Usage ---"
    free -m | awk 'NR==2 {printf "Total: %s MB | Used: %s MB | Free: %s MB | Used Percentage: %.2f%%\n", $2, $3, $4, $3*100/$2}'

    # Total disk usage (Linux)
    echo -e "\n--- Total Disk Usage ---"
    df -h --total -x tmpfs -x devtmpfs | awk '/^total/ {printf "Total: %s | Used: %s | Free: %s | Used Percentage: %s\n", $2, $3, $4, $5}'

elif [ "$OS" = "Darwin" ]; then
    # Total CPU usage (macOS)
    echo -e "\n--- Total CPU Usage ---"
    CPU_USAGE=$(top -l 2 -s 1 | awk '/^CPU usage/ {idle=$7; sub(/%/, "", idle); print 100-idle}' | tail -n 1)
    echo "CPU Usage: ${CPU_USAGE}%"

    # Total memory usage (macOS)
    echo -e "\n--- Total Memory Usage ---"
    TOTAL_MEM_BYTES=$(sysctl -n hw.memsize)
    TOTAL_MEM_MB=$((TOTAL_MEM_BYTES / 1024 / 1024))
    
    VM_STAT=$(vm_stat)
    PAGE_SIZE=$(echo "$VM_STAT" | awk '/page size of/ {print $8}')
    FREE_PAGES=$(echo "$VM_STAT" | awk '/Pages free/ {print $3}' | tr -d '.')
    INACTIVE_PAGES=$(echo "$VM_STAT" | awk '/Pages inactive/ {print $3}' | tr -d '.')
    SPEC_PAGES=$(echo "$VM_STAT" | awk '/Pages speculative/ {print $3}' | tr -d '.')
    
    FREE_MEM_MB=$(((FREE_PAGES + INACTIVE_PAGES + SPEC_PAGES) * PAGE_SIZE / 1024 / 1024))
    USED_MEM_MB=$((TOTAL_MEM_MB - FREE_MEM_MB))
    USED_PCT=$(awk "BEGIN {printf \"%.2f\", ($USED_MEM_MB / $TOTAL_MEM_MB) * 100}")
    
    echo "Total: ${TOTAL_MEM_MB} MB | Used: ${USED_MEM_MB} MB | Free: ${FREE_MEM_MB} MB | Used Percentage: ${USED_PCT}%"

    # Total disk usage (macOS)
    echo -e "\n--- Total Disk Usage ---"
    df -m / | awk 'NR==2 {printf "Total: %.0f MB | Used: %.0f MB | Free: %.0f MB | Used Percentage: %.2f%%\n", $2, $3, $4, $3*100/$2}'
fi

# --- ORIGINAL: Process Stats ---
echo -e "\n--- Top 5 Processes by CPU Usage ---"
ps -eo pid,comm,%cpu,%mem | head -n 1
ps -eo pid,comm,%cpu,%mem | tail -n +2 | sort -k3 -nr | head -n 5

echo -e "\n--- Top 5 Processes by Memory Usage ---"
ps -eo pid,comm,%cpu,%mem | head -n 1
ps -eo pid,comm,%cpu,%mem | tail -n +2 | sort -k4 -nr | head -n 5

# --- NEW: Failed Login Attempts ---
echo -e "\n--- Failed SSH/Login Attempts ---"
if [ "$EUID" -ne 0 ]; then
    echo "Skipping: Root privileges required. Run with 'sudo' to view failed logins."
else
    if [ "$OS" = "Linux" ]; then
        if [ -f /var/log/auth.log ]; then
            # Debian/Ubuntu based
            FAILS=$(grep -c "Failed password" /var/log/auth.log)
            echo "Failed attempts in /var/log/auth.log: $FAILS"
        elif [ -f /var/log/secure ]; then
            # RHEL/CentOS/Amazon Linux based
            FAILS=$(grep -c "Failed password" /var/log/secure)
            echo "Failed attempts in /var/log/secure: $FAILS"
        else
            echo "Authentication log file not found in standard locations."
        fi
    elif [ "$OS" = "Darwin" ]; then
        echo "Querying macOS Unified Log for the last 24 hours (this may take a few seconds)..."
        FAILS=$(log show --predicate 'process == "sshd" and eventMessage contains "Failed"' --last 24h 2>/dev/null | grep -c "Failed")
        echo "Failed SSH attempts (last 24h): $FAILS"
    fi
fi

echo -e "\n==============================================="
