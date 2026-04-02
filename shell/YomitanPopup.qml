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
    property var line: ""
    property var symbolIndex

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

    function lookup(term, newPos, line, index) {
        yomitanRequest("termEntries", {
            term: term
        }, function (data) {
            if ((data.dictionaryEntries?.length ?? 0) > 0) {
                view.loadHtml("");
                yomitanResponse = data;
                root.line = line;
                root.symbolIndex = index;
                view.loadHtml(root.buildHtml(yomitanResponse, term), "http://dummy.domain/");
                checkAnki(term);
                getMedia(term);
                if (newPos) {
                    popup.x = newPos.x;
                    popup.y = newPos.y;
                }
            }
        });
    }

    function replaceCloze(field, entryIndex) {
        if (!/\{cloze-.*?\}/.test(field) || root.line == null || root.symbolIndex == null) {
            return field;
        }

        var primarySource = null;
        for (let i = 0; i < yomitanResponse.dictionaryEntries[entryIndex].headwords.length; i++) {
            primarySource = yomitanResponse.dictionaryEntries[entryIndex].headwords[i].sources.find(s => s.isPrimary);
            if (primarySource)
                break;
        }
        if (!primarySource) {
            return field;
        }

        const clozeBody = primarySource.originalText;
        const clozePrefix = root.line.slice(0, root.symbolIndex);
        const clozeSuffix = root.line.slice(root.symbolIndex + clozeBody.length);

        field = field.replace(/{cloze-prefix}/g, clozePrefix);
        field = field.replace(/{cloze-body}/g, clozeBody);
        field = field.replace(/{cloze-suffix}/g, clozeSuffix);

        return field;
    }

    function addToAnki(term, index) {
        var yomitanAnkiFields = [];
        for (const [key, value] of Object.entries(ankiConfig.fields)) {
            var rx = /\{([^}]+)\}/g;
            var match;
            while (match = rx.exec(value)) {
                if (!yomitanAnkiFields.includes(match[1])) {
                    yomitanAnkiFields.push(match[1]);
                }
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
                    ankiField = replaceCloze(ankiField, index);
                    ankiField = ankiField.replace(new RegExp(`\\{${kkey}\\}`, 'g'), vvalue);
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
                checkAnki(term);
            });
        });
    }

    function checkAnki(term) {
        ankiConnectRequest('modelFieldNames', 6, {
            modelName: ankiConfig.model
        }, function (modelFieldNamesResult) {
            var yomitanAnkiFields = [];
            const firstFieldName = modelFieldNamesResult[0];
            const firstFieldValue = ankiConfig.fields[firstFieldName];
            var rx = /\{([^}]+)\}/g;
            var match;
            while (match = rx.exec(firstFieldValue)) {
                if (!yomitanAnkiFields.includes(match[1])) {
                    yomitanAnkiFields.push(match[1]);
                }
            }

            yomitanRequest("ankiFields", {
                text: term,
                type: "term",
                markers: yomitanAnkiFields,
                includeMedia: false
            }, function (ankiFieldsResult) {
                var notes = [];
                var notesIndexes = new Map();
                for (var i = 0; i < ankiFieldsResult.fields.length; i++) {
                    var ankiField = firstFieldValue;
                    for (const [kkey, vvalue] of Object.entries(ankiFieldsResult.fields[i])) { // assumes termEntries and ankiFields match
                        ankiField = replaceCloze(ankiField, i);
                        ankiField = ankiField.replace(new RegExp(`\\{${kkey}\\}`, 'g'), vvalue);
                    }

                    if (!notesIndexes.has(ankiField)) {
                        notesIndexes.set(ankiField, [i]);
                    } else {
                        notesIndexes.get(ankiField).push(i);
                        continue;
                    }

                    notes.push({
                        deckName: ankiConfig.deck,
                        modelName: ankiConfig.model,
                        fields: {
                            [firstFieldName]: ankiField
                        },
                        options: {
                            allowDuplicate: false
                        }
                    });
                }

                ankiConnectRequest('canAddNotesWithErrorDetail', 6, {
                    notes: notes
                }, function (canAddNotesResult) {
                    var actions = [];
                    var actionsIndexes = [];

                    for (var i = 0; i < canAddNotesResult.length; i++) {
                        const res = canAddNotesResult[i];
                        if (res.error === "cannot create note because it is a duplicate") {
                            const ankiField = notes[i].fields[firstFieldName];
                            actionsIndexes.push(notesIndexes.get(ankiField));
                            actions.push({
                                action: "findCards",
                                version: 6,
                                params: {
                                    query: `"${firstFieldName}:${ankiField}" "deck:${ankiConfig.deck}"`
                                }
                            });
                        }
                    }

                    ankiConnectRequest('multi', 6, {
                        actions: actions
                    }, function (findCardsResults) {
                        var cards = [];
                        var cardsIndexes = new Map();
                        for (var i = 0; i < findCardsResults.length; i++) {
                            for (var j = 0; j < findCardsResults[i].result.length; j++) {
                                const id = findCardsResults[i].result[j];
                                cardsIndexes.set(id, actionsIndexes[i]);
                                cards.push(id);
                            }
                        }

                        ankiConnectRequest('areSuspended', 6, {
                            cards: cards
                        }, function (areSuspendedResult) {
                            let entriesInfo = {};

                            for (var i = 0; i < findCardsResults.length; i++) {
                                const cardIds = findCardsResults[i].result;
                                if (cardIds.length < 1) {
                                    continue;
                                }
                                const allSuspended = cardIds.every(id => areSuspendedResult[cards.indexOf(id)]);

                                const entryIndexes = cardsIndexes.get(cardIds[0]); // assumes all duplicates map to same note

                                for (const ei of entryIndexes) {
                                    entriesInfo[ei] = {
                                        suspended: allSuspended,
                                        cardIds: cardIds
                                    };
                                }
                            }

                            view.runJavaScript(`
                                (function() {
                                    const entriesInfo = ${JSON.stringify(entriesInfo)};
                                    function updateEntry(idx) {
                                        const entry = document.querySelector('.entry[data-index="' + idx + '"]');
                                        if (!entry) {
                                            return false;
                                        }

                                        const entryInfo = entriesInfo[idx];
                                        const header = entry.querySelector('.entry-header');
                                        const addButton = entry.querySelector('.anki-add');

                                        if (addButton) {
                                            addButton.classList.remove("anki-suspended");
                                            if (entryInfo.suspended) {
                                                addButton.classList.add("anki-suspended");
                                            }
                                            addButton.classList.add("anki-duplicate");
                                            addButton.innerText = "✓";
                                        }

                                        const existingViewButton = entry.querySelector('.anki-view');
                                        if (existingViewButton) {
                                            existingViewButton.remove();
                                        }
                                        if (header && addButton) {
                                            const viewButton = document.createElement('button');
                                            viewButton.className = 'anki anki-view';
                                            if (entryInfo.suspended) {
                                                viewButton.classList.add("anki-suspended");
                                            }
                                            viewButton.innerText = "↗";
                                            viewButton.onclick = () => {
                                                if (bridge) {
                                                    bridge.viewInAnki(entryInfo.cardIds);
                                                }
                                            };
                                            header.insertBefore(viewButton, addButton);
                                        }
                                        return true;
                                    }

                                    function applyAll() {
                                        const keys = Object.keys(entriesInfo);
                                        for (let i = 0; i < keys.length; i++) {
                                            const idx = keys[i];
                                            if (updateEntry(idx)) {
                                                delete entriesInfo[idx];
                                            }
                                        }
                                    }

                                    applyAll();

                                    if (Object.keys(entriesInfo).length > 0) {
                                        const observer = new MutationObserver((mutations, obs) => {
                                            applyAll();
                                            if (Object.keys(entriesInfo).length === 0) {
                                                obs.disconnect();
                                            }
                                        });
                                        observer.observe(document.body, { childList: true, subtree: true });
                                    }
                                })();
                            `);
                        });
                    });
                });
            });
        });
    }

    function viewInAnki(ids) {
        ankiConnectRequest('guiBrowse', 6, {
            query: "cid:" + ids.join(',')
        }, function (res) {
            console.log("opened cards " + res);
        });
    }

    function getMedia(term) {
        yomitanRequest("ankiFields", {
            text: term,
            type: "term",
            markers: ["glossary", ...(config.fetchAudio ? ["audio"] : [])],
            includeMedia: true
        }, function (ankiFieldsResult) {
            if (config.fetchAudio) {
                view.runJavaScript(`
                    (function() {
                        var audioMedia = ${JSON.stringify(ankiFieldsResult.audioMedia)};
                        var fields = ${JSON.stringify(ankiFieldsResult.fields)};

                        function updateMedia() {
                            const entries = document.querySelectorAll('.entry');
                            if (entries.length !== ${yomitanResponse.dictionaryEntries.length}) {
                                return false;
                            }
                            for (let i = 0; i < entries.length; i++) {
                                const entry = entries[i];
                                const header = entry.querySelector('.entry-header');

                                if (header) {
                                    const audioButton = document.createElement('button');
                                    audioButton.className = 'audio';
                                    audioButton.innerText = "A";
                                    audioButton.onclick = () => {
                                        const filename = fields[i].audio.slice(7, -1); // remove "[sound:" "]"
                                        const audio = audioMedia.find(m => m.ankiFilename === filename);
                                        if (audio) {
                                            new Audio('data:' + audio.mediaType + ';base64,' + audio.content).play()
                                        }
                                    };
                                    header.appendChild(audioButton);
                                }
                            }

                            return true;
                        }

                        if (!updateMedia()) {
                            const observer = new MutationObserver((mutations, obs) => {
                                if (updateMedia()) {
                                    obs.disconnect();
                                }
                            });
                            observer.observe(document.body, { childList: true, subtree: true });
                        }
                    })();
                `);
            }

            view.runJavaScript(`
                (function() {
                    var mediaInfo = ${JSON.stringify(ankiFieldsResult.dictionaryMedia)};
                    function updateMedia(media) {
                        const imgs = document.querySelectorAll('img[data-dict-path="' + media.path + '"][data-dict-name="' + media.dictionary + '"]');
                        if (imgs.length === 0) {
                            return false;
                        }
                        for (let i = 0; i < imgs.length; i++) {
                            imgs[i].src = 'data:' + media.mediaType + ';base64,' + media.content;
                        }
                        return true;
                    }

                    function applyAll() {
                        var remaining = [];
                        for (let i = 0; i < mediaInfo.length; i++) {
                            if (!updateMedia(mediaInfo[i])) {
                              remaining.push(mediaInfo[i]);
                            }
                        }
                        mediaInfo = remaining;
                    }

                    applyAll();

                    if (mediaInfo.length > 0) {
                        const observer = new MutationObserver((mutations, obs) => {
                            applyAll();
                            if (mediaInfo.length === 0) {
                                obs.disconnect();
                            }
                        });
                        observer.observe(document.body, { childList: true, subtree: true });
                    }
                })();
            `);
        });
    }

    function clear() {
        view.loadHtml("");
        yomitanResponse = "";
    }

    function buildHtml(data, term) {
        var entries = data.dictionaryEntries ?? [];

        var body = `
          <form onsubmit="submitQuery(); return false;" class="lookup">
            <input type="text" id="lquery" value='${term.replace(/&/g, "&amp;").replace(/'/g, "&apos;").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;")}'>
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

        button.anki:first-of-type {
            margin-left: auto;
        }
        .anki {
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
        .anki-duplicate { background-color: #489148; }
        .anki-add.anki-suspended { background-color: #d4c96e; }

        ::-webkit-scrollbar { width: 6px; }
        ::-webkit-scrollbar-track { background: ${config.backgroundColor}; }
        ::-webkit-scrollbar-thumb { background: ${config.foregroundSecondaryColor}; border-radius: 3px; }
        ${config.extraCss}
        </style>
        </head><body>${body}</body></html>`;
    }

    function buildEntry(entry, term, index) {
        var hw = entry.headwords?.[0] ?? {};
        var html = `<div class="entry" data-index="${index}">`;

        // term + reading + anki button header
        html += '<div class="entry-header">';
        html += '<span class="term">' + (hw.term ?? "") + '</span>';
        if (hw.reading && hw.reading !== hw.term)
            html += '<span class="reading">' + (hw.reading) + '</span>';
        html += `<button class="anki anki-add" onclick='addToAnki(${JSON.stringify(term).replace(/'/g, "&apos;")}, ${index})'>＋</button>`;
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
                    html += renderNode(ent.content, def.dictionary);
                else if (typeof ent === "string")
                    html += '<div style="white-space: pre-wrap">' + ent + "</div>";
            }
            html += '</div>';
        }

        html += '</div>';
        return html;
    }

    // Recursively render a dictionary's structured-content node to HTML.
    function renderNode(node, dictionary) {
        if (typeof node === "string")
            return node;
        if (Array.isArray(node)) {
            var s = "";
            for (var i = 0; i < node.length; i++)
                s += renderNode(node[i], dictionary);
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
            return renderNode(node.content, dictionary);

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

        if (tag === "img" && node.path) {
            attrs += ' data-dict-name="' + dictionary + '"';
            attrs += ' data-dict-path="' + node.path + '"';

            let style = "";
            const sizeUnits = node.sizeUnits || "px";
            const width = node.preferredWidth || node.width;
            const height = node.preferredHeight || node.height;

            if (width)
                style += `width:${width}${sizeUnits};`;
            if (height)
                style += `height:${height}${sizeUnits};`;
            if (node.verticalAlign)
                style += `vertical-align:${node.verticalAlign};`;

            attrs += ' style="' + style + '"';

            if (node.alt) {
                attrs += ' alt="' + node.alt + '"';
            }
        }

        if (node.content)
            var inner = renderNode(node.content, dictionary);
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
                        root.lookup(term, null, null, null);
                    }
                    function addToAnki(term, index) {
                        root.addToAnki(term, index);
                    }
                    function viewInAnki(ids) {
                        root.viewInAnki(ids);
                    }
                }
                onNavigationRequested: function (req) {
                    if (req.navigationType === WebEngineNavigationRequest.LinkClickedNavigation) {
                        req.reject();
                        var url = req.url.toString();
                        if (url.startsWith("http://dummy.domain/")) {
                            var params = new URLSearchParams(req.url.toString().split("?")[1] ?? "");
                            if (params.has("query")) {
                                var term = decodeURIComponent(params.get("query"));
                                root.lookup(term, null, null, null);
                            }
                        } else {
                            Qt.openUrlExternally(req.url);
                        }
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
