// The release is readable and its links work without JavaScript.
const copyButton = document.getElementById('copy-release');
const shareButton = document.getElementById('share-release');
const feedback = document.getElementById('feedback');
const canonicalURL = 'https://jhonalexcastano.com/cumple-movistar';
let feedbackTimeout;

function announce(message) {
  clearTimeout(feedbackTimeout);
  feedback.textContent = message;
  feedback.hidden = false;
  feedbackTimeout = setTimeout(() => { feedback.hidden = true; }, 6000);
}

function releaseText() {
  return [...document.querySelectorAll('[data-press-copy]')]
    .map(element => element.textContent.replace(/\s+/g, ' ').trim())
    .join('\n\n');
}

if (navigator.clipboard?.writeText) {
  copyButton.hidden = false;
  copyButton.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(releaseText());
      announce('Comunicado copiado. Ya puedes pegarlo en tu editor.');
    } catch {
      announce('No se pudo copiar. Puedes seleccionar el texto o descargar el PDF.');
    }
  });
}

if (navigator.share || navigator.clipboard?.writeText) {
  shareButton.hidden = false;
  shareButton.addEventListener('click', async () => {
    try {
      if (navigator.share) {
        await navigator.share({title: 'Jhon Alex Castaño · El Cumpleaños del Rey del Chupe', url: canonicalURL});
      } else {
        await navigator.clipboard.writeText(canonicalURL);
        announce('Enlace copiado para compartir.');
      }
    } catch (error) {
      if (error.name !== 'AbortError') announce('Puedes compartir el enlace desde la barra de tu navegador.');
    }
  });
}
