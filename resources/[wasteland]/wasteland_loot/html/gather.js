// wasteland_loot :: html/gather.js
// Chopping / mining minigame: a pointer sweeps round a ring; press E (or
// Space) while it is in the green arc. Every hit is a swing; `hits` hits
// and the tree falls / the rock breaks. One miss and it fails (the player
// has to start again). Esc / X / Backspace gives up.
// Data: { kind = 'tree'|'rock', label, hits, zone (part of the circle), speed (turns a second), speedStep }

(function () {
    'use strict';

    function norm(a) { a = a % 360; return a < 0 ? a + 360 : a; }
    function angDiff(a, b) { const d = Math.abs(norm(a) - norm(b)); return d > 180 ? 360 - d : d; }
    function inZone(angle, center, width) { return angDiff(angle, center) <= width / 2; }
    // The next arc is always well away from the pointer (no free hits).
    function nextZone(from, rnd) { return norm(from + 110 + rnd() * 140); }
    function settings(data) {
        return {
            hits: Math.max(1, Math.min(12, Math.floor(Number(data.hits) || 3))),
            width: Math.max(20, Math.min(200, (Number(data.zone) || 0.2) * 360)),
            speed: Math.max(40, Math.min(900, (Number(data.speed) || 0.45) * 360)),
            step: Math.max(0, Math.min(180, (Number(data.speedStep) || 0) * 360)),
        };
    }

    const helpers = { norm: norm, angDiff: angDiff, inZone: inZone, nextZone: nextZone, settings: settings };
    if (typeof module === 'object' && module.exports) { module.exports = helpers; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    const NS = 'http://www.w3.org/2000/svg';
    const C = 130, R = 100;
    let st = null;

    function svg(tag, attrs) {
        const e = document.createElementNS(NS, tag);
        for (const k in attrs) e.setAttribute(k, attrs[k]);
        return e;
    }
    function point(angle, r) {
        const rad = (angle - 90) * Math.PI / 180;
        return [C + r * Math.cos(rad), C + r * Math.sin(rad)];
    }
    function arc(center, width, r) {
        const a = point(center - width / 2, r), b = point(center + width / 2, r);
        return 'M ' + a[0] + ' ' + a[1] + ' A ' + r + ' ' + r + ' 0 ' + (width > 180 ? 1 : 0) + ' 1 ' + b[0] + ' ' + b[1];
    }

    let audio = null;
    function tone(freq, ms, type, vol) {
        try {
            audio = audio || new (window.AudioContext || window.webkitAudioContext)();
            const o = audio.createOscillator(), g = audio.createGain();
            o.type = type || 'square'; o.frequency.value = freq;
            g.gain.setValueAtTime(vol || 0.05, audio.currentTime);
            g.gain.exponentialRampToValueAtTime(0.0001, audio.currentTime + ms / 1000);
            o.connect(g); g.connect(audio.destination);
            o.start(); o.stop(audio.currentTime + ms / 1000);
        } catch (e) { /* no sound */ }
    }
    function thunk() { tone(st && st.kind === 'rock' ? 220 : 130, 120, 'triangle', 0.12); tone(st && st.kind === 'rock' ? 900 : 520, 50, 'square', 0.03); }

    // A crack in the core for every hit (wood grain splits / stone fractures).
    function addCrack(i) {
        const a0 = (i * 137.5 + 20) % 360;
        let d = 'M ' + point(a0, 6).join(' ');
        let ang = a0, r = 6;
        while (r < 68) {
            r += 10 + Math.random() * 8;
            ang += (Math.random() - 0.5) * 40;
            d += ' L ' + point(ang, Math.min(r, 68)).join(' ');
        }
        const path = svg('path', { d: d, class: 'wlg-crack' });
        st.cracks.appendChild(path);
    }

    function chips() {
        for (let i = 0; i < 9; i++) {
            const c = h('div', { class: 'wlg-chip' });
            const a = Math.random() * Math.PI * 2, dist = 70 + Math.random() * 90;
            c.style.setProperty('--dx', Math.cos(a) * dist + 'px');
            c.style.setProperty('--dy', Math.sin(a) * dist + 'px');
            c.style.setProperty('--rot', (Math.random() * 720 - 360) + 'deg');
            st.face.appendChild(c);
            setTimeout(() => c.remove(), 700);
        }
    }

    function draw() {
        st.zoneEl.setAttribute('d', arc(st.zone, st.width, R));
        const p = point(st.angle, R + 14), q = point(st.angle, R - 18);
        st.needle.setAttribute('x1', q[0]); st.needle.setAttribute('y1', q[1]);
        st.needle.setAttribute('x2', p[0]); st.needle.setAttribute('y2', p[1]);
        st.zoneEl.classList.toggle('is-in', inZone(st.angle, st.zone, st.width));
        st.pips.forEach((el, i) => { el.className = 'wlg-pip' + (i < st.done ? ' is-done' : ''); });
    }

    function frame(t) {
        if (!st || st.over) return;
        const dt = st.last ? Math.min(0.05, (t - st.last) / 1000) : 0;
        st.last = t;
        st.angle = norm(st.angle + st.speed * dt);
        draw();
        st.raf = requestAnimationFrame(frame);
    }

    function end(success, text) {
        st.over = true;
        cancelAnimationFrame(st.raf);
        st.root.classList.add(success ? 'is-ok' : 'is-fail');
        st.status.textContent = text;
        const api = st.api;
        setTimeout(() => api.post('result', { success: success }), success ? 650 : 900);
    }

    function attempt() {
        if (!st || st.over) return;
        if (inZone(st.angle, st.zone, st.width)) {
            st.done += 1;
            thunk();
            addCrack(st.done);
            chips();
            st.root.classList.remove('is-hit'); void st.root.offsetWidth; st.root.classList.add('is-hit');
            if (st.done >= st.total) {
                draw();
                end(true, st.kind === 'rock' ? 'The rock breaks apart!' : 'Timber!');
                return;
            }
            st.zone = nextZone(st.angle, Math.random);
            st.speed += st.step;
            st.status.textContent = (st.kind === 'rock' ? 'Strike ' : 'Swing ') + st.done + ' of ' + st.total;
        } else {
            tone(110, 260, 'sawtooth', 0.06);
            draw();
            end(false, st.kind === 'rock' ? 'The pickaxe glances off. Try again.' : 'The axe slips. Try again.');
        }
    }

    function onKey(e) {
        if (!st) return;
        const k = e.key;
        if (k === 'Escape' || k === 'Backspace' || k === 'x' || k === 'X') {
            if (!st.over) { st.over = true; st.api.post('cancel'); }
            return;
        }
        if (e.repeat) return;
        if (k === 'e' || k === 'E' || k === ' ' || k === 'Enter') { e.preventDefault(); attempt(); }
    }

    const ICONS = {
        tree: '<path d="M14 4l6 6-3 3-6-6z"/><path d="M12.5 8.5L3 18l3 3 9.5-9.5"/>',
        rock: '<path d="M3 10c4-5 14-5 18 0"/><path d="M12 6v15"/><path d="M10 21h4"/>',
    };

    UI.registerScreen('lootGather', {
        mount: function (el, data, api) {
            const s = settings(data || {});
            const kind = data.kind === 'rock' ? 'rock' : 'tree';
            st = { api: api, kind: kind, total: s.hits, done: 0, angle: Math.random() * 360, over: false, last: 0,
                width: s.width, speed: s.speed, step: s.step };
            st.zone = nextZone(st.angle, Math.random);

            const face = svg('svg', { viewBox: '0 0 260 260', class: 'wlg-svg' });
            const defs = svg('defs', {});
            const grad = svg('radialGradient', { id: 'wlg-core-' + kind, cx: '42%', cy: '38%', r: '70%' });
            const cols = kind === 'rock' ? ['#8a8a84', '#55554f', '#2b2b28'] : ['#b3824e', '#7a4f2a', '#3d2614'];
            grad.appendChild(svg('stop', { offset: '0%', 'stop-color': cols[0] }));
            grad.appendChild(svg('stop', { offset: '65%', 'stop-color': cols[1] }));
            grad.appendChild(svg('stop', { offset: '100%', 'stop-color': cols[2] }));
            defs.appendChild(grad);
            face.appendChild(defs);
            // Outer ring track
            face.appendChild(svg('circle', { cx: C, cy: C, r: R, fill: 'none', stroke: 'rgba(0,0,0,0.6)', 'stroke-width': 18 }));
            face.appendChild(svg('circle', { cx: C, cy: C, r: R, fill: 'none', stroke: 'rgba(230,230,220,0.08)', 'stroke-width': 18 }));
            for (let i = 0; i < 24; i++) {
                const a = point(i * 15, R + 12), b = point(i * 15, R + (i % 2 ? 15 : 18));
                face.appendChild(svg('line', { x1: a[0], y1: a[1], x2: b[0], y2: b[1], stroke: 'rgba(230,230,220,0.22)', 'stroke-width': 2 }));
            }
            st.zoneEl = svg('path', { class: 'wlg-zone', fill: 'none', 'stroke-width': 18, 'stroke-linecap': 'round' });
            face.appendChild(st.zoneEl);
            // Core: a log end (rings) or a stone
            face.appendChild(svg('circle', { cx: C, cy: C, r: 72, fill: 'url(#wlg-core-' + kind + ')', stroke: 'rgba(0,0,0,0.7)', 'stroke-width': 3 }));
            if (kind === 'tree') {
                for (const r of [16, 30, 44, 58]) face.appendChild(svg('circle', { cx: C + 2, cy: C - 1, r: r, fill: 'none', stroke: 'rgba(40,22,10,0.55)', 'stroke-width': 2 }));
            } else {
                face.appendChild(svg('path', { d: 'M 84 112 L 110 96 L 150 102 L 172 128', fill: 'none', stroke: 'rgba(255,255,255,0.12)', 'stroke-width': 3 }));
                face.appendChild(svg('path', { d: 'M 92 160 L 128 170 L 168 152', fill: 'none', stroke: 'rgba(0,0,0,0.3)', 'stroke-width': 3 }));
            }
            st.cracks = svg('g', {});
            face.appendChild(st.cracks);
            st.needle = svg('line', { class: 'wlg-needle', 'stroke-width': 6, 'stroke-linecap': 'round' });
            face.appendChild(st.needle);

            const icon = h('div', { class: 'wlg-icon' });
            icon.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' + ICONS[kind] + '</svg>';

            st.pips = [];
            const pips = h('div', { class: 'wlg-pips' });
            for (let i = 0; i < st.total; i++) { const p = h('div', { class: 'wlg-pip' }); st.pips.push(p); pips.appendChild(p); }
            st.status = h('div', { class: 'wlg-status', text: (kind === 'rock' ? 'Strike' : 'Swing') + ' when the needle is in the green' });
            st.face = h('div', { class: 'wlg-face' }, face);
            st.root = h('div', { class: 'wlg-root wlg-' + kind },
                h('div', { class: 'wlg-head' }, icon, h('div', { class: 'wlg-title', text: data.label || (kind === 'rock' ? 'Mining rock' : 'Chopping tree') })),
                st.face, pips, st.status,
                h('div', { class: 'wlg-hint' }, h('span', { class: 'wlg-key', text: 'E' }), ' hit in the green   ', h('span', { class: 'wlg-key', text: 'X' }), ' stop'));
            st.root.addEventListener('mousedown', (e) => { if (e.button === 0) attempt(); });
            el.appendChild(h('div', { class: 'wlg-shade' }));
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
        '.wlg-shade { position: absolute; inset: 0; pointer-events: none;',
        '  background: radial-gradient(circle at 50% 50%, rgba(0,0,0,0.35) 0%, rgba(0,0,0,0.78) 45%, rgba(0,0,0,0.9) 100%); animation: wlg-fade 0.25s ease-out; }',
        '.wlg-root { position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); width: 340px; padding: 18px 18px 14px;',
        '  background: linear-gradient(180deg, rgba(22,24,19,0.96), rgba(10,12,9,0.96)); border: 1px solid var(--wlg-accent); border-radius: 14px;',
        '  text-align: center; box-shadow: 0 0 0 1px rgba(0,0,0,0.6), 0 18px 60px rgba(0,0,0,0.7), 0 0 40px var(--wlg-glow);',
        '  color: #e6e6dc; user-select: none; animation: wlg-pop 0.25s cubic-bezier(.2,1.4,.4,1); }',
        '.wlg-tree { --wlg-accent: rgba(127,199,90,0.55); --wlg-glow: rgba(127,199,90,0.12); --wlg-ink: #7fc75a; }',
        '.wlg-rock { --wlg-accent: rgba(240,160,50,0.55); --wlg-glow: rgba(240,160,50,0.12); --wlg-ink: #f0a032; }',
        '.wlg-head { display: flex; align-items: center; justify-content: center; gap: 10px; margin-bottom: 6px; }',
        '.wlg-icon { width: 26px; height: 26px; color: var(--wlg-ink); }',
        '.wlg-icon svg { width: 100%; height: 100%; }',
        '.wlg-title { font-size: 14px; letter-spacing: 0.2em; text-transform: uppercase; color: var(--wlg-ink); }',
        '.wlg-face { position: relative; width: 260px; height: 260px; margin: 0 auto; }',
        '.wlg-svg { width: 260px; height: 260px; display: block; }',
        '.wlg-zone { stroke: #5fbf4a; opacity: 0.85; transition: opacity 0.08s; filter: drop-shadow(0 0 6px rgba(95,191,74,0.8)); }',
        '.wlg-zone.is-in { stroke: #8cf06a; opacity: 1; filter: drop-shadow(0 0 12px rgba(140,240,106,1)); }',
        '.wlg-needle { stroke: #f4f1e6; filter: drop-shadow(0 0 4px rgba(0,0,0,1)); }',
        '.wlg-crack { fill: none; stroke: rgba(10,6,3,0.85); stroke-width: 3; stroke-linecap: round; stroke-linejoin: round;',
        '  stroke-dasharray: 300; stroke-dashoffset: 300; animation: wlg-draw 0.25s ease-out forwards; }',
        '.wlg-chip { position: absolute; left: 50%; top: 50%; width: 7px; height: 5px; margin: -2px 0 0 -3px; border-radius: 1px;',
        '  background: var(--wlg-chip, #a06a3a); animation: wlg-chip 0.65s ease-out forwards; pointer-events: none; }',
        '.wlg-rock .wlg-chip { --wlg-chip: #9a9a92; }',
        '.wlg-pips { display: flex; justify-content: center; gap: 8px; margin: 10px 0 6px; }',
        '.wlg-pip { width: 26px; height: 8px; border-radius: 3px; background: rgba(230,230,220,0.12); border: 1px solid rgba(230,230,220,0.25); transition: all 0.15s; }',
        '.wlg-pip.is-done { background: var(--wlg-ink); border-color: var(--wlg-ink); box-shadow: 0 0 8px var(--wlg-ink); }',
        '.wlg-status { font-size: 14px; min-height: 18px; }',
        '.wlg-hint { font-size: 11px; color: rgba(230,230,220,0.55); margin-top: 8px; }',
        '.wlg-key { display: inline-block; min-width: 18px; padding: 1px 5px; margin: 0 3px; border: 1px solid rgba(230,230,220,0.4); border-radius: 4px;',
        '  color: #f4f1e6; background: rgba(255,255,255,0.06); font-weight: bold; }',
        '.wlg-root.is-hit .wlg-face { animation: wlg-hit 0.2s ease-out; }',
        '.wlg-root.is-ok .wlg-status { color: var(--wlg-ink); font-weight: bold; }',
        '.wlg-root.is-ok .wlg-face { animation: wlg-break 0.6s ease-in forwards; }',
        '.wlg-root.is-fail { border-color: #d9534f; animation: wlg-shake 0.4s; } .wlg-root.is-fail .wlg-status { color: #ff9c90; }',
        '@keyframes wlg-fade { from { opacity: 0; } to { opacity: 1; } }',
        '@keyframes wlg-pop { from { transform: translate(-50%,-50%) scale(0.85); opacity: 0; } to { transform: translate(-50%,-50%) scale(1); opacity: 1; } }',
        '@keyframes wlg-hit { 0% { transform: scale(1); } 40% { transform: scale(0.95) rotate(-2deg); } 100% { transform: scale(1); } }',
        '@keyframes wlg-break { 0% { transform: scale(1); } 30% { transform: scale(1.06); } 100% { transform: scale(0.6); opacity: 0; } }',
        '@keyframes wlg-draw { to { stroke-dashoffset: 0; } }',
        '@keyframes wlg-chip { from { transform: translate(0,0) rotate(0); opacity: 1; } to { transform: translate(var(--dx),var(--dy)) rotate(var(--rot)); opacity: 0; } }',
        '@keyframes wlg-shake { 0%,100% { transform: translate(-50%,-50%); } 20% { transform: translate(calc(-50% - 8px),-50%); }',
        '  40% { transform: translate(calc(-50% + 8px),-50%); } 60% { transform: translate(calc(-50% - 5px),-50%); } 80% { transform: translate(calc(-50% + 5px),-50%); } }',
    ].join('\n');
})();
