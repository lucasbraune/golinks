// Generating a description needs the server, so the control only exists once
// this script has run — it ships hidden and disabled from link_form.erb.
const urlInput = document.querySelector('input[name="url"]');
const descriptionInput = document.getElementById('description');
const generateButton = document.getElementById('generate-description');
const statusLine = document.getElementById('description-status');

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

document.getElementById('alias-list').addEventListener('click', (event) => {
  if (!event.target.classList.contains('remove-alias')) return;
  const rows = document.querySelectorAll('.alias-row');
  const row = event.target.closest('.alias-row');
  if (rows.length > 1) {
    row.remove();
  } else {
    row.querySelector('input').value = '';
  }
});

document.getElementById('add-alias').addEventListener('click', () => {
  const list = document.getElementById('alias-list');
  const row = document.createElement('div');
  row.className = 'alias-row';
  // Mirrors the alias row in link_form.erb, prefix and all.
  row.innerHTML =
    '<div class="input-prefix">' +
    '<span class="prefix" aria-hidden="true">go/</span>' +
    '<input type="text" name="aliases[]" placeholder="yt" aria-label="Alias">' +
    '</div>' +
    '<button type="button" class="remove-alias" aria-label="Remove alias">&times;</button>';
  list.appendChild(row);
  row.querySelector('input').focus();
});
