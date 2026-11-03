// Framer's dark screensaver, for movie night and while the assistant is off:
// a greyscale Butler, the time and the weather, dim grey on black.
// Nix puts the SVG in place of BUTLER_SVG when it builds this.
// Everything drifts a few pixels every few minutes, so nothing burns into the panel.
const tag = "framer-movie-night-card";

const butler = `@BUTLER_SVG@`;

const iconOfCondition = {
  "clear-night": "mdi:weather-night",
  cloudy: "mdi:weather-cloudy",
  exceptional: "mdi:alert-circle-outline",
  fog: "mdi:weather-fog",
  hail: "mdi:weather-hail",
  lightning: "mdi:weather-lightning",
  "lightning-rainy": "mdi:weather-lightning-rainy",
  partlycloudy: "mdi:weather-partly-cloudy",
  pouring: "mdi:weather-pouring",
  rainy: "mdi:weather-rainy",
  snowy: "mdi:weather-snowy",
  "snowy-rainy": "mdi:weather-snowy-rainy",
  sunny: "mdi:weather-sunny",
  windy: "mdi:weather-windy",
  "windy-variant": "mdi:weather-windy-variant",
};

const spokenCondition = {
  "clear-night": "clear",
  partlycloudy: "partly cloudy",
  "lightning-rainy": "storms",
  "snowy-rainy": "sleet",
  "windy-variant": "windy",
};

// Pixel offsets the content steps through, one every few minutes.
const drift = [
  [0, 0], [6, -4], [-5, 6], [8, 5], [-7, -6], [3, 8], [-8, 2], [5, -8],
];
const driftMs = 3 * 60 * 1000;

const style = `
:host {
  position: fixed;
  inset: 0;
  z-index: 10;
  display: flex;
  align-items: center;
  justify-content: center;
  background: black;
  color: #6a6a6a;
  font-family: var(--ha-font-family-body, sans-serif);
  text-align: center;
}
.content {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 16px;
  transition: transform 20s ease-in-out;
}
.butler svg { width: 260px; height: auto; display: block; opacity: 0.8; }
.time { font-size: 72px; font-weight: 300; line-height: 1; letter-spacing: 2px; }
.weather { display: flex; align-items: center; gap: 10px; font-size: 32px; }
.weather ha-icon { --mdc-icon-size: 40px; color: #6a6a6a; }
.weather ha-icon[hidden], .weather[hidden] { display: none; }
@media (prefers-reduced-motion: reduce) { .content { transition: none; } }
`;

class FramerMovieNightCard extends HTMLElement {
  setConfig(config) {
    this.config = { weather: "weather.home", butler: true, ...config };
    if (this.shadowRoot) return;
    this.attachShadow({ mode: "open" }).innerHTML = `
      <style>${style}</style>
      <div class="content">
        ${this.config.butler ? `<div class="butler">${butler}</div>` : ""}
        <div class="time"></div>
        <div class="weather" hidden><ha-icon></ha-icon><span class="text"></span></div>
      </div>`;
    this.content = this.shadowRoot.querySelector(".content");
    this.time = this.shadowRoot.querySelector(".time");
    this.weather = this.shadowRoot.querySelector(".weather");
    this.icon = this.shadowRoot.querySelector("ha-icon");
    this.text = this.shadowRoot.querySelector(".text");
  }

  set hass(hass) {
    this.timeZone = hass.config?.time_zone;
    this.tick();
    // The condition icon, temperature and condition in words, or whichever of them
    // the weather entity has, so an unavailable entity leaves no blank line.
    const weather = hass.states[this.config.weather];
    const condition = weather?.state;
    const known = condition in iconOfCondition;
    const temperature = weather?.attributes?.temperature;
    const words = [
      typeof temperature === "number" ? `${Math.round(temperature)}°` : "",
      known ? (spokenCondition[condition] ?? condition) : "",
    ].filter(Boolean);
    this.weather.hidden = words.length === 0;
    this.icon.hidden = !known;
    if (known) this.icon.setAttribute("icon", iconOfCondition[condition]);
    this.text.textContent = words.join(" ");
  }

  connectedCallback() {
    this.tick();
    this.ticking = setInterval(() => this.tick(), 10000);
    this.step = 0;
    this.drifting = setInterval(() => this.drift(), driftMs);
  }

  disconnectedCallback() {
    clearInterval(this.ticking);
    clearInterval(this.drifting);
  }

  drift() {
    if (!this.content) return;
    this.step = (this.step + 1) % drift.length;
    const [x, y] = drift[this.step];
    this.content.style.transform = `translate(${x}px, ${y}px)`;
  }

  tick() {
    if (!this.time) return;
    this.time.textContent = new Date().toLocaleTimeString("en-AU", {
      hour: "numeric",
      minute: "2-digit",
      hourCycle: "h23",
      timeZone: this.timeZone,
    });
  }

  getCardSize() {
    return 0;
  }
}

if (!customElements.get(tag)) {
  customElements.define(tag, FramerMovieNightCard);
}
