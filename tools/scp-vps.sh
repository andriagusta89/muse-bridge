#!/bin/bash
# SCP wrapper ke VPS user. Pakai: scp-vps.sh <src> <dst-remote>  |  scp-vps.sh <src-remote> <dst>
exec scp -o BatchMode=yes -o ConnectTimeout=25 \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  # NOTE: baris ProxyCommand di bawah khusus sandbox penulis; di mesin normal HAPUS baris itu.
  # NOTE: the ProxyCommand line below is specific to the author's sandbox; on a normal machine DELETE that line.
  -o "ProxyCommand=nc -X connect -x hatch-egress-proxy:3128 %h %p" \
  -i ~/.ssh/id_ed25519 "$@"
