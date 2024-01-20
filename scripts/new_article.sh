#!/bin/bash
set -eu -o pipefail

RESPONSE_FILE=`mktemp`
npx zenn new:article --machine-readable $@ | tee $RESPONSE_FILE
NLINES=`cat $RESPONSE_FILE | wc -l`
if [ $NLINES -ne 1 ]; then
    rm $RESPONSE_FILE
    exit 1
fi

SLUG=$(basename `cat $RESPONSE_FILE` | sed "s/\.md//g")
echo $SLUG | grep "^[0-9a-z_-]\{12,50\}$" > /dev/null
if [ $? -ne 0 ]; then
    rm $RESPONSE_FILE
    # Invalid slag https://zenn.dev/zenn/articles/what-is-slug
    exit 1
fi

mkdir -p images/$SLUG
echo images/$SLUG
rm $RESPONSE_FILE
