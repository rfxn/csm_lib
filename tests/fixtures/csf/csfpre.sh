#!/bin/bash
# CSF pre-hook
/sbin/iptables -I INPUT -s 10.0.0.1 -j ACCEPT
echo "pre-hook from /etc/csf/csfpre.sh"
