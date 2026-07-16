(() => {
  'use strict';

  const dialog = document.querySelector('[data-install-dialog]');
  if (!dialog) return;

  const openDialog = event => {
    event?.preventDefault();
    if (!dialog.open) dialog.showModal();
    document.body.classList.add('install-open');
  };
  const closeDialog = () => {
    dialog.close();
    document.body.classList.remove('install-open');
  };

  document.querySelectorAll('[data-install-open]').forEach(control => control.addEventListener('click', openDialog));
  dialog.querySelector('[data-install-close]')?.addEventListener('click', closeDialog);
  dialog.addEventListener('close', () => document.body.classList.remove('install-open'));
  dialog.addEventListener('click', event => {
    const bounds = dialog.getBoundingClientRect();
    const outside = event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom;
    if (outside) closeDialog();
  });

  const copyButton = dialog.querySelector('[data-copy-install]');
  const command = dialog.querySelector('[data-install-command]');
  copyButton?.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(command?.textContent.trim() || '');
      copyButton.classList.add('copied');
      copyButton.setAttribute('aria-label', 'Install command copied');
      setTimeout(() => {
        copyButton.classList.remove('copied');
        copyButton.setAttribute('aria-label', 'Copy one-line install command');
      }, 1600);
    } catch {
      const selection = getSelection();
      const range = document.createRange();
      range.selectNodeContents(command);
      selection.removeAllRanges();
      selection.addRange(range);
      copyButton.setAttribute('aria-label', 'Command selected; press Command C to copy');
    }
  });

  if (location.hash === '#install') openDialog();
})();
