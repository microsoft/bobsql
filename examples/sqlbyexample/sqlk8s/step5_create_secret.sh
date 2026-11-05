#!/bin/sh
set -eu
: "${SQLCMDPASSWORD:?Set SQLCMDPASSWORD privately before running this demo}"
export SQLCMDPASSWORD
printf '%s' "$SQLCMDPASSWORD" | kubectl create secret generic mssql-secret --from-file=SA_PASSWORD=/dev/stdin
