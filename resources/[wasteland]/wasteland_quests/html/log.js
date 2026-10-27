// wasteland_quests :: html/log.js
// The /quest screen (also J): the story step you are on, every job you have
// taken in full (what it is, each objective with how to do it, where to
// hand it in and how far, the reward, when you took it) and when finished
// jobs can be taken again. Esc, J or Close shuts it.
// Data: { story?, quests = [{ label, description, ready, ago, rewards = [text],
//         handIn = [{ label, metres }], objectives = [{ text, done, how }] }],
//         again = [{ label, minutes, camps }], active, maxActive, trackerHidden }

(function () {
    'use strict';

    function distance(m) { return m < 1000 ? Math.round(m) + ' m' : (m / 1000).toFixed(1) + ' km'; }

    // Pure helper (unit-tested with Node): a story step in one line.
    function storyLine(s) {
        if (!s || !s.step) return '';
        const st = s.step;
        let line = st.objective || st.title || '';
        if (st.type === 'kill' && st.count) line += ' (' + (st.progress || 0) + '/' + st.count + ')';
        if (st.where) line += ' · ' + st.where;
        return line;
    }

    if (typeof module === 'object' && module.exports) { module.exports = { storyLine: storyLine, distance: distance }; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let api = null;
    function onKey(e) { if (api && (e.key === 'Escape' || e.key === 'j' || e.key === 'J')) api.post('close'); }

    function job(q) {
        const card = h('div', { class: 'wql-job' + (q.ready ? ' is-ready' : '') },
            h('div', { class: 'wql-job__head' },
                h('div', { class: 'wql-job__name', text: q.label }),
                h('div', { class: 'wql-tag' + (q.ready ? ' is-ready' : ''), text: q.ready ? 'Ready to hand in' : 'In progress' })),
            q.description ? h('div', { class: 'wql-desc', text: q.description }) : null);
        const list = h('div', { class: 'wql-objs' });
        (q.objectives || []).forEach((o) => list.appendChild(h('div', { class: 'wql-obj' + (o.done ? ' is-done' : '') },
            h('div', { class: 'wql-obj__text', text: (o.done ? '✓ ' : '○ ') + o.text }),
            o.how && !o.done ? h('div', { class: 'wql-obj__how', text: o.how }) : null)));
        card.appendChild(list);
        const where = (q.handIn || []).map((c) => c.label + ' (' + distance(c.metres) + ')').join(', ');
        card.appendChild(h('div', { class: 'wql-facts' },
            h('div', null, h('span', { class: 'wql-k', text: 'Hand in at' }), h('span', { text: where || 'any camp trader (Jobs)' })),
            h('div', null, h('span', { class: 'wql-k', text: 'Reward' }), h('span', { text: (q.rewards || []).join(', ') || 'nothing' })),
            q.ago ? h('div', null, h('span', { class: 'wql-k', text: 'Taken' }), h('span', { text: q.ago === 'just now' ? 'just now' : q.ago + ' ago' })) : null));
        return card;
    }

    let host = null;

    function render(el, d) {
            el.innerHTML = '';
            const body = h('div', { class: 'wql-body' });

            if (d.story && d.story.step) {
                body.appendChild(h('div', { class: 'wql-section', text: 'Story' }));
                body.appendChild(h('div', { class: 'wql-job wql-story' },
                    h('div', { class: 'wql-job__head' },
                        h('div', { class: 'wql-job__name', text: (d.story.title || 'Story') + (d.story.subtitle ? ' · ' + d.story.subtitle : '') }),
                        h('div', { class: 'wql-tag', text: 'Step ' + d.story.stepNo + ' of ' + d.story.steps })),
                    h('div', { class: 'wql-obj__text', text: '○ ' + (d.story.step.title || '') }),
                    h('div', { class: 'wql-obj__how', text: storyLine(d.story) }),
                    h('div', { class: 'wql-desc', text: 'The story tracker and your map show where to go. /journal tells the story so far.' })));
            }

            body.appendChild(h('div', { class: 'wql-section', text: 'Jobs (' + (d.active || 0) + ' of ' + (d.maxActive || 3) + ')' }));
            if ((d.quests || []).length) (d.quests || []).forEach((q) => body.appendChild(job(q)));
            else body.appendChild(h('div', { class: 'wql-empty', text: 'No jobs taken. Camp traders give jobs: hold Left Alt on one and choose Jobs.' }));

            if ((d.again || []).length) {
                body.appendChild(h('div', { class: 'wql-section', text: 'Done recently' }));
                (d.again || []).forEach((a) => body.appendChild(h('div', { class: 'wql-again' },
                    h('span', { text: a.label }),
                    h('span', { class: 'wql-k', text: 'again in ' + a.minutes + ' min' + (a.camps && a.camps.length ? ' · ' + a.camps.join(', ') : '') }))));
            }

            el.appendChild(h('div', { class: 'wql-shade' }));
            el.appendChild(h('div', { class: 'wql-panel' },
                h('div', { class: 'wql-head' }, h('div', { class: 'wql-title', text: 'Quests' }),
                    UI.button(d.trackerHidden ? 'Show tracker' : 'Hide tracker', () => api.post('toggleTracker')),
                    UI.button('Close', () => api.post('close'))),
                body,
                h('div', { class: 'wl-hint wql-foot', text: 'J, /quest or Esc closes' })));
            el.appendChild(h('style', { text: CSS }));
    }

    UI.registerScreen('questLog', {
        mount: function (el, d, screenApi) {
            api = screenApi; host = el;
            render(el, d);
            document.addEventListener('keydown', onKey);
        },
        update: function (d) { if (host) render(host, d); },
        unmount: function () { document.removeEventListener('keydown', onKey); api = null; host = null; },
    });

    const CSS = [
        '.wql-shade { position: absolute; inset: 0; background: rgba(0,0,0,0.55); }',
        '.wql-panel { position: absolute; left: 50%; top: 50%; transform: translate(-50%,-50%); width: min(720px, 92vw); max-height: 86vh;',
        '  display: flex; flex-direction: column; gap: 10px; padding: 18px 20px; background: var(--wl-bg); border: 1px solid var(--wl-border);',
        '  border-radius: 12px; box-shadow: 0 20px 60px rgba(0,0,0,0.7); color: #ece8da; }',
        '.wql-head { display: flex; align-items: center; gap: 8px; } .wql-title { flex: 1; font-size: 22px; font-weight: 700; color: #e8c25a; letter-spacing: 0.05em; text-transform: uppercase; }',
        '.wql-body { overflow-y: auto; display: flex; flex-direction: column; gap: 8px; padding-right: 4px; }',
        '.wql-section { margin-top: 6px; font-size: 11px; letter-spacing: 0.14em; text-transform: uppercase; color: #e8c25a; border-bottom: 1px solid rgba(214,178,60,0.25); padding-bottom: 3px; }',
        '.wql-job { background: rgba(10,10,9,0.55); border: 1px solid rgba(214,186,140,0.12); border-left: 3px solid #d6b23c; border-radius: 6px; padding: 9px 12px; }',
        '.wql-job.is-ready { border-left-color: #7fc75a; } .wql-story { border-left-color: #c7834a; }',
        '.wql-job__head { display: flex; justify-content: space-between; align-items: center; gap: 8px; }',
        '.wql-job__name { font-size: 15px; font-weight: 700; color: #f0e6c8; }',
        '.wql-tag { font-size: 10px; letter-spacing: 0.08em; text-transform: uppercase; padding: 2px 7px; border-radius: 10px; background: rgba(214,178,60,0.15); color: #e8c25a; white-space: nowrap; }',
        '.wql-tag.is-ready { background: rgba(127,199,90,0.15); color: #9be27a; }',
        '.wql-desc { font-size: 12px; color: rgba(236,232,218,0.7); margin: 3px 0 4px; font-style: italic; }',
        '.wql-objs { display: flex; flex-direction: column; gap: 4px; margin: 4px 0; }',
        '.wql-obj__text { font-size: 13px; } .wql-obj.is-done .wql-obj__text { color: #9be27a; }',
        '.wql-obj__how { font-size: 12px; color: rgba(236,232,218,0.68); margin-left: 16px; }',
        '.wql-facts { display: flex; flex-direction: column; gap: 2px; font-size: 12px; margin-top: 4px; }',
        '.wql-k { color: rgba(236,232,218,0.55); margin-right: 8px; }',
        '.wql-facts .wql-k { display: inline-block; width: 74px; }',
        '.wql-again { display: flex; justify-content: space-between; font-size: 12px; padding: 4px 2px; border-bottom: 1px solid rgba(255,255,255,0.04); }',
        '.wql-empty { font-size: 12px; color: rgba(236,232,218,0.6); font-style: italic; }',
        '.wql-foot { text-align: right; }',
    ].join('\n');
})();
