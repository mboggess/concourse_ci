#!/usr/bin/env bash

function checkout_source() {
  #SOURCE_URI
  #SOURCE_REF
  #SOURCE_CONTEXT_DIR
  #BUILD

  # local HAS_COMMIT_REVISION
  # local COMMIT_REVISION
  local URL
  local SSH_KEY_PATH=$HOME/.ssh/id_rsa

  if [ -z "${SOURCE_REF}" ]; then
    echo "SOURCE_REF is required"
    exit 1
  fi
  if [ -z "${SOURCE_URI}" ]; then
    echo "SOURCE_URI is required"
    exit 1
  fi

  if [[ -d "${SOURCE_SECRET_PATH}" ]]; then
    cp "${SOURCE_SECRET_PATH}/ssh-privatekey" $SSH_KEY_PATH
  fi

  BUILD_DIR=$(mktemp --directory)

  if [[ "${SOURCE_URI}" == "/"* ]]; then
    echo "---> Source URI is local file system..."
    rsync -arvtz ${SOURCE_URI}/ "${BUILD_DIR}"/
  else
    if [[ "${SOURCE_URI}" != "git://"* ]] && [[ "${SOURCE_URI}" != "git@"* ]]; then
      URL="${SOURCE_URI}"
      if [[ "${URL}" != "http://"* ]] && [[ "${URL}" != "https://"* ]]; then
        URL="https://${URL}"
      fi
      curl --head --silent --fail --location --max-time 16 $URL > /dev/null
      if [ $? != 0 ]; then
        echo "Could not access source url: ${SOURCE_URI}"
        exit 1
      fi
    fi

    echo "---> Checking out source into $BUILD_DIR"
    echo "git clone --single-branch --recursive -b ${SOURCE_REF} ${SOURCE_URI} ${BUILD_DIR}"
    git clone --single-branch --recursive -b "${SOURCE_REF}" "${SOURCE_URI}" "${BUILD_DIR}"
    if [ $? != 0 ]; then
      echo "Error trying to fetch git source: ${SOURCE_URI} ${SOURCE_REF}"
      exit 1
    fi
  fi

  # if [[ -n "${BUILD}" ]]; then
  #   HAS_COMMIT_REVISION=$(echo $BUILD | jq -e '.spec.revision.git | has("commit")' || true)
  #   if [[ "$HAS_COMMIT_REVISION" == "true" ]]; then
  #     COMMIT_REVISION=$(echo $BUILD | jq -r '.spec.revision.git.commit')
  #     echo "Using commit revision $COMMIT_REVISION"
  #     git -C $BUILD_DIR checkout $COMMIT_REVISION 1>/dev/null
  #   fi
  # fi

  if [[ -n "${SOURCE_CONTEXT_DIR}" ]]; then
    if [[ "${SOURCE_CONTEXT_DIR}" != "/"* ]]; then
      SOURCE_CONTEXT_DIR="/${SOURCE_CONTEXT_DIR}"
    fi

    echo "Using $SOURCE_CONTEXT_DIR as BUILD_DIR"
    BUILD_DIR="${BUILD_DIR}${SOURCE_CONTEXT_DIR}"
  fi

  echo "BUILD_DIR: $BUILD_DIR"
  export BUILD_DIR
}
