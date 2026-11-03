// Framer's movie night screensaver: a greyscale Butler, the time and the weather,
// dim grey on black. Nix puts the SVG in place of BUTLER_SVG when it builds this.
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

const style = `
:host {
  position: fixed;
  inset: 0;
  z-index: 10;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 16px;
  background: black;
  color: #7a7a7a;
  font-family: var(--ha-font-family-body, sans-serif);
  text-align: center;
}
.butler svg { width: 260px; height: auto; display: block; }
.time { font-size: 72px; font-weight: 300; line-height: 1; letter-spacing: 2px; }
.weather { display: flex; align-items: center; gap: 10px; font-size: 32px; }
.weather ha-icon { --mdc-icon-size: 36px; color: #7a7a7a; }
.weather[hidden] { display: none; }
`;

class FramerMovieNightCard extends HTMLElement {
  setConfig(config) {
    this.config = { weather: "weather.home", ...config };
    if (this.shadowRoot) return;
    this.attachShadow({ mode: "open" }).innerHTML = `
      <style>${style}</style>
      <div class="butler">${butler}</div>
      <div class="time"></div>
      <div class="weather" hidden><ha-icon></ha-icon><span class="temperature"></span></div>`;
    this.time = this.shadowRoot.querySelector(".time");
    this.weather = this.shadowRoot.querySelector(".weather");
    this.icon = this.shadowRoot.querySelector("ha-icon");
    this.temperature = this.shadowRoot.querySelector(".temperature");
  }

  set hass(hass) {
    this.timeZone = hass.config?.time_zone;
    this.tick();
    const weather = hass.states[this.config.weather];
    const temperature = weather?.attributes?.temperature;
    this.weather.hidden = typeof temperature !== "number";
    if (this.weather.hidden) return;
    this.icon.setAttribute("icon", iconOfCondition[weather.state] ?? "mdi:weather-cloudy");
    this.temperature.textContent = `${Math.round(temperature)}°`;
  }

  connectedCallback() {
    this.tick();
    this.ticking = setInterval(() => this.tick(), 10000);
  }

  disconnectedCallback() {
    clearInterval(this.ticking);
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
