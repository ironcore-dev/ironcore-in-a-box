#!/usr/bin/env bash
# SPDX-FileCopyrightText: SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0


set -e

BASEDIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPOROOT="$BASEDIR/.."
export TERM="xterm-256color"

bold="$(tput bold)"
red="$(tput setaf 1)"
green="$(tput setaf 2)"
normal="$(tput sgr0)"

for kustomization in "$BASEDIR"/../base/**/kustomization.yaml; do
  path="$(dirname "$kustomization")"
  dir="${path#"$REPOROOT"/}"
  echo "${bold}Validating $dir${normal}"
  if ! kustomize_output="$(kustomize build "$path" 2>&1)"; then
    echo "${red}Kustomize build $dir failed:"
    echo "$kustomize_output"
    exit 1
  fi
  echo "${green}Successfully validated $dir${normal}"
done

for kustomization in "$BASEDIR"/../cluster/local/**/kustomization.yaml; do
  path="$(dirname "$kustomization")"
  dir="${path#"$REPOROOT"/}"
  echo "${bold}Validating $dir${normal}"
  if ! kustomize_output="$(kustomize build "$path" 2>&1)"; then
    echo "${red}Kustomize build $dir failed:"
    echo "$kustomize_output"
    exit 1
  fi
  echo "${green}Successfully validated $dir${normal}"
done
