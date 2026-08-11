// Click-to-copy for [data-copyable] elements, and the "Copied!" label that
// confirms it. Knows nothing about the setup callout that currently holds the only
// four of them — a page gets working copy chips by rendering the markup (see the
// `copyable` helper in server.rb) and loading this module.
//
// Delegated from the document rather than from a container, so where the chips
// live is the page's business and not this file's.
const label = document.querySelector('[data-copied-label]');

// How long the label stays up before it starts to go. One familiar word, landing
// directly under the cursor where the eye already is, so this only has to outlast
// noticing it — and the label is confirming something that already succeeded, which
// makes overstaying the worse failure. With the fade after it (--dur, 150ms) the
// whole thing is done inside a second.
const DWELL = 800;

// One label for every chip, so two timers rather than one: the first ends the dwell
// and starts the fade, the second empties the text once the fade is over. They have
// to be separate, because clearing the text at the same moment the fade starts
// collapses the label to an empty coloured pill and leaves *that* to fade — which
// reads as the text blinking out and a fragment lingering, not as one thing
// disappearing. Both are reset by a second click, or a pending clear from the
// previous copy would wipe the new label mid-dwell.
let dwellTimer;
let clearTimer;

const showCopied = (event) => {
  // Bottom-right of the pointer, offset clear of the cursor by the translate in
  // components/copyable.css. Copying is mouse-only — the chips are out of the tab
  // order, see the `copyable` helper in server.rb — so there is always a pointer to
  // position against, and the awkward case of a keyboard activation with no cursor
  // to speak of can't arise.
  label.style.left = `${event.clientX}px`;
  label.style.top = `${event.clientY}px`;

  clearTimeout(dwellTimer);
  clearTimeout(clearTimer);

  label.textContent = 'Copied!';
  label.classList.add('is-visible');

  dwellTimer = setTimeout(() => {
    label.classList.remove('is-visible');
    // Read off the element rather than repeated as a number here, so the wait for
    // the fade is whatever --dur currently is — including the 0s that
    // prefers-reduced-motion sets, where the text should just go.
    const fade = parseFloat(getComputedStyle(label).transitionDuration) * 1000;
    // Emptied as well as faded: an unchanged live region is nothing new to
    // announce, so leaving the text in place would silence the next copy.
    clearTimer = setTimeout(() => { label.textContent = ''; }, fade);
  }, DWELL);
};

document.addEventListener('click', (event) => {
  const chip = event.target.closest('[data-copyable]');
  if (!chip) return;

  // The page is only ever served over localhost, which is a secure context, so the
  // clipboard API is always available here. textContent rather than a data
  // attribute: what gets copied is exactly the string on screen, with no second
  // copy of it in the markup to drift.
  navigator.clipboard.writeText(chip.textContent);
  showCopied(event);
});
