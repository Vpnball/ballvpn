#!/usr/bin/env bash
# =========================================
# BallVPN UDP Manager (Menu v2)
# by บอลหลังวัง
# =========================================
set -euo pipefail

# ==== ตั้งรหัสผ่านเข้าหน้าเมนู ====
PASSWORD="${PASSWORD:-ballvpn}"   # เปลี่ยนได้ หรือส่งค่า env PASSWORD=xxx ตอนรันก็ได้

# ==== ค่าพื้นฐาน ====
VPN_SUBNET="${VPN_SUBNET:-10.8.0.0/16}"
DEF_DNAT_LO="${DNAT_LO:-22000}"
DEF_DNAT_HI="${DNAT_HI:-28000}"
DEF_UDP_PORT="${UDP_PORT:-5667}"
DEF_REDIR53="${REDIR53:-5300}"

GREEN='\033[1;32m'; RED='\033[1;31m'; CYAN='\033[1;36m'; YLW='\033[1;33m'; NC='\033[0m'

title() {
  echo -e "${CYAN}\n╔════════════════════════════════════╗"
  echo -e "║     🔰  BallVPN UDP Menu v2 🔰       ║"
  echo -e "╚════════════════════════════════════╝${NC}"
}

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}กรุณารันด้วย root (sudo)${NC}"; exit 1
  fi
}

ask_pass() {
  read -rsp "ใส่รหัสผ่านเพื่อเข้าเมนู: " input; echo
  [[ "$input" == "$PASSWORD" ]] || { echo -e "${RED}❌ รหัสผ่านไม่ถูกต้อง${NC}"; exit 1; }
}

get_iface() {
  ip -o -4 route show to default | awk '{print $5}' | head -n1
}

is_private() {
  [[ "$1" =~ ^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]
}

get_pubip() {
  local ifc="$1"
  # ลองจาก addr บน iface ก่อน
  local ips; ips=$(ip -4 addr show dev "$ifc" | awk '/inet /{print $2}' | cut -d/ -f1)
  for ip in $ips; do if ! is_private "$ip"; then echo "$ip"; return; fi; done
  # ค่อย fallback ออกเน็ต
  (curl -s --max-time 3 ifconfig.me || true)
}

save_rules() {
  mkdir -p /etc/iptables
  iptables-save > /etc/iptables/rules.v4
  command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1 || true
}

enable_forward() {
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  grep -q 'net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
}

install_deps() {
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y curl iptables-persistent >/dev/null 2>&1 || true
}

clear_nat_dups() {
  # ล้างรายการซ้ำที่เราจะใส่ใหม่เฉพาะที่เกี่ยวข้อง (ไม่ล้างทั้งหมด)
  local ifc="$1" lo="$2" hi="$3" uport="$4" r53="$5" pubip="$6"
  # DNAT ช่วงพอร์ต
  while iptables -t nat -C PREROUTING -i "$ifc" -p udp --dport "$lo:$hi" -j DNAT --to-destination ":$uport" 2>/dev/null; do
    iptables -t nat -D PREROUTING -i "$ifc" -p udp --dport "$lo:$hi" -j DNAT --to-destination ":$uport"
  done
  # REDIRECT 53
  while iptables -t nat -C PREROUTING -i "$ifc" -p udp --dport 53 -j REDIRECT --to-ports "$r53" 2>/dev/null; do
    iptables -t nat -D PREROUTING -i "$ifc" -p udp --dport 53 -j REDIRECT --to-ports "$r53"
  done
  # SNAT
  while iptables -t nat -C POSTROUTING -s "$VPN_SUBNET" -j SNAT --to-source "$pubip" 2>/dev/null; do
    iptables -t nat -D POSTROUTING -s "$VPN_SUBNET" -j SNAT --to-source "$pubip"
  done
}

set_core_rules() {
  local ifc="$1" lo="$2" hi="$3" uport="$4" r53="$5" pubip="$6"
  # กฎหลัก
  iptables -t nat -A PREROUTING -i "$ifc" -p udp --dport "$lo:$hi" -j DNAT --to-destination ":$uport"
  iptables -t nat -A PREROUTING -i "$ifc" -p udp --dport 53 -j REDIRECT --to-ports "$r53"
  iptables -t nat -A POSTROUTING -s "$VPN_SUBNET" -j SNAT --to-source "$pubip"
}

install_all() {
  title
  echo -e "${YLW}กำลังติดตั้ง/ตั้งค่าหลัก...${NC}"
  enable_forward
  install_deps
  local ifc; ifc=$(get_iface); [[ -n "$ifc" ]] || { echo -e "${RED}ไม่พบ default interface${NC}"; exit 1; }
  local pub; pub=$(get_pubip "$ifc"); [[ -n "$pub" ]] || { echo -e "${RED}หา Public IP ไม่ได้${NC}"; exit 1; }

  clear_nat_dups "$ifc" "$DEF_DNAT_LO" "$DEF_DNAT_HI" "$DEF_UDP_PORT" "$DEF_REDIR53" "$pub"
  set_core_rules "$ifc" "$DEF_DNAT_LO" "$DEF_DNAT_HI" "$DEF_UDP_PORT" "$DEF_REDIR53" "$pub"
  save_rules

  echo -e "${GREEN}\n🎉 ติดตั้งสำเร็จ${NC}"
  echo -e "🌎 IP  : $pub"
  echo -e "📡 UDP : $DEF_UDP_PORT"
  echo -e "🧩 IF  : $ifc"
}

add_dnat_range() {
  title
  local ifc; ifc=$(get_iface)
  read -rp "ช่วงพอร์ตต้น (เช่น 20000) [ค่าเดิม $DEF_DNAT_LO]: " lo; lo=${lo:-$DEF_DNAT_LO}
  read -rp "ช่วงพอร์ตท้าย (เช่น 28000) [ค่าเดิม $DEF_DNAT_HI]: " hi; hi=${hi:-$DEF_DNAT_HI}
  read -rp "ปลายทางภายใน (UDP port) [ค่าเดิม $DEF_UDP_PORT]: " up; up=${up:-$DEF_UDP_PORT}
  iptables -t nat -A PREROUTING -i "$ifc" -p udp --dport "$lo:$hi" -j DNAT --to-destination ":$up"
  save_rules
  echo -e "${GREEN}✅ เพิ่ม DNAT $lo:$hi -> :$up บน $ifc แล้ว${NC}"
}

flush_all_ballvpn() {
  title
  local ifc; ifc=$(get_iface)
  # ล้างเฉพาะรายการที่เรามักใช้ (ปลอดภัยกว่าล้างทั้ง table)
  iptables -t nat -S PREROUTING | grep -E "DNAT|REDIRECT" | awk '{print $0}' | \
  while read -r rule; do
    # แปลง -A เป็น -D เพื่อลบ
    iptables -t nat ${rule/-A /-D } 2>/dev/null || true
  done
  iptables -t nat -S POSTROUTING | grep SNAT | grep "$VPN_SUBNET" | awk '{print $0}' | \
  while read -r rule; do iptables -t nat ${rule/-A /-D } 2>/dev/null || true; done
  save_rules
  echo -e "${GREEN}✅ ล้างกฎ NAT ที่เกี่ยวกับ BallVPN แล้ว${NC}"
}

show_status() {
  title
  local ifc pub; ifc=$(get_iface); pub=$(get_pubip "$ifc")
  echo -e "🌎 Public IP : ${pub:-unknown}"
  echo -e "🧩 IFACE     : ${ifc:-unknown}"
  echo -e "🛣  IP Forward: $(sysctl -n net.ipv4.ip_forward 2>/dev/null)"
  echo -e "\n${YLW}== NAT PREROUTING ==${NC}"
  iptables -t nat -L PREROUTING -n -v | grep -E 'DNAT|REDIRECT' || echo "(ว่าง)"
  echo -e "\n${YLW}== NAT POSTROUTING ==${NC}"
  iptables -t nat -L POSTROUTING -n -v | grep SNAT || echo "(ว่าง)"
}

menu() {
  while :; do
    title
    echo -e "${YLW}1) ติดตั้ง/รีติดตั้ง BallVPN (DNAT+SNAT+save)${NC}"
    echo -e "${YLW}2) เพิ่ม DNAT ช่วงพอร์ต → :ปลายทาง UDP${NC}"
    echo -e "${YLW}3) ล้างกฎ BallVPN (DNAT/REDIRECT/SNAT)${NC}"
    echo -e "${YLW}4) แสดงสถานะ NAT / Interface / Forward${NC}"
    echo -e "${YLW}5) ออกเมนู${NC}"
    read -rp "เลือกเมนู [1-5]: " ans
    case "$ans" in
      1) install_all; read -rp "กด Enter เพื่อกลับเมนู...";;
      2) add_dnat_range; read -rp "กด Enter เพื่อกลับเมนู...";;
      3) flush_all_ballvpn; read -rp "กด Enter เพื่อกลับเมนู...";;
      4) show_status; read -rp "กด Enter เพื่อกลับเมนู...";;
      5) exit 0;;
      *) echo -e "${RED}เมนูไม่ถูกต้อง${NC}"; sleep 1;;
    esac
  done
}

# ==== MAIN ====
need_root
title
ask_pass
menu
