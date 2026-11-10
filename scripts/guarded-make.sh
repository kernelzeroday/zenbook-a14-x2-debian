#!/bin/bash
# usage: guarded-make.sh LOGDIR make-args...
# Runs make pinned to cluster 0 (CPUs 0-5), niced, and pauses it on heat or lost freq cap.
set -u
LOG=$1; shift; mkdir -p "$LOG"
HOT=75000 COOL=60000 CAPMAX=2764800
ZONES=$(for z in /sys/class/thermal/thermal_zone*; do grep -qE '^(cpu|cpullc|cpuillc|gpuss|ddr)-' $z/type && echo $z/temp; done)
setsid taskset -c 0-5 nice -n 19 ionice -c3 make "$@" >"$LOG/build.log" 2>&1 &
PG=$!; paused=0
trap 'kill -CONT -$PG 2>/dev/null; kill -TERM -$PG 2>/dev/null; exit 130' INT TERM
while kill -0 $PG 2>/dev/null; do
  t=$(cat $ZONES 2>/dev/null | sort -n | tail -1)
  cap=$(cat /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq | sort -n | tail -1)
  reason=""; [ "$t" -ge $HOT ] && reason="hot"; [ "$cap" -gt $CAPMAX ] && reason="${reason}cap-lost($cap)"
  if [ -n "$reason" ] && [ $paused = 0 ]; then kill -STOP -$PG; paused=1; echo "$(date +%T) PAUSE $reason t=$t" >>"$LOG/guard.log"
  elif [ -z "$reason" ] && [ $paused = 1 ] && [ "$t" -lt $COOL ]; then kill -CONT -$PG; paused=0; echo "$(date +%T) RESUME t=$t" >>"$LOG/guard.log"; fi
  echo "$(date +%T) max=$t cap=$cap paused=$paused load=$(cut -d' ' -f1 /proc/loadavg)" >>"$LOG/temps.log"; sync -d "$LOG/temps.log" 2>/dev/null
  sleep 2
done
wait $PG; rc=$?; echo "$(date +%T) DONE rc=$rc" >>"$LOG/guard.log"; exit $rc
