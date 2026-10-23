# Experimental UWB trial

## Prueba física en el iPhone

1. Firmá el nuevo IPA sin firmar e instalalo en el iPhone como las versiones anteriores.
2. Iniciá sesión si hace falta, actualizá las etiquetas y seleccioná **Cleo**. Tocá **Buscar dispositivos cercanos** y seleccioná el dispositivo que ya permitió leer su batería.
3. Dejá el **Perfil experimental 2.0**, seleccionado por defecto en iOS 26.1 o posterior, y el ensayo de direcciones **Base (sin invertir)** para conservar el paquete anterior. Tocá **Iniciar prueba UWB**. La app vuelve a autenticar la conexión Bluetooth y lee la batería automáticamente antes de preparar UWB; no hace falta ejecutar antes la prueba de batería.
4. Aceptá el permiso de Nearby Interaction si aparece y mantené la app abierta en primer plano, con Cleo cerca. Comprobá si aparece **Distancia UWB** en metros y si cambia al mover la etiqueta.
5. Si falla, tocá **Detener prueba UWB** antes de seleccionar el perfil **1.1** y comenzar otra prueba. Detené también la prueba al terminar.

Todavía no se ha demostrado una medición real con Cleo. Una conexión Bluetooth, una batería leída o una configuración aceptada no confirman UWB. Si no aparecen metros, compartí el mensaje de estado y el **Registro técnico** de la app, que usa diagnósticos sanitizados; no compartas claves, tokens ni la URL de retorno del inicio de sesión.

### Ensayo de representación de direcciones

El selector **Ensayo de direcciones** conserva Base por defecto y permite invertir
solo la etiqueta, solo el iPhone o ambas. Cambia exclusivamente los bytes de las
dos direcciones del paquete Samsung; no altera la configuración Apple, el canal,
los tiempos, el vendor ni el IV. Es una prueba de representación entre sistemas,
no una corrección de compatibilidad demostrada. Los valores no se muestran y las
colisiones de las direcciones efectivas se rechazan. El selector queda bloqueado
mientras la prueba o el cierre Bluetooth estén activos. Detené cada intento antes
de cambiarlo y reportá su modo junto con el resultado, sin enviar datos internos.

### Plazos y observación de la sesión

La app concede 30 segundos para preparar NI y confirmar la configuración por
Bluetooth. El ACK de configuración del intento actual cancela ese temporizador y
abre otro plazo completo de 30 segundos para la medición. Usa un reloj monotónico;
ACKs o mediciones que lleguen al vencer el plazo no reviven el intento aunque la
tarea del temporizador todavía no se haya ejecutado. NI gobierna ese plazo de
medición; Bluetooth conserva un límite de seguridad de 35 segundos desde su ACK,
con 5 segundos de margen para no competir con el mismo vencimiento de NI.
Esto no amplía el plazo de medición ni demuestra compatibilidad de radio.

Cada temporizador Bluetooth valida su operación y generación de conexión antes
de actuar. Un vencimiento cancelado o reemplazado no puede cerrar una operación
posterior. STOP dispone de hasta 3 segundos para que termine una escritura previa,
y otros 3 segundos desde su envío real para recibir confirmación. Repetir la
parada no extiende esos plazos. El cierre Bluetooth conserva su barrera de
confirmación y un límite independiente de 5 segundos.

Los dos registros usan el prefijo `[+1.234 s]`, con un mismo origen monotónico de
la ejecución de la app. Limpiar un registro no reinicia su reloj. El motivo de fin
NI se registra antes de iniciar la limpieza; petición, espera, envío y confirmación
de STOP y petición/confirmación de cierre se distinguen. Las secciones permanecen
separadas: compará sus tiempos para reconstruir el orden, sin asumir que un eco o
un callback de inicio prueba comunicación de medición UWB.

El registro distingue solicitar la sesión de observar `sessionDidStartRunning`.
La ausencia del callback se informa como no observada, sin afirmar que la radio no
inició. Solo las primeras tres actualizaciones NI llevan un resumen de presencia
de objeto/distancia y etapa; al terminar se informa la cuenta total. No se imprimen
tokens, direcciones ni datos de radio privados. Los plazos **de la app** se
distinguen de `didRemove(.timeout)`, emitido por el framework. Corregir los plazos
de la app no demuestra haber encontrado la causa del timeout físico de Cleo.

## Apple configuration bridge

### Inspección de notificaciones Bluetooth

La notificación de parámetros UWB se inspecciona solo dentro de la conexión Bluetooth autenticada. Se aplica el descifrado AES-CBC existente, la trama con contador de cuatro bytes y la secuencia de recepción compartida con la batería. El registro informa únicamente longitud de la carga descifrada o rechazo por cifrado/relleno, trama incompleta o repetición; no registra claves, IV, contadores ni contenido.

Una respuesta de 48 bytes puede contener una trama cifrada, pero su longitud no identifica el contenido. Las pruebas usan datos sintéticos: todavía no disponemos del contenido de la respuesta real de Cleo. El relleno CBC válido no demuestra integridad criptográfica, ni la inspección identifica un estado de éxito UWB. La carga desconocida no se interpreta ni produce distancia y su rechazo no cancela por sí solo la sesión de Nearby Interaction.

Tras validar cifrado, trama y contador, la app compara la carga con el paquete exacto de 35 bytes entregado a CoreBluetooth para escribir la configuración. Conserva ese paquete solo durante el intento autenticado y lo borra al detener, reiniciar o cerrar la conexión y ante fallos. Lo guarda antes de esperar la confirmación de escritura porque la notificación puede llegar primero. El registro solo indica **coincide exactamente**, **diferente** o **no disponible**; nunca muestra los bytes. Una coincidencia no demuestra que la etiqueta acepte el perfil de radio ni identifica un estado de firmware. Para la nueva prueba, compartí esa categoría junto con el motivo de finalización de Nearby Interaction.

The trial uses public Nearby Interaction foreground accessory APIs. Its compatibility with SmartTag2 firmware is unproven. Configuration acceptance and Bluetooth write acknowledgements do not establish a distance measurement.

The [Apple accessory protocol R4](https://developer.apple.com/download/files/Nearby-Interaction-Accessory-Protocol-Specification-R4.pdf), section 3.4, defines the outer configuration header: version 1.0, preferred update rate 0 (automatic), ten reserved zero bytes, and the inner length. [Interoperability R3](https://developer.apple.com/download/files/Nearby-Interaction-with-UWB-Interoperability-Specification-R3.pdf), section 4, defines the version 1.1 inner configuration and generated output. The [R4 interoperability preview](https://developer.apple.com/download/files/Nearby-Interaction-with-UWB-Interoperability-Specification-Developer-Preview-R4.pdf) defines version 2.0 requests. The published tables were obtained from Apple's indexed document text; direct PDF retrieval returned 404 during research.

The experimental profile explicitly declares manufacturer/model/middleware IDs 0 and maximum clock drift 20 ppm. These are assumptions, not recovered SmartTag hardware values. It selects an accessory initiator/controller role and a fresh random short accessory address. Version 2 requests hopping by default, six slots, 2400 RSTU slot duration and 240 ms interval; Apple selects the final values. The wrapper totals 37 bytes for version 1.1 and 48 for version 2.0.

Generated data is decoded only for the documented version and exact length: 30 bytes for version 1.1 or 35 for version 2.0. The length byte excludes its five-byte header. Fields use little endian. Unknown versions, malformed lengths, reserved bytes, hopping values, and radio parameters outside the trial profile stop the experiment. The Samsung adapter performs additional profile checks before any transmission.

The version 2 input is gated by runtime support: [iOS 26.1 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_1-release-notes/) document additional accessory parameters including hopping. The integration uses the established `NINearbyAccessoryConfiguration(data:)` initializer rather than new SDK-only declarations.

Only a current, matching Nearby Interaction object's finite, nonnegative `distance` may be displayed in meters. RSSI, configuration acceptance, sample vectors and a previous session's values are never substitutes. The foreground trial requires the Nearby Interaction privacy description; no fabricated `com.apple.developer.nearby-interaction` entitlement is added.
# Reading a failed trial

The technical screen keeps Bluetooth and Nearby Interaction events in separate sections; it does not claim one interleaved chronology. Known 1.1/2.0 configurations report their length, version and radio fields before strict validation. Failures distinguish Apple decoding from Samsung translation and name unsupported fields without logging their secret values. Unknown layouts report only length/version.

NI removal reports `timeout`, `peerEnded` or an unknown reason. NI invalidation reports only the numeric error code and whether parameters had been handed to the Bluetooth transport. That handoff is not a GATT acknowledgement or evidence of radio compatibility. No payload, session identifier, address, STS IV, token or key is included. A failed trial never becomes a distance result.

## Solicitud experimental de hopping (solo perfil 2.0)

**Solicitud hopping** permanece activada por defecto para conservar el paquete
anterior. Con el perfil 2.0 y la prueba detenida se puede desactivar la solicitud.
Solo cambia el byte 41 de la configuración inicial Apple; los otros campos y el
ensayo de direcciones elegido permanecen iguales. Al elegir 1.1 la opción vuelve
a su valor inicial y queda bloqueada: ese perfil no tiene este campo configurable.

La solicitud no garantiza la selección. El registro con marcas de tiempo informa
por separado el valor solicitado y el generado por Apple. Si se solicita OFF y
Apple selecciona ON, aparece **Solicitud no concedida** antes de codificar o enviar
parámetros UWB a la etiqueta. Nunca se fuerza OFF en el paquete Samsung. Si Apple
selecciona OFF con la solicitud ON habitual, se conserva la aceptación anterior.
El paquete Samsung siempre refleja la selección recibida, no la intención del
selector; solo cambia su bit de hopping cuando los demás parámetros coinciden.

Para comparar, mantené el mismo perfil 2.0 y ensayo de direcciones, ejecutá una
prueba con la solicitud activada, detenela y repetí con la solicitud desactivada.
Compartí el valor solicitado/seleccionado y el motivo de finalización, o metros
reales si aparecen. OFF aceptado por Apple o un eco Bluetooth no demuestra que el
firmware de Cleo pueda usar ese modo. La compatibilidad real continúa sin probarse.

Evidencia acotada: [Apple R4, tabla 4-2 y sección 4.4.3.3](https://developer.apple.com/download/files/Nearby-Interaction-with-UWB-Interoperability-Specification-Developer-Preview-R4.pdf)
permite solicitar 0/1 y devolver la selección; solo se recuperaron extractos
oficiales indexados, no el PDF completo. [uTag fijado](https://github.com/KieronQuinn/uTag/blob/f46375a9c2af6de4c8678f6aba7b91972054ae74/app/src/main/java/com/kieronquinn/app/utag/components/uwb/UwbConfig.kt)
solicita 1 y codifica la selección en el bit global 34 del paquete de la etiqueta.
El valor Android DISABLE=0 no prueba que el firmware Samsung lo admita.

La [implementación AOSP del codificador](https://android.googlesource.com/platform/packages/modules/Uwb/+/25caf0858e7e2ac5cb3e8e99b8376f11f30bcbad/service/java/com/android/server/uwb/params/FiraEncoder.java)
también aplica reglas de orden de MAC/vendor según versión de Android. Esto no
establece una traducción universal para iOS. La investigación limitada al APK no
recuperó la implementación UCI externa ni demostró otro cambio de radio correcto;
este selector es un experimento documentado y no una solución confirmada.

