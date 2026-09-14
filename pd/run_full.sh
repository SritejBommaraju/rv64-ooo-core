#!/bin/bash
cd /mnt/c/Users/bomma/projects/rv64-ooo-core/pd
export PATH="$HOME/oss-cad-suite/bin:$PATH"
make synth sta summary > /tmp/pd_full_run.log 2>&1
