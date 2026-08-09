// Generating a description needs the server, so the control only exists once
// this script has run — it ships hidden and disabled from link_form.erb.
const urlInput = document.querySelector('input[name="url"]');
const descriptionInput = document.getElementById('description');
const generateButton = document.querySelector('[data-generate-description]');
const statusLine = document.querySelector('[data-description-status]');

// Deliberately not wired to paste/input on the URL field. A URL arrives by
// typing, autofill, and drag as well as paste, and on the edit form it's
// already there before any event fires — so an automatic trigger is either
// unreliable or fires while the user is still typing. One explicit click also
// means there's no in-flight request to race against a description the user
// is writing by hand.
const setBusy = (busy) => {
  generateButton.disabled = busy || urlInput.value.trim() === '';
  generateButton.textContent = busy ? 'Generating…' : 'Generate';
};

const setStatus = (text, isError = false) => {
  statusLine.textContent = text;
  statusLine.classList.toggle('is-error', isError);
};

generateButton.hidden = false;
setBusy(false);
urlInput.addEventListener('input', () => setBusy(false));

generateButton.addEventListener('click', async () => {
  setBusy(true);
  setStatus('');

  // The server allows itself 15s per fetch plus a retry, which is far longer
  // than anyone will sit in front of a form. Give up first and say so.
  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), 20000);

  try {
    const response = await fetch('/links/describe', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ url: urlInput.value.trim() }),
      signal: abort.signal
    });
    // /links/describe answers with JSON on every path, success or failure.
    const data = await response.json();
    if (!response.ok) throw new Error(data.error);

    descriptionInput.value = data.description;
    setStatus('Generated from the page.');
  } catch (error) {
    setStatus(
      error.name === 'AbortError' ? 'That took too long. Write a description yourself.' : error.message,
      true
    );
  } finally {
    clearTimeout(timer);
    setBusy(false);
  }
});

document.querySelector('[data-alias-list]').addEventListener('click', (event) => {
  if (!event.target.matches('[data-role="remove-alias"]')) return;
  const rows = document.querySelectorAll('[data-alias-row]');
  const row = event.target.closest('[data-alias-row]');
  // The alias list is never empty: blanking the last row instead of
  // removing it keeps at least one row on the page at all times. This was
  // originally just a UX call (never leave the list looking closed-off with
  // zero rows); the clone-the-sibling add button below now depends on it
  // too, since it's what guarantees there's always a row to clone.
  if (rows.length > 1) {
    row.remove();
  } else {
    row.querySelector('input').value = '';
  }
});

document.querySelector('[data-add-alias]').addEventListener('click', () => {
  const list = document.querySelector('[data-alias-list]');
  // link_form.erb always renders at least one alias row — (aliases.empty? ?
  // [''] : aliases) — and remove-alias blanks the last one rather than
  // removing it, so there is always a row here to copy. That makes the ERB
  // loop the only place this markup exists, rather than a second copy here
  // that can drift from it (as the old innerHTML string had: it was missing
  // autocomplete="off" spellcheck="false"). cloneNode copies the value
  // *attribute*, not what's been typed, so blank it explicitly rather than
  // rely on that.
  const rows = list.querySelectorAll('[data-alias-row]');
  const row = rows[rows.length - 1].cloneNode(true);
  row.querySelector('input').value = '';
  list.appendChild(row);
  row.querySelector('input').focus();
});

const deleteForm = document.querySelector('[data-delete-form]');
const deleteDialog = document.querySelector('[data-delete-dialog]');

// Only on the edit form: the add form has nothing to delete.
if (deleteForm) {
  deleteForm.addEventListener('submit', (event) => {
    event.preventDefault();
    deleteDialog.showModal();
  });

  // .submit() deliberately does not fire a submit event, so this can't loop
  // back into the handler above.
  deleteDialog.addEventListener('close', () => {
    if (deleteDialog.returnValue === 'delete') deleteForm.submit();
  });
}
