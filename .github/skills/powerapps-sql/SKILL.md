---
name: powerapps-sql
description: "Build the Power Apps orders canvas app backed by Azure SQL AdventureWorksLT. Use when working with examples/powerappssql, SalesLT order galleries, customer/product lookups, order-detail filtering, or the editable order form."
---

# Power Apps with Azure SQL

## Procedure

1. Read the [walkthrough](../../../examples/powerappssql/readme.md).
   Verify an Azure SQL database with the required `SalesLT` tables and access
   to a Power Platform environment.
2. Confirm connection and authentication prerequisites. The inherited example
   uses SQL authentication; enter credentials only in the supported private
   connection UI, never in source or chat. Explain any firewall/authentication
   change and obtain approval before applying it.
3. Follow the walkthrough to create the SQL connection and canvas app, then
   build the order gallery and customer-name lookup.
4. Add the selected-order form, order-detail gallery, and product-name lookup.
   Verify actual control names before adapting formulas; template-generated
   names may differ from the walkthrough.
5. Add sorting and save behavior. Test selection/context changes before writes.
   Obtain approval before updating order data, then verify the change in SQL.
6. Save the app and report the tested behavior and remaining configuration.
   Do not delete shared connections, apps, or databases as automatic cleanup.

Use synthetic sample orders and the
[repository publishing checks](../../../SECRET-SCANNING.md).
