import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

const primary = { title: 'La voie des rois, volume 2', originalTitle: 'The way of kings', authors: ['Brandon Sanderson'], publishedDate: '2017' };
const work = { key: '/works/OL123W', title: 'The Way of Kings', author_name: ['Brandon Sanderson'], first_publish_year: 2010 };
const resolve = (docs, notice = primary) => JSON.parse(execFileSync('/usr/bin/perl', [new URL('../lib/book-original-date.pl', import.meta.url).pathname], { input: JSON.stringify({ primary: notice, docs }), encoding: 'utf8' }));

test('identifies the original work independently of the translated volume', () => {
  assert.deepEqual(resolve([work]), { publishedDate: '2010' });
});
test('ignores search rank and rejects another author', () => {
  assert.equal(resolve([{ ...work, author_name: ['Someone Else'] }, work]).publishedDate, '2010');
  assert.deepEqual(resolve([{ ...work, author_name: ['Someone Else'] }]), {});
});
test('does not use the translation as an original work', () => {
  assert.deepEqual(resolve([{ ...work, title: primary.title, first_publish_year: 2017 }]), {});
});
test('rejects ambiguous works and inconsistent dates', () => {
  assert.deepEqual(resolve([work, { ...work, key: '/works/OL456W' }]), {});
  assert.deepEqual(resolve([work, { ...work, first_publish_year: 2011 }]), {});
});
test('leaves missing, invalid or later years unknown', () => {
  for (const first_publish_year of [undefined, '', 'unknown', 0, 2018]) assert.deepEqual(resolve([{ ...work, first_publish_year }]), {});
  assert.deepEqual(resolve([]), {});
});
test('requires the complete author set; tolerates accents and surname-first names', () => {
  assert.deepEqual(resolve([{ ...work, author_name: ['Brandon Sanderson', 'Other Author'] }]), {});
  assert.equal(resolve([{ ...work, author_name: ['Sánderson, Brandon'] }]).publishedDate, '2010');
});
