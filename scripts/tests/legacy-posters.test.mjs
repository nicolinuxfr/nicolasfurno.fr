import test from 'node:test';
import assert from 'node:assert/strict';
import { bookQuery, previousFilm } from '../legacy-posters.mjs';

test('retrouve le film indiqué par avant dans sa collection', () => {
  const parts = [
    { id: 1, title: 'Spider-Man: Homecoming', release_date: '2017-07-05', poster_path: '/home.jpg' },
    { id: 2, title: 'Spider-Man: Far From Home', release_date: '2019-07-03', poster_path: '/far.jpg' },
    { id: 3, title: 'Spider-Man: No Way Home', release_date: '2021-12-15', poster_path: '/no-way.jpg' },
  ];
  assert.equal(previousFilm(parts, 'spider-man-far-from-home-watts', '2021-12-15')?.id, 2);
});

test('le sous-titre du film prime sur le titre commun de la saga', () => {
  const parts = [
    { id: 1, title: 'Thor', release_date: '2011-04-21', poster_path: '/thor.jpg' },
    { id: 2, title: 'Thor : Ragnarok', release_date: '2017-10-25', poster_path: '/ragnarok.jpg' },
  ];
  assert.equal(previousFilm(parts, 'thor-ragnarok-waititi', '2022-07-06')?.id, 2);
});

test('retrouve le titre et l’auteur d’un livre à partir du lien avant', () => {
  assert.deepEqual(bookQuery('foret-sombre-liu'), { title: 'foret sombre', author: 'liu' });
});
