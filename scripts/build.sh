#!/usr/bin/env bash

function set_frontend_package_versions() {
  pushd $BUILD_DIR
  # https://docs.npmjs.com/cli/version
  # bower version $NEXT_VERSION || true
  if [[ -f "bower.json" ]]; then
    echo "Setting bower.json version to ${NEXT_VERSION}"
    jq --arg VERSION "$NEXT_VERSION" '.version=$VERSION' $BUILD_DIR/bower.json | sponge $BUILD_DIR/bower.json || true
  fi

  if [[ -f "package.json" ]]; then
    echo "Setting package.json version to ${NEXT_VERSION}"
    npm version $NEXT_VERSION --no-git-tag-version --allow-same-version || true
  fi
  popd
}

function deploy_frontend_packages {
  local BOWER_CREDENTIALS
  local USERNAME
  local PASSWORD
  local PACKAGE_VERSION

  local NPM_REPO=https://elsols.artifactoryonline.com/elsols/api/npm/npm/
  local BOWER_REPO=https://elsols.artifactoryonline.com/elsols/bower

  BOWER_CREDENTIALS=$(cat ~/.bowerrc | jq -r '.registry.search[0]' | cut -d@ -f1 | cut -d/ -f3)
  USERNAME=$(echo $BOWER_CREDENTIALS | cut -d: -f1)
  PASSWORD=$(echo $BOWER_CREDENTIALS | cut -d: -f2)

  local IMAGE_ARR=(${OUTPUT_IMAGE//:/ })  #relying on word splitting
  local IMAGE_PATH="${IMAGE_ARR[0]}"
  local IMAGE_NAME="${IMAGE_PATH##*/}"  #remove namespace

  echo "Package Name: $IMAGE_NAME"

  if [[ "${PUSH_TAGS}" == "true" && "${VERSIONABLE}" == "true" || "$REBUILD" == "true" ]]; then

    local BOWER_PACKAGE_DIR=${SCRIPT_DIR}/bower
    pushd $BOWER_PACKAGE_DIR
    npm install
    popd

    local ARCHIVE_FILE=/tmp/package.tar.gz
    echo "Packaging ${BUILD_DIR} into ${ARCHIVE_FILE}"
    node -p "require('${BOWER_PACKAGE_DIR}/package.js')"

    PACKAGE_VERSION=$(node -p "require('${BUILD_DIR}/package.json').version")
    echo "Publishing ${PACKAGE_VERSION} to Artifactory (Bower)"

    artifactory-push -f ${ARCHIVE_FILE} \
     -t ${BOWER_REPO}/${IMAGE_NAME}/${IMAGE_NAME}-$PACKAGE_VERSION.tar.gz \
     -u ${USERNAME} -p ${PASSWORD}

     echo "Publishing ${IMAGE_NAME} to Artifactory (NPM)"
     npm publish --registry $NPM_REPO
  fi
}

function build() {
  #BUILD_DIR
  #NODE_VERSION
  #BUILDER
  #BUILD_ARGS
  #POST_BUILD_CMDS

  if [[ -z "$BUILD_DIR" ]] || [[ ! -d "${BUILD_DIR}" ]]; then
    echo 'BUILD_DIR is invalid or non-existent!'
    exit 1
  fi

  if [[ -z "$NEXT_VERSION" ]]; then
    echo 'NEXT_VERSION is empty!'
    exit 1
  fi

  echo "Switching to BUILD_DIR $BUILD_DIR"
  pushd "${BUILD_DIR}"

  local NPM_GLOBAL_PACKAGES="grunt-cli grunt bower bower-art-resolver artifactory-push"
  local NPM_ARGS="run build"
  local GRADLE_ARGS="distDockerPrepare"
  local MVN_ARGS="clean package docker:build"
  local BUILDFILES_PATH=/var/run/build
  local SONARQUBE_TASK=sonarqube
  local SWAGGER_CONFLUENCE_TASK=swaggerConfluence
  local ARTIFACTORY_PUBLISH_TASK=artifactoryPublish

  local GRADLE_TASKS
  local ADDITIONAL_TASKS

  if [[ -f "package.json" ]]; then
    echo "Found package.json"

    if [[ ! -z "${NODE_VERSION}" ]]; then
      echo "Installing version '$NODE_VERSION' of node"
    elif [[ -f ".nvmrc" ]]; then
      echo "Using .nvmrc"
      unset NODE_VERSION
    else
      echo "Using latest 'node' version"
      NODE_VERSION=node
    fi

    source_nvm

    nvm install $NODE_VERSION
    nvm use $NODE_VERSION
    npm install -g $NPM_GLOBAL_PACKAGES
  fi

  echo "Determining builder"
  if [ -f "build.gradle" ]; then
    echo "Found build.gradle"

    export GRADLE_USER_HOME=$HOME

    BUILDER=${BUILDER:-"gradle --no-daemon"}
    BUILD_ARGS=${BUILD_ARGS:-${GRADLE_ARGS:-build}}

    DOCKERFILE_CONTEXT_DIR=${DOCKERFILE_CONTEXT_DIR:-build/docker/}

    if [[ "${OVERRIDE_DOCKERFILE}" == "true" ]]; then
      DOCKERFILE_CONTEXT_DIR=./
      echo "Copying build files to $PWD"
      cp -rf $BUILDFILES_PATH/gradle/* .
    fi

    if [ -f "gradlew" ]; then
      echo "---> Building application with wrapper..."
      BUILDER="./gradlew --no-daemon"
    fi

    if [ "${SKIP_ADDITIONAL_TASKS}" != "true" ];  then
      GRADLE_TASKS=$(bash -c "$BUILDER tasks --all")

      ADDITIONAL_TASKS=""
      if [[ "$GRADLE_TASKS" =~ ${SONARQUBE_TASK} ]]; then
        echo "Found ${SONARQUBE_TASK} gradle task"
        ADDITIONAL_TASKS="$SONARQUBE_TASK"
      fi
      if [[ "$GRADLE_TASKS" =~ ${SWAGGER_CONFLUENCE_TASK} ]]; then
        echo "Found ${SWAGGER_CONFLUENCE_TASK} gradle task"
        ADDITIONAL_TASKS+=" $SWAGGER_CONFLUENCE_TASK"
      fi
      if [[ "$GRADLE_TASKS" =~ ${ARTIFACTORY_PUBLISH_TASK} ]]; then
        echo "Found ${ARTIFACTORY_PUBLISH_TASK} gradle task"
        ADDITIONAL_TASKS+=" $ARTIFACTORY_PUBLISH_TASK"
      fi

      if [[ -n "$ADDITIONAL_TASKS" ]]; then
        if [[ -n "$POST_BUILD_CMDS" ]]; then
          POST_BUILD_CMDS+=";"
        fi
        POST_BUILD_CMDS+="$BUILDER $ADDITIONAL_TASKS"
      fi
    fi
  elif [[ -f "pom.xml" ]]; then
    echo "Using mvn builder"

    BUILDER=${BUILDER:-mvn}
    BUILD_ARGS=${BUILD_ARGS:-${MVN_ARGS:-package}}
    DOCKERFILE_CONTEXT_DIR=${DOCKERFILE_CONTEXT_DIR:-./}

  elif [[ -f "package.json" ]]; then
    echo "Using npm builder"

    BUILDER=${BUILDER:-npm}
    BUILD_ARGS=${BUILD_ARGS:-${NPM_ARGS:-build}}
    DOCKERFILE_CONTEXT_DIR=${DOCKERFILE_CONTEXT_DIR:-./}

    set_frontend_package_versions

    if [ "${SKIP_ADDITIONAL_TASKS}" != "true" ];  then

      ADDITIONAL_TASKS=""
      local APPLICATION_TYPE
      APPLICATION_TYPE=$(node -p "require('./package.json').applicationType")

      NPM_TASKS=$(bash -c "npm run")
      if [[ "$NPM_TASKS" =~ ${SONARQUBE_TASK} ]]; then
        echo "Found ${SONARQUBE_TASK} npm task"
        ADDITIONAL_TASKS="npm run $SONARQUBE_TASK;"
      fi

      if [[ "$APPLICATION_TYPE" == "MODULE" ]]; then
        echo "Application is module"
        export -f deploy_frontend_packages
        ADDITIONAL_TASKS+=" deploy_frontend_packages;"
      fi

      if [[ -n "$ADDITIONAL_TASKS" ]]; then
        if [[ -n "$POST_BUILD_CMDS" ]]; then
          POST_BUILD_CMDS+=";"
        fi
        POST_BUILD_CMDS+="$ADDITIONAL_TASKS"
      fi
    fi

  elif [[ -f "Dockerfile" ]]; then
    echo "Found Dockerfile"

    BUILDER=${BUILDER:-echo}
    BUILD_ARGS=${BUILD_ARGS:-"docker build"}
    DOCKERFILE_CONTEXT_DIR=${DOCKERFILE_CONTEXT_DIR:-./}

  fi

  if [ -z "$BUILDER" ]; then
    echo "---> Could not determine builder"
    exit 1
  fi

  echo "---> Building application from source..."
  BUILD_ARGS=${BUILD_ARGS:-"build"}
  echo "--> # BUILDER = $BUILDER"
  echo "--> # BUILD_ARGS = $BUILD_ARGS"

  echo "---> Building application with..."
  echo "--------> $BUILDER $BUILD_ARGS"
  bash -c "${BUILDER} ${BUILD_ARGS}"

  if [ $? != 0 ]; then
    echo "Error building code using: $BUILDER $BUILD_ARGS"
    exit 1
  fi

  if [ -n "${POST_BUILD_CMDS}" ]; then
    echo "---> Executing Post-Build Commands"
    echo "--------> $POST_BUILD_CMDS"

    if [[ "$DISABLE_POST_BUILD_CMD_EXIT_ON_FAILURE" == "true" ]]; then
      disable_exit_on_failure
    fi

    bash -c "${POST_BUILD_CMDS}"

    if [[ "$DISABLE_POST_BUILD_CMD_EXIT_ON_FAILURE" == "true" ]]; then
      enable_exit_on_failure
    fi
  fi

  if [ -f "sonar-project.properties" ] && [ "${SKIP_ADDITIONAL_TASKS}" != "true" ]; then

    if [[ -f "${HOME}/sonar-scanner.properties" ]]; then
      SONAR_SCANNER_PROPERTIES_PATH=/usr/local/sonar-scanner/conf/sonar-scanner.properties

      rm $SONAR_SCANNER_PROPERTIES_PATH
      ln -s $HOME/sonar-scanner.properties $SONAR_SCANNER_PROPERTIES_PATH
    fi

    echo "---> Running sonar-scanner"
    bash -c "sonar-scanner -Dsonar.projectVersion=${NEXT_VERSION}"
    if [ $? != 0 ]; then
      echo "Error running sonar-scanner"
      exit 1
    fi
  fi

  echo "Exiting $BUILD_DIR"
  popd

  DOCKERFILE_CONTEXT_DIR="${BUILD_DIR}/${DOCKERFILE_CONTEXT_DIR}"
  export DOCKERFILE_CONTEXT_DIR

  echo "$DOCKERFILE_CONTEXT_DIR" > $BUILD_DIR/../STASH_DIRECTORY
  echo "STASH_DIRECTORY: $DOCKERFILE_CONTEXT_DIR"

  echo "Finished building application"

  if [[ -n "$OUTPUT_TYPE" ]]; then

    echo "OUTPUT_TYPE: $OUTPUT_TYPE"
    case $OUTPUT_TYPE in
      bower) #deploy_bower_package
        ;;
      npm) #deploy_npm_package
        ;;
      jar) #steps above should have handled this
        ;;
      docker) return ;;
      image) return ;;
      push) return ;;
      deploy) return ;;
      * ) ;;
    esac

    # We still want to push git tags despite exiting early
    push_git_tags
    success
    exit 0
  fi
}
