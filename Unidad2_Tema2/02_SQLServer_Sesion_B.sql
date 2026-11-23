/* =====================================================================
   AA4 · SQL Server · SEGUNDA PESTAÑA (sesión B)
   Se usa solo en la demostración de REDO/UNDO de la sección 1.
   ===================================================================== */

-- B1 · (después del bloque 1.5) Abre una venta y NO la confirma
USE FarmaciaDB;
BEGIN TRANSACTION VentaEnCurso;
    INSERT INTO dbo.Ventas (id_cliente, total) VALUES (1, 999.99);
    SELECT SCOPE_IDENTITY() AS Venta_Sin_Confirmar, @@TRANCOUNT AS Transacciones_Abiertas;
-- (la transacción queda abierta mientras se ejecuta el bloque 1.6)

-- B2 · (después del bloque 1.6) La cajera anula la venta
ROLLBACK TRANSACTION VentaEnCurso;
SELECT @@TRANCOUNT AS Transacciones_Abiertas;
USE master;   -- libera la base para la conmutación de la sección 4
