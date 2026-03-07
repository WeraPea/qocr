pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Item {
    id: root
    property var ocrData: ({})
    property alias config: config

    FileView {
        path: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/qocr/config.json`
        watchChanges: true
        onFileChanged: reload()
        JsonAdapter { // qmllint disable unresolved-type
            id: config
            property int boxMargin: 15
            property int border: 1
            property bool japaneseOnly: true
            property string viewMode: "hover" // hover | always
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
                property string extraCss: ""
                property string apiUrl: "http://127.0.0.1:19633"
                property int textScanLength: 16
            }
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
                try {
                    var parsed = JSON.parse(data);
                    root.updateMonitor(parsed.monitor, parsed);
                } catch (e) {
                    console.log("Parse error:", e);
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
            function rescan(): void {
                Object.entries(root.ocrData).forEach(([monitor, data]) => {
                    var r = data.region;
                    root.updateMonitor(monitor, {});
                    ocrProc.write(`rescan ${root.config.japaneseOnly} ${r.x} ${r.y} ${r.w} ${r.h} ${r.X} ${r.Y} ${monitor}\n`);
                });
            }
            function clear(): void {
                var updated = {};
                Object.keys(root.ocrData).forEach(function (key) {
                    var old = root.ocrData[key];
                    var copy = Object.assign({}, old);
                    copy.lines = [];
                    updated[key] = copy;
                });
                root.ocrData = updated;
            }
            function show_region(): void {
                ocr.showRegion = true;
                regionTimer.restart();
            }
            function set_config(setting: string, value: string): void {
                if (value.toLowerCase() === "true")
                    root.config[setting] = true;
                else if (value.toLowerCase() === "false")
                    root.config[setting] = false;
                else if (!isNaN(value))
                    root.config[setting] = Number(value);
                else
                    root.config[setting] = value;
            }
            function toggle_config(setting: string): void {
                if (setting === "viewMode")
                    root.config[setting] = root.config[setting] === "hover" ? "always" : "hover";
                else if (setting === "japaneseOnly")
                    root.config[setting] = root.config[setting] ? false : true;
            }
            function get_config(setting: string): string {
                return root.config[setting];
            }
        }
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

            onLineRectsChanged: updateRegions()
            onOcrDataChanged: {
                panel.lineRects = [];
            }

            function updateRegions() {
                panel.regionItems = (yomitanPopup.visible ? [yomitanPopup] : []).concat(panel.lineRects);
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
                enabled: root.config.viewMode === "hover"
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

            YomitanLookup {
                anchors.fill: parent
                lines: panel.lines
                popup: yomitanPopup
                textScanLength: root.config.yomitan.textScanLength // qmllint disable missing-property
            }

            YomitanPopup {
                id: yomitanPopup
                config: root.config.yomitan
                onVisibleChanged: panel.updateRegions()
            }

            Item {
                id: overlay
                anchors.fill: parent

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
                            property bool _visible: root.config.viewMode === "always" || line.hovered
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
