SELECT COUNT(*) AS stores FROM zava.Store;
SELECT COUNT(*) AS suppliers FROM zava.Supplier;
SELECT COUNT(*) AS products FROM zava.Product;
SELECT COUNT(*) AS supplier_products FROM zava.SupplierProduct;
SELECT COUNT(*) AS spp_params FROM zava.StoreProductParam;

SELECT COUNT(*) AS po_cnt FROM zava.PurchaseOrder;
SELECT COUNT(*) AS po_lines FROM zava.PurchaseOrderLine;
SELECT COUNT(*) AS shipments FROM zava.Shipment;
SELECT COUNT(*) AS deliveries FROM zava.Delivery;
SELECT COUNT(*) AS delivery_lines FROM zava.DeliveryLine;

SELECT COUNT(*) AS inv_txn FROM zava.InventoryTransaction;
SELECT TOP 5 * FROM zava.InventoryTransaction ORDER BY inv_txn_id DESC;
GO
