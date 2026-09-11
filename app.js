import { angleDescription, angleFromVerticalDrag, clampAngle, lidGeometry } from './logic.mjs';

const root = document.documentElement;
const stage = document.querySelector('#laptop-stage');
const angleInput = document.querySelector('#angle');
const outputs = [document.querySelector('#angle-output'), document.querySelector('#angle-side-output')];
const playButton = document.querySelector('#play');
const soundButton = document.querySelector('#sound');
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
const defaults = { angle: 110, style: 'silk', wallpaper: 'orchid', strength: 72, blur: 2, shadow: 34, sound: false };
const presets = {
  silk: { strength: 72, blur: 2, shadow: 34 },
  shade: { strength: 82, blur: 1, shadow: 62 },
  frost: { strength: 88, blur: 8, shadow: 42 },
};
const wallpaperNames = new Set(['orchid', 'tide', 'dusk', 'citrus']);
let state = { ...defaults };
let playing = false;
let frame = null;
let audioContext = null;
let lastClickBand = 'open';

function restoreSettings() {
  try {
    const current = localStorage.getItem('foldly-settings');
    const legacy = localStorage.getItem('hingely-settings') ?? localStorage.getItem('bendy-settings');
    const saved = JSON.parse(current ?? legacy);
    if (!saved || typeof saved !== 'object') return;
    state.angle = clampAngle(saved.angle ?? defaults.angle);
    state.style = presets[saved.style] ? saved.style : defaults.style;
    state.wallpaper = wallpaperNames.has(saved.wallpaper) ? saved.wallpaper : defaults.wallpaper;
    for (const key of ['strength', 'blur', 'shadow']) {
      const control = document.querySelector(`#${key}`);
      const value = Number(saved[key]);
      state[key] = Number.isFinite(value) ? Math.min(Number(control.max), Math.max(Number(control.min), Math.round(value))) : defaults[key];
    }
    state.sound = saved.sound === true;
  } catch { /* Ignore invalid or unavailable storage. */ }
}

function persistSettings() {
  try {
    localStorage.setItem('foldly-settings', JSON.stringify(state));
    localStorage.removeItem('hingely-settings');
    localStorage.removeItem('bendy-settings');
  } catch { /* Storage is optional. */ }
}

function playFoldClick(closing) {
  if (!state.sound || !audioContext || audioContext.state !== 'running') return;
  const now = audioContext.currentTime;
  const oscillator = audioContext.createOscillator();
  const gain = audioContext.createGain();
  oscillator.type = 'sine';
  oscillator.frequency.setValueAtTime(closing ? 210 : 165, now);
  oscillator.frequency.exponentialRampToValueAtTime(closing ? 92 : 240, now + 0.07);
  gain.gain.setValueAtTime(0.0001, now);
  gain.gain.exponentialRampToValueAtTime(0.055, now + 0.008);
  gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.085);
  oscillator.connect(gain).connect(audioContext.destination);
  oscillator.start(now);
  oscillator.stop(now + 0.09);
}

function syncRangeFill(input) {
  const min = Number(input.min || 0);
  const max = Number(input.max || 100);
  const fill = ((Number(input.value) - min) / (max - min)) * 100;
  input.style.setProperty('--fill', `${Math.min(100, Math.max(0, fill))}%`);
}

function updateAngle(value, { save = true } = {}) {
  state.angle = clampAngle(value);
  const closed = 120 - state.angle;
  const progress = closed / 105;
  const geometry = lidGeometry(state.angle, state.strength);
  root.style.setProperty('--angle', state.angle);
  root.style.setProperty('--lid-fold', `${geometry.lidFold.toFixed(2)}deg`);
  root.style.setProperty('--lid-progress', geometry.closure.toFixed(3));
  root.style.setProperty('--fold', `${geometry.desktopFold.toFixed(2)}deg`);
  root.style.setProperty('--fold-progress', progress.toFixed(3));
  root.style.setProperty('--dynamic-blur', `${(progress * state.blur).toFixed(2)}px`);
  root.style.setProperty('--dynamic-shadow', ((progress * state.shadow) / 100).toFixed(3));
  angleInput.value = state.angle;
  syncRangeFill(angleInput);
  outputs.forEach((output) => { output.value = `${state.angle}°`; output.textContent = `${state.angle}°`; });
  stage.setAttribute('aria-valuenow', String(state.angle));
  stage.setAttribute('aria-valuetext', angleDescription(state.angle));
  const band = state.angle < 31 ? 'closed' : state.angle > 44 ? 'open' : lastClickBand;
  if (band !== lastClickBand) { playFoldClick(band === 'closed'); lastClickBand = band; }
  if (save) persistSettings();
}

function selectStyle(name, save = true, applyPreset = true) {
  if (!presets[name]) return;
  state.style = name;
  if (applyPreset) Object.assign(state, presets[name]);
  root.dataset.style = name;
  document.querySelectorAll('button[data-style]').forEach((button) => {
    const selected = button.dataset.style === name;
    button.classList.toggle('selected', selected);
    button.setAttribute('aria-pressed', String(selected));
  });
  for (const key of ['strength', 'blur', 'shadow']) {
    const input = document.querySelector(`#${key}`);
    input.value = state[key];
    syncRangeFill(input);
    const output = document.querySelector(`#${key}-output`);
    output.value = state[key];
    output.textContent = state[key];
  }
  updateAngle(state.angle, { save });
}

function selectWallpaper(name, save = true) {
  if (!wallpaperNames.has(name)) return;
  state.wallpaper = name;
  root.dataset.wallpaper = name;
  document.querySelectorAll('button[data-wallpaper]').forEach((button) => {
    const selected = button.dataset.wallpaper === name;
    button.classList.toggle('selected', selected);
    button.setAttribute('aria-pressed', String(selected));
  });
  if (save) persistSettings();
}

function ensureAudio() {
  try {
    if (!audioContext) {
      const AudioCtor = window.AudioContext || window.webkitAudioContext;
      if (AudioCtor) audioContext = new AudioCtor();
    }
    if (audioContext?.state === 'suspended') {
      audioContext.resume().catch(() => setSound(false));
    }
  } catch {
    setSound(false);
  }
}

function setSound(enabled, save = true) {
  state.sound = enabled;
  soundButton.setAttribute('aria-pressed', String(enabled));
  soundButton.setAttribute('aria-label', enabled ? 'Mute bend sound' : 'Turn sound on');
  soundButton.classList.toggle('sound-enabled', enabled);
  if (enabled) ensureAudio();
  if (save) persistSettings();
}

function stopAnimation() {
  playing = false;
  if (frame) cancelAnimationFrame(frame);
  frame = null;
  playButton.setAttribute('aria-pressed', 'false');
  playButton.classList.remove('playing');
  playButton.querySelector('.play-label').textContent = 'Play the fold';
}

function startAnimation() {
  if (playing) { stopAnimation(); return; }
  if (reducedMotion.matches) { updateAngle(state.angle > 60 ? 24 : 110); return; }
  ensureAudio();
  playing = true;
  playButton.setAttribute('aria-pressed', 'true');
  playButton.classList.add('playing');
  playButton.querySelector('.play-label').textContent = 'Pause the fold';
  const startedAt = performance.now();
  const duration = 4200;
  const animate = (now) => {
    if (!playing) return;
    const t = ((now - startedAt) % duration) / duration;
    const eased = 0.5 - Math.cos(t * Math.PI * 2) / 2;
    updateAngle(110 - eased * 86, { save: false });
    frame = requestAnimationFrame(animate);
  };
  frame = requestAnimationFrame(animate);
}

function reset() {
  stopAnimation();
  state = { ...defaults };
  selectStyle(defaults.style, false);
  selectWallpaper(defaults.wallpaper, false);
  setSound(defaults.sound, false);
  updateAngle(defaults.angle);
}

restoreSettings();
selectStyle(state.style, false, false);
selectWallpaper(state.wallpaper, false);
setSound(state.sound, false);
updateAngle(state.angle, { save: false });

angleInput.addEventListener('input', (event) => { stopAnimation(); updateAngle(event.target.value); });
document.querySelectorAll('button[data-style]').forEach((button) => button.addEventListener('click', () => selectStyle(button.dataset.style)));
document.querySelectorAll('button[data-wallpaper]').forEach((button) => button.addEventListener('click', () => selectWallpaper(button.dataset.wallpaper)));

for (const key of ['strength', 'blur', 'shadow']) {
  const input = document.querySelector(`#${key}`);
  const output = document.querySelector(`#${key}-output`);
  input.addEventListener('input', () => {
    state[key] = Number(input.value);
    syncRangeFill(input);
    output.value = input.value;
    output.textContent = input.value;
    updateAngle(state.angle);
  });
}

let drag = null;
stage.addEventListener('pointerdown', (event) => {
  if (event.button !== 0) return;
  stopAnimation();
  drag = { y: event.clientY, angle: state.angle };
  stage.classList.add('dragging');
  stage.setPointerCapture(event.pointerId);
});
stage.addEventListener('pointermove', (event) => { if (drag) updateAngle(angleFromVerticalDrag(drag.angle, drag.y, event.clientY)); });
for (const name of ['pointerup', 'pointercancel']) stage.addEventListener(name, () => { drag = null; stage.classList.remove('dragging'); });
stage.addEventListener('keydown', (event) => {
  if (event.key === 'ArrowUp' || event.key === 'ArrowRight') { event.preventDefault(); stopAnimation(); updateAngle(state.angle + (event.shiftKey ? 10 : 2)); }
  if (event.key === 'ArrowDown' || event.key === 'ArrowLeft') { event.preventDefault(); stopAnimation(); updateAngle(state.angle - (event.shiftKey ? 10 : 2)); }
  if (event.key === 'Home') { event.preventDefault(); stopAnimation(); updateAngle(15); }
  if (event.key === 'End') { event.preventDefault(); stopAnimation(); updateAngle(120); }
});

playButton.addEventListener('click', startAnimation);
soundButton.addEventListener('click', () => setSound(!state.sound));
document.querySelector('#reset').addEventListener('click', reset);
document.addEventListener('keydown', (event) => {
  const interactive = event.target.closest('button, a, input, summary, dialog, [role="slider"]');
  if (event.code === 'Space' && !interactive && !event.repeat) { event.preventDefault(); startAnimation(); }
});
document.querySelectorAll('[data-open-dialog]').forEach((button) => button.addEventListener('click', () => document.querySelector(`#${button.dataset.openDialog}`).showModal()));
document.querySelectorAll('[data-close-dialog]').forEach((button) => button.addEventListener('click', () => button.closest('dialog').close()));
document.querySelectorAll('dialog').forEach((dialog) => dialog.addEventListener('click', (event) => { if (event.target === dialog) dialog.close(); }));
reducedMotion.addEventListener('change', () => { if (reducedMotion.matches) stopAnimation(); });
