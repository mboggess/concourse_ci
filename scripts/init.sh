#!/usr/bin/env bash
# IFS=$'\n\t'

function contains_element () {
    local i
    for i in "${@:2}"; do
        [[ "$i" == "$1" ]] && return 0
    done
    return 1
}

function disable_exit_on_failure() {
  echo "Disabling exit on failure"
  trap - EXIT

  export EXIT_ON_FAILURE=false
  set +eo pipefail
}

function enable_exit_on_failure() {
  echo "Enabling exit on failure"
  trap 'failure' EXIT

  export EXIT_ON_FAILURE=true
  set -eo pipefail
}

function fail() {
  if [[ "$EXIT_ON_FAILURE" == "true" ]]; then
    exit 1
  else
    echo "[FATAL] Error occurred, but not exiting due to EXIT_ON_FAILURE"
    return 1
  fi
}

function source_nvm() {
  # shellcheck source=/dev/null
  source $NVM_DIR/nvm.sh || true
}

function source_env_file() {
  # shellcheck source=secrets/env
  source ~/env || true
}

enable_exit_on_failure

if [ "${DEBUG}" == "true" ]; then
  set -x
  echo "========================================"
  env
  echo "========================================"
  tree -a /var/run/secrets
  echo "========================================"
fi

echo "Initializing environment"

if [[ -d "${SECRETS_DIR}" ]]; then
  echo "Syncing secrets from $SECRETS_DIR to $HOME"
  rsync -arvtz --ignore-existing $SECRETS_DIR/ $HOME/
fi

source_env_file

# shellcheck source=checkout.sh
source ${SCRIPT_DIR}/checkout.sh
# shellcheck source=versioning.sh
source ${SCRIPT_DIR}/version.sh
# shellcheck source=build.sh
source ${SCRIPT_DIR}/build.sh
# shellcheck source=docker.sh
source ${SCRIPT_DIR}/docker.sh
# shellcheck source=finish.sh
source ${SCRIPT_DIR}/finish.sh

echo "Initialization complete"
