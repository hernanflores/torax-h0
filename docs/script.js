const ring = document.querySelector('.ring-outer');
const core = document.querySelector('.ring-core');
let phase = 0;

function animatePattern() {
  phase += 0.22;
  ring.style.transform = `rotate(${phase}deg)`;
  core.style.transform = `scale(${1 + Math.sin(phase / 18) * 0.035})`;
  requestAnimationFrame(animatePattern);
}

animatePattern();
