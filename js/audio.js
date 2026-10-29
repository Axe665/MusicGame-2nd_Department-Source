/* =========================================================
   Local audio playback wrapper.
   The chart clock is the HTMLAudioElement currentTime, so the
   notes stay locked to the supplied MP3.
   ========================================================= */
(function (global) {
  'use strict';

  class OrbitAudio {
    constructor() {
      this.el = document.getElementById('songAudio');
      this.volume = .72;
      this.started = false;
      this.paused = false;
      this.onEnded = null;

      if (!this.el) throw new Error('Audio element is missing.');
      this.el.volume = this.volume;
      this.el.addEventListener('ended', () => {
        this.started = false;
        if (typeof this.onEnded === 'function') this.onEnded();
      });
    }

    async start(volumePct) {
      const el = this.el;
      this.stop(0);
      this.volume = Math.max(0, Math.min(1, (volumePct ?? 72) / 100));
      el.volume = this.volume;
      try { el.currentTime = 0; } catch (e) { /* metadata not ready */ }
      this.started = true;
      this.paused = false;
      try {
        await el.play();
      } catch (err) {
        this.started = false;
        throw err;
      }
    }

    get songTime() {
      if (!this.started) return 0;
      return this.el.currentTime || 0;
    }

    get duration() {
      return Number.isFinite(this.el.duration) ? this.el.duration : 0;
    }

    getSpectrum() {
      return null;
    }

    setVolume(pct) {
      this.volume = Math.max(0, Math.min(1, pct / 100));
      this.el.volume = this.volume;
    }

    async pause() {
      this.paused = true;
      this.el.pause();
    }

    async resume() {
      if (!this.started) return;
      this.paused = false;
      try {
        await this.el.play();
      } catch (e) {
        /* leave it paused if the browser refuses */
      }
    }

    stop() {
      this.started = false;
      this.paused = false;
      this.el.pause();
      try { this.el.currentTime = 0; } catch (e) { /* metadata not ready */ }
    }
  }

  global.OrbitAudio = OrbitAudio;
})(window);
