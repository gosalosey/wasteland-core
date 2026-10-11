// wasteland_appearance :: html/creator.js
// Character creator screen (runs inside wasteland_ui). Every change is
// previewed on the ped by the client script; "Done" submits the look to the
// server, which validates and stores it.

(function () {
    'use strict';

    // ------------------------------------------------------------------
    // Pure helpers (unit-tested with Node)
    // ------------------------------------------------------------------

    function clone(v) { return JSON.parse(JSON.stringify(v)); }

    function findById(list, id) {
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
        return null;
    }

    // Set a clothing component or prop field, adding the entry if missing.
    function setPart(appearance, kind, id, field, value) {
        const list = appearance[kind];
        let entry = findById(list, id);
        if (!entry) {
            entry = { id: id, drawable: kind === 'props' ? -1 : 0, texture: 0 };
            list.push(entry);
        }
        entry[field] = value;
        if (field === 'drawable') entry.texture = 0; // textures differ per drawable
        return appearance;
    }

    // Switch male/female: keep heritage, face and eyes; take hair, clothing
    // and props from the other model's defaults (their indices differ).
    function switchModel(appearance, defaults, model) {
        const base = clone(model === 'mp_f_freemode_01' ? defaults.female : defaults.male);
        base.heritage = clone(appearance.heritage);
        base.features = clone(appearance.features);
        base.eyeColor = appearance.eyeColor;
        base.overlays = clone(appearance.overlays);
        return base;
    }

    // Keep values inside the ranges the game reported.
    function clampToRanges(appearance, ranges) {
        const a = clone(appearance);
        const lim = (v, lo, hi) => Math.min(Math.max(v, lo), hi);
        if (ranges.hair !== undefined) a.hair.style = lim(a.hair.style, 0, ranges.hair);
        (ranges.overlays || []).forEach((max, i) => {
            const o = a.overlays[i];
            if (o && o.style !== 255) o.style = lim(o.style, 0, max);
        });
        a.components.forEach((c) => {
            const r = ranges.components && ranges.components[String(c.id)];
            if (r) { c.drawable = lim(c.drawable, 0, r.drawables); c.texture = lim(c.texture, 0, r.textures); }
        });
        a.props.forEach((p) => {
            const r = ranges.props && ranges.props[String(p.id)];
            if (r) { p.drawable = lim(p.drawable, -1, r.drawables); p.texture = lim(p.texture, 0, r.textures); }
        });
        return a;
    }

    if (typeof module === 'object' && module.exports) {
        module.exports = { setPart: setPart, switchModel: switchModel, clampToRanges: clampToRanges, findById: findById };
        return;
    }

    // ------------------------------------------------------------------
    // Screen
    // ------------------------------------------------------------------

    const UI = window.WastelandUI;
    const h = UI.h;
    let s; // screen state

    const TABS = [
        { id: 'body', label: 'Body', camera: 'body' },
        { id: 'face', label: 'Face', camera: 'face' },
        { id: 'hair', label: 'Hair', camera: 'face' },
        { id: 'details', label: 'Details', camera: 'face' },
        { id: 'clothing', label: 'Clothing', camera: 'body' },
    ];

    const pct = (v) => Math.round(v * 100) + '%';

    function preview() {
        clearTimeout(s.previewTimer);
        s.previewTimer = setTimeout(() => s.api.post('preview', s.a), 60);
    }

    function change(fn) {
        fn(s.a);
        preview();
    }

    // A picker whose range follows the game data (updated in place).
    function rangedPicker(key, opts) {
        const p = UI.picker(opts);
        s.ranged[key] = p;
        return p;
    }

    function section(title) { return h('div', { class: 'wl-section-title', text: title }); }

    function renderBody(box) {
        box.appendChild(section('Body'));
        box.appendChild(h('div', { class: 'wla-row' },
            UI.button('Male', () => { s.a = switchModel(s.a, s.defaults, 'mp_m_freemode_01'); preview(); render(); },
                s.a.model === 'mp_m_freemode_01' ? 'primary' : undefined),
            UI.button('Female', () => { s.a = switchModel(s.a, s.defaults, 'mp_f_freemode_01'); preview(); render(); },
                s.a.model === 'mp_f_freemode_01' ? 'primary' : undefined)));
        box.appendChild(section('Heritage'));
        box.appendChild(UI.picker({ label: 'Mother', min: 0, max: 45, value: s.a.heritage.mother,
            format: (v) => String(v + 1), onChange: (v) => change((a) => { a.heritage.mother = v; }) }));
        box.appendChild(UI.picker({ label: 'Father', min: 0, max: 45, value: s.a.heritage.father,
            format: (v) => String(v + 1), onChange: (v) => change((a) => { a.heritage.father = v; }) }));
        box.appendChild(UI.slider({ label: 'Resemblance (mother - father)', min: 0, max: 1, step: 0.01, value: s.a.heritage.shapeMix,
            format: pct, onInput: (v) => change((a) => { a.heritage.shapeMix = v; }) }));
        box.appendChild(UI.slider({ label: 'Skin tone (mother - father)', min: 0, max: 1, step: 0.01, value: s.a.heritage.skinMix,
            format: pct, onInput: (v) => change((a) => { a.heritage.skinMix = v; }) }));
        box.appendChild(UI.picker({ label: 'Eye colour', min: 0, max: 31, value: s.a.eyeColor,
            format: (v) => String(v + 1), onChange: (v) => change((a) => { a.eyeColor = v; }) }));
    }

    function renderFace(box) {
        box.appendChild(section('Face shape'));
        s.labels.features.forEach((label, i) => {
            box.appendChild(UI.slider({ label: label, min: -1, max: 1, step: 0.05, value: s.a.features[i],
                format: (v) => v.toFixed(2), onInput: (v) => change((a) => { a.features[i] = v; }) }));
        });
    }

    function overlayControls(box, index) {
        const def = s.labels.overlays[index];
        const o = s.a.overlays[index];
        // style 255 = none; shown as 0, real styles as 1..n
        box.appendChild(rangedPicker('overlay' + index, {
            label: def.label, min: 0, max: (s.ranges.overlays[index] || 0) + 1,
            value: o.style === 255 ? 0 : o.style + 1,
            format: (v) => (v === 0 ? 'None' : String(v)),
            onChange: (v) => change((a) => { a.overlays[index].style = v === 0 ? 255 : v - 1; }),
        }));
        box.appendChild(UI.slider({ label: def.label + ' opacity', min: 0, max: 1, step: 0.05, value: o.opacity,
            format: pct, onInput: (v) => change((a) => { a.overlays[index].opacity = v; }) }));
        if (def.colorable) {
            box.appendChild(UI.picker({ label: def.label + ' colour', min: 0, max: 63, value: o.color,
                format: (v) => String(v + 1), onChange: (v) => change((a) => { a.overlays[index].color = v; }) }));
        }
    }

    function renderHair(box) {
        box.appendChild(section('Hair'));
        box.appendChild(rangedPicker('hair', { label: 'Style', min: 0, max: s.ranges.hair, value: s.a.hair.style,
            format: (v) => String(v + 1), onChange: (v) => change((a) => { a.hair.style = v; }) }));
        box.appendChild(UI.picker({ label: 'Colour', min: 0, max: 63, value: s.a.hair.color,
            format: (v) => String(v + 1), onChange: (v) => change((a) => { a.hair.color = v; }) }));
        box.appendChild(UI.picker({ label: 'Highlights', min: 0, max: 63, value: s.a.hair.highlight,
            format: (v) => String(v + 1), onChange: (v) => change((a) => { a.hair.highlight = v; }) }));
        box.appendChild(section('Eyebrows'));
        overlayControls(box, 2);
        box.appendChild(section('Facial hair'));
        overlayControls(box, 1);
    }

    function renderDetails(box) {
        [0, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].forEach((i) => {
            box.appendChild(section(s.labels.overlays[i].label));
            overlayControls(box, i);
        });
    }

    function renderClothing(box) {
        box.appendChild(h('p', { class: 'wl-hint', text: 'Your starting clothes. Later you find and wear clothing as items.' }));
        s.labels.components.forEach((c) => {
            const entry = findById(s.a.components, c.id) || { drawable: 0, texture: 0 };
            const r = s.ranges.components[String(c.id)] || { drawables: 0, textures: 0 };
            box.appendChild(section(c.label));
            box.appendChild(rangedPicker('comp' + c.id, { label: 'Style', min: 0, max: r.drawables, value: entry.drawable,
                format: (v) => String(v + 1), onChange: (v) => {
                    change((a) => setPart(a, 'components', c.id, 'drawable', v));
                    s.ranged['compTex' + c.id].set(0);
                } }));
            box.appendChild(rangedPicker('compTex' + c.id, { label: 'Variant', min: 0, max: r.textures, value: entry.texture,
                format: (v) => String(v + 1), onChange: (v) => change((a) => setPart(a, 'components', c.id, 'texture', v)) }));
        });
        s.labels.props.forEach((p) => {
            const entry = findById(s.a.props, p.id) || { drawable: -1, texture: 0 };
            const r = s.ranges.props[String(p.id)] || { drawables: -1, textures: 0 };
            box.appendChild(section(p.label));
            box.appendChild(rangedPicker('prop' + p.id, { label: 'Style', min: -1, max: r.drawables, value: entry.drawable,
                format: (v) => (v < 0 ? 'None' : String(v + 1)), onChange: (v) => {
                    change((a) => setPart(a, 'props', p.id, 'drawable', v));
                    s.ranged['propTex' + p.id].set(0);
                } }));
            box.appendChild(rangedPicker('propTex' + p.id, { label: 'Variant', min: 0, max: r.textures, value: entry.texture,
                format: (v) => String(v + 1), onChange: (v) => change((a) => setPart(a, 'props', p.id, 'texture', v)) }));
        });
    }

    const RENDER = { body: renderBody, face: renderFace, hair: renderHair, details: renderDetails, clothing: renderClothing };

    function render() {
        s.ranged = {};
        s.content.innerHTML = '';
        RENDER[s.tab](s.content);
    }

    function selectTab(id) {
        s.tab = id;
        const tab = TABS.filter((t) => t.id === id)[0];
        s.api.post('camera', { mode: tab.camera });
        render();
    }

    function applyRanges(r) {
        s.ranges = r;
        const set = (key, lo, hi) => { if (s.ranges && s.ranged[key]) s.ranged[key].setRange(lo, hi); };
        set('hair', 0, r.hair);
        (r.overlays || []).forEach((max, i) => set('overlay' + i, 0, max + 1));
        Object.keys(r.components || {}).forEach((id) => {
            set('comp' + id, 0, r.components[id].drawables);
            set('compTex' + id, 0, r.components[id].textures);
        });
        Object.keys(r.props || {}).forEach((id) => {
            set('prop' + id, -1, r.props[id].drawables);
            set('propTex' + id, 0, r.props[id].textures);
        });
    }

    function setMessage(text, kind) {
        s.message.textContent = text || '';
        s.message.className = 'wl-message' + (kind ? ' is-' + kind : '');
    }

    UI.registerScreen('appearanceCreator', {
        mount: function (el, data, api) {
            s = {
                api: api, a: clone(data.appearance), defaults: data.defaults, ranges: data.ranges,
                labels: data.labels, tab: 'body', ranged: {}, previewTimer: null,
            };
            s.content = h('div', { class: 'wla-content' });
            s.message = h('div', { class: 'wl-message' });
            const tabs = UI.tabs(TABS, selectTab);
            const done = UI.button('Done', () => {
                setMessage('Saving...');
                clearTimeout(s.previewTimer);
                api.post('save', s.a);
            }, 'primary');
            const footer = h('div', { class: 'wla-footer' },
                UI.button('↺', () => api.post('rotate', { degrees: -30 })),
                UI.button('↻', () => api.post('rotate', { degrees: 30 })),
                h('span', { class: 'wla-spacer' }),
                data.cancellable ? UI.button('Cancel', () => api.post('cancel')) : null,
                done);
            el.appendChild(h('div', { class: 'wl-panel wla-panel' },
                h('h1', { class: 'wl-title', text: data.reason === 'new' ? 'New survivor' : 'Appearance' }),
                h('p', { class: 'wl-subtitle', text: 'Your face and body are permanent once you are done.' }),
                tabs, s.content, s.message, footer));
            el.appendChild(h('style', { text: CSS }));
            tabs.select('body');
        },
        update: function (data) {
            if (data.ranges) {
                applyRanges(data.ranges);
                s.a = clampToRanges(s.a, data.ranges);
            }
            if (data.error) setMessage(data.error, 'error');
        },
        unmount: function () { clearTimeout(s.previewTimer); s = null; },
    });

    const CSS = [
        '.wla-panel { position: absolute; top: 4vh; right: 3vw; bottom: 4vh; width: 400px; display: flex; flex-direction: column; }',
        '.wla-content { flex: 1; overflow-y: auto; padding-right: 6px; }',
        '.wla-row { display: flex; gap: 8px; }',
        '.wla-row .wl-btn { flex: 1; }',
        '.wla-footer { display: flex; gap: 8px; align-items: center; padding-top: 12px; border-top: 1px solid var(--wl-border); }',
        '.wla-spacer { flex: 1; }',
        '.wla-content::-webkit-scrollbar { width: 6px; }',
        '.wla-content::-webkit-scrollbar-thumb { background: var(--wl-border); border-radius: 3px; }',
    ].join('\n');
})();
