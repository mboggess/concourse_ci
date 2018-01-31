#!/usr/bin/env bash

function get_version() {
  #BUILD_DIR
  #TAG_BRANCHES
  #PUSH_TAGS
  #NEXT_VERSION

  source_nvm

  local DEFAULT_VERSION=0.1.0
  NEXT_VERSION=${NEXT_VERSION:-$DEFAULT_VERSION}
  TAG_BRANCHES=${TAG_BRANCHES:-"^master$|^develop$|^release/|^hotfix/"}

  local MAX_TAG_LENGTH=128
  local BRANCH_ARR
  local VERSION_TAG
  local CURRENT_BRANCH_TAG
  local FLAT_REF
  local SHORT_HASH
  local COMMIT_DATE
  local DATE

  if [[ -z "$BUILD_DIR" ]] || [[ ! -d "${BUILD_DIR}" ]]; then
    echo 'BUILD_DIR is invalid or non-existent!'
    exit 1
  fi

  if [[ -z "${TAG_BRANCHES}" ]]; then
    echo "Missing TAG_BRANCHES variable! Set TAG_BRANCHES='master|develop|etc' to specify branches that should receive tags"
    exit 1
  fi

  VERSIONABLE=false
  BRANCH_ARR=(${TAG_BRANCHES//|/ })
  for tag in "${BRANCH_ARR[@]}"
  do
    # echo "Checking $SOURCE_REF against $tag"
    if [[ "$SOURCE_REF" =~ $tag ]]; then
      echo "Found matching branch ${tag} pattern"
      VERSIONABLE=true
      break
    fi
  done
  echo "Branch ${SOURCE_REF} is versionable: ${VERSIONABLE}"

  VERSION_TAG=$(git -C $BUILD_DIR rev-list --tags --max-count=1 2>/dev/null \
    | xargs --no-run-if-empty git -C $BUILD_DIR describe --tags || true)
  echo "Current Branch Version: $VERSION_TAG"
  # VERSION_TAG=$(git rev-list --tags --max-count=1 | xargs git describe --tags || true)
  # VERSION_TAG=$(git tag --list --sort=version:refname 2>/dev/null | tail -1 || true)

  if [[ -z "${VERSION_TAG}" ]]; then
    echo "No git tags found - starting with ${NEXT_VERSION}"
  else
    CURRENT_BRANCH_TAG=$(git -C $BUILD_DIR tag --points-at HEAD | tail -1)
    echo "Current Branch Tag: $CURRENT_BRANCH_TAG"

    if [[ "$VERSIONABLE" == "false" ]]; then
      PUSH_TAGS=false # make sure we don't push to git - regardless
      PUSH_JFROG=false # don't push to artifactory

      FLAT_REF="${SOURCE_REF//[^[:alnum:]]/_}"
      COMMIT_DATE=$(git -C $BUILD_DIR log -1 --format=%cd --date=iso)
      DATE=$(date --date="$COMMIT_DATE" +%Y%m%d)
      SHORT_HASH=$(git -C $BUILD_DIR rev-parse --short HEAD)
      NEXT_VERSION="SNAPSHOT-${DATE}-${FLAT_REF}-${SHORT_HASH}"

      # Sanity check the docker tag length
      if [[ ${#NEXT_VERSION} -ge $MAX_TAG_LENGTH ]]; then
        MAX_LENGTH=$(expr $MAX_TAG_LENGTH - ${#NEXT_VERSION} + ${#FLAT_REF})
        echo "Flattened git ref $FLAT_REF is too long! Must be less than $MAX_LENGTH chars."
        # FLAT_REF="${FLAT_REF::$MAX_LENGTH}"
        exit 1
      fi
      echo "Using $NEXT_VERSION as tag"

    elif [[ "${CURRENT_BRANCH_TAG}" == "${VERSION_TAG}" ]]; then
      if [[ "$REBUILD" != "true" ]]; then
        echo "This branch has already been tagged $VERSION_TAG - Use REBUILD=true to force a rebuild"
        exit 1
      fi
      # We have already built this branch, don't increment or push tags again
      echo "Rebuilding Version: ${VERSION_TAG}"
      NEXT_VERSION="$VERSION_TAG"
      VERSIONABLE=false
      # PUSH_TAGS=false #Don't push tag again
    else
      if [[ $VERSION_TAG =~ -1$ ]]; then
        #Hack to support version tags ending in -1 that should start at 0
        echo "Found .-1 patch version, next version will end with .0"
        BUMPED_VERSION=$(echo $VERSION_TAG | sed -e 's/-1$/0/g')

        # parse and validate version
        BUMPED_VERSION=$(semver $BUMPED_VERSION)
      else
        # Fetch branch name before first / (if it exists)
        local BRANCH_BASE="${SOURCE_REF%/*}"
        # Do some replacements of known branches
        BRANCH=$(sed -e's/release/rc/; s/develop//; s/master//;' <<< "$BRANCH_BASE")
        if [[ -z "$BRANCH" ]]; then
          BUMPED_VERSION=$(semver -i $VERSION_TAG || true)
        else
          BUMPED_VERSION=$(semver -i prerelease $VERSION_TAG --preid $BRANCH || true)
        fi
      fi

      if [[ -z "${BUMPED_VERSION}" ]]; then
        echo 'Error getting next build version!'
        exit 1
      fi
      NEXT_VERSION=$BUMPED_VERSION
      echo "Incrementing Build Version to: ${NEXT_VERSION}"
    fi
  fi

  BUILD_NUMBER=${NEXT_VERSION}

  export NEXT_VERSION
  export BUILD_NUMBER
  export PUSH_TAGS
  export PUSH_JFROG
  export VERSIONABLE

  echo "$NEXT_VERSION" > $BUILD_DIR/../VERSION
  echo "VERSION: $NEXT_VERSION"
  echo "PUSH_TAGS: $PUSH_TAGS"
  echo "VERSIONABLE: $VERSIONABLE"
}

function get_commit_info() {
  #BUILD_DIR

  if [[ -z "$BUILD_DIR" ]] || [[ ! -d "${BUILD_DIR}" ]]; then
    echo 'BUILD_DIR is invalid or non-existent!'
    exit 1
  fi

  COMMIT_ID=$(git -C $BUILD_DIR log -1 --format="%H")
  COMMIT_DATE=$(git -C $BUILD_DIR log -1 --format=%cd --date=local)
  COMMIT_AUTHOR=$(git -C $BUILD_DIR log -1 --format='%an <%ae>')
  COMMIT_AUTHOR_EMAIL=$(git -C $BUILD_DIR log -1 --format='%ae')
  COMMIT_MESSAGE=$(git -C $BUILD_DIR log -1 --pretty=%B | cat)

  export COMMIT_ID
  export COMMIT_DATE
  export COMMIT_AUTHOR
  export COMMIT_AUTHOR_EMAIL
  export COMMIT_MESSAGE

  echo "COMMIT_ID: ${COMMIT_ID}"
  echo "COMMIT_DATE: ${COMMIT_DATE}"
  echo "COMMIT_AUTHOR: ${COMMIT_AUTHOR}"
  echo "COMMIT_AUTHOR_EMAIL: ${COMMIT_AUTHOR_EMAIL}"
  echo "COMMIT_MESSAGE: ${COMMIT_MESSAGE}"
}

function tag_repo() {
  #PUSH_TAGS
  #VERSIONABLE
  #BUILD_DIR
  #NEXT_VERSION

  if [[ -z "$BUILD_DIR" ]] || [[ ! -d "${BUILD_DIR}" ]]; then
    echo 'BUILD_DIR is invalid or non-existent!'
    exit 1
  fi

  if [[ -z "$NEXT_VERSION" ]]; then
    echo 'NEXT_VERSION is empty!'
    exit 1
  fi

  if [[ "${PUSH_TAGS}" == "true" && "${VERSIONABLE}" == "true" ]]; then
    echo "Tagging repository as ${NEXT_VERSION}"
    git -C $BUILD_DIR tag $NEXT_VERSION
  fi
}

function push_git_tags() {
  #PUSH_TAGS
  #VERSIONABLE
  #BUILD_DIR
  #NEXT_VERSION

  if [[ -z "$BUILD_DIR" ]] || [[ ! -d "${BUILD_DIR}" ]]; then
    echo 'BUILD_DIR is invalid or non-existent!'
    exit 1
  fi

  if [[ -z "$NEXT_VERSION" ]]; then
    echo 'NEXT_VERSION is empty!'
    exit 1
  fi

  if [[ "${PUSH_TAGS}" == "true" && "${VERSIONABLE}" == "true" ]]; then
    echo "Pushing tag to origin"
    git -C $BUILD_DIR push origin $NEXT_VERSION
  fi
}
