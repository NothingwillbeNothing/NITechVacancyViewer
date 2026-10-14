const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const script = fs.readFileSync(path.join(__dirname, '../NITechVacancyViewer/Resources/extract-schedule.js'), 'utf8');

function extract(html) {
    const dom = new JSDOM(html, { runScripts: 'outside-only' });
    try { return JSON.parse(dom.window.eval(script)); }
    finally { dom.window.close(); }
}

function table(rows, date = '') {
    return `<table class="kyuko-shisetsu-nofixed" ${date ? `data-date="${date}"` : ''}><tbody>${rows}</tbody></table>`;
}

function row(name, event = '') {
    return `<tr><td class="kyuko-shi-shisetsunm">${name}</td><td valign="top">${event ? `<div class="kyuko-shi-jugyo">${event}</div>` : ''}</td></tr>`;
}

test('extracts seven days and vacant rooms without dropping long descriptions', () => {
    const html = Array.from({ length: 7 }, (_, day) => table(
        '<tr><th>施設</th></tr>' + row(' 0111 ', '08:50-10:20　講義 <span>担当者 備考</span>') + row('0112'), `2026-10-${14 + day}`
    )).join('');
    const result = extract(html);
    assert.equal(result.days.length, 7);
    assert.equal(result.days[0].date, '2026-10-14');
    assert.equal(result.days[0].rooms[0].name, '0111');
    assert.equal(result.days[0].rooms[0].events[0].text, '08:50-10:20 講義 担当者 備考');
    assert.deepEqual(result.days[0].rooms[1].events, []);
});

test('decodes HTML entities in open-ended times', () => {
    const result = extract(table(row('0111', '&lt;&lt;-&gt;&gt;　終日予約')));
    assert.equal(result.days[0].rooms[0].events[0].text, '<<->> 終日予約');
    assert.equal(result.days[0].date, null);
});

test('preserves unknown reservations instead of reporting a vacant row', () => {
    const result = extract(table(row('0111', '時刻調整中')));
    assert.equal(result.days[0].rooms[0].events[0].text, '時刻調整中');
});

test('rejects missing, empty, and malformed tables', () => {
    for (const html of ['', table(''), '<table class="kyuko-shisetsu-nofixed"></table>', table('<tr><td class="kyuko-shi-shisetsunm">0111</td></tr>')]) {
        assert.throws(() => extract(html));
    }
});

test('rejects excessive tables and discards non-ISO date attributes', () => {
    assert.throws(() => extract(Array.from({ length: 8 }, () => table(row('a'))).join('')));
    assert.equal(extract(table(row('a'), 'today')).days[0].date, null);
});
