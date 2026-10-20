// wasteland_ui :: html/shell.js
// NUI shell: routes messages from client/main.lua to screens, loads screen
// scripts from module resources, and offers small DOM helpers that follow
// the design system (style.css). The routing core (createShell) has no DOM
// dependency so it can be unit-tested with Node (tests/js).

(function (global) {
    'use strict';

    // ------------------------------------------------------------------
    // Routing core
    // ------------------------------------------------------------------

    // env: { loadScript(url) -> Promise, createContainer(name) -> el,
    //        removeContainer(el), post(endpoint, body) -> Promise, log(level, msg) }
    function createShell(env) {
        const definitions = {}; // name -> { mount, update?, unmount? }
        const screens = {};     // name -> { def, el }
        const pending = {};     // name -> { data, updates[] } while its script loads
        const loading = {};     // url -> Promise

        function api(name) {
            return {
                post: (action, payload) => env.post('action', { screen: name, action: action, payload: payload }),
                log: (message) => env.log('info', name + ': ' + message),
            };
        }

        function safe(name, what, fn) {
            try { fn(); } catch (e) { env.log('error', name + ' ' + what + ' failed: ' + (e && e.message || e)); }
        }

        function mount(name, data) {
            const def = definitions[name];
            const el = env.createContainer(name);
            screens[name] = { def: def, el: el };
            safe(name, 'mount', () => def.mount(el, data, api(name)));
        }

        function update(name, data) {
            const s = screens[name];
            if (s && typeof s.def.update === 'function') safe(name, 'update', () => s.def.update(data));
        }

        function unmount(name) {
            const s = screens[name];
            if (!s) return;
            delete screens[name];
            if (typeof s.def.unmount === 'function') safe(name, 'unmount', () => s.def.unmount());
            env.removeContainer(s.el);
        }

        // A screen that cannot be shown is reported back, so the game does
        // not think it is open (and keep the mouse/keyboard on it).
        function failed(name, why) {
            env.log('error', why);
            env.post('failed', { screen: name });
        }

        // Right after joining, a resource's files can briefly be unavailable:
        // try a script a few times before giving up.
        const RETRIES = env.retries === undefined ? 4 : env.retries;
        const wait = env.wait || ((ms) => new Promise((r) => setTimeout(r, ms)));
        function loadWithRetry(url, attempt) {
            return env.loadScript(url).catch((err) => {
                if (attempt >= RETRIES) throw err;
                return wait(1000 * (attempt + 1)).then(() => loadWithRetry(url, attempt + 1));
            });
        }

        function open(msg) {
            const name = msg.screen;
            unmount(name);
            if (definitions[name]) { mount(name, msg.data); return Promise.resolve(); }
            const p = { data: msg.data, updates: [] };
            pending[name] = p;
            if (!loading[msg.script]) loading[msg.script] = loadWithRetry(msg.script, 0);
            return loading[msg.script].then(() => {
                if (pending[name] !== p) return; // closed or opened again while loading
                delete pending[name];
                if (!definitions[name]) return failed(name, 'screen script ' + msg.script + ' did not register screen "' + name + '"');
                mount(name, p.data);
                p.updates.forEach((d) => update(name, d));
            }, (err) => {
                delete loading[msg.script]; // the next open tries again
                if (pending[name] !== p) return;
                delete pending[name];
                failed(name, 'could not load ' + msg.script + ': ' + (err && err.message || err));
            });
        }

        function handle(msg) {
            if (!msg || msg.wl !== true || typeof msg.screen !== 'string') return undefined;
            if (msg.type === 'open') return open(msg);
            if (msg.type === 'update') {
                if (pending[msg.screen]) pending[msg.screen].updates.push(msg.data);
                else update(msg.screen, msg.data);
            } else if (msg.type === 'close') {
                delete pending[msg.screen];
                unmount(msg.screen);
            }
            return undefined;
        }

        function registerScreen(name, def) {
            if (typeof name !== 'string' || !def || typeof def.mount !== 'function') {
                throw new Error('registerScreen(name, { mount, update?, unmount? })');
            }
            definitions[name] = def;
        }

        return { handle: handle, registerScreen: registerScreen, isOpen: (n) => !!screens[n] };
    }

    // ------------------------------------------------------------------
    // DOM helpers (design system building blocks)
    // ------------------------------------------------------------------

    function createHelpers(doc) {
        // h('div', { class: 'x', text: 'hi', onclick: fn, attrs: { type: 'text' } }, child, ...)
        function h(tag, props) {
            const el = doc.createElement(tag);
            const p = props || {};
            Object.keys(p).forEach((k) => {
                const v = p[k];
                if (k === 'class') el.className = v;
                else if (k === 'text') el.textContent = v;
                else if (k === 'attrs') Object.keys(v).forEach((a) => el.setAttribute(a, v[a]));
                else if (k.indexOf('on') === 0 && typeof v === 'function') el.addEventListener(k.slice(2), v);
                else el[k] = v;
            });
            for (let i = 2; i < arguments.length; i++) {
                const c = arguments[i];
                if (c === null || c === undefined || c === false) continue;
                el.appendChild(typeof c === 'string' ? doc.createTextNode(c) : c);
            }
            return el;
        }

        function button(label, onClick, variant) {
            return h('button', { class: 'wl-btn' + (variant ? ' wl-btn--' + variant : ''), text: label, onclick: onClick });
        }

        // Numeric slider. opts: { label, min, max, step, value, format(v), onInput(v) }
        function slider(opts) {
            const out = h('span', { class: 'wl-field__value' });
            const input = h('input', { class: 'wl-slider', attrs: { type: 'range', min: opts.min, max: opts.max, step: opts.step || 1 } });
            input.value = opts.value;
            const fmt = opts.format || ((v) => String(v));
            const show = () => { out.textContent = fmt(Number(input.value)); };
            input.addEventListener('input', () => { show(); if (opts.onInput) opts.onInput(Number(input.value)); });
            show();
            const el = h('label', { class: 'wl-field' }, h('span', { class: 'wl-field__label', text: opts.label }), out, input);
            el.set = (v) => { input.value = v; show(); };
            el.setMax = (m) => { input.max = m; if (Number(input.value) > m) { input.value = m; show(); } };
            return el;
        }

        // Index picker with arrows. opts: { label, min, max, value, format(v), onChange(v) }
        function picker(opts) {
            let value = opts.value;
            let min = opts.min;
            let max = opts.max;
            const fmt = opts.format || ((v) => String(v));
            const display = h('span', { class: 'wl-picker__value' });
            const show = () => { display.textContent = fmt(value) + ' / ' + fmt(max); };
            const step = (d) => {
                if (max < min) return;
                value = value + d;
                if (value > max) value = min;
                if (value < min) value = max;
                show();
                if (opts.onChange) opts.onChange(value);
            };
            const el = h('div', { class: 'wl-field wl-picker' },
                h('span', { class: 'wl-field__label', text: opts.label }),
                h('div', { class: 'wl-picker__row' },
                    h('button', { class: 'wl-btn wl-btn--icon', text: '‹', onclick: () => step(-1) }),
                    display,
                    h('button', { class: 'wl-btn wl-btn--icon', text: '›', onclick: () => step(1) })));
            show();
            el.set = (v) => { value = v; show(); };
            el.setRange = (a, b) => { min = a; max = b; if (value > max) value = max; if (value < min) value = min; show(); };
            el.get = () => value;
            return el;
        }

        // Tabs. items: [{ id, label }]; onSelect(id). Returns element with select(id).
        function tabs(items, onSelect) {
            const buttons = {};
            const el = h('div', { class: 'wl-tabs', attrs: { role: 'tablist' } });
            const select = (id) => {
                Object.keys(buttons).forEach((k) => buttons[k].classList.toggle('is-active', k === id));
                onSelect(id);
            };
            items.forEach((it) => {
                buttons[it.id] = h('button', { class: 'wl-tab', text: it.label, onclick: () => select(it.id) });
                el.appendChild(buttons[it.id]);
            });
            el.select = select;
            return el;
        }

        return { h: h, button: button, slider: slider, picker: picker, tabs: tabs };
    }

    // ------------------------------------------------------------------
    // Exports: Node (tests) or browser bootstrap (NUI)
    // ------------------------------------------------------------------

    if (typeof module === 'object' && module.exports) {
        module.exports = { createShell: createShell, createHelpers: createHelpers };
        return;
    }

    const doc = global.document;
    const resource = typeof global.GetParentResourceName === 'function' ? global.GetParentResourceName() : 'wasteland_ui';

    function post(endpoint, body) {
        return global.fetch('https://' + resource + '/' + endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body || {}),
        }).then((r) => r.json()).catch(() => ({ ok: false }));
    }

    function log(level, message) {
        if (global.console) global.console[level === 'error' ? 'error' : 'log'](message);
        post('log', { level: level, message: String(message) });
    }

    const shell = createShell({
        loadScript: (url) => new Promise((resolve, reject) => {
            const s = doc.createElement('script');
            s.src = url;
            s.onload = () => resolve();
            s.onerror = () => reject(new Error('network or 404'));
            doc.head.appendChild(s);
        }),
        createContainer: (name) => {
            const el = doc.createElement('div');
            el.className = 'wl-screen';
            el.dataset.screen = name;
            doc.getElementById('wl-root').appendChild(el);
            return el;
        },
        removeContainer: (el) => el.remove(),
        post: post,
        log: log,
    });

    global.WastelandUI = Object.assign({ registerScreen: shell.registerScreen, post: post, log: log }, createHelpers(doc));
    global.addEventListener('message', (e) => shell.handle(e.data));
    global.addEventListener('error', (e) => log('error', (e.message || 'script error') + ' (' + (e.filename || '?') + ':' + (e.lineno || 0) + ')'));
    post('ready');
})(typeof window !== 'undefined' ? window : this);
