import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildYearRankingCacheKeyUrl,
  buildYearRankingSearchPayload,
  renderYearRankingHtml,
  selectYearRankingSubjects,
} from './year_ranking.mjs';

test('versions only year-ranking cache keys', () => {
  const yearUrl = buildYearRankingCacheKeyUrl(
    'https://bgm.tv/anime/browser/airtime/2026?sort=rank',
  );
  const generalUrl = buildYearRankingCacheKeyUrl(
    'https://bgm.tv/anime/browser?sort=rank',
  );

  assert.equal(
    yearUrl.searchParams.get('__animemaster_cache'),
    'year-ranking-api-v1',
  );
  assert.equal(yearUrl.searchParams.get('sort'), 'rank');
  assert.equal(generalUrl.searchParams.has('__animemaster_cache'), false);
});

test('builds a year-bounded ranked anime query', () => {
  assert.deepEqual(buildYearRankingSearchPayload(2026), {
    keyword: '',
    sort: 'rank',
    filter: {
      type: [2],
      air_date: ['>=2026-01-01', '<2027-01-01'],
      rank: ['>=1'],
    },
  });
});

test('keeps only ranked anime from the requested year and sorts by rank', () => {
  const selected = selectYearRankingSubjects(
    [
      { id: 1, type: 2, date: '2026-01-01', rating: { rank: 200, score: 8 } },
      { id: 2, type: 2, date: '2025-01-01', rating: { rank: 1, score: 9 } },
      { id: 3, type: 2, date: '2026-02-01', rating: { rank: 0, score: 9 } },
      { id: 4, type: 1, date: '2026-03-01', rating: { rank: 2, score: 9 } },
      { id: 5, type: 2, date: '2026-04-01', rating: { rank: 50, score: 8.5 } },
    ],
    2026,
  );

  assert.deepEqual(
    selected.map((subject) => subject.id),
    [5, 1],
  );
});

test('renders parser-compatible escaped browser HTML', () => {
  const html = renderYearRankingHtml([
    {
      id: 493016,
      name: 'A < B',
      name_cn: '异国&日记',
      images: { large: 'https://example.com/a&b.jpg' },
      rating: { score: 8.4 },
    },
  ]);

  assert.match(html, /id="browserItemList"/);
  assert.match(html, /class="item"/);
  assert.match(html, /class="l" href="\/subject\/493016"/);
  assert.match(html, /异国&amp;日记/);
  assert.match(html, /<small class="fade">8.4<\/small>/);
  assert.match(html, /a&amp;b\.jpg/);
});
