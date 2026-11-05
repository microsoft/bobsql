ostress -E -S. -istart.sql
ostress -E -S. -iinsert.sql -n10 -q -r10000
ostress -E -S. -icleanup.sql