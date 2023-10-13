#!/bin/sh

# Stop when error
set -e

# Generate secrets, copy .env.secret template to .env.secret and replace generated secrets
awk '
  /generatethispass/ {
    cmd = "< /dev/urandom tr -dc A-Za-z0-9_ | head -c 25"
    cmd | getline str
    close(cmd)
    gsub("generatethispass", str)
  }
  { print }
' .env.secret.template > .env.secret

