// wasteland_survival :: html/hud.js
// Survival HUD (runs inside wasteland_ui, no input focus). Two styles:
//   body     - (default) a body figure (red while bleeding, green tint while
//              infected) with rings in an arc: health, stamina, food, drink;
//              small rings top left for armour (outer ring the vest, inner
//              ring the plates) and voice (range, lit while talking); small
//              rings for temperature, pee and poop; bleeding / infection tags
//   classic  - health (and armour) as bars on a riveted plate, food, drink,
//              temperature, pee and poop as round iron dials
// Modes:
//   compact    - every icon, always
//   immersive  - an icon only while it matters (low, cold, hot)
//   off        - nothing
// /hud opens edit mode: drag the HUD anywhere, pick mode, row/column and
// size, then Save (client/main.lua stores it on the player's PC).
// Also: a line with the player's server id, character name and cash (moves
// with the HUD), and a stamina bar at the bottom middle of the screen that
// only shows while stamina is being used.
// Data: { mode, health, armor (vest %, only while one is worn), plates (%), stamina, voice = { talking, level, levels, on },
//         portrait = { sig, shots? = { sig, with, without } } (the character picture, client/portrait.lua),
//         editing, layout = { x, y, vertical, size, style },
//         info = { id, name, cash },
//         stats = { hunger, thirst, infection, bleeding, temperature, treatment, dead } }

(function () {
    'use strict';

    // ------------------------------------------------------------------
    // Pure helpers (unit-tested with Node)
    // ------------------------------------------------------------------

    const LOW = 35;       // amber at or below; immersive shows the icon
    const CRITICAL = 15;  // red and pulsing at or below
    const TEMP_MIN = 33;  // thermometer empty
    const TEMP_MAX = 39;  // thermometer full

    const clamp = (v) => Math.max(0, Math.min(100, Math.round(v)));

    function levelOf(value) {
        if (value <= CRITICAL) return 'critical';
        if (value <= LOW) return 'low';
        return 'ok';
    }

    function tempLevel(t) {
        if (t <= 34.5 || t >= 39.5) return 'critical';
        if (t <= 35.5 || t >= 38.5) return 'low';
        return 'ok';
    }

    // Icons to show: [{ key, label, fill 0..100, level ok|low|critical }]
    function icons(data) {
        const s = data.stats || {};
        if (data.mode === 'off' || s.dead) return [];
        const all = [];
        if (typeof data.health === 'number') all.push({ key: 'health', label: 'Health', fill: clamp(data.health) });
        // plates (in the vest) above the vest's own bar
        if (typeof data.plates === 'number') all.push({ key: 'plates', label: 'Plates', fill: clamp(data.plates) });
        if (typeof data.armor === 'number') all.push({ key: 'armor', label: 'Armor', fill: clamp(data.armor) });
        if (typeof s.hunger === 'number') all.push({ key: 'food', label: 'Food', fill: clamp(s.hunger) });
        if (typeof s.thirst === 'number') all.push({ key: 'drink', label: 'Drink', fill: clamp(s.thirst) });
        all.forEach((i) => { i.level = levelOf(i.fill); });
        if (typeof s.temperature === 'number') {
            const t = s.temperature;
            all.push({ key: 'temp', label: 'Temp.', fill: clamp((t - TEMP_MIN) / (TEMP_MAX - TEMP_MIN) * 100), level: tempLevel(t),
                hot: t >= 38.5 });
        }
        // toilet: these fill up (full = you have to go)
        const need = (v) => (v >= 85 ? 'critical' : v >= 65 ? 'low' : 'ok');
        if (typeof s.bladder === 'number') all.push({ key: 'pee', label: 'Pee', fill: clamp(s.bladder), level: need(s.bladder) });
        if (typeof s.bowel === 'number') all.push({ key: 'poop', label: 'Poop', fill: clamp(s.bowel), level: need(s.bowel) });
        if (data.mode === 'immersive') return all.filter((i) => i.level !== 'ok');
        return all;
    }

    // Badges: bleeding (1-3) and infection (percent, treated or not).
    function badges(data) {
        const s = data.stats || {};
        if (data.mode === 'off' || s.dead) return [];
        const out = [];
        if (s.bleeding > 0) {
            const lvl = Math.min(3, s.bleeding);
            out.push({ key: 'bleeding', level: lvl, text: ['', 'Bleeding', 'Bleeding heavily', 'Bleeding severely'][lvl] });
        }
        if (s.infection > 0) {
            out.push({ key: 'infection', text: (s.treatment ? 'Infection (treated) ' : 'Infection ') + clamp(s.infection) + '%' });
        }
        return out;
    }

    // Id, name and cash line (null when the HUD is off). Cash null = unknown
    // (inventory not running).
    function infoLine(data) {
        const s = data.stats || {};
        if (data.mode === 'off' || s.dead || !data.info) return null;
        const i = data.info;
        const cash = typeof i.cash === 'number' ? '$' + Math.max(0, Math.floor(i.cash)).toLocaleString('en-US') : null;
        return { id: typeof i.id === 'number' ? '#' + i.id : null, name: i.name ? String(i.name) : null, cash: cash };
    }

    // Stamina bar: shown only while stamina is not full (and the HUD is on).
    function staminaBar(data) {
        const s = data.stats || {};
        if (data.mode === 'off' || s.dead || typeof data.stamina !== 'number') return { visible: false, fill: 100 };
        const fill = clamp(data.stamina);
        return { visible: fill < 100, fill: fill, low: fill <= 20 };
    }

    // The body style: rings in the arc, the small rings, the armour and voice
    // rings, and how the body figure looks. Rings: [{ key, fill, level, text }].
    function bodyView(data) {
        const s = data.stats || {};
        if (data.mode === 'off' || s.dead) return null;
        const ring = (key, v) => ({ key: key, fill: clamp(v), level: levelOf(clamp(v)), text: clamp(v) + '%' });
        let big = [];
        if (typeof data.health === 'number') big.push(ring('health', data.health));
        if (typeof data.stamina === 'number') big.push(ring('stamina', data.stamina));
        if (typeof s.hunger === 'number') big.push(ring('food', s.hunger));
        if (typeof s.thirst === 'number') big.push(ring('drink', s.thirst));
        const small = icons(Object.assign({}, data, { mode: 'compact', health: null, armor: null, plates: null, stats: Object.assign({}, s, { hunger: null, thirst: null }) }))
            .filter((i) => i.key === 'temp' || i.key === 'pee' || i.key === 'poop');
        const armor = typeof data.armor === 'number'
            ? { worn: true, fill: clamp(data.armor), plates: typeof data.plates === 'number' ? clamp(data.plates) : 0, level: levelOf(clamp(data.armor)) }
            : { worn: false, fill: 0, plates: 0, level: 'ok' };
        const v = data.voice || {};
        const levels = v.levels || 3;
        const voice = { on: v.on !== false, talking: v.talking === true,
            fill: typeof v.level === 'number' ? clamp(v.level / levels * 100) : (v.on === false ? 0 : 66) };
        const immersive = data.mode === 'immersive';
        if (immersive) {
            big = big.filter((i) => i.level !== 'ok');
        }
        return {
            big: big,
            small: immersive ? small.filter((i) => i.level !== 'ok') : small,
            armor: armor, voice: voice,
            body: { bleeding: Math.min(3, s.bleeding || 0), infected: (s.infection || 0) > 0,
                hurt: typeof data.health === 'number' && data.health <= LOW },
        };
    }

    // The character picture: `a` is a shot with the character, `b` the same
    // view without (RGBA pixel arrays, w x h). Pixels that differ are the
    // character: they keep a's colour, the rest become clear. Returns the
    // RGBA result and the box around the character ({ x, y, w, h }, null if
    // nothing differs).
    function cutout(a, b, w, h) {
        const out = new Uint8ClampedArray(w * h * 4);
        const rows = new Uint32Array(h), cols = new Uint32Array(w);
        for (let i = 0, px = 0; px < w * h; px++, i += 4) {
            const d = Math.abs(a[i] - b[i]) + Math.abs(a[i + 1] - b[i + 1]) + Math.abs(a[i + 2] - b[i + 2]);
            const alpha = d >= 48 ? 255 : d > 24 ? Math.round((d - 24) * 255 / 24) : 0;
            out[i] = a[i]; out[i + 1] = a[i + 1]; out[i + 2] = a[i + 2]; out[i + 3] = alpha;
            if (alpha > 128) { rows[Math.floor(px / w)]++; cols[px % w]++; }
        }
        // the box: rows and columns with more than a couple of character pixels (noise left out)
        const firstLast = (counts, n) => {
            let f = -1, l = -1;
            for (let i = 0; i < n; i++) if (counts[i] > 2) { if (f < 0) f = i; l = i; }
            return [f, l];
        };
        const [y0, y1] = firstLast(rows, h);
        const [x0, x1] = firstLast(cols, w);
        const box = y0 < 0 || x0 < 0 ? null : { x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1 };
        return { data: out, box: box };
    }

    // Layout: x/y are the share of the free space left of / above the HUD
    // (0 = left/top edge, 1 = right/bottom edge), so the HUD stays on screen
    // at any resolution or size. x/y null = default corner (bottom right).
    const SIZES = { s: 0.8, m: 1, l: 1.3 };
    const unit = (v) => (typeof v === 'number' && isFinite(v) ? Math.max(0, Math.min(1, v)) : null);

    function normalizeLayout(l) {
        l = l || {};
        let x = unit(l.x);
        let y = unit(l.y);
        if (x === null || y === null) { x = null; y = null; }
        return { x: x, y: y, vertical: l.vertical === true, size: SIZES[l.size] ? l.size : 'm', style: l.style === 'classic' ? 'classic' : 'body' };
    }

    // Pixel position of the HUD's top-left corner (null = default corner).
    function toPixels(layout, box, view) {
        const l = normalizeLayout(layout);
        if (l.x === null) return null;
        return {
            left: Math.round(l.x * Math.max(0, view.w - box.w)),
            top: Math.round(l.y * Math.max(0, view.h - box.h)),
        };
    }

    // Layout x/y for a HUD dragged to left/top (clamped to the screen).
    function toFractions(left, top, box, view) {
        const fw = view.w - box.w;
        const fh = view.h - box.h;
        const r = (v) => Math.round(Math.max(0, Math.min(1, v)) * 10000) / 10000;
        return { x: fw > 0 ? r(left / fw) : 0, y: fh > 0 ? r(top / fh) : 0 };
    }

    if (typeof module === 'object' && module.exports) {
        module.exports = { cutout: cutout, bodyView: bodyView, icons: icons, badges: badges, infoLine: infoLine, staminaBar: staminaBar, normalizeLayout: normalizeLayout, toPixels: toPixels, toFractions: toFractions };
        return;
    }

    // ------------------------------------------------------------------
    // Screen
    // ------------------------------------------------------------------

    const UI = window.WastelandUI;
    const h = UI.h;
    const NS = 'http://www.w3.org/2000/svg';
    let root;
    let uid = 0;

    function svg(tag, attrs, children) {
        const el = document.createElementNS(NS, tag);
        Object.keys(attrs || {}).forEach((k) => el.setAttribute(k, attrs[k]));
        (children || []).forEach((c) => el.appendChild(c));
        return el;
    }

    // Glyphs in a 24 x 24 box (filled shapes and strokes).
    const GLYPHS = {
        health: { fill: 'M12 20.5s-7.2-4.4-9.4-8.8A5.1 5.1 0 0 1 12 6.4a5.1 5.1 0 0 1 9.4 5.3c-2.2 4.4-9.4 8.8-9.4 8.8z' },
        armor: { fill: 'M12 2.8l7.6 2.9v5.9c0 5-3.3 8.3-7.6 9.6-4.3-1.3-7.6-4.6-7.6-9.6V5.7z' },
        plates: { fill: 'M7 3h10l2 3v13l-2 2H7l-2-2V6zM8.5 11h7v2h-7z' },
        food: { stroke: 'M7 3v7.5a2 2 0 0 0 4 0V3M9 12.5V21M16.5 21V3c-2.2 1-3.5 4-3.5 7.5 0 1.6.9 2.5 2.2 2.5h1.3' },
        drink: { fill: 'M12 2.8s-6.2 7.3-6.2 11.5a6.2 6.2 0 0 0 12.4 0C18.2 10.1 12 2.8 12 2.8z' },
        temp: { stroke: 'M10 13.6V5a2 2 0 0 1 4 0v8.6a4.2 4.2 0 1 1-4 0zM12 9v7.5', dot: true },
        pee: { fill: 'M12 2.8s-6 7-6 11.2a6 6 0 0 0 12 0C18 9.8 12 2.8 12 2.8z', text: 'P' },
        stamina: { stroke: 'M13 8l-3 4.5 3 3-1.5 6M10 12.5l-4.5 1M13.2 9.5l4 2 2.3-2.2M13 15.5l4.5 1 1 4.5', circle: [14.5, 4.6, 2.3] },
        bread: { fill: 'M3.5 11.2C3.5 7.2 7.4 5 12 5s8.5 2.2 8.5 6.2c0 1.3-.8 2.1-2 2.2V19H5.5v-5.6c-1.2-.1-2-.9-2-2.2z' },
        glass: { stroke: 'M7 3h10c0 5.2-2.2 8.2-5 8.2S7 8.2 7 3zM12 11.2V19M8 21h8' },
        speaker: { fill: 'M3.5 9h4l5.2-4.2v14.4L7.5 15h-4z', stroke: 'M16 8.6a4.8 4.8 0 0 1 0 6.8M18.6 6a8.4 8.4 0 0 1 0 12' },
        poop: { fill: 'M12 3.5c2 .8 2.2 2.8 1.2 3.8 2.8 0 3.8 1.8 3 3 2.8.2 3.8 2.8 2.8 4.5 2 .9 1.4 4.7-1 4.7H6c-2.4 0-3-3.8-1-4.7-1-1.7 0-4.3 2.8-4.5-.8-1.2.2-3 3-3-1-1-.6-3 1.2-3.8z' },
    };

    function glyph(key) {
        const g = GLYPHS[key] || GLYPHS.health;
        const kids = [];
        if (g.fill) kids.push(svg('path', { d: g.fill, class: 'wlh-g-fill' }));
        if (g.stroke) kids.push(svg('path', { d: g.stroke, class: 'wlh-g-stroke' }));
        if (g.dot) kids.push(svg('circle', { cx: '12', cy: '17.2', r: '2.2', class: 'wlh-g-fill' }));
        if (g.circle) kids.push(svg('circle', { cx: String(g.circle[0]), cy: String(g.circle[1]), r: String(g.circle[2]), class: 'wlh-g-fill' }));
        if (g.text) {
            const t = svg('text', { x: '12', y: '17.6', 'text-anchor': 'middle', class: 'wlh-g-text' });
            t.textContent = g.text;
            kids.push(t);
        }
        return svg('svg', { viewBox: '0 0 24 24', class: 'wlh-glyph' }, kids);
    }

    // A round iron badge: a ring that drains around the glyph.
    const RING = 2 * Math.PI * 19;
    function badgeEl(icon) {
        const ring = svg('svg', { viewBox: '0 0 48 48', class: 'wlh-ring' }, [
            svg('circle', { cx: '24', cy: '24', r: '19', class: 'wlh-ring__track' }),
            svg('circle', { cx: '24', cy: '24', r: '19', class: 'wlh-ring__fill',
                'stroke-dasharray': RING.toFixed(2), 'stroke-dashoffset': (RING * (1 - icon.fill / 100)).toFixed(2) }),
        ]);
        const el = h('div', { class: 'wlh-dial wlh-dial--' + icon.key + (icon.hot ? ' is-hot' : '') + ' is-' + icon.level,
            attrs: { title: icon.label + ' ' + icon.fill + '%' } },
            ring, h('div', { class: 'wlh-dial__face' }, glyph(icon.key)));
        return el;
    }

    // The long bar on a riveted plate (health, armour under it).
    function barEl(icon, thin) {
        const fill = h('div', { class: 'wlh-bar__fill' });
        fill.style.width = icon.fill + '%';
        return h('div', { class: 'wlh-plate wlh-plate--' + icon.key + ' is-' + icon.level + (thin ? ' is-thin' : '') },
            h('div', { class: 'wlh-plate__icon' }, glyph(icon.key)),
            h('div', { class: 'wlh-bar' }, fill, h('div', { class: 'wlh-bar__grime' })),
            h('span', { class: 'wlh-plate__value', text: String(icon.fill) }));
    }

    // ------------------------------------------------------------------
    // Body style
    // ------------------------------------------------------------------

    // The figure, in a 100 x 220 box: head, neck, torso, hips, arms, legs.
    const BODY_PARTS = [
        'M50 4.5c6.6 0 11.2 5.6 11.2 13.2S56.6 31.5 50 31.5 38.8 25.3 38.8 17.7 43.4 4.5 50 4.5z',
        'M45 29h10l1 8H44z',
        'M31 39c6-3.2 13-4.6 19-4.6s13 1.4 19 4.6l2.2 30c.2 14-4 28-6.6 40H36.4C33.8 97 29.6 83 29.8 69z',
        'M36.4 107h27.2l2.2 16c-5 4-10.6 5.6-15.8 5.6S39.2 127 34.2 123z',
        'M31 40.5c-6 2-8.6 7.6-9.4 16l-2.4 32c-.4 9-2 18-3.6 27.4l5.6 1.4c2.2-9.2 4.4-18 5.4-27l3.2-26.6z',
        'M69 40.5c6 2 8.6 7.6 9.4 16l2.4 32c.4 9 2 18 3.6 27.4l-5.6 1.4c-2.2-9.2-4.4-18-5.4-27l-3.2-26.6z',
        'M16.2 116.5c-2 4.2-1.4 9.4 1.6 10.4s5.4-3.6 5-9z',
        'M83.8 116.5c2 4.2 1.4 9.4-1.6 10.4s-5.4-3.6-5-9z',
        'M34.4 122c4.6 3.6 10 5 14.4 5.4l-1.6 44-1.6 36.6h-7.6l-1.6-36.6z',
        'M65.6 122c-4.6 3.6-10 5-14.4 5.4l1.6 44 1.6 36.6h7.6l1.6-36.6z',
        'M37.6 207.4h8.8c1.6 2.6 1.4 5-1 6.4h-8.6c-1.2-1.8-.8-4.4.8-6.4z',
        'M62.4 207.4h-8.8c-1.6 2.6-1.4 5 1 6.4h8.6c1.2-1.8.8-4.4-.8-6.4z',
    ];
    // Muscle lines over it (chest, belly, knees).
    const BODY_LINES = 'M38 50c4 4 8 5 12 5s8-1 12-5M50 56v48M41 66h18M41 77h18M42 88h16M38.6 158c2 2 6 2 8 0M53.4 158c2 2 6 2 8 0M26 70c1 6 1 12 0 18M74 70c-1 6-1 12 0 18';

    // The character picture: made from the shots once, kept on this PC.
    const PORTRAIT_KEY = 'wl.hud.portrait';
    let portrait = null;          // { sig, url }
    let making = null;            // sig of the shots being made into a picture
    let asked = null;             // sig a picture was asked for
    try { portrait = JSON.parse(localStorage.getItem(PORTRAIT_KEY) || 'null'); } catch (e) { portrait = null; }

    function loadImage(src) {
        return new Promise((ok, bad) => { const i = new Image(); i.onload = () => ok(i); i.onerror = bad; i.src = src; });
    }

    function makePortrait(shots) {
        making = shots.sig;
        Promise.all([loadImage(shots.with), loadImage(shots.without)]).then(([a, b]) => {
            const scale = Math.min(1, 640 / a.height);
            const w = Math.round(a.width * scale), hh = Math.round(a.height * scale);
            const pixels = (img) => {
                const c = document.createElement('canvas'); c.width = w; c.height = hh;
                const x = c.getContext('2d'); x.drawImage(img, 0, 0, w, hh);
                return x.getImageData(0, 0, w, hh).data;
            };
            const res = cutout(pixels(a), pixels(b), w, hh);
            if (!res.box) throw new Error('no character in the shots');
            const pad = 4, bx = res.box;
            const full = document.createElement('canvas'); full.width = w; full.height = hh;
            full.getContext('2d').putImageData(new ImageData(res.data, w, hh), 0, 0);
            const crop = document.createElement('canvas');
            crop.width = bx.w + pad * 2; crop.height = bx.h + pad * 2;
            crop.getContext('2d').drawImage(full, bx.x - pad, bx.y - pad, crop.width, crop.height, 0, 0, crop.width, crop.height);
            portrait = { sig: shots.sig, url: crop.toDataURL('image/png') };
            try { localStorage.setItem(PORTRAIT_KEY, JSON.stringify(portrait)); } catch (e) { /* storage full: keep it for now */ }
        }).catch((e) => { UI.log && UI.log('warn', 'character picture: ' + (e && e.message || e)); })
            .then(() => { making = null; if (post) post('portraitDone', {}); if (last && root) render(last); });
    }

    // Each update: make the picture from new shots, or ask for one when this
    // look has none yet.
    function portraitFor(p) {
        if (!p) return portrait;
        if (p.shots && making !== p.shots.sig && (!portrait || portrait.sig !== p.shots.sig)) makePortrait(p.shots);
        else if (!p.shots && (!portrait || portrait.sig !== p.sig) && asked !== p.sig && !making) { asked = p.sig; post('portraitNeed', {}); }
        return portrait;   // the last one shows until the new one is ready
    }

    function characterPicture(pic, b) {
        const img = h('img', { class: 'wlh-portrait__img', draggable: false });
        img.src = pic.url;
        const tint = (cls) => { const d = h('div', { class: 'wlh-portrait__tint ' + cls }); d.style.webkitMaskImage = d.style.maskImage = 'url(' + pic.url + ')'; return d; };
        return h('div', { class: 'wlh-portrait' + (b.bleeding ? ' is-bleeding is-bleeding-' + b.bleeding : '') + (b.infected ? ' is-infected' : '')
            + (b.hurt ? ' is-hurt' : '') }, img, tint('wlh-portrait__infection'), tint('wlh-portrait__blood'));
    }

    function bodyFigure(b) {
        const id = 'wlhb' + (++uid);
        const shapes = (cls) => svg('g', { class: cls }, BODY_PARTS.map((d) => svg('path', { d: d })));
        return svg('svg', { viewBox: '0 0 100 220', preserveAspectRatio: 'none', class: 'wlh-body' + (b.bleeding ? ' is-bleeding is-bleeding-' + b.bleeding : '')
            + (b.infected ? ' is-infected' : '') + (b.hurt ? ' is-hurt' : '') }, [
            svg('defs', {}, [svg('linearGradient', { id: id, x1: '0', y1: '0', x2: '1', y2: '1' }, [
                svg('stop', { offset: '0', 'stop-color': '#e2e2dc' }), svg('stop', { offset: '0.55', 'stop-color': '#9a9a93' }),
                svg('stop', { offset: '1', 'stop-color': '#55554f' })])]),
            (() => { const g = shapes('wlh-body__skin'); g.setAttribute('fill', 'url(#' + id + ')'); return g; })(),
            svg('path', { d: BODY_LINES, class: 'wlh-body__lines' }),
            shapes('wlh-body__infection'),
            shapes('wlh-body__blood'),
        ]);
    }

    // An arc ring (open on the left, like a gauge) with a glyph and a value.
    const ARC = 0.8;   // share of the circle the gauge covers
    function arcRing(r, sw, fill, cls) {
        const c = 2 * Math.PI * r;
        const track = svg('circle', { cx: '30', cy: '30', r: String(r), class: 'wlh-arc__track ' + (cls || ''),
            'stroke-width': String(sw), 'stroke-dasharray': (c * ARC).toFixed(2) + ' ' + c.toFixed(2), transform: 'rotate(216 30 30)' });
        const bar = svg('circle', { cx: '30', cy: '30', r: String(r), class: 'wlh-arc__fill ' + (cls || ''),
            'stroke-width': String(sw), 'stroke-dasharray': (c * ARC * fill / 100).toFixed(2) + ' ' + c.toFixed(2), transform: 'rotate(216 30 30)' });
        return [track, bar];
    }

    function bigRing(r) {
        const glyphKey = { health: 'health', stamina: 'stamina', food: 'bread', drink: 'glass' }[r.key];
        return h('div', { class: 'wlh-gauge wlh-gauge--' + r.key + ' is-' + r.level, attrs: { title: r.key + ' ' + r.text } },
            svg('svg', { viewBox: '0 0 60 60', class: 'wlh-gauge__ring' }, arcRing(26, 4.2, r.fill)),
            h('div', { class: 'wlh-gauge__face' }, glyph(glyphKey), h('span', { class: 'wlh-gauge__val', text: r.text })));
    }

    function armorRing(a) {
        return h('div', { class: 'wlh-mini wlh-mini--armor' + (a.worn ? '' : ' is-none') + ' is-' + a.level,
            attrs: { title: a.worn ? 'Armour ' + a.fill + '%, plates ' + a.plates + '%' : 'No armour' } },
            svg('svg', { viewBox: '0 0 60 60', class: 'wlh-gauge__ring' }, arcRing(26, 4.5, a.fill).concat(arcRing(19.5, 3.2, a.plates, 'is-plates'))),
            h('div', { class: 'wlh-mini__face' }, glyph('armor')));
    }

    function voiceRing(v) {
        return h('div', { class: 'wlh-mini wlh-mini--voice' + (v.talking ? ' is-talking' : '') + (v.on ? '' : ' is-none'),
            attrs: { title: v.on ? 'Voice' : 'No voice' } },
            svg('svg', { viewBox: '0 0 60 60', class: 'wlh-gauge__ring' }, arcRing(26, 4.5, v.fill)),
            h('div', { class: 'wlh-mini__face' }, glyph('speaker')));
    }

    function renderBody(shown) {
        const v = bodyView(shown);
        if (!v) return;
        const wrap = h('div', { class: 'wlh-bodyhud' });
        const left = h('div', { class: 'wlh-bodyhud__left' },
            h('div', { class: 'wlh-bodyhud__minis' }, armorRing(v.armor), voiceRing(v.voice)),
            (() => { const pic = portraitFor(shown.portrait); return pic ? characterPicture(pic, v.body) : bodyFigure(v.body); })());
        const right = h('div', { class: 'wlh-bodyhud__arc' });
        v.big.forEach((r, i) => {
            const g = bigRing(r);
            g.style.marginLeft = 'calc(' + [0, 16, 16, 0][i % 4] + 'px * var(--wlh-scale))';
            right.appendChild(g);
        });
        wrap.appendChild(left);
        wrap.appendChild(right);
        root.appendChild(wrap);
        if (v.small.length) {
            const row = h('div', { class: 'wlh-row wlh-bodyhud__small' });
            v.small.forEach((i) => row.appendChild(badgeEl(i)));
            root.appendChild(row);
        }
    }

    // ------------------------------------------------------------------
    // Edit mode (/hud)
    // ------------------------------------------------------------------

    let host;           // the screen element
    let stamina = null; // bottom-middle stamina bar (kept, so it can fade)
    let post;           // api.post(action, payload)
    let toolbar = null;
    let draft = null;   // while editing: { mode, x, y, vertical, size }
    let drag = null;    // { dx, dy } while the mouse holds the HUD
    let last = null;    // last data from the game

    const MODES = [['compact', 'Always'], ['immersive', 'When it matters'], ['off', 'Off']];
    const DEMO = { hunger: 80, thirst: 60, temperature: 37, infection: 0, bleeding: 0, bladder: 40, bowel: 20 };

    function view() { return { w: window.innerWidth, h: window.innerHeight }; }
    function box() { const r = root.getBoundingClientRect(); return { w: r.width, h: r.height }; }

    function place(layout) {
        root.style.setProperty('--wlh-scale', String(SIZES[layout.size] || 1));
        root.classList.toggle('is-vertical', layout.vertical === true);
        const px = toPixels(layout, box(), view());
        if (px) {
            root.style.left = px.left + 'px';
            root.style.top = px.top + 'px';
            root.style.right = 'auto';
            root.style.bottom = 'auto';
        } else {
            root.style.left = '';
            root.style.top = '';
            root.style.right = '';
            root.style.bottom = '';
        }
    }

    function finish(save) {
        if (save && draft) {
            post('saveLayout', { mode: draft.mode, x: draft.x, y: draft.y, vertical: draft.vertical, size: draft.size, style: draft.style });
        } else {
            post('cancelLayout', {});
        }
    }

    function buildToolbar() {
        const group = (label, options, current, pick) => {
            const g = h('div', { class: 'wlh-tb__group' }, h('span', { class: 'wlh-tb__label', text: label }));
            options.forEach((o) => {
                g.appendChild(UI.button(o[1], () => { pick(o[0]); render(last); }, o[0] === current ? 'primary' : undefined));
            });
            return g;
        };
        return h('div', { class: 'wlh-tb' },
            h('div', { class: 'wlh-tb__title', text: 'Drag the HUD anywhere on the screen, then Save' }),
            group('Show', MODES, draft.mode, (v) => { draft.mode = v; }),
            group('Style', [['body', 'Body'], ['classic', 'Classic']], draft.style, (v) => { draft.style = v; }),
            draft.style === 'classic' ? group('Layout', [[false, 'Row'], [true, 'Column']], draft.vertical, (v) => { draft.vertical = v; }) : null,
            group('Size', [['s', 'S'], ['m', 'M'], ['l', 'L']], draft.size, (v) => { draft.size = v; }),
            h('div', { class: 'wlh-tb__group' },
                UI.button('Reset', () => { draft.x = null; draft.y = null; draft.vertical = false; draft.size = 'm'; draft.style = 'body'; render(last); }),
                UI.button('Cancel', () => finish(false)),
                UI.button('Save', () => finish(true), 'primary')));
    }

    function render(data) {
        last = data;
        const editing = data.editing === true;
        if (editing && !draft) draft = Object.assign({ mode: data.mode || 'compact' }, normalizeLayout(data.layout));
        if (!editing) { draft = null; drag = null; }

        root.innerHTML = '';
        root.classList.toggle('is-editing', editing);
        const line = infoLine(editing ? Object.assign({}, data, { mode: 'compact', stats: {} }) : data);
        if (line) {
            const info = h('div', { class: 'wlh-info' });
            if (line.id) info.appendChild(h('span', { class: 'wlh-info__id', text: line.id }));
            if (line.name) info.appendChild(h('span', { class: 'wlh-info__name', text: line.name }));
            if (line.cash) info.appendChild(h('span', { class: 'wlh-info__cash', text: line.cash }));
            root.appendChild(info);
        }
        // While editing every icon shows, so there is always something to move.
        const shown = editing
            ? Object.assign({}, data, {
                mode: 'compact',
                health: typeof data.health === 'number' ? data.health : 100,
                stats: Object.assign({}, DEMO, data.stats || {}, { dead: false }),
            })
            : data;
        const style = (editing ? draft : normalizeLayout(data.layout)).style;
        root.classList.toggle('is-body', style === 'body');
        if (style === 'body') renderBody(editing ? Object.assign({}, shown, { stamina: typeof data.stamina === 'number' ? data.stamina : 100 }) : shown);
        const list = style === 'body' ? [] : icons(shown);
        const BAR = { health: true, armor: true, plates: true };
        const bars = list.filter((i) => BAR[i.key]);
        const dials = list.filter((i) => !BAR[i.key]);
        const panel = h('div', { class: 'wlh-panel' });
        bars.forEach((i) => panel.appendChild(barEl(i, i.key !== 'health')));
        if (dials.length) {
            const row = h('div', { class: 'wlh-row' });
            dials.forEach((i) => row.appendChild(badgeEl(i)));
            panel.appendChild(row);
        }
        if (bars.length || dials.length) root.appendChild(panel);
        const b = badges(shown);
        if (b.length) {
            const tags = h('div', { class: 'wlh-badges' });
            b.forEach((x) => tags.appendChild(h('span', { class: 'wlh-badge wlh-badge--' + x.key, text: x.text })));
            root.appendChild(tags);
        }
        place(editing ? draft : normalizeLayout(data.layout));

        if (toolbar) { toolbar.remove(); toolbar = null; }
        if (editing) { toolbar = buildToolbar(); host.appendChild(toolbar); }

        const bar = style === 'body' ? { visible: false, fill: 100 } : staminaBar(data);
        stamina.classList.toggle('is-visible', bar.visible);
        stamina.classList.toggle('is-low', bar.low === true);
        stamina.firstChild.style.width = bar.fill + '%';
    }

    function onDown(e) {
        if (!draft || e.button !== 0) return;
        const r = root.getBoundingClientRect();
        drag = { dx: e.clientX - r.left, dy: e.clientY - r.top };
        e.preventDefault();
    }
    function onMove(e) {
        if (!drag || !draft) return;
        const f = toFractions(e.clientX - drag.dx, e.clientY - drag.dy, box(), view());
        draft.x = f.x;
        draft.y = f.y;
        place(draft);
    }
    function onUp() { drag = null; }
    function onKey(e) { if (draft && e.key === 'Escape') finish(false); }

    UI.registerScreen('hud', {
        mount: function (el, data, api) {
            host = el;
            post = api.post;
            root = h('div', { class: 'wlh-root' });
            el.appendChild(root);
            stamina = h('div', { class: 'wlh-stamina' }, h('div', { class: 'wlh-stamina__fill' }));
            el.appendChild(stamina);
            el.appendChild(h('style', { text: CSS }));
            root.addEventListener('mousedown', onDown);
            document.addEventListener('mousemove', onMove);
            document.addEventListener('mouseup', onUp);
            document.addEventListener('keydown', onKey);
            render(data);
        },
        update: render,
        unmount: function () {
            document.removeEventListener('mousemove', onMove);
            document.removeEventListener('mouseup', onUp);
            document.removeEventListener('keydown', onKey);
            root = null; host = null; toolbar = null; draft = null; drag = null; stamina = null;
        },
    });

    const CSS = [
        '.wlh-root { position: absolute; right: 1.6vw; bottom: 3vh; display: flex; flex-direction: column; align-items: flex-end; gap: 6px; pointer-events: none;',
        '  --wlh-ok: #8fbf5f; --wlh-low: #d99a2b; --wlh-critical: #d2261c; --wlh-scale: 1; font-family: var(--wl-font-display); }',
        '.wlh-root.is-editing { pointer-events: auto; cursor: move; outline: 2px dashed rgba(127,199,90,0.85); outline-offset: 8px;',
        '  border-radius: 8px; background: rgba(10,14,9,0.35); }',
        // the panel: everything sized from --wlh-scale
        '.wlh-panel { display: flex; flex-direction: column; align-items: stretch; gap: calc(5px * var(--wlh-scale)); }',
        // plate with a bar (health / armour)
        '.wlh-plate { position: relative; display: flex; align-items: center; gap: calc(7px * var(--wlh-scale));',
        '  width: calc(282px * var(--wlh-scale)); height: calc(30px * var(--wlh-scale)); padding: 0 calc(10px * var(--wlh-scale)) 0 calc(4px * var(--wlh-scale));',
        '  border-radius: calc(6px * var(--wlh-scale)); border: 1px solid #4a3d2e;',
        '  background: radial-gradient(3px 3px at 6px 50%, #8a7a62 40%, transparent 60%), radial-gradient(3px 3px at calc(100% - 6px) 50%, #8a7a62 40%, transparent 60%),',
        '    linear-gradient(180deg, #2c2620, #15120f 70%, #1d1914);',
        '  box-shadow: 0 4px 12px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,230,190,0.08), inset 0 -2px 4px rgba(0,0,0,0.5); }',
        '.wlh-plate.is-thin { height: calc(26px * var(--wlh-scale)); width: calc(282px * var(--wlh-scale)); }',
        '.wlh-plate__icon { flex: none; display: grid; place-items: center; width: calc(24px * var(--wlh-scale)); height: calc(24px * var(--wlh-scale));',
        '  border-radius: calc(5px * var(--wlh-scale)); background: linear-gradient(180deg, #3a3129, #1a1612); border: 1px solid #55463a;',
        '  box-shadow: inset 0 1px 0 rgba(255,230,190,0.1); color: #d2261c; }',
        '.is-thin .wlh-plate__icon { width: calc(21px * var(--wlh-scale)); height: calc(21px * var(--wlh-scale)); }',
        '.wlh-plate--armor .wlh-plate__icon { color: #8fa8b8; }',
        '.wlh-plate--plates .wlh-plate__icon { color: #c9a24a; }',
        '.wlh-plate--plates .wlh-bar__fill { background: linear-gradient(180deg, #ecd28c, #b88a2c 55%, #6b4f16); box-shadow: 0 0 8px rgba(201,162,74,0.45); }',
        '.wlh-plate__icon .wlh-glyph { width: 72%; height: 72%; filter: drop-shadow(0 0 3px currentColor); }',
        '.wlh-bar { position: relative; flex: 1; height: 58%; border-radius: 3px; overflow: hidden; background: #0a0807;',
        '  box-shadow: inset 0 2px 4px rgba(0,0,0,0.9), 0 1px 0 rgba(255,230,190,0.06); }',
        '.wlh-bar__fill { position: absolute; left: 0; top: 0; bottom: 0; transition: width 0.4s ease;',
        '  background: linear-gradient(180deg, #e2453a 0%, #a3160f 55%, #5e0805 100%); box-shadow: 0 0 10px rgba(210,38,28,0.55); }',
        '.wlh-plate--armor .wlh-bar__fill { background: linear-gradient(180deg, #b9cfdc, #6c8797 55%, #3b4e5a); box-shadow: 0 0 8px rgba(143,168,184,0.45); }',
        // scratches and dirt over the bar
        '.wlh-bar__grime { position: absolute; inset: 0; pointer-events: none;',
        '  background: repeating-linear-gradient(115deg, rgba(0,0,0,0.22) 0 2px, transparent 2px 9px),',
        '    linear-gradient(180deg, rgba(255,255,255,0.18), rgba(255,255,255,0) 45%); }',
        '.wlh-plate__value { flex: none; min-width: calc(24px * var(--wlh-scale)); text-align: right; font-size: calc(13px * var(--wlh-scale)); font-weight: 700;',
        '  color: #e9dfcc; text-shadow: 0 1px 2px #000; font-variant-numeric: tabular-nums; }',
        '.is-thin .wlh-plate__value { font-size: calc(12px * var(--wlh-scale)); }',
        '.wlh-plate.is-critical { border-color: #7a1a12; box-shadow: 0 0 14px rgba(210,38,28,0.45), 0 4px 12px rgba(0,0,0,0.6); }',
        '.wlh-plate--health.is-critical .wlh-bar__fill { animation: wlhPulse 0.9s ease-in-out infinite; }',
        // round iron dials
        '.wlh-row { display: flex; gap: calc(7px * var(--wlh-scale)); justify-content: flex-start; }',
        '.wlh-root.is-vertical .wlh-row { flex-direction: column; align-items: flex-end; }',
        '.wlh-root.is-vertical .wlh-badges { flex-direction: column; align-items: flex-end; }',
        '.wlh-dial { position: relative; width: calc(46px * var(--wlh-scale)); height: calc(46px * var(--wlh-scale)); border-radius: 50%; --c: var(--wlh-ok);',
        '  background: radial-gradient(circle at 35% 30%, #4a4036, #1d1915 62%, #0f0d0b);',
        '  border: 2px solid #4f4133; box-shadow: 0 4px 10px rgba(0,0,0,0.65), inset 0 1px 1px rgba(255,230,190,0.15), inset 0 -3px 6px rgba(0,0,0,0.6); }',
        // four rivets around the rim
        '.wlh-dial::before { content: ""; position: absolute; inset: -1px; border-radius: 50%; pointer-events: none;',
        '  background: radial-gradient(circle at 50% 4%, #a08c70 0 1.6px, transparent 2.2px), radial-gradient(circle at 50% 96%, #a08c70 0 1.6px, transparent 2.2px),',
        '    radial-gradient(circle at 4% 50%, #a08c70 0 1.6px, transparent 2.2px), radial-gradient(circle at 96% 50%, #a08c70 0 1.6px, transparent 2.2px); }',
        '.wlh-ring { position: absolute; inset: 0; width: 100%; height: 100%; transform: rotate(-90deg); }',
        '.wlh-ring__track { fill: none; stroke: rgba(0,0,0,0.55); stroke-width: 4; }',
        '.wlh-ring__fill { fill: none; stroke: var(--c); stroke-width: 4; stroke-linecap: round; filter: drop-shadow(0 0 2px var(--c));',
        '  transition: stroke-dashoffset 0.5s ease, stroke 0.3s; }',
        '.wlh-dial__face { position: absolute; inset: 22%; display: grid; place-items: center; border-radius: 50%; color: var(--c);',
        '  background: radial-gradient(circle at 40% 35%, #2a241e, #0e0c0a); box-shadow: inset 0 1px 3px rgba(0,0,0,0.8); }',
        '.wlh-glyph { width: 78%; height: 78%; overflow: visible; filter: drop-shadow(0 0 3px var(--c, currentColor)); }',
        '.wlh-g-fill { fill: currentColor; }',
        '.wlh-g-stroke { fill: none; stroke: currentColor; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }',
        '.wlh-g-text { fill: #120f0c; font-size: 8px; font-weight: 800; font-family: Arial, sans-serif; }',
        // colours per stat
        '.wlh-dial--food { --c: #e0912f; } .wlh-dial--drink { --c: #3fb5c9; } .wlh-dial--temp { --c: #cfe3ea; } .wlh-dial--temp.is-hot { --c: #ff7a3c; }',
        '.wlh-dial--pee { --c: #d8c63a; } .wlh-dial--poop { --c: #a0703e; }',
        '.wlh-dial.is-low { --c: var(--wlh-low); border-color: #6b4f22; }',
        '.wlh-dial.is-critical { --c: var(--wlh-critical); border-color: #7a1a12; animation: wlhGlow 1s ease-in-out infinite; }',
        '@keyframes wlhPulse { 50% { opacity: 0.55; } }',
        '@keyframes wlhGlow { 50% { box-shadow: 0 0 16px rgba(210,38,28,0.75), 0 4px 10px rgba(0,0,0,0.65), inset 0 -3px 6px rgba(0,0,0,0.6); } }',
        // bleeding / infection tags
        '.wlh-badges { display: flex; gap: 6px; }',
        '.wlh-badge { font-size: 11px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; padding: 3px 9px; border-radius: 4px;',
        '  background: linear-gradient(180deg, #2a231d, #120f0c); text-shadow: 0 1px 2px #000; box-shadow: 0 3px 8px rgba(0,0,0,0.5); }',
        '.wlh-badge--bleeding { color: #ff6b5e; border: 1px solid #8a1d14; }',
        '.wlh-badge--bleeding::before { content: "\\25CF  "; color: #d2261c; }',
        '.wlh-badge--infection { color: #a6e06a; border: 1px solid #4f7a2a; }',
        '.wlh-badge--infection::before { content: "\\2623  "; }',
        '.wlh-info { display: flex; gap: 10px; align-items: baseline; font-size: calc(17px * var(--wlh-scale)); color: #efe6d4; font-weight: 600;',
        '  text-shadow: 0 1px 2px #000, 0 0 6px rgba(0,0,0,0.6); white-space: nowrap; letter-spacing: 0.03em; }',
        '.wlh-info__id { color: #d99a2b; font-weight: 700; }',
        '.wlh-info__cash { color: #9be27a; font-weight: 700; font-variant-numeric: tabular-nums; }',
        '.wlh-stamina { position: absolute; left: 50%; bottom: 2.2vh; width: 200px; height: 6px; transform: translateX(-50%);',
        '  background: #0a0807; border: 1px solid #4a3d2e; border-radius: 3px; overflow: hidden; box-shadow: 0 2px 6px rgba(0,0,0,0.6);',
        '  opacity: 0; transition: opacity 0.6s ease 0.8s; pointer-events: none; }',
        '.wlh-stamina.is-visible { opacity: 1; transition: opacity 0.15s ease; }',
        '.wlh-stamina__fill { height: 100%; width: 100%; background: linear-gradient(180deg, #efe6d2, #a89c84); box-shadow: 0 0 6px rgba(239,230,210,0.4); transition: width 0.15s linear; }',
        '.wlh-stamina.is-low .wlh-stamina__fill { background: linear-gradient(180deg, #f0b44a, #b06e14); }',
        // ---- body style
        '.wlh-bodyhud { display: flex; align-items: center; gap: calc(4px * var(--wlh-scale)); }',
        '.wlh-bodyhud__left { position: relative; width: calc(132px * var(--wlh-scale)); height: calc(262px * var(--wlh-scale)); }',
        '.wlh-bodyhud__minis { position: absolute; left: 0; top: 0; display: flex; gap: calc(5px * var(--wlh-scale)); z-index: 1; }',
        '.wlh-body { position: absolute; left: calc(10px * var(--wlh-scale)); top: calc(26px * var(--wlh-scale)); width: calc(118px * var(--wlh-scale));',
        '  height: calc(236px * var(--wlh-scale)); filter: drop-shadow(0 3px 6px rgba(0,0,0,0.8)); overflow: visible; }',
        '.wlh-body__skin path { stroke: rgba(30,30,28,0.9); stroke-width: 0.8; }',
        '.wlh-body__lines { fill: none; stroke: rgba(40,40,36,0.55); stroke-width: 0.9; stroke-linecap: round; }',
        '.wlh-body__blood path, .wlh-body__infection path { opacity: 0; transition: opacity 0.4s; }',
        '.wlh-body__blood path { fill: #c8150c; } .wlh-body__infection path { fill: #6fbf2c; }',
        '.wlh-body.is-hurt .wlh-body__blood path { opacity: 0.22; }',
        '.wlh-body.is-bleeding .wlh-body__blood path { animation: wlhBleed 1.4s ease-in-out infinite; }',
        '.wlh-body.is-bleeding-3 .wlh-body__blood path { animation-duration: 0.7s; }',
        '.wlh-body.is-infected .wlh-body__infection path { opacity: 0.28; }',
        '@keyframes wlhBleed { 0%, 100% { opacity: 0.15; } 50% { opacity: 0.6; } }',
        '.wlh-portrait { position: absolute; left: calc(6px * var(--wlh-scale)); top: calc(30px * var(--wlh-scale)); width: calc(124px * var(--wlh-scale));',
        '  height: calc(230px * var(--wlh-scale)); }',
        '.wlh-portrait__img, .wlh-portrait__tint { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: contain; object-position: center bottom; }',
        '.wlh-portrait__img { filter: drop-shadow(0 3px 6px rgba(0,0,0,0.85)); }',
        '.wlh-portrait__tint { opacity: 0; transition: opacity 0.4s; -webkit-mask-size: contain; mask-size: contain;',
        '  -webkit-mask-repeat: no-repeat; mask-repeat: no-repeat; -webkit-mask-position: center bottom; mask-position: center bottom; }',
        '.wlh-portrait__blood { background: #c8150c; mix-blend-mode: multiply; } .wlh-portrait__infection { background: #6fbf2c; mix-blend-mode: multiply; }',
        '.wlh-portrait.is-hurt .wlh-portrait__blood { opacity: 0.35; }',
        '.wlh-portrait.is-bleeding .wlh-portrait__blood { animation: wlhBleed2 1.4s ease-in-out infinite; }',
        '.wlh-portrait.is-bleeding-3 .wlh-portrait__blood { animation-duration: 0.7s; }',
        '.wlh-portrait.is-infected .wlh-portrait__infection { opacity: 0.4; }',
        '@keyframes wlhBleed2 { 0%, 100% { opacity: 0.25; } 50% { opacity: 0.8; } }',
        '.wlh-bodyhud__arc { display: flex; flex-direction: column; gap: calc(6px * var(--wlh-scale)); }',
        '.wlh-gauge, .wlh-mini { position: relative; display: grid; place-items: center; --c1: #8fe3ff; --c2: #2c7be5; }',
        '.wlh-gauge { width: calc(58px * var(--wlh-scale)); height: calc(58px * var(--wlh-scale)); }',
        '.wlh-mini { width: calc(40px * var(--wlh-scale)); height: calc(40px * var(--wlh-scale)); }',
        '.wlh-gauge__ring { position: absolute; inset: 0; width: 100%; height: 100%; overflow: visible; }',
        '.wlh-arc__track { fill: none; stroke: rgba(0,0,0,0.55); stroke-linecap: round; }',
        '.wlh-arc__fill { fill: none; stroke: var(--c2); stroke-linecap: round; filter: drop-shadow(0 0 2px var(--c1)); transition: stroke-dasharray 0.5s ease; }',
        '.wlh-gauge .wlh-arc__fill, .wlh-mini .wlh-arc__fill { stroke: var(--c1); }',
        '.wlh-gauge::before, .wlh-mini::before { content: ""; position: absolute; inset: 14%; border-radius: 50%;',
        '  background: radial-gradient(circle at 40% 35%, rgba(40,40,38,0.85), rgba(8,8,8,0.9)); box-shadow: inset 0 1px 3px rgba(0,0,0,0.8); }',
        '.wlh-gauge__face, .wlh-mini__face { position: relative; display: flex; flex-direction: column; align-items: center; justify-content: center;',
        '  color: #f3f3ee; line-height: 1; }',
        '.wlh-gauge__face .wlh-glyph { width: calc(20px * var(--wlh-scale)); height: calc(20px * var(--wlh-scale)); filter: drop-shadow(0 1px 2px #000); }',
        '.wlh-mini__face .wlh-glyph { width: calc(17px * var(--wlh-scale)); height: calc(17px * var(--wlh-scale)); filter: drop-shadow(0 1px 2px #000); }',
        '.wlh-gauge__val { margin-top: calc(1px * var(--wlh-scale)); font-size: calc(11px * var(--wlh-scale)); font-weight: 700; color: #f3f3ee;',
        '  text-shadow: 0 1px 2px #000; font-family: Arial, sans-serif; }',
        '.wlh-gauge.is-low { --c1: #f2b24a; } .wlh-gauge.is-critical { --c1: #ff4a3d; animation: wlhPulse 0.9s ease-in-out infinite; }',
        '.wlh-mini--armor { --c1: #a9c7da; } .wlh-mini--armor .wlh-arc__fill.is-plates { stroke: #e0b84f; filter: drop-shadow(0 0 2px #e0b84f); }',
        '.wlh-mini--armor .wlh-mini__face { color: #a9c7da; }',
        '.wlh-mini.is-none { opacity: 0.45; }',
        '.wlh-mini--voice { --c1: #e8e8e2; } .wlh-mini--voice.is-talking { --c1: #7fe36a; }',
        '.wlh-mini--voice.is-talking .wlh-mini__face { color: #7fe36a; } .wlh-mini--voice.is-talking::before { box-shadow: 0 0 10px rgba(127,227,106,0.6), inset 0 1px 3px rgba(0,0,0,0.8); }',
        '.wlh-bodyhud__small { justify-content: flex-end; }',
        '.wlh-bodyhud__small .wlh-dial { width: calc(36px * var(--wlh-scale)); height: calc(36px * var(--wlh-scale)); }',
        '.wlh-tb { position: absolute; top: 3vh; left: 50%; transform: translateX(-50%); display: flex; flex-wrap: wrap; justify-content: center;',
        '  gap: 10px 16px; max-width: 92vw; padding: 10px 14px; background: var(--wl-bg); border: 1px solid var(--wl-border);',
        '  border-radius: var(--wl-radius); box-shadow: 0 10px 30px rgba(0,0,0,0.5); pointer-events: auto; }',
        '.wlh-tb__title { width: 100%; text-align: center; font-size: 13px; color: var(--wl-text-dim); }',
        '.wlh-tb__group { display: flex; align-items: center; gap: 6px; }',
        '.wlh-tb__label { font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--wl-text-dim); margin-right: 2px; }',
    ].join('\n');
})();
