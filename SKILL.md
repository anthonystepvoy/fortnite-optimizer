---
name: fortnite-optimization
description: Audit, diagnose, optimize, and validate Fortnite performance on Windows PCs. Use for low or unstable FPS, frame-time spikes, stutter, input delay, high ping or jitter, Performance Mode tuning, competitive settings, GPU/CPU/RAM/storage bottlenecks, DIMM-slot or dual-channel checks, PCIe lane/link checks, ReBAR, BIOS and driver updates, background processes, overlays, replays, custom Windows builds such as KernelOS/Atlas/ReviOS, broken Windows Update, or a complete evidence-backed gaming-PC health sweep.
---

# Fortnite Optimization

Diagnosticar primero, modificar después y validar siempre con datos comparables. Responder en el idioma del usuario.

## Reglas obligatorias

- Anunciar que se está usando esta skill y qué acción provoca.
- No cerrar Fortnite, el launcher, un stream ni otra aplicación si el usuario no lo autorizó. Si hay una partida activa, limitarse a lecturas y captura de métricas.
- No reiniciar automáticamente. Avisar qué quedó pendiente y dejar que el usuario decida cuándo reiniciar.
- No cambiar Performance Mode si el usuario pidió conservarlo.
- No flashear BIOS desde Windows mientras se juega ni con un sistema inestable. Usar la utilidad UEFI de la placa y el archivo exacto para modelo y revisión.
- No aplicar paquetes de tweaks, `.reg` ajenos, temporizadores HPET/BCD, Nagle, prioridad en tiempo real, afinidades fijas ni desactivaciones masivas sin evidencia y prueba A/B.
- No desactivar Defender, firewall, VBS/Memory Integrity, mitigaciones o servicios de actualización sin explicar el riesgo y obtener consentimiento explícito.
- No editar ACL, manifiestos, registro de COMPONENTS ni archivos de WinSxS a mano. No eliminar paquetes permanentes.
- No formatear USB, particiones ni hacer instalación limpia sin autorización explícita y verificación del destino.
- Respaldar antes de escribir; registrar cada cambio, valor anterior, reinicio requerido y método de reversión.
- Separar FPS/frametime de ping/jitter. Una caída de FPS no es un problema de red y un pico de ping no se arregla cambiando la GPU.
- Investigar versiones, BIOS, drivers, parches y recomendaciones actuales antes de actuar: fuentes oficiales primero; foros/Reddit solo como evidencia secundaria y claramente rotulada.

## Niveles de acción

1. **L0 — solo lectura:** inventario, logs, métricas, estado de juego, hardware, firmware, servicios y red. Ejecutar sin cerrar el juego.
2. **L1 — reversible sin reinicio:** ajustes del juego, overlays, replays, procesos de fondo autorizados, energía por aplicación y limpieza controlada.
3. **L2 — reversible con reinicio o coste de seguridad:** drivers, HAGS, VBS, servicios, Windows Update y firmware. Pedir consentimiento y crear respaldo.
4. **L3 — firmware/destructivo:** BIOS, borrado de cachés de servicio, USB booteable, cambio de edición o instalación limpia. Confirmar modelo, rutas, discos, copias y energía estable.

## Flujo obligatorio

### 1. Congelar el contexto y crear la línea base

- Detectar si Fortnite está abierto y si el usuario está en partida.
- Registrar objetivo: monitor/Hz, resolución, modo de render, límite de FPS, VRR/V-Sync, sensación buscada y si prioriza competencia, imagen o estabilidad.
- Registrar escenario de prueba: lobby, Creative, replay o partida; streaming/OBS/navegador; primera partida tras parche; red usada.
- Ejecutar `scripts/collect-fortnite-audit.ps1`. Usar `-IncludeServicingHealth` solo si se investigan Windows Update o imágenes personalizadas.
- Si el juego está abierto, ejecutar `scripts/capture-fortnite-session.ps1` durante 120–300 segundos. Este script no mide FPS: combinarlo con estadísticas de Fortnite, PresentMon o CapFrameX.
- Medir al menos promedio, 1% low, 0.1% low y frametime; repetir tres veces cuando sea práctico y comparar medianas.

### 2. Auditar hardware y firmware

Leer [hardware-firmware.md](references/hardware-firmware.md) antes de recomendar cambios físicos o BIOS.

- Confirmar CPU, GPU, placa exacta/revisión, BIOS/fecha, fuente y temperaturas/clocks/potencia bajo carga.
- Enumerar todos los DIMM: capacidad, ranura, velocidad configurada y número de slots. Verificar manual de placa; con dos módulos suele corresponder A2/B2, pero no asumirlo.
- Confirmar doble canal con HWiNFO/CPU-Z/firmware cuando SMBIOS no lo demuestre.
- Confirmar que la GPU está en la ranura primaria conectada a CPU y negociar ancho/generación correctos bajo carga. No juzgar la generación actual estando en reposo.
- Comprobar ReBAR, Above 4G Decoding, UEFI/CSM, XMP/EXPO, estabilidad de RAM, temperaturas, throttling y salud/espacio del SSD.

### 3. Clasificar el cuello de botella

| Evidencia | Diagnóstico probable | Próximo control |
|---|---|---|
| GPU 95–99%, clocks/temperatura normales | GPU-bound | Resolución, 3D resolution, clocks, power limit, driver |
| GPU baja y un núcleo/hilo al límite | Game-thread/CPU-bound | procesos, RAM, cap, replays, asset streaming, versión del juego |
| Clocks caen con temperatura o límites | térmico/potencia | cooler, airflow, pasta, PSU, límites BIOS |
| RAM single-channel, baja frecuencia o paging | memoria | slots, XMP, estabilidad, pagefile |
| Disco al 100% durante tirones | streaming/almacenamiento | SSD, espacio, salud, replays, assets |
| Spike coincide con navegador, stream, OBS, emulador u overlay | contención de fondo | prueba A/B cerrando solo lo autorizado |
| FPS estable pero RTT/jitter/loss sube | red/ruta | Ethernet, router/SQM, ISP, región |

No recomendar una GPU nueva hasta demostrar GPU-bound. En Performance Mode es normal ver GPU holgada cuando manda el game thread.

### 4. Auditar y optimizar Windows

Leer [windows-servicing.md](references/windows-servicing.md) antes de tocar servicios, seguridad, drivers o Windows Update.

- Detectar Windows oficial versus imagen modificada, edición/build/canal/licencia, políticas, pausas, servicios, tareas, Defender y salud de componentes.
- Revisar Inicio, Run/RunOnce, Startup folders y tareas no Microsoft; investigar aperturas automáticas de Chrome/PWA/URLs como Waze.
- Identificar overlays y procesos de impacto: NVIDIA App/Share, Game Bar, Discord, Steam, Overwolf, OBS, navegadores/streams, emuladores Android y launchers.
- Mantener pagefile administrado por el sistema en SSD; no desactivarlo.
- Probar Game Mode activado. Tratar HAGS, Reflex, plan de energía y Memory Integrity como variables A/B, no dogmas.
- Usar drivers estables oficiales y evitar drivers opcionales de Windows Update salvo que resuelvan un problema identificado.
- Para Windows Update roto, respaldar y restaurar primero políticas/servicios/tareas; después DISM/SFC. Detenerse ante corrupción estructural recurrente.

### 5. Auditar y optimizar Fortnite

Leer [fortnite-measurement.md](references/fortnite-measurement.md) antes de editar configuración o interpretar frametimes.

- Respaldar `GameUserSettings.ini` y registrar su atributo de solo lectura antes de editar.
- Preservar el render elegido. En Performance Mode, no migrar a DX12 como “arreglo” sin permiso.
- Probar límites de FPS coherentes con estabilidad y objetivo. Un monitor de 200 Hz puede usarse con caps de 180, 200, 220 o 240; refresh y cap son variables distintas.
- Evaluar replays, captura, highlights, cosmetic/asset streaming, texturas de alta resolución, shader rebuild y verificación de archivos.
- Probar resolución nativa versus estirada por preferencia y frametime. Una resolución menor no soluciona un game thread saturado.
- Cambiar una familia de variables por vez y repetir exactamente el escenario de prueba.

### 6. Auditar ping, jitter y latencia local

Leer [network-latency.md](references/network-latency.md) antes de cambiar NIC, TCP o router.

- Medir gateway, destino externo estable y región/servidor relevante: mediana, p95, jitter y pérdida, en reposo y bajo carga.
- Preferir Ethernet, revisar velocidad negociada, driver del fabricante, cable, EEE y ahorro de energía.
- Medir bufferbloat; recomendar SQM/QoS en el router cuando la latencia solo sube con tráfico.
- Explicar que DNS mejora resolución/conexión inicial, no el ping sostenido; port forwarding tampoco reduce RTT.
- Evitar desactivar autotuning, offloads o interrupt moderation en bloque. Probar uno por uno y revertir si no mejora.

### 7. Validar y entregar

- Volver a medir después de cada grupo de cambios y también después del reinicio cuando corresponda.
- Comparar promedio, 1%/0.1% low, p95/p99 frametime, GPU, núcleo más cargado, temperaturas, clocks, RAM, disco, RTT/jitter/loss.
- Distinguir mejora real de variación entre partidas y de compilación de shaders de la primera partida.
- Entregar: causa principal con evidencia, cambios aplicados, cambios descartados, backups, reinicio pendiente, resultados antes/después y riesgos restantes.
- Si no se puede medir un dato, decirlo; no inferirlo de FPS promedio ni de “sensación”.

## Comandos de los scripts

```powershell
# Auditoría general; no modifica configuración.
powershell -ExecutionPolicy Bypass -File scripts/collect-fortnite-audit.ps1

# Añadir salud de DISM y objetivos de ping cuando corresponda.
powershell -ExecutionPolicy Bypass -File scripts/collect-fortnite-audit.ps1 `
  -IncludeServicingHealth -PingTargets 1.1.1.1

# Captura mientras Fortnite está abierto; no cierra ni cambia el proceso.
powershell -ExecutionPolicy Bypass -File scripts/capture-fortnite-session.ps1 `
  -DurationSeconds 180 -PingTarget 1.1.1.1
```

Resolver rutas relativas desde la carpeta de esta skill. Guardar los informes fuera de la carpeta de la skill.
