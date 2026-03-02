import QtQuick
import Quickshell

Item {
    id: selector
    required property var lines
    anchors.fill: parent
    property var selWords: ({})
    property bool dragging: false
    property point dragStart: Qt.point(0, 0)
    property point dragEnd: Qt.point(0, 0)

    function boxCorners(b) {
        var ox = b.x, oy = b.y;
        var w = b.width, h = b.height;
        var a = b.angle * Math.PI / 180;
        var cos = Math.cos(a), sin = Math.sin(a);
        // Rotate each corner offset around top-left (ox, oy)
        function rot(dx, dy) {
            return [ox + cos * dx - sin * dy, oy + sin * dx + cos * dy];
        }
        return [rot(0, 0), rot(w, 0), rot(w, h), rot(0, h)];
    }

    function project(corners, ax, ay) {
        var min = Infinity, max = -Infinity;
        for (var i = 0; i < corners.length; i++) {
            var d = corners[i][0] * ax + corners[i][1] * ay;
            if (d < min)
                min = d;
            if (d > max)
                max = d;
        }
        return [min, max];
    }

    function boxesIntersect(a, b) {
        // Fast AABB path when both boxes are unrotated
        if (Math.abs(a.angle) <= 5 && Math.abs(b.angle) <= 5) {
            return a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y;
        }
        var ca = boxCorners(a), cb = boxCorners(b);
        var axes = [[ca[1][0] - ca[0][0], ca[1][1] - ca[0][1]], [ca[3][0] - ca[0][0], ca[3][1] - ca[0][1]], [cb[1][0] - cb[0][0], cb[1][1] - cb[0][1]], [cb[3][0] - cb[0][0], cb[3][1] - cb[0][1]],];
        for (var i = 0; i < axes.length; i++) {
            var ax = axes[i][0], ay = axes[i][1];
            var pa = project(ca, ax, ay);
            var pb = project(cb, ax, ay);
            if (pa[1] < pb[0] || pb[1] < pa[0])
                return false;
        }
        return true;
    }

    function wordsInDrag() {
        var db = {
            x: Math.min(dragStart.x, dragEnd.x),
            y: Math.min(dragStart.y, dragEnd.y),
            width: Math.abs(dragStart.x - dragEnd.x),
            height: Math.abs(dragStart.y - dragEnd.y),
            angle: 0
        };
        var hits = {};
        for (var li = 0; li < lines.length; li++) {
            if (!boxesIntersect(lines[li].aabb, db))
                continue;
            var words = lines[li].words;
            for (var wi = 0; wi < words.length; wi++) {
                if (!boxesIntersect(words[wi].aabb, db))
                    continue;
                var symbols = words[wi].symbols;
                for (var si = 0; si < symbols.length; si++) {
                    if (boxesIntersect(symbols[si].box, db))
                        hits[li + "-" + wi + "-" + si] = {
                            li: li,
                            wi: wi,
                            si: si,
                            text: symbols[si].text
                        };
                }
                if (words[wi].has_space_after) {
                    if (boxesIntersect(words[wi].whitespace_box, db))
                        hits[li + "-" + wi] = {
                            li: li,
                            wi: wi,
                            si: -1,
                            text: " "
                        };
                }
            }
        }
        return hits;
    }

    Rectangle {
        visible: selector.dragging
        x: Math.min(selector.dragStart.x, selector.dragEnd.x)
        y: Math.min(selector.dragStart.y, selector.dragEnd.y)
        width: Math.abs(selector.dragEnd.x - selector.dragStart.x)
        height: Math.abs(selector.dragEnd.y - selector.dragStart.y)
        color: Qt.rgba(border.color.r, border.color.g, border.color.b, border.color.a * 0.5)
        border.color: config.selectedBackground
        border.width: 1
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: tap => {
            for (var li = 0; li < lines.length; li++) {
                if (boxesIntersect({
                    x: tap.position.x,
                    y: tap.position.y,
                    width: 1,
                    height: 1,
                    angle: 0
                }, lines[li].box))
                    Quickshell.execDetached(["wl-copy", lines[li].text]);
            }
        }
    }

    DragHandler {
        id: dragHandler
        target: null
        onActiveChanged: {
            if (active) {
                selector.dragStart = centroid.position;
                selector.dragEnd = centroid.position;
                selector.dragging = true;
                selector.selWords = {};
            } else {
                var entries = Object.values(selector.selWords);
                if (entries.length > 0) {
                    entries.sort(function (a, b) {
                        if (a.li !== b.li)
                            return a.li - b.li;
                        if (a.wi !== b.wi)
                            return a.wi - b.wi;
                        // handle whitespace
                        if (a.si === -1)
                            return 1;
                        if (b.si === -1)
                            return -1;
                        return a.si - b.si;
                    });
                    var prev_li = -1;
                    var text = "";
                    for (var i = 0; i < entries.length; i++) {
                        var s = entries[i];
                        if (prev_li !== -1 && s.li !== prev_li)
                            text += "\n";
                        text += s.text;
                        prev_li = s.li;
                    }
                    Quickshell.execDetached(["wl-copy", text]);
                }
                selector.dragging = false;
            }
        }
        onCentroidChanged: {
            if (!active)
                return;
            selector.dragEnd = centroid.position;
            selector.selWords = selector.wordsInDrag();
        }
    }
}
