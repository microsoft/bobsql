#!/bin/sh
set -eu
: "${SQLCMDPASSWORD:?Set SQLCMDPASSWORD privately before running this demo}"
export SQLCMDPASSWORD
SERVERIP=$(kubectl get services -o=jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
PORT=31433
sqlcmd -b -Usa -S$SERVERIP,$PORT -Q"SHUTDOWN WITH NOWAIT"