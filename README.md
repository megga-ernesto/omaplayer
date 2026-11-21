# ElMeGGa OmaPlayer

Now-playing widget for the Omarchy shell, with playback controls, live audio visualizers, and optional synced lyrics.

![OmaPlayer's media panel with layered waves and synced lyrics](preview.jpg)

## English

OmaPlayer shows the active media source, track information, cover art, and playback controls in the bar and an expandable panel. The bar, player panel, and timeline have independent visualizer settings. The panel follows the active Omarchy theme and offers an optional glass finish. The interface is available in English and Spanish.

### Install and enable

Compatible with the Omarchy Quattro shell. Tested on Omarchy 4.5.0-3.

```sh
omarchy plugin add https://github.com/megga-ernesto/omaplayer.git --enable
```

Click the music icon, track title, or visualizer in the bar to open the player. Use the gear to open settings. Use **Lyrics** to look up synchronized lyrics.

### Dependencies and data

- Omarchy's Quickshell, Hyprland, and an app that exposes an MPRIS playback session provide the panel and media controls. Available commands depend on the media app.
- Python 3 runs the optional helpers. The audio visualizers use `parec` (from Arch's `libpulse` package) to read the default output monitor locally. The helper sends visualization data to the widget and saves no recording.
- Lyrics use `curl` to query [LRCLIB](https://lrclib.net/docs) over HTTPS when **Lyrics** is enabled and the panel is open. The request contains the available title, artist, album, and duration. Online artwork for supported services uses `curl` when requested from the panel. OmaPlayer automatically fetches cover art from those fixed HTTPS sources when the displayed track changes. Turn off **Load online covers automatically** to load covers manually.

### Optional desktop blur

The glass finish and cover backdrop are optional. Desktop blur requires a one-time manual Hyprland setup. Installation and updates leave your Hyprland configuration alone.

Copy `hyprland-glass.lua` to `~/.config/hypr/omaplayer.lua`. Add `require("hypr.omaplayer")` once at the end of `~/.config/hypr/hyprland.lua`. Run `hyprctl reload` and `hyprctl configerrors`. Then enable **Glass finish** and **Blur the backdrop** in the widget. The backdrop helper uses Hyprland's layer rule and can temporarily enable compositor blur while OmaPlayer is open, restoring the previous setting when the panel closes normally.

### Disable or uninstall

```sh
omarchy plugin disable elmegga.omaplayer
omarchy plugin remove elmegga.omaplayer
```

If you configured desktop blur, remove the `require("hypr.omaplayer")` line and the `~/.config/hypr/omaplayer.lua` file, then run `hyprctl reload` and `hyprctl configerrors`.

## Español

OmaPlayer muestra la carátula, los datos de la pista y los controles en la barra y en un panel desplegable. Los visualizadores de la barra, el reproductor y la barra de tiempo se configuran por separado. La interfaz sigue el tema activo de Omarchy.

### Instalar y usar

```sh
omarchy plugin add https://github.com/megga-ernesto/omaplayer.git --enable
```

Abre el panel pulsando el icono de música, el título o el visualizador. Usa el engranaje para abrir los ajustes. La opción **Letra** consulta LRCLIB solo cuando está activada y el panel está abierto.

Los controles dependen de los datos que comparta la aplicación mediante MPRIS. Las funciones opcionales usan Python 3, `parec` (paquete `libpulse` en Arch) para el visualizador y `curl` para letras o carátulas en línea. El visualizador procesa la salida de audio local y no guarda grabaciones. Las carátulas de servicios compatibles se cargan automáticamente. Puedes apagar **Cargar carátulas en línea automáticamente** para cargarlas a mano.

Para difuminar el escritorio tras el panel, copia `hyprland-glass.lua` en `~/.config/hypr/omaplayer.lua`, añade una vez `require("hypr.omaplayer")` al final de `~/.config/hypr/hyprland.lua` y ejecuta `hyprctl reload` y `hyprctl configerrors`. Después activa **Acabado de cristal** y **Difuminar el fondo** en OmaPlayer.

### Desactivar o quitar

```sh
omarchy plugin disable elmegga.omaplayer
omarchy plugin remove elmegga.omaplayer
```

Si configuraste el desenfoque, quita la línea `require("hypr.omaplayer")` y el archivo `~/.config/hypr/omaplayer.lua`. Ejecuta `hyprctl reload` y `hyprctl configerrors`.

## License

Plugin source code is available under the [MIT License](LICENSE). Rights to the music-related material visible in the preview remain with their respective rights holders.
