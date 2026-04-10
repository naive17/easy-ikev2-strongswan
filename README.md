# IKEv2 VPN Server

Self-hosted IKEv2 VPN server using StrongSwan in Docker. 
I made this to use it with [VPNmanager](https://apps.apple.com/it/app/vpnmanager/id6470751776) on iOS to create a **Personal VPN** — to allow ios 26.4> users to allow for the LocalDevVPN dual vpns setup.
I didn't want to use a sketchy vpn i didn't own or could not check.

## How it works

iOS allows two simultaneous VPN connections when one is a **Personal VPN** (created by an app using Apple's `NEVPNManager` API) and the other is a **Device VPN** (such as LocalDevVPN).

This script allow you to self host a bare minimum ikev2 VPN on a machine.
A very tiny Hetzner VPS will do it, like the smallest one available.

## Requirements

- A Linux server (Ubuntu/Debian recommended)
- Root or sudo access
- Docker (installed automatically if not present)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/your-username/your-repo/main/setup.sh | sudo bash
```

Or inspect first:

```bash
curl -fsSL https://raw.githubusercontent.com/your-username/your-repo/main/setup.sh -o setup.sh
cat setup.sh
sudo bash setup.sh
```

## Setup on iPhone

### 1. Install VPNmanager
Download [VPNmanager](https://apps.apple.com/it/app/vpnmanager/id6470751776) from the App Store.

### 2. Add your VPN
Open VPNmanager and create a new IKEv2 profile:

| Field | Value |
|---|---|
| Type | IKEv2 |
| Server | your server IP |
| Remote ID | your server IP |
| Username | your username |
| Password | your password |

### 3. Connect
Enable the VPN in VPNmanager. It will appear under **VPN Personale** in iOS Settings → VPN.

### 4. Enable LocalDevVPN
With the Personal VPN active, you can now enable LocalDevVPN at the same time and sideload apps without a PC.

## Persistence

Certificates and config are stored at `/etc/ipsec.d/` on the host. The container restarts automatically after a server reboot.

## Cleanup

```bash
docker stop strongswan && docker rm strongswan && rm -rf /etc/ipsec.d/private /etc/ipsec.d/certs /etc/ipsec.d/cacerts /etc/ipsec.d/ipsec.conf /etc/ipsec.d/ipsec.secrets
```
