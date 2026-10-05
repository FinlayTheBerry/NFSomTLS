#!/bin/sh

cd "$(dirname "$(realpath "$0")")"

if [ "$(id -u)" != "0" ]; then
    echo "This script requires root. Try sudo $0"
    exit 1
fi

if [ ! -f "./nfsomtls.crt" ]; then
    echo "./nfsomtls.crt does not exist. Please copy it from /nfs_certificates/nfsomtls.crt on the server."
    exit 1
fi

if [ ! -f "./nfsomtls.key" ]; then
    echo "./nfsomtls.key does not exist. Please copy it from /nfs_certificates/nfsomtls.key on the server."
    exit 1
fi

if [ ! -f "./server_ip" ]; then
    echo "./server_ip does not exist. Please create it and paste the server IP address inside."
    exit 1
fi

install -o +0 -g +0 -m 600 -d /nfs_certificates/
install -o +0 -g +0 -m 600 -d /nfs/

pacman -S --needed --noconfirm iptables 1>/dev/null 2>&1
read -r -d '' iptables_dot_rules << EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# Allow loopback
-A INPUT -i lo -j ACCEPT
# Allow responses to connections initiated by this PC
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
# Allow inbound traffic from tailscale
-A INPUT -i tailscale0 -j ACCEPT

COMMIT
EOF
echo "${iptables_dot_rules}" > /etc/iptables/iptables.rules
install -o +0 -g +0 -m 644  /etc/iptables/iptables.rules /etc/iptables/iptables.rules
systemctl enable --now iptables
systemctl restart iptables
read -r -d '' ip6tables_dot_rules << EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# Allow loopback
-A INPUT -i lo -j ACCEPT
# Allow responses to connections initiated by this PC
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
# Allow inbound traffic from tailscale
-A INPUT -i tailscale0 -j ACCEPT

COMMIT
EOF
echo "${ip6tables_dot_rules}" > /etc/iptables/ip6tables.rules
install -o +0 -g +0 -m 644  /etc/iptables/ip6tables.rules /etc/iptables/ip6tables.rules
systemctl enable --now ip6tables
systemctl restart ip6tables

read -r -d '' fstab << EOF

# NFS
$(cat ./server_ip):/ /nfs nfs rw,hard,tcp,nconnect=4,nfsvers=4.2,timeo=15,port=56366,nofail,_netdev,xprtsec=mtls 0 0
EOF
echo "${fstab}" >> /etc/fstab
nano /etc/fstab

sudo -u yaybld yay -S --needed --noconfirm ktls-utils 1>/dev/null 2>&1
read -r -d '' tlshd_config << EOF
#
# Copyright (c) 2022 Oracle and/or its affiliates.
#
# This file is part of ktls-utils.
#
# ktls-utils is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301, USA.
#
# See tlshd.conf(5) for details.
#

[debug]
loglevel=4
tls=4
nl=4

[authenticate]
#keyrings= <keyring>;<keyring>;<keyring>
#dane= off | opportunistic | require
#dane.trust_anchor= <pathname>
#dane.resolver= <address>;<address>

[authenticate.client]
x509.truststore= /nfs_certificates/nfsomtls.crt
#x509.crl= <pathname>
x509.certificate= /nfs_certificates/nfsomtls.crt
x509.private_key= /nfs_certificates/nfsomtls.key
#x509.pq.certificate= <pathname>
#x509.pq.private_key= <pathname>

[authenticate.server]
x509.truststore= /nfs_certificates/nfsomtls.crt
#x509.crl= <pathname>
x509.certificate= /nfs_certificates/nfsomtls.crt
x509.private_key= /nfs_certificates/nfsomtls.key
#x509.pq.certificate= <pathname>
#x509.pq.private_key= <pathname>
EOF
echo "${tlshd_config}" > /etc/tlshd/config
install -o +0 -g +0 -m 644 /etc/tlshd/config /etc/tlshd/config
install -o +0 -g +0 -m 600 ./nfsomtls.key /nfs_certificates/nfsomtls.key
install -o +0 -g +0 -m 600 ./nfsomtls.crt /nfs_certificates/nfsomtls.crt
systemctl enable --now tlshd
systemctl restart tlshd

echo "Done!"

