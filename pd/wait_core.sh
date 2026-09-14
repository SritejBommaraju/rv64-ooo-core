#!/bin/bash
n=0
while [ $n -lt 40 ]; do
  test -f /mnt/c/Users/bomma/projects/rv64-ooo-core/pd/out/core_synth.status && break
  sleep 10
  n=$((n+1))
done
echo "LOOP_DONE n=$n"
for f in lsq l1d core; do
  echo -n "$f: "
  cat /mnt/c/Users/bomma/projects/rv64-ooo-core/pd/out/${f}_synth.status 2>/dev/null
  echo
done
tail -5 /tmp/pd_lsq_l1d.log
