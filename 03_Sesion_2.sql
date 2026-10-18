/* =====================================================================
   SECCIÓN 3 · CONTROL DE BLOQUEOS Y NIVELES DE AISLAMIENTO
   Archivo 3 de 3 · VENTANA "SESIÓN 2"  (Estudiante B)
   ---------------------------------------------------------------------
   Abre este archivo en una ventana distinta a la de 02_Sesion_1.sql.
   Ejecuta los pasos en el orden global (1.1, 1.2, 1.3...).
   Cada paso indica a qué ventana volver.
   ===================================================================== */

USE MatriculacionUNACH;
GO

-- Anota este número: identifica a esta sesión en las vistas de bloqueos.
SELECT @@SPID AS id_sesion_2;
GO


/* =====================================================================
   ESCENARIO 1 · READ UNCOMMITTED  (lectura sucia)
   Empieza en SESIÓN 1, paso 1.0
   ===================================================================== */

-- 1.2 (SESIÓN 2) El Estudiante B consulta cupos leyendo datos NO confirmados
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT asignatura_id, nombre_materia, cupos_disponibles
FROM dbo.Asignaturas WHERE asignatura_id = 1;      -- 4: LECTURA SUCIA (no espera)

SELECT registro_id, estudiante_id, asignatura_id, estado
FROM dbo.Registros_Matricula WHERE asignatura_id = 1;   -- aparece el estudiante 4, que aún no confirma
GO
-- → Ve a SESIÓN 1, paso 1.3

-- 1.4 (SESIÓN 2) Volver a consultar después del ROLLBACK de la Sesión 1
SELECT asignatura_id, nombre_materia, cupos_disponibles
FROM dbo.Asignaturas WHERE asignatura_id = 1;      -- 5: el 4 leído antes NUNCA existió

SELECT registro_id, estudiante_id, asignatura_id, estado
FROM dbo.Registros_Matricula WHERE asignatura_id = 1;   -- el estudiante 4 desapareció
GO
-- → Ve a SESIÓN 1, paso 2.0


/* =====================================================================
   ESCENARIO 2 · READ COMMITTED
   ===================================================================== */

-- 2.2 (SESIÓN 2) Consultar el cupo mientras la Sesión 1 tiene un cambio
-- sin confirmar. ESTA CONSULTA QUEDA EN ESPERA: READ COMMITTED no
-- permite leer el dato sucio, así que espera a que se libere.
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

SELECT asignatura_id, nombre_materia, cupos_disponibles
FROM dbo.Asignaturas WHERE asignatura_id = 1;      -- espera... luego devuelve 5
GO
-- → Ve a SESIÓN 1, paso 2.3

-- 2.5 (SESIÓN 2) El estudiante abre la pantalla de matrícula
BEGIN TRANSACTION;

    SELECT cupos_disponibles AS primera_lectura
    FROM dbo.Asignaturas WHERE asignatura_id = 1;  -- 5
GO
-- → Ve a SESIÓN 1, paso 2.6

-- 2.7 (SESIÓN 2) Misma consulta, misma transacción, distinto resultado
    SELECT cupos_disponibles AS segunda_lectura
    FROM dbo.Asignaturas WHERE asignatura_id = 1;  -- 4: LECTURA NO REPETIBLE

COMMIT TRANSACTION;
GO
-- → Ve a SESIÓN 1, paso 3.0


/* =====================================================================
   ESCENARIO 3 · REPEATABLE READ
   ===================================================================== */

-- 3.1 (SESIÓN 2) El sistema lee que hay 5 cupos
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

BEGIN TRANSACTION;

    SELECT cupos_disponibles AS primera_lectura
    FROM dbo.Asignaturas WHERE asignatura_id = 1;  -- 5
GO
-- → Ve a SESIÓN 1, paso 3.2 (su UPDATE quedará bloqueado)

-- 3.3 (SESIÓN 2) Observar el bloqueo y repetir la lectura
SELECT * FROM dbo.vw_SesionesBloqueadas;           -- Sesión 1 bloqueada por Sesión 2
SELECT * FROM dbo.vw_MonitorBloqueos ORDER BY sesion, tipo_recurso;
-- Sesión 2: bloqueo S en GRANT · Sesión 1: bloqueo X en WAIT

    SELECT cupos_disponibles AS segunda_lectura
    FROM dbo.Asignaturas WHERE asignatura_id = 1;  -- sigue en 5: LECTURA REPETIBLE
GO

-- 3.4 (SESIÓN 2) Terminar. En ese instante el UPDATE de la Sesión 1 se ejecuta.
COMMIT TRANSACTION;
GO
-- → Ve a SESIÓN 1, paso 3.5

-- 3.6 (SESIÓN 2) Consultar la lista de matriculados en Base de Datos
BEGIN TRANSACTION;

    SELECT registro_id, estudiante_id, estado
    FROM dbo.Registros_Matricula
    WHERE asignatura_id = 1;                       -- 1 fila
GO
-- → Ve a SESIÓN 1, paso 3.7

-- 3.8 (SESIÓN 2) Repetir la misma consulta
    SELECT registro_id, estudiante_id, estado
    FROM dbo.Registros_Matricula
    WHERE asignatura_id = 1;                       -- 2 filas: LECTURA FANTASMA

COMMIT TRANSACTION;
GO
-- → Ve a SESIÓN 1, paso 4.0


/* =====================================================================
   ESCENARIO 4 · SERIALIZABLE
   ===================================================================== */

-- 4.1 (SESIÓN 2) Leer cupos y matriculados en el nivel más estricto
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

BEGIN TRANSACTION;

    SELECT cupos_disponibles
    FROM dbo.Asignaturas WHERE asignatura_id = 1;  -- 5

    SELECT registro_id, estudiante_id, estado
    FROM dbo.Registros_Matricula
    WHERE asignatura_id = 1;                       -- 1 fila
GO
-- → Ve a SESIÓN 1, paso 4.2 (su INSERT quedará bloqueado)

-- 4.3 (SESIÓN 2) Observar el bloqueo de rango y repetir la lectura
SELECT * FROM dbo.vw_SesionesBloqueadas;
SELECT * FROM dbo.vw_MonitorBloqueos ORDER BY sesion, tipo_recurso;
-- Sesión 2: RangeS-S en GRANT · Sesión 1: RangeI-N (inserción en rango) en WAIT

    SELECT registro_id, estudiante_id, estado
    FROM dbo.Registros_Matricula
    WHERE asignatura_id = 1;                       -- sigue en 1 fila: SIN FANTASMAS
GO

-- 4.4 (SESIÓN 2) Terminar. En ese instante el INSERT de la Sesión 1 se ejecuta.
COMMIT TRANSACTION;

SELECT registro_id, estudiante_id, estado
FROM dbo.Registros_Matricula
WHERE asignatura_id = 1;                           -- 2 filas (nueva transacción)
GO
-- → Ve a SESIÓN 1, paso 5.0


/* =====================================================================
   ESCENARIO 5 (VALOR AGREGADO) · INTERBLOQUEO (DEADLOCK) Y SU SOLUCIÓN
   ===================================================================== */

-- 5.2 (SESIÓN 2) Leer el mismo cupo (sigue en SERIALIZABLE)
BEGIN TRANSACTION;

    SELECT cupos_disponibles FROM dbo.Asignaturas WHERE asignatura_id = 1;   -- 5
GO
-- → Ve a SESIÓN 1, paso 5.3

-- 5.4 (SESIÓN 2) Intentar descontar el cupo.
-- Cada sesión espera a la otra: es un ciclo sin salida. En unos
-- segundos SQL Server elige una "víctima", le muestra el error 1205
-- y revierte su transacción. La otra sesión continúa.
UPDATE dbo.Asignaturas
SET cupos_disponibles = cupos_disponibles - 1
WHERE asignatura_id = 1;
GO

-- 5.5 (SESIÓN 2) SOLO si esta sesión NO recibió el error 1205:
-- SELECT @@TRANCOUNT;   -- si devuelve 1, ejecuta:
-- COMMIT TRANSACTION;
GO
-- → Ve a SESIÓN 1, paso 5.6

-- 5.7 (SESIÓN 2) Mismo patrón, ahora con UPDLOCK. Queda EN ESPERA
-- desde el SELECT, sin deadlock.
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

BEGIN TRANSACTION;

    SELECT cupos_disponibles
    FROM dbo.Asignaturas WITH (UPDLOCK)
    WHERE asignatura_id = 1;                       -- espera... luego devuelve 4
GO
-- → Ve a SESIÓN 1, paso 5.8

-- 5.9 (SESIÓN 2) Descontar y confirmar sobre el valor ya actualizado
    UPDATE dbo.Asignaturas
    SET cupos_disponibles = cupos_disponibles - 1
    WHERE asignatura_id = 1;

COMMIT TRANSACTION;                                -- cupos = 3

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;    -- dejar la sesión en su nivel normal
GO
-- → Ve a SESIÓN 1, paso 5.10
