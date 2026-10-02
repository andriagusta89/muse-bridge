#!/bin/bash
# SSH wrapper ke VPS user (VPS kamu / your VPS) via egress proxy.
# Pakai: ssh-vps.sh "<perintah>"
exec ssh -o BatchMode=yes -o ConnectTimeout=25 \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ControlMaster=auto -o ControlPath="$HOME/.ssh/cm-%r@%h-%p" -o ControlPersist=600 \
  # NOTE: baris ProxyCommand di bawah khusus sandbox penulis; di mesin normal HAPUS baris itu.
  # NOTE: the ProxyCommand line below is specific to the author's sandbox; on a normal machine DELETE that line.
  -o "ProxyCommand=nc -X connect -x hatch-egress-proxy:3128 %h %p" \
  -i ~/.ssh/id_ed25519 root@YOUR_VPS_IP "$@"
