/* =====================================================================
   SECCIÓN 3 · CONTROL DE BLOQUEOS Y NIVELES DE AISLAMIENTO
   Archivo 2 de 3 · VENTANA "SESIÓN 1"  (Estudiante A)
   ---------------------------------------------------------------------
   PREPARACIÓN
   1. Ejecuta primero 01_Esquema_y_Transacciones.sql completo.
   2. Abre este archivo en una ventana de consulta de SSMS y
      03_Sesion_2.sql en OTRA ventana. Cada ventana es una sesión
      (conexión) distinta, como dos estudiantes en dos computadoras.
   3. Los pasos están numerados de forma global (1.1, 1.2, 1.3...).
      Ejecuta los pasos en orden, alternando entre las dos ventanas.
      Cada paso dice en qué ventana va.
   4. Cuando una consulta queda "Executing query..." sin terminar,
      está BLOQUEADA esperando a la otra sesión. Es el comportamiento
      esperado: toma la captura y continúa con el siguiente paso.
   ===================================================================== */

USE MatriculacionUNACH;
GO

-- Anota este número: identifica a esta sesión en las vistas de bloqueos.
SELECT @@SPID AS id_sesion_1;
GO


/* =====================================================================
   ESCENARIO 1 · READ UNCOMMITTED  (lectura sucia)
   ===================================================================== */

-- 1.0 (SESIÓN 1) Restablecer escenario: Base de Datos con 5 cupos
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
UPDATE dbo.Asignaturas SET cupos_disponibles = 5 WHERE asignatura_id = 1;
DELETE FROM dbo.Registros_Matricula WHERE asignatura_id = 1 AND estudiante_id IN (4, 5);
SELECT asignatura_id, nombre_materia, cupos_disponibles FROM dbo.Asignaturas WHERE asignatura_id = 1;
GO

-- 1.1 (SESIÓN 1) El Estudiante A (id 4) empieza a matricularse, SIN COMMIT
BEGIN TRANSACTION;

    INSERT INTO dbo.Registros_Matricula (estudiante_id, asignatura_id, estado)
    VALUES (4, 1, 'PENDIENTE');

    UPDATE dbo.Asignaturas
    SET cupos_disponibles = cupos_disponibles - 1
    WHERE asignatura_id = 1;

    SELECT cupos_disponibles AS cupos_vistos_por_sesion_1
    FROM dbo.Asignaturas WHERE asignatura_id = 1;             -- 4
GO
-- → Ve a SESIÓN 2, paso 1.2

-- 1.3 (SESIÓN 1) El Estudiante A cancela su proceso
ROLLBACK TRANSACTION;

SELECT cupos_disponibles AS cupos_reales
FROM dbo.Asignaturas WHERE asignatura_id = 1;                 -- 5
GO
-- → Ve a SESIÓN 2, paso 1.4


/* =====================================================================
   ESCENARIO 2 · READ COMMITTED  (sin lectura sucia, con lectura no repetible)
   ===================================================================== */

-- 2.0 (SESIÓN 1) Restablecer escenario
UPDATE dbo.Asignaturas SET cupos_disponibles = 5 WHERE asignatura_id = 1;
DELETE FROM dbo.Registros_Matricula WHERE asignatura_id = 1 AND estudiante_id IN (4, 5);
GO

-- 2.1 (SESIÓN 1) Modificar el cupo SIN COMMIT
BEGIN TRANSACTION;

    UPDATE dbo.Asignaturas
    SET cupos_disponibles = cupos_disponibles - 1
    WHERE asignatura_id = 1;
GO
-- → Ve a SESIÓN 2, paso 2.2 (su consulta quedará en espera)

-- 2.3 (SESIÓN 1) Observar el bloqueo
-- La Sesión 2 aparece bloqueada por la Sesión 1.
SELECT * FROM dbo.vw_SesionesBloqueadas;

-- Sesión 1 tiene un bloqueo X (exclusivo) en estado GRANT;
-- Sesión 2 pide un bloqueo S (compartido) en estado WAIT.
SELECT * FROM dbo.vw_MonitorBloqueos ORDER BY sesion, tipo_recurso;
GO

-- 2.4 (SESIÓN 1) Cancelar. En ese instante la Sesión 2 recibe el valor 5.
ROLLBACK TRANSACTION;
GO
-- → Ve a SESIÓN 2, paso 2.5

-- 2.6 (SESIÓN 1) Otro estudiante confirma una matrícula (autocommit).
-- Termina de inmediato: en READ COMMITTED la Sesión 2 ya soltó su
-- bloqueo de lectura apenas terminó el SELECT.
UPDATE dbo.Asignaturas
SET cupos_disponibles = cupos_disponibles - 1
WHERE asignatura_id = 1;
GO
-- → Ve a SESIÓN 2, paso 2.7


/* =====================================================================
   ESCENARIO 3 · REPEATABLE READ  (lectura estable, pero con fantasmas)
   ===================================================================== */

-- 3.0 (SESIÓN 1) Restablecer escenario
UPDATE dbo.Asignaturas SET cupos_disponibles = 5 WHERE asignatura_id = 1;
DELETE FROM dbo.Registros_Matricula WHERE asignatura_id = 1 AND estudiante_id IN (4, 5);
GO
-- → Ve a SESIÓN 2, paso 3.1

-- 3.2 (SESIÓN 1) Intentar tomar un cupo. QUEDA BLOQUEADO porque la
-- Sesión 2 mantiene su bloqueo S hasta terminar la transacción.
UPDATE dbo.Asignaturas
SET cupos_disponibles = cupos_disponibles - 1
WHERE asignatura_id = 1;
GO
-- → Ve a SESIÓN 2, paso 3.3 (este UPDATE terminará en el paso 3.4)

-- 3.5 (SESIÓN 1) Confirmar que el UPDATE se aplicó al liberarse el bloqueo
SELECT cupos_disponibles FROM dbo.Asignaturas WHERE asignatura_id = 1;   -- 4
GO
-- → Ve a SESIÓN 2, paso 3.6

-- 3.7 (SESIÓN 1) Insertar una matrícula NUEVA en Base de Datos.
-- NO se bloquea: REPEATABLE READ protege las filas que ya se leyeron,
-- pero no impide que aparezcan filas nuevas.
INSERT INTO dbo.Registros_Matricula (estudiante_id, asignatura_id, estado)
VALUES (4, 1, 'PENDIENTE');
GO
-- → Ve a SESIÓN 2, paso 3.8


/* =====================================================================
   ESCENARIO 4 · SERIALIZABLE  (sin fantasmas: bloqueo de rango)
   ===================================================================== */

-- 4.0 (SESIÓN 1) Restablecer escenario
UPDATE dbo.Asignaturas SET cupos_disponibles = 5 WHERE asignatura_id = 1;
DELETE FROM dbo.Registros_Matricula WHERE asignatura_id = 1 AND estudiante_id IN (4, 5);
GO
-- → Ve a SESIÓN 2, paso 4.1

-- 4.2 (SESIÓN 1) Intentar la misma inserción del escenario 3.
-- Ahora SÍ QUEDA BLOQUEADA por el bloqueo de rango (RangeS-S).
INSERT INTO dbo.Registros_Matricula (estudiante_id, asignatura_id, estado)
VALUES (4, 1, 'PENDIENTE');
GO
-- → Ve a SESIÓN 2, paso 4.3 (este INSERT terminará en el paso 4.4)


/* =====================================================================
   ESCENARIO 5 (VALOR AGREGADO) · INTERBLOQUEO (DEADLOCK) Y SU SOLUCIÓN
   Patrón peligroso: "leo el cupo y luego lo actualizo".
   ===================================================================== */

-- 5.0 (SESIÓN 1) Restablecer escenario
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
UPDATE dbo.Asignaturas SET cupos_disponibles = 5 WHERE asignatura_id = 1;
DELETE FROM dbo.Registros_Matricula WHERE asignatura_id = 1 AND estudiante_id IN (4, 5);
GO

-- 5.1 (SESIÓN 1) Leer el cupo en SERIALIZABLE
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRANSACTION;

    SELECT cupos_disponibles FROM dbo.Asignaturas WHERE asignatura_id = 1;   -- 5
GO
-- → Ve a SESIÓN 2, paso 5.2

-- 5.3 (SESIÓN 1) Intentar descontar el cupo. Queda en espera:
-- la Sesión 2 también tiene un bloqueo S sobre la misma fila.
UPDATE dbo.Asignaturas
SET cupos_disponibles = cupos_disponibles - 1
WHERE asignatura_id = 1;
GO
-- → Ve a SESIÓN 2, paso 5.4

-- 5.5 (SESIÓN 1) SOLO si esta sesión NO recibió el error 1205:
-- SELECT @@TRANCOUNT;   -- si devuelve 1, ejecuta:
-- COMMIT TRANSACTION;
GO

-- 5.6 (SESIÓN 1) Solución: restablecer y leer con UPDLOCK
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
UPDATE dbo.Asignaturas SET cupos_disponibles = 5 WHERE asignatura_id = 1;
GO

BEGIN TRANSACTION;

    -- UPDLOCK: "leo esta fila porque la voy a modificar".
    -- Dos bloqueos U no son compatibles, así que el segundo estudiante
    -- espera desde la lectura y nunca se forma el ciclo del deadlock.
    SELECT cupos_disponibles
    FROM dbo.Asignaturas WITH (UPDLOCK)
    WHERE asignatura_id = 1;                                   -- 5
GO
-- → Ve a SESIÓN 2, paso 5.7 (su SELECT quedará en espera)

-- 5.8 (SESIÓN 1) Descontar y confirmar
    UPDATE dbo.Asignaturas
    SET cupos_disponibles = cupos_disponibles - 1
    WHERE asignatura_id = 1;

COMMIT TRANSACTION;                                            -- cupos = 4
GO
-- → Ve a SESIÓN 2, paso 5.9

-- 5.10 (SESIÓN 1) Verificación y limpieza final
SELECT cupos_disponibles FROM dbo.Asignaturas WHERE asignatura_id = 1;   -- 3: ningún descuento se perdió

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
UPDATE dbo.Asignaturas SET cupos_disponibles = 5 WHERE asignatura_id = 1;
DELETE FROM dbo.Registros_Matricula WHERE asignatura_id = 1 AND estudiante_id IN (4, 5);
GO
