#!/usr/bin/env bash

function test_docker() {
    if [ ! -e "${DOCKER_SOCKET}" ]; then
      echo "Docker socket missing at ${DOCKER_SOCKET}"
      exit 1
    fi

    type docker 1>/dev/null
}

function should_perform_docker_function() {
  if [[ -n "$OUTPUT_TYPE" ]]; then

    echo "OUTPUT_TYPE: $OUTPUT_TYPE"
    case $OUTPUT_TYPE in
      docker) return ;;
      image) return ;;
      push) return ;;
      deploy) return ;;
      * )
        ;;
    esac
    echo "$OUTPUT_TYPE not supported - EXITING"
    exit 0
  fi
}

function should_do_push() {
  if [[ -n "$OUTPUT_TYPE" ]]; then

    echo "OUTPUT_TYPE: $OUTPUT_TYPE"
    case $OUTPUT_TYPE in
      push) return ;;
      deploy) return ;;
      * )
        ;;
    esac
    echo "$OUTPUT_TYPE not supported - EXITING"
    exit 0
  fi
}

function create_docker_image() {
  #BUILD_DIR
  #DOCKERFILE_CONTEXT_DIR
  #COMMIT_ID, COMMIT_DATE, COMMIT_AUTHOR, COMMIT_MESSAGE

  should_perform_docker_function

  test_docker

  local DOCKER_CFG_PULL_PATH=$HOME/docker/pull
  local DOCKER_CFG_PUSH_PATH=$HOME/docker/push

  if [[ -d "${PULL_DOCKERCFG_PATH}" ]]; then
    if [[ -f "${PULL_DOCKERCFG_PATH}/.dockerconfigjson" ]]; then
      mkdir -p "${DOCKER_CFG_PULL_PATH}"
      cp "${PULL_DOCKERCFG_PATH}/.dockerconfigjson" "$DOCKER_CFG_PULL_PATH/config.json"
      mkdir $HOME/.docker
      cp "${PULL_DOCKERCFG_PATH}/.dockerconfigjson" "$HOME/.docker/config.json"
    fi
  fi

  if [[ -d "${PUSH_DOCKERCFG_PATH}" ]]; then
    if [[ -f "${PUSH_DOCKERCFG_PATH}/.dockerconfigjson" ]]; then
      mkdir -p "${DOCKER_CFG_PUSH_PATH}"
      cp "${PUSH_DOCKERCFG_PATH}/.dockerconfigjson" "$DOCKER_CFG_PUSH_PATH/config.json"
    fi
    if [[ -f "${PUSH_DOCKERCFG_PATH}/.dockercfg" ]]; then
      cp "${PUSH_DOCKERCFG_PATH}/.dockercfg" "$HOME/.dockercfg"
    fi
  fi

  if [ ! -d "${DOCKERFILE_CONTEXT_DIR}" ]; then
    echo "Unable to find Dockerfile directory at '${DOCKERFILE_CONTEXT_DIR}'"
    exit 1
  fi

  if [ ! -e "${DOCKERFILE_CONTEXT_DIR}/Dockerfile" ]; then
    echo "Expected Dockerfile at '${DOCKERFILE_CONTEXT_DIR}'"
    exit 1
  fi

  if [[ -z "${OUTPUT_IMAGE}" ]]; then
    echo "No OUTPUT_IMAGE set. Not building docker image."
    exit 1
  fi

  # popd

  # IMAGE_PUSH_URL="${OUTPUT_REGISTRY}/${OUTPUT_IMAGE}"
  local IMAGE_ARR=(${OUTPUT_IMAGE//:/ })
  local IMAGE_PATH="${IMAGE_ARR[0]}"
  local PUSH_URL="${OUTPUT_REGISTRY}/${IMAGE_PATH}"

  IMAGE_NAME="${IMAGE_PATH##*/}"  #remove namespace
  PUSH_TAG="${IMAGE_ARR[1]}"
  NEXT_VERSION_PUSH_URL="${PUSH_URL}:${NEXT_VERSION}"

  # echo $BUILD | jq -e '.spec.source | has("dockerfile")'
  # echo $BUILD | jq -r '.spec.source.dockerfile'

  echo "Building ${IMAGE_NAME} with tags ${NEXT_VERSION_PUSH_URL}"
  # docker --config=$DOCKER_CFG_PULL_PATH build --rm -q \
  docker --config=$DOCKER_CFG_PULL_PATH build --pull --rm \
    --label io.openshift.build.commit.id="$COMMIT_ID" \
    --label io.openshift.build.commit.ref="$SOURCE_REF" \
    --label io.openshift.build.source-location="$SOURCE_URI" \
    --label io.openshift.build.commit.author="$COMMIT_AUTHOR" \
    --label io.openshift.build.commit.date="$COMMIT_DATE" \
    --label io.openshift.build.commit.message="$COMMIT_MESSAGE" \
    --label VERSION="$NEXT_VERSION" \
    -t "${NEXT_VERSION_PUSH_URL}" "${DOCKERFILE_CONTEXT_DIR}"

  if [ $? != 0 ]; then
    echo "Error building docker image: ${NEXT_VERSION_PUSH_URL} ${DOCKERFILE_CONTEXT_DIR}"
    exit 1
  fi

  local activePushContext
  if [ -s "$DOCKER_CFG_PUSH_PATH" ]; then
    activePushContext="$DOCKER_CFG_PUSH_PATH"
  elif [[ -s "$PUSH_DOCKERCFG_PATH" ]]; then
    activePushContext="$PUSH_DOCKERCFG_PATH"
  fi

  if [[ -n "$activePushContext" ]]; then
    echo "Using $activePushContext config to PUSH ${IMAGE_NAME} to ${NEXT_VERSION_PUSH_URL}"
    docker --config="${activePushContext}" push "${NEXT_VERSION_PUSH_URL}"
  else
    echo "No docker configs found at $DOCKER_CFG_PUSH_PATH or $PUSH_DOCKERCFG_PATH"
    if [[ "$DEBUG" == "true" ]]; then
      tree -a "$DOCKER_CFG_PUSH_PATH"
      tree -a "$PUSH_DOCKERCFG_PATH"
    fi
  fi

  export IMAGE_NAME
  export NEXT_VERSION_PUSH_URL
  export PUSH_TAG
}

function push_to_jfrog() {
  #NEXT_VERSION_PUSH_URL
  #PUSH_JFROG
  #IMAGE_NAME
  #PUSH_TAG

  should_do_push

  test_docker

  local DOCKER_CFG_JFROG_PATH=$HOME/docker/jfrog
  local DOCKER_CFG_JFROG_SOURCE_PATH=/etc/jfrog

  if [[ -f "${DOCKER_CFG_JFROG_SOURCE_PATH}/.dockerconfigjson" ]]; then
    mkdir -p "${DOCKER_CFG_JFROG_PATH}"
    cp "${DOCKER_CFG_JFROG_SOURCE_PATH}/.dockerconfigjson" "$DOCKER_CFG_JFROG_PATH/config.json"
  fi

  if [ "${PUSH_JFROG}" == "true" ] && [ -d "${DOCKER_CFG_JFROG_PATH}" ]; then
    # if [[ "$VERSIONABLE" != "true" ]]; then
    #   echo "Not versionable - Not pushing to Jfrog"
    #   return 0
    # fi
    local JFROG_REGISTRY=elsols-docker.jfrog.io/eols
    local JFROG_PUSH_URL="${JFROG_REGISTRY}/${IMAGE_NAME}"
    local JFROG_PUSH_TAG="${JFROG_PUSH_URL}:${PUSH_TAG}"
    local JFROG_PUSH_VERSION_TAG="${JFROG_PUSH_URL}:${NEXT_VERSION}"

    echo "Pushing to ${JFROG_PUSH_TAG} and ${JFROG_PUSH_VERSION_TAG}"
    docker tag "${NEXT_VERSION_PUSH_URL}" "${JFROG_PUSH_VERSION_TAG}"
    docker tag "${JFROG_PUSH_VERSION_TAG}" "${JFROG_PUSH_TAG}"
    docker --config="${DOCKER_CFG_JFROG_PATH}" push "${JFROG_PUSH_VERSION_TAG}"
    docker --config="${DOCKER_CFG_JFROG_PATH}" push "${JFROG_PUSH_TAG}"
  fi
}

function push_to_openshift() {
  #OPENSHIFT_BUILD_NAMESPACE
  #IMAGE_NAME
  #NEXT_VERSION
  #PUSH_TAG
  #ACTIVE_TAG

  type oc 1>/dev/null # Fail if oc binary isn't present

  should_do_push

  ACTIVE_TAG=${ACTIVE_TAG:-active}
  OS_SERVER_URL=${OS_SERVER_URL:-"https://openshift.default.svc.cluster.local"}

  local SVC_ACCOUNT_PATH=/var/run/secrets/kubernetes.io/serviceaccount
  local TOKEN_PATH=$SVC_ACCOUNT_PATH/token

  local PROMOTION_ENV
  local CAN_PUSH_TAGS
  local TOKEN

  if [[ ! -f "${TOKEN_PATH}" ]]; then
    echo "OpenShift serviceaccount token expected at $TOKEN_PATH but not found."
    exit 1
  fi

  echo "Found OpenShift serviceaccount token at ${TOKEN_PATH}"
  TOKEN=$(cat $TOKEN_PATH)

  echo "Logging into OpenShift"
  oc login $OS_SERVER_URL --token=$TOKEN --insecure-skip-tls-verify 1>/dev/null
  if [ $? != 0 ]; then
    echo "Error authenticating to OpenShift."
    exit 1
  fi

  if [[ -z "$OPENSHIFT_BUILD_NAMESPACE" ]]; then
    echo "OPENSHIFT_BUILD_NAMESPACE is empty."
    exit 1
  fi
  echo "Current build namespace: $OPENSHIFT_BUILD_NAMESPACE"

  PROMOTION_ENV="$(oc export namespace $OPENSHIFT_BUILD_NAMESPACE \
    --template='{.metadata.annotations.promotion-env}' \
    -o jsonpath
  )"
  echo "Promotion environment: $PROMOTION_ENV"

  CAN_PUSH_TAGS=$(oc policy can-i create imagestreamtag)
  if [[ "${CAN_PUSH_TAGS}" == "yes"  ]]; then
    echo "Waiting 5 seconds to tag image"
    sleep 5

    if [[ "$VERSIONABLE" == "true" ]]; then
      # only push to $PUSH_TAG if it's a versionable build
      echo "VERSIONABLE - Tagging ${IMAGE_NAME}:${NEXT_VERSION} as ${IMAGE_NAME}:${PUSH_TAG}"
      oc tag $IMAGE_NAME:$NEXT_VERSION $IMAGE_NAME:$PUSH_TAG
    fi

    echo "Tagging ${IMAGE_NAME}:${NEXT_VERSION} as ${PROMOTION_ENV}/${IMAGE_NAME}:${NEXT_VERSION}"
    oc tag $IMAGE_NAME:$NEXT_VERSION \
      $PROMOTION_ENV/$IMAGE_NAME:$NEXT_VERSION \
      $PROMOTION_ENV/$IMAGE_NAME:$ACTIVE_TAG

    # oc label dc $IMAGE_NAME APP_VERSION=$NEXT_VERSION --overwrite -n $PROMOTION_ENV

    # oc tag adaptive-service2:v2.0.4.RC1 adaptive-service2:latest \
    #   dev/adaptive-service2:v2.0.4.RC1 \
    #   dev/adaptive-service2:dev --as=system:serviceaccount:build:builder

    # oc set image -n dev dc/adaptive-service2 adaptive-service2=adaptive-service2:v2.0.4.RC1

  else
    echo "Unable to create imagestreamtags! Make sure $(oc whoami) has edit rights on this project."
    exit 1
  fi
}
