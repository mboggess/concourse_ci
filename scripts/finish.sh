#!/usr/bin/env bash

function success() {
  trigger_sanity_test
  
  python $SCRIPT_DIR/slack.py --success 1
}

function failure() {
  if [[ $? == 0 ]]; then
    return
  fi

  python $SCRIPT_DIR/slack.py --success 0
}

function trigger_sanity_test() {
    curl https://jenkins-automation.apps.els-ols.com/job/Sanity%20Test/build?token=YnvaUR07rvi8aChPdWr6 || true
}
