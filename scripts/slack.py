#!/usr/bin/env python

import sys
import requests
import json
import os
from argparse import ArgumentParser


def str2bool(v):
    if v.lower() in ('yes', 'true', 't', 'y', '1'):
        return True
    elif v.lower() in ('no', 'false', 'f', 'n', '0'):
        return False
    else:
        raise argparse.ArgumentTypeError('Boolean value expected.')


try:
    PEOPLE = os.environ['SLACK_PEOPLE_MAP']
    URL = os.environ['SLACK_URL']
except KeyError as e:
    print('{} environment variable not defined!'.format(e))
    sys.exit(1)

def slack(text, username = None, icon_emoji = None, icon_url = None, channel = None, attachment = None):
    payload = '{'

    if username:
        payload += '"username": "{}", '.format(username)

    if icon_emoji:
        payload += '"icon_emoji": "{}", '.format(icon_emoji)

    if icon_url:
        payload += '"icon_url": "{}", '.format(icon_url)

    if channel:
        payload += '"channel": "{}", '.format(channel)

    if attachment:
        payload += '{}, '.format(attachment)

    payload += '"text": "{}"'.format(text)
    payload += '}'

    r = requests.post(URL, data=payload)


parser = ArgumentParser(prog='slack')
parser.add_argument("--success", type=str2bool, nargs='?',
                        const=True, default=True,
                        help="Indicate if build was successful.")
args = parser.parse_args()

try:
    BUILD = os.environ['BUILD']
except KeyError as e:
    err_msg = '{} environment variable not defined!'.format(e)
    print(err_msg)
    slack(err_msg, channel="@czuares")
    sys.exit(0);

BUILD_JSON = json.loads(BUILD)
BC = BUILD_JSON['metadata']['labels']['bc']
BUILD_NUM = BUILD_JSON['metadata']['annotations']['openshift.io/build.number']

if args.success:
    status = 'successful'
else:
    status = 'failed'

try:
    COMMIT_AUTHOR = os.environ['COMMIT_AUTHOR']
    COMMIT_AUTHOR_EMAIL = os.environ['COMMIT_AUTHOR_EMAIL']
    NEXT_VERSION = os.environ['NEXT_VERSION']
    message = 'Build #{} for `{}:{}` by \'{}\' {}'.format(BUILD_NUM, BC, NEXT_VERSION, COMMIT_AUTHOR, status)
except KeyError as e:
    COMMIT_AUTHOR_EMAIL = ''
    message = 'Build #{} for `{}` {}'.format(BUILD_NUM, BC, status)


PEOPLE_JSON = json.loads(PEOPLE)
#print(PEOPLE_JSON)
#print(COMMIT_AUTHOR_EMAIL)
#print(args.success)

# Send the message directly to the user if we know their Slack username
if COMMIT_AUTHOR_EMAIL in PEOPLE_JSON and not args.success:
    print('Sending message to author {}'.format(COMMIT_AUTHOR_EMAIL))
    slack(message, channel=PEOPLE_JSON[COMMIT_AUTHOR_EMAIL])

# Always send to channel
slack(message)
