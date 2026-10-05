#!/bin/sh

cd "$(dirname "$(realpath "$0")")"

if [ "$(id -u)" != "0" ]; then
    echo "This script requires root. Try sudo $0"
    exit 1
fi

install -o +0 -g +0 -m 600 -d /nfs_certificates/

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

pacman -S --needed --noconfirm nfs-utils 1>/dev/null 2>&1
read -r -d '' nfs_dot_conf << EOF
[general]
# pipefs-directory=/var/lib/nfs/rpc_pipefs
#
[nfsrahead]
# nfs=15000
# nfs4=16000
#
[exports]
# rootdir=/export
#
[exportfs]
# debug=0
#
[gssd]
# verbosity=0
# rpc-verbosity=0
# use-memcache=0
# use-machine-creds=1
# use-gss-proxy=0
# avoid-dns=1
# allowed-enctypes=aes256-cts-hmac-sha384-192,aes128-cts-hmac-sha256-128,camellia256-cts-cmac,camellia128-cts-cmac,aes256-cts-hmac-sha1-96,aes128-cts-hmac-sha1-96
# context-timeout=0
# rpc-timeout=5
# keytab-file=/etc/krb5.keytab
# cred-cache-directory=
# preferred-realm=
# set-home=1
# upcall-timeout=30
# cancel-timed-out-upcalls=0
#
[lockd]
# port=0
# udp-port=0
#
[exportd]
# debug="all|auth|call|general|parse"
# manage-gids=n
# state-directory-path=/var/lib/nfs
# threads=1
# cache-use-ipaddr=n
# ttl=1800
# no-netlink=0
#
[mountd]
# debug="all|auth|call|general|parse"
# apply-root-cred=n
manage-gids=y
# descriptors=0
port=0
# threads=1
# reverse-lookup=n
# state-directory-path=/var/lib/nfs
# ha-callout=
# cache-use-ipaddr=n
# ttl=1800
# no-netlink=0
#
[nfsdcld]
# debug=0
# storagedir=/var/lib/nfs/nfsdcld
#
[nfsd]
host=$(tailscale ip -4)
# debug=0
# threads=16
# host=
port=56366
# grace-time=90
# lease-time=90
udp=n
tcp=y
vers2=no
vers3=n
vers4=n
vers4.0=n
vers4.1=n
vers4.2=y
rdma=n
# rdma-port=20049
# fh-key-file=/etc/nfs_fh.key

[statd]
# debug=0
# port=0
# outgoing-port=0
# name=
# state-directory-path=/var/lib/nfs/statd
# ha-callout=
# no-notify=0
#
[sm-notify]
# debug=0
# force=0
# retry-time=900
# outgoing-port=
# outgoing-addr=
# lift-grace=y
#
[svcgssd]
# principal=
EOF
echo "${nfs_dot_conf}" > /etc/nfs.conf
install -o +0 -g +0 -m 644 /etc/nfs.conf /etc/nfs.conf
read -r -d '' exports << EOF
/finserv/ 100.64.0.0/10(rw,sync,no_subtree_check,no_root_squash,crossmnt,xprtsec=mtls)
/important_data/ 100.64.0.0/10(rw,sync,no_subtree_check,no_root_squash,crossmnt,xprtsec=mtls)
EOF
echo "${exports}" > /etc/exports
install -o +0 -g +0 -m 644 /etc/exports /etc/exports
systemctl disable --now nfs-mountd 1>/dev/null 2>&1
systemctl mask nfs-mountd
systemctl disable --now nfs-server 1>/dev/null 2>&1
systemctl mask nfs-server
systemctl disable --now rpcbind 1>/dev/null 2>&1
systemctl mask rpcbind
systemctl enable --now nfsv4-server
systemctl restart nfsv4-server
exportfs -arv -d all 1>/dev/null 2>&1

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
loglevel=0
tls=0
nl=0

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
read -r -d '' openssl_dot_conf << EOF
[ req ]
default_bits        = 4096
distinguished_name  = req_distinguished_name
x509_extensions     = v3_ca_and_tls
prompt              = no

[ req_distinguished_name ]
CN = NFS over mTLS Certificate

[ v3_ca_and_tls ]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, digitalSignature, keyEncipherment, keyCertSign, cRLSign
extendedKeyUsage = serverAuth, clientAuth

subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = flamecraft.net
IP.1  = $(tailscale ip -4)
EOF
echo "${openssl_dot_conf}" > /nfs_certificates/openssl.conf
install -o +0 -g +0 -m 600 /nfs_certificates/openssl.conf /nfs_certificates/openssl.conf
if [ ! -f "/nfs_certificates/nfsomtls.key" ]; then
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out /nfs_certificates/nfsomtls.key
    install -o +0 -g +0 -m 600 /nfs_certificates/nfsomtls.key /nfs_certificates/nfsomtls.key
else
    echo "/nfs_certificates/nfsomtls.key already exists. Leaving as is."
fi
if [ ! -f "/nfs_certificates/nfsomtls.crt" ]; then
    openssl req -x509 -new -nodes -key /nfs_certificates/nfsomtls.key -out /nfs_certificates/nfsomtls.crt -days 3650 -config /nfs_certificates/openssl.conf
    install -o +0 -g +0 -m 600 /nfs_certificates/nfsomtls.crt /nfs_certificates/nfsomtls.crt
else
    echo "/nfs_certificates/nfsomtls.crt already exists. Leaving as is."
fi
rm /nfs_certificates/openssl.conf
systemctl enable --now tlshd
systemctl restart tlshd

echo "Done!"
