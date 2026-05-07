#!/usr/bin/env bash

make_fake_swift() {
  export FAKE_SWIFT="$BATS_TEST_TMPDIR/fake-swift"
  cat > "$FAKE_SWIFT" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "${AGENDA_FAKE_SWIFT_LOG:?}"
case "${2:-help}" in
  status)
    echo "Calendar access: notDetermined"
    echo "Can read events: no"
    echo "Next: run 'agenda request-access'"
    ;;
  --help|-h|help|*)
    echo "agenda fake help"
    ;;
esac
FAKE
  chmod +x "$FAKE_SWIFT"
}

ensure_caller_pwd() {
  if [ -z "${CALLER_PWD:-}" ]; then
    export CALLER_PWD="$BATS_TEST_TMPDIR/caller"
    mkdir -p "$CALLER_PWD"
  fi
}

agenda() {
  ensure_caller_pwd
  cd "$REPO_DIR" && SWIFT="${FAKE_SWIFT:-swift}" CALLER_PWD="$CALLER_PWD" mise run -q "$@"
}
export -f agenda
