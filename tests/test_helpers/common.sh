#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0

# log LEVEL MESSAGE
#
# Output a TAP-compliant message that displays nicely in the BATS logs. The
# MESSAGE is prepended with a severity indicator based on the provided LEVEL.
# Accepted LEVEL values:
#   * info
#   * warn
#   * err
#   * on_fail
#
# Note that the messages with "on_fail" level are displayed only if
# the test fails.
log() {
    if [ "$#" -ne 2 ]; then
        log err "Function '${FUNCNAME[0]}' expects exactly 2 arguments. $# given."
        return 1
    fi
    local level=$1; shift
    local message=$1; shift

    case "$level" in
        "info")
            echo "# INFO: $message" >&3
            ;;
        "warn")
            echo "# WARN: $message" >&3
            ;;
        "err")
            echo "# ERROR: $message" >&3
            ;;
        "on_fail")
            echo "$message"
            ;;
        *)
            echo "Unknown log level given to 'log' function: $level"
            return 1
            ;;
    esac
}

# wait_for TIMEOUT CMD [ ARGS ...]
#
# Repeatedly try to execute command CMD with provided ARGS until it succeeds
# or the TIMEOUT (in seconds) is reached. If the CMD does not succeed on the
# first attempt, each subsequent attempt is spaced by 1 second.
# Note that the TIMEOUT represents the amount of 1 second sleeps between
# attempts. The actual maximum time this function may take is the TIMEOUT value
# plus combined execution time of each CMD attempt.
wait_for() {
    if [ "$#" -lt 2 ]; then
        log err "Function '${FUNCNAME[0]}' expects at least 2 arguments. $# given."
        return 1
    fi
    local timeout=$1; shift
    local attempt=1
    while true; do
        log info "Waiting for command to succeed ($attempt/$timeout): '$*'"

        if "$@"; then
            log info "Command succeeded after $attempt attempts: '$*'"
            return 0
        fi

        ((++attempt))
        if [ "$attempt" -gt "$timeout" ]; then
            return 1
        fi

        sleep 1
    done
}

# succeed_for ATTEMPTS TIMEOUT CMD [ ARGS ...]
#
# Ensure that the command CMD with provided ARGS can successfully execute at
# least ATTEMPTS of times in a row. This is usefull, for example, to wait for
# flapping resources to stabilize. Each attempt is spaced by one second.
# If the TIMEOUT (in seconds) is reached before the command was stable for
# the required ATTEMPTS, the function fails.
# Note that the TIMEOUT represents the amount of 1 second sleeps between
# attempts. The actual maximum time this function may take is the TIMEOUT value
# plus combined execution time of each CMD attempt.
succeed_for() {
    if [ "$#" -lt 3 ]; then
        log err "Function '${FUNCNAME[0]}' expects at least 3 arguments. $# given."
        return 1
    fi
    local duration=$1; shift
    local timeout=$1; shift
    local attempts=0

    while [ "$attempts" -lt "$timeout" ]; do
        log info "Waiting for command to be stable for at least $duration attempts: '$*'"
        local good_for=0
        local failed=0
        for _ in $(seq 1 "$duration"); do
            if [ "$attempts" != "0" ]; then
                sleep 1
            fi

            if "$@"; then
                ((++good_for))
                ((++attempts))
                log info "Command was successful in the last $good_for attempts (total attempts: $attempts/$timeout): '$*'"
            else
                ((++attempts))
                log info "Command failed. Restarting stability check (total attempts: $attempts/$timeout): '$*'"
                failed=1
                break
            fi

            if [ "$attempts" -ge "$timeout" ]; then
                break 2
            fi
        done

        if [ "$failed" == "0" ]; then
            log info "Command was stable for required amount of attempts ($duration): '$*'"
            return 0
        fi
    done

    log err "Command wasn't stable for required amount of attempts ($duration): '$*'"
    return 1
}

# create_cre_mock SUBNET
#
# Generate a mock container-runtime executable at $CRE_MOCK that implements the
# "network inspect kind" command used by hack/detect-public-vip-config.sh.
#
# The caller must set the CRE_MOCK variable to the desired output path before
# invoking this function.
#
# Example:
#   CRE_MOCK="$TMPDIR/cre-mock.sh"
#   create_cre_mock "172.19.0.0/16"
#   run hack/detect-public-vip-config.sh "$CRE_MOCK"
#   assert_line "PUBLIC_CIDR_IPV4=172.19.1.0/24"
#
# Pass an empty SUBNET to simulate a failure (no IPv4 subnet found).
create_cre_mock() {
    local subnet=$1; shift

    cat > "$CRE_MOCK" <<'HEADER'
#!/usr/bin/env bash
set -euo pipefail

if [ "$1" = "network" ] && [ "$2" = "inspect" ] && [ "$3" = "kind" ]; then
HEADER
    if [ -n "$subnet" ]; then
        cat >> "$CRE_MOCK" <<EOF
    echo "$subnet"
EOF
    fi
    cat >> "$CRE_MOCK" <<'FOOTER'
    exit 0
fi

echo "unexpected args: $*" >&2
exit 1
FOOTER

    chmod +x "$CRE_MOCK"
}
