# Red, ping y latencia local

## Índice

1. Separar métricas
2. Medición
3. Ruta local y NIC
4. Router, bufferbloat e ISP
5. Tweaks que evitar

## 1. Separar métricas

- **RTT/ping:** ida y vuelta hasta un destino.
- **Jitter:** variación del RTT; puede sentirse peor que una media algo mayor.
- **Packet loss:** paquetes perdidos; causa teletransporte, correcciones y desconexiones.
- **Input latency local:** mouse → CPU/juego → GPU → pantalla; no equivale a ping.
- **Frametime:** tiempo entre cuadros; spikes se sienten como stutter aunque el ping sea perfecto.

No atribuir “delay” a la red sin separar estas capas.

## 2. Medición

Medir por Ethernet cuando sea posible:

1. Gateway/router local.
2. Un destino externo estable.
3. Región/servidor relevante de Epic si se puede identificar de forma legítima.
4. Reposo y carga de subida/descarga.

Registrar mediana, p95, máximo, jitter y pérdida; `ping`, `pathping` y `tracert` sirven para orientación. Los routers intermedios pueden de-priorizar ICMP: pérdida en un salto que no continúa hasta el destino no prueba un problema.

No hacer pruebas de saturación mientras el usuario compite. Avisar que una prueba de bufferbloat consume ancho de banda.

## 3. Ruta local y NIC

Comprobar:

- Ethernet versus Wi-Fi, velocidad negociada, dúplex, cable/puerto y errores del adaptador;
- driver LAN oficial, firmware de router y ausencia de VPN/proxy/WARP no deseado;
- Energy Efficient Ethernet/Green Ethernet y ahorro de energía si coinciden con microcortes;
- interrupt moderation y offloads solo mediante A/B; pueden ayudar throughput y empeorar o mejorar latencia según NIC/CPU;
- procesos de streaming, cloud sync, launcher, emulador y actualizaciones en segundo plano.

No deshabilitar IPv6 por rutina. No fijar DNS si el actual resuelve bien. No exponer IP pública, credenciales de router ni identificadores innecesarios en informes.

## 4. Router, bufferbloat e ISP

Si el ping sube únicamente bajo carga, priorizar SQM (CAKE/FQ-CoDel cuando el router lo soporte) o QoS bien configurado, limitando ligeramente por debajo del throughput real. Verificar quién más usa la red.

Si el primer salto ya tiene jitter/pérdida, revisar LAN/Wi-Fi/router. Si empieza después y persiste al destino, documentar horarios/rutas y escalar al ISP. Elegir la región de Fortnite con menor latencia estable, no solo menor muestra aislada.

Un stream Full HD puede afectar por ancho de banda o bufferbloat aunque la PC tenga recursos. Comparar con/sin stream y revisar subida además de bajada.

## 5. Tweaks que evitar

No presentar como reducción universal de ping:

- cambiar DNS;
- abrir puertos o activar DMZ;
- desactivar TCP autotuning;
- modificar `TcpAckFrequency`, `TCPNoDelay`, `NetworkThrottlingIndex` o `SystemResponsiveness`;
- deshabilitar todos los offloads/interrupt moderation;
- usar “gaming VPN” sin comparar ruta, jitter y pérdida.

Fortnite usa su propio tráfico y servidores; muchas claves TCP no afectan ese flujo. Aplicar solo cambios soportados, respaldados y medidos.
