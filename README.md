# Chat efímero en PowerShell

Un chat mínimo para terminal, hecho en PowerShell puro y sin dependencias. Creas una sala o te unes a una, y las salas se encuentran solas en la red, sin pasar IPs a mano. Nada se guarda en disco: cuando el host cierra la sala, el chat desaparece.

## Archivos

* `chat.ps1`: el programa (sirve para crear una sala o para unirse).
* `chat.bat`: lanzador. Doble clic y listo.

## Uso

1. Haz doble clic en `chat.bat` (o ejecuta `powershell -ExecutionPolicy Bypass -File .\chat.ps1`).
2. Elige tu nombre. Sin espacios (se cambian por `_`), máximo 12 letras. Si lo dejas vacío, te toca algo como `Shyguy42`.
3. Elige qué hacer:

   * **Crear una sala:** le pones nombre y los demás la ven en su lista.
   * **Unirme a una sala:** aparece la lista de salas de la red. Escribe el número (o el nombre) para entrar. `R` busca de nuevo, `M` te deja escribir una IP a mano.
4. Escribe y presiona Enter para enviar.

Comandos dentro del chat:

* `/lista`: ver quién está conectado.
* `/q`: salir.

Tu nombre sale con color, y tus propios mensajes llevan `(tú)` al lado. Si dos personas eligen el mismo nombre, a la segunda se le agrega un número (`Ana2`).

## Cómo funciona

* Una sala es un PC (el host). Los demás se conectan a él por TCP.
* El host avisa por broadcast UDP cada 2 segundos que existe; los demás escuchan y arman la lista.
* Puertos: chat en TCP `5000` (si está ocupado, prueba `5001` a `5009`) y descubrimiento en UDP `5001`.

## Si no conecta

* Revisa que el firewall de Windows del host permita a PowerShell. La primera vez Windows suele preguntar: hay que aceptar.
* Algunas redes aíslan los equipos entre sí y no dejan que se vean. Prueba `Test-NetConnection IP-DEL-HOST -Port 5000`.
* Si la sala no aparece en la lista, usa `M` e ingresa la IP del host que se ve arriba en su pantalla (con `:puerto` si no usa el 5000).

## Advertencia

Los mensajes viajan en texto plano y no hay autenticación: cualquiera que alcance el host puede leer y participar. Úsalo solo para pruebas y con permiso en la red donde lo ejecutes. No envíes información privada.

## Licencia

MIT

