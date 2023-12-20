#!/bin/sh

# Stop when error
set -e

# Input and output file names
input_file="/shell/env/.env.secret.template"
output_file=".env.secret"

# Function to generate a random password
generate_password() {
  used_symbols="$1"
  length="$2"
  password="$(tr -dc "$used_symbols" < /dev/urandom | fold -w "$length" | head -n 1)"
  echo "$password"
}

# Function to escape special characters for sed
escape_for_sed() {
  echo "$1" | sed -e 's/[\/&]/\\&/g'
}

# Read the input file line by line and process it
while IFS= read -r line; do

  # Check if the line contains 'generate_this_pass'
  if echo "$line" | grep -q 'generate_this_pass'; then
    # Generate a new password for this occurrence
    password=$(generate_password "A-Za-z0-9_" 25)
    # Replace 'generate_this_pass' with the generated password, properly escaped
    line="$(echo "$line" | sed "s/$(escape_for_sed "generate_this_pass")/$(escape_for_sed "$password")/")"
  fi

  # Check if the line contains 'generate_key'
  if echo "$line" | grep -q 'generate_key'; then
    # Generate a new key for this occurrence
    key=$(generate_password "A-Za-z0-9_!@#$%^&*()+-={}[]|:;,<>" 65)
    # Replace 'generate_key' with the generated key, properly escaped
    line="$(echo "$line" | sed "s/$(escape_for_sed "generate_key")/$(escape_for_sed "$key")/")"
  fi

  # Append the processed line to the output file
  echo "$line" >> "$output_file"
done < "$input_file"
