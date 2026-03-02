import QtQuick

Rectangle {
    required property string mode // "border" | "borderless" | "shape"
    required property Rectangle source

    x: mode === "border" ? source.x : source.x + source.border.width
    y: mode === "border" ? source.y : source.y + source.border.width
    width: mode === "border" ? source.width : source.width - source.border.width * 2
    height: mode === "border" ? source.height : source.height - source.border.width * 2

    visible: source._visible
    color: mode === "shape" ? "white" : mode === "border" ? Qt.rgba(source.border.color.r, source.border.color.g, source.border.color.b, 1) : Qt.rgba(source.color.r, source.color.g, source.color.b, 1)
}
