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
  row.innerHTML =
    '<input type="text" name="aliases[]" placeholder="yt">' +
    '<button type="button" class="remove-alias" aria-label="Remove alias">&times;</button>';
  list.appendChild(row);
  row.querySelector('input').focus();
});
