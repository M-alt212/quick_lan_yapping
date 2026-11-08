# Chat efímero en PowerShell

Un chat mínimo para terminal, hecho en PowerShell puro y sin dependencias. Ahora es **un solo programa**: creas una sala o te unes a una, y las salas se encuentran solas en la red, sin pasar IPs a mano. Nada se guarda en disco: cuando el host cierra la sala, el chat desaparece.

## Archivos

- `chat.ps1`: el programa (sirve para crear una sala o para unirse).
- `chat.bat`: lanzador. Doble clic y listo.

## Uso

1. Haz doble clic en `chat.bat` (o ejecuta `powershell -ExecutionPolicy Bypass -File .\chat.ps1`).
2. Elige tu nombre. Sin espacios (se cambian por `_`), máximo 12 letras. Si lo dejas vacío, te toca algo como `Shyguy42`.
3. Elige qué hacer:
   - **Crear una sala:** le pones nombre y los demás la ven en su lista.
   - **Unirme a una sala:** aparece la lista de salas de la red. Escribe el número (o el nombre) para entrar. `R` busca de nuevo, `M` te deja escribir una IP a mano.
4. Escribe y presiona Enter para enviar.

Comandos dentro del chat:

- `/lista`: ver quién está conectado.
- `/q`: salir.

Tu nombre sale con color, y tus propios mensajes llevan `(tú)` al lado. Si dos personas eligen el mismo nombre, a la segunda se le agrega un número (`Ana2`).

## Cómo funciona

- Una sala es un PC (el host). Los demás se conectan a él por TCP.
- El host avisa por broadcast UDP cada 2 segundos que existe; los demás escuchan y arman la lista.
- Puertos: chat en TCP `5000` (si está ocupado, prueba `5001` a `5009`) y descubrimiento en UDP `5001`.

## Convivencia con BAR

Este chat y BAR (el proyecto grande de actividades) pueden estar abiertos a la vez en la misma red sin mezclarse:

| | Chat efímero | BAR |
|---|---|---|
| Chat (TCP) | 5000 a 5009 | 45454 a 45463 |
| Descubrimiento (UDP) | 5001 | 45455 |
| Etiqueta del aviso | `EPH1` | `AULA1` |
| Primer mensaje al conectar | `HI` | `JOIN` |

Cada uno solo ve las salas de su propio tipo. Si alguien se conecta a mano (IP y puerto) a la sala equivocada, el saludo no coincide y la conexión se cierra a los pocos segundos con "La sala no respondió".

## Si no conecta

- Revisa que el firewall de Windows del host permita a PowerShell. La primera vez Windows suele preguntar: hay que aceptar.
- Algunas redes aíslan los equipos entre sí y no dejan que se vean. Prueba `Test-NetConnection IP-DEL-HOST -Port 5000`.
- Si la sala no aparece en la lista, usa `M` e ingresa la IP del host que se ve arriba en su pantalla (con `:puerto` si no usa el 5000).

## Cambios respecto a la versión anterior

- `server.ps1` y `client.ps1` se reemplazan por `chat.ps1`.
- Ya no es compatible con los clientes de la versión anterior.

## Advertencia

Los mensajes viajan en texto plano y no hay autenticación: cualquiera que alcance el host puede leer y participar. Úsalo solo para pruebas y con permiso en la red donde lo ejecutes. No envíes información privada.

## Licencia

MIT
