import QtQuick

ShaderEffect {
    id: root
    required property Item sourceItem
    required property Item maskItem
    property real opacitySource: 1.0
    property real opacityMask: 1.0

    property var source: ShaderEffectSource {
        sourceItem: root.sourceItem
        width: root.sourceItem.width
        height: root.sourceItem.height
    }

    property var mask: ShaderEffectSource {
        sourceItem: root.maskItem
        width: root.maskItem.width
        height: root.maskItem.height
    }

    fragmentShader: "./ClipMask.frag.qsb"
}
