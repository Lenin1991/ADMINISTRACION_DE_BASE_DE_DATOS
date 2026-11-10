/* =====================================================================
   SECCIÓN 3 · CONTROL DE CONCURRENCIA · VENTANA DEL OPERADOR B
   LOCK_TIMEOUT de 5 s: si B queda bloqueado, en lugar de esperar
   indefinidamente recibe el error 1222, lo que deja evidencia del bloqueo.
   Orden: A1 → B1 → A2 → A3 → B3 → A4+A5 → B5 → A6 → A7 → B7 → A8 → A9 → B9 → A10 → B11
   ===================================================================== */

/* CASO 1 · LECTURA SUCIA ------------------------------------------------ */
-- B1 · Consulta el paquete 1 con READ UNCOMMITTED
USE RecuperacionLogistica;
SET LOCK_TIMEOUT 5000;   -- si queda bloqueado, error 1222 a los 5 s
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT N'READ UNCOMMITTED' AS Nivel, id_paquete, costo_envio, estado
FROM dbo.Paquetes WHERE id_paquete = 1;   -- lee un dato que A aún no confirma

/* CASO 1 · SOLUCIÓN CON READ COMMITTED ---------------------------------- */
-- B3 · La misma consulta con READ COMMITTED
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
DECLARE @inicio DATETIME2 = SYSDATETIME();
PRINT CONCAT('Inicio de la lectura: ', CONVERT(VARCHAR(12), @inicio, 114));

SELECT N'READ COMMITTED' AS Nivel, id_paquete, costo_envio, estado
FROM dbo.Paquetes WHERE id_paquete = 1;   -- espera el bloqueo X de A → error 1222 a los 5 s

PRINT CONCAT('Tiempo esperado (ms): ', DATEDIFF(MILLISECOND, @inicio, SYSDATETIME()));

/* CASO 2a · READ COMMITTED: LECTURA NO REPETIBLE ------------------------ */
-- B5 · Mientras A tiene abierto su reporte, B sube 5 USD el costo de Quito
UPDATE dbo.Paquetes SET costo_envio = costo_envio + 5.00 WHERE id_sucursal = 2;
SELECT N'Actualización confirmada sin esperar' AS Resultado, @@ROWCOUNT AS Filas;

/* CASO 2b · REPEATABLE READ: FANTASMA ----------------------------------- */
-- B7 · Intenta volver a cambiar los costos
UPDATE dbo.Paquetes SET costo_envio = costo_envio - 5.00 WHERE id_sucursal = 2;
GO   -- → bloqueado por los S de A: error 1222

-- B7b · Inserta un paquete NUEVO en Quito
INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal)
VALUES (N'Paquete fantasma', 1.00, 50.00, 2);
SELECT N'Inserción confirmada' AS Resultado, SCOPE_IDENTITY() AS id_paquete_nuevo;   -- → sí lo logra

/* CASO 2c · SERIALIZABLE ------------------------------------------------ */
-- B9 · Intenta insertar otro paquete en Quito
INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal)
VALUES (N'Segundo fantasma', 1.00, 50.00, 2);
GO   -- → bloqueado por el rango RangeS-S de A: error 1222

-- B9b · Insertar en OTRA sucursal (Guayaquil) queda fuera del rango
INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal)
VALUES (N'Paquete para Guayaquil', 1.00, 8.00, 3);
SELECT N'Inserción en Guayaquil confirmada' AS Resultado;

/* LIMPIEZA ---------------------------------------------------------------- */
-- B11 · Deja los datos como estaban antes de la sección 3
UPDATE dbo.Paquetes SET costo_envio = costo_envio - 5.00
WHERE id_sucursal = 2 AND descripcion <> N'Paquete fantasma';
DELETE FROM dbo.Paquetes WHERE descripcion IN (N'Paquete fantasma', N'Paquete para Guayaquil');
SET LOCK_TIMEOUT -1;

SELECT COUNT(*) AS Paquetes_Quito, SUM(costo_envio) AS Costo_Total_Quito,
       (SELECT COUNT(*) FROM dbo.Paquetes) AS Total_Paquetes
FROM dbo.Paquetes WHERE id_sucursal = 2;   -- 4 · 45.40 · 13
