Deploy schema & seed (Sections 2–3).
Create the views (Section 4).
Run replenishment for today:


EXEC zava.sp_AutoReplenish;

Inspect POs

SELECT * FROM zava.PurchaseOrder ORDER BY po_id DESC;
SELECT * FROM zava.PurchaseOrderLine WHERE po_id = (SELECT MAX(po_id) FROM zava.PurchaseOrder);