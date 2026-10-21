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
- `LampStore.swift`: estado de la app, sondeo y envío limitado a uno cada 60 ms
- `Views.swift`: interfaz SwiftUI
