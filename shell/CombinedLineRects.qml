pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    anchors.fill: parent
    required property var rects

    Item {
        id: borderLayer
        anchors.fill: parent
        opacity: 0
        layer.enabled: true
        Repeater {
            model: root.rects
            delegate: LineRect {
                required property var modelData
                source: modelData
                mode: "border"
            }
        }
    }
    Item {
        id: borderlessLayer
        anchors.fill: parent
        opacity: 0
        layer.enabled: true
        Repeater {
            model: root.rects
            delegate: LineRect {
                required property var modelData
                source: modelData
                mode: "borderless"
            }
        }
    }
    ShaderClipMask {
        opacitySource: root.rects[0]?.border.color.a ?? 0
        opacityMask: root.rects[0]?.color.a ?? 0
        anchors.fill: parent
        sourceItem: borderLayer
        maskItem: borderlessLayer
    }
}
