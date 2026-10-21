# Luz WiZ

App de barra de menú para macOS que controla lámparas WiZ por la red local (UDP 38899),
sin cuenta ni nube.

## Funciones
- Encender / apagar, brillo
- Blanco regulable (2200–6500 K) con atajos: Vela, Cálida, Neutra, Día, Fría
- Color: tono, intensidad y una paleta rápida
- Las 32 escenas de WiZ, con velocidad para las animadas
- Hasta 8 favoritos (clic derecho para borrar)
- Temporizador de apagado
- Varias lámparas, renombrables; si el router les cambia la IP, las vuelve a encontrar por MAC
- Abrir al iniciar sesión

### Opciones de la lámpara (menú ⚙︎)
- **Más cálida al bajar el brillo**: en modo Blanco, sigue la curva *dim to warm* de la propia lámpara
- **Encendido y apagado suaves**: fundido de 1,5 s; al apagar deja guardado el brillo
- **Colores suaves con LED blanco**: los tonos pastel salen de los LEDs blancos en vez de mezclar RGB

El firmware 1.39 rechaza `setUserConfig` por la red local, así que estas opciones las aplica la app
(solo valen para lo que se controla desde Luz WiZ). Por la misma razón, el sensor de toque no se puede
activar ni desactivar desde acá.

## Compilar
Solo necesita las Command Line Tools (`xcode-select --install`), no Xcode.

```bash
./build.sh --open
```

Instala `Luz WiZ.app` en `~/Applications`. La primera vez macOS pide permiso de red local:
hay que aceptarlo (o activarlo en Ajustes del Sistema → Privacidad y seguridad → Red local).

## Estructura
- `Wiz.swift`: protocolo WiZ y sockets UDP
- `Models.swift`: lámpara, estado, escenas, favoritos
- `LampStore.swift`: estado de la app, sondeo, envío limitado a uno cada 60 ms y opciones de la lámpara
- `Views.swift`: interfaz SwiftUI
