# Index script compatible with gkrizek/bash-lambda-layer.
#
# Optionally, the trigger event (eg scheduled CloudWatch Events) may include hosts like:
# {"hosts": [ "example.com", "example.com:53" ]}
function handler {
  set -Ceuo pipefail
  # Pipe to a command group, because Lambda has no /dev/fd support (otherwise we would
  # use input redirection with command substitution to access the $ARGS array instead).
  jq -jr '.hosts[]?|tostring+"\u0000"' <<< "${1:-}" | {
    while read -d '' -r host; do hosts+=("$host"); done
    echo "Executing: cert-metrics.sh$(printf " '%s'" "${host[@]}")"
    . cert-metrics.sh "${hosts[@]}" 3>&2 2>&1 1>&3
  }
}
