#!/bin/bash

# Debian DNS Configuration Script
# This script sets DNS servers to 178.22.122.101 and 185.51.200.1
# Run with: sudo ./dns_setup.sh

DNS1="178.22.122.101"
DNS2="185.51.200.1"

echo "=== Debian DNS Configuration Script ==="
echo "Setting DNS servers to: $DNS1, $DNS2"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
   echo "This script needs to be run as root (use sudo)"
   echo "Usage: sudo $0"
   exit 1
fi

# Function to configure NetworkManager
configure_networkmanager() {
   echo "Using NetworkManager..."
   
   # Get all active connections
   CONNECTIONS=$(nmcli -t -f NAME connection show --active)
   
   if [ -z "$CONNECTIONS" ]; then
       echo "No active network connections found!"
       exit 1
   fi
   
   echo "Active connections found:"
   echo "$CONNECTIONS"
   
   # Configure each active connection
   while IFS= read -r connection; do
       echo "Configuring connection: $connection"
       
       # Set DNS servers
       nmcli connection modify "$connection" ipv4.dns "$DNS1,$DNS2"
       nmcli connection modify "$connection" ipv4.ignore-auto-dns yes
       nmcli connection modify "$connection" ipv6.ignore-auto-dns yes
       
       # Restart the connection
       nmcli connection down "$connection" 2>/dev/null
       sleep 1
       nmcli connection up "$connection"
       
       echo "   systemd-resolved configured"
}

# Function to configure traditional resolv.conf
configure_resolv_conf() {
   echo "Using traditional /etc/resolv.conf method..."
   
   # Backup original resolv.conf
   cp /etc/resolv.conf /etc/resolv.conf.backup 2>/dev/null
   
   # Remove immutable flag if exists
   chattr -i /etc/resolv.conf 2>/dev/null
   
   # Create new resolv.conf
   cat > /etc/resolv.conf << EOF
# Custom DNS servers - configured by script
# Backup available at /etc/resolv.conf.backup
nameserver $DNS1
nameserver $DNS2
nameserver 1.1.1.1
options timeout:2
options attempts:3
EOF
   
   # Make it immutable to prevent overwriting by DHCP
   chattr +i /etc/resolv.conf 2>/dev/null || echo "Warning: Could not make resolv.conf immutable"
   
   echo "   DHCP client configured"
fi

# Flush DNS cache if available
if command -v systemctl &> /dev/null; then
   if systemctl is-active --quiet systemd-resolved; then
       systemctl restart systemd-resolved
   fi
   if systemctl is-active --quiet nscd; then
       systemctl restart nscd
   fi
fi

echo ""
echo "=== Verifying DNS Configuration ==="

# Test DNS resolution
echo "Testing DNS resolution..."
if command -v dig &> /dev/null; then
   echo "Using dig to test DNS:"
   dig @$DNS1 google.com +short | head -n 1
elif command -v nslookup &> /dev/null; then
   echo "Using nslookup to test DNS:"
   nslookup google.com $DNS1 | grep "Address:" | tail -n 1
else
   echo "DNS testing tools not available"
fi

# Show current DNS configuration
echo ""
echo "Current DNS configuration:"
if command -v systemd-resolve &> /dev/null; then
   echo "systemd-resolved status:"
   systemd-resolve --status | grep -A 5 "DNS Servers" | head -n 5
elif command -v nmcli &> /dev/null && systemctl is-active --quiet NetworkManager; then
   echo "NetworkManager DNS settings:"
   nmcli device show | grep "IP4.DNS" | head -n 5
else
   echo "Contents of /etc/resolv.conf:"
   cat /etc/resolv.conf | grep -E "nameserver|search|domain"
fi

echo ""
echo "=== Configuration Complete ==="
echo " Configuration will persist across reboots"
echo ""
echo "To verify it's working, try:"
echo "  dig google.com"
echo "  nslookup google.com"
echo ""
echo "To revert changes, restore from backup files:"
echo "  /etc/resolv.conf.backup"
echo "  /etc/systemd/resolved.conf.backup (if exists)"
echo "  /etc/dhcp/dhclient.conf.backup (if exists)"
