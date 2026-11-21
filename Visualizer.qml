import QtQuick
import qs.Commons

Canvas {
    id: root

    required property color ink
    required property string styleName
    property int barCount: 10
    property bool horizontalMirror: false
    property bool animateWaves: false
    property real waveSpeed: 1
    property var frame: [[], []]

    onBarCountChanged: requestPaint()
    onHorizontalMirrorChanged: requestPaint()
    onFrameChanged: if (styleName !== "waves")
        requestPaint()
    onInkChanged: requestPaint()
    onStyleNameChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    Loader {
        anchors.fill: parent
        active: root.visible && root.styleName === "waves"
        sourceComponent: WaveProgress {
            progress: 1
            bands: root.animateWaves ? root.frame[0] : []
            accent: root.ink
            track: "transparent"
            showTrack: false
            reversed: false
            unit: Style.spaceReal(1)
            mirrorAcrossTimeline: root.horizontalMirror
            intensity: 1.4
            traveling: root.animateWaves
            speed: root.waveSpeed
        }
    }

    function drawWave(context, samples, direction) {
        context.beginPath();
        for (let i = 0; i < samples.length; i++) {
            const x = 1 + (width - 2) * i / (samples.length - 1);
            const y = height / 2 + direction * samples[i] * (height - 4) / 2;
            if (i === 0)
                context.moveTo(x, y);
            else
                context.lineTo(x, y);
        }
        context.stroke();
    }

    function drawDot(context, x, y, radius) {
        context.beginPath();
        context.arc(x, y, radius, 0, 2 * Math.PI);
        context.fill();
    }

    onPaint: {
        const context = getContext("2d");
        context.reset();
        context.clearRect(0, 0, width, height);
        if (styleName === "waves")
            return;
        context.fillStyle = ink;
        context.strokeStyle = ink;
        context.lineWidth = 1.4;
        if (styleName === "wave") {
            const wave = frame[1].length > 1 ? frame[1] : [0, 0];
            drawWave(context, wave, -1);
            if (horizontalMirror)
                drawWave(context, wave, 1);
            return;
        }

        const bands = frame[0];
        const levels = Array(barCount).fill(0);
        for (let i = 0; i < bands.length; i++) {
            const bucket = Math.floor(i * barCount / bands.length);
            levels[bucket] = Math.max(levels[bucket], bands[i]);
        }
        const cell = width / levels.length;
        for (let i = 0; i < levels.length; i++) {
            const x = cell * (i + 0.5);
            const level = levels[i];
            if (styleName === "dots") {
                const radius = Math.min(1.4, cell / 3);
                const y = horizontalMirror ? height / 2 - level * (height / 2 - 2) : height - 2 - level * (height - 4);
                drawDot(context, x, y, radius);
                if (horizontalMirror)
                    drawDot(context, x, height - y, radius);
            } else if (horizontalMirror) {
                const size = 3 + level * (height - 4);
                context.fillRect(x - cell / 3, (height - size) / 2, cell * 2 / 3, size);
            } else {
                const size = 2 + level * (height - 4);
                context.fillRect(x - cell / 3, height - 1 - size, cell * 2 / 3, size);
            }
        }
    }
}
