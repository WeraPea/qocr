import QtQuick
import Quickshell
import Quickshell.Wayland
import QtWebEngine
import QtWebChannel

Rectangle {
    id: root

    anchors.fill: parent
    visible: yomitanResponse !== ""
    color: "transparent"

    property alias popupWidth: popup.width
    property alias popupHeight: popup.height

    required property var config
    required property var ankiConfig
    required property var screen
    property var yomitanResponse: ""

    function yomitanRequest(endpoint, body, callback) {
        var xhr = new XMLHttpRequest();
        xhr.open("POST", config.apiUrl + "/" + endpoint);
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200)
                callback(JSON.parse(xhr.responseText));
        };
        xhr.send(JSON.stringify(body));
    }

    function ankiConnectRequest(action, version, params, callback) {
        const xhr = new XMLHttpRequest();
        xhr.open('POST', ankiConfig.ankiConnectUrl);
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                const response = JSON.parse(xhr.responseText);
                if (response.error) {
                    throw response.error;
                } else {
                    if (response.hasOwnProperty('result'))
                        callback(response.result);
                }
            }
        };
        xhr.send(JSON.stringify({
            action,
            version,
            params
        }));
    }

    function lookup(term, newPos) {
        yomitanRequest("termEntries", {
            term: term
        }, function (data) {
            if ((data.dictionaryEntries?.length ?? 0) > 0) {
                yomitanResponse = data;
                view.loadHtml(root.buildHtml(yomitanResponse, term));
                if (newPos) {
                    popup.x = newPos.x;
                    popup.y = newPos.y;
                }
            }
        });
    }

    function addToAnki(term, index) {
        var yomitanAnkiFields = [];
        for (const [key, value] of Object.entries(ankiConfig.fields)) {
            var rx = /\{([^}]+)\}/g;
            var match;
            while (match = rx.exec(value)) {
                yomitanAnkiFields.push(match[1]);
            }
        }

        yomitanRequest("ankiFields", {
            text: term,
            type: "term",
            markers: yomitanAnkiFields,
            includeMedia: true,
            maxEntries: index + 1
        }, function (data) {
            var ankiFields = {};
            for (const [key, value] of Object.entries(ankiConfig.fields)) {
                var ankiField = value;
                for (const [kkey, vvalue] of Object.entries(data.fields[index])) { // assumes termEntries and ankiFields match
                    ankiField = ankiField.replace(`{${kkey}}`, vvalue);
                }
                ankiFields[key] = ankiField;
            }

            for (var i = 0; i < data.dictionaryMedia.length; i++) {
                if (Object.values(ankiFields).some(v => v.includes(data.dictionaryMedia[i].ankiFilename)))
                    ankiConnectRequest('storeMediaFile', 6, {
                        filename: data.dictionaryMedia[i].ankiFilename,
                        data: data.dictionaryMedia[i].content
                    }, function (res) {
                        console.log("added media " + res);
                    });
            }

            for (var i = 0; i < data.audioMedia.length; i++) {
                if (Object.values(ankiFields).some(v => v.includes(data.audioMedia[i].ankiFilename)))
                    ankiConnectRequest('storeMediaFile', 6, {
                        filename: data.audioMedia[i].ankiFilename,
                        data: data.audioMedia[i].content
                    }, function (res) {
                        console.log("added media " + res);
                    });
            }

            ankiConnectRequest('addNote', 6, {
                note: {
                    deckName: ankiConfig.deck,
                    modelName: ankiConfig.model,
                    tags: ankiConfig.tags,
                    fields: ankiFields,
                    options: {
                        allowDuplicate: ankiConfig.allowDuplicate
                    }
                }
            }, function (res) {
                console.log("added card " + res);
            });
        });
    }

    function clear() {
        yomitanResponse = "";
        view.loadHtml("");
    }

    function buildHtml(data, term) {
        var entries = data.dictionaryEntries ?? [];

        var body = `
          <form onsubmit="submitQuery(); return false;" class="lookup">
            <input type="text" id="lquery" value="${term}">
            <button type="submit">Lookup</button>
          </form>
          <script src="qrc:///qtwebchannel/qwebchannel.js"></script>
          <script>
          let bridge = null;
          new QWebChannel(qt.webChannelTransport, function(channel) {
              bridge = channel.objects.bridge;
          });
          function submitQuery() {
              var q = document.getElementById("lquery").value;
              if (bridge) {
                  bridge.lookup(q);
              }
          }
          function addToAnki(term, index) {
              if (bridge) {
                  bridge.addToAnki(term, index);
              }
          }
          </script>
        `;

        for (var ei = 0; ei < entries.length; ei++) {
            var entry = entries[ei];
            if (ei > 0)
                body += '<hr class="entry-sep">';
            body += buildEntry(entry, term, ei);
        }

        return `<!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
        html, body {
            background: ${config.backgroundColor};
            color: ${config.foregroundColor};
            font-family: sans-serif;
            font-size: 14px;
            padding: 5px 6px;
            margin: 0;
            --fg: ${config.foregroundColor};
            --text-color: ${config.foregroundColor};
            --font-size-no-units: 14;
        }

        hr.entry-sep {
            border: none;
            border-top: 1px solid ${config.separatorColor};
            margin: 8px -12px;
        }
        .entry-header { display: flex; align-items: center; gap: 10px; margin-bottom: 6px; }
        .term    { font-size: 2em; }
        .reading { font-size: 1.2em; color: #66d9ee; }
        .inflections { font-size: 0.9em; color: ${config.foregroundSecondaryColor}; margin-bottom: 0.2em; }
        .freqs { display: flex; flex-wrap: wrap; gap: 5px; margin-bottom: 6px; }
        .freq-pill { display: inline-flex; border: 1px solid #489148; border-radius: 0.25em }
        .freq-name { background: #489148; font-size: 0.8em; color: white; font-weight: bold; padding: 0.4em 0.2em; }
        .freq-val  { padding: 0.2em 0.2em; }
        .def-header { display: flex; flex-wrap: wrap; align-items: center; gap: 0.2em; margin-bottom: 0.2em; }
        .badge {
            display: inline-block;
            font-size: 0.8em;
            font-weight: bold;
            padding: 0.2em 0.3em;
            word-break: keep-all;
            border-radius: 0.25em;
            vertical-align: text-bottom;
            color: white;
        }
        .badge-star { background: #025CAA; }
        .badge-dict { background: #9057AD; }

        .lookup {
            display: flex;
            gap: 6px;
            margin-bottom: 8px;
        }
        .lookup input {
            flex: 1;
            background: transparent;
            color: ${config.foregroundColor};
            border: 1px solid ${config.separatorColor};
            border-radius: 0.25em;
            padding: 0.2em 0.3em;
            font-size: 1em;
            outline: none;
        }
        .lookup button {
            background: ${config.foregroundColor};
            color: ${config.backgroundColor};
            border: none;
            border-radius: 0.25em;
            padding: 0.2em 0.3em;
            font-size: 1em;
            cursor: pointer;
        }
        .lookup input:focus { border-color: ${config.foregroundSecondaryColor}; }
        .lookup button:hover { filter: brightness(1.1); }
        .lookup button:active { filter: brightness(0.9); }

        .anki {
            margin-left: auto;
            background: ${config.foregroundColor};
            color: ${config.backgroundColor};
            border: none;
            border-radius: 0.25em;
            padding: 0.2em 0.3em;
            font-size: 1em;
            cursor: pointer;
        }
        .anki:hover { filter: brightness(1.1); }
        .anki:active { filter: brightness(0.9); }

        ::-webkit-scrollbar { width: 6px; }
        ::-webkit-scrollbar-track { background: ${config.backgroundColor}; }
        ::-webkit-scrollbar-thumb { background: ${config.foregroundSecondaryColor}; border-radius: 3px; }
        ${config.extraCss}
        </style>
        </head><body>${body}</body></html>`;
    }

    function buildEntry(entry, term, index) {
        var hw = entry.headwords?.[0] ?? {};
        var html = '<div class="entry">';

        // term + reading + anki button header
        html += '<div class="entry-header">';
        html += '<span class="term">' + (hw.term ?? "") + '</span>';
        if (hw.reading && hw.reading !== hw.term)
            html += '<span class="reading">' + (hw.reading) + '</span>';
        html += `<button class="anki" onclick="addToAnki('${term}', ${index})">+</button>`;
        html += '</div>';

        // inflections
        var rules = entry.inflectionRuleChainCandidates?.[0]?.inflectionRules ?? [];
        if (rules.length > 0) {
            html += '<div class="inflections">';
            html += rules.map(r => "• " + (r.name ?? r)).join("  ");
            html += '</div>';
        }

        // frequencies
        var freqs = groupFrequencies(entry.frequencies ?? []);
        if (freqs.length > 0) {
            html += '<div class="freqs">';
            for (var fi = 0; fi < freqs.length; fi++) {
                var freq = freqs[fi];
                html += '<span class="freq-pill"><span class="freq-name">' + (freq.name) + '</span>';
                html += '<span class="freq-val">';
                for (var fvi = 0; fvi < freq.values.length; fvi++) {
                    if (fvi > 0 && fvi - 1 < freq.values.length)
                        html += ", ";
                    html += (freq.values[fvi]);
                }
                html += '</span></span>';
            }
            html += '</div>';
        }

        // pronunciations: not planned for now

        // definitions
        var defs = entry.definitions ?? [];
        for (var di = 0; di < defs.length; di++) {
            var def = defs[di];
            html += '<div class="def-block">';
            html += '<div class="def-header">';

            // tags (★ etc.) as blue badges
            var tags = def.tags ?? [];
            for (var ti = 0; ti < tags.length; ti++) {
                var tag = tags[ti];
                var tip = (tag.content ?? []).join(", ");
                html += '<span class="badge badge-star" title="' + tip + '">' + (tag.name ?? "") + '</span>';
            }
            // dictionary name as purple badge
            if (def.dictionary)
                html += '<span class="badge badge-dict">' + def.dictionary + '</span>';
            html += '</div>';

            var entries = def.entries ?? [];
            for (var ei = 0; ei < entries.length; ei++) {
                var ent = entries[ei];
                if (ent.type === "structured-content")
                    html += renderNode(ent.content);
                else if (typeof ent === "string")
                    html += '<div style="white-space: pre-wrap">' + ent + "</div>";
            }
            html += '</div>';
        }

        html += '</div>';
        return html;
    }

    // Recursively render a dictionary's structured-content node to HTML.
    function renderNode(node) {
        if (typeof node === "string")
            return node;
        if (Array.isArray(node)) {
            var s = "";
            for (var i = 0; i < node.length; i++)
                s += renderNode(node[i]);
            return s;
        }

        var tag = node.tag;
        var dc = node.data?.content;

        if (tag === "br")
            return "<br>";

        // skip for now
        if (dc === "attribution")
            return "";

        if (!tag)
            return renderNode(node.content);

        var attrs = "";

        if (node.lang)
            attrs += ' lang="' + node.lang + '"';
        if (node.href)
            attrs += ' href="' + node.href + '"';
        if (node.title)
            attrs += ' title="' + node.title + '"';
        if (node.rowSpan)
            attrs += ' rowspan="' + node.rowSpan + '"';
        if (node.colSpan)
            attrs += ' colspan="' + node.colSpan + '"';

        if (node.style) {
            var styleStr = styleObjToString(node.style);
            if (styleStr)
                attrs += ' style="' + styleStr + '"';
        }

        if (node.data) {
            for (var k in node.data)
                attrs += ' data-' + k + '="' + (String(node.data[k])) + '"';
        }

        if (node.content)
            var inner = renderNode(node.content);
        else
            inner = "";

        return "<" + tag + attrs + ">" + inner + "</" + tag + ">";
    }

    function styleObjToString(styleObj) {
        var parts = [];
        for (var prop in styleObj) {
            var val = String(styleObj[prop]);
            var cssProp = prop.replace(/([A-Z])/g, m => "-" + m.toLowerCase());
            parts.push(cssProp + ":" + val);
        }
        return parts.join(";");
    }

    function groupFrequencies(freqs) {
        var groups = [], map = {};
        for (var i = 0; i < freqs.length; i++) {
            var f = freqs[i];
            var name = f.dictionaryAlias || f.dictionary;
            if (!map[name]) {
                map[name] = {
                    name: name,
                    values: []
                };
                groups.push(map[name]);
            }
            map[name].values.push(f.displayValue ?? String(f.frequency));
        }
        return groups;
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onTapped: root.clear()
    }

    PanelWindow {
        screen: root.screen
        anchors {
            left: true
            right: true
            top: true
            bottom: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: root.visible
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Top // below the popup
        Shortcut {
            sequence: "Escape"
            onActivated: root.clear()
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onTapped: root.clear()
        }
    }

    PanelWindow {
        screen: root.screen
        anchors {
            left: true
            right: true
            top: true
            bottom: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: root.visible
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay
        Shortcut {
            sequence: "Escape"
            onActivated: root.clear()
        }

        mask: Region {
            item: popup
        }

        Rectangle {
            id: popup

            width: 400
            height: 480
            color: root.config.backgroundColor

            WebEngineView {
                id: view
                anchors.fill: parent
                backgroundColor: root.config.backgroundColor

                onContextMenuRequested: function (req) {
                    req.accepted = true;
                }
                webChannel: channel
                WebChannel {
                    id: channel
                    registeredObjects: [bridge]
                }
                QtObject {
                    id: bridge
                    WebChannel.id: "bridge"

                    function lookup(term) {
                        root.lookup(term, null);
                    }
                    function addToAnki(term, index) {
                        root.addToAnki(term, index);
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: root.config.borderColor
                border.width: 1
            }
        }
    }
}
