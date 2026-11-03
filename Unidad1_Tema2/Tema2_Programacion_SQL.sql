/* =====================================================================
   ADMINISTRACIÓN DE BASES DE DATOS · Unidad 1 · Tema 2
   Implementación de vistas, funciones, procedimientos y triggers
   en el sistema de gestión de matrículas
   ---------------------------------------------------------------------
   Motor   : Microsoft SQL Server 2017 o superior (probado en SQL Server 2025, v17.0)
   Autor   : Lenin Vladimir Peñafiel Buestán
   ---------------------------------------------------------------------
   ORDEN DEL SCRIPT
     0. Creación de la base de datos
     1. Tablas base (Tema 1) + Auditoria_Matriculas + Historial_Cupos
     2. Funciones
     3. Vistas
     4. Triggers
     5. Procedimientos almacenados
     6. Carga de datos (a través del procedimiento de inscripción)
     7. Pruebas de éxito
     8. Pruebas de error
     9. Valor agregado: seguridad por roles e intento de inyección SQL

   CÓMO EJECUTAR (SSMS): ejecutar las secciones 0 a 6 completas una sola
   vez. Las secciones 7, 8 y 9 se ejecutan bloque por bloque (seleccionar
   el bloque y presionar F5) para tomar las capturas de cada prueba.
   ===================================================================== */


/* =====================================================================
   SECCIÓN 0 · CREACIÓN DE LA BASE DE DATOS
   ===================================================================== */
USE master;
GO

IF DB_ID(N'MatriculacionUNACH_T2') IS NOT NULL
BEGIN
    ALTER DATABASE MatriculacionUNACH_T2 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MatriculacionUNACH_T2;
END
GO

CREATE DATABASE MatriculacionUNACH_T2;
GO

USE MatriculacionUNACH_T2;
GO


/* =====================================================================
   SECCIÓN 1 · TABLAS
   ===================================================================== */

-- 1.1 Tablas base (mismo diseño de la actividad del Tema 1) -------------
CREATE TABLE dbo.Estudiantes (
    estudiante_id  INT IDENTITY(1,1)  NOT NULL,
    nombre         NVARCHAR(100)      NOT NULL,
    cedula         CHAR(10)           NOT NULL,
    facultad       NVARCHAR(80)       NOT NULL,
    CONSTRAINT PK_Estudiantes        PRIMARY KEY (estudiante_id),
    CONSTRAINT UQ_Estudiantes_cedula UNIQUE (cedula),
    CONSTRAINT CK_Estudiantes_cedula CHECK (LEN(cedula) = 10 AND cedula NOT LIKE '%[^0-9]%')
);

CREATE TABLE dbo.Asignaturas (
    asignatura_id      INT IDENTITY(1,1) NOT NULL,
    nombre_materia     NVARCHAR(100)     NOT NULL,
    docente            NVARCHAR(100)     NOT NULL,
    cupos_disponibles  SMALLINT          NOT NULL,
    CONSTRAINT PK_Asignaturas        PRIMARY KEY (asignatura_id),
    CONSTRAINT UQ_Asignaturas_nombre UNIQUE (nombre_materia),
    -- Se conserva como última línea de defensa; el trigger
    -- tr_ValidarCupoNegativo intercepta antes con un mensaje claro.
    CONSTRAINT CK_Asignaturas_cupos  CHECK (cupos_disponibles >= 0)
);

CREATE TABLE dbo.Registros_Matricula (
    registro_id     INT IDENTITY(1,1) NOT NULL,
    estudiante_id   INT               NOT NULL,
    asignatura_id   INT               NOT NULL,
    fecha_registro  DATETIME2(0)      NOT NULL CONSTRAINT DF_Matricula_fecha  DEFAULT (SYSDATETIME()),
    estado          VARCHAR(12)       NOT NULL CONSTRAINT DF_Matricula_estado DEFAULT ('CONFIRMADA'),
    CONSTRAINT PK_Registros_Matricula PRIMARY KEY (registro_id),
    CONSTRAINT FK_Matricula_Estudiante FOREIGN KEY (estudiante_id) REFERENCES dbo.Estudiantes (estudiante_id),
    CONSTRAINT FK_Matricula_Asignatura FOREIGN KEY (asignatura_id) REFERENCES dbo.Asignaturas (asignatura_id),
    CONSTRAINT CK_Matricula_estado     CHECK (estado IN ('CONFIRMADA', 'PENDIENTE')),
    CONSTRAINT UQ_Matricula_Estudiante_Asignatura UNIQUE (estudiante_id, asignatura_id)
);

-- Índice de apoyo para las consultas por asignatura (vistas, fn_ListaClase,
-- reporte de carga docente). El índice del UNIQUE ya cubre estudiante_id.
CREATE NONCLUSTERED INDEX IX_Matricula_Asignatura
    ON dbo.Registros_Matricula (asignatura_id) INCLUDE (estudiante_id, fecha_registro);
GO

-- 1.2 Auditoria_Matriculas ----------------------------------------------
-- Además de las columnas pedidas, guarda el estudiante, la asignatura, el
-- equipo y la aplicación de origen, para que la bitácora siga siendo útil
-- aunque el registro de matrícula ya haya sido eliminado (retiro).
CREATE TABLE dbo.Auditoria_Matriculas (
    auditoria_id   INT IDENTITY(1,1) NOT NULL,
    registro_id    INT               NOT NULL,      -- sin FK: el registro puede haber sido retirado
    estudiante_id  INT               NOT NULL,
    asignatura_id  INT               NOT NULL,
    accion         NVARCHAR(15)      NOT NULL,
    usuario        NVARCHAR(128)     NOT NULL CONSTRAINT DF_Auditoria_usuario DEFAULT (ORIGINAL_LOGIN()),
    usuario_bd     NVARCHAR(128)     NOT NULL CONSTRAINT DF_Auditoria_usrbd   DEFAULT (USER_NAME()),
    fecha          DATETIME2(0)      NOT NULL CONSTRAINT DF_Auditoria_fecha   DEFAULT (SYSDATETIME()),
    equipo         NVARCHAR(128)     NULL     CONSTRAINT DF_Auditoria_equipo  DEFAULT (HOST_NAME()),
    aplicacion     NVARCHAR(128)     NULL     CONSTRAINT DF_Auditoria_app     DEFAULT (APP_NAME()),
    CONSTRAINT PK_Auditoria_Matriculas PRIMARY KEY (auditoria_id),
    CONSTRAINT CK_Auditoria_accion     CHECK (accion IN (N'MATRICULACIÓN', N'RETIRO'))
);

-- 1.3 Historial_Cupos ----------------------------------------------------
CREATE TABLE dbo.Historial_Cupos (
    historial_id   INT IDENTITY(1,1) NOT NULL,
    asignatura_id  INT               NOT NULL,
    cupo_anterior  SMALLINT          NOT NULL,
    cupo_nuevo     SMALLINT          NOT NULL,
    fecha_cambio   DATETIME2(0)      NOT NULL CONSTRAINT DF_Historial_fecha   DEFAULT (SYSDATETIME()),
    usuario        NVARCHAR(128)     NOT NULL CONSTRAINT DF_Historial_usuario DEFAULT (ORIGINAL_LOGIN()),
    CONSTRAINT PK_Historial_Cupos PRIMARY KEY (historial_id),
    CONSTRAINT FK_Historial_Asignatura FOREIGN KEY (asignatura_id) REFERENCES dbo.Asignaturas (asignatura_id)
);
GO

-- 1.4 Datos maestros -------------------------------------------------------
INSERT INTO dbo.Estudiantes (nombre, cedula, facultad) VALUES
    (N'Ana Lucía Guamán',      '0600000001', N'Ingeniería'),
    (N'Carlos Andrés Yépez',   '0600000002', N'Ingeniería'),
    (N'María José Cando',      '0600000003', N'Ciencias de la Educación'),
    (N'Luis Fernando Ortiz',   '0600000004', N'Ciencias de la Salud'),
    (N'Daniela Paredes',       '0600000005', N'Ciencias Políticas y Administrativas'),
    (N'Jorge Enrique Vallejo', '0600000006', N'Ingeniería'),
    (N'Paola Estefanía Rivas', '0600000007', N'Ciencias de la Salud'),
    (N'Diego Alejandro Mora',  '0600000008', N'Ingeniería');

INSERT INTO dbo.Asignaturas (nombre_materia, docente, cupos_disponibles) VALUES
    (N'Base de Datos',              N'Ing. Patricio Morales', 30),  -- 1
    (N'Programación Avanzada',      N'Ing. Verónica Salazar', 25),  -- 2
    (N'Redes de Computadoras',      N'Ing. Jorge Villacrés',  20),  -- 3
    (N'Sistemas Operativos',        N'Ing. Gabriela Naranjo', 20),  -- 4
    (N'Estadística',                N'Ing. Verónica Salazar', 25),  -- 5
    (N'Cálculo Diferencial',        N'Dr. Marco Cevallos',    30),  -- 6
    (N'Inteligencia Artificial',    N'Ing. Patricio Morales', 15),  -- 7
    (N'Seminario de Investigación', N'Dra. Silvia Cevallos',   1);  -- 8
GO


/* =====================================================================
   SECCIÓN 2 · FUNCIONES
   ===================================================================== */

-- 2.1 fn_CalcularCostoMatricula (escalar) -------------------------------
-- Devuelve el valor a pagar: USD 15,00 por cada materia CONFIRMADA.
-- El tipo DECIMAL(10,2) evita los errores de redondeo de FLOAT en montos.
CREATE OR ALTER FUNCTION dbo.fn_CalcularCostoMatricula (@estudiante_id INT)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @costo_por_materia DECIMAL(10,2) = 15.00;
    DECLARE @materias INT;

    SELECT @materias = COUNT(*)
    FROM dbo.Registros_Matricula
    WHERE estudiante_id = @estudiante_id
      AND estado = 'CONFIRMADA';

    RETURN @materias * @costo_por_materia;
END;
GO

-- 2.2 fn_VerificarDisponibilidad (escalar) ------------------------------
-- Devuelve 1 si la asignatura tiene cupos y 0 si no los tiene o no existe.
CREATE OR ALTER FUNCTION dbo.fn_VerificarDisponibilidad (@asignatura_id INT)
RETURNS BIT
AS
BEGIN
    DECLARE @disponible BIT = 0;

    IF EXISTS (SELECT 1
               FROM dbo.Asignaturas
               WHERE asignatura_id = @asignatura_id
                 AND cupos_disponibles > 0)
        SET @disponible = 1;

    RETURN @disponible;
END;
GO

-- 2.3 fn_ListaClase (de tabla en línea) ---------------------------------
-- Función de tabla EN LÍNEA (una sola instrucción SELECT): el optimizador
-- la expande dentro de la consulta que la usa, igual que una vista, pero
-- con parámetro. Así aprovecha el índice IX_Matricula_Asignatura.
CREATE OR ALTER FUNCTION dbo.fn_ListaClase (@asignatura_id INT)
RETURNS TABLE
AS
RETURN
(
    SELECT e.nombre         AS Estudiante,
           e.cedula         AS Cedula,
           e.facultad       AS Facultad,
           r.fecha_registro AS Fecha_Matricula
    FROM dbo.Registros_Matricula AS r
    INNER JOIN dbo.Estudiantes   AS e ON e.estudiante_id = r.estudiante_id
    WHERE r.asignatura_id = @asignatura_id
      AND r.estado = 'CONFIRMADA'
);
GO


/* =====================================================================
   SECCIÓN 3 · VISTAS
   ===================================================================== */

-- 3.1 Vista_OfertaAcademica ----------------------------------------------
-- Materias con cupos > 0. La capacidad total se obtiene como
-- matriculados + cupos disponibles, y con ella el porcentaje de ocupación.
CREATE OR ALTER VIEW dbo.Vista_OfertaAcademica
AS
SELECT a.asignatura_id                          AS ID,
       a.nombre_materia                         AS Asignatura,
       a.docente                                AS Docente,
       COUNT(r.registro_id)                     AS Matriculados,
       a.cupos_disponibles                      AS Cupos_Disponibles,
       COUNT(r.registro_id) + a.cupos_disponibles AS Capacidad_Total,
       CAST(COUNT(r.registro_id) * 100.0
            / NULLIF(COUNT(r.registro_id) + a.cupos_disponibles, 0)
            AS DECIMAL(5,2))                    AS Porcentaje_Ocupacion
FROM dbo.Asignaturas AS a
LEFT JOIN dbo.Registros_Matricula AS r
       ON r.asignatura_id = a.asignatura_id
      AND r.estado = 'CONFIRMADA'
WHERE a.cupos_disponibles > 0
GROUP BY a.asignatura_id, a.nombre_materia, a.docente, a.cupos_disponibles;
GO

-- 3.2 Vista_DetalleMatricula ---------------------------------------------
CREATE OR ALTER VIEW dbo.Vista_DetalleMatricula
AS
SELECT r.registro_id     AS Registro,
       e.nombre          AS Estudiante,
       e.facultad        AS Facultad,
       a.nombre_materia  AS Asignatura,
       a.docente         AS Docente,
       r.fecha_registro  AS Fecha_Registro,
       r.estado          AS Estado
FROM dbo.Registros_Matricula AS r
INNER JOIN dbo.Estudiantes   AS e ON e.estudiante_id = r.estudiante_id
INNER JOIN dbo.Asignaturas   AS a ON a.asignatura_id = r.asignatura_id;
GO

-- 3.3 Vista_EstudiantesSaturados -----------------------------------------
CREATE OR ALTER VIEW dbo.Vista_EstudiantesSaturados
AS
SELECT e.estudiante_id    AS ID,
       e.nombre           AS Estudiante,
       e.cedula           AS Cedula,
       e.facultad         AS Facultad,
       COUNT(*)           AS Materias_Matriculadas
FROM dbo.Estudiantes AS e
INNER JOIN dbo.Registros_Matricula AS r
        ON r.estudiante_id = e.estudiante_id
       AND r.estado = 'CONFIRMADA'
GROUP BY e.estudiante_id, e.nombre, e.cedula, e.facultad
HAVING COUNT(*) > 5;
GO


/* =====================================================================
   SECCIÓN 4 · TRIGGERS
   Todos son "set-based": funcionan igual si la instrucción afecta una
   fila o muchas, porque trabajan con las tablas virtuales inserted/deleted.
   ===================================================================== */

-- 4.1 tr_AuditoriaMatricula_Insert ---------------------------------------
CREATE OR ALTER TRIGGER dbo.tr_AuditoriaMatricula_Insert
ON dbo.Registros_Matricula
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Auditoria_Matriculas (registro_id, estudiante_id, asignatura_id, accion)
    SELECT i.registro_id, i.estudiante_id, i.asignatura_id, N'MATRICULACIÓN'
    FROM inserted AS i;
END;
GO

-- 4.2 tr_ValidarCupoNegativo (INSTEAD OF UPDATE) -------------------------
-- Reemplaza la actualización: si alguna fila quedaría con cupos < 0,
-- rechaza la instrucción COMPLETA y explica qué materia lo provocó.
-- Si todo es válido, ejecuta la actualización real.
CREATE OR ALTER TRIGGER dbo.tr_ValidarCupoNegativo
ON dbo.Asignaturas
INSTEAD OF UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM inserted WHERE cupos_disponibles < 0)
    BEGIN
        DECLARE @detalle NVARCHAR(1500);

        SELECT @detalle = STRING_AGG(
                   CONCAT(i.nombre_materia, N' (', d.cupos_disponibles, N' → ', i.cupos_disponibles, N')'),
                   N', ')
        FROM inserted AS i
        INNER JOIN deleted AS d ON d.asignatura_id = i.asignatura_id
        WHERE i.cupos_disponibles < 0;

        DECLARE @mensaje NVARCHAR(2048) =
            CONCAT(N'Operación rechazada por tr_ValidarCupoNegativo: el cupo no puede ser negativo. ', @detalle);

        THROW 50020, @mensaje, 1;   -- dentro de un trigger, THROW revierte la transacción completa
    END;

    UPDATE a
    SET    a.nombre_materia    = i.nombre_materia,
           a.docente           = i.docente,
           a.cupos_disponibles = i.cupos_disponibles
    FROM dbo.Asignaturas AS a
    INNER JOIN inserted   AS i ON i.asignatura_id = a.asignatura_id;
END;
GO

-- 4.3 tr_LogCambioCupo (AFTER UPDATE) ------------------------------------
-- Registra en Historial_Cupos los cambios MANUALES de cupos.
-- Los procedimientos de inscripción y retiro marcan la sesión con
-- SESSION_CONTEXT('origen') = 'SP'; esos cambios ya quedan en la
-- auditoría de matrículas y no se duplican aquí.
CREATE OR ALTER TRIGGER dbo.tr_LogCambioCupo
ON dbo.Asignaturas
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF CAST(SESSION_CONTEXT(N'origen') AS NVARCHAR(10)) = N'SP'
        RETURN;

    INSERT INTO dbo.Historial_Cupos (asignatura_id, cupo_anterior, cupo_nuevo)
    SELECT i.asignatura_id, d.cupos_disponibles, i.cupos_disponibles
    FROM inserted AS i
    INNER JOIN deleted AS d ON d.asignatura_id = i.asignatura_id
    WHERE i.cupos_disponibles <> d.cupos_disponibles;
END;
GO


/* =====================================================================
   SECCIÓN 5 · PROCEDIMIENTOS ALMACENADOS
   ===================================================================== */

-- 5.1 sp_InscribirAsignatura ---------------------------------------------
-- Valida parámetros, bloquea la fila de la asignatura (UPDLOCK) para que
-- dos estudiantes no tomen el mismo último cupo, verifica disponibilidad
-- con fn_VerificarDisponibilidad, inserta y descuenta en una sola
-- transacción. La auditoría la registra el trigger automáticamente.
CREATE OR ALTER PROCEDURE dbo.sp_InscribirAsignatura
    @estudiante_id INT,
    @asignatura_id INT,
    @mostrar       BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Estudiantes WHERE estudiante_id = @estudiante_id)
            THROW 50013, N'El estudiante no existe.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.Asignaturas WHERE asignatura_id = @asignatura_id)
            THROW 50010, N'La asignatura no existe.', 1;

        EXEC sys.sp_set_session_context @key = N'origen', @value = N'SP';

        BEGIN TRANSACTION;

            -- Bloqueo de actualización sobre la fila: la siguiente sesión espera aquí.
            DECLARE @cupos SMALLINT;
            SELECT @cupos = cupos_disponibles
            FROM dbo.Asignaturas WITH (UPDLOCK, HOLDLOCK)
            WHERE asignatura_id = @asignatura_id;

            IF dbo.fn_VerificarDisponibilidad(@asignatura_id) = 0
                THROW 50011, N'No hay cupos disponibles en la asignatura.', 1;

            IF EXISTS (SELECT 1 FROM dbo.Registros_Matricula
                       WHERE estudiante_id = @estudiante_id AND asignatura_id = @asignatura_id)
                THROW 50012, N'El estudiante ya está matriculado en esta asignatura.', 1;

            INSERT INTO dbo.Registros_Matricula (estudiante_id, asignatura_id, estado)
            VALUES (@estudiante_id, @asignatura_id, 'CONFIRMADA');

            UPDATE dbo.Asignaturas
            SET cupos_disponibles = cupos_disponibles - 1
            WHERE asignatura_id = @asignatura_id;

        COMMIT TRANSACTION;

        EXEC sys.sp_set_session_context @key = N'origen', @value = NULL;

        IF @mostrar = 1
            SELECT N'Matrícula registrada' AS Resultado,
                   @estudiante_id          AS Estudiante,
                   @asignatura_id          AS Asignatura,
                   @cupos - 1              AS Cupos_Restantes;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'origen', @value = NULL;
        THROW;
    END CATCH
END;
GO

-- 5.2 sp_RetirarAsignatura -----------------------------------------------
CREATE OR ALTER PROCEDURE dbo.sp_RetirarAsignatura
    @estudiante_id INT,
    @asignatura_id INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        EXEC sys.sp_set_session_context @key = N'origen', @value = N'SP';

        BEGIN TRANSACTION;

            DECLARE @registro_id INT;
            SELECT @registro_id = registro_id
            FROM dbo.Registros_Matricula WITH (UPDLOCK, HOLDLOCK)
            WHERE estudiante_id = @estudiante_id
              AND asignatura_id = @asignatura_id;

            IF @registro_id IS NULL
                THROW 50014, N'No existe una matrícula de ese estudiante en esa asignatura.', 1;

            DELETE FROM dbo.Registros_Matricula
            WHERE registro_id = @registro_id;

            UPDATE dbo.Asignaturas
            SET cupos_disponibles = cupos_disponibles + 1
            WHERE asignatura_id = @asignatura_id;

            INSERT INTO dbo.Auditoria_Matriculas (registro_id, estudiante_id, asignatura_id, accion)
            VALUES (@registro_id, @estudiante_id, @asignatura_id, N'RETIRO');

        COMMIT TRANSACTION;

        EXEC sys.sp_set_session_context @key = N'origen', @value = NULL;

        SELECT N'Retiro registrado' AS Resultado,
               @registro_id         AS Registro_Eliminado,
               @estudiante_id       AS Estudiante,
               @asignatura_id       AS Asignatura;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'origen', @value = NULL;
        THROW;
    END CATCH
END;
GO

-- 5.3 sp_ReporteCargaDocente ---------------------------------------------
-- Resumen por docente. Se agrupa por asignatura ANTES de unir, para que
-- STRING_AGG no repita una materia por cada estudiante matriculado.
-- El parámetro opcional filtra un docente (búsqueda parcial) sin SQL dinámico.
CREATE OR ALTER PROCEDURE dbo.sp_ReporteCargaDocente
    @docente NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT a.docente                                   AS Docente,
           COUNT(*)                                    AS Materias_a_Cargo,
           SUM(ISNULL(m.total, 0))                     AS Total_Estudiantes,
           CAST(AVG(ISNULL(m.total, 0) * 1.0) AS DECIMAL(5,2)) AS Promedio_por_Materia,
           STRING_AGG(a.nombre_materia, N', ')
               WITHIN GROUP (ORDER BY a.nombre_materia) AS Detalle_Materias
    FROM dbo.Asignaturas AS a
    LEFT JOIN (SELECT asignatura_id, COUNT(*) AS total
               FROM dbo.Registros_Matricula
               WHERE estado = 'CONFIRMADA'
               GROUP BY asignatura_id) AS m
           ON m.asignatura_id = a.asignatura_id
    WHERE @docente IS NULL OR a.docente LIKE N'%' + @docente + N'%'
    GROUP BY a.docente
    ORDER BY Total_Estudiantes DESC, a.docente;
END;
GO


/* =====================================================================
   SECCIÓN 6 · CARGA DE MATRÍCULAS
   Se usa el propio procedimiento, de modo que cada matrícula descuenta
   su cupo y queda auditada por el trigger desde el inicio.
   ===================================================================== */
-- Estudiante 1: 6 materias (aparecerá en Vista_EstudiantesSaturados)
EXEC dbo.sp_InscribirAsignatura 1, 1, 0;
EXEC dbo.sp_InscribirAsignatura 1, 2, 0;
EXEC dbo.sp_InscribirAsignatura 1, 3, 0;
EXEC dbo.sp_InscribirAsignatura 1, 4, 0;
EXEC dbo.sp_InscribirAsignatura 1, 5, 0;
EXEC dbo.sp_InscribirAsignatura 1, 6, 0;
-- Estudiante 2: 5 materias (no aparece: la condición es MÁS de 5)
EXEC dbo.sp_InscribirAsignatura 2, 1, 0;
EXEC dbo.sp_InscribirAsignatura 2, 2, 0;
EXEC dbo.sp_InscribirAsignatura 2, 3, 0;
EXEC dbo.sp_InscribirAsignatura 2, 4, 0;
EXEC dbo.sp_InscribirAsignatura 2, 5, 0;
-- Resto de estudiantes
EXEC dbo.sp_InscribirAsignatura 3, 1, 0;
EXEC dbo.sp_InscribirAsignatura 3, 7, 0;
EXEC dbo.sp_InscribirAsignatura 3, 6, 0;
EXEC dbo.sp_InscribirAsignatura 4, 2, 0;
EXEC dbo.sp_InscribirAsignatura 4, 3, 0;
EXEC dbo.sp_InscribirAsignatura 5, 1, 0;
EXEC dbo.sp_InscribirAsignatura 5, 5, 0;
EXEC dbo.sp_InscribirAsignatura 6, 7, 0;
EXEC dbo.sp_InscribirAsignatura 7, 8, 0;   -- ocupa el único cupo de Seminario
-- El estudiante 8 queda sin matrículas para las pruebas.

SELECT N'Carga terminada' AS Estado,
       (SELECT COUNT(*) FROM dbo.Registros_Matricula)  AS Matriculas,
       (SELECT COUNT(*) FROM dbo.Auditoria_Matriculas) AS Filas_Auditoria,
       (SELECT COUNT(*) FROM dbo.Historial_Cupos)      AS Filas_Historial;   -- 20, 20, 0
GO


/* =====================================================================
   SECCIÓN 7 · PRUEBAS DE ÉXITO (ejecutar bloque por bloque)
   ===================================================================== */

-- PRUEBA 7.1-a · Vista_OfertaAcademica
-- Solo materias con cupos > 0 (Seminario de Investigación no aparece: 0 cupos)
SELECT *
FROM dbo.Vista_OfertaAcademica
ORDER BY Porcentaje_Ocupacion DESC;
GO

-- PRUEBA 7.1-b · Vista_DetalleMatricula (estudiante, facultad, materia y fecha)
SELECT Registro, Estudiante, Facultad, Asignatura, Fecha_Registro, Estado
FROM dbo.Vista_DetalleMatricula
ORDER BY Registro;
GO

-- PRUEBA 7.1-c · Vista_EstudiantesSaturados (más de 5 materias)
-- Carlos Andrés Yépez tiene exactamente 5 y NO debe aparecer
SELECT * FROM dbo.Vista_EstudiantesSaturados;

-- Control: número de materias por estudiante
SELECT e.estudiante_id, e.nombre, COUNT(r.registro_id) AS Materias
FROM dbo.Estudiantes AS e
LEFT JOIN dbo.Registros_Matricula AS r ON r.estudiante_id = e.estudiante_id
GROUP BY e.estudiante_id, e.nombre
ORDER BY Materias DESC;
GO

-- PRUEBA 7.2-a · fn_CalcularCostoMatricula → DECIMAL(10,2): USD 15,00 por materia
SELECT e.estudiante_id,
       e.nombre,
       dbo.fn_CalcularCostoMatricula(e.estudiante_id) AS Costo_Matricula_USD
FROM dbo.Estudiantes AS e
ORDER BY e.estudiante_id;

-- Tipo de dato devuelto por la función
SELECT SQL_VARIANT_PROPERTY(dbo.fn_CalcularCostoMatricula(1), 'BaseType')  AS Tipo,
       SQL_VARIANT_PROPERTY(dbo.fn_CalcularCostoMatricula(1), 'Precision') AS Precision,
       SQL_VARIANT_PROPERTY(dbo.fn_CalcularCostoMatricula(1), 'Scale')     AS Escala;
GO

-- PRUEBA 7.2-b · fn_VerificarDisponibilidad → BIT (1 = hay cupo, 0 = sin cupo)
SELECT a.asignatura_id,
       a.nombre_materia,
       a.cupos_disponibles,
       dbo.fn_VerificarDisponibilidad(a.asignatura_id) AS Disponible
FROM dbo.Asignaturas AS a
ORDER BY a.asignatura_id;

-- Asignatura inexistente → 0
SELECT dbo.fn_VerificarDisponibilidad(999) AS Disponible_Asignatura_999;
GO

-- PRUEBA 7.2-c · fn_ListaClase (función de tabla en línea con parámetro)
-- Lista de clase de Base de Datos (asignatura 1)
SELECT * FROM dbo.fn_ListaClase(1) ORDER BY Estudiante;

-- Se combina con otras tablas como si fuera una tabla más (CROSS APPLY)
SELECT a.nombre_materia AS Asignatura, lc.Estudiante, lc.Cedula
FROM dbo.Asignaturas AS a
CROSS APPLY dbo.fn_ListaClase(a.asignatura_id) AS lc
WHERE a.docente = N'Ing. Patricio Morales'
ORDER BY a.nombre_materia, lc.Estudiante;
GO

-- PRUEBA 7.3 · sp_InscribirAsignatura (éxito) + auditoría automática del trigger
-- Diego Alejandro Mora (8) se matricula en Redes de Computadoras (3)
SELECT cupos_disponibles AS Cupos_Redes_Antes FROM dbo.Asignaturas WHERE asignatura_id = 3;

EXEC dbo.sp_InscribirAsignatura @estudiante_id = 8, @asignatura_id = 3;

SELECT TOP (1) auditoria_id, registro_id, estudiante_id, asignatura_id,
       accion, usuario, usuario_bd, fecha, equipo, aplicacion
FROM dbo.Auditoria_Matriculas
ORDER BY auditoria_id DESC;
GO

-- PRUEBA 7.4 · sp_RetirarAsignatura (éxito): elimina, devuelve el cupo y audita
EXEC dbo.sp_RetirarAsignatura @estudiante_id = 8, @asignatura_id = 3;

SELECT cupos_disponibles AS Cupos_Redes_Despues FROM dbo.Asignaturas WHERE asignatura_id = 3;

SELECT TOP (2) auditoria_id, registro_id, estudiante_id, asignatura_id, accion, usuario, fecha
FROM dbo.Auditoria_Matriculas
ORDER BY auditoria_id DESC;
GO

-- PRUEBA 7.5 · sp_ReporteCargaDocente (resumen por docente, filtro opcional)
EXEC dbo.sp_ReporteCargaDocente;

-- Con filtro parcial por nombre del docente
EXEC dbo.sp_ReporteCargaDocente @docente = N'Salazar';
GO

-- PRUEBA 7.6 · tr_LogCambioCupo: un administrador amplía manualmente el cupo
-- de Base de Datos (1). El cambio queda en Historial_Cupos.
SELECT asignatura_id, nombre_materia, cupos_disponibles AS Cupo_Antes
FROM dbo.Asignaturas WHERE asignatura_id = 1;

UPDATE dbo.Asignaturas SET cupos_disponibles = 35 WHERE asignatura_id = 1;

SELECT * FROM dbo.Historial_Cupos;
-- Las inscripciones y el retiro hechos por los procedimientos NO están
-- en el historial (SESSION_CONTEXT 'origen' = 'SP'); solo el cambio manual.
GO


/* =====================================================================
   SECCIÓN 8 · PRUEBAS DE ERROR (ejecutar bloque por bloque)
   ===================================================================== */

-- PRUEBAS 8.1 a 8.5 · Errores controlados de los procedimientos (TRY/CATCH + THROW)
-- 8.1 Matricular sin cupo: Seminario de Investigación (8) tiene 0 cupos → 50011
EXEC dbo.sp_InscribirAsignatura @estudiante_id = 8, @asignatura_id = 8;
GO
-- 8.2 Matrícula duplicada: Ana Lucía ya está en Base de Datos → 50012
EXEC dbo.sp_InscribirAsignatura @estudiante_id = 1, @asignatura_id = 1;
GO
-- 8.3 Asignatura inexistente → 50010
EXEC dbo.sp_InscribirAsignatura @estudiante_id = 8, @asignatura_id = 999;
GO
-- 8.4 Estudiante inexistente → 50013
EXEC dbo.sp_InscribirAsignatura @estudiante_id = 999, @asignatura_id = 1;
GO
-- 8.5 Retiro de una matrícula que no existe → 50014
EXEC dbo.sp_RetirarAsignatura @estudiante_id = 8, @asignatura_id = 1;
GO

-- PRUEBA 8.6 · tr_ValidarCupoNegativo (INSTEAD OF UPDATE) impide un cupo negativo
-- Seminario de Investigación tiene 0 cupos; se intenta dejarlo en -1 → 50020
UPDATE dbo.Asignaturas
SET cupos_disponibles = cupos_disponibles - 1
WHERE asignatura_id = 8;
GO
-- PRUEBA 8.7 · Actualización masiva: si UNA materia quedaría negativa,
-- no cambia NINGUNA (la instrucción completa se rechaza) → 50020
UPDATE dbo.Asignaturas
SET cupos_disponibles = cupos_disponibles - 15;
GO

-- PRUEBA 8.8 · Verificación de atomicidad: tras los errores nada cambió
SELECT asignatura_id, nombre_materia, cupos_disponibles
FROM dbo.Asignaturas
ORDER BY asignatura_id;

SELECT (SELECT COUNT(*) FROM dbo.Registros_Matricula)  AS Matriculas,          -- sigue en 20
       (SELECT COUNT(*) FROM dbo.Auditoria_Matriculas) AS Filas_Auditoria,     -- 22 (20 + inscripción + retiro)
       (SELECT COUNT(*) FROM dbo.Historial_Cupos)      AS Filas_Historial,     -- 1 (solo el cambio manual)
       @@TRANCOUNT                                     AS Transacciones_Abiertas;
GO


/* =====================================================================
   SECCIÓN 9 · VALOR AGREGADO: SEGURIDAD POR ROLES E INYECCIÓN SQL
   La aplicación de matrícula solo puede EJECUTAR procedimientos y leer
   vistas; no puede tocar las tablas directamente. Gracias al
   encadenamiento de propiedad (ownership chaining), los procedimientos
   sí pueden modificar las tablas en su nombre.
   ===================================================================== */

-- PRUEBA 9.1 / 9.2 · Mínimo privilegio
CREATE ROLE rol_app_matricula;
GRANT EXECUTE ON dbo.sp_InscribirAsignatura TO rol_app_matricula;
GRANT EXECUTE ON dbo.sp_RetirarAsignatura   TO rol_app_matricula;
GRANT SELECT  ON dbo.Vista_OfertaAcademica  TO rol_app_matricula;
GRANT SELECT  ON dbo.Vista_DetalleMatricula TO rol_app_matricula;

CREATE USER usr_app_matricula WITHOUT LOGIN;
ALTER ROLE rol_app_matricula ADD MEMBER usr_app_matricula;
GO

-- Intento de escribir directamente en la tabla → error 229 (permiso denegado)
EXECUTE AS USER = 'usr_app_matricula';
    SELECT USER_NAME() AS Usuario_Actual;
    INSERT INTO dbo.Registros_Matricula (estudiante_id, asignatura_id) VALUES (8, 2);
REVERT;
GO

-- PRUEBA 9.3 · El mismo usuario SÍ puede matricular mediante el procedimiento
EXECUTE AS USER = 'usr_app_matricula';
    EXEC dbo.sp_InscribirAsignatura @estudiante_id = 8, @asignatura_id = 2;
    SELECT TOP (3) * FROM dbo.Vista_OfertaAcademica ORDER BY ID;   -- lectura permitida
REVERT;

SELECT TOP (1) auditoria_id, registro_id, accion, usuario, usuario_bd, fecha
FROM dbo.Auditoria_Matriculas
ORDER BY auditoria_id DESC;          -- usuario_bd = usr_app_matricula
GO

-- PRUEBA 9.4 · Intento de inyección SQL a través del procedimiento
-- El parámetro es INT: el texto malicioso nunca se ejecuta como código;
-- el motor solo intenta convertirlo a número y falla (error 8114).
EXEC dbo.sp_InscribirAsignatura
     @estudiante_id = '8; DROP TABLE dbo.Estudiantes;--',
     @asignatura_id = 2;
GO

SELECT COUNT(*) AS Estudiantes_Siguen_Existiendo FROM dbo.Estudiantes;   -- 8
GO

-- EVIDENCIA GENERAL · Objetos programables creados
SELECT o.type_desc                     AS Tipo_Objeto,
       o.name                          AS Nombre,
       OBJECT_NAME(o.parent_object_id) AS Tabla_Asociada,
       o.create_date                   AS Fecha_Creacion
FROM sys.objects AS o
WHERE o.is_ms_shipped = 0
  AND o.type IN ('U','V','FN','IF','P','TR')
ORDER BY CASE o.type WHEN 'U' THEN 1 WHEN 'V' THEN 2 WHEN 'FN' THEN 3
                     WHEN 'IF' THEN 4 WHEN 'P' THEN 5 ELSE 6 END, o.name;
GO
