#!/bin/bash
set -e

# Configuration directory
CONFIG_DIR="/etc/mtproxy"

# Function to get external IP from multiple providers
get_external_ip() {
    local providers=(
        "https://digitalresistance.dog/myIp"
        "https://ifconfig.me"
        "https://ip.me"
    )

    for provider in "${providers[@]}"; do
        local ip=$(curl -s -4 --connect-timeout 5 --max-time 10 "$provider" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done

    echo ""
    return 1
}

echo "####"
echo "#### MTProxy - Telegram Proxy"
echo "####"
echo

# Download proxy secret if not exists
if [ ! -f "$CONFIG_DIR/proxy-secret" ]; then
    echo "[+] Downloading proxy secret..."
    curl -s https://core.telegram.org/getProxySecret -o "$CONFIG_DIR/proxy-secret"
fi

# Download proxy config if not exists or older than 1 day
if [ ! -f "$CONFIG_DIR/proxy-multi.conf" ] || [ $(find "$CONFIG_DIR/proxy-multi.conf" -mtime +1 | wc -l) -gt 0 ]; then
    echo "[+] Downloading proxy config..."
    curl -s https://core.telegram.org/getProxyConfig -o "$CONFIG_DIR/proxy-multi.conf"
fi

# Generate secret if not provided
if [ -z "$SECRET" ]; then
    echo "[+] No SECRET provided, generating one..."
    export SECRET=$(head -c 16 /dev/urandom | xxd -ps)
    echo "[+] Generated secret: $SECRET"
else
    echo "[+] Using provided secret: $SECRET"
fi

# Validate SECRET format (should be 32 hex chars)
if ! echo "$SECRET" | grep -qE '^[0-9a-fA-F]{32}$'; then
    echo "[F] Bad secret format: should be 32 hex chars (for 16 bytes)."
    exit 1
fi

# Convert SECRET to lowercase
SECRET=$(echo "$SECRET" | tr '[:upper:]' '[:lower:]')

# Set default values
PORT=${PORT:-443}
STATS_PORT=${STATS_PORT:-8888}
WORKERS=${WORKERS:-1}
PROXY_TAG=${PROXY_TAG:-}

# Determine transport mode and generate client secret
CLIENT_SECRET=""
TRANSPORT_MODE="standard"
MTPROXY_ARGS=""

if [ -n "$DOMAIN" ]; then
    # EE Mode (Fake-TLS + Padding)
    TRANSPORT_MODE="EE (Fake-TLS)"
    DOMAIN_HEX=$(echo -n "$DOMAIN" | xxd -ps | tr -d '\n')
    CLIENT_SECRET="ee${SECRET}${DOMAIN_HEX}"
    MTPROXY_ARGS="-D $DOMAIN"
    echo "[+] EE Mode enabled with domain: $DOMAIN"
elif [ "$RANDOM_PADDING" = "true" ]; then
    # DD Mode (Random Padding only)
    TRANSPORT_MODE="DD (Random Padding)"
    CLIENT_SECRET="dd${SECRET}"
    MTPROXY_ARGS="-R"
    echo "[+] DD Mode enabled (random padding)"
else
    # Standard mode
    CLIENT_SECRET="$SECRET"
    echo "[+] Standard mode"
fi

# Get external IP
if [ -n "$EXTERNAL_IP" ]; then
    IP="$EXTERNAL_IP"
    echo "[+] Using provided external IP: $IP"
else
    echo "[+] Detecting external IP..."
    IP=$(get_external_ip)
    if [ -z "$IP" ]; then
        echo "[!] Warning: Cannot determine external IP address automatically."
        echo "[!] Please set EXTERNAL_IP environment variable."
        IP="YOUR_SERVER_IP"
    else
        echo "[+] Detected external IP: $IP"
    fi
fi

INTERNAL_IP="$(ip -4 route get 8.8.8.8 | grep '^8\.8\.8\.8\s' | grep -Po 'src\s+\d+\.\d+\.\d+\.\d+' | awk '{print $2}')"

if [[ -z "$INTERNAL_IP" ]]; then
  echo "[F] Cannot determine internal IP address."
  exit 4
fi

# Build mtproto-proxy command
CMD="./mtproto-proxy -u mtproxy -p $STATS_PORT -H $PORT -S $SECRET --http-stats --nat-info $INTERNAL_IP:$IP"

if [ -n "$PROXY_TAG" ]; then
    CMD="$CMD -P $PROXY_TAG"
    echo "[+] Using proxy tag: $PROXY_TAG"
fi

if [ -n "$MTPROXY_ARGS" ]; then
    CMD="$CMD $MTPROXY_ARGS"
fi

CMD="$CMD --aes-pwd $CONFIG_DIR/proxy-secret $CONFIG_DIR/proxy-multi.conf -M $WORKERS"

echo
echo "[*] =========================================="
echo "[*] Final configuration:"
echo "[*] =========================================="
echo "[*]   Transport mode: $TRANSPORT_MODE"
echo "[*]   Server secret: $SECRET"
echo "[*]   Client secret: $CLIENT_SECRET"
echo "[*]   External IP: $IP"
echo "[*]   Client port: $PORT"
echo "[*]   Stats port: $STATS_PORT (http://localhost:$STATS_PORT/stats)"
echo "[*]   Workers: $WORKERS"
[ -n "$PROXY_TAG" ] && echo "[*]   Proxy tag: $PROXY_TAG" || echo "[*]   Proxy tag: not set"
[ -n "$DOMAIN" ] && echo "[*]   Domain: $DOMAIN"
echo "[*] =========================================="
echo "[*] Connection links:"
echo "[*] =========================================="
echo "[*]   tg://proxy?server=${IP}&port=${PORT}&secret=${CLIENT_SECRET}"
echo "[*]"
echo "[*]   https://t.me/proxy?server=${IP}&port=${PORT}&secret=${CLIENT_SECRET}"
echo "[*] =========================================="
echo
echo "[+] Starting MTProxy..."
echo "[+] Command: $CMD"
echo

exec $CMD
