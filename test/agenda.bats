#!/usr/bin/env bats

load test_helper

setup() {
  export AGENDA_FAKE_SWIFT_LOG="$BATS_TEST_TMPDIR/swift.log"
  make_fake_swift
}

@test "status task forwards to Swift command" {
  run agenda_task status --json

  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$AGENDA_FAKE_SWIFT_LOG")" = "$REPO_DIR/lib/agenda.swift" ]
  [ "$(sed -n '2p' "$AGENDA_FAKE_SWIFT_LOG")" = "status" ]
  [ "$(sed -n '3p' "$AGENDA_FAKE_SWIFT_LOG")" = "--json" ]
}

@test "event list task forwards flags" {
  run agenda_task event:list --days 2 --limit 3 --json

  [ "$status" -eq 0 ]
  diff -u <(cat <<EXPECTED
$REPO_DIR/lib/agenda.swift
event/list
--days
2
--limit
3
--json
EXPECTED
) "$AGENDA_FAKE_SWIFT_LOG"
}

@test "Swift source typechecks on macOS" {
  if [ "$(uname -s)" != "Darwin" ]; then
    skip "EventKit is only available on macOS"
  fi
  if ! command -v swiftc >/dev/null 2>&1; then
    skip "swiftc not available"
  fi

  run swiftc -typecheck "$REPO_DIR/lib/agenda.swift"
  [ "$status" -eq 0 ]
}
