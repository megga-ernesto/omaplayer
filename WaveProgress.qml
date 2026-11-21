import QtQuick

Canvas {
    id: root

    required property real progress
    required property var bands
    required property color accent
    required property color track
    required property bool reversed
    required property real unit
    required property bool mirrorAcrossTimeline
    required property real intensity
    required property bool traveling
    property real speed: 1

    property bool showTrack: true
    property bool drawWaves: true

    readonly property real axis: height * (!drawWaves || mirrorAcrossTimeline ? 0.5 : 0.72)

    property var targetLevels: []
    property var frontLevels: []
    property var backLevels: []
    property real frontPhase: 0
    property real backPhase: 0.43

    Timer {
        id: travelClock
        property double previousTick: 0
        interval: 33
        repeat: true
        running: root.traveling && root.visible && root.progress > 0
        onRunningChanged: previousTick = running ? Date.now() : 0
        onTriggered: {
            const now = Date.now();
            const seconds = Math.min(0.10, Math.max(0, (now - previousTick) / 1000));
            previousTick = now;
            root.frontPhase = (root.frontPhase + seconds * root.speed * 0.50) % 2;
            root.backPhase = (root.backPhase + seconds * root.speed * 0.32) % 2;
            root.frontLevels = root.followAudio(root.frontLevels, seconds, 0.26, 0.62, 0.72);
            root.backLevels = root.followAudio(root.backLevels, seconds, 0.43, 0.90, 0.44);
            root.requestPaint();
        }
    }

    onBandsChanged: {
        if (!bands.length) {
            targetLevels = [];
            return;
        }

        const buckets = [0, 0, 0, 0, 0, 0];
        for (let i = 0; i < bands.length; i++) {
            const bucket = Math.floor(i * buckets.length / bands.length);
            buckets[bucket] = Math.max(buckets[bucket], bands[i]);
        }
        targetLevels = buckets;
    }

    function followAudio(previous, seconds, attack, release, localWeight) {
        if (!targetLevels.length)
            return previous;
        const overall = Math.max(...targetLevels);
        return targetLevels.map((peak, index) => {
            const target = localWeight * peak + (1 - localWeight) * overall;
            const current = previous[index] ?? 0.22;
            const timeConstant = target > current ? attack : release;
            return current + (target - current) * (1 - Math.exp(-seconds / timeConstant));
        });
    }

    onMirrorAcrossTimelineChanged: requestPaint()
    onShowTrackChanged: requestPaint()
    onDrawWavesChanged: requestPaint()
    onIntensityChanged: requestPaint()
    onProgressChanged: requestPaint()
    onAccentChanged: requestPaint()
    onTrackChanged: requestPaint()
    onReversedChanged: requestPaint()
    onUnitChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    function audioGain(levels, normalized) {
        if (!levels.length)
            return 0.40 * intensity;
        const position = Math.max(0, Math.min(1, normalized)) * (levels.length - 1);
        const lower = Math.floor(position);
        const higher = Math.min(levels.length - 1, lower + 1);
        const energy = levels[lower] + (levels[higher] - levels[lower]) * (position - lower);
        return intensity * (0.04 + 1.65 * energy);
    }

    function playedShape(context, span, end, baseline, wave) {
        const inset = 2 * unit;
        function screenX(distance) {
            const x = inset + distance;
            return reversed ? width - x : x;
        }

        const wavelengthSpace = Math.min(span, Math.max(52 * unit, end * 1.35));
        const segments = Math.max(2, Math.ceil(end / Math.max(0.75, unit)));
        const headroom = (mirrorAcrossTimeline ? Math.min(baseline, height - baseline) : baseline) - 2 * unit;
        const profile = [];

        context.beginPath();
        context.moveTo(screenX(0), baseline);
        for (let sample = 1; sample < segments; sample++) {
            const distance = end * sample / segments;
            const distanceFromPlayhead = end - distance;
            const normalized = distanceFromPlayhead / wavelengthSpace;
            const phase = (normalized * wave.frequency - wave.phase) * Math.PI;
            const heightRatio = 0.58 + 0.42 * Math.pow(Math.sin(phase / 2), 2);
            const envelope = Math.min(1, distance / (10 * unit), (end - distance) / (10 * unit));
            const gain = audioGain(wave.levels, normalized + wave.bandOffset);
            const rise = Math.max(0, Math.min(headroom, wave.strength * heightRatio * envelope * Math.pow(Math.sin(phase), 4) * gain));
            const x = screenX(distance);
            context.lineTo(x, baseline - rise);
            if (mirrorAcrossTimeline)
                profile.push([x, rise]);
        }
        context.lineTo(screenX(end), baseline);
        for (let i = profile.length - 1; i >= 0; i--)
            context.lineTo(profile[i][0], baseline + profile[i][1]);
        context.closePath();
        context.fill();
    }

    onPaint: {
        const context = getContext("2d");
        context.reset();
        context.clearRect(0, 0, width, height);
        const inset = 2 * unit;
        const span = Math.max(0, width - 2 * inset);
        const baseline = axis;
        const end = span * Math.max(0, Math.min(1, progress));

        context.lineCap = "round";
        context.lineWidth = 3 * unit;
        if (showTrack) {
            context.strokeStyle = track;
            context.beginPath();
            context.moveTo(inset, baseline);
            context.lineTo(inset + span, baseline);
            context.stroke();
        }

        if (end <= 0)
            return;

        if (drawWaves) {
            context.fillStyle = Qt.alpha(accent, accent.a * 0.22);
            playedShape(context, span, end, baseline, {
                phase: backPhase,
                levels: backLevels,
                frequency: 3.1,
                strength: height * 0.55,
                bandOffset: 0.16
            });
            const fill = context.createLinearGradient(0, 0, 0, mirrorAcrossTimeline ? height : baseline);
            fill.addColorStop(0, accent);
            fill.addColorStop(mirrorAcrossTimeline ? 0.5 : 1, Qt.alpha(accent, accent.a * 0.36));
            if (mirrorAcrossTimeline)
                fill.addColorStop(1, accent);
            context.fillStyle = fill;
            playedShape(context, span, end, baseline, {
                phase: frontPhase,
                levels: frontLevels,
                frequency: 3.8,
                strength: height * 0.65,
                bandOffset: 0
            });
        }

        if (showTrack) {
            context.strokeStyle = Qt.alpha(accent, accent.a * 0.83);
            context.beginPath();
            context.moveTo(reversed ? width - inset : inset, baseline);
            context.lineTo(reversed ? width - inset - end : inset + end, baseline);
            context.stroke();
        }
    }
}
