/* Update PO line and header statuses & totals */
;WITH rcv AS (
  SELECT dl.po_line_id,
         SUM(dl.qty_delivered - dl.qty_damaged) AS qty_rcvd
  FROM zava.DeliveryLine dl
  GROUP BY dl.po_line_id
)
UPDATE pol
   SET status = CASE WHEN rcv.qty_rcvd >= pol.qty_ordered THEN 'CLOSED'
                     WHEN rcv.qty_rcvd > 0                     THEN 'PARTIAL'
                     ELSE 'OPEN' END
FROM zava.PurchaseOrderLine pol
LEFT JOIN rcv ON rcv.po_line_id = pol.po_line_id;

;WITH sums AS (
  SELECT po_id, SUM(line_amount_eur) AS total
  FROM zava.PurchaseOrderLine
  GROUP BY po_id
)
UPDATE po SET total_amount_eur = s.total
FROM zava.PurchaseOrder po
JOIN sums s ON s.po_id = po.po_id;
GO
