ostress -E -S. -istart.sql
ostress -E -S. -iinsert.sql -n10 -r5000 -q
ostress -E -S. -icleanup.sql