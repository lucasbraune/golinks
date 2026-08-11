// Wires up the setup callout: dismissing it, and bringing it back from the footer.
// Copying the strings out of it belongs to js/copyable.js, which the chips share
// with anything else that ever renders one. Whether the callout is currently
// *shown* is already settled before this runs, by the blocking inline script in
// views/layout.erb — same split as the theme: the state that affects first paint
// is applied inline, and only the controls defer to a module.
//
// Loaded from views/layout.erb, which renders the callout and its footer control on
// every page unconditionally, so all three elements below are guaranteed to exist.
const callout = document.querySelector('[data-setup-callout]');
const dismiss = document.querySelector('[data-setup-dismiss]');
const restore = document.querySelector('[data-setup-restore]');

// Where focus goes once the dismiss button stops existing. The first field in <main>
// is whatever the page is actually for: the filter box on the list (already its
// autofocus target on load) and the name field on the add/edit form. Optional,
// because "the page has a field" is a fact about today's two pages, not a guarantee.
const firstField = document.querySelector('main input, main textarea');

// localStorage throws in some privacy modes. Nothing here is worth failing the
// page over: an unwritable preference just means the callout comes back next
// load, which is the safer of the two ways to be wrong.
const writeDismissed = (value) => {
  try {
    if (value) localStorage.setItem('setupDismissed', '1');
    else localStorage.removeItem('setupDismissed');
  } catch {
    /* preference just won't persist */
  }
};

dismiss.addEventListener('click', () => {
  callout.hidden = true;
  writeDismissed(true);
  // Focus was on the button that just stopped existing, so it has to go somewhere
  // deliberate rather than fall back to the document.
  firstField?.focus();
});

// The same action whether the callout is up or not, which is why it's one branch
// and not two: show it (a no-op if it's already showing) and go to it. The
// control is in the footer and the callout is at the top of the page, so without
// the trip up there the click looks like it did nothing.
//
// Focusing the callout is what makes that trip: the browser scrolls a focused
// element into view — and only if it isn't already there, so an on-screen callout
// stays put instead of jumping. tabindex="-1" in the ERB is what makes it a
// focus target. Focusing the dismiss button inside it would scroll just as well
// but would land the keyboard on "throw this away" as the first thing it touches.
restore.addEventListener('click', () => {
  callout.hidden = false;
  writeDismissed(false);
  callout.focus();
});
