import QtQuick

Item {
    id: root
    required property var popup
    required property var lines
    required property int textScanLength
    TapHandler {
        acceptedButtons: Qt.MiddleButton
        onTapped: tap => {
            var pos = tap.position;
            var best = null;
            var bestDist = Infinity;

            for (var li = 0; li < root.lines.length; li++) {
                for (var wi = 0; wi < root.lines[li].words.length; wi++) {
                    var symbols = root.lines[li].words[wi].symbols;
                    for (var si = 0; si < symbols.length; si++) {
                        var b = symbols[si].box;
                        var dist = obbDist(pos, b);
                        if (dist < bestDist) {
                            bestDist = dist;
                            best = {
                                li: li,
                                wi: wi,
                                si: si
                            };
                        }
                    }
                }
            }

            if (best === null)
                return;

            var text = "";
            outer: for (var li = best.li; li < root.lines.length; li++) {
                var words = root.lines[li].words;
                for (var wi = (li === best.li ? best.wi : 0); wi < words.length; wi++) {
                    var syms = words[wi].symbols;
                    for (var si = (li === best.li && wi === best.wi ? best.si : 0); si < syms.length; si++) {
                        text += syms[si].text;
                        if (text.replace(/\s/g, '').length >= root.textScanLength)
                            break outer;
                    }
                    if (words[wi].has_space_after)
                        text += " ";
                }
                if (li < root.lines.length - 1)
                    text += "\n";
            }

            var hitBox = root.lines[best.li].words[best.wi].symbols[best.si].aabb;
            var x, y;
            x = hitBox.x + 10;
            if (x + root.popup.width > Screen.width)
                x = Screen.width - root.popup.width;
            y = hitBox.y - root.popup.height - 10;
            if (y < 0)
                y = hitBox.y + hitBox.height + 10;
            root.popup.lookup(text, {
                x: x,
                y: y
            });
        }

        function obbDist(pos, box) {
            var angle = box.angle * Math.PI / 180;
            var cos = Math.cos(-angle), sin = Math.sin(-angle);
            var dx = pos.x - box.x, dy = pos.y - box.y;
            var lx = cos * dx - sin * dy;
            var ly = sin * dx + cos * dy;
            var cx = Math.max(0, Math.min(box.width, lx));
            var cy = Math.max(0, Math.min(box.height, ly));
            var ex = lx - cx, ey = ly - cy;
            return Math.sqrt(ex * ex + ey * ey);
        }
    }
}
