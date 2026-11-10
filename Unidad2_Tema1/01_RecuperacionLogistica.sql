/* =====================================================================
   ADMINISTRACIÓN DE BASES DE DATOS · Unidad 2 · Tema 1
   Fundamentos de recuperación: consistencia, concurrencia, respaldos
   y plan de recuperación para la base RecuperacionLogistica
   ---------------------------------------------------------------------
   Motor  : Microsoft SQL Server 2019 o superior (T-SQL)
   Autor  : Lenin Vladimir Peñafiel Buestán
   ---------------------------------------------------------------------
   ARCHIVOS
     01_RecuperacionLogistica.sql  (este)  Secciones 1, 2, 4 y 5
     02_Operador_A.sql                     Sección 3 · ventana del operador A
     03_Operador_B.sql                     Sección 3 · ventana del operador B

   ORDEN DE EJECUCIÓN
     1. Secciones 1 y 2 de este archivo.
     2. Sección 3: abrir 02 y 03 en DOS pestañas de SSMS y ejecutar los
        pasos alternando A → B → A ... según la numeración.
     3. Secciones 4 y 5 de este archivo, bloque por bloque.
   ===================================================================== */


/* =====================================================================
   SECCIÓN 1 · CREACIÓN DE LA BASE DE DATOS DE PRUEBA
   ===================================================================== */
USE master;
GO

IF DB_ID(N'RecuperacionLogistica_Prueba') IS NOT NULL
BEGIN
    ALTER DATABASE RecuperacionLogistica_Prueba SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE RecuperacionLogistica_Prueba;
END
IF DB_ID(N'RecuperacionLogistica') IS NOT NULL
BEGIN
    ALTER DATABASE RecuperacionLogistica SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE RecuperacionLogistica;
END
GO

CREATE DATABASE RecuperacionLogistica;
GO

-- Modelo de recuperación COMPLETO: imprescindible para respaldar el log
-- de transacciones y restaurar a un punto en el tiempo (sección 4).
ALTER DATABASE RecuperacionLogistica SET RECOVERY FULL;
-- Bloqueo clásico (sin versionado) para que la sección 3 muestre los
-- efectos de cada nivel de aislamiento tal como los define el estándar.
ALTER DATABASE RecuperacionLogistica SET READ_COMMITTED_SNAPSHOT OFF;
ALTER DATABASE RecuperacionLogistica SET ALLOW_SNAPSHOT_ISOLATION OFF;
GO

USE RecuperacionLogistica;
GO

CREATE TABLE dbo.Sucursales (
    id_sucursal       INT IDENTITY(1,1) NOT NULL,
    nombre_ciudad     NVARCHAR(60)      NOT NULL,
    capacidad_maxima  INT               NOT NULL,      -- número máximo de paquetes en bodega
    CONSTRAINT PK_Sucursales           PRIMARY KEY (id_sucursal),
    CONSTRAINT UQ_Sucursales_ciudad    UNIQUE (nombre_ciudad),
    CONSTRAINT CK_Sucursales_capacidad CHECK (capacidad_maxima > 0)
);

CREATE TABLE dbo.Paquetes (
    id_paquete    INT IDENTITY(1,1) NOT NULL,
    descripcion   NVARCHAR(120)     NOT NULL,
    peso          DECIMAL(8,2)      NOT NULL,          -- kilogramos
    costo_envio   DECIMAL(10,2)     NOT NULL,          -- dólares
    id_sucursal   INT               NOT NULL,
    fecha_envio   DATE              NOT NULL CONSTRAINT DF_Paquetes_fecha  DEFAULT (CAST(SYSDATETIME() AS DATE)),
    estado        VARCHAR(12)       NOT NULL CONSTRAINT DF_Paquetes_estado DEFAULT ('REGISTRADO'),
    CONSTRAINT PK_Paquetes            PRIMARY KEY (id_paquete),
    CONSTRAINT FK_Paquetes_Sucursales FOREIGN KEY (id_sucursal) REFERENCES dbo.Sucursales (id_sucursal),
    CONSTRAINT CK_Paquetes_peso       CHECK (peso > 0),
    CONSTRAINT CK_Paquetes_costo      CHECK (costo_envio > 0),
    CONSTRAINT CK_Paquetes_estado     CHECK (estado IN ('REGISTRADO', 'EN_TRANSITO', 'ENTREGADO', 'DEVUELTO'))
);

-- Índice de apoyo a la clave foránea y a los reportes por sucursal y fecha.
CREATE NONCLUSTERED INDEX IX_Paquetes_Sucursal_Fecha
    ON dbo.Paquetes (id_sucursal, fecha_envio) INCLUDE (costo_envio, estado);
GO


/* =====================================================================
   SECCIÓN 2 · ESTRATEGIAS DE CONSISTENCIA
   Reglas de una sola fila  → CHECK (peso > 0, costo > 0, estado válido)
   Sucursal inexistente     → FOREIGN KEY
   Regla entre varias filas → TRIGGER (capacidad máxima de la sucursal):
   un CHECK solo ve la fila que se inserta; no puede contar cuántos
   paquetes tiene ya la sucursal.
   ===================================================================== */
CREATE OR ALTER TRIGGER dbo.tr_ValidarCapacidadSucursal
ON dbo.Paquetes
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Solo importa cuando se agregan paquetes o se cambian de sucursal.
    IF NOT UPDATE(id_sucursal) RETURN;

    DECLARE @detalle NVARCHAR(1000);

    SELECT @detalle = STRING_AGG(CONCAT(s.nombre_ciudad, N' (', c.total, N' de ', s.capacidad_maxima, N')'), N', ')
    FROM dbo.Sucursales AS s
    INNER JOIN (SELECT p.id_sucursal, COUNT(*) AS total
                FROM dbo.Paquetes AS p
                WHERE p.id_sucursal IN (SELECT id_sucursal FROM inserted)
                GROUP BY p.id_sucursal) AS c
            ON c.id_sucursal = s.id_sucursal
    WHERE c.total > s.capacidad_maxima;

    IF @detalle IS NOT NULL
    BEGIN
        DECLARE @mensaje NVARCHAR(2048) =
            CONCAT(N'Capacidad máxima superada en la sucursal: ', @detalle, N'. La operación se revierte.');
        THROW 50001, @mensaje, 1;   -- THROW en un trigger revierte toda la transacción
    END
END;
GO

-- 2.1 Datos válidos -------------------------------------------------------
INSERT INTO dbo.Sucursales (nombre_ciudad, capacidad_maxima) VALUES
    (N'Riobamba',  40),
    (N'Quito',     60),
    (N'Guayaquil', 60),
    (N'Cuenca',     3),   -- capacidad pequeña para probar el trigger
    (N'Ambato',    30);

INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal, fecha_envio, estado) VALUES
    (N'Laptop Lenovo IdeaPad',          2.10, 12.50, 1, '2026-10-26', 'ENTREGADO'),
    (N'Licuadora Oster',                3.40,  9.80, 1, '2026-10-28', 'ENTREGADO'),
    (N'Caja de libros universitarios',  8.75, 18.00, 2, '2026-10-29', 'ENTREGADO'),
    (N'Teléfono Samsung A55',           0.45,  6.25, 2, '2026-11-02', 'EN_TRANSITO'),
    (N'Monitor LG 27 pulgadas',         5.90, 15.40, 2, '2026-11-03', 'EN_TRANSITO'),
    (N'Zapatos deportivos',             1.20,  5.75, 2, '2026-11-05', 'REGISTRADO'),
    (N'Impresora Epson L3250',          4.80, 14.20, 3, '2026-10-30', 'ENTREGADO'),
    (N'Juego de ollas',                 6.30, 13.10, 3, '2026-11-04', 'EN_TRANSITO'),
    (N'Audífonos Sony',                 0.35,  4.90, 4, '2026-11-01', 'ENTREGADO'),
    (N'Cafetera Nespresso',             3.10, 11.30, 4, '2026-11-06', 'REGISTRADO'),
    (N'Bicicleta plegable',            14.50, 32.00, 5, '2026-11-02', 'EN_TRANSITO'),
    (N'Kit de herramientas',            7.20, 16.80, 5, '2026-11-07', 'REGISTRADO');
GO

-- 2.2 Inserción válida que llena la capacidad de Cuenca (2 → 3 de 3) --------
INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal)
VALUES (N'Tablet Huawei MatePad', 0.60, 7.40, 4);

SELECT s.nombre_ciudad, s.capacidad_maxima, COUNT(p.id_paquete) AS paquetes_actuales
FROM dbo.Sucursales AS s
LEFT JOIN dbo.Paquetes AS p ON p.id_sucursal = s.id_sucursal
GROUP BY s.nombre_ciudad, s.capacidad_maxima
ORDER BY s.nombre_ciudad;
GO

-- Catálogo: restricciones de integridad y trigger creados
SELECT OBJECT_NAME(parent_object_id) AS Tabla, name AS Restriccion, type_desc AS Tipo
FROM sys.objects
WHERE type IN ('PK', 'F', 'UQ', 'C', 'TR') AND is_ms_shipped = 0
ORDER BY Tabla, Tipo;

SELECT name AS Restriccion_CHECK, definition AS Regla
FROM sys.check_constraints
ORDER BY name;
GO

-- 2.3 Datos inválidos: el motor bloquea cada intento -----------------------
-- a) Peso negativo → CHECK CK_Paquetes_peso (error 547)
INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal)
VALUES (N'Paquete con peso negativo', -2.00, 10.00, 1);
GO
-- b) Peso cero → CHECK CK_Paquetes_peso (error 547)
INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal)
VALUES (N'Paquete con peso cero', 0.00, 10.00, 1);
GO
-- c) Costo de envío cero → CHECK CK_Paquetes_costo (error 547)
INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal)
VALUES (N'Paquete sin costo', 1.00, 0.00, 1);
GO
-- d) Sucursal inexistente → FOREIGN KEY FK_Paquetes_Sucursales (error 547)
INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal)
VALUES (N'Paquete hacia sucursal 99', 1.00, 10.00, 99);
GO
-- e) Cuenca ya está llena (3 de 3) → TRIGGER tr_ValidarCapacidadSucursal (error 50001)
INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal)
VALUES (N'Paquete que excede la capacidad', 1.00, 10.00, 4);
GO
-- f) Actualizar un costo a un valor negativo → CHECK (error 547)
UPDATE dbo.Paquetes SET costo_envio = -5.00 WHERE id_paquete = 1;
GO
-- g) Eliminar una sucursal que tiene paquetes → FOREIGN KEY (error 547)
DELETE FROM dbo.Sucursales WHERE id_sucursal = 1;
GO

-- 2.4 Atomicidad de una transacción con una fila inválida ------------------
-- Tres paquetes en una sola transacción; el tercero tiene costo negativo.
-- XACT_ABORT revierte también los dos primeros: no queda nada a medias.
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
        INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal) VALUES (N'Lote A - Caja 1', 2.00, 8.00, 2);
        INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal) VALUES (N'Lote A - Caja 2', 2.50, 8.50, 2);
        INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal) VALUES (N'Lote A - Caja 3', 3.00, -1.00, 2);
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SELECT ERROR_NUMBER() AS Error, ERROR_MESSAGE() AS Mensaje, N'Transacción revertida completa' AS Resultado;
END CATCH;
SET XACT_ABORT OFF;

SELECT COUNT(*) AS Paquetes_Lote_A FROM dbo.Paquetes WHERE descripcion LIKE N'Lote A%';   -- 0
SELECT COUNT(*) AS Total_Paquetes   FROM dbo.Paquetes;                                    -- 13
GO


/* =====================================================================
   SECCIÓN 3 · CONTROL DE CONCURRENCIA
   Se ejecuta con los archivos 02_Operador_A.sql y 03_Operador_B.sql en
   dos pestañas de SSMS (dos sesiones distintas).
   Consulta auxiliar: bloqueos activos en la base (cualquier pestaña).
   ===================================================================== */
SELECT l.request_session_id AS Sesion,
       l.resource_type      AS Recurso,
       l.request_mode       AS Modo,
       l.request_status     AS Estado,
       OBJECT_NAME(p.object_id) AS Objeto,
       i.name               AS Indice
FROM sys.dm_tran_locks AS l
LEFT JOIN sys.partitions AS p ON p.hobt_id = l.resource_associated_entity_id
LEFT JOIN sys.indexes    AS i ON i.object_id = p.object_id AND i.index_id = p.index_id
WHERE l.resource_database_id = DB_ID(N'RecuperacionLogistica')
  AND l.resource_type <> 'DATABASE'
ORDER BY l.request_session_id, l.resource_type;
GO


/* =====================================================================
   SECCIÓN 4 · COPIAS DE SEGURIDAD (Full, Diferencial y Log)
   Los archivos se guardan en la carpeta de respaldos predeterminada de
   la instancia, dentro de la subcarpeta RecuperacionLogistica.
   CHECKSUM verifica cada página al escribirla; INIT reemplaza el archivo;
   COMPRESSION reduce el tamaño (disponible en las ediciones Developer,
   Standard y Enterprise).
   ===================================================================== */
USE master;
GO

-- 4.0 Carpeta de respaldos y verificación del modelo de recuperación ------
DECLARE @dir NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400)) + N'\RecuperacionLogistica';
EXEC master.dbo.xp_create_subdir @dir;

SELECT name AS Base, recovery_model_desc AS Modelo_Recuperacion, @dir AS Carpeta_Respaldos
FROM sys.databases WHERE name = N'RecuperacionLogistica';
GO

-- 4.1 Respaldo COMPLETO (Full): base de toda la cadena ---------------------
DECLARE @archivo NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400))
                               + N'\RecuperacionLogistica\RL_01_Full.bak';
BACKUP DATABASE RecuperacionLogistica
    TO DISK = @archivo
    WITH INIT, CHECKSUM, COMPRESSION, STATS = 25,
         NAME = N'RecuperacionLogistica - Respaldo completo semanal';
GO

-- Operaciones del día 1 (cambios después del Full)
USE RecuperacionLogistica;
INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal, estado) VALUES
    (N'Refrigeradora Indurama', 45.00, 48.00, 3, 'REGISTRADO'),
    (N'Colchón de 2 plazas',    22.00, 30.50, 2, 'REGISTRADO');
UPDATE dbo.Paquetes SET estado = 'ENTREGADO' WHERE id_paquete IN (4, 5);
SELECT COUNT(*) AS Total_Paquetes FROM dbo.Paquetes;   -- 15
GO

-- 4.2 Respaldo DIFERENCIAL: todo lo que cambió desde el último Full -------
USE master;
DECLARE @archivo NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400))
                               + N'\RecuperacionLogistica\RL_02_Diferencial.bak';
BACKUP DATABASE RecuperacionLogistica
    TO DISK = @archivo
    WITH DIFFERENTIAL, INIT, CHECKSUM, COMPRESSION, STATS = 25,
         NAME = N'RecuperacionLogistica - Respaldo diferencial diario';
GO

-- Operaciones posteriores al diferencial
USE RecuperacionLogistica;
INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal) VALUES
    (N'Televisor TCL 55 pulgadas', 18.00, 27.90, 1);
UPDATE dbo.Paquetes SET estado = 'EN_TRANSITO' WHERE id_paquete IN (6, 10, 12);
GO

-- 4.3 Respaldo del LOG DE TRANSACCIONES (equivalente incremental en SQL Server)
USE master;
DECLARE @archivo NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400))
                               + N'\RecuperacionLogistica\RL_03_Log_1.trn';
BACKUP LOG RecuperacionLogistica
    TO DISK = @archivo
    WITH INIT, CHECKSUM, COMPRESSION, STATS = 25,
         NAME = N'RecuperacionLogistica - Log 1';
GO

-- 4.4 Incidente simulado: borrado accidental -------------------------------
-- Se guarda la hora segura (antes del error) en una tabla temporal global
-- para usarla luego en la restauración a un punto en el tiempo.
USE RecuperacionLogistica;
INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal) VALUES
    (N'Repuestos de motocicleta', 9.40, 19.60, 5);           -- operación legítima

IF OBJECT_ID('tempdb..##PuntoSeguro') IS NOT NULL DROP TABLE ##PuntoSeguro;
WAITFOR DELAY '00:00:02';
SELECT CAST(SYSDATETIME() AS DATETIME) AS hora_segura INTO ##PuntoSeguro;
WAITFOR DELAY '00:00:02';

DELETE FROM dbo.Paquetes WHERE estado = 'ENTREGADO';         -- ¡error del operador!

SELECT hora_segura AS Hora_Segura_Antes_Del_Error,
       (SELECT COUNT(*) FROM dbo.Paquetes) AS Paquetes_Que_Quedan
FROM ##PuntoSeguro;
GO

-- Log 2: contiene la operación legítima y el borrado accidental
USE master;
DECLARE @archivo NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400))
                               + N'\RecuperacionLogistica\RL_04_Log_2.trn';
BACKUP LOG RecuperacionLogistica
    TO DISK = @archivo
    WITH INIT, CHECKSUM, COMPRESSION, STATS = 25,
         NAME = N'RecuperacionLogistica - Log 2';
GO

-- 4.5 Historial de la cadena de respaldos (msdb) ----------------------------
SELECT b.backup_start_date                          AS Inicio,
       CASE b.type WHEN 'D' THEN 'Completo' WHEN 'I' THEN 'Diferencial' WHEN 'L' THEN 'Log' END AS Tipo,
       CAST(b.backup_size / 1024.0 AS DECIMAL(10,1))            AS Tamano_KB,
       CAST(b.compressed_backup_size / 1024.0 AS DECIMAL(10,1)) AS Comprimido_KB,
       b.first_lsn                                  AS Primer_LSN,
       b.last_lsn                                   AS Ultimo_LSN,
       b.differential_base_lsn                      AS Base_Diferencial,
       RIGHT(m.physical_device_name, 22)            AS Archivo
FROM msdb.dbo.backupset AS b
INNER JOIN msdb.dbo.backupmediafamily AS m ON m.media_set_id = b.media_set_id
WHERE b.database_name = N'RecuperacionLogistica'
ORDER BY b.backup_start_date;
GO


/* =====================================================================
   SECCIÓN 5 · PLAN DE PRUEBAS DE RESTAURACIÓN
   La restauración se hace en una base NUEVA (RecuperacionLogistica_Prueba)
   con archivos físicos propios (WITH MOVE): producción no se toca.
   ===================================================================== */

-- 5.1 Verificar que cada archivo de respaldo es legible y está íntegro -----
DECLARE @d NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400)) + N'\RecuperacionLogistica\';
DECLARE @f1 NVARCHAR(400) = @d + N'RL_01_Full.bak',
        @f2 NVARCHAR(400) = @d + N'RL_02_Diferencial.bak',
        @f3 NVARCHAR(400) = @d + N'RL_03_Log_1.trn',
        @f4 NVARCHAR(400) = @d + N'RL_04_Log_2.trn';
RESTORE VERIFYONLY FROM DISK = @f1 WITH CHECKSUM;
RESTORE VERIFYONLY FROM DISK = @f2 WITH CHECKSUM;
RESTORE VERIFYONLY FROM DISK = @f3 WITH CHECKSUM;
RESTORE VERIFYONLY FROM DISK = @f4 WITH CHECKSUM;
GO

-- 5.2 Restauración completa a un punto en el tiempo, en la base de prueba --
DECLARE @d    NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400)) + N'\RecuperacionLogistica\';
DECLARE @data NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultDataPath')   AS NVARCHAR(400)) + N'RecuperacionLogistica_Prueba.mdf';
DECLARE @log  NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultLogPath')    AS NVARCHAR(400)) + N'RecuperacionLogistica_Prueba_log.ldf';
DECLARE @f1 NVARCHAR(400) = @d + N'RL_01_Full.bak',
        @f2 NVARCHAR(400) = @d + N'RL_02_Diferencial.bak',
        @f3 NVARCHAR(400) = @d + N'RL_03_Log_1.trn',
        @f4 NVARCHAR(400) = @d + N'RL_04_Log_2.trn';
DECLARE @punto DATETIME = (SELECT hora_segura FROM ##PuntoSeguro);
DECLARE @inicio DATETIME2 = SYSDATETIME();

RESTORE DATABASE RecuperacionLogistica_Prueba FROM DISK = @f1
    WITH MOVE N'RecuperacionLogistica'     TO @data,
         MOVE N'RecuperacionLogistica_log' TO @log,
         NORECOVERY, REPLACE, STATS = 50;                      -- 1) Full
RESTORE DATABASE RecuperacionLogistica_Prueba FROM DISK = @f2
    WITH NORECOVERY;                                           -- 2) Diferencial
RESTORE LOG RecuperacionLogistica_Prueba FROM DISK = @f3
    WITH NORECOVERY;                                           -- 3) Log 1
RESTORE LOG RecuperacionLogistica_Prueba FROM DISK = @f4
    WITH STOPAT = @punto, RECOVERY;                            -- 4) Log 2 hasta la hora segura

SELECT @punto AS Restaurado_Hasta,
       DATEDIFF(MILLISECOND, @inicio, SYSDATETIME()) AS Duracion_Restauracion_ms;
GO

-- 5.3 Hallazgos: producción frente a la copia restaurada --------------------
SELECT N'Producción (con el error)' AS Base, COUNT(*) AS Paquetes,
       SUM(CASE WHEN estado = 'ENTREGADO' THEN 1 ELSE 0 END) AS Entregados
FROM RecuperacionLogistica.dbo.Paquetes
UNION ALL
SELECT N'Copia restaurada (STOPAT)', COUNT(*),
       SUM(CASE WHEN estado = 'ENTREGADO' THEN 1 ELSE 0 END)
FROM RecuperacionLogistica_Prueba.dbo.Paquetes;

-- Paquetes que se recuperan gracias a la restauración
SELECT r.id_paquete, r.descripcion, r.estado, r.fecha_envio
FROM RecuperacionLogistica_Prueba.dbo.Paquetes AS r
WHERE NOT EXISTS (SELECT 1 FROM RecuperacionLogistica.dbo.Paquetes AS p
                  WHERE p.id_paquete = r.id_paquete)
ORDER BY r.id_paquete;

-- La operación legítima previa al error también está en la copia
SELECT id_paquete, descripcion, estado
FROM RecuperacionLogistica_Prueba.dbo.Paquetes
WHERE descripcion = N'Repuestos de motocicleta';
GO

-- 5.4 Integridad física y lógica de la copia restaurada --------------------
DBCC CHECKDB (N'RecuperacionLogistica_Prueba') WITH NO_INFOMSGS, ALL_ERRORMSGS;
SELECT N'DBCC CHECKDB sin errores en la copia restaurada' AS Resultado;
GO

-- 5.5 Reparación controlada: devolver a producción los paquetes borrados ----
SET IDENTITY_INSERT RecuperacionLogistica.dbo.Paquetes ON;
INSERT INTO RecuperacionLogistica.dbo.Paquetes
       (id_paquete, descripcion, peso, costo_envio, id_sucursal, fecha_envio, estado)
SELECT r.id_paquete, r.descripcion, r.peso, r.costo_envio, r.id_sucursal, r.fecha_envio, r.estado
FROM RecuperacionLogistica_Prueba.dbo.Paquetes AS r
WHERE NOT EXISTS (SELECT 1 FROM RecuperacionLogistica.dbo.Paquetes AS p
                  WHERE p.id_paquete = r.id_paquete);
SET IDENTITY_INSERT RecuperacionLogistica.dbo.Paquetes OFF;

SELECT COUNT(*) AS Paquetes_En_Produccion,
       SUM(CASE WHEN estado = 'ENTREGADO' THEN 1 ELSE 0 END) AS Entregados
FROM RecuperacionLogistica.dbo.Paquetes;   -- 17 · 7
GO

-- 5.6 Limpieza del entorno de prueba ----------------------------------------
ALTER DATABASE RecuperacionLogistica_Prueba SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE RecuperacionLogistica_Prueba;
DROP TABLE IF EXISTS ##PuntoSeguro;
SELECT name AS Bases_Restantes FROM sys.databases WHERE name LIKE N'RecuperacionLogistica%';
GO


/* =====================================================================
   ANEXO · Función de tabla para la pregunta de reflexión 2
   Reporte paramétrico por rango de fechas y sucursal.
   ===================================================================== */
USE RecuperacionLogistica;
GO
CREATE OR ALTER FUNCTION dbo.fn_PaquetesPorRango
(
    @desde       DATE,
    @hasta       DATE,
    @id_sucursal INT
)
RETURNS TABLE
AS
RETURN
(
    SELECT p.id_paquete, p.descripcion, p.fecha_envio, p.costo_envio, p.estado, s.nombre_ciudad
    FROM dbo.Paquetes AS p
    INNER JOIN dbo.Sucursales AS s ON s.id_sucursal = p.id_sucursal
    WHERE p.id_sucursal = @id_sucursal
      AND p.fecha_envio BETWEEN @desde AND @hasta
);
GO
SELECT * FROM dbo.fn_PaquetesPorRango('2026-11-01', '2026-11-30', 2) ORDER BY fecha_envio;
GO
