# ⚙️ Motor de liquidación
### Qué hace el asistente, paso a paso

El motor trabaja siempre sobre **un cliente o un proveedor** y sobre **una divisa cada vez**. Lee sus movimientos abiertos y propone liquidaciones en varias pasadas, de la regla más segura a la menos segura. Cada pasada solo puede usar el importe que las pasadas anteriores no hayan reservado ya.

Cada propuesta queda etiquetada con dos datos: el **método de conciliación** (la regla que la generó) y la **confianza**. Los dos son informativos, nunca impiden registrar un grupo, y son la forma más rápida de saber qué paso ha producido cada propuesta cuando se prueba o se depura.

> En la aplicación estos valores se ven en la columna **Metodo de conciliacion** de la propuesta. Los textos de la interfaz están escritos sin tildes, por eso aquí aparecen entrecomillados tal y como se leen en pantalla.

---

## Resumen de los pasos

| # | Paso | Qué produce | Método de conciliación | Confianza |
|---|------|-------------|------------------------|-----------|
| 0 | Preparación de los movimientos | Nada visible: prepara la lista de trabajo | — | — |
| 1 | Referencia explícita | Grupos de liquidación | `Referencia explicita` | `Muy alta` |
| 2 | Coincidencia exacta 1:1 | Grupos de liquidación | `Exacto 1:1` | `Alta` |
| 3 | Coincidencia exacta 1:N | Grupos de liquidación | `Exacto 1:N` | `Alta` |
| 4 | Tolerancia de pago | Grupos de liquidación | `Tolerancia de pago` | `Media` |
| 5 | Clasificación de casos dudosos | Solo una etiqueta, ningún grupo | — (escribe **Tipo de candidato IA**) | — |
| 6 | Conciliación asistida por IA | Grupos de liquidación | `Asistido por IA` | `Alta` o `Media`, según la etiqueta |
| 7 | Reparto FIFO residual | Grupos de liquidación | `FIFO` | La configurada (`Baja` por defecto) |
| 8 | Ajustes del usuario | Movimientos añadidos a mano | `Manual` | En blanco |
| 9 | Registro | La liquidación real en el ERP | No cambia el del grupo | — |

Los pasos 1 a 7 se ejecutan **en este orden**: primero los pasos 1 a 5 para cada divisa, después el paso 6 recorre los casos dudosos uno a uno y, por último, el paso 7 vuelve a recorrer cada divisa. Lo que un paso reserva deja de estar disponible para los siguientes.

---

## Los pasos en detalle

### 0. Preparación de los movimientos
**Método de conciliación:** — · **Confianza:** —

- Se recogen todos los movimientos del cliente o del proveedor que estén **abiertos, no revertidos y con importe pendiente distinto de cero**.
- Se separan **por divisa**: el motor nunca cruza movimientos de divisas distintas.
- Dentro de cada divisa se ordenan **por fecha de registro**, del más antiguo al más reciente.
- Se guarda una foto del importe pendiente de cada movimiento en ese instante. A partir de ahí, el motor va descontando de esa foto lo que cada paso reserva.

**Cómo comprobarlo:** una propuesta recién creada nunca debe contener movimientos cerrados, revertidos, de otra divisa ni de otro cliente o proveedor.

---

### 1. Referencia explícita
**Método de conciliación:** `Referencia explicita` · **Confianza:** `Muy alta`

Es la regla más fiable, porque el propio movimiento dice a qué documento se refiere.

- Se busca esa referencia en cuatro sitios: el **nº de documento a liquidar**, la **referencia de pago**, el **nº de documento externo** y el **texto de la descripción**.
- En la descripción se busca el nº de documento (o el nº de documento externo) dentro del texto; se exige que tenga **al menos 3 caracteres** para no dar por buenas coincidencias casuales.
- El movimiento que lleva la referencia es el que liquida; los documentos referenciados son los liquidados. Si un mismo movimiento referencia varios documentos, se agrupan todos hasta agotar su importe, empezando por el más antiguo.
- **Este paso no mira las fechas:** una referencia explícita vale aunque los movimientos estén separados por meses.

**Qué se controla con los importes:** en este paso **no se exige que los importes coincidan**. Quien decide el emparejamiento es la referencia; el importe solo decide **cuánto** se liquida:

- Los dos movimientos deben tener **saldo libre** (importe pendiente todavía no reservado) y ser de **sentido contrario**. Eso es todo lo que se exige.
- Se liquida siempre **el menor de los dos saldos**, así que una referencia puede resolver el caso entero o solo una parte.
- Si el documento referenciado es **mayor**, se liquida lo que alcance y el documento **sigue abierto por el resto**. Ejemplo: pago de 600 que referencia una factura de 1.000 → se propone 600 y la factura conserva 400 abiertos.
- Si el movimiento que lleva la referencia es **mayor**, se queda con saldo sobrante que pasa a los pasos siguientes. Ejemplo: pago de 1.000 que referencia una factura de 600 → se propone 600 y al pago le quedan 400 libres, que intentarán resolver los pasos 2 a 7 (y que el paso 5 suele etiquetar como `Coincidencia parcial`).
- Cuando la referencia apunta a varios documentos, se reparte por orden de antigüedad hasta agotar el saldo: los documentos más antiguos se liquidan primero y el último puede quedar liquidado solo en parte.

**No hace nada cuando:** el movimiento no lleva ninguna referencia, el documento referenciado ya está cerrado o sin saldo libre, o ambos movimientos van en el mismo sentido (dos facturas, dos pagos…).

---

### 2. Coincidencia exacta 1:1
**Método de conciliación:** `Exacto 1:1` · **Confianza:** `Alta`

Empareja un movimiento con otro del sentido contrario por el mismo importe exacto.

- Solo se propone cuando la pareja es **inequívoca**: debe haber **un único candidato del lado contrario y un único candidato de su mismo lado**.
- Esa doble comprobación evita el caso clásico de dos facturas del mismo importe: si no se sabe cuál de las dos paga el cobro, el motor prefiere no elegir.
- Se respeta el límite **Dif. max. de fechas para conciliar (dias)** de la configuración; si está en blanco, no hay límite de fechas.
- El **movimiento más reciente** es el que liquida, porque normalmente es el que consume un saldo que ya existía.

**No hace nada cuando:** hay ambigüedad por cualquiera de los dos lados, o los movimientos están más separados en el tiempo que el límite configurado.

---

### 3. Coincidencia exacta 1:N
**Método de conciliación:** `Exacto 1:N` · **Confianza:** `Alta`

Un movimiento cuyo importe coincide exactamente con **la suma de varios** movimientos contrarios (un cobro que salda tres facturas, por ejemplo).

- La búsqueda está acotada a propósito: se examina un número limitado de candidatos y el número de movimientos por combinación no puede superar el valor **Max. lineas por combinacion** de la configuración.
- Solo se propone si existe **una única combinación posible**. En cuanto aparece una segunda, el caso se considera ambiguo y se deja para los pasos siguientes.
- Si el movimiento único es el **más reciente**, el resultado es un solo grupo con varios movimientos liquidados.
- Si el movimiento único es el **más antiguo** (por ejemplo, una factura saldada por varios pagos), se generan **varios grupos**, uno por cada pago, cada uno con su parte de la factura. Así cada grupo puede registrarse por separado.
- También se respeta el límite de diferencia de fechas al elegir los candidatos.

**No hace nada cuando:** hay más de una combinación válida, la combinación necesitaría más líneas de las permitidas, o los movimientos superan el límite de fechas.

---

### 4. Tolerancia de pago
**Método de conciliación:** `Tolerancia de pago` · **Confianza:** `Media`

Cubre las diferencias pequeñas: un pago de 999,50 contra una factura de 1.000.

- **Solo se ejecuta si la tolerancia de pago está configurada en el ERP.** El asistente no tiene un parámetro propio de tolerancia: usa el estándar y respeta la tolerancia máxima que el ERP ya ha calculado para cada movimiento.
- La diferencia entre ambos importes debe ser distinta de cero y no superar esa tolerancia.
- Igual que en el paso 2, solo se propone si hay **un único candidato**, y se respeta el límite de diferencia de fechas.

**No hace nada cuando:** la tolerancia de pago no está activada, la diferencia se pasa del margen, o hay varios candidatos posibles.

---

### 5. Clasificación de los casos dudosos
**Método de conciliación:** — · **Confianza:** —

Este paso **no propone nada**: solo pone nombre a lo que las reglas anteriores no han sabido resolver, para poder medirlo y, más adelante, tratarlo con ayuda de IA.

Cada movimiento que sigue con saldo libre recibe una etiqueta en **Tipo de candidato IA**:

| Etiqueta | Qué significa |
|----------|---------------|
| `Varias coincidencias exactas` | Encaja por importe con más de un movimiento; elegir uno sería arbitrario |
| `Referencia textual` | Su texto apunta a un documento, pero la referencia no bastó para cerrar el caso |
| `Coincidencia parcial` | Ya se le reservó parte del importe, pero le queda saldo suelto |
| `Residual sin clasificar` | Queda abierto sin ningún indicio aprovechable |

La etiqueta viaja con el movimiento y se queda escrita en las líneas que generen los pasos siguientes, así que sigue siendo visible en la propuesta final.

**Cómo usarlo al depurar:** si un caso que esperaba resolverse aparece como `Varias coincidencias exactas`, el motor ha funcionado bien y lo que falta es un dato que desambigüe (una referencia, o unas fechas más ajustadas).

---

### 6. Conciliación asistida por IA
**Método de conciliación:** `Asistido por IA` · **Confianza:** la configurada por tipo de candidato (`Alta` / `Media`)

Última oportunidad antes del FIFO, y el único paso que no es determinista.

- Se activa con la casilla **Activar conciliación con IA** de la configuración. **Viene desactivada**: sin activarla, el motor se comporta exactamente igual que antes.
- Solo se envían los casos etiquetados como `Varias coincidencias exactas`, `Referencia textual` y `Coincidencia parcial`. `Residual sin clasificar` y `No necesario` nunca se envían.
- **Un caso = una consulta.** Cada caso lleva únicamente el movimiento que liquida y el pequeño grupo de candidatos que el motor ya había preseleccionado: mismos filtros de divisa, signo contrario, límite de fechas y antigüedad que usan los pasos deterministas.
- El modelo decide **una sola cosa**: cuáles de esos candidatos liquida el movimiento. No elige el movimiento liquidador, no ve ninguna tabla y no propone ninguna confianza.
- **Que los importes cuadren no es evidencia.** Todos los candidatos cuadran ya, por construcción; lo que debe distinguirlos es el número de documento, la referencia, la descripción o las fechas.
- **No resolver es un resultado esperado y correcto.** Si el modelo no ve evidencia suficiente, no propone nada y el caso baja al FIFO como siempre.
- Lo que el modelo propone **se vuelve a validar en AL** antes de crear nada: que el movimiento estuviera entre los candidatos de ese caso, que siga abierto, que tenga saldo, que no se asigne de más. El grupo se crea con las mismas comprobaciones que un grupo manual.
- Si la IA no está configurada, no responde o falla, **el caso simplemente no se resuelve**: la propuesta se genera igual, con FIFO.

| Etiqueta de origen | Confianza del grupo | Campo de configuración |
|--------------------|---------------------|------------------------|
| `Varias coincidencias exactas` | `Alta` | **Confianza IA varias coincidencias exactas** |
| `Referencia textual` | `Alta` | **Confianza IA referencia textual** |
| `Coincidencia parcial` | `Media` | **Confianza IA coincidencia parcial** |

El **Tipo de candidato IA** original se conserva en las líneas del grupo, así que en la propuesta final se ve tanto que lo resolvió la IA como qué duda resolvió.

**Cómo aislarlo en una prueba:** desactivando **Activar conciliación con IA** se reproduce el resultado determinista exacto. Con ella activada y el FIFO desactivado se ve solo lo que ha aportado la IA.

---

### 7. Reparto FIFO residual
**Método de conciliación:** `FIFO` · **Confianza:** la del campo **Confianza por defecto de FIFO** (`Baja` por defecto)

Última pasada, la menos fiable, pensada para que no quede saldo compatible sin proponer.

- Se activa o desactiva con la casilla **Activar FIFO residual** de la configuración.
- Reparte los saldos que quedan **empezando por el movimiento más antiguo**.
- Cada movimiento solo se reparte contra movimientos **anteriores a él**, de modo que el más reciente siempre queda como el que liquida.
- **No exige que los importes cuadren**: reparte hasta donde llegue y deja saldos parciales abiertos, que es justo lo que haría una persona cerrando por antigüedad.
- Este paso **no aplica el límite de diferencia de fechas**; su criterio es la antigüedad, no la cercanía.

**Cómo aislarlo en una prueba:** desactivando **Activar FIFO residual** se ve exactamente qué ha resuelto el motor determinista y qué quedaba suelto.

---

### 8. Ajustes del usuario
**Método de conciliación:** `Manual` · **Confianza:** en blanco

Nada se registra sin pasar por la revisión de una persona.

- El usuario puede **añadir** movimientos a un grupo o **quitarlos**. Los que añade a mano se marcan como `Manual` y **no reciben ninguna confianza inventada**.
- El movimiento que liquida conserva el método con el que se propuso, y el grupo queda marcado como **modificado manualmente**.
- Al añadir, solo se ofrecen movimientos compatibles: mismo cliente o proveedor, misma divisa, sentido contrario y con saldo libre.
- Si se quita el último movimiento liquidado, el grupo desaparece: un grupo sin contrapartida no se puede registrar.

---

### 9. Registro
**Método de conciliación:** el que ya tuviera el grupo (no se modifica)

- Cada grupo se registra **por separado**. Si uno falla, los demás no se ven afectados y la propuesta queda como registrada parcialmente.
- Justo antes de registrar se **vuelven a leer los movimientos reales**: los importes guardados en la propuesta son una foto, no la verdad actual. Se comprueba que siguen abiertos, que pertenecen al mismo cliente o proveedor, que comparten divisa y que todavía tienen importe suficiente.
- La liquidación la hace el **proceso estándar del ERP**, igual que si se hiciera a mano, con su tratamiento habitual de tolerancias y redondeos.
- Si los movimientos del cliente o proveedor cambian por fuera mientras tanto, la propuesta se marca **obsoleta** y hay que regenerarla.

---

## Reglas que se cumplen en todos los pasos

1. **Nunca se cruzan clientes o proveedores distintos, ni divisas distintas.**
2. **Un importe reservado no se vuelve a ofrecer.** Lo que un paso aparta deja de estar disponible para los siguientes.
3. **Siempre se liquidan movimientos de sentido contrario:** un cargo contra un abono, nunca dos del mismo signo.
4. **Ningún movimiento se sobreasigna:** lo propuesto nunca supera su importe pendiente real.
5. **Que los importes coincidan solo se exige en los pasos 2, 3 y 4.** La referencia explícita (paso 1), la IA (paso 6) y el FIFO (paso 7) liquidan el menor de los dos saldos y admiten liquidaciones parciales; los importes ahí limitan, no emparejan.
6. **Ante la duda, no se propone.** Si hay varias soluciones igual de válidas, el motor prefiere dejar el caso al usuario antes que elegir por él.
7. **El más reciente liquida.** Cuando no hay una referencia que marque la dirección, el movimiento más nuevo toma el papel de liquidador.
8. **El método y la confianza son informativos.** No condicionan ni bloquean el registro; sirven para revisar, filtrar y depurar.
9. **Nada se registra automáticamente.** El motor propone; la persona decide.

---

## Guía rápida para probar y depurar

| Si quiero probar… | Preparo… | Espero ver |
|-------------------|----------|------------|
| Referencia por descripción o nº externo | Un pago cuyo texto contenga el nº de la factura | `Referencia explicita` |
| Referencia con importes distintos | Un pago de 1.000 que referencia una factura de 600 | `Referencia explicita` por 600, y 400 libres para los pasos siguientes |
| Pareja limpia por importe | Una factura y un pago del mismo importe, sin referencias | `Exacto 1:1` |
| Ambigüedad por importe | Dos facturas del mismo importe y un solo pago | Ningún grupo exacto y la etiqueta `Varias coincidencias exactas` |
| Un pago que salda varias facturas | Facturas de 600 y 400 y un pago posterior de 1.000 | `Exacto 1:N`, un solo grupo |
| Varios pagos contra una factura | Factura de 1.000 anterior, pagos de 600 y 400 | `Exacto 1:N`, dos grupos |
| Diferencia pequeña | Tolerancia activada en el ERP y un pago de 999,50 contra 1.000 | `Tolerancia de pago` |
| Cierre por antigüedad | Saldos sueltos que no cuadran entre sí, con FIFO activado | `FIFO` |
| Que un paso no interfiera | Desactivar FIFO, o bajar el límite de fechas o de líneas por combinación | Menos grupos, o ninguno |
