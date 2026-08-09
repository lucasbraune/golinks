// Loaded on every page — layout.erb always renders the footer button this
// wires up, so unlike pages/*.js there's no page-specific existence guard
// needed. The theme itself is already applied by the blocking inline script
// in <head>, before this module runs; this only wires up the button that
// changes it. Being a module, it runs after the DOM is parsed, so unlike the
// old classic-script version this doesn't need to wait for DOMContentLoaded.
const root = document.documentElement;

// localStorage throws in some privacy modes; a missing preference just
// means "follow the system", which is the default anyway.
const write = (value) => {
  try {
    if (value) localStorage.setItem('theme', value);
    else localStorage.removeItem('theme');
  } catch {
    /* preference just won't persist */
  }
};

const MODES = ['system', 'light', 'dark'];
const current = () => (root.dataset.theme === 'light' || root.dataset.theme === 'dark' ? root.dataset.theme : 'system');

const button = document.getElementById('theme-toggle');

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
