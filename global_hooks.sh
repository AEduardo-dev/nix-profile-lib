#!/usr/bin/env bash

refresh() {
    kill -SIGUSR1 $PPID
    exit 0
}

switch() {
    echo "$1" >/tmp/devshell-expected-profile
    kill -SIGUSR1 $PPID
    exit 0
}

echo "✓ Global functions loaded: refresh, switch"
