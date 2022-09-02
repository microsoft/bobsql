# Demo for Purview access policies with SQL Server 2022

UNDER CONSTRUCTION

# Prereqs

1. Invite guest AAD account and have one other account that is not your AAD admin available.

# Steps for demo

1. Enable Purview in portal for SQL Server - Azure Arc.
1. Launch Purview Studio in the portal.
1. Click on Data Map on the left-hand menu.
1. Select Sources from new menu displayed.
1. Select Register. In the search window type in Arc. Select SQL Server on Arc-enabled servers and clock on Continue.
1. Fill out the Register sources screen
    1. Given it a new name.
    1. Choose your subscription
    1. Choose your Server name which is the Azure Arc Server for SQL Server 2022
    1. For Server endpoint just put in the same as Server name.
    1. Leave root collection
    1. Click on the refresh button to fill in the Application ID.
    1. If the Enabled button is greyed out the data source is automatically enabled for Data use Management.
    1. Click on Register.
    1. Your data source should now appear on the list of data sources
1. Create a Data policy for your other AAD account
    1. 