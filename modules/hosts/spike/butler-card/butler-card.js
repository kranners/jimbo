const tag = "butler-voice-card";

const phaseOfSatellite = {
  listening: "listening",
  processing: "thinking",
  responding: "speaking",
};

const statusOfPhase = {
  listening: "Listening…",
  thinking: "Thinking…",
};

const secondsToLeave = 0.9;
const largestTextPx = 56;
const smallestTextPx = 22;

const butler = `
<svg viewBox="0 0 1000 1100" aria-hidden="true">
  <defs>
    <radialGradient id="sphere" cx="36%" cy="28%" r="78%">
      <stop offset="0" stop-color="#43b8b5"/>
      <stop offset="0.5" stop-color="#1a8789"/>
      <stop offset="1" stop-color="#0a4449"/>
    </radialGradient>
    <radialGradient id="shine" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="brass" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#f4dc8c"/>
      <stop offset="1" stop-color="#b8923a"/>
    </linearGradient>
    <linearGradient id="cloth" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#1d2a33"/>
      <stop offset="1" stop-color="#0d1318"/>
    </linearGradient>
  </defs>
  <g class="ripples">
    <circle cx="500" cy="400" r="300"/>
    <circle cx="500" cy="400" r="300"/>
    <circle cx="500" cy="400" r="300"/>
  </g>
  <g class="body" transform="translate(-12 78)">
    <path d="M512 520 L236 572 Q150 730 112 1100 L912 1100 Q874 730 788 572 Z" fill="url(#cloth)" stroke="#7fd6d0" stroke-opacity="0.3" stroke-width="6"/>
    <path d="M512 1100 L340 560 L684 560 Z" fill="#f5efe0"/>
    <path d="M512 1100 L352 560 L292 590 L400 760 L330 800 Z M512 1100 L672 560 L732 590 L624 760 L694 800 Z" fill="#253540"/>
    <circle cx="512" cy="790" r="22" fill="#17222b"/>
    <circle cx="512" cy="890" r="22" fill="#17222b"/>
    <circle cx="512" cy="990" r="22" fill="#17222b"/>
    <path d="M416 624 L416 548 Q512 522 608 548 L608 624 Z" fill="#f5efe0"/>
  </g>
  <g class="head-pose">
    <g class="head-motion">
      <circle cx="500" cy="400" r="300" fill="url(#sphere)"/>
      <ellipse cx="380" cy="215" rx="120" ry="62" transform="rotate(-28 380 215)" fill="url(#shine)"/>
      <path d="M268 560 Q330 660 470 690" fill="none" stroke="#7fd6d0" stroke-opacity="0.25" stroke-width="14" stroke-linecap="round"/>
      <g class="face">
        <g transform="translate(500 400) scale(0.765) translate(-512 -452)">
          <g class="brow brow-left"><g class="brow-motion"><path d="M316 336 Q404 290 476 322"/></g></g>
          <g class="brow brow-right"><g class="brow-motion"><path d="M548 256 Q634 176 718 230"/></g></g>
          <g class="blinker">
            <path class="eye eye-open" d="M344 404 L452 404"/>
            <path class="eye eye-glad" d="M344 418 Q398 366 452 418"/>
          </g>
          <path class="chain" d="M596 452 Q566 510 606 534 Q646 552 664 520 Q684 492 712 528 Q742 590 752 700"/>
          <g class="monocle">
            <circle cx="632" cy="368" r="86" fill="#f5efe0" fill-opacity="0.22" stroke="url(#brass)" stroke-width="30"/>
            <g class="blinker">
              <circle class="pupil pupil-open" cx="632" cy="376" r="24"/>
              <path class="pupil pupil-glad" d="M606 386 Q632 352 658 386"/>
            </g>
            <path class="glint" d="M590 334 Q606 314 634 312"/>
            <path class="sparkle" d="M584 290 L592 312 L614 320 L592 328 L584 350 L576 328 L554 320 L576 312 Z"/>
          </g>
        </g>
      </g>
    </g>
  </g>
  <g class="bow">
    <g transform="translate(-12 78) translate(512 622) scale(1.12) translate(-512 -622)">
      <path d="M512 622 L264 506 Q224 622 264 738 Z M512 622 L760 506 Q800 622 760 738 Z" fill="url(#brass)" stroke="#17222b" stroke-width="20" stroke-linejoin="round"/>
      <path d="M318 572 L420 610 M318 672 L420 634 M706 572 L604 610 M706 672 L604 634" stroke="#8c6a22" stroke-width="18" stroke-linecap="round"/>
      <rect x="458" y="566" width="108" height="112" rx="28" fill="url(#brass)" stroke="#17222b" stroke-width="20"/>
      <path d="M482 596 Q500 586 520 588" fill="none" stroke="#fff6d8" stroke-width="12" stroke-linecap="round"/>
    </g>
  </g>
  <g class="thoughts">
    <circle cx="760" cy="150" r="20"/>
    <circle cx="830" cy="92" r="28"/>
    <circle cx="912" cy="30" r="36"/>
  </g>
</svg>`;

const style = `
:host { display: block; height: 0; }
.overlay {
  position: fixed;
  inset: 0;
  z-index: 10;
  pointer-events: none;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  font-family: var(--ha-font-family-body, var(--paper-font-body1_-_font-family, sans-serif));
  color: white;
}
.overlay::before {
  content: "";
  position: absolute;
  inset: 0;
  background:
    radial-gradient(ellipse 90% 45% at 50% 100%, rgba(26, 135, 137, 0.45), transparent 70%),
    linear-gradient(to bottom, rgba(4, 12, 16, 0.84), rgba(4, 12, 16, 0.92));
  animation: dim-in 0.6s ease-out both;
}
.overlay.leaving::before { animation: dim-out ${secondsToLeave}s ease-in both; }
@keyframes dim-in { from { opacity: 0; } }
@keyframes dim-out { to { opacity: 0; } }

.talk {
  position: relative;
  flex: 1 1 0;
  min-height: 0;
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  padding: 6vh 6vw 3vh;
  box-sizing: border-box;
  transition: opacity 0.4s;
}
.lines {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.5em;
  text-align: center;
  line-height: 1.3;
  font-size: ${largestTextPx}px;
}
.overlay.leaving .talk { opacity: 0; }
.status {
  font-size: 0.7em;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: #f4dc8c;
  opacity: 0.85;
}
.heard {
  font-size: 0.8em;
  font-style: italic;
  color: rgba(255, 255, 255, 0.78);
  text-shadow: 0 0.05em 0.2em black;
}
.heard::before { content: "“"; }
.heard::after { content: "”"; }
.bubble {
  position: relative;
  max-width: 100%;
  padding: 0.55em 0.8em;
  box-sizing: border-box;
  border-radius: 0.7em;
  background: #f5efe0;
  color: #17222b;
  border: 0.08em solid #d9b860;
  box-shadow: 0 0.3em 1em rgba(0, 0, 0, 0.5);
  animation: bubble-in 0.35s cubic-bezier(0.3, 1.5, 0.6, 1) both;
}
.bubble::after {
  content: "";
  position: absolute;
  left: 50%;
  bottom: -0.5em;
  width: 0.9em;
  height: 0.9em;
  background: #f5efe0;
  border-right: 0.08em solid #d9b860;
  border-bottom: 0.08em solid #d9b860;
  transform: translateX(-50%) rotate(45deg);
}
@keyframes bubble-in { from { opacity: 0; transform: translateY(0.4em) scale(0.92); } }
[hidden] { display: none !important; }

.butler {
  position: relative;
  flex: none;
  align-self: center;
  width: min(84vw, 50vh);
  margin-bottom: -4vh;
  transform-origin: 50% 100%;
  animation: arrive 1.1s cubic-bezier(0.2, 0.8, 0.3, 1) both;
}
.overlay.leaving .butler { animation: leave ${secondsToLeave}s cubic-bezier(0.5, 0, 0.8, 0.4) both; }
@keyframes arrive {
  0% { transform: translateY(105%) rotate(-6deg); }
  60% { transform: translateY(-5%) rotate(3deg); }
  80% { transform: translateY(2%) rotate(-1deg); }
  100% { transform: none; }
}
@keyframes leave {
  0% { transform: none; }
  25% { transform: translateY(-3%) rotate(-2deg); }
  100% { transform: translateY(110%) rotate(5deg); }
}
svg { display: block; width: 100%; height: auto; overflow: visible; }

.head-pose, .head-motion, .face, .brow, .brow-motion, .blinker, .eye, .pupil, .monocle, .bow, .thoughts circle, .ripples circle, .sparkle {
  transform-box: view-box;
}
.head-pose { transform-origin: 500px 700px; transition: transform 0.6s cubic-bezier(0.3, 1.4, 0.6, 1); }
.head-motion { transform-origin: 500px 700px; }
.face { transition: transform 0.6s cubic-bezier(0.3, 1.3, 0.6, 1); }
.brow path { fill: none; stroke: #f5efe0; stroke-width: 44; stroke-linecap: round; }
.brow { transition: transform 0.45s cubic-bezier(0.3, 1.5, 0.6, 1); }
.brow-left { transform-origin: 396px 316px; }
.brow-right { transform-origin: 633px 226px; }
.brow-left .brow-motion { transform-origin: 396px 316px; }
.brow-right .brow-motion { transform-origin: 633px 226px; }
.eye { fill: none; stroke: #f5efe0; stroke-width: 30; stroke-linecap: round; transition: opacity 0.3s; }
.pupil-open { fill: #f5efe0; transition: opacity 0.3s; }
.pupil-glad { fill: none; stroke: #f5efe0; stroke-width: 14; stroke-linecap: round; transition: opacity 0.3s; }
.eye-glad, .pupil-glad { opacity: 0; }
.blinker { transform-origin: 400px 404px; }
.monocle .blinker { transform-origin: 632px 376px; }
.overlay.blink .blinker { transform: scaleY(0.12); }
.glint { fill: none; stroke: white; stroke-width: 20; stroke-linecap: round; }
.sparkle { fill: white; opacity: 0; transform-origin: 584px 320px; }
.monocle { transform-origin: 632px 368px; }
.chain { fill: none; stroke: url(#brass); stroke-width: 11; stroke-linecap: round; stroke-dasharray: 1 19; }
.bow { transform-origin: 500px 700px; }
.thoughts circle { fill: #f4dc8c; opacity: 0; }
.ripples circle { fill: none; stroke: #f4dc8c; stroke-width: 6; opacity: 0; transform-origin: 500px 400px; }

.listening .head-pose { transform: translateY(18px) rotate(-5deg) scale(1.04); }
.listening .brow-right { transform: translateY(-34px) rotate(-6deg); }
.listening .brow-left { transform: translateY(-8px); }
.listening .ripples circle { animation: ripple 2.4s ease-out infinite; }
.listening .ripples circle:nth-child(2) { animation-delay: 0.8s; }
.listening .ripples circle:nth-child(3) { animation-delay: 1.6s; }
.listening .sparkle { animation: sparkle 2.4s ease-in-out infinite; }
.listening .head-motion { animation: nod 2.4s ease-in-out infinite; }
@keyframes ripple {
  0% { opacity: 0.7; transform: scale(1); }
  100% { opacity: 0; transform: scale(1.55); }
}
@keyframes sparkle {
  0%, 55%, 100% { opacity: 0; transform: scale(0.2) rotate(0deg); }
  70% { opacity: 1; transform: scale(1.4) rotate(45deg); }
  85% { opacity: 0; transform: scale(0.4) rotate(90deg); }
}
@keyframes nod {
  0%, 100% { transform: none; }
  50% { transform: translateY(8px) rotate(-1.5deg); }
}

.thinking .head-pose { transform: rotate(6deg); }
.thinking .face { transform: translate(48px, -46px); }
.thinking .brow-left { transform: translate(14px, 16px) rotate(14deg); }
.thinking .brow-right { transform: translate(-6px, 22px) rotate(-12deg); }
.thinking .monocle { animation: twirl 3.2s ease-in-out infinite; }
.thinking .thoughts circle { animation: thought 2.1s ease-in-out infinite; }
.thinking .thoughts circle:nth-child(2) { animation-delay: 0.35s; }
.thinking .thoughts circle:nth-child(3) { animation-delay: 0.7s; }
.thinking .head-motion { animation: ponder 4.2s ease-in-out infinite; }
@keyframes twirl {
  0% { transform: rotate(0deg); }
  60%, 100% { transform: rotate(360deg); }
}
@keyframes thought {
  0%, 100% { opacity: 0.25; transform: translateY(0); }
  45% { opacity: 1; transform: translateY(-14px); }
}
@keyframes ponder {
  0%, 100% { transform: none; }
  50% { transform: rotate(2.5deg); }
}

.speaking .head-pose { transform: translateY(6px); }
.speaking .head-motion { animation: bob 0.62s ease-in-out infinite alternate; }
.speaking .brow-left .brow-motion { animation: chatter 0.94s ease-in-out infinite alternate; }
.speaking .brow-right .brow-motion { animation: chatter 0.71s ease-in-out infinite alternate-reverse; }
.speaking .bow { animation: bounce 0.31s ease-in-out infinite alternate; }
@keyframes bob {
  0% { transform: translateY(0) rotate(-1deg); }
  100% { transform: translateY(-14px) rotate(1.5deg); }
}
@keyframes chatter {
  0% { transform: translateY(4px); }
  100% { transform: translateY(-18px) rotate(-4deg); }
}
@keyframes bounce {
  0% { transform: scale(1, 1); }
  100% { transform: scale(1.07, 0.9); }
}

.content .eye-open, .content .pupil-open { opacity: 0; }
.content .eye-glad, .content .pupil-glad { opacity: 1; }
.content .head-pose { transform: rotate(-4deg); }
.content .brow-left { transform: translateY(-6px); }
.content .brow-right { transform: translateY(-4px); }
.content .head-motion { animation: breathe 3.6s ease-in-out infinite; }
@keyframes breathe {
  0%, 100% { transform: none; }
  50% { transform: translateY(-6px); }
}

@media (prefers-reduced-motion: reduce) {
  .overlay *, .overlay *::before, .overlay *::after { animation: none !important; transition: none !important; }
  .overlay::before { animation: none; }
  .overlay.leaving { opacity: 0; transition: opacity ${secondsToLeave}s; }
  .thinking .thoughts circle { opacity: 1; }
}
`;

class ButlerVoiceCard extends HTMLElement {
  connectedWhileHidden = true;

  setConfig(config) {
    this.config = config;
    this.hidden = true;
    if (this.shadowRoot) return;
    this.attachShadow({ mode: "open" }).innerHTML = `
      <style>${style}</style>
      <div class="overlay" hidden>
        <div class="talk">
          <div class="lines">
            <div class="status" hidden></div>
            <div class="heard" hidden></div>
            <div class="bubble" hidden></div>
          </div>
        </div>
        <div class="butler">${butler}</div>
      </div>`;
    this.overlay = this.shadowRoot.querySelector(".overlay");
    this.talk = this.shadowRoot.querySelector(".talk");
    this.lines = this.shadowRoot.querySelector(".lines");
    this.status = this.shadowRoot.querySelector(".status");
    this.heard = this.shadowRoot.querySelector(".heard");
    this.bubble = this.shadowRoot.querySelector(".bubble");
  }

  set hass(hass) {
    const attributes = hass.states[this.config.voice]?.attributes ?? {};
    const satellite = hass.states[this.config.satellite]?.state;
    const reply = attributes.reply ?? "";
    const phase = phaseOfSatellite[satellite] ?? (reply ? "content" : undefined);

    if (hass.states[this.config.conversation]?.state !== "on" || !phase) {
      this.leave();
      return;
    }

    this.overlay.classList.remove("listening", "thinking", "speaking", "content");
    this.overlay.classList.add(phase);
    this.show(this.status, reply ? "" : (statusOfPhase[phase] ?? ""));
    this.show(this.heard, attributes.heard ?? "");
    this.show(this.bubble, reply);
    this.arrive();
  }

  show(element, text) {
    if (element.textContent === text) return;
    element.textContent = text;
    element.hidden = !text;
    this.fitText();
  }

  fitText() {
    if (this.overlay.hidden) return;
    const { paddingTop, paddingBottom } = getComputedStyle(this.talk);
    const room = this.talk.clientHeight - parseFloat(paddingTop) - parseFloat(paddingBottom);
    let size = largestTextPx;
    this.lines.style.fontSize = `${size}px`;
    while (size > smallestTextPx && this.lines.offsetHeight > room) {
      size -= 2;
      this.lines.style.fontSize = `${size}px`;
    }
  }

  arrive() {
    clearTimeout(this.leaving);
    this.leaving = undefined;
    if (this.overlay.classList.contains("leaving")) {
      this.overlay.classList.remove("leaving");
    }
    if (!this.hidden) return;
    this.setVisible(true);
    this.overlay.hidden = false;
    this.fitText();
    this.blinkLater();
  }

  leave() {
    if (this.hidden || this.leaving) return;
    this.overlay.classList.add("leaving");
    this.leaving = setTimeout(() => {
      this.leaving = undefined;
      this.overlay.classList.remove("leaving");
      this.overlay.hidden = true;
      clearTimeout(this.blinking);
      this.setVisible(false);
    }, secondsToLeave * 1000);
  }

  setVisible(visible) {
    this.hidden = !visible;
    this.dispatchEvent(new Event("card-visibility-changed"));
  }

  blinkLater() {
    clearTimeout(this.blinking);
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    this.blinking = setTimeout(() => {
      this.overlay.classList.add("blink");
      setTimeout(() => this.overlay.classList.remove("blink"), 150);
      this.blinkLater();
    }, 2500 + Math.random() * 4000);
  }

  getCardSize() {
    return 0;
  }
}

if (!customElements.get(tag)) {
  customElements.define(tag, ButlerVoiceCard);
}
