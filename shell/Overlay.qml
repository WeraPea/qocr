pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Item {
    id: root
    property var ocrData: ({})
    property alias config: config
    property bool showOverlay: config.showOverlay
    property var panels: ({})

    FileView {
        path: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/qocr/config.json`
        watchChanges: true
        onFileChanged: reload()
        JsonAdapter { // qmllint disable unresolved-type
            id: config
            property int boxMargin: 15
            property int border: 1
            property bool japaneseOnly: true
            property bool autoRescan: false
            property real autoRescanDelay: 0
            property real autoRescanDelayUnchanged: 0.1
            property bool overlayOnHover: true
            property bool showOverlay: true
            property bool hideOverlayOnRescan: false
            property string background: "#50000000"
            property string selectedBorder: "#cc56b7a5"
            property string selectedBackground: "#6656b7a5"
            property string borderColor: "#50d0d0d0"
            property string regionBorder: "#cccc6633"
            property string regionBackground: "#26cc6633"
            property JsonObject yomitan: JsonObject {
                property string backgroundColor: "#121212"
                property string foregroundColor: "#d0d0d0"
                property string borderColor: "#56b7a5"
                property string separatorColor: "#505050"
                property string foregroundSecondaryColor: "#909090"
                property string backgroundSecondaryColor: "#303030"
                property string extraCss: ""
                property string apiUrl: "http://127.0.0.1:19633"
                property int textScanLength: 16
                property int lookupMaxDistance: 10
                property bool fetchAudio: false // can be slow if not using a local audio source
            }
            property JsonObject anki: JsonObject {
                property bool enable: true
                property string ankiConnectUrl: "http://127.0.0.1:8765"
                property string deck: "Mining"
                property string model: "Lapis"
                property list<string> tags: ["qocr"]
                property bool allowDuplicate: true
                property var fields: {
                    "Expression": "{expression}",
                    "ExpressionFurigana": "{furigana-plain}",
                    "ExpressionReading": "{reading}",
                    "ExpressionAudio": "{audio}",
                    "MainDefinition": "{single-glossary-jitendexorg-2025-06-01}",
                    "Sentence": "{cloze-prefix}<b>{cloze-body}</b>{cloze-suffix}",
                    "Glossary": "{glossary}",
                    "IsWordAndSentenceCard": "x",
                    "PitchPosition": "{pitch-accent-positions}",
                    "PitchCategories": "{pitch-accent-categories}",
                    "Frequency": "{frequency-harmonic-rank}",
                    "FreqSort": "{frequency-harmonic-rank}"
                }
            }
        }
    }

    Connections {
        target: root.config
        function onAutoRescanChanged() {
            if (root.config.autoRescan)
                ocrProc.rescan();
        }
        function onShowOverlayChanged() {
            root.showOverlay = root.config.showOverlay;
        }
    }

    function updateMonitor(monitor, data) {
        var updated = Object.assign({}, root.ocrData); // copies to trigger bindings
        updated[monitor] = data;
        root.ocrData = updated;
    }

    Process {
        id: ocrProc
        command: ["qocrd"]
        stdinEnabled: true
        stdout: SplitParser {
            splitMarker: "\0"
            onRead: data => {
                // console.log(data);
                root.showOverlay = root.config.showOverlay;
                try {
                    var parsed = JSON.parse(data);
                    if (parsed.unchanged) {
                        rescanTimer.interval = root.config.autoRescanDelayUnchanged;
                    } else {
                        root.updateMonitor(parsed.monitor, parsed);
                        rescanTimer.interval = root.config.autoRescanDelay;
                    }
                } catch (e) {
                    console.log("Parse error:", e);
                }
                if (root.config.autoRescan) {
                    ocrProc.pendingRescans--;
                    if (ocrProc.pendingRescans <= 0)
                        rescanTimer.running = true;
                }
            }
        }
        stderr: SplitParser {
            onRead: data => {
                console.log("qocrd stderr:", data);
            }
        }
        // qmllint disable signal-handler-parameters
        onExited: (c, s) => console.log(c, s)
        // qmllint enable signal-handler-parameters
        running: true

        property int pendingRescans: 0
        function rescan() {
            var entries = Object.entries(root.ocrData);
            pendingRescans = entries.length;
            if (root.config.hideOverlayOnRescan)
                root.showOverlay = false;
            entries.forEach(([monitor, data]) => {
                var r = data.region;
                ocrProc.write(`rescan ${root.config.japaneseOnly} ${r.x} ${r.y} ${r.w} ${r.h} ${r.X} ${r.Y} ${monitor}\n`);
            });
        }
    }

    Item {
        id: ocr
        property bool showRegion: false
        IpcHandler {
            target: "ocr"

            function scan(): void {
                ocrProc.write(`scan ${root.config.japaneseOnly} false\n`);
            }
            function scan_fullscreen(): void {
                ocrProc.write(`scan ${root.config.japaneseOnly} true\n`);
            }
            function scan_output(output: string): void {
                var panel = root.panels[output];
                if (!panel)
                    return;
                root.ocrData[output] = {
                    monitor: output,
                    region: {
                        x: panel.screen.x,
                        y: panel.screen.y,
                        w: panel.screen.width,
                        h: panel.screen.height,
                        X: 0,
                        Y: 0
                    }
                };
                ocrProc.rescan();
            }
            function scan_region(output: string, x: int, y: int, w: int, h: int): void {
                var panel = root.panels[output];
                if (!panel)
                    return;
                root.ocrData[output] = {
                    monitor: output,
                    region: {
                        x: x,
                        y: y,
                        w: w,
                        h: h,
                        X: x - panel.screen.x,
                        Y: y - panel.screen.y
                    }
                };
                ocrProc.rescan();
            }
            function rescan(): void {
                ocrProc.rescan();
            }
            function clear_overlay(): void {
                var updated = {};
                Object.keys(root.ocrData).forEach(function (key) {
                    var old = root.ocrData[key];
                    var copy = Object.assign({}, old);
                    copy.lines = [];
                    updated[key] = copy;
                });
                root.ocrData = updated;
            }
            function clear_all(): void {
                root.ocrData = {};
            }
            function show_region(): void {
                ocr.showRegion = true;
                regionTimer.restart();
            }
            function set_config(setting: string, value: string): void {
                var parts = setting.split(".");
                var target = parts.length > 1 ? root.config[parts[0]] : root.config;
                var key = parts[parts.length - 1];
                if (value.toLowerCase() === "true")
                    target[key] = true;
                else if (value.toLowerCase() === "false")
                    target[key] = false;
                else if (!isNaN(value))
                    target[key] = Number(value);
                else
                    target[key] = value;
            }
            function toggle_config(setting: string): void {
                root.config[setting] = !root.config[setting];
            }
            function get_config(setting: string): string {
                var parts = setting.split(".");
                var target = parts.length > 1 ? root.config[parts[0]] : root.config;
                var key = parts[parts.length - 1];
                return target[key];
            }
            function trigger_popup(x: int, y: int, monitor: string): void {
                var panel = root.panels[monitor];
                if (!panel)
                    return;

                panel.yomitanLookup.lookup({
                    x: x,
                    y: y
                });
            }
        }
    }

    Timer {
        id: rescanTimer
        interval: root.config.autoRescanDelay * 1000
        onTriggered: ocrProc.rescan()
    }

    Timer {
        id: regionTimer
        interval: 1500
        onTriggered: ocr.showRegion = false
    }

    Variants {
        model: Quickshell.screens

        PanelWindow { // qmllint disable uncreatable-type
            id: panel

            required property var modelData
            screen: modelData

            property var lineRects: []
            property var regionItems: []
            property var ocrData: root.ocrData[screen.name] ?? {}
            property var lines: ocrData.lines ?? []
            property var region: ocrData.region

            Component.onCompleted: {
                root.panels[screen.name] = panel;
            }

            Component.onDestruction: {
                delete root.panels[screen.name];
            }

            onLineRectsChanged: updateRegions()
            onOcrDataChanged: {
                panel.lineRects = [];
            }

            function updateRegions() {
                panel.regionItems = root.config.showOverlay ? panel.lineRects : [];
            }

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            mask: Region {
                regions: _regions.instances
            }

            Variants {
                id: _regions
                model: panel.regionItems
                delegate: Region {
                    required property var modelData
                    item: modelData
                }
            }

            Item {
                id: regionItem

                Rectangle {
                    visible: ocr.showRegion && panel.region !== null
                    x: panel.region ? panel.region.X : 0
                    y: panel.region ? panel.region.Y : 0
                    width: panel.region ? panel.region.w : 0
                    height: panel.region ? panel.region.h : 0
                    color: root.config.regionBackground
                    border.color: root.config.regionBorder
                    border.width: 2
                }
            }

            HoverHandler {
                id: hover
                enabled: root.config.overlayOnHover
                property var hoveredLines: ({})

                function updateHovered(pos) {
                    for (var li = 0; li < panel.lines.length; li++) {
                        var b = panel.lines[li].aabb;
                        hoveredLines[li] = pos.x < b.x + b.width + root.config.boxMargin && pos.x > b.x - root.config.boxMargin && pos.y < b.y + b.height + root.config.boxMargin && pos.y > b.y - root.config.boxMargin;
                    }
                    hoveredLines = Object.assign({}, hoveredLines); // trigger binding
                }

                onPointChanged: hover.updateHovered(point.position)
                onHoveredChanged: if (!hovered) {
                    hover.hoveredLines = {};
                }
            }

            Selector {
                id: selector
                lines: panel.lines
            }

            CombinedLineRects {
                id: combined
                rects: panel.lineRects
            }

            property alias yomitanLookup: yomitanLookup
            YomitanLookup {
                id: yomitanLookup
                anchors.fill: parent
                lines: panel.lines
                popup: yomitanPopup
                config: root.config.yomitan
            }

            YomitanPopup {
                id: yomitanPopup
                config: root.config.yomitan
                ankiConfig: root.config.anki
                onVisibleChanged: panel.updateRegions()
                screen: panel.screen
            }

            Item {
                id: overlay
                anchors.fill: parent
                visible: root.showOverlay

                Repeater {
                    model: panel.lines
                    delegate: Item {
                        id: line
                        required property var modelData
                        required property int index
                        property bool isVertical: modelData.is_vertical ?? false
                        property string text: modelData.text
                        property bool hovered: (hover.hoveredLines[line.index] ?? false)

                        Rectangle {
                            id: lineRect
                            property bool _visible: overlay.visible && (!root.config.overlayOnHover || line.hovered)
                            visible: false
                            x: parent.modelData.aabb.x - root.config.boxMargin
                            y: parent.modelData.aabb.y - root.config.boxMargin
                            width: parent.modelData.aabb.width + root.config.boxMargin * 2
                            height: parent.modelData.aabb.height + root.config.boxMargin * 2

                            color: root.config.background
                            border.color: root.config.borderColor
                            border.width: root.config.border
                        }

                        Component.onCompleted: {
                            var arr = panel.lineRects.slice();
                            arr.push(lineRect);
                            panel.lineRects = arr;
                        }

                        Repeater {
                            model: parent.modelData.words
                            delegate: Item {
                                id: word
                                required property var modelData
                                required property int index
                                property string text: modelData.text
                                property bool isVertical: line.isVertical

                                Rectangle {
                                    id: wordSpaceRect
                                    visible: selector.dragging && (selector.selWords[line.index + "-" + word.index] !== undefined)
                                    x: parent.modelData.whitespace_box.x ?? 0
                                    y: parent.modelData.whitespace_box.y ?? 0
                                    width: parent.modelData.whitespace_box.width
                                    height: parent.modelData.whitespace_box.height
                                    rotation: Math.abs(parent.modelData.whitespace_box.angle ?? 0) <= 5 ? 0 : parent.modelData.whitespace_box.angle
                                    transformOrigin: Item.TopLeft
                                    color: root.config.selectedBackground
                                }
                                Repeater {
                                    model: parent.modelData.symbols
                                    delegate: Item {
                                        id: symbol
                                        required property var modelData
                                        required property int index
                                        property string text: modelData.text
                                        property bool selected: selector.dragging && (selector.selWords[line.index + "-" + word.index + "-" + symbol.index] !== undefined)

                                        Rectangle {
                                            id: symbolRect
                                            visible: parent.selected
                                            x: parent.modelData.box.x
                                            y: parent.modelData.box.y
                                            width: parent.modelData.box.width
                                            height: parent.modelData.box.height
                                            rotation: Math.abs(parent.modelData.box.angle) <= 5 ? 0 : parent.modelData.box.angle
                                            transformOrigin: Item.TopLeft
                                            color: root.config.selectedBackground
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
