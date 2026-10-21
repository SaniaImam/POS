/* =====================================================================
   POS - Supplier, Purchase, GRN, Inventory and Sale
   Tables + stored procedures used by POS-Backend

   How to run (SSMS):
     1. Open this file in SSMS, connect to your SQL Server.
     2. Check the database name on the USE line below.
     3. Press F5 (Execute). The script can be run again safely:
        tables are only created if missing, and each procedure is
        dropped (if it exists) and created again.

   Works on SQL Server 2008 and newer.

   Assumes these EXISTING tables (used by the Customer / Item screens):
     dbo.Items      (Id INT PK, ItemCode, ItemName, CategoryId, Price)
     dbo.Categories (Id INT PK, CategoryName)
     dbo.Customers  (Id INT PK, CustomerCode, Name, Phone, Email)
   If yours are named differently, change the REFERENCES / JOIN lines.

   Existing Customer / Item / Category procedures are NOT touched.
   ===================================================================== */

USE POS;
GO


/* =====================================================================
   TABLES
   ===================================================================== */

-- Supplier --------------------------------------------------------------
IF OBJECT_ID('dbo.Suppliers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Suppliers
    (
        Id            INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Suppliers PRIMARY KEY,
        -- SUP-0001, SUP-0002 ... generated from Id
        SupplierCode  AS ('SUP-' + CASE WHEN Id < 10000
                                        THEN RIGHT('0000' + CAST(Id AS VARCHAR(10)), 4)
                                        ELSE CAST(Id AS VARCHAR(10)) END) PERSISTED,
        Name          NVARCHAR(150) NOT NULL,
        ContactPerson NVARCHAR(100) NULL,
        Phone         NVARCHAR(20)  NOT NULL,
        Email         NVARCHAR(150) NULL,
        Address       NVARCHAR(300) NULL,
        -- Suppliers are soft-deleted so old purchases keep their supplier
        IsActive      BIT NOT NULL CONSTRAINT DF_Suppliers_IsActive DEFAULT (1),
        CreatedAt     DATETIME2 NOT NULL CONSTRAINT DF_Suppliers_CreatedAt DEFAULT (SYSDATETIME())
    );

    CREATE UNIQUE INDEX UX_Suppliers_SupplierCode ON dbo.Suppliers (SupplierCode);
END
GO

-- Purchase --------------------------------------------------------------
IF OBJECT_ID('dbo.Purchases', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Purchases
    (
        Id           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Purchases PRIMARY KEY,
        PurchaseNo   AS ('PO-' + CASE WHEN Id < 10000
                                      THEN RIGHT('0000' + CAST(Id AS VARCHAR(10)), 4)
                                      ELSE CAST(Id AS VARCHAR(10)) END) PERSISTED,
        SupplierId   INT NOT NULL CONSTRAINT FK_Purchases_Suppliers REFERENCES dbo.Suppliers (Id),
        PurchaseDate DATE NOT NULL,
        InvoiceNo    NVARCHAR(50)  NULL,
        Remarks      NVARCHAR(500) NULL,
        CreatedAt    DATETIME2 NOT NULL CONSTRAINT DF_Purchases_CreatedAt DEFAULT (SYSDATETIME())
    );

    CREATE UNIQUE INDEX UX_Purchases_PurchaseNo ON dbo.Purchases (PurchaseNo);
END
GO

IF OBJECT_ID('dbo.PurchaseItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PurchaseItems
    (
        Id               INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PurchaseItems PRIMARY KEY,
        PurchaseId       INT NOT NULL CONSTRAINT FK_PurchaseItems_Purchases REFERENCES dbo.Purchases (Id),
        ItemId           INT NOT NULL CONSTRAINT FK_PurchaseItems_Items REFERENCES dbo.Items (Id),
        Quantity         INT NOT NULL CONSTRAINT CK_PurchaseItems_Quantity CHECK (Quantity > 0),
        UnitCost         DECIMAL(18,2) NOT NULL CONSTRAINT CK_PurchaseItems_UnitCost CHECK (UnitCost >= 0),
        -- Increased by every GRN line received against this purchase line
        ReceivedQuantity INT NOT NULL CONSTRAINT DF_PurchaseItems_ReceivedQuantity DEFAULT (0),

        CONSTRAINT UX_PurchaseItems_Purchase_Item UNIQUE (PurchaseId, ItemId),
        CONSTRAINT CK_PurchaseItems_Received CHECK (ReceivedQuantity BETWEEN 0 AND Quantity)
    );
END
GO

-- GRN -------------------------------------------------------------------
IF OBJECT_ID('dbo.GRNs', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GRNs
    (
        Id         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_GRNs PRIMARY KEY,
        GRNNo      AS ('GRN-' + CASE WHEN Id < 10000
                                     THEN RIGHT('0000' + CAST(Id AS VARCHAR(10)), 4)
                                     ELSE CAST(Id AS VARCHAR(10)) END) PERSISTED,
        PurchaseId INT NOT NULL CONSTRAINT FK_GRNs_Purchases REFERENCES dbo.Purchases (Id),
        GRNDate    DATE NOT NULL,
        Remarks    NVARCHAR(500) NULL,
        CreatedAt  DATETIME2 NOT NULL CONSTRAINT DF_GRNs_CreatedAt DEFAULT (SYSDATETIME())
    );

    CREATE UNIQUE INDEX UX_GRNs_GRNNo ON dbo.GRNs (GRNNo);
END
GO

IF OBJECT_ID('dbo.GRNItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GRNItems
    (
        Id               INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_GRNItems PRIMARY KEY,
        GRNId            INT NOT NULL CONSTRAINT FK_GRNItems_GRNs REFERENCES dbo.GRNs (Id),
        ItemId           INT NOT NULL CONSTRAINT FK_GRNItems_Items REFERENCES dbo.Items (Id),
        ReceivedQuantity INT NOT NULL CONSTRAINT CK_GRNItems_ReceivedQuantity CHECK (ReceivedQuantity > 0),

        CONSTRAINT UX_GRNItems_GRN_Item UNIQUE (GRNId, ItemId)
    );
END
GO

-- Inventory (one row per item, created on first GRN) ----------------------
IF OBJECT_ID('dbo.Inventory', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Inventory
    (
        ItemId         INT NOT NULL CONSTRAINT PK_Inventory PRIMARY KEY
                           CONSTRAINT FK_Inventory_Items REFERENCES dbo.Items (Id),
        QuantityOnHand INT NOT NULL CONSTRAINT DF_Inventory_QuantityOnHand DEFAULT (0),
        ReorderLevel   INT NOT NULL CONSTRAINT DF_Inventory_ReorderLevel DEFAULT (0),
        -- Weighted average purchase cost, updated on every GRN
        AverageCost    DECIMAL(18,2) NOT NULL CONSTRAINT DF_Inventory_AverageCost DEFAULT (0),
        LastUpdated    DATETIME2 NULL
    );
END
GO

-- Sale ------------------------------------------------------------------
IF OBJECT_ID('dbo.Sales', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Sales
    (
        Id            INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Sales PRIMARY KEY,
        SaleNo        AS ('SL-' + CASE WHEN Id < 10000
                                       THEN RIGHT('0000' + CAST(Id AS VARCHAR(10)), 4)
                                       ELSE CAST(Id AS VARCHAR(10)) END) PERSISTED,
        SaleDate      DATETIME2 NOT NULL CONSTRAINT DF_Sales_SaleDate DEFAULT (SYSDATETIME()),
        -- NULL = walk-in customer
        CustomerId    INT NULL CONSTRAINT FK_Sales_Customers REFERENCES dbo.Customers (Id),
        Discount      DECIMAL(18,2) NOT NULL CONSTRAINT DF_Sales_Discount DEFAULT (0),
        PaymentMethod NVARCHAR(30) NULL
    );

    CREATE UNIQUE INDEX UX_Sales_SaleNo ON dbo.Sales (SaleNo);
END
GO

IF OBJECT_ID('dbo.SaleItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.SaleItems
    (
        Id        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_SaleItems PRIMARY KEY,
        SaleId    INT NOT NULL CONSTRAINT FK_SaleItems_Sales REFERENCES dbo.Sales (Id),
        ItemId    INT NOT NULL CONSTRAINT FK_SaleItems_Items REFERENCES dbo.Items (Id),
        Quantity  INT NOT NULL CONSTRAINT CK_SaleItems_Quantity CHECK (Quantity > 0),
        UnitPrice DECIMAL(18,2) NOT NULL CONSTRAINT CK_SaleItems_UnitPrice CHECK (UnitPrice >= 0)
    );
END
GO


/* =====================================================================
   SUPPLIER PROCEDURES
   ===================================================================== */

IF OBJECT_ID('dbo.sp_GetSuppliers', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetSuppliers;
GO

CREATE PROCEDURE dbo.sp_GetSuppliers
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        Id,
        SupplierCode,
        Name,
        ContactPerson,
        Phone,
        Email,
        Address
    FROM dbo.Suppliers
    WHERE IsActive = 1
    ORDER BY Id DESC;
END
GO

-- Returns Id = -1 when an active supplier already has this phone number
IF OBJECT_ID('dbo.sp_AddSupplier', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_AddSupplier;
GO

CREATE PROCEDURE dbo.sp_AddSupplier
    @Name          NVARCHAR(150),
    @ContactPerson NVARCHAR(100) = NULL,
    @Phone         NVARCHAR(20),
    @Email         NVARCHAR(150) = NULL,
    @Address       NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM dbo.Suppliers WHERE Phone = @Phone AND IsActive = 1)
    BEGIN
        SELECT -1 AS Id, CAST(NULL AS VARCHAR(20)) AS SupplierCode;
        RETURN;
    END

    INSERT INTO dbo.Suppliers (Name, ContactPerson, Phone, Email, Address)
    VALUES (@Name, NULLIF(@ContactPerson, ''), @Phone, NULLIF(@Email, ''), NULLIF(@Address, ''));

    DECLARE @Id INT = SCOPE_IDENTITY();

    SELECT Id, SupplierCode
    FROM dbo.Suppliers
    WHERE Id = @Id;
END
GO

-- RETURN 0 = updated, -1 = phone used by another supplier, -2 = not found
IF OBJECT_ID('dbo.sp_UpdateSupplier', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_UpdateSupplier;
GO

CREATE PROCEDURE dbo.sp_UpdateSupplier
    @Id            INT,
    @Name          NVARCHAR(150),
    @ContactPerson NVARCHAR(100) = NULL,
    @Phone         NVARCHAR(20),
    @Email         NVARCHAR(150) = NULL,
    @Address       NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Suppliers WHERE Id = @Id AND IsActive = 1)
        RETURN -2;

    IF EXISTS (SELECT 1 FROM dbo.Suppliers WHERE Phone = @Phone AND IsActive = 1 AND Id <> @Id)
        RETURN -1;

    UPDATE dbo.Suppliers
    SET Name          = @Name,
        ContactPerson = NULLIF(@ContactPerson, ''),
        Phone         = @Phone,
        Email         = NULLIF(@Email, ''),
        Address       = NULLIF(@Address, '')
    WHERE Id = @Id;

    RETURN 0;
END
GO

-- Soft delete. NOCOUNT stays OFF: the API reads the affected row count
-- (0 = not found).
IF OBJECT_ID('dbo.sp_DeleteSupplier', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_DeleteSupplier;
GO

CREATE PROCEDURE dbo.sp_DeleteSupplier
    @Id INT
AS
BEGIN
    UPDATE dbo.Suppliers
    SET IsActive = 0
    WHERE Id = @Id AND IsActive = 1;
END
GO


/* =====================================================================
   PURCHASE PROCEDURES
   Status is calculated from received quantities, never stored:
     Pending  = nothing received yet
     Partial  = some received
     Received = every line fully received
   ===================================================================== */

IF OBJECT_ID('dbo.sp_GetPurchases', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetPurchases;
GO

CREATE PROCEDURE dbo.sp_GetPurchases
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.Id,
        p.PurchaseNo,
        p.PurchaseDate,
        p.SupplierId,
        s.Name AS SupplierName,
        p.InvoiceNo,
        COUNT(pi.Id) AS ItemCount,
        ISNULL(SUM(pi.Quantity * pi.UnitCost), 0) AS TotalAmount,
        CASE
            WHEN ISNULL(SUM(pi.ReceivedQuantity), 0) = 0 THEN 'Pending'
            WHEN SUM(pi.ReceivedQuantity) >= SUM(pi.Quantity) THEN 'Received'
            ELSE 'Partial'
        END AS Status
    FROM dbo.Purchases p
    INNER JOIN dbo.Suppliers s ON s.Id = p.SupplierId
    LEFT JOIN dbo.PurchaseItems pi ON pi.PurchaseId = p.Id
    GROUP BY p.Id, p.PurchaseNo, p.PurchaseDate, p.SupplierId, s.Name, p.InvoiceNo
    ORDER BY p.Id DESC;
END
GO

IF OBJECT_ID('dbo.sp_GetPurchaseById', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetPurchaseById;
GO

CREATE PROCEDURE dbo.sp_GetPurchaseById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.Id,
        p.PurchaseNo,
        p.PurchaseDate,
        p.SupplierId,
        s.Name AS SupplierName,
        p.InvoiceNo,
        p.Remarks,
        ISNULL(SUM(pi.Quantity * pi.UnitCost), 0) AS TotalAmount,
        CASE
            WHEN ISNULL(SUM(pi.ReceivedQuantity), 0) = 0 THEN 'Pending'
            WHEN SUM(pi.ReceivedQuantity) >= SUM(pi.Quantity) THEN 'Received'
            ELSE 'Partial'
        END AS Status
    FROM dbo.Purchases p
    INNER JOIN dbo.Suppliers s ON s.Id = p.SupplierId
    LEFT JOIN dbo.PurchaseItems pi ON pi.PurchaseId = p.Id
    WHERE p.Id = @Id
    GROUP BY p.Id, p.PurchaseNo, p.PurchaseDate, p.SupplierId, s.Name, p.InvoiceNo, p.Remarks;
END
GO

IF OBJECT_ID('dbo.sp_GetPurchaseItems', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetPurchaseItems;
GO

CREATE PROCEDURE dbo.sp_GetPurchaseItems
    @PurchaseId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        pi.ItemId,
        i.ItemCode,
        i.ItemName,
        pi.Quantity,
        pi.UnitCost,
        pi.ReceivedQuantity
    FROM dbo.PurchaseItems pi
    INNER JOIN dbo.Items i ON i.Id = pi.ItemId
    WHERE pi.PurchaseId = @PurchaseId
    ORDER BY pi.Id;
END
GO

-- Header only. The API then calls sp_AddPurchaseItem once per line,
-- all inside one transaction.
IF OBJECT_ID('dbo.sp_AddPurchase', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_AddPurchase;
GO

CREATE PROCEDURE dbo.sp_AddPurchase
    @SupplierId   INT,
    @PurchaseDate DATE,
    @InvoiceNo    NVARCHAR(50)  = NULL,
    @Remarks      NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Suppliers WHERE Id = @SupplierId AND IsActive = 1)
    BEGIN
        RAISERROR('Supplier not found.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.Purchases (SupplierId, PurchaseDate, InvoiceNo, Remarks)
    VALUES (@SupplierId, @PurchaseDate, NULLIF(@InvoiceNo, ''), NULLIF(@Remarks, ''));

    DECLARE @Id INT = SCOPE_IDENTITY();

    SELECT Id, PurchaseNo
    FROM dbo.Purchases
    WHERE Id = @Id;
END
GO

IF OBJECT_ID('dbo.sp_AddPurchaseItem', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_AddPurchaseItem;
GO

CREATE PROCEDURE dbo.sp_AddPurchaseItem
    @PurchaseId INT,
    @ItemId     INT,
    @Quantity   INT,
    @UnitCost   DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.PurchaseItems (PurchaseId, ItemId, Quantity, UnitCost)
    VALUES (@PurchaseId, @ItemId, @Quantity, @UnitCost);
END
GO


/* =====================================================================
   GRN PROCEDURES
   ===================================================================== */

IF OBJECT_ID('dbo.sp_GetGRNs', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetGRNs;
GO

CREATE PROCEDURE dbo.sp_GetGRNs
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        g.Id,
        g.GRNNo,
        g.GRNDate,
        g.PurchaseId,
        p.PurchaseNo,
        s.Name AS SupplierName,
        COUNT(gi.Id) AS ItemCount,
        ISNULL(SUM(gi.ReceivedQuantity), 0) AS TotalQuantity,
        g.Remarks
    FROM dbo.GRNs g
    INNER JOIN dbo.Purchases p ON p.Id = g.PurchaseId
    INNER JOIN dbo.Suppliers s ON s.Id = p.SupplierId
    LEFT JOIN dbo.GRNItems gi ON gi.GRNId = g.Id
    GROUP BY g.Id, g.GRNNo, g.GRNDate, g.PurchaseId, p.PurchaseNo, s.Name, g.Remarks
    ORDER BY g.Id DESC;
END
GO

-- Header only. The API then calls sp_AddGRNItem once per line,
-- all inside one transaction.
IF OBJECT_ID('dbo.sp_AddGRN', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_AddGRN;
GO

CREATE PROCEDURE dbo.sp_AddGRN
    @PurchaseId INT,
    @GRNDate    DATE,
    @Remarks    NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Purchases WHERE Id = @PurchaseId)
    BEGIN
        RAISERROR('Purchase not found.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.GRNs (PurchaseId, GRNDate, Remarks)
    VALUES (@PurchaseId, @GRNDate, NULLIF(@Remarks, ''));

    DECLARE @Id INT = SCOPE_IDENTITY();

    SELECT Id, GRNNo
    FROM dbo.GRNs
    WHERE Id = @Id;
END
GO

-- Receives one item. In a single step it:
--   1. saves the GRN line
--   2. adds the quantity to PurchaseItems.ReceivedQuantity
--   3. adds the stock to Inventory and updates the weighted average cost
IF OBJECT_ID('dbo.sp_AddGRNItem', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_AddGRNItem;
GO

CREATE PROCEDURE dbo.sp_AddGRNItem
    @GRNId            INT,
    @ItemId           INT,
    @ReceivedQuantity INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PurchaseId INT;
    DECLARE @Pending    INT;
    DECLARE @UnitCost   DECIMAL(18,2);

    SELECT @PurchaseId = PurchaseId
    FROM dbo.GRNs
    WHERE Id = @GRNId;

    IF @PurchaseId IS NULL
    BEGIN
        RAISERROR('GRN not found.', 16, 1);
        RETURN;
    END

    -- UPDLOCK stops two GRNs receiving the same pending quantity at once
    SELECT
        @Pending  = Quantity - ReceivedQuantity,
        @UnitCost = UnitCost
    FROM dbo.PurchaseItems WITH (UPDLOCK, ROWLOCK)
    WHERE PurchaseId = @PurchaseId AND ItemId = @ItemId;

    IF @Pending IS NULL
    BEGIN
        RAISERROR('Item is not on this purchase.', 16, 1);
        RETURN;
    END

    IF @ReceivedQuantity <= 0 OR @ReceivedQuantity > @Pending
    BEGIN
        RAISERROR('Received quantity is more than the pending quantity.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.GRNItems (GRNId, ItemId, ReceivedQuantity)
    VALUES (@GRNId, @ItemId, @ReceivedQuantity);

    UPDATE dbo.PurchaseItems
    SET ReceivedQuantity = ReceivedQuantity + @ReceivedQuantity
    WHERE PurchaseId = @PurchaseId AND ItemId = @ItemId;

    IF EXISTS (SELECT 1 FROM dbo.Inventory WITH (UPDLOCK) WHERE ItemId = @ItemId)
    BEGIN
        UPDATE dbo.Inventory
        SET AverageCost = CASE
                              WHEN QuantityOnHand <= 0 THEN @UnitCost
                              ELSE ROUND(((QuantityOnHand * AverageCost) + (@ReceivedQuantity * @UnitCost))
                                         / (QuantityOnHand + @ReceivedQuantity), 2)
                          END,
            QuantityOnHand = QuantityOnHand + @ReceivedQuantity,
            LastUpdated    = SYSDATETIME()
        WHERE ItemId = @ItemId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.Inventory (ItemId, QuantityOnHand, AverageCost, LastUpdated)
        VALUES (@ItemId, @ReceivedQuantity, @UnitCost, SYSDATETIME());
    END
END
GO


/* =====================================================================
   INVENTORY PROCEDURES
   ===================================================================== */

-- Every item is listed; items never received show 0 on hand
IF OBJECT_ID('dbo.sp_GetInventory', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetInventory;
GO

CREATE PROCEDURE dbo.sp_GetInventory
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        i.Id AS ItemId,
        i.ItemCode,
        i.ItemName,
        ISNULL(c.CategoryName, '') AS CategoryName,
        ISNULL(inv.QuantityOnHand, 0) AS QuantityOnHand,
        ISNULL(inv.ReorderLevel, 0) AS ReorderLevel,
        ISNULL(inv.AverageCost, 0) AS AverageCost,
        inv.LastUpdated
    FROM dbo.Items i
    LEFT JOIN dbo.Categories c ON c.Id = i.CategoryId
    LEFT JOIN dbo.Inventory inv ON inv.ItemId = i.Id
    ORDER BY i.ItemName;
END
GO


/* =====================================================================
   SALE PROCEDURES
   (read-only for now: the Sale Record screen only lists sales.
    A checkout screen will need an sp_AddSale / sp_AddSaleItem pair that
    also reduces Inventory.QuantityOnHand.)
   ===================================================================== */

-- ItemCount = total units sold on the sale
IF OBJECT_ID('dbo.sp_GetSales', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetSales;
GO

CREATE PROCEDURE dbo.sp_GetSales
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        sa.Id,
        sa.SaleNo,
        sa.SaleDate,
        sa.CustomerId,
        cu.Name AS CustomerName,
        ISNULL(SUM(si.Quantity), 0) AS ItemCount,
        ISNULL(SUM(si.Quantity * si.UnitPrice), 0) AS SubTotal,
        sa.Discount,
        ISNULL(SUM(si.Quantity * si.UnitPrice), 0) - sa.Discount AS TotalAmount,
        sa.PaymentMethod
    FROM dbo.Sales sa
    LEFT JOIN dbo.Customers cu ON cu.Id = sa.CustomerId
    LEFT JOIN dbo.SaleItems si ON si.SaleId = sa.Id
    GROUP BY sa.Id, sa.SaleNo, sa.SaleDate, sa.CustomerId, cu.Name, sa.Discount, sa.PaymentMethod
    ORDER BY sa.SaleDate DESC, sa.Id DESC;
END
GO

IF OBJECT_ID('dbo.sp_GetSaleById', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetSaleById;
GO

CREATE PROCEDURE dbo.sp_GetSaleById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        sa.Id,
        sa.SaleNo,
        sa.SaleDate,
        sa.CustomerId,
        cu.Name AS CustomerName,
        ISNULL(SUM(si.Quantity * si.UnitPrice), 0) AS SubTotal,
        sa.Discount,
        ISNULL(SUM(si.Quantity * si.UnitPrice), 0) - sa.Discount AS TotalAmount,
        sa.PaymentMethod
    FROM dbo.Sales sa
    LEFT JOIN dbo.Customers cu ON cu.Id = sa.CustomerId
    LEFT JOIN dbo.SaleItems si ON si.SaleId = sa.Id
    WHERE sa.Id = @Id
    GROUP BY sa.Id, sa.SaleNo, sa.SaleDate, sa.CustomerId, cu.Name, sa.Discount, sa.PaymentMethod;
END
GO

IF OBJECT_ID('dbo.sp_GetSaleItems', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetSaleItems;
GO

CREATE PROCEDURE dbo.sp_GetSaleItems
    @SaleId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        si.ItemId,
        i.ItemCode,
        i.ItemName,
        si.Quantity,
        si.UnitPrice
    FROM dbo.SaleItems si
    INNER JOIN dbo.Items i ON i.Id = si.ItemId
    WHERE si.SaleId = @SaleId
    ORDER BY si.Id;
END
GO
