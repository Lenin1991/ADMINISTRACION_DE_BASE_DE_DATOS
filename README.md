# Administración de Bases de Datos

Repositorio de las actividades de la asignatura **Administración de Bases de Datos**.

---

## Unidad 1 · Tema 1: Concurrencia y consistencia en un sistema de matriculación universitaria

Base de datos de matrícula en **Microsoft SQL Server** para estudiar dos preguntas: cómo se cumplen las propiedades **ACID** y qué ve cada estudiante, según el **nivel de aislamiento**, cuando otro se matricula al mismo tiempo.

### Archivos

| Archivo | Contenido |
| --- | --- |
| [`01_Esquema_y_Transacciones.sql`](01_Esquema_y_Transacciones.sql) | Creación de la base, tablas con restricciones, datos de prueba, transacciones A (COMMIT), B (ROLLBACK) y C (atomicidad multimateria), vistas de monitoreo de bloqueos y procedimiento `sp_MatricularEstudiante`. |
| [`02_Sesion_1.sql`](02_Sesion_1.sql) | Pasos de la **Sesión 1** (Estudiante A) para las pruebas de concurrencia. |
| [`03_Sesion_2.sql`](03_Sesion_2.sql) | Pasos de la **Sesión 2** (Estudiante B) para las pruebas de concurrencia. |

### Modelo de datos

```
Estudiantes (estudiante_id PK, nombre, cedula UNIQUE, facultad)
      │ 1
      │
      │ N
Registros_Matricula (registro_id PK, estudiante_id FK, asignatura_id FK,
                     fecha_registro, estado ∈ {CONFIRMADA, PENDIENTE})
      │ N             UNIQUE (estudiante_id, asignatura_id)
      │
      │ 1
Asignaturas (asignatura_id PK, nombre_materia UNIQUE, docente,
             cupos_disponibles CHECK >= 0)
```

### Requisitos

- Microsoft SQL Server 2016 SP1 o superior (probado en SQL Server 17.0 RTM).
- SQL Server Management Studio (SSMS).
- Un usuario con permiso para crear bases de datos y `VIEW SERVER STATE`, necesario para las vistas de monitoreo.

### Cómo ejecutarlo

1. Abre `01_Esquema_y_Transacciones.sql` en SSMS y ejecútalo **por bloques**: selecciona cada bloque y presiona `F5`. El script borra y recrea la base `MatriculacionUNACH`, así que siempre parte de un estado limpio.
2. Abre `02_Sesion_1.sql` y `03_Sesion_2.sql` en **dos pestañas distintas**. Cada pestaña es una conexión diferente; compruébalo con `SELECT @@SPID`, que debe devolver números distintos.
3. Sigue los pasos numerados (1.0, 1.1, 1.2…) alternando entre las pestañas. Cada paso indica en qué ventana va.
4. Si una consulta se queda en **"Ejecutando consulta…"**, está bloqueada a propósito. No la canceles y pasa a la otra pestaña.

### Resultados obtenidos

| Prueba | Resultado |
| --- | --- |
| Transacción A (COMMIT) | Matrícula confirmada y cupo de 6 a 5 en una sola unidad. |
| Transacción B (ROLLBACK) | El registro desaparece tras el error 207. `IDENT_CURRENT` queda en 2: el ROLLBACK no devuelve los números IDENTITY. |
| Transacción C (atomicidad) | Error 50001. Cupos 5 → 4 → 5 y 10 → 9 → 10: no queda una matrícula a medias. |
| READ UNCOMMITTED | **Lectura sucia**: la Sesión 2 vio 4 cupos que nunca se confirmaron. |
| READ COMMITTED | Sin lectura sucia (espera `LCK_M_S`), pero con **lectura no repetible**: 5 → 4 en la misma transacción. |
| REPEATABLE READ | El UPDATE de la otra sesión esperó 2 min 17 s, pero hubo **lectura fantasma**: 1 → 2 filas. |
| SERIALIZABLE | Bloqueo de rango `RangeS-S` / `RangeI-N` (`LCK_M_RIn_NL`). **Sin fantasmas**. |
| Deadlock | Error 1205: SQL Server eligió una sesión como víctima. |
| Solución con `UPDLOCK` | La segunda sesión espera desde la lectura. Cupos 5 → 4 → 3, sin deadlock ni descuentos perdidos. |
| `sp_MatricularEstudiante` | Descuento atómico (`WHERE cupos_disponibles > 0`). Rechaza cupos agotados (50011), duplicados (2627) y asignaturas inexistentes (50010) sin consumir cupos. |

### Hallazgos clave

- **Un error no revierte la transacción por sí solo.** Después del error 207, `@@TRANCOUNT` seguía en 1. Por eso se usan `TRY/CATCH` y `SET XACT_ABORT ON`.
- **Un `UPDATE` sobre un ID inexistente no es un error**: afecta 0 filas. Hay que validar `@@ROWCOUNT` y lanzar el error con `THROW`.
- **READ COMMITTED + escritura atómica** es el mejor equilibrio para la matrícula: evita datos sin confirmar y la sobreventa de cupos, sin las esperas de SERIALIZABLE.

---

## Unidad 1 · Tema 2: Vistas, funciones, procedimientos y triggers en el sistema de matrículas

Sobre el mismo modelo de matrícula se agregan objetos programables para consultar la oferta, calcular costos, inscribir y retirar materias de forma atómica y auditar automáticamente cada cambio.

### Archivo

| Archivo | Contenido |
| --- | --- |
| [`Unidad1_Tema2/Tema2_Programacion_SQL.sql`](Unidad1_Tema2/Tema2_Programacion_SQL.sql) | Script autocontenido: crea la base `MatriculacionUNACH_T2`, las tablas, 3 vistas, 3 funciones, 3 procedimientos y 3 triggers, carga los datos e incluye las pruebas de éxito, de error y de seguridad. |

### Objetos implementados

| Tipo | Objeto | Qué hace |
| --- | --- | --- |
| Tabla | `Auditoria_Matriculas` | Bitácora de MATRICULACIÓN y RETIRO con login, usuario de BD, fecha, equipo y aplicación. |
| Tabla | `Historial_Cupos` | Cambios manuales de cupo (anterior → nuevo, fecha y usuario). |
| Vista | `Vista_OfertaAcademica` | Materias con cupo, docente y porcentaje de ocupación. |
| Vista | `Vista_DetalleMatricula` | Estudiante, facultad, materia, docente y fecha. |
| Vista | `Vista_EstudiantesSaturados` | Estudiantes con más de 5 materias. |
| Función escalar | `fn_CalcularCostoMatricula` | `DECIMAL(10,2)`: USD 15,00 por materia confirmada. |
| Función escalar | `fn_VerificarDisponibilidad` | `BIT`: 1 si hay cupo, 0 si no hay o la materia no existe. |
| Función de tabla en línea | `fn_ListaClase` | Lista de clase (nombre, cédula, facultad) de una asignatura. |
| Procedimiento | `sp_InscribirAsignatura` | Valida, bloquea la fila con `UPDLOCK`, inserta y descuenta el cupo en una transacción con `TRY/CATCH` y `XACT_ABORT`. |
| Procedimiento | `sp_RetirarAsignatura` | Elimina la matrícula, devuelve el cupo y registra el RETIRO. |
| Procedimiento | `sp_ReporteCargaDocente` | Materias, estudiantes y promedio por docente, con filtro opcional. |
| Trigger | `tr_AuditoriaMatricula_Insert` | `AFTER INSERT`: audita cada matrícula (procesa todas las filas a la vez). |
| Trigger | `tr_ValidarCupoNegativo` | `INSTEAD OF UPDATE`: rechaza toda la instrucción si algún cupo quedaría negativo (error 50020). |
| Trigger | `tr_LogCambioCupo` | `AFTER UPDATE`: registra solo los cambios manuales; ignora los de los procedimientos mediante `SESSION_CONTEXT`. |

### Cómo ejecutarlo

1. Abre `Tema2_Programacion_SQL.sql` en SSMS.
2. Selecciona desde el inicio hasta el final de la **Sección 6** y presiona `F5`. Debe devolver `20 | 20 | 0` (matrículas, auditoría, historial).
3. Ejecuta las secciones 7, 8 y 9 **bloque por bloque** (cada prueba termina en `GO`).

### Resultados obtenidos (SQL Server 2025, v17.0)

| Prueba | Resultado |
| --- | --- |
| Vistas | Oferta sin Seminario (0 cupos); 20 matrículas en el detalle; solo Ana Lucía (6 materias) aparece como saturada. |
| Funciones | Costos de 90.00 a 0.00 (tipo `decimal(10,2)`); disponibilidad 0 en Seminario y en la asignatura 999; lista de clase usable con `CROSS APPLY`. |
| Inscripción y retiro | Cupo de Redes 17 → 16 → 17; la auditoría registra MATRICULACIÓN (trigger) y RETIRO (procedimiento). |
| Cambio manual de cupo | Base de Datos 26 → 35 queda en `Historial_Cupos`; las 22 operaciones de los procedimientos no se duplican allí. |
| Errores de los procedimientos | 50011 sin cupo, 50012 duplicado, 50010 asignatura inexistente, 50013 estudiante inexistente, 50014 retiro inexistente. |
| Trigger de cupo negativo | Error 50020 al dejar Seminario en −1; un `UPDATE` masivo de −15 se rechaza completo (no cambia ninguna materia). |
| Atomicidad | Tras los errores: 20 matrículas, 22 filas de auditoría, 1 en el historial y `@@TRANCOUNT = 0`. |
| Seguridad por roles | El usuario de la aplicación recibe el error 229 al insertar en la tabla, pero matricula con el procedimiento (ownership chaining). |
| Inyección SQL | `'8; DROP TABLE dbo.Estudiantes;--'` produce el error 8114 (conversión a `int`); la tabla sigue con 8 estudiantes. |

---

## Unidad 2 · Tema 1: Fundamentos de recuperación (AA3)

Base `RecuperacionLogistica` de una empresa de comercio electrónico: consistencia de datos, control de concurrencia entre dos operadores, cadena de respaldos (Full, Diferencial y Log) y un plan de recuperación probado con una restauración a un punto en el tiempo.

### Archivos

| Archivo | Contenido |
| --- | --- |
| [`Unidad2_Tema1/01_RecuperacionLogistica.sql`](Unidad2_Tema1/01_RecuperacionLogistica.sql) | Secciones 1, 2, 4 y 5: base y tablas, restricciones y trigger, pruebas válidas e inválidas, respaldos, incidente simulado, restauración de prueba y función de tabla del anexo. |
| [`Unidad2_Tema1/02_Operador_A.sql`](Unidad2_Tema1/02_Operador_A.sql) | Sección 3, ventana del operador A (transacciones de modificación y de reporte). |
| [`Unidad2_Tema1/03_Operador_B.sql`](Unidad2_Tema1/03_Operador_B.sql) | Sección 3, ventana del operador B (lecturas y cambios concurrentes, con `LOCK_TIMEOUT` de 5 s). |

### Cómo ejecutarlo

1. Ejecuta las secciones 1 y 2 de `01_RecuperacionLogistica.sql`.
2. Abre `02` y `03` en **dos pestañas** de SSMS y ejecuta los pasos en este orden: A1 → B1 → A2 → A3 → B3 → A4+A5 → B5 → A6 → A7 → B7 → A8 → A9 → B9 → A10 → B11.
3. Ejecuta las secciones 4 y 5 de `01` **bloque por bloque y en la misma pestaña** (la hora segura del incidente se guarda en una tabla temporal global de esa sesión).

### Resultados obtenidos (SQL Server 2025 Developer, v17.0)

| Bloque | Resultado |
| --- | --- |
| Consistencia | 7 intentos inválidos bloqueados: peso negativo y cero, costo cero, sucursal 99 y borrar una sucursal con paquetes (error 547); Cuenca llena (trigger, error 50001); una transacción de 3 filas con una inválida no deja ninguna. |
| Lectura sucia | Con `READ UNCOMMITTED`, B leyó 999.99 / DEVUELTO, un valor que A luego revirtió; con `READ COMMITTED`, B esperó 5 006 ms y recibió el error 1222. |
| Lectura no repetible | Con `READ COMMITTED`, el reporte de Quito pasó de 45.40 a 65.40 dentro de la misma transacción. |
| Fantasma | Con `REPEATABLE READ`, B no pudo cambiar costos (1222), pero insertó un paquete y el reporte pasó de 4 a 5 filas. |
| `SERIALIZABLE` | 6 bloqueos `RangeS-S`: B no pudo insertar en Quito (1222), sí en Guayaquil, y ambas lecturas de A fueron idénticas. |
| Respaldos | Full 5 264 KB → 825 KB comprimido; Diferencial 1 616 → 221 KB; Log 1 140 → 41 KB; Log 2 76 → 18 KB. Los cuatro superan `RESTORE VERIFYONLY`. |
| Restauración | Full + Diferencial + Log 1 + Log 2 con `STOPAT` en una base de prueba en 13,1 s: recupera los 7 paquetes borrados por error y conserva la operación legítima previa; `DBCC CHECKDB` sin errores. |

## Unidad 2 · Tema 2 (AA4): Recuperación en gestores de BD

Caso: farmacia «Salud Andina» (Riobamba), mismas 4 tablas en **SQL Server 2025** y **PostgreSQL 19**: logs de transacciones, UNDO/REDO, log shipping, conmutación por falla y recuperación a un punto en el tiempo (PITR).

### Archivos

| Archivo | Contenido |
| --- | --- |
| [`Unidad2_Tema2/01_SQLServer_FarmaciaDB.sql`](Unidad2_Tema2/01_SQLServer_FarmaciaDB.sql) | Base FarmaciaDB (modelo FULL), lectura del log con `fn_dblog`, UNDO y REDO, log shipping manual con `STANDBY`, PITR con `STOPAT` y conmutación con respaldo de la cola del log. |
| [`Unidad2_Tema2/02_SQLServer_Sesion_B.sql`](Unidad2_Tema2/02_SQLServer_Sesion_B.sql) | Segunda pestaña de SSMS: transacción sin confirmar para demostrar el UNDO en la restauración. |
| [`Unidad2_Tema2/03_PostgreSQL_farmacia_db.sql`](Unidad2_Tema2/03_PostgreSQL_farmacia_db.sql) | Base farmacia_db, archivado del WAL, lectura con `pg_walinspect`, UNDO, borrado erróneo, búsqueda forense y reparación desde la instancia restaurada. |
| [`Unidad2_Tema2/04_PostgreSQL_consola.txt`](Unidad2_Tema2/04_PostgreSQL_consola.txt) | Comandos de PowerShell: reinicio del servicio, `pg_basebackup` y restauración con `recovery_target_time`. |

### Cómo ejecutarlo

1. SQL Server: ejecuta `01` bloque por bloque; en el paso B1 abre `02` en otra pestaña y deja la transacción abierta hasta el paso B2.
2. PostgreSQL: ejecuta `03` en el Query Tool de pgAdmin (cada `ALTER SYSTEM` por separado) y, en los puntos marcados `[CONSOLA]`, los comandos de `04` en PowerShell.

### Resultados obtenidos

| Bloque | Resultado |
| --- | --- |
| UNDO / REDO | SQL Server: 8 compensaciones + `LOP_ABORT_XACT`; restauración con 102 transacciones rehechas y 1 deshecha. PostgreSQL: transacción 678 `aborted`. |
| Log shipping | Secundaria en `STANDBY` sincronizada (9 ventas / 118,00 USD), solo lectura (error 3906); conmutación en 0,65 s sin pérdida de datos. |
| PITR SQL Server | `DELETE` de 9 filas replicado por el log shipping; `STOPAT` a 23:16:23.750 en 1,5 s recupera las 15 líneas. |
| PITR PostgreSQL | `recovery_target_time` = 23:41:37.246426-05 con `inclusive = false`: se detiene antes de la transacción 680, timeline 2, 12 líneas recuperadas. |

---

**Autor:** Lenin Vladimir · Administración de Bases de Datos
