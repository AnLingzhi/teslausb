#!/bin/bash
# shellcheck disable=SC2016
# SC2016 shellcheck wants double quotes for the free/used space calculation
# below, but that requires additional ugly escaping

if [[ -e /sys/kernel/config/usb_gadget/teslausb ]]
then
  drives_active=yes
else
  drives_active=no
fi

readarray -t snapshots < <(find /backingfiles/snapshots/ -name snap.bin 2> /dev/null | sort)
readonly numsnapshots=${#snapshots[@]}
if [[ "$numsnapshots" != "0" ]]
then
  oldestsnapshot=$(stat --format="%Y" "${snapshots[0]}")
  newestsnapshot=$(stat --format="%Y" "${snapshots[-1]}")
fi

wifidev=$(find /sys/class/net/ -type l -name 'wl*' -printf '%P' -quit)

wifi_ssid=""
wifi_freq=""
wifi_strength=""
wifi_ip=""

if [ -n "$wifidev" ]; then
  if command -v iw >/dev/null 2>&1; then
    iw_output=$(iw dev "$wifidev" link 2>/dev/null)
    wifi_ssid=$(echo "$iw_output" | awk -F': ' '/SSID:/ {print $2}')
    wifi_freq=$(echo "$iw_output" | awk -F': ' '/freq:/ {printf "%d", $2 * 1000000}')
    signal_dbm=$(echo "$iw_output" | awk -F': ' '/signal:/ {print int($2)}')
    wifi_strength=$(awk "BEGIN {printf \"%.2f\", ($signal_dbm + 90) / 60}")
  elif command -v iwgetid >/dev/null 2>&1; then
    wifi_ssid=$(iwgetid -r "$wifidev" 2>/dev/null || true)
    wifi_freq=$(iwgetid -f "$wifidev" 2>/dev/null || true)
  fi

  # 信号强度备用方案
  if [ -z "$wifi_strength" ] && command -v iwconfig >/dev/null 2>&1; then
    quality=$(iwconfig "$wifidev" 2>/dev/null | grep -i "Link Quality" | sed 's/.*Link Quality=\([0-9]*\)\/\([0-9]*\).*/\1 \2/')
    if [ -n "$quality" ]; then
      q1=$(echo "$quality" | cut -d' ' -f1)
      q2=$(echo "$quality" | cut -d' ' -f2)
      wifi_strength=$(awk "BEGIN {printf \"%.2f\", $q1 / $q2}")
    fi
  fi

  # 获取 IP 地址（IPv4）
  wifi_ip=$(ip -4 addr show dev "$wifidev" | awk '/inet / {print $2}' | cut -d/ -f1)
fi

ethdev=$(find /sys/class/net/ -type l \( -name 'eth*' -o -name 'en*' \) -printf '%P' -quit)

if [ -n "$ethdev" ]
then
  read -r _ ether_ip _ < <(ifconfig "$ethdev" | grep "inet ")
  IFS=" :" read -r _ ether_speed < <(ethtool "$ethdev" 2>&1 | grep Speed)
else
  ether_ip=
  ether_speed=
fi

read -r -d ' ' ut < /proc/uptime

cat << EOF
HTTP/1.0 200 OK
Content-type: application/json

{
   "cpu_temp": "$(cat /sys/class/thermal/thermal_zone0/temp)",
   "num_snapshots": "$numsnapshots",
   "snapshot_oldest": "$oldestsnapshot",
   "snapshot_newest": "$newestsnapshot",
   $(eval "$(stat --file-system --format='echo -e \"total_space\": \"$((%b*%S))\",\\\n\ \ \ \"free_space\": \"$((%f*%S))\",' /backingfiles/.)")
   "uptime": "$ut",
   "drives_active": "$drives_active",
   "wifi_ssid": "$wifi_ssid",
   "wifi_freq": "$wifi_freq",
   "wifi_strength": "$wifi_strength",
   "wifi_ip": "$wifi_ip",
   "ether_ip": "$ether_ip",
   "ether_speed": "$ether_speed"
}
EOF
