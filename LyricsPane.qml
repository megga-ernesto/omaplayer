import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

Rectangle {
    id: root

    required property bool requestActive
    required property string trackTitle
    required property string artist
    required property string album
    required property real duration
    required property real position
    required property bool hasPosition
    required property color ink
    required property color muted
    required property color outline
    signal dismissed

    readonly property string trackKey: trackTitle.trim() && (artist.trim() || /\S\s+[-–—]\s+\S/.test(trackTitle)) ? JSON.stringify([trackTitle.trim(), artist.trim(), album.trim(), Math.round(duration)]) : ""
    readonly property var lines: resultKey === trackKey ? (result.lines ?? []) : []
    readonly property string lookupState: !trackKey ? "metadata" : resultKey === trackKey ? result.state : "loading"
    readonly property int currentLine: {
        if (!hasPosition)
            return -1;
        let low = 0;
        let high = lines.length;
        while (low < high) {
            const middle = (low + high) >> 1;
            if (lines[middle][0] <= position)
                low = middle + 1;
            else
                high = middle;
        }
        return low - 1;
    }

    property string submittedKey: ""
    property string resultKey: ""
    property var result: ({})

    implicitHeight: Style.space(lookupState === "ready" ? 240 : 102)
    radius: Style.space(14)
    color: Qt.alpha(ink, 0.055)
    border.color: outline

    function scheduleLookup() {
        if (requestActive && trackKey && resultKey !== trackKey && !fetch.running)
            lookupDelay.restart();
        else
            lookupDelay.stop();
    }

    onTrackKeyChanged: scheduleLookup()
    onRequestActiveChanged: {
        if (requestActive && lookupState === "error")
            resultKey = "";
        scheduleLookup();
    }
    Component.onCompleted: scheduleLookup()

    Commons.Translations {
        id: strings
        directory: Qt.resolvedUrl("i18n")
    }

    Timer {
        id: lookupDelay
        interval: 550
        onTriggered: {
            if (!root.requestActive || !root.trackKey || fetch.running)
                return;
            root.submittedKey = root.trackKey;
            fetch.command = ["python3", decodeURIComponent(String(Qt.resolvedUrl("fetch-lyrics.py")).slice(7)), root.trackTitle.trim(), root.artist.trim(), root.album.trim(), String(Math.round(root.duration))];
            fetch.running = true;
        }
    }

    Process {
        id: fetch
        stdout: StdioCollector {
            id: lyricsOutput
        }
        onExited: function (code) {
            if (root.submittedKey === root.trackKey) {
                try {
                    root.result = code === 0 ? JSON.parse(lyricsOutput.text) : {
                        state: "error"
                    };
                } catch (error) {
                    root.result = {
                        state: "error"
                    };
                }
                root.resultKey = root.submittedKey;
            }
            Qt.callLater(root.scheduleLookup);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(17)
        spacing: Style.space(10)

        Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: strings.t("lyrics")
            color: root.ink
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
        }

        Text {
            Layout.fillWidth: true
            visible: root.lookupState !== "ready" || !root.hasPosition
            textFormat: Text.PlainText
            text: strings.t("lyricsState." + (root.lookupState === "ready" ? "noPosition" : root.lookupState))
            color: root.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
        }

        ListView {
            id: lyricsList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.lookupState === "ready"
            clip: true
            spacing: Style.space(3)
            model: root.lines
            boundsBehavior: Flickable.StopAtBounds
            QQC.ScrollBar.vertical: QQC.ScrollBar {}

            function followPlayback() {
                if (root.currentLine >= 0)
                    positionViewAtIndex(root.currentLine, ListView.Center);
            }

            onModelChanged: {
                positionViewAtBeginning();
                Qt.callLater(followPlayback);
            }
            Connections {
                target: root
                function onCurrentLineChanged() {
                    Qt.callLater(lyricsList.followPlayback);
                }
            }

            delegate: Rectangle {
                required property int index
                required property var modelData
                readonly property bool active: index === root.currentLine && !!modelData[1]

                width: lyricsList.width
                height: verse.implicitHeight + Style.space(14)
                radius: Style.space(10)
                color: active ? Qt.alpha(Commons.Color.accent, 0.15) : "transparent"

                Text {
                    id: verse
                    width: Math.max(0, parent.width - Style.space(22))
                    x: Style.space(9)
                    y: Style.space(7)
                    textFormat: Text.PlainText
                    text: parent.modelData[1]
                    wrapMode: Text.Wrap
                    color: parent.active ? root.ink : root.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: parent.active
                }
            }
        }

        Item {
            Layout.fillHeight: true
            visible: root.lookupState !== "ready"
        }
    }
}
