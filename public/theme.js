// Loaded blocking from <head> on every page, and deliberately not a module:
// modules are deferred, so the page would paint in the system theme and then
// flip to the stored one — a visible flash on every load. Being a classic
// script it also shares the global scope, hence the IIFE that links.js
// doesn't need.
(() => {
  const root = document.documentElement;

  // localStorage throws in some privacy modes; a missing preference just
  // means "follow the system", which is the default anyway.
  const read = () => {
    try {
      return localStorage.getItem('theme');
    } catch {
      return null;
    }
  };

  const write = (value) => {
    try {
      if (value) localStorage.setItem('theme', value);
      else localStorage.removeItem('theme');
    } catch {
      /* preference just won't persist */
    }
  };

  // Absence of data-theme leaves color-scheme at "light dark", which follows
  // the system — so this is also what a no-JS visitor gets.
  const stored = read();
  if (stored === 'light' || stored === 'dark') root.dataset.theme = stored;

  const MODES = ['system', 'light', 'dark'];
  const current = () => (root.dataset.theme === 'light' || root.dataset.theme === 'dark' ? root.dataset.theme : 'system');

  // The button is rendered after this script runs, so wire it up once the
  // DOM exists. Pages without a toggle (if any) simply skip this.
  document.addEventListener('DOMContentLoaded', () => {
    const button = document.getElementById('theme-toggle');
    if (!button) return;

    const render = () => {
      const mode = current();
      button.textContent = `theme: ${mode}`;
      // The visible label reads as a state, so spell out that activating it
      // changes that state rather than leaving "dark, button" ambiguous.
      button.setAttribute('aria-label', `Theme: ${mode}. Activate to change.`);
    };

    button.addEventListener('click', () => {
      const next = MODES[(MODES.indexOf(current()) + 1) % MODES.length];
      if (next === 'system') delete root.dataset.theme;
      else root.dataset.theme = next;
      write(next === 'system' ? null : next);
      render();
    });

    render();
  });
})();
