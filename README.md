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

**Autor:** Lenin Vladimir · Administración de Bases de Datos
