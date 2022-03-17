1. Let's show easy and auto scaling first. 
2. Show bwazuresqlgp2 and its service tier
3. Show the code to run multiple threads to connect and run a query batch against this server
4. Run the code and show the timings. Almost 30 seconds a query
5. Why? Go to the portal and see high CPU
6. Change the service tier to 8 CPUs
7. Run the program again. See the query batches now run in around 6 seconds per batch
8. So easy scale with no migration
9. 