#!/usr/bin/env bash
# Behavior tests for the verified Atomic and OMP Pi-derived harness adapters.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HARNESS="$ROOT/bin/fm-harness.sh"
LOCK="$ROOT/bin/fm-lock.sh"
LOCK_LIB="$ROOT/bin/fm-session-lock-lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-atomic-omp-adapters)

test_atomic_marker_wins_over_inherited_parent_markers() {
  local out
  out=$(ATOMIC_CODING_AGENT=true OMPCODE= CLAUDECODE=1 PI_CODING_AGENT=true "$HARNESS")
  [ "$out" = atomic ] || fail "Atomic marker was misclassified as '$out'"
  pass "fm-harness: Atomic identity wins over inherited Claude and Pi markers"
}

test_omp_marker_wins_over_inherited_claude_marker() {
  local out
  out=$(ATOMIC_CODING_AGENT= OMPCODE=1 CLAUDECODE=1 PI_CODING_AGENT= "$HARNESS")
  [ "$out" = omp ] || fail "OMP marker was misclassified as '$out'"
  pass "fm-harness: OMP identity wins over its inherited Claude marker"
}

test_atomic_and_omp_process_ancestry_fallbacks() {
  local fakebin out
  fakebin=$(fm_fakebin "$TMP_ROOT/ancestry")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *'comm='*) printf '%s\n' "${FM_FAKE_COMM:?}" ;;
  *'ppid='*) printf '1\n' ;;
  *'args='*) printf '%s\n' "${FM_FAKE_ARGS:-}" ;;
esac
SH
  chmod +x "$fakebin/ps"
  out=$(PATH="$fakebin:$PATH" FM_FAKE_COMM=atomic ATOMIC_CODING_AGENT= OMPCODE= CLAUDECODE= PI_CODING_AGENT= "$HARNESS")
  [ "$out" = atomic ] || fail "Atomic ancestry was classified as '$out'"
  out=$(PATH="$fakebin:$PATH" FM_FAKE_COMM=omp ATOMIC_CODING_AGENT= OMPCODE= CLAUDECODE= PI_CODING_AGENT= "$HARNESS")
  [ "$out" = omp ] || fail "OMP ancestry was classified as '$out'"
  pass "fm-harness: Atomic and OMP retain process-ancestry fallbacks"
}

test_runtime_project_extension_shims_exist() {
  local runtime file
  for file in fm-primary-turnend-guard.ts fm-primary-pi-watch.ts; do
    assert_present "$ROOT/.pi/extensions/$file" "Atomic inherited Pi-compatible extension is missing: $file"
    assert_present "$ROOT/.omp/extensions/$file" "OMP project extension shim is missing: $file"
    assert_grep "../../.pi/extensions/$file" "$ROOT/.omp/extensions/$file" \
      "OMP project extension shim does not reuse the shared Pi-compatible implementation"
  done
  assert_grep '!**/fm-calm.ts' "$ROOT/.atomic/settings.json" \
    "Atomic project settings do not exclude the incompatible inherited Pi Calm extension"
  pass "Atomic inherited discovery and OMP project shims reuse FirstMate's shared Pi-compatible extensions"
}

test_runtime_busy_signatures_are_scoped() {
  local atomic_busy omp_busy
  # shellcheck source=/dev/null
  . "$ROOT/bin/fm-tmux-lib.sh"
  atomic_busy='∀ Working on request...'
  omp_busy='Working… [esc]'
  printf '%s\n' "$atomic_busy" | fm_busy_lines_match atomic \
    || fail "Atomic's verified spinner did not classify as busy"
  printf '%s\n' "$omp_busy" | fm_busy_lines_match omp \
    || fail "OMP's verified busy footer did not classify as busy"
  if printf '%s\n' "$atomic_busy" | fm_busy_lines_match omp; then
    fail "OMP borrowed Atomic's busy signature"
  fi
  if printf '%s\n' "$omp_busy" | fm_busy_lines_match atomic; then
    fail "Atomic borrowed OMP's busy signature"
  fi
  pass "tmux adapter: Atomic and OMP busy signatures are runtime-scoped"
}

test_session_lock_accepts_exact_atomic_and_omp_identities() {
  local fakebin runtime shape comm args state out
  fakebin=$(fm_fakebin "$TMP_ROOT/session-lock")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *'comm='*) printf '%s\n' "${FM_FAKE_COMM:?}" ;;
  *'args='*) printf '%s\n' "${FM_FAKE_ARGS:-}" ;;
  *'ppid='*) printf '1\n' ;;
esac
SH
  chmod +x "$fakebin/ps"
  for runtime in atomic omp; do
    for shape in command interpreter; do
      if [ "$shape" = command ]; then
        comm=$runtime
        args=$runtime
      else
        comm=node
        args="/opt/test/$runtime/dist/cli.js"
      fi
      state="$TMP_ROOT/session-lock-$runtime-$shape"
      mkdir -p "$state"
      out=$(PATH="$fakebin:$PATH" FM_FAKE_COMM="$comm" FM_FAKE_ARGS="$args" \
        FM_STATE_OVERRIDE="$state" "$LOCK") \
        || fail "$runtime $shape identity could not acquire the session lock"
      assert_contains "$out" "lock acquired: harness pid" \
        "$runtime $shape lock acquisition omitted its harness pid"
      printf '%s\n' "$$" > "$state/.lock"
      out=$(PATH="$fakebin:$PATH" FM_FAKE_COMM="$comm" FM_FAKE_ARGS="$args" \
        FM_STATE_OVERRIDE="$state" "$LOCK" status)
      assert_contains "$out" "lock: held by live harness pid $$" \
        "$runtime $shape holder was not recognized as live"
    done
    if PATH="$fakebin:$PATH" FM_FAKE_COMM="$runtime-helper" FM_FAKE_ARGS="$runtime-helper" \
      bash -c '. "$1"; fm_harness_pid_alive "$$"' _ "$LOCK_LIB"; then
      fail "$runtime helper command was accepted as an exact session-lock identity"
    fi
    if PATH="$fakebin:$PATH" FM_FAKE_COMM=node FM_FAKE_ARGS="/opt/test/$runtime-helper/dist/cli.js" \
      bash -c '. "$1"; fm_harness_pid_alive "$$"' _ "$LOCK_LIB"; then
      fail "$runtime helper interpreter path was accepted as an exact session-lock identity"
    fi
  done
  pass "session lock: exact Atomic and OMP commands and interpreters acquire and stay live"
}

test_atomic_marker_wins_over_inherited_parent_markers
test_omp_marker_wins_over_inherited_claude_marker
test_atomic_and_omp_process_ancestry_fallbacks
test_runtime_project_extension_shims_exist
test_runtime_busy_signatures_are_scoped
test_session_lock_accepts_exact_atomic_and_omp_identities

echo "# all Atomic and OMP adapter tests passed"
