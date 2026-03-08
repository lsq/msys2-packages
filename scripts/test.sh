#!/usr/bin/env bash

scriptdir=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
echo $(gh run --repo $GITHUB_REPOSITORY view $GITHUB_RUN_ID --json jobs --jq '.jobs[]|select(.name |startswith("test"))')
run_job=$(gh run --repo $GITHUB_REPOSITORY view $GITHUB_RUN_ID --json jobs --jq '.jobs[] | select(.name | startswith("test")) | .url, (.steps[] | select(.name == "check update") | "#step:\(.number):1")' | tr -d "\n")
echo $run_job
# source $scriptdir/fontforge_test.sh
