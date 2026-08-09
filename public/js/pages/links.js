const entries = JSON.parse(document.querySelector('[data-entries-data]').textContent);
const total = entries.length;
const entriesBody = document.querySelector('[data-entries-body]');
const rowsByName = new Map(
  Array.from(entriesBody.querySelectorAll('tr[data-name]')).map((row) => [row.dataset.name, row])
);
// Rows keyed by data-name, the natural key, rather than array position — a
// row's position in `entries` no longer has to match its position in the
// DOM for this array to line up with it.
const rows = entries.map((entry) => rowsByName.get(entry.name));
// One name link per row, same order as `rows` and `entries`.
const nameLinks = rows.map((row) => row.querySelector('[data-role="name-link"]'));
const emptyRow = document.querySelector('[data-empty-row]');
const emptyQuery = document.querySelector('[data-empty-query]');
const subtitleCount = document.querySelector('[data-subtitle-count]');
const search = document.querySelector('[data-search]');

let Fuse;
try {
  ({ default: Fuse } = await import('https://cdn.jsdelivr.net/npm/fuse.js@7.5.0/dist/fuse.mjs'));
} catch {
  // Offline, or the CDN is down. The list is server-rendered, so only
  // filtering and the keyboard model are gone; say so, rather than leaving a
  // search box that silently swallows what you type.
  search.disabled = true;
  search.placeholder = 'Filter unavailable — offline';
}

// Everything below needs the index, so it's gated on having one — a failed
// import above is the clean early exit, not a crash partway through.
if (Fuse) {
  // Name and alias are what a query is actually trying to recall ("that
  // youtube one was called yt, right?"); the destination URL is a much
  // weaker signal but still worth a small boost when someone searches by
  // the site they remember going to. Description sits between the two: it
  // catches the query you make when you've forgotten the name entirely and
  // are searching for what the thing does ("budget").
  const fuse = new Fuse(entries, {
    keys: [
      { name: 'name', weight: 0.45 },
      { name: 'aliases', weight: 0.3 },
      { name: 'description', weight: 0.15 },
      { name: 'url', weight: 0.1 }
    ],
    // 0.35 sits just past a cliff for short queries: "dis" matched 8 of 16 links,
    // including claude (one edit from "dis" lands inside "AI assistant"). Note
    // Fuse thresholds run the other way from intuition — 0 is exact, 1 matches
    // anything — so tightening means going down. At 0.30 "dis" returns disney and
    // xmen and nothing else, with every name and typo case unchanged.
    threshold: 0.30,
    ignoreLocation: true,
    // Match each word of the query separately rather than as one pattern. A
    // single fuzzy pattern tops out around 32 characters, so multi-word queries
    // arriving from the address bar as ?q= ("spreadsheet pokemon") matched
    // nothing at all; per-token matching with IDF weighting resolves them, and
    // single-word queries score identically to before. Needs the full Fuse build,
    // which is what the CDN module above already is.
    useTokenSearch: true,
    // 'any' ranks by relevance across the words that do match, so a query only
    // has to get part of the phrasing right. The cost is that a query matching
    // nothing in particular still returns its closest row instead of the "No
    // links match" state — 'all' is the stricter alternative if that grates.
    tokenMatch: 'any'
  });

  const plural = (n) => `${n} link${n === 1 ? '' : 's'}`;

  // Name links of the currently-visible rows, in row order — what the
  // up/down arrows step through. Rebuilt whenever the filter changes, rather
  // than re-derived from the DOM on every keypress.
  let visibleLinks = nameLinks;
  // Entry index of the best match for the current query, or null when there's
  // no query or nothing matched. Enter activates this, and its row carries the
  // .is-top-match mark so Enter's target is never a guess.
  let topIndex = null;

  const applyFilter = () => {
    const query = search.value.trim();
    // Fuse sorts by score, so results[0] is the best match — which is not
    // necessarily the topmost visible row. Rows keep their rendered (name)
    // order instead of reshuffling as you type, so the list stays browsable
    // and rows don't jump around under the cursor.
    const results = query === '' ? null : fuse.search(query);
    const matches = results === null ? null : new Set(results.map((r) => r.refIndex));

    visibleLinks = [];
    rows.forEach((row, i) => {
      const visible = matches === null || matches.has(i);
      row.hidden = !visible;
      if (visible) visibleLinks.push(nameLinks[i]);
    });

    topIndex = results !== null && results.length > 0 ? results[0].refIndex : null;
    rows.forEach((row, i) => row.classList.toggle('is-top-match', i === topIndex));

    emptyRow.hidden = !(matches !== null && visibleLinks.length === 0);
    emptyQuery.textContent = query;
    subtitleCount.textContent = matches === null ? plural(total) : `${visibleLinks.length} of ${plural(total)}`;
  };

  search.addEventListener('input', applyFilter);

  // The box arrives pre-filled when a name didn't resolve and the catch-all route
  // in server.rb sent the query here as ?q= — which fires no input event, so run
  // the filter once to match what's already in the box. Selecting the text makes
  // the next keystroke replace it rather than append: a query that landed here
  // failed to resolve, so the likely next move is a different guess.
  if (search.value.trim() !== '') {
    applyFilter();
    search.select();
  }

  document.addEventListener('keydown', (event) => {
    const onSearch = document.activeElement === search;

    // "/" jumps to the search box from anywhere on the page, the same way
    // it does on GitHub — a fitting shortcut for a page built around typing
    // short names quickly.
    if (event.key === '/' && !onSearch) {
      event.preventDefault();
      search.focus();
      return;
    }

    // Enter goes straight to the best match, so the common case is "type a few
    // characters and leave" with no arrow keys involved at all. Cmd/Ctrl opens
    // it in a new tab, matching what the same chord does on a focused link.
    if (event.key === 'Enter' && onSearch && topIndex !== null) {
      event.preventDefault();
      const target = nameLinks[topIndex];
      if (event.metaKey || event.ctrlKey) {
        window.open(target.href, '_blank', 'noopener');
      } else {
        target.click();
      }
      return;
    }

    // Escape steps back out one level rather than dropping focus entirely:
    // from a link it returns to the search box with the query intact (so you
    // can keep refining), and from the search box it clears the query. It
    // never blurs — on a page that is essentially one search box, "nothing
    // focused" is a dead state with no keyboard way back in.
    if (event.key === 'Escape') {
      if (visibleLinks.includes(document.activeElement)) {
        event.preventDefault();
        search.focus();
      } else if (onSearch && search.value !== '') {
        event.preventDefault();
        search.value = '';
        applyFilter();
      }
      return;
    }

    if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') return;

    // Only steer the arrow keys while focus is already on the search box or on
    // one of the name links; anywhere else (an alias chip, the edit button,
    // elsewhere on the page) they keep their normal behaviour — notably
    // scrolling, which is what they're for when the list isn't in play.
    const activeIndex = visibleLinks.indexOf(document.activeElement);
    if (!onSearch && activeIndex === -1) return;
    if (visibleLinks.length === 0) return;

    event.preventDefault();

    // The arrows are for overriding the default, not taking it — if you wanted
    // the best match you'd press Enter — so they walk the visible rows from the
    // top rather than starting at the marked row. Starting at the mark meant
    // the first press could land on the row that was already marked (and, when
    // the best match was the last row, clamp onto itself), so the key looked
    // dead. Both ends of the list lead back to the search box, so neither
    // direction dead-ends.
    if (event.key === 'ArrowUp') {
      if (onSearch || activeIndex === 0) search.focus();
      else visibleLinks[activeIndex - 1].focus();
    } else if (onSearch) {
      visibleLinks[0].focus();
    } else if (activeIndex === visibleLinks.length - 1) {
      search.focus();
    } else {
      visibleLinks[activeIndex + 1].focus();
    }
  });
}
