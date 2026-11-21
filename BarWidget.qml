import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import qs.Ui as Ui

Ui.BarWidget {
    id: root
    moduleName: "elmegga.omaplayer"
    implicitWidth: barControls.implicitWidth
    implicitHeight: vertical ? barControls.implicitHeight : barSize

    readonly property real barLabelHeight: Math.max(1, barSize - 2 * Style.space(3))

    property real lastAutomaticTitleWidth: 0
    property bool opened: false
    property string selectedKey: ""
    property string loadedCover: ""
    property string requestedCover: ""
    property string attemptedCover: ""
    property bool coverError: false

    property bool showSettings: false
    property bool saveFailed: false
    property bool audioFailed: false
    property var audioFrame: [[], []]

    readonly property var controls: ["previous", "play", "next", "mute"]
    readonly property var enabledControls: Array.isArray(settings?.controls) ? settings.controls : ["previous", "play", "next"]
    readonly property bool automaticWidth: setting("titleWidthMode", "fixed") === "auto"
    readonly property int fixedTitleWidth: Math.min(360, Math.max(64, Number(setting("titleWidth", 100)) || 100))
    readonly property real titleWidthLimit: automaticWidth ? Math.max(Style.space(64), Math.min(Style.space(340), Screen.width * 0.22)) : Style.space(fixedTitleWidth)
    readonly property bool reserveIdleSpace: setting("idleBarMode", "compact") === "reserve"
    readonly property bool hasBarMedia: !!player && (player.isPlaying || (player.playbackState === MprisPlaybackState.Paused && !!(title || artist || album)))
    readonly property bool showBarSlots: hasBarMedia || reserveIdleSpace
    readonly property string barTitleText: hasBarMedia ? title || strings.t("unknown") : strings.t("idleTitle")
    readonly property real automaticTitleWidth: Math.min(titleWidthLimit, Math.max(reserveIdleSpace ? idleTitleMetrics.width : 0, hasBarMedia ? barTitle.implicitWidth : lastAutomaticTitleWidth))

    onAutomaticTitleWidthChanged: if (hasBarMedia && automaticWidth)
        lastAutomaticTitleWidth = automaticTitleWidth

    readonly property bool scrollTitle: setting("scrollTitle", false) === true
    readonly property int titleFontSize: sizeSetting("titleFontSize", 14, 8, 18)
    readonly property int barIconSize: sizeSetting("barIconSize", 14, 8, 22)
    readonly property bool showBarCover: setting("showBarCover", true) === true
    property bool backdropBlurFailed: false

    readonly property bool autoOnlineArt: setting("autoOnlineArt", true) === true
    readonly property bool shouldFetchCover: autoOnlineArt && onlineArt && (opened || (visible && showBarCover && hasBarMedia))
    readonly property bool glassPlayer: setting("glassPlayer", false) === true
    readonly property bool glassCoverBackground: setting("glassCoverBackground", false) === true
    readonly property bool blurGlassBackdrop: setting("blurGlassBackdrop", false) === true
    readonly property bool wantsBackdropBlur: opened && glassPlayer && blurGlassBackdrop
    readonly property bool showLyrics: setting("showLyrics", false) === true
    readonly property bool showVisualizer: setting("showVisualizer", false) === true
    readonly property bool barVisualizerMirror: setting("barVisualizerMirror", setting("doubleMirrorVisualizer", false)) === true
    readonly property int visualizerWidth: sizeSetting("visualizerWidth", barVisualizerMirror ? 58 : 42, 24, 120)
    readonly property int visualizerHeight: sizeSetting("visualizerHeight", 16, 8, 24)
    readonly property int visualizerBars: sizeSetting("visualizerBars", 10, 4, 24)
    readonly property string visualizerStyle: setting("visualizerStyle", "waves")
    readonly property bool showPanelVisualizer: setting("showPanelVisualizer", false) === true
    readonly property string panelVisualizerStyle: setting("panelVisualizerStyle", "waves")
    readonly property bool panelVisualizerMirror: setting("panelVisualizerMirror", setting("panelDoubleMirror", false)) === true
    readonly property bool panelVisualizerFit: setting("panelVisualizerFit", true) === true
    readonly property int panelVisualizerWidth: sizeSetting("panelVisualizerWidth", 320, 120, 520)
    readonly property int panelVisualizerHeight: sizeSetting("panelVisualizerHeight", 44, 20, 100)
    readonly property int panelVisualizerBars: sizeSetting("panelVisualizerBars", 16, 4, 24)
    readonly property bool progressMirror: setting("progressMirror", true) === true
    readonly property bool showProgressVisualizer: setting("showProgressVisualizer", true) === true
    readonly property string progressVisualizerStyle: setting("progressVisualizerStyle", "waves")
    readonly property int progressVisualizerBars: sizeSetting("progressVisualizerBars", 16, 4, 24)
    readonly property int progressWaveSpeed: sizeSetting("progressWaveSpeed", 100, 25, 200)
    readonly property int panelWaveSpeed: sizeSetting("panelWaveSpeed", 100, 25, 200)
    readonly property int barWaveSpeed: sizeSetting("barWaveSpeed", 100, 25, 200)
    readonly property bool progressReactsToAudio: opened && showProgressVisualizer && !Style.reduceMotion && !!player?.isPlaying && hasPosition && duration > 0
    readonly property bool wantsAudioFrames: progressReactsToAudio || (hasBarMedia && !Style.reduceMotion && ((showVisualizer && visible) || (showPanelVisualizer && opened)))
    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property var output: audioSink?.audio ?? null

    function sizeSetting(key, fallback, minimum, maximum) {
        const value = Math.round(Number(setting(key, fallback)));
        return Number.isFinite(value) ? Math.min(maximum, Math.max(minimum, value)) : fallback;
    }

    function saveSetting(key, value) {
        const entry = Object.assign({}, settings, {
            id: moduleName
        });
        entry[key] = value;
        saveFailed = !bar?.shell?.updateEntryInline(moduleName, entry);
        if (!saveFailed)
            settings = entry;
    }

    function setControl(key, enabled) {
        saveSetting("controls", enabled ? enabledControls.concat([key]) : enabledControls.filter(item => item !== key));
    }

    PwObjectTracker {
        objects: root.audioSink ? [root.audioSink] : []
    }

    Process {
        command: ["python3", decodeURIComponent(String(Qt.resolvedUrl("backdrop-blur.py")).slice(7))]
        running: root.wantsBackdropBlur
        onStarted: root.backdropBlurFailed = false
        onExited: code => {
            root.backdropBlurFailed = root.wantsBackdropBlur && code !== 0;
        }
    }

    Process {
        id: audioMonitor
        command: ["python3", decodeURIComponent(String(Qt.resolvedUrl("audio-levels.py")).slice(7))]
        running: root.wantsAudioFrames
        stdout: SplitParser {
            onRead: line => {
                if (line.length < 2500)
                    root.audioFrame = JSON.parse(line);
            }
        }
        onStarted: root.audioFailed = false
        onExited: code => {
            root.audioFrame = [[], []];
            root.audioFailed = root.wantsAudioFrames && code !== 0;
        }
    }

    readonly property var players: (Mpris.players?.values ?? []).filter(p => !!p)
    readonly property var player: players.find(p => p.dbusName === selectedKey) ?? players.find(p => p.isPlaying && (p.trackTitle || p.trackArtist)) ?? players.find(p => p.isPlaying) ?? players.find(p => p.trackTitle || p.trackArtist) ?? players[0] ?? null
    readonly property bool canTogglePlayback: !!(player?.canTogglePlaying || (player?.isPlaying ? player.canPause : player?.canPlay))
    readonly property string playbackIcon: player?.isPlaying ? "󰏤" : "󰐊"
    readonly property string title: bounded(player?.trackTitle)
    readonly property string artist: bounded(player?.trackArtist)
    readonly property string album: bounded(player?.trackAlbum)
    readonly property string artUrl: String(player?.trackArtUrl ?? "")
    readonly property bool onlineArt: artUrl.length <= 2048 && /^https:\/\/(i\.scdn\.co|i\.ytimg\.com|img\.youtube\.com|lh3\.googleusercontent\.com)\//.test(artUrl)
    readonly property string cover: requestedCover === artUrl && loadedCover ? loadedCover : artUrl.length <= 2048 && artUrl.startsWith("file:///") ? artUrl : ""
    readonly property real duration: player?.lengthSupported && Number.isFinite(player.length) ? Math.max(0, player.length) : 0
    readonly property bool hasPosition: player?.positionSupported ?? false
    readonly property real radius: Style.space(14)
    readonly property color surface: Qt.alpha(ink, 0.055)
    readonly property color surfaceHover: Qt.alpha(ink, 0.11)
    readonly property color outline: Qt.alpha(ink, 0.15)
    readonly property color accentInk: Commons.Color.accent.hslLightness > 0.56 ? "#171717" : "#ffffff"
    readonly property color ink: Commons.Color.popups.text
    readonly property color muted: Qt.tint(ink, Qt.alpha(Commons.Color.popups.background, 0.32))
    readonly property var details: {
        const metadata = player?.metadata ?? {};
        const albumArtist = bounded(player?.trackAlbumArtist);
        const year = /^\d{4}/.exec(bounded(metadata["xesam:contentCreated"]));
        const genre = metadata["xesam:genre"];
        return [["albumArtist", albumArtist !== artist ? albumArtist : ""], ["genre", bounded(Array.isArray(genre) ? genre.slice(0, 4).join(", ") : genre)], ["year", year ? year[0] : ""]].filter(entry => entry[1] !== "");
    }

    function bounded(value) {
        return String(value ?? "").slice(0, 256);
    }

    function clock(seconds) {
        const whole = Math.floor(Math.max(0, seconds));
        const minutes = Math.floor(whole / 60);
        const remainder = String(whole % 60).padStart(2, "0");
        return minutes < 60 ? minutes + ":" + remainder : Math.floor(minutes / 60) + ":" + String(minutes % 60).padStart(2, "0") + ":" + remainder;
    }

    function open() {
        opened = true;
    }
    function close() {
        opened = false;
        showSettings = false;
    }

    function cycleLoop() {
        if (!player?.canControl || !player?.loopSupported)
            return;
        if (player.loopState === MprisLoopState.None)
            player.loopState = MprisLoopState.Playlist;
        else if (player.loopState === MprisLoopState.Playlist)
            player.loopState = MprisLoopState.Track;
        else
            player.loopState = MprisLoopState.None;
    }

    function togglePlayback() {
        if (!player)
            return;
        if (player.isPlaying && player.canPause)
            player.pause();
        else if (!player.isPlaying && player.canPlay)
            player.play();
        else if (player.canTogglePlaying)
            player.togglePlaying();
    }

    function requestCover() {
        if (!onlineArt || fetch.running)
            return;
        coverDelay.stop();
        requestedCover = artUrl;
        attemptedCover = artUrl;
        coverError = false;
        fetch.command = ["python3", decodeURIComponent(String(Qt.resolvedUrl("fetch-cover.py")).slice(7)), artUrl];
        fetch.running = true;
    }

    function scheduleCover() {
        if (shouldFetchCover && !fetch.running && attemptedCover !== artUrl)
            coverDelay.restart();
        else
            coverDelay.stop();
    }

    onArtUrlChanged: {
        loadedCover = "";
        attemptedCover = "";
        coverError = false;
        scheduleCover();
    }

    onShouldFetchCoverChanged: scheduleCover()

    Timer {
        id: coverDelay
        interval: 350
        onTriggered: if (root.shouldFetchCover)
            root.requestCover()
    }

    onPlayersChanged: if (selectedKey && !players.some(p => p.dbusName === selectedKey))
        selectedKey = ""

    Commons.Translations {
        id: strings
        directory: Qt.resolvedUrl("i18n")
    }

    Process {
        id: fetch
        stdout: StdioCollector {
            id: coverOutput
        }
        onExited: function (code) {
            if (root.requestedCover === root.artUrl && root.requestedCover) {
                root.loadedCover = code === 0 ? coverOutput.text.trim() : "";
                root.coverError = !root.loadedCover;
            }
            Qt.callLater(root.scheduleCover);
        }
    }

    component Label: Text {
        textFormat: Text.PlainText
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        color: root.ink
        elide: Text.ElideRight
    }

    component Control: Button {
        foreground: root.ink
        focusable: true
        radius: root.radius
        opacity: enabled ? 1 : 0.4
    }

    component TransportButton: Control {
        property bool primary: false
        property bool secondary: false
        readonly property int buttonSize: Style.space(primary ? 56 : secondary ? 37 : 44)

        Layout.preferredWidth: buttonSize
        Layout.preferredHeight: buttonSize
        radius: buttonSize / 2
        iconSize: Style.space(primary ? 26 : secondary ? 17 : 22)
        horizontalPadding: 0
        verticalPadding: 0
        background: primary ? Commons.Color.accent : secondary ? "transparent" : root.surface
        foreground: primary ? root.accentInk : root.ink
    }

    component FinishedPane: Rectangle {
        id: finishedPane

        property real solidTint: 0
        property real opacityBoost: 0
        property real artworkOpacity: 0.24

        border.color: root.glassPlayer ? Qt.alpha(root.ink, 0.24) : root.outline

        function glassTone(tint, opacity) {
            const base = Qt.tint(Commons.Color.popups.background, Qt.alpha(Commons.Color.accent, tint));
            return root.glassPlayer ? Qt.alpha(base, Math.min(1, opacity + finishedPane.opacityBoost)) : base;
        }

        gradient: Gradient {
            GradientStop {
                position: 0
                color: finishedPane.glassTone(root.glassPlayer ? 0.25 : finishedPane.solidTint, 0.77)
            }
            GradientStop {
                position: 0.54
                color: finishedPane.glassTone(root.glassPlayer ? 0.12 : finishedPane.solidTint * 0.35, 0.72)
            }
            GradientStop {
                position: 1
                color: finishedPane.glassTone(root.glassPlayer ? 0.04 : 0, 0.88)
            }
        }

        Rectangle {
            id: glassMask
            anchors.fill: parent
            anchors.margins: 1
            radius: finishedPane.radius - 1
            visible: false
            layer.enabled: glassArtwork.visible
        }

        SizedImage {
            id: glassArtwork
            anchors.fill: glassMask
            visible: root.glassPlayer && root.glassCoverBackground && status === Image.Ready
            url: root.glassPlayer && root.glassCoverBackground && root.opened ? root.cover : ""
            crop: true
            opacity: finishedPane.artworkOpacity
            layer.enabled: visible
            layer.effect: MultiEffect {
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 48
                blur: 1
                maskEnabled: true
                maskSource: glassMask
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: Style.space(24)
            anchors.rightMargin: Style.space(24)
            anchors.topMargin: 1
            height: 1
            visible: root.glassPlayer
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0
                    color: "transparent"
                }
                GradientStop {
                    position: 0.38
                    color: Qt.alpha(root.ink, 0.22)
                }
                GradientStop {
                    position: 1
                    color: "transparent"
                }
            }
        }
    }

    component SettingGroup: Rectangle {
        id: group
        required property string caption
        default property alias rows: fields.data
        Layout.fillWidth: true
        implicitHeight: fields.implicitHeight + Style.space(28)
        radius: root.radius
        color: root.surface
        border.color: root.outline

        property Item contents: ColumnLayout {
            id: fields
            parent: group
            anchors.fill: parent
            anchors.margins: Style.space(14)
            spacing: Style.space(8)
            Label {
                Layout.fillWidth: true
                text: group.caption
                font.bold: true
                color: Commons.Color.accent
            }
        }
    }

    component Toggle: QQC.Switch {
        id: toggle
        Layout.fillWidth: true
        spacing: Style.space(10)
        implicitHeight: Math.max(implicitContentHeight, indicator.implicitHeight) + Style.space(8)
        contentItem: Label {
            text: toggle.text
            verticalAlignment: Text.AlignVCenter
            rightPadding: toggle.indicator.width + toggle.spacing
        }
        indicator: Rectangle {
            x: toggle.width - width
            y: (toggle.height - height) / 2
            implicitWidth: Style.space(34)
            implicitHeight: Style.space(19)
            radius: height / 2
            color: toggle.checked ? Commons.Color.accent : root.surfaceHover
            border.color: toggle.activeFocus ? Commons.Color.accent : root.outline
            Rectangle {
                y: (parent.height - height) / 2
                x: toggle.checked ? parent.width - width - Style.space(3) : Style.space(3)
                width: Style.space(13)
                height: width
                radius: width / 2
                color: toggle.checked ? root.accentInk : root.ink
                Behavior on x {
                    NumberAnimation {
                        duration: Style.duration(150)
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    component Stepper: QQC.SpinBox {
        id: stepper
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        readonly property real buttonWidth: Style.space(40)
        implicitWidth: Style.space(126)
        implicitHeight: Style.space(40)
        leftPadding: buttonWidth
        rightPadding: buttonWidth
        background: Rectangle {
            radius: height / 2
            color: root.surface
            border.color: stepper.activeFocus ? Commons.Color.accent : root.outline
        }
        down.indicator: Rectangle {
            x: 0
            width: stepper.buttonWidth
            height: stepper.height
            radius: height / 2
            color: stepper.down.pressed || decrementHover.hovered ? root.surfaceHover : "transparent"
            HoverHandler {
                id: decrementHover
                cursorShape: stepper.value > stepper.from ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
            Label {
                anchors.centerIn: parent
                text: "−"
                font.pixelSize: Style.space(16)
                color: stepper.value > stepper.from ? root.ink : root.muted
            }
        }
        up.indicator: Rectangle {
            x: stepper.width - width
            width: stepper.buttonWidth
            height: stepper.height
            radius: height / 2
            color: stepper.up.pressed || incrementHover.hovered ? root.surfaceHover : "transparent"
            HoverHandler {
                id: incrementHover
                cursorShape: stepper.value < stepper.to ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
            Label {
                anchors.centerIn: parent
                text: "+"
                font.pixelSize: Style.space(16)
                color: stepper.value < stepper.to ? root.ink : root.muted
            }
        }
        contentItem: TextInput {
            text: stepper.displayText
            color: root.ink
            selectionColor: Commons.Color.accent
            selectedTextColor: root.accentInk
            selectByMouse: true
            readOnly: !stepper.editable
            validator: stepper.validator
            font: stepper.font
            horizontalAlignment: Qt.AlignHCenter
            verticalAlignment: Qt.AlignVCenter
            inputMethodHints: Qt.ImhDigitsOnly
        }
    }

    component Selector: QQC.ComboBox {
        id: selector
        implicitWidth: Style.space(168)
        leftPadding: Style.space(10)
        rightPadding: Style.space(28)
        implicitHeight: Style.space(34)
        background: Rectangle {
            radius: height / 2
            color: selector.hovered ? root.surfaceHover : root.surface
            border.color: selector.activeFocus ? Commons.Color.accent : root.outline
        }
        contentItem: Label {
            clip: true
            text: selector.displayText
            verticalAlignment: Text.AlignVCenter
        }
        indicator: Label {
            x: selector.width - Style.space(23)
            y: (selector.height - height) / 2
            text: "⌄"
            color: root.muted
        }
        delegate: QQC.ItemDelegate {
            id: option
            required property int index
            required property var modelData
            width: ListView.view?.width ?? selector.width
            highlighted: selector.highlightedIndex === index
            contentItem: Label {
                text: selector.textRole ? option.modelData[selector.textRole] : option.modelData
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                radius: Style.space(8)
                color: option.highlighted ? root.surfaceHover : "transparent"
            }
        }
        popup: QQC.Popup {
            y: selector.height + Style.space(4)
            width: selector.width
            padding: Style.space(4)
            implicitHeight: Math.min(contentItem.implicitHeight + 2 * padding, Style.space(240))
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: selector.popup.visible ? selector.delegateModel : null
                currentIndex: selector.highlightedIndex
                QQC.ScrollBar.vertical: QQC.ScrollBar {}
            }
            background: Rectangle {
                radius: root.radius
                color: Commons.Color.popups.background
                border.color: root.outline
            }
        }
    }

    component SizeSetting: GridLayout {
        id: sizeRow
        required property string settingKey
        required property string caption
        required property int amount
        required property int minimum
        required property int maximum
        property bool stacked: false
        property int increment: 1

        columns: stacked ? 1 : 2
        columnSpacing: Style.space(8)
        rowSpacing: Style.space(3)
        Layout.fillWidth: true
        Label {
            text: sizeRow.caption
            Layout.fillWidth: true
        }
        Stepper {
            Accessible.name: sizeRow.caption
            from: sizeRow.minimum
            to: sizeRow.maximum
            value: sizeRow.amount
            stepSize: sizeRow.increment
            editable: true
            onValueModified: root.saveSetting(sizeRow.settingKey, value)
        }
    }

    component VisualizerSettings: ColumnLayout {
        id: group
        required property string target
        readonly property bool inPanel: target === "player"
        readonly property bool inTimeline: target === "timeline"

        Layout.fillWidth: true
        spacing: Style.space(6)
        readonly property bool displayed: inTimeline ? root.showProgressVisualizer : inPanel ? root.showPanelVisualizer : root.showVisualizer
        readonly property string styleValue: inTimeline ? root.progressVisualizerStyle : inPanel ? root.panelVisualizerStyle : root.visualizerStyle
        readonly property bool mirrorValue: inTimeline ? root.progressMirror : inPanel ? root.panelVisualizerMirror : root.barVisualizerMirror

        RowLayout {
            Layout.fillWidth: true
            Toggle {
                text: strings.t("enableVisualizer")
                checked: group.displayed
                onToggled: root.saveSetting(group.inTimeline ? "showProgressVisualizer" : group.inPanel ? "showPanelVisualizer" : "showVisualizer", checked)
            }
            Selector {
                id: stylePicker
                implicitWidth: Style.space(112)
                visible: group.displayed
                Accessible.name: strings.t("visualizer")
                readonly property var styles: ["bars", "wave", "waves", "dots"]
                model: styles.map(key => strings.t(key))
                currentIndex: Math.max(0, styles.indexOf(group.styleValue))
                onActivated: root.saveSetting(group.inTimeline ? "progressVisualizerStyle" : group.inPanel ? "panelVisualizerStyle" : "visualizerStyle", styles[currentIndex])
            }
        }

        Toggle {
            visible: group.displayed
            text: strings.t("horizontalMirror")
            checked: group.mirrorValue
            onToggled: root.saveSetting(group.inTimeline ? "progressMirror" : group.inPanel ? "panelVisualizerMirror" : "barVisualizerMirror", checked)
        }

        Toggle {
            visible: group.displayed && group.inPanel
            text: strings.t("fitTrackCard")
            checked: root.panelVisualizerFit
            onToggled: root.saveSetting("panelVisualizerFit", checked)
        }

        RowLayout {
            Layout.fillWidth: true
            visible: group.displayed && !group.inTimeline && (!group.inPanel || !root.panelVisualizerFit)
            spacing: Style.space(10)

            SizeSetting {
                stacked: true
                Layout.preferredWidth: 1
                settingKey: group.inPanel ? "panelVisualizerWidth" : "visualizerWidth"
                caption: strings.t("visualizerWidth")
                amount: group.inPanel ? root.panelVisualizerWidth : root.visualizerWidth
                minimum: group.inPanel ? 120 : 24
                maximum: group.inPanel ? 520 : 120
            }

            SizeSetting {
                stacked: true
                Layout.preferredWidth: 1
                settingKey: group.inPanel ? "panelVisualizerHeight" : "visualizerHeight"
                caption: strings.t("visualizerHeight")
                amount: group.inPanel ? root.panelVisualizerHeight : root.visualizerHeight
                minimum: group.inPanel ? 20 : 8
                maximum: group.inPanel ? 100 : 24
            }
        }

        SizeSetting {
            visible: group.displayed && group.styleValue === "waves"
            settingKey: group.inTimeline ? "progressWaveSpeed" : group.inPanel ? "panelWaveSpeed" : "barWaveSpeed"
            caption: strings.t("waveSpeed")
            amount: group.inTimeline ? root.progressWaveSpeed : group.inPanel ? root.panelWaveSpeed : root.barWaveSpeed
            minimum: 25
            maximum: 200
            increment: 10
        }

        SizeSetting {
            visible: group.displayed && (group.styleValue === "bars" || group.styleValue === "dots")
            settingKey: group.inTimeline ? "progressVisualizerBars" : group.inPanel ? "panelVisualizerBars" : "visualizerBars"
            caption: strings.t(group.styleValue === "dots" ? "dotCount" : "barCount")
            amount: group.inTimeline ? root.progressVisualizerBars : group.inPanel ? root.panelVisualizerBars : root.visualizerBars
            minimum: 4
            maximum: 24
        }
    }

    component BarControl: WidgetButton {
        required property string actionKey
        property bool available: false
        bar: root.bar
        fontSize: Style.bar.iconFont
        interactive: available
        dimmed: !available
        visible: root.showBarSlots && root.enabledControls.includes(actionKey)
        Accessible.role: Accessible.Button
        Accessible.name: tooltipText
    }

    GridLayout {
        id: barControls
        anchors.centerIn: parent
        columns: root.vertical ? 1 : 7
        columnSpacing: 0
        rowSpacing: 0

        WidgetButton {
            id: trigger
            bar: root.bar
            text: root.player?.isPlaying ? "󰎈" : "󰝚"
            fontSize: Style.bar.iconFont
            labelVisible: false
            fixedWidth: root.vertical ? -1 : Style.bar.iconSlot
            fixedHeight: root.vertical ? Style.bar.iconSlot : root.barLabelHeight
            Layout.alignment: Qt.AlignVCenter
            tooltipText: strings.t("player")
            Accessible.role: Accessible.Button
            Accessible.name: tooltipText
            onPressed: button => {
                if (button === Qt.LeftButton)
                    root.opened = !root.opened;
            }
            OpticalGlyph {
                anchors.fill: barArtwork
                visible: !barArtwork.visible
                text: trigger.text
                fontFamily: trigger.fontFamily
                fontSize: trigger.fontSize
                paintedSize: barArtwork.width
                color: trigger.foreground
                scale: trigger.pressScale
            }

            Rectangle {
                id: barCoverMask
                anchors.fill: barArtwork
                radius: Style.space(3)
                visible: false
                layer.enabled: true
            }

            SizedImage {
                id: barArtwork
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height, Style.space(root.barIconSize))
                height: width
                visible: status === Image.Ready
                scale: trigger.pressScale
                layer.enabled: visible
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: barCoverMask
                }
                crop: true
                url: root.showBarCover && root.hasBarMedia ? root.cover : ""
            }
        }

        WidgetButton {
            id: titleButton
            bar: root.bar
            visible: !root.vertical && root.showBarSlots
            hasVisualContent: root.showBarSlots
            labelVisible: false
            fixedHeight: root.barLabelHeight
            Layout.alignment: Qt.AlignVCenter
            fixedWidth: (root.automaticWidth ? root.automaticTitleWidth : root.titleWidthLimit) + Style.space(9)
            tooltipText: strings.t("player")
            Accessible.role: Accessible.Button
            Accessible.name: root.barTitleText
            onPressed: button => {
                if (button === Qt.LeftButton)
                    root.opened = !root.opened;
            }

            Item {
                id: titleClip
                anchors.fill: parent
                anchors.leftMargin: Style.space(3)
                anchors.rightMargin: Style.space(6)
                clip: true
                readonly property bool scrolling: root.scrollTitle && !Style.reduceMotion && barTitle.implicitWidth > width && titleButton.visible
                property real offset: 0

                Label {
                    id: barTitle
                    x: -titleClip.offset
                    anchors.verticalCenter: parent.verticalCenter
                    width: titleClip.scrolling ? implicitWidth : titleClip.width
                    text: root.barTitleText
                    color: titleButton.foreground
                    font.family: titleButton.fontFamily
                    font.pixelSize: Math.min(Style.space(root.titleFontSize), root.barLabelHeight)
                    scale: titleButton.pressScale
                    onTextChanged: {
                        titleScroll.stop();
                        titleClip.offset = 0;
                        if (titleClip.scrolling)
                            titleScroll.start();
                    }
                }

                TextMetrics {
                    id: idleTitleMetrics
                    font: barTitle.font
                    text: strings.t("idleTitle")
                }

                onScrollingChanged: {
                    if (scrolling)
                        titleScroll.start();
                    else {
                        titleScroll.stop();
                        offset = 0;
                    }
                }

                SequentialAnimation {
                    id: titleScroll
                    loops: Animation.Infinite
                    PauseAnimation {
                        duration: Style.duration(1000)
                    }
                    NumberAnimation {
                        target: titleClip
                        property: "offset"
                        from: 0
                        to: Math.max(0, barTitle.implicitWidth - titleClip.width)
                        duration: Style.duration(Math.max(700, Math.round(to * 25)))
                    }
                    PauseAnimation {
                        duration: Style.duration(1000)
                    }
                    PropertyAction {
                        target: titleClip
                        property: "offset"
                        value: 0
                    }
                }
            }
        }

        WidgetButton {
            id: visualizerButton
            bar: root.bar
            visible: root.showVisualizer && root.showBarSlots
            hasVisualContent: root.showVisualizer && root.showBarSlots
            labelVisible: false
            fixedWidth: root.vertical ? root.barSize : Style.space(root.visualizerWidth + 8)
            fixedHeight: root.barLabelHeight
            Layout.alignment: Qt.AlignCenter
            tooltipText: strings.t("player")
            Accessible.role: Accessible.Button
            Accessible.name: strings.t("visualizer")
            onPressed: button => {
                if (button === Qt.LeftButton)
                    root.opened = !root.opened;
            }

            Visualizer {
                visible: root.hasBarMedia
                anchors.centerIn: parent
                width: Math.min(root.vertical ? root.barLabelHeight : parent.width, Style.space(root.visualizerWidth))
                height: Math.min(parent.height, Style.space(root.visualizerHeight))
                ink: visualizerButton.foreground
                styleName: root.visualizerStyle
                waveSpeed: root.barWaveSpeed / 100
                animateWaves: !!root.player?.isPlaying && !Style.reduceMotion
                horizontalMirror: root.barVisualizerMirror
                barCount: root.visualizerBars
                frame: root.audioFrame
            }
        }

        BarControl {
            actionKey: "previous"
            text: "󰒮"
            tooltipText: strings.t("previous")
            available: root.hasBarMedia && (root.player?.canGoPrevious ?? false)
            onPressed: button => {
                if (button === Qt.LeftButton && available)
                    root.player?.previous();
            }
        }

        BarControl {
            actionKey: "play"
            text: root.playbackIcon
            tooltipText: strings.t(root.player?.isPlaying ? "pause" : "play")
            available: root.hasBarMedia && (root.canTogglePlayback)
            onPressed: button => {
                if (button === Qt.LeftButton && available)
                    root.togglePlayback();
            }
        }

        BarControl {
            actionKey: "next"
            text: "󰒭"
            tooltipText: strings.t("next")
            available: root.hasBarMedia && (root.player?.canGoNext ?? false)
            onPressed: button => {
                if (button === Qt.LeftButton && available)
                    root.player?.next();
            }
        }

        BarControl {
            actionKey: "mute"
            text: root.output?.muted ? "󰝟" : "󰕾"
            tooltipText: strings.t(root.output?.muted ? "unmute" : "mute")
            available: !!root.output
            onPressed: button => {
                if (button === Qt.LeftButton && available)
                    root.output.muted = !root.output.muted;
            }
        }
    }

    // A single shell overlay keeps focus and outside-click dismissal shared by both cards.
    Item {
        id: panelAnchor
        parent: trigger
        width: trigger.width
        height: trigger.height
        x: panel.anchorShift
    }

    TransformWatcher {
        id: triggerTransform
        a: panel.anchorWindow?.contentItem ?? null
        b: trigger
    }

    KeyboardPanel {
        id: panel
        WlrLayershell.namespace: "omarchy-omaplayer"
        owner: root
        bar: root.bar
        anchorItem: panelAnchor
        open: root.opened
        centerOnBar: false
        padding: 0
        borderSpec: Border.none()
        focusTarget: loadedContent

        readonly property real paneGap: Style.space(10)
        readonly property real desiredPaneWidth: Style.space(442)
        readonly property bool hasCompanion: root.showSettings
        readonly property bool sideBySide: hasCompanion && availableCardWidth >= Style.space(760) + paneGap
        readonly property real playerWidth: fittedContentWidth(sideBySide ? Math.min(desiredPaneWidth, (availableCardWidth - paneGap) / 2) : desiredPaneWidth)
        readonly property real settingsWidth: sideBySide ? Math.min(desiredPaneWidth, availableCardWidth - playerWidth - paneGap) : playerWidth
        readonly property real triggerCenter: {
            triggerTransform.transform;
            return anchorWindow ? trigger.mapToItem(anchorWindow.contentItem, trigger.width / 2, 0).x : 0;
        }
        readonly property real playerLeft: barPos === "left" ? barThickness + gap : barPos === "right" ? screenW - barThickness - playerWidth - gap : Math.max(margin, Math.min(triggerCenter - playerWidth / 2, screenW - margin - playerWidth))
        readonly property bool settingsOnLeft: playerLeft - margin > screenW - margin - playerLeft - playerWidth
        readonly property real anchorShift: {
            if (!sideBySide || root.vertical)
                return 0;
            const combinedLeft = playerLeft - (settingsOnLeft ? settingsWidth + paneGap : 0);
            return combinedLeft + contentWidth / 2 - triggerCenter;
        }

        contentWidth: sideBySide ? playerWidth + paneGap + settingsWidth : playerWidth
        contentHeight: fittedContentHeight(loadedContentHeight)
        onOpenChanged: if (!open)
            root.close()

        content: FocusScope {
            id: dashboard
            readonly property var panelSurface: {
                const surface = parent?.parent?.parent;
                return surface && "radius" in surface && "borderSpec" in surface ? surface : null;
            }
            readonly property real heightLimit: panel.availableCardHeight || Style.space(700)
            readonly property bool stacked: panel.hasCompanion && !panel.sideBySide
            readonly property real playerHeight: Math.min(playerChrome.implicitHeight + Style.space(20), stacked ? (heightLimit - panel.paneGap) * 0.45 : heightLimit)
            readonly property real companionLimit: stacked ? heightLimit - panel.paneGap - playerHeight : heightLimit
            readonly property real settingsHeight: Math.min(settingsChrome.implicitHeight + Style.space(20), companionLimit)
            readonly property real companionX: !panel.sideBySide || panel.settingsOnLeft ? 0 : panel.playerWidth + panel.paneGap
            readonly property real companionY: stacked ? (panel.barPos === "bottom" ? 0 : playerHeight + panel.paneGap) : (panel.barPos === "bottom" ? height - settingsHeight : 0)
            implicitHeight: !panel.hasCompanion ? playerHeight : stacked ? playerHeight + panel.paneGap + settingsHeight : Math.max(playerHeight, settingsHeight)

            Binding {
                target: dashboard.panelSurface
                property: "color"
                value: "transparent"
                when: dashboard.panelSurface !== null
            }

            Keys.onEscapePressed: {
                if (root.showSettings)
                    root.showSettings = false;
                else
                    root.close();
            }

            // The shell card surrounds both panes, including the space between
            // them and under the shorter pane. Dismiss from those empty areas too.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: root.close()
            }

            FinishedPane {
                id: playerCard
                x: panel.sideBySide && panel.settingsOnLeft ? panel.settingsWidth + panel.paneGap : 0
                y: panel.barPos === "bottom" ? dashboard.height - height : 0
                width: panel.playerWidth
                height: dashboard.playerHeight
                radius: Style.space(20)
                solidTint: 0.17

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                ColumnLayout {
                    id: playerChrome
                    anchors.fill: parent
                    anchors.margins: Style.space(10)
                    spacing: Style.space(5)

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Style.space(8)
                        Layout.rightMargin: Style.space(8)
                        Layout.topMargin: Style.space(6)
                        spacing: Style.space(8)

                        Label {
                            Layout.fillWidth: true
                            text: strings.t("player")
                            font.bold: true
                            font.pixelSize: Style.font.subtitle
                        }
                        Rectangle {
                            visible: !!root.player
                            implicitWidth: playbackStatus.implicitWidth + Style.space(16)
                            implicitHeight: playbackStatus.implicitHeight + Style.space(8)
                            radius: height / 2
                            color: root.player?.isPlaying ? Qt.alpha(Commons.Color.accent, 0.15) : root.surface
                            Label {
                                id: playbackStatus
                                anchors.centerIn: parent
                                text: strings.t(root.player?.isPlaying ? "playing" : root.player?.playbackState === MprisPlaybackState.Paused ? "paused" : "stopped")
                                color: root.player?.isPlaying ? Commons.Color.accent : root.muted
                                font.pixelSize: Style.font.caption
                            }
                        }
                        Control {
                            iconText: "󰦨"
                            text: strings.t("lyrics")
                            tooltipText: strings.t("lyricsTooltip")
                            Accessible.name: strings.t("showLyrics")
                            Accessible.pressed: root.showLyrics
                            selected: root.showLyrics
                            bordered: true
                            background: root.surface
                            onClicked: root.saveSetting("showLyrics", !root.showLyrics)
                        }
                        Control {
                            id: settingsButton
                            iconText: "󰒓"
                            tooltipText: strings.t(root.showSettings ? "closeSettings" : "settings")
                            Accessible.name: tooltipText
                            Accessible.pressed: root.showSettings
                            selected: root.showSettings
                            background: root.surface
                            onClicked: root.showSettings = !root.showSettings
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        implicitHeight: playerPage.implicitHeight + Style.space(12)
                        clip: true
                        contentWidth: width
                        contentHeight: implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        QQC.ScrollBar.vertical: QQC.ScrollBar {}

                        ColumnLayout {
                            id: playerPage
                            x: Style.space(8)
                            y: Style.space(6)
                            width: parent.width - Style.space(16)
                            spacing: Style.space(14)
                            BorderSurface {
                                Layout.fillWidth: true
                                implicitHeight: hero.implicitHeight + Style.space(20)
                                radius: root.radius
                                color: Qt.alpha(Commons.Color.popups.background, 0.24)
                                borderSpec: Border.none()

                                Rectangle {
                                    id: spectrumMask
                                    anchors.fill: parent
                                    anchors.margins: Style.space(3)
                                    radius: Math.max(0, root.radius - Style.space(3))
                                    visible: false
                                    layer.enabled: panelSpectrum.visible
                                }

                                Visualizer {
                                    id: panelSpectrum
                                    visible: root.showPanelVisualizer && root.hasBarMedia
                                    anchors.centerIn: parent
                                    width: root.panelVisualizerFit ? spectrumMask.width : Math.min(spectrumMask.width, Style.space(root.panelVisualizerWidth))
                                    height: root.panelVisualizerFit ? spectrumMask.height : Math.min(spectrumMask.height, Style.space(root.panelVisualizerHeight))
                                    ink: Qt.alpha(Commons.Color.accent, 0.20)
                                    layer.enabled: visible && root.panelVisualizerFit
                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskSource: spectrumMask
                                    }
                                    styleName: root.panelVisualizerStyle
                                    waveSpeed: root.panelWaveSpeed / 100
                                    animateWaves: root.opened && !!root.player?.isPlaying && !Style.reduceMotion
                                    horizontalMirror: root.panelVisualizerMirror
                                    barCount: root.panelVisualizerBars
                                    frame: root.audioFrame
                                }

                                RowLayout {
                                    id: hero
                                    z: 1
                                    anchors.fill: parent
                                    anchors.margins: Style.space(10)
                                    spacing: Style.space(16)

                                    Rectangle {
                                        Layout.preferredWidth: Style.space(118)
                                        Layout.preferredHeight: Style.space(118)
                                        radius: root.radius
                                        color: Qt.tint(Commons.Color.popups.background, Qt.alpha(Commons.Color.accent, 0.14))
                                        Label {
                                            anchors.centerIn: parent
                                            text: "󰝚"
                                            color: Commons.Color.accent
                                            font.pixelSize: Style.space(32)
                                            visible: artwork.status !== Image.Ready
                                        }
                                        Rectangle {
                                            id: coverMask
                                            anchors.fill: artwork
                                            radius: Style.space(13)
                                            visible: false
                                            layer.enabled: true
                                        }
                                        SizedImage {
                                            id: artwork
                                            anchors.fill: parent
                                            anchors.margins: Style.space(2)
                                            layer.enabled: status === Image.Ready
                                            layer.effect: MultiEffect {
                                                maskEnabled: true
                                                maskSource: coverMask
                                            }
                                            url: root.cover
                                            crop: true
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: Style.space(5)

                                        RowLayout {
                                            Layout.fillWidth: true
                                            visible: sourceName.text !== "" || root.players.length > 1
                                            spacing: Style.space(6)
                                            Label {
                                                text: "󰎈"
                                                color: Commons.Color.accent
                                            }
                                            Label {
                                                id: sourceName
                                                visible: root.players.length < 2
                                                Layout.fillWidth: true
                                                text: root.bounded(root.player?.identity || root.player?.desktopEntry)
                                                color: Commons.Color.accent
                                                font.pixelSize: Style.font.bodySmall
                                                font.bold: true
                                            }
                                            Selector {
                                                id: sourcePicker
                                                Layout.fillWidth: true
                                                visible: root.players.length > 1
                                                implicitHeight: Style.space(28)
                                                Accessible.name: strings.t("playbackSource")
                                                displayText: root.selectedKey ? currentText : sourceName.text || currentText
                                                model: [
                                                    {
                                                        label: strings.t("automatic"),
                                                        key: ""
                                                    }
                                                ].concat(root.players.slice(0, 20).map(p => ({
                                                            label: root.bounded(p.identity || p.desktopEntry || p.dbusName),
                                                            key: p.dbusName
                                                        })))
                                                textRole: "label"
                                                valueRole: "key"
                                                currentIndex: Math.max(0, indexOfValue(root.selectedKey))
                                                onActivated: root.selectedKey = currentValue
                                            }
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: root.player ? root.title || strings.t("unknown") : strings.t("empty")
                                            font.bold: true
                                            font.pixelSize: Style.space(21)
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 2
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            visible: text !== ""
                                            text: root.player ? root.artist : strings.t("emptyDetail")
                                            color: root.muted
                                            wrapMode: root.player ? Text.NoWrap : Text.WordWrap
                                            font.pixelSize: Style.font.subtitle
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            visible: text !== ""
                                            text: root.album
                                            color: root.muted
                                            font.pixelSize: Style.font.caption
                                        }
                                    }
                                }
                            }

                            Control {
                                visible: root.onlineArt && !root.cover
                                enabled: !fetch.running
                                text: strings.t(fetch.running ? "artLoading" : root.coverError ? "artError" : "art")
                                onClicked: root.requestCover()
                            }

                            RowLayout {
                                visible: !!root.player
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: -Style.space(2)
                                spacing: Style.space(10)

                                TransportButton {
                                    secondary: true
                                    iconText: "󰒟"
                                    tooltipText: strings.t("shuffle")
                                    Accessible.name: tooltipText
                                    selected: root.player?.shuffle === true
                                    enabled: !!(root.player?.canControl && root.player?.shuffleSupported)
                                    onClicked: root.player.shuffle = !root.player.shuffle
                                }

                                TransportButton {
                                    iconText: "󰒮"
                                    Accessible.name: strings.t("previous")
                                    enabled: root.player?.canGoPrevious ?? false
                                    onClicked: root.player?.previous()
                                }

                                TransportButton {
                                    primary: true
                                    iconText: root.playbackIcon
                                    Accessible.name: strings.t(root.player?.isPlaying ? "pause" : "play")
                                    enabled: root.canTogglePlayback
                                    onClicked: root.togglePlayback()
                                }

                                TransportButton {
                                    iconText: "󰒭"
                                    Accessible.name: strings.t("next")
                                    enabled: root.player?.canGoNext ?? false
                                    onClicked: root.player?.next()
                                }

                                TransportButton {
                                    secondary: true
                                    iconText: root.player?.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
                                    tooltipText: strings.t(root.player?.loopState === MprisLoopState.Track ? "repeatTrack" : root.player?.loopState === MprisLoopState.Playlist ? "repeatAll" : "repeat")
                                    Accessible.name: tooltipText
                                    selected: enabled && root.player?.loopState !== MprisLoopState.None
                                    enabled: !!(root.player?.canControl && root.player?.loopSupported)
                                    onClicked: root.cycleLoop()
                                }
                            }

                            ColumnLayout {
                                id: timing
                                Layout.fillWidth: true
                                visible: root.hasPosition || root.duration > 0
                                spacing: Style.space(2)
                                property real position: 0

                                Timer {
                                    interval: 250
                                    repeat: true
                                    running: root.opened && root.hasPosition && !!root.player?.isPlaying
                                    onTriggered: timing.position = root.player.position
                                }

                                Connections {
                                    target: root
                                    function onPlayerChanged() {
                                        timing.position = root.player?.position ?? 0;
                                    }
                                    function onOpenedChanged() {
                                        if (root.opened)
                                            timing.position = root.player?.position ?? 0;
                                    }
                                }

                                Connections {
                                    target: root.player
                                    function onPositionChanged() {
                                        timing.position = root.player?.position ?? 0;
                                    }
                                    function onTrackChanged() {
                                        timing.position = root.player?.position ?? 0;
                                    }
                                }

                                QQC.Slider {
                                    id: seekSlider
                                    Layout.fillWidth: true
                                    visible: root.duration > 0 && root.hasPosition
                                    enabled: root.player?.canSeek ?? false
                                    to: Math.max(1, root.duration)
                                    value: timing.position
                                    implicitHeight: Style.space(!root.showProgressVisualizer ? 24 : root.progressMirror ? 54 : 44)
                                    Accessible.name: strings.t("progress")
                                    background: Item {
                                        id: progressPaint
                                        readonly property real unit: Style.spaceReal(1)
                                        readonly property real trackSpan: Math.max(0, width - 4 * unit)
                                        readonly property bool showOlas: root.showProgressVisualizer && root.progressVisualizerStyle === "waves"

                                        x: seekSlider.leftPadding + seekSlider.handle.width / 2 - 2 * unit
                                        width: Math.max(0, seekSlider.availableWidth - seekSlider.handle.width + 4 * unit)
                                        height: seekSlider.height

                                        Visualizer {
                                            visible: root.showProgressVisualizer && !progressPaint.showOlas && width >= 2
                                            x: 2 * progressPaint.unit + (seekSlider.mirrored ? progressPaint.trackSpan - width : 0)
                                            width: progressPaint.trackSpan * seekSlider.position
                                            height: root.progressMirror ? progressPaint.height - 4 * progressPaint.unit : progressWave.axis
                                            y: root.progressMirror ? progressWave.axis - height / 2 : 0
                                            ink: Qt.alpha(Commons.Color.accent, 0.65)
                                            styleName: root.progressVisualizerStyle
                                            horizontalMirror: root.progressMirror
                                            barCount: root.progressVisualizerBars
                                            frame: root.progressReactsToAudio ? root.audioFrame : [[], []]
                                        }

                                        WaveProgress {
                                            id: progressWave
                                            anchors.fill: parent
                                            drawWaves: progressPaint.showOlas
                                            mirrorAcrossTimeline: root.progressMirror
                                            intensity: 0.95
                                            speed: root.progressWaveSpeed / 100
                                            traveling: drawWaves && root.progressReactsToAudio
                                            bands: traveling ? root.audioFrame[0] : []
                                            unit: progressPaint.unit
                                            progress: seekSlider.position
                                            reversed: seekSlider.mirrored
                                            accent: Commons.Color.accent
                                            track: root.surfaceHover
                                        }
                                    }
                                    handle: Rectangle {
                                        x: seekSlider.leftPadding + seekSlider.visualPosition * (seekSlider.availableWidth - width)
                                        y: progressPaint.y + progressWave.axis - height / 2
                                        implicitWidth: Style.space(14)
                                        implicitHeight: implicitWidth
                                        radius: width / 2
                                        color: Commons.Color.accent
                                        border.color: seekSlider.activeFocus ? root.ink : "transparent"
                                    }
                                    onMoved: if (root.player?.canSeek)
                                        root.player.position = value
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        text: root.hasPosition ? root.clock(seekSlider.pressed ? seekSlider.value : timing.position) : "—"
                                        color: root.muted
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                    }
                                    Label {
                                        text: root.duration > 0 ? root.clock(root.duration) : "—"
                                        color: root.muted
                                    }
                                }
                            }

                            Repeater {
                                model: root.details
                                Label {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    color: root.muted
                                    font.pixelSize: Style.font.bodySmall
                                    text: strings.t(modelData[0]).arg(modelData[1])
                                }
                            }
                        }
                    }
                    LyricsPane {
                        visible: root.showLyrics
                        Layout.fillWidth: true
                        Layout.leftMargin: Style.space(8)
                        Layout.rightMargin: Style.space(8)
                        Layout.minimumHeight: Style.space(86)
                        Layout.preferredHeight: implicitHeight
                        Layout.fillHeight: true
                        requestActive: root.opened && root.showLyrics
                        trackTitle: root.title
                        artist: root.artist
                        album: root.album
                        duration: root.duration
                        position: timing.position
                        hasPosition: root.hasPosition
                        ink: root.ink
                        muted: root.muted
                        outline: root.outline
                    }
                }
            }

            FinishedPane {
                id: settingsCard
                visible: root.showSettings
                x: dashboard.companionX
                y: dashboard.companionY
                width: panel.settingsWidth
                height: dashboard.settingsHeight
                radius: Style.space(20)
                opacityBoost: 0.08
                artworkOpacity: 0.14

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                ColumnLayout {
                    id: settingsChrome
                    anchors.fill: parent
                    anchors.margins: Style.space(10)
                    spacing: Style.space(5)

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Style.space(8)
                        Layout.rightMargin: Style.space(8)
                        Layout.topMargin: Style.space(6)
                        spacing: Style.space(8)
                        Label {
                            Layout.fillWidth: true
                            text: strings.t("settings")
                            font.bold: true
                            font.pixelSize: Style.font.subtitle
                        }
                        Control {
                            iconText: "󰅖"
                            tooltipText: strings.t("closeSettings")
                            Accessible.name: tooltipText
                            background: root.surface
                            onClicked: {
                                root.showSettings = false;
                                settingsButton.forceActiveFocus();
                            }
                        }
                    }

                    Flickable {
                        id: settingsScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        implicitHeight: settingsPage.implicitHeight + Style.space(12)
                        clip: true
                        contentWidth: width
                        contentHeight: implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        QQC.ScrollBar.vertical: QQC.ScrollBar {}

                        Connections {
                            target: root
                            function onShowSettingsChanged() {
                                if (root.showSettings)
                                    settingsScroll.contentY = 0;
                            }
                        }

                        ColumnLayout {
                            id: settingsPage
                            x: Style.space(8)
                            y: Style.space(6)
                            width: parent.width - Style.space(16)
                            spacing: Style.space(10)
                            SettingGroup {
                                caption: strings.t("playerAppearance")
                                Toggle {
                                    text: strings.t("glassFinish")
                                    checked: root.glassPlayer
                                    onToggled: root.saveSetting("glassPlayer", checked)
                                }
                                Toggle {
                                    visible: root.glassPlayer
                                    text: strings.t("glassCoverBackground")
                                    checked: root.glassCoverBackground
                                    onToggled: root.saveSetting("glassCoverBackground", checked)
                                }
                                Toggle {
                                    visible: root.glassPlayer
                                    text: strings.t("blurBackdrop")
                                    checked: root.blurGlassBackdrop
                                    onToggled: root.saveSetting("blurGlassBackdrop", checked)
                                }
                                Label {
                                    visible: root.wantsBackdropBlur && root.backdropBlurFailed
                                    Layout.fillWidth: true
                                    text: strings.t("blurUnavailable")
                                    color: Commons.Color.urgent
                                    wrapMode: Text.WordWrap
                                }
                                Toggle {
                                    text: strings.t("autoOnlineArt")
                                    checked: root.autoOnlineArt
                                    onToggled: root.saveSetting("autoOnlineArt", checked)
                                }
                            }

                            SettingGroup {
                                caption: strings.t("appearance")
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        text: strings.t("titleWidth")
                                        Layout.fillWidth: true
                                    }
                                    Selector {
                                        implicitWidth: Style.space(110)
                                        Accessible.name: strings.t("titleWidth")
                                        model: [strings.t("autoWidth"), strings.t("fixedWidth")]
                                        currentIndex: root.automaticWidth ? 0 : 1
                                        onActivated: root.saveSetting("titleWidthMode", currentIndex === 0 ? "auto" : "fixed")
                                    }
                                    Stepper {
                                        visible: !root.automaticWidth
                                        Accessible.name: strings.t("titleWidth")
                                        from: 64
                                        to: 360
                                        stepSize: 8
                                        editable: true
                                        value: root.fixedTitleWidth
                                        onValueModified: root.saveSetting("titleWidth", value)
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        text: strings.t("idleBarMode")
                                        Layout.fillWidth: true
                                    }
                                    Selector {
                                        Accessible.name: strings.t("idleBarMode")
                                        model: [strings.t("idleCompact"), strings.t("idleReserve")]
                                        currentIndex: root.reserveIdleSpace ? 1 : 0
                                        onActivated: root.saveSetting("idleBarMode", currentIndex === 1 ? "reserve" : "compact")
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(10)
                                    SizeSetting {
                                        stacked: true
                                        Layout.preferredWidth: 1
                                        settingKey: "titleFontSize"
                                        caption: strings.t("titleFontSize")
                                        amount: root.titleFontSize
                                        minimum: 8
                                        maximum: 18
                                    }

                                    SizeSetting {
                                        stacked: true
                                        Layout.preferredWidth: 1
                                        settingKey: "barIconSize"
                                        caption: strings.t("barIconSize")
                                        amount: root.barIconSize
                                        minimum: 8
                                        maximum: 22
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(10)
                                    Toggle {
                                        Layout.preferredWidth: 1
                                        text: strings.t("scrollTitle")
                                        checked: root.scrollTitle
                                        onToggled: root.saveSetting("scrollTitle", checked)
                                    }

                                    Toggle {
                                        Layout.preferredWidth: 1
                                        text: strings.t("barCover")
                                        checked: root.showBarCover
                                        onToggled: root.saveSetting("showBarCover", checked)
                                    }
                                }
                            }

                            SettingGroup {
                                caption: strings.t("barControls")
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 2
                                    columnSpacing: Style.space(10)

                                    Repeater {
                                        model: root.controls
                                        Toggle {
                                            required property string modelData
                                            Layout.preferredWidth: 1
                                            text: strings.t(modelData === "play" ? "playPause" : modelData)
                                            checked: root.enabledControls.includes(modelData)
                                            onToggled: root.setControl(modelData, checked)
                                        }
                                    }
                                }
                            }

                            SettingGroup {
                                id: visualizerGroup
                                caption: strings.t("displaySettings")
                                property string target: "player"

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(5)

                                    Repeater {
                                        model: [
                                            {
                                                key: "player",
                                                name: "playerTarget"
                                            },
                                            {
                                                key: "bar",
                                                name: "barTarget"
                                            },
                                            {
                                                key: "timeline",
                                                name: "timeline"
                                            }
                                        ]
                                        Control {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            horizontalPadding: Style.space(3)
                                            fontSize: Style.font.bodySmall
                                            text: strings.t(modelData.name)
                                            selected: visualizerGroup.target === modelData.key
                                            Accessible.pressed: selected
                                            onClicked: visualizerGroup.target = modelData.key
                                        }
                                    }
                                }

                                Label {
                                    text: strings.t("visualizer")
                                    font.bold: true
                                    color: Commons.Color.accent
                                }

                                VisualizerSettings {
                                    target: visualizerGroup.target
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: root.saveFailed || root.audioFailed
                                text: strings.t(root.saveFailed ? "saveFailed" : "audioFailed")
                                color: Commons.Color.urgent
                            }
                        }
                    }
                }
            }
        }
    }
}
