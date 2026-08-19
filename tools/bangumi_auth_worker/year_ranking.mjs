function escapeHtml(value) {
  return String(value ?? '').replace(
    /[&<>"']/g,
    (character) =>
      ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;',
      })[character],
  );
}

export function buildYearRankingCacheKeyUrl(target) {
  const cacheUrl = new URL(target.toString());
  if (/^\/anime\/browser\/airtime\/\d{4}\/?$/.test(cacheUrl.pathname)) {
    // Isolate the API-backed chart from legacy all-time fallback entries.
    cacheUrl.searchParams.set('__animemaster_cache', 'year-ranking-api-v1');
  }
  return cacheUrl;
}

export function buildYearRankingSearchPayload(year) {
  return {
    keyword: '',
    sort: 'rank',
    filter: {
      type: [2],
      air_date: [`>=${year}-01-01`, `<${year + 1}-01-01`],
      rank: ['>=1'],
    },
  };
}

export function selectYearRankingSubjects(data, year, limit = 10) {
  if (!Array.isArray(data)) return [];

  return data
    .filter((subject) => {
      const rank = Number(subject?.rating?.rank);
      const score = Number(subject?.rating?.score);
      return (
        subject?.type === 2 &&
        String(subject?.date || '').startsWith(`${year}-`) &&
        Number.isFinite(rank) &&
        rank > 0 &&
        Number.isFinite(score) &&
        score > 0
      );
    })
    .sort((left, right) => left.rating.rank - right.rating.rank)
    .slice(0, limit);
}

export function renderYearRankingHtml(subjects) {
  const items = subjects
    .map((subject) => {
      const title = String(subject.name_cn || '').trim() || subject.name || '';
      const image = subject.images?.large || subject.image || '';
      const score = Number(subject.rating?.score);
      const scoreText = Number.isFinite(score) ? String(score) : '暂无数据';
      return [
        '<li class="item">',
        `<a class="l" href="/subject/${escapeHtml(subject.id)}">${escapeHtml(title)}</a>`,
        `<small class="fade">${escapeHtml(scoreText)}</small>`,
        `<img src="${escapeHtml(image)}">`,
        '</li>',
      ].join('');
    })
    .join('');

  return `<!doctype html><html><body><ul id="browserItemList">${items}</ul></body></html>`;
}
