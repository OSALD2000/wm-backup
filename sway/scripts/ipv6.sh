#!/bin/sh
# Gibt die oeffentliche IPv6-Adresse aus, nicht die erste am Interface.
#
# Warum es das braucht: waybars network-Modul mit family=ipv6 nimmt die erste
# Adresse mit global scope. Dieser Rechner hat davon vier —
#   fd00:feff:390:0:566e:788:6051:2f72   ULA, privat
#   fd00:feff:390:0:cc1d:afbd:2f12:bc8   ULA, privat
#   2a02:3100:aeb0:7100:4cf3:ddb5:...    oeffentlich
#   2a02:3100:aeb0:7100:58bb:11f:...     oeffentlich, temporaer
# — und waybar zeigte die ULA. "ip" nennt fc00::/7 zwar global scope, gemeint
# ist damit aber nur "nicht link-local"; ins Internet routet sie nicht.
#
# Hier: erste Adresse, die NICHT mit fc oder fd beginnt. Die kommt von SLAAC
# und ist die stabile — dieselbe, die i3status unter i3 angezeigt hat.
# ponytail: kein Interface-Filter. Bei mehreren Uplinks gleichzeitig nimmt es
# den ersten Treffer; wenn das je stoert, `-d wlp2s0` o.ae. ergaenzen.
ip -6 addr show scope global 2>/dev/null |
  awk '/inet6/ && $2 !~ /^f[cd]/ { sub(/\/.*/, "", $2); print $2; exit }'
