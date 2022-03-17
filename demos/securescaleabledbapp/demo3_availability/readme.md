1. Show the code on how retry logic works with the provider
2. Change the app config file to use a db that doesn't exist
3. rebuild and run the code and observe the errors and retry messages
4. Change the app config file to bwazursqlgp2 and reubild the app
5. Run failovergp.ps1 to initiate a GP service tier failover
6. Observe the retries and eventual success
7. Change the code to use the BC conn string and rebuild
8. Run failoverbc.ps1 to initiate a BC service tier failover
9. Observe retries are almost slient and it "just works"