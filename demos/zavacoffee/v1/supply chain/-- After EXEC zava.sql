-- After EXEC zava.sp_AutoReplenish (with @create_future_receipts = 0 recommended now)
EXEC zava.sp_CreateShipmentsFromApprovedPOs;
