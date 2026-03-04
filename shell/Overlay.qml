pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick.Layouts
import QtQuick

Item {
    id: root
    property var ocrData: ({})

    FileView {
        path: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/qocr/config.json`
        watchChanges: true
        onFileChanged: reload()
        JsonAdapter {
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
        }
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
                    var updated = Object.assign({}, root.ocrData); // copy to trigger binding
                    updated[parsed.monitor] = parsed;
                    root.ocrData = updated;
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
        onExited: (c, s) => console.log(c, s)
        running: true
    }

    Item {
        id: ocr
        property bool showRegion: false
        IpcHandler {
            target: "ocr"

            function scan(): void {
                ocrProc.write(`scan ${config.japaneseOnly} false\n`);
            }
            function scan_fullscreen(): void {
                ocrProc.write(`scan ${config.japaneseOnly} true\n`);
            }
            function rescan(): void {
                Object.entries(root.ocrData).forEach(([monitor, data]) => {
                    var r = data.region;
                    ocrProc.write(`rescan ${config.japaneseOnly} ${r.x} ${r.y} ${r.w} ${r.h} ${r.X} ${r.Y} ${monitor}\n`);
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
                    config[setting] = true;
                else if (value.toLowerCase() === "false")
                    config[setting] = false;
                else if (!isNaN(value))
                    config[setting] = Number(value);
                else
                    config[setting] = value;
            }
            function toggle_config(setting: string): void {
                if (setting === "viewMode")
                    config[setting] = config[setting] === "hover" ? "always" : "hover";
                else if (setting === "japaneseOnly")
                    config[setting] = config[setting] ? false : true;
            }
            function get_config(setting: string): string {
                return config[setting];
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

        PanelWindow {
            id: panel

            required property var modelData
            screen: modelData

            property var regionItems: []
            property var ocrData: root.ocrData[screen.name] ?? {}
            property var lines: ocrData.lines ?? []
            property var region: ocrData.region

            onOcrDataChanged: panel.regionItems = []

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
                    color: config.regionBackground
                    border.color: config.regionBorder
                    border.width: 2
                }
            }

            HoverHandler {
                id: hover
                enabled: config.viewMode === "hover"
                property var hoveredLines: ({})

                function updateHovered(pos) {
                    for (var li = 0; li < lines.length; li++) {
                        var b = lines[li].aabb;
                        hoveredLines[li] = pos.x < b.x + b.width + config.boxMargin && pos.x > b.x - config.boxMargin && pos.y < b.y + b.height + config.boxMargin && pos.y > b.y - config.boxMargin;
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
                rects: panel.regionItems
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
                            property bool _visible: config.viewMode === "always" || line.hovered
                            visible: false
                            x: parent.modelData.aabb.x - config.boxMargin
                            y: parent.modelData.aabb.y - config.boxMargin
                            width: parent.modelData.aabb.width + config.boxMargin * 2
                            height: parent.modelData.aabb.height + config.boxMargin * 2

                            color: config.background
                            border.color: config.borderColor
                            border.width: config.border
                        }

                        Component.onCompleted: {
                            var arr = panel.regionItems.slice();
                            arr.push(lineRect);
                            panel.regionItems = arr;
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
                                    color: config.selectedBackground
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
                                            color: config.selectedBackground
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
