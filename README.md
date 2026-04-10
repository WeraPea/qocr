# qocr - wayland japanese ocr overlay

wayland OCR overlay for japanese text, built with [Quickshell](https://quickshell.outfoxxed.me/). uses Chrome Screen AI for local, offline OCR. integrates with [Yomitan](https://github.com/yomidevs/yomitan) for dictionary lookups and [AnkiConnect](https://ankiweb.net/shared/info/2055492159) for mining.

inspired by [meikipop](https://github.com/rtr46/meikipop). Chrome Screen AI integration code taken from meikipop.

## features
- **local OCR** via Chrome Screen AI - nothing leaves your machine
- **Yomitan popup** - middle-click or hover to look up words
- **Anki mining** - add cards directly from the popup
- **text selection** - drag to select and copy text
- **per-symbol bounding boxes** - accurate selection even for rotated/vertical text
- **auto-rescan** - continuously re-OCR a region
- **multi-monitor** support

## usage
- click anywhere to dismiss the Yomitan popup
- middle-click a character to look it up in Yomitan
- right-click a line to copy it to clipboard
- drag to select text and copy it to clipboard
- ＋ button in popup to add to Anki, ✓ if already in deck, ↗ to open in Anki browser

## requirements
- Nix (or manually: Python 3, Quickshell with QtWebEngine, grim, slurp, wl-clipboard)
- Chrome Screen AI model files
- Yomitan browser extension with [yomitan-api](https://github.com/yomidevs/yomitan-api/) installed
- AnkiConnect (optional)

## installation

### nix flake
```nix
# flake inputs
inputs.qocr.url = "github:WeraPea/qocr";

# home-manager
home-manager.users."username".imports = [
  inputs.qocr.homeModules.qocr
  {
    services.qocr,{
      enable = true;
      settings = {
        japaneseOnly = true;
        yomitan.apiUrl = "http://127.0.0.1:19633";
      };
    };
  }
];

```

### Chrome Screen AI model
Download the Screen AI component and extract it to `~/.config/screen_ai/resources/`:

[https://chrome-infra-packages.appspot.com/p/chromium/third_party/screen-ai](https://chrome-infra-packages.appspot.com/p/chromium/third_party/screen-ai)

The daemon will tell you this if the files are missing.

## configuration
Config file: `$XDG_CONFIG_HOME/qocr/config.json` (usually `~/.config/qocr/config.json`)

```json
{
  "boxMargin": 15,
  "border": 1,
  "japaneseOnly": true,
  "autoRescan": false,
  "autoRescanDelay": 0,
  "autoRescanDelayUnchanged": 0.1,
  "overlayOnHover": true,
  "showOverlay": true,
  "hideOverlayOnRescan": false,
  "background": "#50000000",
  "selectedBorder": "#cc56b7a5",
  "selectedBackground": "#6656b7a5",
  "borderColor": "#50d0d0d0",
  "regionBorder": "#cccc6633",
  "regionBackground": "#26cc6633",
  "yomitan": {
    "backgroundColor": "#121212",
    "foregroundColor": "#d0d0d0",
    "borderColor": "#56b7a5",
    "separatorColor": "#505050",
    "foregroundSecondaryColor": "#909090",
    "backgroundSecondaryColor": "#303030",
    "extraCss": "",
    "apiUrl": "http://127.0.0.1:19633",
    "textScanLength": 16,
    "lookupMaxDistance": 10,
    "fetchAudio": false,
    "autoPlayFirstAudio": false
  },
  "anki": {
    "enable": true,
    "ankiConnectUrl": "http://127.0.0.1:8765",
    "deck": "Mining",
    "model": "Lapis",
    "tags": ["qocr"],
    "allowDuplicate": true,
    "fields": {
      "Expression": "{expression}",
      "Sentence": "{cloze-prefix}<b>{cloze-body}</b>{cloze-suffix}"
    }
  }
}
```

> **note:** `fetchAudio` fetches audio for each dictionary entry on every lookup. with remote audio sources this hammers public servers unnecessarily. a local source like [yomitan-ultimate-audio](https://github.com/L-M-Sherlock/yomitan-ultimate-audio/) is strongly recommended if you want audio.

## IPC commands
qocr exposes IPC via Quickshell: `qocr ipc call ocr <command>`

| command | description |
|---|---|
| `scan` | select a region with slurp and OCR it |
| `scan_fullscreen` | select a whole output with slurp |
| `scan_output <name>` | OCR a specific output by name |
| `scan_region <output> <x> <y> <w> <h>` | OCR a specific region |
| `rescan` | re-OCR current regions |
| `clear_overlay` | clear text overlays (keep regions) |
| `clear_all` | clear everything |
| `show_region` | briefly flash the current region |
| `trigger_popup <x> <y> <monitor>` | trigger Yomitan lookup at screen coordinates |
| `close_popup` | close Yomitan popup |
| `hover_on` / `hover_off` | enable/disable hover lookup mode |
| `toggle_config <key>` | toggle a boolean config value |
| `set_config <key> <value>` | set a config value |
| `get_config <key>` | get a config value |

Nested config keys use dot notation: `yomitan.autoPlayFirstAudio`, `anki.enable`.

## example keybinds (Mango)
```
# scan selected region
bind=SUPER,s,spawn,qocr ipc call ocr scan

# scan current monitor
bind=SUPER,f,spawn_shell,qocr ipc call ocr scan_output $(mmsg -g -o | awk '$3 == "1" {print $1}')

# scan fullscreen (slurp -o)
bind=SUPER,g,spawn,qocr ipc call ocr scan_fullscreen

# rescan
bind=SUPER,r,spawn,qocr ipc call ocr rescan

# clear overlays
bind=SUPER,c,spawn,qocr ipc call ocr clear_overlay

# show current region
bind=SUPER,w,spawn,qocr ipc call ocr show_region

# toggle hover-over-text overlay
bind=SUPER,v,spawn,qocr ipc call ocr toggle_config overlayOnHover

# toggle text overlay visibility
bind=SUPER,d,spawn,qocr ipc call ocr toggle_config showOverlay

# toggle auto-rescan
bind=SUPER,q,spawn,qocr ipc call ocr toggle_config autoRescan

# toggle auto-play audio in Yomitan popup
bind=SUPER,z,spawn,qocr ipc call ocr toggle_config yomitan.autoPlayFirstAudio

# trigger Yomitan popup at cursor position (requires wl-find-cursor)
bind=SUPER,e,spawn_shell,output=$(mmsg -g -o | awk '$3 == "1" {print $1}'); xy=$(wl-find-cursor -p); qocr ipc call ocr trigger_popup $xy $output

# hold shift to hover-lookup at cursor (press to enable, release to disable, wl-find-cursor only required for inital position)
bindp=NONE,SHIFT_L,spawn_shell,if [ "$(qocr ipc call ocr hover_on)" == "true" ]; then output=$(mmsg -g -o | awk '$3 == "1" {print $1}'); xy=$(wl-find-cursor -p); qocr ipc call ocr trigger_popup $xy $output; fi
bindpr=SHIFT,SHIFT_L,spawn,qocr ipc call ocr hover_off
```

## license
GPL-3.0
