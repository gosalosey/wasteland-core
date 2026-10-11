// wasteland_vehicles :: html/lockpick.js
// Lockpick minigame. A pick turns around the lock; press E, Space or click
// while it is inside the bright zone to set a pin. Every pin set: a new
// zone somewhere else, the pick turns the other way, a little faster.
// One miss and the try fails. Esc gives up.
// Data: { pins, zone (degrees), speed (degrees a second), speedStep }
// Posts: result { success }, cancel

(function () {
    'use strict';

    // Angles in degrees, 0 at the top, clockwise.
    function norm(a) { return ((a % 360) + 360) % 360; }
    function angDiff(a, b) { const d = Math.abs(norm(a) - norm(b)); return d > 180 ? 360 - d : d; }
    function inZone(angle, center, width) { return angDiff(angle, center) <= width / 2; }
    // A new zone at least `minGap` degrees away from where the pick is now.
    function nextZone(needle, rnd, minGap) {
        const gap = minGap === undefined ? 100 : minGap;
        return norm(needle + gap + rnd() * (360 - 2 * gap));
    }

    const helpers = { norm: norm, angDiff: angDiff, inZone: inZone, nextZone: nextZone };
    if (typeof module === 'object' && module.exports) { module.exports = helpers; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    const NS = 'http://www.w3.org/2000/svg';
    const R = 92;
    let st = null;

    function svg(tag, attrs) {
        const e = document.createElementNS(NS, tag);
        for (const k in attrs) e.setAttribute(k, attrs[k]);
        return e;
    }
    function point(angle, r) {
        const rad = (angle - 90) * Math.PI / 180;
        return [120 + r * Math.cos(rad), 120 + r * Math.sin(rad)];
    }
    function arc(center, width, r) {
        const a = point(center - width / 2, r), b = point(center + width / 2, r);
        return 'M ' + a[0] + ' ' + a[1] + ' A ' + r + ' ' + r + ' 0 ' + (width > 180 ? 1 : 0) + ' 1 ' + b[0] + ' ' + b[1];
    }

    let audio = null;
    function click(freq, ms) {
        try {
            audio = audio || new (window.AudioContext || window.webkitAudioContext)();
            const o = audio.createOscillator(), g = audio.createGain();
            o.type = 'square'; o.frequency.value = freq;
            g.gain.setValueAtTime(0.05, audio.currentTime);
            g.gain.exponentialRampToValueAtTime(0.0001, audio.currentTime + ms / 1000);
            o.connect(g); g.connect(audio.destination);
            o.start(); o.stop(audio.currentTime + ms / 1000);
        } catch (e) { /* no sound */ }
    }

    function draw() {
        st.zoneEl.setAttribute('d', arc(st.zone, st.width, R));
        const p = point(st.angle, R + 8), q = point(st.angle, 30);
        st.pick.setAttribute('x1', q[0]); st.pick.setAttribute('y1', q[1]);
        st.pick.setAttribute('x2', p[0]); st.pick.setAttribute('y2', p[1]);
        st.pins.forEach((el, i) => { el.className = 'wllp-pin' + (i < st.set ? ' is-set' : ''); });
    }

    function frame(t) {
        if (!st || st.over) return;
        const dt = st.last ? Math.min(0.05, (t - st.last) / 1000) : 0;
        st.last = t;
        st.angle = norm(st.angle + st.dir * st.speed * dt);
        draw();
        st.raf = requestAnimationFrame(frame);
    }

    function end(success, text) {
        st.over = true;
        cancelAnimationFrame(st.raf);
        st.root.classList.add(success ? 'is-ok' : 'is-fail');
        st.status.textContent = text;
        const api = st.api;
        setTimeout(() => api.post('result', { success: success }), success ? 600 : 800);
    }

    function attempt() {
        if (!st || st.over) return;
        if (inZone(st.angle, st.zone, st.width)) {
            st.set += 1;
            click(880, 60);
            if (st.set >= st.total) { draw(); end(true, 'The lock turns!'); return; }
            st.root.classList.remove('is-hit'); void st.root.offsetWidth; st.root.classList.add('is-hit');
            st.zone = nextZone(st.angle, Math.random);
            st.dir = -st.dir;
            st.speed += st.step;
            st.status.textContent = 'Pin ' + st.set + ' of ' + st.total + ' set';
        } else {
            click(140, 220);
            draw();
            end(false, 'The pick slips.');
        }
    }

    function onKey(e) {
        if (!st) return;
        if (e.key === 'Escape' || e.key === 'Backspace') {
            if (!st.over) { st.over = true; st.api.post('cancel'); }
            return;
        }
        if (e.repeat) return;
        if (e.key === 'e' || e.key === 'E' || e.key === ' ' || e.key === 'Enter') { e.preventDefault(); attempt(); }
    }

    UI.registerScreen('vehLockpick', {
        mount: function (el, data, api) {
            const total = Math.max(1, Math.min(10, Number(data.pins) || 4));
            st = { api: api, total: total, set: 0, angle: Math.random() * 360, dir: 1, over: false, last: 0,
                width: Math.max(5, Math.min(180, Number(data.zone) || 32)), speed: Number(data.speed) || 150, step: Number(data.speedStep) || 0 };
            st.zone = nextZone(st.angle, Math.random);

            const face = svg('svg', { viewBox: '0 0 240 240', class: 'wllp-svg' });
            const defs = svg('defs', {});
            const grad = svg('radialGradient', { id: 'wllp-metal', cx: '40%', cy: '35%', r: '75%' });
            grad.appendChild(svg('stop', { offset: '0%', 'stop-color': '#5a5c55' }));
            grad.appendChild(svg('stop', { offset: '70%', 'stop-color': '#2a2c27' }));
            grad.appendChild(svg('stop', { offset: '100%', 'stop-color': '#151612' }));
            defs.appendChild(grad);
            face.appendChild(defs);
            face.appendChild(svg('circle', { cx: 120, cy: 120, r: 112, fill: 'url(#wllp-metal)', stroke: '#0b0c0a', 'stroke-width': 4 }));
            face.appendChild(svg('circle', { cx: 120, cy: 120, r: R, fill: 'none', stroke: 'rgba(0,0,0,0.55)', 'stroke-width': 14 }));
            for (let i = 0; i < 12; i++) {
                const a = point(i * 30, 104), b = point(i * 30, 110);
                face.appendChild(svg('line', { x1: a[0], y1: a[1], x2: b[0], y2: b[1], stroke: 'rgba(230,230,220,0.25)', 'stroke-width': 2 }));
            }
            st.zoneEl = svg('path', { class: 'wllp-zone', fill: 'none', 'stroke-width': 14, 'stroke-linecap': 'round' });
            face.appendChild(st.zoneEl);
            // Keyhole
            face.appendChild(svg('circle', { cx: 120, cy: 112, r: 11, fill: '#050505' }));
            face.appendChild(svg('path', { d: 'M 113 116 L 127 116 L 131 142 L 109 142 Z', fill: '#050505' }));
            st.pick = svg('line', { class: 'wllp-pick', 'stroke-width': 4, 'stroke-linecap': 'round' });
            face.appendChild(st.pick);
            face.appendChild(svg('circle', { cx: 120, cy: 120, r: 6, fill: '#c9a227' }));

            st.pins = [];
            const pins = h('div', { class: 'wllp-pins' });
            for (let i = 0; i < total; i++) { const p = h('div', { class: 'wllp-pin' }); st.pins.push(p); pins.appendChild(p); }
            st.status = h('div', { class: 'wllp-status', text: 'Set ' + total + ' pins' });
            st.root = h('div', { class: 'wllp-root' },
                h('div', { class: 'wllp-title', text: 'Picking the lock' }),
                h('div', { class: 'wllp-face' }, face),
                pins, st.status,
                h('div', { class: 'wllp-hint', text: 'E / Space / click: set the pin when the pick is in the green  ·  Esc: give up' }));
            st.root.addEventListener('mousedown', (e) => { if (e.button === 0) attempt(); });
            el.appendChild(st.root);
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            draw();
            st.raf = requestAnimationFrame(frame);
        },
        unmount: function () {
            document.removeEventListener('keydown', onKey);
            if (st) cancelAnimationFrame(st.raf);
            st = null;
        },
    });

    const CSS = [
        '.wllp-root { position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); width: 320px; padding: 18px 18px 14px;',
        '  background: rgba(12,14,11,0.92); border: 1px solid rgba(127,199,90,0.35); border-radius: 10px; text-align: center;',
        '  box-shadow: 0 10px 40px rgba(0,0,0,0.6); color: #e6e6dc; user-select: none; }',
        '.wllp-title { font-size: 13px; letter-spacing: 0.18em; text-transform: uppercase; color: #7fc75a; margin-bottom: 8px; }',
        '.wllp-face { width: 240px; height: 240px; margin: 0 auto; }',
        '.wllp-svg { width: 240px; height: 240px; display: block; }',
        '.wllp-zone { stroke: #7fc75a; filter: drop-shadow(0 0 6px rgba(127,199,90,0.9)); }',
        '.wllp-pick { stroke: #e8c25a; filter: drop-shadow(0 0 3px rgba(0,0,0,0.9)); }',
        '.wllp-pins { display: flex; justify-content: center; gap: 8px; margin: 12px 0 6px; }',
        '.wllp-pin { width: 22px; height: 8px; border-radius: 2px; background: rgba(230,230,220,0.15); border: 1px solid rgba(230,230,220,0.25); }',
        '.wllp-pin.is-set { background: #7fc75a; border-color: #7fc75a; box-shadow: 0 0 6px rgba(127,199,90,0.8); }',
        '.wllp-status { font-size: 14px; min-height: 18px; }',
        '.wllp-hint { font-size: 10px; color: rgba(230,230,220,0.5); margin-top: 6px; }',
        '.wllp-root.is-hit .wllp-face { animation: wllp-hit 0.18s ease-out; }',
        '@keyframes wllp-hit { 0% { transform: scale(1); } 50% { transform: scale(1.04); } 100% { transform: scale(1); } }',
        '.wllp-root.is-ok { border-color: #7fc75a; } .wllp-root.is-ok .wllp-status { color: #7fc75a; }',
        '.wllp-root.is-fail { border-color: #d9534f; animation: wllp-shake 0.35s; } .wllp-root.is-fail .wllp-status { color: #ff9c90; }',
        '@keyframes wllp-shake { 0%,100% { transform: translate(-50%,-50%); } 25% { transform: translate(calc(-50% - 6px),-50%); }',
        '  75% { transform: translate(calc(-50% + 6px),-50%); } }',
    ].join('\n');
})();
