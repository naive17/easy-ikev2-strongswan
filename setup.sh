#!/bin/bash

set -e

# Check if running as root or sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo: sudo bash vpn-setup.sh"
  exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
  echo "Docker not found. Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  if command -v systemctl &> /dev/null; then
    systemctl enable docker
    systemctl start docker
  elif command -v service &> /dev/null; then
    service docker start
  fi
fi

# Auto-detect public IP
echo "Detecting server IP..."
SERVER_IP=$(curl -s https://api.ipify.org 2>/dev/null) || \
SERVER_IP=$(curl -s https://ifconfig.me 2>/dev/null) || \
SERVER_IP=$(curl -s https://icanhazip.com 2>/dev/null) || \
SERVER_IP=$(curl -s https://ipecho.net/plain 2>/dev/null) || \
SERVER_IP=$(ip route get 1 | awk '{print $NF;exit}' 2>/dev/null) || \
SERVER_IP=$(hostname -I | awk '{print $1}')

if [ -z "$SERVER_IP" ]; then
  echo "Could not auto-detect IP. Please enter it manually:"
  read -r SERVER_IP
else
  echo "Detected IP: $SERVER_IP"
  read -rp "Is this correct? [Y/n]: " confirm
  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    read -rp "Enter server IP: " SERVER_IP
  fi
fi

# Ask for credentials
read -rp "Enter VPN username [myuser]: " VPN_USER
VPN_USER=${VPN_USER:-myuser}

while true; do
  read -rsp "Enter VPN password [mypassword]: " VPN_PASSWORD
  echo
  VPN_PASSWORD=${VPN_PASSWORD:-mypassword}
  read -rsp "Confirm VPN password [mypassword]: " VPN_PASSWORD_CONFIRM
  echo
  VPN_PASSWORD_CONFIRM=${VPN_PASSWORD_CONFIRM:-mypassword}
  if [ "$VPN_PASSWORD" = "$VPN_PASSWORD_CONFIRM" ]; then
    break
  fi
  echo "Passwords do not match, try again."
done

# Generate random PSK
VPN_PSK=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 24)

# Setup
echo ""
echo "Setting up IKEv2 VPN server..."
echo "  Server IP : $SERVER_IP"
echo "  Username  : $VPN_USER"
echo ""

mkdir -p /etc/ipsec.d/{private,certs,cacerts}

# Generate certificates
docker run --rm -v /etc/ipsec.d:/etc/ipsec.d philplckthun/strongswan bash -c "
  ipsec pki --gen --type rsa --size 4096 --outform pem > /etc/ipsec.d/private/ca-key.pem && \
  ipsec pki --self --ca --lifetime 3650 --in /etc/ipsec.d/private/ca-key.pem --type rsa --dn 'CN=VPN CA' --outform pem > /etc/ipsec.d/cacerts/ca-cert.pem && \
  ipsec pki --gen --type rsa --size 2048 --outform pem > /etc/ipsec.d/private/server-key.pem && \
  ipsec pki --pub --in /etc/ipsec.d/private/server-key.pem --type rsa | ipsec pki --issue --lifetime 730 \
    --cacert /etc/ipsec.d/cacerts/ca-cert.pem \
    --cakey /etc/ipsec.d/private/ca-key.pem \
    --dn 'CN=$SERVER_IP' --san '$SERVER_IP' \
    --flag serverAuth --flag ikeIntermediate \
    --outform pem > /etc/ipsec.d/certs/server-cert.pem
"

# Write ipsec.conf
cat > /etc/ipsec.d/ipsec.conf << EOF
config setup
  uniqueids=no
  charondebug="cfg 2, dmn 2, ike 2, net 0"
conn %default
  dpdaction=clear
  dpddelay=300s
  rekey=no
  left=%defaultroute
  leftfirewall=yes
  right=%any
  ikelifetime=60m
  keylife=20m
  rekeymargin=3m
  keyingtries=1
  auto=add
conn IKEv2-EAP
  keyexchange=ikev2
  leftsubnet=0.0.0.0/0
  leftcert=server-cert.pem
  leftsendcert=always
  leftid=$SERVER_IP
  rightauth=eap-mschapv2
  rightsourceip=10.10.10.0/24
  rightdns=8.8.8.8
  rightsendcert=never
  eap_identity=%any
EOF

# Write ipsec.secrets
cat > /etc/ipsec.d/ipsec.secrets << EOF
: RSA server-key.pem
: PSK "$VPN_PSK"
$VPN_USER : EAP "$VPN_PASSWORD"
$VPN_USER : XAUTH "$VPN_PASSWORD"
EOF

# Stop and remove existing container if any
docker stop strongswan 2>/dev/null || true
docker rm strongswan 2>/dev/null || true

# Run container
docker run -d \
  --name strongswan \
  --restart=always \
  --cap-add=NET_ADMIN \
  --privileged \
  -e VPN_USER=$VPN_USER \
  -e VPN_PASSWORD=$VPN_PASSWORD \
  -e VPN_PSK=$VPN_PSK \
  -p 500:500/udp \
  -p 4500:4500/udp \
  -v /etc/ipsec.d:/etc/ipsec.d \
  --tmpfs /var/run \
  philplckthun/strongswan

echo ""
echo "================================================"
echo " IKEv2 VPN server is ready!"
echo "------------------------------------------------"
echo " Server IP  : $SERVER_IP"
echo " Remote ID  : $SERVER_IP"
echo " Username   : $VPN_USER"
echo " Password   : $VPN_PASSWORD"
echo "================================================"
