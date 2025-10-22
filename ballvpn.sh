#!/bin/bash
# =========================================
# BallVPN UDP Install Script (by บอลหลังวัง)
# Version 1.0
# =========================================

clear
echo -e "\033[1;36m╔════════════════════════════════════╗"
echo -e "║     🔰  BallVPN UDP Installer 🔰    ║"
echo -e "╚════════════════════════════════════╝\033[0m"

# ===== Password protect =====
PASSWORD="ballvpn"
read -sp "ใส่รหัสผ่านเพื่อเข้าใช้งาน: " input
echo ""
if [[ "$input" != "$PASSWORD" ]]; then
  echo -e "\033[1;31m❌ รหัสผ่านไม่ถูกต้อง! ออกจากสคริปต์...\033[0m"
  exit 1
fi
echo -e "\033[1;32m✅ เข้าสู่ระบบสำเร็จ!\033[0m"
sleep 1

# ===== Detect Interface =====
IFACE=$(ip -o -4 route show to default | awk '{print $5}')
IP=$(curl -s ifconfig.me)
VPN_SUBNET="10.8.0.0/16"
PORT_UDP=5667

clear
echo -e "\n🌐 Interface: $IFACE"
echo -e "🌎 Public IP: $IP"
echo -e "📡 UDP Port : $PORT_UDP"
echo -e "--------------------------------------"

# ===== Enable IP Forward =====
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q 'net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

# ===== Install Dependencies =====
apt update -y >/dev/null 2>&1
apt install -y net-tools curl iptables-persistent >/dev/null 2>&1

# ===== Setup UDP Forward / NAT =====
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING

iptables -t nat -A PREROUTING -i $IFACE -p udp --dport 22000:28000 -j DNAT --to-destination :$PORT_UDP
iptables -t nat -A PREROUTING -i $IFACE -p udp --dport 53 -j REDIRECT --to-ports 5300
iptables -t nat -A POSTROUTING -s $VPN_SUBNET -j SNAT --to-source $IP

# ===== Save Rules =====
iptables-save > /etc/iptables/rules.v4
netfilter-persistent save >/dev/null 2>&1

# ===== Finish =====
clear
echo -e "\033[1;32m🎉 ติดตั้งระบบ UDP (BallVPN) สำเร็จ!\033[0m"
echo -e "--------------------------------------"
echo -e "🌎 IP  : $IP"
echo -e "📡 UDP : $PORT_UDP"
echo -e "🧩 IF  : $IFACE"
echo -e "--------------------------------------"
echo -e "🔥 ใช้กับแอพ BallVPN หรือ HTTP Custom ได้ทันที"
echo -e "📜 กฎ iptables ถูกบันทึกถาวรเรียบร้อยแล้ว"
echo -e "\033[1;36m--------------------------------------\033[0m"
