#!/bin/bash

# OpenVPN TOTP Connection Script for macOS

# Configuration
CONFIG_FILE="" # OVPN Config File
USERNAME="" # Connection username
CONSTANT_STRING="" # if totp password needs a constant string, remain empty if none 
TOTP_SECRET="" # the totp secret

# Files
TEMP_CREDS="/tmp/openvpn_creds_$$"
LOG_FILE="/tmp/openvpn_session_$$.log"

# Global variables
OPENVPN_PID=""
TAIL_PID=""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Flag Handling ---
SHOW_LOGS=false
for arg in "$@"; do
    if [[ "$arg" == "--verbose" ]]; then
        SHOW_LOGS=true
        break
    fi
done

# Simple logging functions
log_info() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] ℹ️${NC}  $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️${NC}  $1"
}

log_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ❌${NC} $1"
}

# Show connection info (simplified)
show_connection_info() {
    log_info "Checking connection status..."
    
    # Check for VPN interface
    VPN_INTERFACE=$(ifconfig 2>/dev/null | grep -E "^(tun|tap|utun)" | head -1 | cut -d: -f1)
    if [[ -n "$VPN_INTERFACE" ]]; then
        VPN_IP=$(ifconfig "$VPN_INTERFACE" 2>/dev/null | grep "inet " | awk '{print $2}' | head -1)
        log_success "VPN Interface: $VPN_INTERFACE"
        if [[ -n "$VPN_IP" ]]; then
            log_success "VPN IP: $VPN_IP"
        fi
    else
        log_info "No VPN interface detected yet"
    fi
}

# Cleanup function
cleanup() {
    echo ""
    log_warning "Cleaning up and disconnecting..."
    
    # Kill tail process
    if [[ -n "$TAIL_PID" ]] && kill -0 "$TAIL_PID" 2>/dev/null; then
        sudo kill "$TAIL_PID" 2>/dev/null
    fi
    
    # Kill OpenVPN
    if [[ -n "$OPENVPN_PID" ]] && kill -0 "$OPENVPN_PID" 2>/dev/null; then
        log_info "Terminating OpenVPN (PID: $OPENVPN_PID)..."
        sudo kill "$OPENVPN_PID" 2>/dev/null
        sleep 2
        
        # Force kill if needed
        if kill -0 "$OPENVPN_PID" 2>/dev/null; then
            log_warning "Force killing OpenVPN..."
            sudo kill -9 "$OPENVPN_PID" 2>/dev/null
        fi
    fi
    
    # Cleanup files
    [[ -f "$TEMP_CREDS" ]] && rm -f "$TEMP_CREDS"
    [[ -f "$LOG_FILE" ]] && sudo rm -f "$LOG_FILE"
    
    log_success "Disconnected successfully"
    exit 0
}

# Signal handler
handle_signal() {
    echo ""
    log_warning "Ctrl+C pressed. Disconnecting..."
    cleanup
}

trap handle_signal SIGINT SIGTERM
trap cleanup EXIT

# Generate TOTP
generate_totp() {
    if command -v oathtool >/dev/null 2>&1; then
        oathtool --totp -b "$1"
    else
        log_error "oathtool not found. Install with: brew install oath-toolkit"
        exit 1
    fi
}

# Main script
clear
echo "🔐 OpenVPN TOTP Connector"
echo "=================================="
echo ""

# Check config file
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

# Generate TOTP
log_info "Generating TOTP..."
TOTP=$(generate_totp "$TOTP_SECRET")
if [[ -z "$TOTP" ]]; then
    log_error "Failed to generate TOTP"
    exit 1
fi

PASSWORD="${CONSTANT_STRING}${TOTP}"
log_success "TOTP generated: $TOTP"

# Create credentials
cat > "$TEMP_CREDS" << EOF
$USERNAME
$PASSWORD
EOF

# Show initial status
show_connection_info

# Start OpenVPN
log_info "Starting OpenVPN..."
log_warning "Closing this terminal will disconnect the VPN!"
log_info "Press Ctrl+C to disconnect safely"
echo ""
echo "📋 OpenVPN Logs:"
echo "================"

# Start OpenVPN in background and capture PID
sudo openvpn --config "$CONFIG_FILE" \
             --auth-user-pass "$TEMP_CREDS" \
             --verb 3 \
             --log "$LOG_FILE" &

OPENVPN_PID=$!
log_info "OpenVPN started with PID: $OPENVPN_PID"

# Wait for log file to be created
sleep 2

# Check if OpenVPN is still running
if ! kill -0 "$OPENVPN_PID" 2>/dev/null; then
    log_error "OpenVPN failed to start"
    if $SHOW_LOGS && [[ -f "$LOG_FILE" ]]; then
        echo "Recent log entries:"
        sudo tail -10 "$LOG_FILE" 2>/dev/null
    fi
    exit 1
fi

# Follow logs
if $SHOW_LOGS && [[ -f "$LOG_FILE" ]]; then
    echo "----------------------------------------"
    sudo tail -f "$LOG_FILE" &
    TAIL_PID=$!
    
    # Connection detection
    CONNECTED=false
    for i in {1..30}; do
        if [[ -f "$LOG_FILE" ]] && grep -q "Initialization Sequence Completed\|CONNECTED" "$LOG_FILE" 2>/dev/null; then
            CONNECTED=true
            break
        fi
        sleep 1
    done
    
    if [[ "$CONNECTED" == "true" ]]; then
        echo ""
        log_success "🎉 VPN Connection Established!"
        sleep 2
        show_connection_info
        echo "----------------------------------------"
    fi
else
    log_warning "Log file not created, running without live logs"
    sleep 2
    log_success "🎉 VPN Connection Established!"
    echo ""
fi

# Wait for OpenVPN to exit
wait "$OPENVPN_PID"
EXIT_CODE=$?

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
    log_success "OpenVPN disconnected normally"
else
    log_warning "OpenVPN exited with code: $EXIT_CODE"
fi