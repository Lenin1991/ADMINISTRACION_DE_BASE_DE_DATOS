/* 
   ADMINISTRACIÓN DE BASES DE DATOS · Unidad 1 · Tema 1
   Gestión de Concurrencia y Consistencia
   en el Sistema de Matriculación Universitaria
   
   Motor   : Microsoft SQL Server 2016 SP1 o superior (T-SQL)
   Autor   : <Apellido Nombre>
   Archivo : 1 de 3  (esquema, datos, transacciones A/B/C, mejoras)
             2 de 3  02_Sesion_1.sql  (pruebas de aislamiento)
             3 de 3  03_Sesion_2.sql  (pruebas de aislamiento)
  
   CÓMO EJECUTAR (SSMS):
   Selecciona cada bloque con el mouse y presiona F5. Ejecutar bloque
   por bloque permite tomar una captura del estado de la base de datos
   antes y después de cada operación.
                                                                     */


/* 
   SECCIÓN 0 · CREACIÓN DE LA BASE DE DATOS
                                                                          */
USE master;
GO

-- Si la base existe de una ejecución anterior, se elimina para empezar
-- desde un estado limpio y reproducible.
IF DB_ID(N'MatriculacionUNACH') IS NOT NULL
BEGIN
    ALTER DATABASE MatriculacionUNACH SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MatriculacionUNACH;
END
GO

CREATE DATABASE MatriculacionUNACH;
GO

-- READ COMMITTED en SQL Server puede funcionar con bloqueos o con
-- versiones de filas (snapshot). Se desactiva el versionado para que
-- el motor use bloqueos clásicos y los fenómenos de concurrencia
-- (esperas, bloqueos) sean visibles en las pruebas de la Sección 3.
ALTER DATABASE MatriculacionUNACH SET READ_COMMITTED_SNAPSHOT OFF;
ALTER DATABASE MatriculacionUNACH SET ALLOW_SNAPSHOT_ISOLATION OFF;
GO

USE MatriculacionUNACH;
GO


/* 
   SECCIÓN 1 · ESQUEMA Y RESTRICCIONES
                                                                       */


-- 1.1 Estudiantes

CREATE TABLE dbo.Estudiantes (
    estudiante_id  INT IDENTITY(1,1)  NOT NULL,
    nombre         NVARCHAR(100)      NOT NULL,
    cedula         CHAR(10)           NOT NULL,   -- cédula ecuatoriana: 10 dígitos
    facultad       NVARCHAR(80)       NOT NULL,

    CONSTRAINT PK_Estudiantes        PRIMARY KEY (estudiante_id),
    CONSTRAINT UQ_Estudiantes_cedula UNIQUE (cedula),
    CONSTRAINT CK_Estudiantes_cedula CHECK (LEN(cedula) = 10
                                           AND cedula NOT LIKE '%[^0-9]%')
);
GO


-- 1.2 Asignaturas
-- El CHECK sobre cupos_disponibles es la última línea de defensa:
-- aunque una aplicación tenga un error, el motor nunca aceptará un
-- cupo negativo (sobreventa de cupos).

CREATE TABLE dbo.Asignaturas (
    asignatura_id      INT IDENTITY(1,1) NOT NULL,
    nombre_materia     NVARCHAR(100)     NOT NULL,
    docente            NVARCHAR(100)     NOT NULL,
    cupos_disponibles  SMALLINT          NOT NULL,

    CONSTRAINT PK_Asignaturas         PRIMARY KEY (asignatura_id),
    CONSTRAINT UQ_Asignaturas_nombre  UNIQUE (nombre_materia),
    CONSTRAINT CK_Asignaturas_cupos   CHECK (cupos_disponibles >= 0)
);
GO


-- 1.3 Registros_Matricula

CREATE TABLE dbo.Registros_Matricula (
    registro_id     INT IDENTITY(1,1) NOT NULL,
    estudiante_id   INT               NOT NULL,
    asignatura_id   INT               NOT NULL,
    fecha_registro  DATETIME2(0)      NOT NULL
                    CONSTRAINT DF_Matricula_fecha  DEFAULT (SYSDATETIME()),
    estado          VARCHAR(12)       NOT NULL
                    CONSTRAINT DF_Matricula_estado DEFAULT ('PENDIENTE'),

    CONSTRAINT PK_Registros_Matricula PRIMARY KEY (registro_id),
    CONSTRAINT FK_Matricula_Estudiante
        FOREIGN KEY (estudiante_id) REFERENCES dbo.Estudiantes (estudiante_id),
    CONSTRAINT FK_Matricula_Asignatura
        FOREIGN KEY (asignatura_id) REFERENCES dbo.Asignaturas (asignatura_id),
    CONSTRAINT CK_Matricula_estado
        CHECK (estado IN ('CONFIRMADA', 'PENDIENTE')),
    -- Un estudiante no puede matricularse dos veces en la misma materia.
    CONSTRAINT UQ_Matricula_Estudiante_Asignatura
        UNIQUE (estudiante_id, asignatura_id)
);
GO


-- 1.4 Índice de apoyo (Tema 1.4)
-- La restricción UNIQUE ya crea un índice que empieza por estudiante_id.
-- Este índice cubre las búsquedas por asignatura ("¿quiénes están
-- matriculados en Base de Datos?") y permite que SERIALIZABLE bloquee
-- solo el rango de esa asignatura y no toda la tabla.

CREATE NONCLUSTERED INDEX IX_Matricula_Asignatura
    ON dbo.Registros_Matricula (asignatura_id)
    INCLUDE (estado);
GO


-- 1.5 Datos iniciales (datos ficticios)

INSERT INTO dbo.Estudiantes (nombre, cedula, facultad) VALUES
    (N'Ana Lucía Guamán',     '0600000001', N'Ingeniería'),
    (N'Carlos Andrés Yépez',  '0600000002', N'Ingeniería'),
    (N'María José Cando',     '0600000003', N'Ciencias de la Educación'),
    (N'Luis Fernando Ortiz',  '0600000004', N'Ciencias de la Salud'),
    (N'Daniela Paredes',      '0600000005', N'Ciencias Políticas y Administrativas');

INSERT INTO dbo.Asignaturas (nombre_materia, docente, cupos_disponibles) VALUES
    (N'Base de Datos',              N'Ing. Patricio Morales',   6),  -- id 1
    (N'Programación Avanzada',      N'Ing. Verónica Salazar',  10),  -- id 2
    (N'Redes de Computadoras',      N'Ing. Jorge Villacrés',    8),  -- id 3
    (N'Sistemas Operativos',        N'Ing. Gabriela Naranjo',  12),  -- id 4
    (N'Seminario de Investigación', N'Dra. Silvia Cevallos',    1);  -- id 5
GO

-- Verificación del estado inicial
SELECT * FROM dbo.Estudiantes;
SELECT * FROM dbo.Asignaturas;
SELECT * FROM dbo.Registros_Matricula;   -- vacía
GO


-- 1.6 Vistas de monitoreo de concurrencia (se usan en la Sección 3)
-- Requieren el permiso VIEW SERVER STATE (lo tiene un usuario
-- administrador en una instalación local).

CREATE OR ALTER VIEW dbo.vw_MonitorBloqueos
AS
SELECT
    l.request_session_id   AS sesion,
    l.resource_type        AS tipo_recurso,
    CASE
        WHEN l.resource_type = 'OBJECT'
            THEN OBJECT_NAME(l.resource_associated_entity_id)
        ELSE OBJECT_NAME(p.object_id)
    END                    AS tabla,
    l.resource_description AS detalle,
    l.request_mode         AS modo_bloqueo,   -- S, X, IX, RangeS-S, etc.
    l.request_status       AS estado          -- GRANT = concedido, WAIT = esperando
FROM sys.dm_tran_locks AS l
LEFT JOIN sys.partitions AS p
       ON p.hobt_id = l.resource_associated_entity_id
WHERE l.resource_database_id = DB_ID()
  AND l.resource_type <> 'DATABASE';
GO

CREATE OR ALTER VIEW dbo.vw_SesionesBloqueadas
AS
SELECT
    r.session_id          AS sesion_bloqueada,
    r.blocking_session_id AS bloqueada_por,
    r.wait_type           AS tipo_espera,
    r.wait_time           AS espera_ms,
    t.text                AS instruccion_en_espera
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.blocking_session_id <> 0;
GO


/* 
   SECCIÓN 2 · TRANSACCIONES CON PROPIEDADES ACID
                                                                       */

/* 
   TRANSACCIÓN A · USO DE COMMIT
   El Estudiante 1 se matricula en "Base de Datos".
   Resultado esperado: el registro existe y el cupo baja de 6 a 5.
                                                                   */

-- A.0 Estado ANTES
SELECT asignatura_id, nombre_materia, cupos_disponibles
FROM dbo.Asignaturas
WHERE nombre_materia = N'Base de Datos';            -- 6 cupos

SELECT * FROM dbo.Registros_Matricula;              -- 0 filas
GO

-- A.1 Transacción
BEGIN TRANSACTION MatriculaA;

    DECLARE @id_bd INT = (SELECT asignatura_id
                          FROM dbo.Asignaturas
                          WHERE nombre_materia = N'Base de Datos');

    -- Paso 1: registrar la matrícula
    INSERT INTO dbo.Registros_Matricula (estudiante_id, asignatura_id, estado)
    VALUES (1, @id_bd, 'CONFIRMADA');

    -- Paso 2: descontar el cupo
    UPDATE dbo.Asignaturas
    SET cupos_disponibles = cupos_disponibles - 1
    WHERE asignatura_id = @id_bd;

    -- 1 = la transacción sigue abierta; nada es permanente todavía
    SELECT @@TRANCOUNT AS transacciones_abiertas;

COMMIT TRANSACTION MatriculaA;
GO

-- A.2 Verificación DESPUÉS del COMMIT
SELECT r.registro_id,
       e.nombre          AS estudiante,
       a.nombre_materia,
       r.fecha_registro,
       r.estado,
       a.cupos_disponibles
FROM dbo.Registros_Matricula AS r
JOIN dbo.Estudiantes  AS e ON e.estudiante_id = r.estudiante_id
JOIN dbo.Asignaturas  AS a ON a.asignatura_id = r.asignatura_id;  -- cupos = 5

SELECT @@TRANCOUNT AS transacciones_abiertas;       -- 0
GO


/* 
   TRANSACCIÓN B · USO DE ROLLBACK
   El Estudiante 2 inicia su matrícula, ocurre un fallo a mitad de
   camino y se deshace todo. Ejecutar B.1, B.2 y B.3 POR SEPARADO.
                                                                     */

-- B.1 Inicio de la transacción e INSERT
SELECT COUNT(*) AS registros_antes FROM dbo.Registros_Matricula;   -- 1

BEGIN TRANSACTION MatriculaB;

    INSERT INTO dbo.Registros_Matricula (estudiante_id, asignatura_id, estado)
    VALUES (2, 1, 'PENDIENTE');

    -- Dentro de la transacción el nuevo registro SÍ se ve:
    SELECT * FROM dbo.Registros_Matricula;                          -- 2 filas
    SELECT @@TRANCOUNT AS transacciones_abiertas;                   -- 1
GO

-- B.2 Fallo simulado: comando erróneo (la columna "cupos" no existe).
-- Resultado esperado: Msg 207 "Invalid column name 'cupos'".
UPDATE dbo.Asignaturas
SET cupos = cupos - 1
WHERE asignatura_id = 1;
GO

-- B.3 Se detecta el fallo y se deshace la transacción
SELECT @@TRANCOUNT AS transacciones_abiertas;   -- sigue en 1: el error no la cerró

ROLLBACK TRANSACTION MatriculaB;
GO

-- B.4 Verificación DESPUÉS del ROLLBACK
SELECT COUNT(*) AS registros_despues FROM dbo.Registros_Matricula;   -- 1
SELECT * FROM dbo.Registros_Matricula;          -- solo el registro de la Transacción A

SELECT cupos_disponibles
FROM dbo.Asignaturas WHERE asignatura_id = 1;   -- 5, sin cambios

-- Hallazgo: el ROLLBACK deshace los datos, pero NO el contador IDENTITY.
-- El valor 2 ya fue consumido y la próxima matrícula recibirá el id 3.
SELECT IDENT_CURRENT('dbo.Registros_Matricula') AS ultimo_identity_generado;   -- 2
GO


/* 
   TRANSACCIÓN C · MATRÍCULA MULTIMATERIA (ATOMICIDAD)
   Tres materias en una sola transacción. La tercera usa un ID que no
   existe (999); al fallar, las dos primeras deben deshacerse.

   Hallazgo importante: en SQL un UPDATE con un ID inexistente NO
   produce error, simplemente afecta 0 filas. Si no se valida
   @@ROWCOUNT, la transacción haría COMMIT de una matrícula incompleta.
   Por eso se valida y se lanza el error con THROW.
                                                                       */

-- C.0 Estado ANTES
SELECT asignatura_id, nombre_materia, cupos_disponibles
FROM dbo.Asignaturas
WHERE asignatura_id IN (1, 2);          -- 5 y 10
GO

-- C.1 Transacción (ejecutar este bloque completo de una vez)
SET XACT_ABORT ON;   -- ante cualquier error en tiempo de ejecución, la transacción
                     -- queda marcada para revertirse por completo

-- Una variable de tabla NO se ve afectada por el ROLLBACK, por eso
-- sirve como "caja negra" para guardar evidencia de lo que pasó adentro.
DECLARE @evidencia TABLE (
    orden          TINYINT,
    momento        NVARCHAR(40),
    asignatura_id  INT,
    nombre_materia NVARCHAR(100),
    cupos          SMALLINT
);

INSERT INTO @evidencia
SELECT 1, N'Antes de la transacción', asignatura_id, nombre_materia, cupos_disponibles
FROM dbo.Asignaturas WHERE asignatura_id IN (1, 2);

BEGIN TRY
    BEGIN TRANSACTION MatriculaMultimateria;

        -- Materia 1 (éxito)
        UPDATE dbo.Asignaturas
        SET cupos_disponibles = cupos_disponibles - 1
        WHERE asignatura_id = 1;

        -- Materia 2 (éxito)
        UPDATE dbo.Asignaturas
        SET cupos_disponibles = cupos_disponibles - 1
        WHERE asignatura_id = 2;

        INSERT INTO @evidencia
        SELECT 2, N'Dentro de la transacción', asignatura_id, nombre_materia, cupos_disponibles
        FROM dbo.Asignaturas WHERE asignatura_id IN (1, 2);

        -- Materia 3 (falla: el ID 999 no existe)
        UPDATE dbo.Asignaturas
        SET cupos_disponibles = cupos_disponibles - 1
        WHERE asignatura_id = 999;

        IF @@ROWCOUNT = 0
        BEGIN
            THROW 50001, N'La asignatura 999 no existe. Se cancela la matrícula completa.', 1;
        END

    COMMIT TRANSACTION MatriculaMultimateria;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    SELECT ERROR_NUMBER()  AS numero_error,
           ERROR_MESSAGE() AS mensaje,
           N'ROLLBACK ejecutado' AS accion;
END CATCH;

INSERT INTO @evidencia
SELECT 3, N'Después del ROLLBACK', asignatura_id, nombre_materia, cupos_disponibles
FROM dbo.Asignaturas WHERE asignatura_id IN (1, 2);

-- Evidencia: dentro de la transacción los cupos bajaron (4 y 9),
-- pero después del ROLLBACK volvieron a 5 y 10.
SELECT momento, asignatura_id, nombre_materia, cupos
FROM @evidencia
ORDER BY asignatura_id, orden;

SET XACT_ABORT OFF;
GO

-- C.2 Verificación final
SELECT asignatura_id, nombre_materia, cupos_disponibles
FROM dbo.Asignaturas;                   -- Base de Datos = 5, Programación Avanzada = 10
GO


/*  
   SECCIÓN 4 · VALOR AGREGADO
   (La Sección 3, niveles de aislamiento, está en los archivos
    02_Sesion_1.sql y 03_Sesion_2.sql)
                                                                        */

-- 
-- 4.1 Prueba del CHECK: el motor rechaza un cupo negativo
-- Resultado esperado: Msg 547, conflicto con CK_Asignaturas_cupos.
-- 
BEGIN TRY
    UPDATE dbo.Asignaturas
    SET cupos_disponibles = -1
    WHERE asignatura_id = 5;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS numero_error, ERROR_MESSAGE() AS mensaje;
END CATCH;

SELECT asignatura_id, nombre_materia, cupos_disponibles
FROM dbo.Asignaturas WHERE asignatura_id = 5;   -- sigue en 1
GO

-- 
-- 4.2 Procedimiento almacenado de matrícula segura
-- Combina lo visto en la tarea:
--   * Atomicidad: TRY/CATCH + XACT_ABORT, todo o nada.
--   * Concurrencia: el cupo se descuenta con un UPDATE condicional
--     (cupos_disponibles > 0). Leer y escribir ocurre en UNA sola
--     instrucción con bloqueo exclusivo, así dos estudiantes nunca
--     pueden tomar el mismo último cupo, sin necesidad de SERIALIZABLE.
--   * Integridad: si el INSERT falla (estudiante duplicado o
--     inexistente), el cupo descontado se devuelve automáticamente.
-- 
CREATE OR ALTER PROCEDURE dbo.sp_MatricularEstudiante
    @estudiante_id INT,
    @asignatura_id INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

            UPDATE dbo.Asignaturas
            SET cupos_disponibles = cupos_disponibles - 1
            WHERE asignatura_id = @asignatura_id
              AND cupos_disponibles > 0;

            IF @@ROWCOUNT = 0
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM dbo.Asignaturas
                               WHERE asignatura_id = @asignatura_id)
                BEGIN
                    THROW 50010, N'La asignatura no existe.', 1;
                END
                ELSE
                BEGIN
                    THROW 50011, N'No hay cupos disponibles en la asignatura.', 1;
                END
            END

            INSERT INTO dbo.Registros_Matricula (estudiante_id, asignatura_id, estado)
            VALUES (@estudiante_id, @asignatura_id, 'CONFIRMADA');

        COMMIT TRANSACTION;

        SELECT N'Matrícula confirmada' AS resultado,
               @estudiante_id AS estudiante_id,
               @asignatura_id AS asignatura_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;   -- devuelve el error original a quien llamó al procedimiento
    END CATCH
END;
GO

-- 4.3 Pruebas del procedimiento (ejecutar UNA por UNA)

-- Caso 1: matrícula correcta. Seminario baja de 1 a 0.
EXEC dbo.sp_MatricularEstudiante @estudiante_id = 3, @asignatura_id = 5;
GO

-- Caso 2: ya no hay cupos. Error 50011, nada cambia.
EXEC dbo.sp_MatricularEstudiante @estudiante_id = 4, @asignatura_id = 5;
GO

-- Caso 3: matrícula duplicada. Error 2627 (UNIQUE).
-- El UPDATE ya había descontado el cupo, pero el ROLLBACK lo devuelve.
EXEC dbo.sp_MatricularEstudiante @estudiante_id = 1, @asignatura_id = 1;
GO

-- Caso 4: asignatura inexistente. Error 50010.
EXEC dbo.sp_MatricularEstudiante @estudiante_id = 2, @asignatura_id = 999;
GO

-- Verificación: los cupos coinciden con las matrículas confirmadas.
SELECT a.asignatura_id,
       a.nombre_materia,
       a.cupos_disponibles,
       COUNT(r.registro_id) AS matriculados
FROM dbo.Asignaturas AS a
LEFT JOIN dbo.Registros_Matricula AS r ON r.asignatura_id = a.asignatura_id
GROUP BY a.asignatura_id, a.nombre_materia, a.cupos_disponibles
ORDER BY a.asignatura_id;
-- Base de Datos: 5 cupos, 1 matriculado · Seminario: 0 cupos, 1 matriculado
GO
