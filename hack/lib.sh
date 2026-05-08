#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0

# Portable replacement for GNU realpath --relative-to (BSD realpath lacks this flag).
# Both directories must exist.
# Usage: relpath <target> <base>
relpath() {
    local target base
    target=$(cd "$1" && pwd)
    base=$(cd "$2" && pwd)

    local common="$base"
    while [ "${target#"$common"}" = "$target" ]; do
        common=$(dirname "$common")
    done

    local up=""
    local rest="$base"
    while [ "$rest" != "$common" ]; do
        up="../$up"
        rest=$(dirname "$rest")
    done

    local rel="${target#"$common"}"
    rel="${rel#/}"
    printf '%s\n' "${up}${rel}"
}
