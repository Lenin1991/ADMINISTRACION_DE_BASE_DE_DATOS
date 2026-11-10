/* =====================================================================
   SECCIÓN 3 · CONTROL DE CONCURRENCIA · VENTANA DEL OPERADOR A
   Ejecutar cada paso por separado, alternando con la ventana del
   operador B en este orden:
   A1 → B1 → A2 → A3 → B3 → A4+A5 → B5 → A6 → A7 → B7 → A8 → A9 → B9 → A10 → B11
   ===================================================================== */

/* ---------------------------------------------------------------------
   CASO 1 · LECTURA SUCIA (READ UNCOMMITTED)
   --------------------------------------------------------------------- */
-- A1 · Modifica el paquete 1 SIN confirmar
USE RecuperacionLogistica;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRANSACTION;
    UPDATE dbo.Paquetes
    SET costo_envio = 999.99, estado = 'DEVUELTO'
    WHERE id_paquete = 1;

    SELECT id_paquete, costo_envio, estado, @@TRANCOUNT AS Transacciones_Abiertas
    FROM dbo.Paquetes WHERE id_paquete = 1;
-- (sin COMMIT: la transacción queda abierta)

-- A2 · A se arrepiente y deshace el cambio
ROLLBACK TRANSACTION;

SELECT id_paquete, costo_envio, estado, @@TRANCOUNT AS Transacciones_Abiertas
FROM dbo.Paquetes WHERE id_paquete = 1;   -- el paquete vuelve a 12.50 / ENTREGADO

/* ---------------------------------------------------------------------
   CASO 1 · SOLUCIÓN CON READ COMMITTED
   --------------------------------------------------------------------- */
-- A3 · Vuelve a modificar SIN confirmar y muestra sus bloqueos exclusivos (X)
BEGIN TRANSACTION;
    UPDATE dbo.Paquetes
    SET costo_envio = 999.99, estado = 'DEVUELTO'
    WHERE id_paquete = 1;

    SELECT resource_type AS Recurso, request_mode AS Modo, request_status AS Estado
    FROM sys.dm_tran_locks
    WHERE request_session_id = @@SPID AND resource_type IN ('KEY', 'PAGE', 'OBJECT');

-- A4 · Deshace el cambio del caso 1
ROLLBACK TRANSACTION;

/* ---------------------------------------------------------------------
   CASO 2 · REPORTE DE PAQUETES DE QUITO MIENTRAS B ALTERA LOS COSTOS
   2a · READ COMMITTED → lectura no repetible
   --------------------------------------------------------------------- */
-- A5 · Primera lectura del reporte de Quito
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRANSACTION;
    SELECT N'Lectura 1' AS Lectura, COUNT(*) AS Paquetes, SUM(costo_envio) AS Costo_Total
    FROM dbo.Paquetes WHERE id_sucursal = 2;
-- (la transacción del reporte sigue abierta)

-- A6 · Segunda lectura en la MISMA transacción
    SELECT N'Lectura 2' AS Lectura, COUNT(*) AS Paquetes, SUM(costo_envio) AS Costo_Total
    FROM dbo.Paquetes WHERE id_sucursal = 2;   -- el total cambió: LECTURA NO REPETIBLE
COMMIT TRANSACTION;

/* 2b · REPEATABLE READ → sin lectura no repetible, pero con fantasma ---- */
-- A7 · Primera lectura
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRANSACTION;
    SELECT N'Lectura 1' AS Lectura, COUNT(*) AS Paquetes, SUM(costo_envio) AS Costo_Total
    FROM dbo.Paquetes WHERE id_sucursal = 2;
-- (los bloqueos compartidos S se mantienen hasta el final de la transacción)

-- A8 · Segunda lectura en la MISMA transacción
    SELECT N'Lectura 2' AS Lectura, COUNT(*) AS Paquetes, SUM(costo_envio) AS Costo_Total
    FROM dbo.Paquetes WHERE id_sucursal = 2;   -- aparece una fila nueva: FANTASMA

    SELECT id_paquete, descripcion, costo_envio
    FROM dbo.Paquetes WHERE id_sucursal = 2 ORDER BY id_paquete;
COMMIT TRANSACTION;

/* 2c · SERIALIZABLE → sin lectura no repetible ni fantasma -------------- */
-- A9 · Primera lectura y bloqueos de rango
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRANSACTION;
    SELECT N'Lectura 1' AS Lectura, COUNT(*) AS Paquetes, SUM(costo_envio) AS Costo_Total
    FROM dbo.Paquetes WHERE id_sucursal = 2;

    SELECT resource_type AS Recurso, request_mode AS Modo, COUNT(*) AS Cantidad
    FROM sys.dm_tran_locks
    WHERE request_session_id = @@SPID AND resource_type IN ('KEY', 'OBJECT', 'PAGE')
    GROUP BY resource_type, request_mode;   -- RangeS-S: bloquea también los "huecos"

-- A10 · Segunda lectura → idéntica a la primera
    SELECT N'Lectura 2' AS Lectura, COUNT(*) AS Paquetes, SUM(costo_envio) AS Costo_Total
    FROM dbo.Paquetes WHERE id_sucursal = 2;   -- sin lectura no repetible ni fantasma
COMMIT TRANSACTION;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
