#!/usr/bin/env bash
set -euo pipefail

diagnostics_dir=${DIAGNOSTICS_DIR:-${RUNNER_TEMP:-/tmp}/ci-diagnostics}
mkdir -p "$diagnostics_dir"
cpu_count=$(nproc)
build_jobs=${BUILD_JOBS:-0}
if [[ ! $build_jobs =~ ^(0|[1-9][0-9]{0,3})$ ]]; then
  echo '::error::BUILD_JOBS must be 0 (automatic) or a positive integer up to 9999'
  exit 2
fi
if (( build_jobs == 0 )); then
  build_jobs=$cpu_count
elif (( build_jobs > cpu_count )); then
  echo "::error::BUILD_JOBS exceeds the available CPU count ($cpu_count)"
  exit 2
fi

snapshot() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
  free -h || true
  df -h . "$diagnostics_dir" || true
  uptime || true
  for resource in cpu memory io; do
    if [[ -r /proc/pressure/$resource ]]; then
      echo "Pressure: $resource"
      cat "/proc/pressure/$resource" || true
    fi
  done
  if [[ -r /proc/vmstat ]]; then
    awk '$1 == "oom_kill" {print}' /proc/vmstat || true
  fi
  if [[ -r /proc/meminfo ]]; then
    awk '/^(MemAvailable|SwapTotal|SwapFree):/ {print}' /proc/meminfo || true
  fi
}

{
  printf 'ImageOS=%s ImageVersion=%s RUNNER_ARCH=%s\n' "${ImageOS:-unknown}" "${ImageVersion:-unknown}" "${RUNNER_ARCH:-unknown}"
  printf 'CPUs=%s BUILD_JOBS=%s\n' "$cpu_count" "$build_jobs"
  uname -a
  git rev-parse HEAD
  for feed in feeds/*; do
    if [[ -e $feed/.git ]]; then
      printf '%s ' "$feed"
      git -C "$feed" rev-parse HEAD
    fi
  done
} | tee "$diagnostics_dir/environment.log"

monitor_pid=''
cleanup() {
  local build_status=$?
  trap - EXIT INT TERM
  set +e
  if [[ -n $monitor_pid ]]; then
    kill "$monitor_pid" 2>/dev/null
    wait "$monitor_pid" 2>/dev/null
  fi
  snapshot 2>&1 | tee -a "$diagnostics_dir/resources.log"
  # Best effort: the runner may deny kernel logs, or disappear before cleanup.
  sudo -n dmesg --ctime 2>&1 | tail -n 200 > "$diagnostics_dir/kernel.log"
  printf 'Final build exit code: %s\n' "$build_status"
  exit "$build_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

snapshot 2>&1 | tee -a "$diagnostics_dir/resources.log" || true
(
  sleep_pid=''
  # Invoked by the subshell's EXIT trap.
  # shellcheck disable=SC2329
  stop_monitor() {
    if [[ -n $sleep_pid ]]; then
      kill "$sleep_pid" 2>/dev/null || true
      wait "$sleep_pid" 2>/dev/null || true
    fi
  }
  trap stop_monitor EXIT
  trap 'exit 0' INT TERM
  while true; do
    sleep 60 &
    sleep_pid=$!
    wait "$sleep_pid" || true
    sleep_pid=''
    snapshot 2>&1 | tee -a "$diagnostics_dir/resources.log" || true
  done
) &
monitor_pid=$!

# pipefail keeps tee from hiding a failed build. Preserve the existing serial
# verbose retry, which reports the underlying compiler error after make fails.
if make -j"$build_jobs" 2>&1 | tee "$diagnostics_dir/build.log"; then
  exit 0
else
  echo 'Parallel build failed; retrying once with make -j1 V=s'
  make -j1 V=s 2>&1 | tee -a "$diagnostics_dir/build.log"
fi
