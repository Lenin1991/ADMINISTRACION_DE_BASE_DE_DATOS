/* =====================================================================
   ADMINISTRACIÓN DE BASES DE DATOS · Unidad 2 · Tema 2 (AA4)
   Recuperación en gestores de BD · Parte SQL Server
   ---------------------------------------------------------------------
   Motor : Microsoft SQL Server 2019 o superior
   Autor : Lenin Vladimir Peñafiel Buestán
   Caso  : Farmacia "Salud Andina" (Riobamba) · base FarmaciaDB
   ---------------------------------------------------------------------
   ORDEN DE EJECUCIÓN (bloque por bloque, en la MISMA pestaña salvo
   el bloque 1.6, que usa una segunda pestaña: 02_SQLServer_Sesion_B.sql)
     1. Logs de transacciones: configuración, DML, UNDO y REDO
     2. Log shipping hacia FarmaciaDB_Secundaria (método DRP 1)
     3. Caso práctico: pérdida parcial de datos y PITR con STOPAT
     4. Desastre del servidor principal y conmutación (failover)
   ===================================================================== */


/* =====================================================================
   SECCIÓN 1 · LOGS DE TRANSACCIONES
   ===================================================================== */

-- 1.1 Base de datos, modelo FULL y configuración del archivo de log ------
USE master;
GO
IF DB_ID(N'FarmaciaDB_Redo')       IS NOT NULL BEGIN ALTER DATABASE FarmaciaDB_Redo       SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE FarmaciaDB_Redo;       END
IF DB_ID(N'FarmaciaDB_PITR')       IS NOT NULL BEGIN ALTER DATABASE FarmaciaDB_PITR       SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE FarmaciaDB_PITR;       END
IF DB_ID(N'FarmaciaDB_Secundaria') IS NOT NULL BEGIN DROP DATABASE FarmaciaDB_Secundaria; END
IF DB_ID(N'FarmaciaDB')            IS NOT NULL BEGIN ALTER DATABASE FarmaciaDB            SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE FarmaciaDB;            END
GO
CREATE DATABASE FarmaciaDB;
GO
-- Modelo FULL: el log conserva cada transacción hasta que se respalda.
ALTER DATABASE FarmaciaDB SET RECOVERY FULL;
-- Log con tamaño inicial y crecimiento fijos (evita crecimientos pequeños
-- y frecuentes, que fragmentan el log en muchos VLF).
ALTER DATABASE FarmaciaDB MODIFY FILE (NAME = N'FarmaciaDB_log', SIZE = 64MB, FILEGROWTH = 64MB);
GO

USE FarmaciaDB;
GO
CREATE TABLE dbo.Clientes (
    id_cliente   INT IDENTITY(1,1) CONSTRAINT PK_Clientes PRIMARY KEY,
    cedula       CHAR(10)      NOT NULL CONSTRAINT UQ_Clientes_cedula UNIQUE,
    nombre       NVARCHAR(100) NOT NULL,
    telefono     VARCHAR(15)   NULL,
    correo       VARCHAR(100)  NULL
);
CREATE TABLE dbo.Productos (
    id_producto  INT IDENTITY(1,1) CONSTRAINT PK_Productos PRIMARY KEY,
    nombre       NVARCHAR(100) NOT NULL,
    laboratorio  NVARCHAR(60)  NOT NULL,
    precio       DECIMAL(10,2) NOT NULL CONSTRAINT CK_Productos_precio CHECK (precio > 0),
    stock        INT           NOT NULL CONSTRAINT CK_Productos_stock  CHECK (stock >= 0)
);
CREATE TABLE dbo.Ventas (
    id_venta     INT IDENTITY(1,1) CONSTRAINT PK_Ventas PRIMARY KEY,
    id_cliente   INT           NOT NULL CONSTRAINT FK_Ventas_Clientes REFERENCES dbo.Clientes (id_cliente),
    fecha_venta  DATETIME2(0)  NOT NULL CONSTRAINT DF_Ventas_fecha DEFAULT (SYSDATETIME()),
    total        DECIMAL(10,2) NOT NULL DEFAULT (0)
);
CREATE TABLE dbo.Detalle_Ventas (
    id_detalle      INT IDENTITY(1,1) CONSTRAINT PK_Detalle_Ventas PRIMARY KEY,
    id_venta        INT           NOT NULL CONSTRAINT FK_Detalle_Ventas  REFERENCES dbo.Ventas (id_venta),
    id_producto     INT           NOT NULL CONSTRAINT FK_Detalle_Producto REFERENCES dbo.Productos (id_producto),
    cantidad        INT           NOT NULL CONSTRAINT CK_Detalle_cantidad CHECK (cantidad > 0),
    precio_unitario DECIMAL(10,2) NOT NULL
);
GO

INSERT INTO dbo.Clientes (cedula, nombre, telefono, correo) VALUES
    ('0601111111', N'Andrea Guamán',    '0991111111', 'andrea.guaman@correo.ec'),
    ('0602222222', N'Bryan Cajamarca',  '0992222222', 'bryan.cajamarca@correo.ec'),
    ('0603333333', N'Camila Yánez',     '0993333333', 'camila.yanez@correo.ec'),
    ('0604444444', N'Diego Paucar',     '0994444444', 'diego.paucar@correo.ec'),
    ('0605555555', N'Elena Villagómez', '0995555555', 'elena.villagomez@correo.ec'),
    ('0606666666', N'Fernando Lema',    '0996666666', 'fernando.lema@correo.ec');

INSERT INTO dbo.Productos (nombre, laboratorio, precio, stock) VALUES
    (N'Paracetamol 500 mg x 20',   N'Genfar',     2.50, 300),
    (N'Ibuprofeno 400 mg x 10',    N'MK',         3.20, 250),
    (N'Amoxicilina 500 mg x 21',   N'Bagó',       8.90, 120),
    (N'Loratadina 10 mg x 10',     N'La Santé',   4.10, 180),
    (N'Omeprazol 20 mg x 14',      N'Genfar',     6.75, 150),
    (N'Suero oral 500 ml',         N'Pedialyte',  3.60, 200),
    (N'Vitamina C 1 g x 10',       N'Redoxon',    5.40, 160),
    (N'Alcohol antiséptico 1 L',   N'Weir',       4.95,  90);

INSERT INTO dbo.Ventas (id_cliente, fecha_venta) VALUES
    (1, '2026-11-10 09:15'), (2, '2026-11-10 11:40'), (3, '2026-11-11 16:05'),
    (4, '2026-11-12 10:20'), (1, '2026-11-13 18:30'), (5, '2026-11-14 12:10');

INSERT INTO dbo.Detalle_Ventas (id_venta, id_producto, cantidad, precio_unitario) VALUES
    (1, 1, 2, 2.50), (1, 4, 1, 4.10),
    (2, 3, 1, 8.90), (2, 6, 3, 3.60),
    (3, 2, 2, 3.20), (3, 7, 1, 5.40),
    (4, 5, 1, 6.75), (4, 1, 1, 2.50), (4, 8, 1, 4.95),
    (5, 3, 2, 8.90),
    (6, 6, 2, 3.60), (6, 2, 1, 3.20);

UPDATE v SET total = d.total
FROM dbo.Ventas AS v
JOIN (SELECT id_venta, SUM(cantidad * precio_unitario) AS total
      FROM dbo.Detalle_Ventas GROUP BY id_venta) AS d ON d.id_venta = v.id_venta;
GO

-- Configuración resultante del log
SELECT name AS Archivo, type_desc AS Tipo,
       size * 8 / 1024 AS Tamano_MB,
       CASE WHEN is_percent_growth = 1 THEN CONCAT(growth, ' %')
            ELSE CONCAT(growth * 8 / 1024, ' MB') END AS Crecimiento
FROM sys.database_files;

SELECT d.name AS Base, d.recovery_model_desc AS Modelo_Recuperacion,
       d.log_reuse_wait_desc AS Espera_Reutilizacion_Log,
       (SELECT COUNT(*) FROM sys.dm_db_log_info(DB_ID())) AS VLF
FROM sys.databases AS d WHERE d.name = N'FarmaciaDB';
GO

-- 1.2 Respaldo completo: inicia la cadena del log --------------------------
-- Sin este respaldo, una base en modo FULL se comporta como SIMPLE
-- (pseudo-simple) y el log se trunca solo.
USE master;
DECLARE @dir NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400)) + N'\FarmaciaDB';
EXEC master.dbo.xp_create_subdir @dir;
DECLARE @f NVARCHAR(400) = @dir + N'\FDB_00_Full.bak';
BACKUP DATABASE FarmaciaDB TO DISK = @f
    WITH INIT, CHECKSUM, COMPRESSION, STATS = 25, NAME = N'FarmaciaDB - Completo';
GO

-- 1.3 Operaciones DML que quedan registradas en el log ---------------------
USE FarmaciaDB;
GO
BEGIN TRANSACTION OperacionesDelDia;
    INSERT INTO dbo.Clientes (cedula, nombre, telefono, correo)
    VALUES ('0607777777', N'Gabriela Ortiz', '0997777777', 'gabriela.ortiz@correo.ec');   -- INSERT

    UPDATE dbo.Productos SET precio = 9.50 WHERE id_producto = 3;                          -- UPDATE

    DELETE FROM dbo.Clientes WHERE id_cliente = 6;                                         -- DELETE (cliente sin ventas)
COMMIT TRANSACTION OperacionesDelDia;
GO

-- Lectura del log activo con fn_dblog: cada operación DML queda como un
-- registro con su LSN, su transacción y la tabla afectada.
SELECT [Current LSN], [Transaction ID], Operation, AllocUnitName AS Tabla_Indice,
       [Transaction Name], [Begin Time]
FROM fn_dblog(NULL, NULL)
WHERE [Transaction ID] IN (SELECT [Transaction ID] FROM fn_dblog(NULL, NULL)
                           WHERE [Transaction Name] = N'OperacionesDelDia')
  AND (Operation IN ('LOP_BEGIN_XACT', 'LOP_COMMIT_XACT')
       OR AllocUnitName LIKE 'dbo.%')
ORDER BY [Current LSN];
GO

-- 1.4 UNDO: un error dentro de una transacción se deshace con el log ------
-- El identificador de la transacción se guarda en una variable de tabla,
-- porque las variables de tabla no se ven afectadas por el ROLLBACK.
USE FarmaciaDB;
GO
DECLARE @tran TABLE (id_tran NVARCHAR(20));

BEGIN TRANSACTION ErrorDePrecios;
    UPDATE dbo.Productos SET precio = 0.01;          -- error: todos los precios en 0,01

    SELECT TOP (3) id_producto, nombre, precio AS Precio_Durante_El_Error
    FROM dbo.Productos ORDER BY id_producto;

    INSERT INTO @tran SELECT DISTINCT [Transaction ID]
    FROM fn_dblog(NULL, NULL) WHERE [Transaction Name] = N'ErrorDePrecios';
ROLLBACK TRANSACTION ErrorDePrecios;                  -- UNDO

SELECT TOP (3) id_producto, nombre, precio AS Precio_Tras_ROLLBACK
FROM dbo.Productos ORDER BY id_producto;

-- El log muestra las 8 modificaciones originales, las 8 compensaciones
-- (registros de UNDO) y el aborto de la transacción.
SELECT Operation AS Operacion,
       CASE WHEN Description LIKE '%COMPENSATION%' THEN N'Compensación (UNDO)'
            WHEN Operation = 'LOP_MODIFY_ROW'     THEN N'Cambio original'
            ELSE N'' END AS Tipo_Registro,
       COUNT(*) AS Registros, MIN([Current LSN]) AS Primer_LSN
FROM fn_dblog(NULL, NULL)
WHERE [Transaction ID] = (SELECT id_tran FROM @tran)
GROUP BY Operation, CASE WHEN Description LIKE '%COMPENSATION%' THEN N'Compensación (UNDO)'
                         WHEN Operation = 'LOP_MODIFY_ROW'     THEN N'Cambio original'
                         ELSE N'' END
ORDER BY Primer_LSN;
GO

-- 1.5 Antes del REDO: venta confirmada en esta sesión -----------------------
-- (Después de este bloque, ejecutar el bloque B1 en la segunda pestaña.)
USE FarmaciaDB;
GO
BEGIN TRANSACTION VentaConfirmada;
    INSERT INTO dbo.Ventas (id_cliente, total) VALUES (3, 17.80);
    INSERT INTO dbo.Detalle_Ventas (id_venta, id_producto, cantidad, precio_unitario)
    VALUES (SCOPE_IDENTITY(), 3, 2, 8.90);
COMMIT TRANSACTION VentaConfirmada;
SELECT MAX(id_venta) AS Venta_Confirmada, @@TRANCOUNT AS Transacciones_Abiertas FROM dbo.Ventas;
GO

-- 1.6 REDO y UNDO en una restauración real ------------------------------------
-- (Con la transacción de la sesión B todavía ABIERTA.)
-- El respaldo de log contiene una transacción confirmada (VentaConfirmada)
-- y una sin confirmar (VentaEnCurso, de la sesión B).
USE master;
DECLARE @d NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400)) + N'\FarmaciaDB\';
DECLARE @f NVARCHAR(400) = @d + N'FDB_01_Log.trn';
BACKUP LOG FarmaciaDB TO DISK = @f
    WITH INIT, CHECKSUM, COMPRESSION, STATS = 50, NAME = N'FarmaciaDB - Log 1';
GO

USE master;
DECLARE @d    NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400)) + N'\FarmaciaDB\';
DECLARE @data NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultDataPath')   AS NVARCHAR(400)) + N'FarmaciaDB_Redo.mdf';
DECLARE @log  NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultLogPath')    AS NVARCHAR(400)) + N'FarmaciaDB_Redo_log.ldf';
DECLARE @full NVARCHAR(400) = @d + N'FDB_00_Full.bak', @l1 NVARCHAR(400) = @d + N'FDB_01_Log.trn';

RESTORE DATABASE FarmaciaDB_Redo FROM DISK = @full
    WITH MOVE N'FarmaciaDB' TO @data, MOVE N'FarmaciaDB_log' TO @log, NORECOVERY, REPLACE;
RESTORE LOG FarmaciaDB_Redo FROM DISK = @l1 WITH RECOVERY;   -- REDO de lo confirmado + UNDO de lo pendiente

-- Mensajes de recuperación que SQL Server escribe en su registro de errores
EXEC master.dbo.xp_readerrorlog 0, 1, N'FarmaciaDB_Redo', N'rolled';
GO

-- Verificación: la venta confirmada está; la venta en curso de B, no.
SELECT N'FarmaciaDB_Redo' AS Base, v.id_venta, c.nombre, v.total
FROM FarmaciaDB_Redo.dbo.Ventas AS v
JOIN FarmaciaDB_Redo.dbo.Clientes AS c ON c.id_cliente = v.id_cliente
WHERE v.id_venta >= 7
ORDER BY v.id_venta;
GO
-- (Ahora ejecutar el bloque B2 en la segunda pestaña.)


/* =====================================================================
   SECCIÓN 2 · LOG SHIPPING (método DRP 1)
   Escenario: el servidor principal puede sufrir un fallo de disco.
   Se mantiene una base secundaria en espera (STANDBY, solo lectura) que
   recibe cada respaldo de log del principal.
   ===================================================================== */

-- 2.1 Inicializar la secundaria con el completo y el log 1 ----------------
USE master;
DECLARE @d    NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400)) + N'\FarmaciaDB\';
DECLARE @data NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultDataPath')   AS NVARCHAR(400)) + N'FarmaciaDB_Secundaria.mdf';
DECLARE @log  NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultLogPath')    AS NVARCHAR(400)) + N'FarmaciaDB_Secundaria_log.ldf';
DECLARE @tuf  NVARCHAR(400) = @d + N'FarmaciaDB_Secundaria_undo.tuf';
DECLARE @full NVARCHAR(400) = @d + N'FDB_00_Full.bak', @l1 NVARCHAR(400) = @d + N'FDB_01_Log.trn';

RESTORE DATABASE FarmaciaDB_Secundaria FROM DISK = @full
    WITH MOVE N'FarmaciaDB' TO @data, MOVE N'FarmaciaDB_log' TO @log, STANDBY = @tuf, REPLACE;
RESTORE LOG FarmaciaDB_Secundaria FROM DISK = @l1 WITH STANDBY = @tuf;

SELECT name AS Base, state_desc AS Estado, is_in_standby AS En_Espera, is_read_only AS Solo_Lectura
FROM sys.databases WHERE name IN (N'FarmaciaDB', N'FarmaciaDB_Secundaria');
GO

-- 2.2 Ciclo de log shipping: nuevas ventas → BACKUP LOG → RESTORE LOG --------
USE FarmaciaDB;
INSERT INTO dbo.Ventas (id_cliente, total) VALUES (2, 6.40);
INSERT INTO dbo.Detalle_Ventas (id_venta, id_producto, cantidad, precio_unitario) VALUES (SCOPE_IDENTITY(), 2, 2, 3.20);
INSERT INTO dbo.Ventas (id_cliente, total) VALUES (5, 10.80);
INSERT INTO dbo.Detalle_Ventas (id_venta, id_producto, cantidad, precio_unitario) VALUES (SCOPE_IDENTITY(), 7, 2, 5.40);
GO
USE master;
DECLARE @d   NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400)) + N'\FarmaciaDB\';
DECLARE @tuf NVARCHAR(400) = @d + N'FarmaciaDB_Secundaria_undo.tuf', @l2 NVARCHAR(400) = @d + N'FDB_02_Log.trn';
BACKUP LOG FarmaciaDB TO DISK = @l2 WITH INIT, CHECKSUM, COMPRESSION, NAME = N'FarmaciaDB - Log 2';
RESTORE LOG FarmaciaDB_Secundaria FROM DISK = @l2 WITH STANDBY = @tuf;

SELECT N'Principal' AS Base, COUNT(*) AS Ventas, SUM(total) AS Total_USD FROM FarmaciaDB.dbo.Ventas
UNION ALL
SELECT N'Secundaria (STANDBY)', COUNT(*), SUM(total) FROM FarmaciaDB_Secundaria.dbo.Ventas;
GO

-- 2.3 La secundaria es de solo lectura mientras está en espera (STANDBY):
--     un intento de escritura falla con el error 3906
INSERT INTO FarmaciaDB_Secundaria.dbo.Clientes (cedula, nombre) VALUES ('0609999999', N'Prueba');
GO
-- Pero sí puede consultarse (útil para reportes)
SELECT TOP (3) id_venta, id_cliente, total FROM FarmaciaDB_Secundaria.dbo.Ventas ORDER BY id_venta DESC;
GO


/* =====================================================================
   SECCIÓN 3 · CASO PRÁCTICO: PÉRDIDA PARCIAL DE DATOS Y PITR (STOPAT)
   Un auxiliar quiere borrar el detalle de UNA venta anulada (la 2) y
   olvida parte del filtro: borra el detalle de todas las ventas del
   10 al 12 de noviembre.
   ===================================================================== */

-- 3.1 Estado previo, error y búsqueda forense del instante exacto en el log
USE FarmaciaDB;
GO
SELECT COUNT(*) AS Detalles_Antes_Del_Error FROM dbo.Detalle_Ventas;

WAITFOR DELAY '00:00:02';

DELETE d FROM dbo.Detalle_Ventas AS d
JOIN dbo.Ventas AS v ON v.id_venta = d.id_venta
WHERE v.fecha_venta < '2026-11-13';                         -- ¡error del auxiliar!

SELECT COUNT(*) AS Detalles_Despues_Del_Error FROM dbo.Detalle_Ventas;

-- Hallar en el log la transacción DELETE y su hora de inicio
IF OBJECT_ID('tempdb..##PuntoFalla') IS NOT NULL DROP TABLE ##PuntoFalla;
SELECT TOP (1) b.[Transaction ID]            AS id_tran,
       b.[Begin Time]                        AS inicio_texto,
       CONVERT(DATETIME, STUFF(REPLACE(b.[Begin Time], '/', '-'), 20, 1, '.'), 121) AS inicio_delete,
       (SELECT COUNT(*) FROM fn_dblog(NULL, NULL) AS r
        WHERE r.[Transaction ID] = b.[Transaction ID]
          AND r.Operation = 'LOP_DELETE_ROWS'
          AND r.AllocUnitName = 'dbo.Detalle_Ventas.PK_Detalle_Ventas') AS filas_borradas
INTO ##PuntoFalla
FROM fn_dblog(NULL, NULL) AS b
WHERE b.Operation = 'LOP_BEGIN_XACT' AND b.[Transaction Name] = N'DELETE'
ORDER BY b.[Current LSN] DESC;

SELECT id_tran AS Transaccion, inicio_texto AS Begin_Time_En_El_Log,
       inicio_delete AS Inicio_DELETE, filas_borradas AS Filas_Borradas
FROM ##PuntoFalla;
GO

-- 3.2 El log shipping replica el error en la secundaria --------------------
USE master;
DECLARE @d   NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400)) + N'\FarmaciaDB\';
DECLARE @tuf NVARCHAR(400) = @d + N'FarmaciaDB_Secundaria_undo.tuf', @l3 NVARCHAR(400) = @d + N'FDB_03_Log.trn';
BACKUP LOG FarmaciaDB TO DISK = @l3 WITH INIT, CHECKSUM, COMPRESSION, NAME = N'FarmaciaDB - Log 3';
RESTORE LOG FarmaciaDB_Secundaria FROM DISK = @l3 WITH STANDBY = @tuf;

SELECT N'Principal' AS Base, COUNT(*) AS Detalles FROM FarmaciaDB.dbo.Detalle_Ventas
UNION ALL
SELECT N'Secundaria (log shipping)', COUNT(*) FROM FarmaciaDB_Secundaria.dbo.Detalle_Ventas;
GO

-- 3.3 PITR: restaurar en una base aparte hasta un instante antes del DELETE
USE master;
DECLARE @d    NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400)) + N'\FarmaciaDB\';
DECLARE @data NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultDataPath')   AS NVARCHAR(400)) + N'FarmaciaDB_PITR.mdf';
DECLARE @log  NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultLogPath')    AS NVARCHAR(400)) + N'FarmaciaDB_PITR_log.ldf';
DECLARE @full NVARCHAR(400) = @d + N'FDB_00_Full.bak',
        @l1   NVARCHAR(400) = @d + N'FDB_01_Log.trn',
        @l2   NVARCHAR(400) = @d + N'FDB_02_Log.trn',
        @l3   NVARCHAR(400) = @d + N'FDB_03_Log.trn';
DECLARE @stopat DATETIME  = (SELECT DATEADD(MILLISECOND, -10, inicio_delete) FROM ##PuntoFalla);
DECLARE @inicio DATETIME2 = SYSDATETIME();

RESTORE DATABASE FarmaciaDB_PITR FROM DISK = @full
    WITH MOVE N'FarmaciaDB' TO @data, MOVE N'FarmaciaDB_log' TO @log, NORECOVERY, REPLACE;
RESTORE LOG FarmaciaDB_PITR FROM DISK = @l1 WITH NORECOVERY;
RESTORE LOG FarmaciaDB_PITR FROM DISK = @l2 WITH NORECOVERY;
RESTORE LOG FarmaciaDB_PITR FROM DISK = @l3 WITH STOPAT = @stopat, RECOVERY;

SELECT @stopat AS Restaurado_Hasta,
       DATEDIFF(MILLISECOND, @inicio, SYSDATETIME()) AS Duracion_ms;
GO

-- 3.4 Hallazgos y reparación controlada en producción ------------------------
SELECT N'Producción (con el error)' AS Base, COUNT(*) AS Detalles FROM FarmaciaDB.dbo.Detalle_Ventas
UNION ALL
SELECT N'Copia PITR (STOPAT)', COUNT(*) FROM FarmaciaDB_PITR.dbo.Detalle_Ventas;

-- Filas que se recuperan
SELECT r.id_detalle, r.id_venta, p.nombre AS Producto, r.cantidad, r.precio_unitario
FROM FarmaciaDB_PITR.dbo.Detalle_Ventas AS r
JOIN FarmaciaDB_PITR.dbo.Productos AS p ON p.id_producto = r.id_producto
WHERE NOT EXISTS (SELECT 1 FROM FarmaciaDB.dbo.Detalle_Ventas AS x WHERE x.id_detalle = r.id_detalle)
ORDER BY r.id_detalle;

SET IDENTITY_INSERT FarmaciaDB.dbo.Detalle_Ventas ON;
INSERT INTO FarmaciaDB.dbo.Detalle_Ventas (id_detalle, id_venta, id_producto, cantidad, precio_unitario)
SELECT r.id_detalle, r.id_venta, r.id_producto, r.cantidad, r.precio_unitario
FROM FarmaciaDB_PITR.dbo.Detalle_Ventas AS r
WHERE NOT EXISTS (SELECT 1 FROM FarmaciaDB.dbo.Detalle_Ventas AS p WHERE p.id_detalle = r.id_detalle);
SET IDENTITY_INSERT FarmaciaDB.dbo.Detalle_Ventas OFF;

SELECT N'Producción reparada' AS Base, COUNT(*) AS Detalles FROM FarmaciaDB.dbo.Detalle_Ventas;
GO


/* =====================================================================
   SECCIÓN 4 · DESASTRE DEL SERVIDOR PRINCIPAL Y CONMUTACIÓN (FAILOVER)
   Escenario: el disco de datos del principal falla. El disco del log
   sigue accesible, así que se respalda la cola del log y la secundaria
   asume el rol de principal.
   ===================================================================== */

-- 4.1 Última venta antes del fallo y envío de la reparación a la secundaria
USE FarmaciaDB;
INSERT INTO dbo.Ventas (id_cliente, total) VALUES (4, 4.95);
INSERT INTO dbo.Detalle_Ventas (id_venta, id_producto, cantidad, precio_unitario)
VALUES (SCOPE_IDENTITY(), 8, 1, 4.95);
SELECT COUNT(*) AS Ventas_Principal, (SELECT COUNT(*) FROM dbo.Detalle_Ventas) AS Detalles_Principal
FROM dbo.Ventas;
GO

-- 4.2 Fallo y conmutación ------------------------------------------------------
USE master;
-- Sesiones que todavía usan la base principal (sin este paso el respaldo de
-- la cola falla con el error 3101: la base está en uso)
SELECT session_id, program_name, status
FROM sys.dm_exec_sessions WHERE database_id = DB_ID(N'FarmaciaDB');

-- Se cierran las conexiones, como se haría ante la caída del servidor.
ALTER DATABASE FarmaciaDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO

USE master;
DECLARE @d    NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400)) + N'\FarmaciaDB\';
DECLARE @tail NVARCHAR(400) = @d + N'FDB_04_Cola_Log.trn';
DECLARE @inicio DATETIME2 = SYSDATETIME();

-- a) Respaldo de la cola del log: rescata las transacciones posteriores
--    al último log. NORECOVERY deja al principal fuera de servicio
--    (estado RESTORING), igual que si el servidor hubiera caído.
BACKUP LOG FarmaciaDB TO DISK = @tail WITH INIT, NO_TRUNCATE, NORECOVERY, CHECKSUM, NAME = N'FarmaciaDB - Cola del log';

-- b) La secundaria aplica la cola y se recupera: pasa a ser la principal.
RESTORE LOG FarmaciaDB_Secundaria FROM DISK = @tail WITH RECOVERY;

SELECT DATEDIFF(MILLISECOND, @inicio, SYSDATETIME()) AS Duracion_Conmutacion_ms;
SELECT name AS Base, state_desc AS Estado, is_in_standby AS En_Espera, is_read_only AS Solo_Lectura
FROM sys.databases WHERE name IN (N'FarmaciaDB', N'FarmaciaDB_Secundaria');
GO

-- 4.3 La nueva principal tiene todos los datos (incluida la última venta,
--     rescatada con la cola del log) y acepta escrituras -----------------
USE FarmaciaDB_Secundaria;
SELECT COUNT(*) AS Ventas, (SELECT COUNT(*) FROM dbo.Detalle_Ventas) AS Detalles,
       (SELECT TOP (1) CONCAT('Venta ', id_venta, ' · USD ', total) FROM dbo.Ventas ORDER BY id_venta DESC) AS Ultima_Venta
FROM dbo.Ventas;

INSERT INTO dbo.Clientes (cedula, nombre) VALUES ('0608888888', N'Hugo Salazar');
SELECT TOP (1) id_cliente, nombre, N'Escritura aceptada en la nueva principal' AS Resultado
FROM dbo.Clientes ORDER BY id_cliente DESC;
GO

-- 4.4 Historial completo de respaldos y restauraciones (msdb) ----------------
SELECT b.backup_start_date AS Inicio,
       CASE b.type WHEN 'D' THEN 'Completo' WHEN 'L' THEN 'Log' END AS Tipo,
       b.name AS Nombre,
       CAST(b.compressed_backup_size / 1024.0 AS DECIMAL(10,1)) AS KB,
       b.first_lsn AS Primer_LSN, b.last_lsn AS Ultimo_LSN
FROM msdb.dbo.backupset AS b
WHERE b.database_name = N'FarmaciaDB'
ORDER BY b.backup_start_date;
GO
