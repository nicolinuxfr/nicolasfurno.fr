#!/bin/zsh

set -euo pipefail

test_dir=${0:A:h}
"$test_dir/test-core.sh"
"$test_dir/test-services.sh"
"$test_dir/test-series.sh"
