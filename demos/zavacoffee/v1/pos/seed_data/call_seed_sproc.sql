-- Example: 14 days, 300 orders per store per day, up to 3 lines per order
EXEC zava.usp_Seed_POS
  @DaysBack                 = 14,
  @OrdersPerStorePerDay     = 300,
  @MaxLinesPerOrder         = 3,
  @PctKiosk                 = 35,
  @PctCustomerAttached      = 40,
  @DoPostInventoryAndOutbox = 0,     -- set to 1 to generate POS Inventory + Outbox
  @MinCustomers             = 10000,
  @AutoSeedReferences       = 1,
