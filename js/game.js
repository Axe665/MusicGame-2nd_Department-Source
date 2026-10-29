/* =========================================================
   Two-lane rhythm game runtime.
   ========================================================= */
(function () {
  'use strict';

  const C = window.OrbitChart;
  const TAU = Math.PI * 2;
  const clamp = C.clamp;
  const DIFFS = C.DIFFICULTIES;
  const BEAT = C.BEAT;
  const DURATION = C.DURATION;
  const KEY_COLOR = C.KEY_COLOR;

  const JUDGE = { perfect: .04, good: .06 };
  const BASE_SCORE = { perfect: 1000, good: 600 };
  const ACC_WEIGHT = { perfect: 1, good: .6, miss: 0 };
  const LABELS = { perfect: 'PERFECT', good: 'GOOD', miss: 'MISS' };
  const JCOLORS = { perfect: '#fff0bf', good: '#7ef7de', miss: '#8e94ae' };
  const NOTE = {
    red: { main: '#ff4d73', light: '#ffc0cd', dark: '#8f1230', glow: 'rgba(255,77,115,' },
    blue: { main: '#49ccff', light: '#c8f6ff', dark: '#075d80', glow: 'rgba(73,204,255,' },
    white: { main: '#eef4ff', light: '#ffffff', dark: '#8194c9', glow: 'rgba(226,237,255,' }
  };
  const STORE_BEST = 'rhythm-best-v3';
  const STORE_DIFF = 'rhythm-diff-v3';
  const STORE_VOLUME = 'rhythm-volume-v1';
  const STORE_FLOW = 'rhythm-flow-v1';
  const STORE_OFFSET = 'rhythm-offset-v1';

  const $ = id => document.getElementById(id);

  function storageGet(key, fallback) {
    try {
      const raw = localStorage.getItem(key);
      return raw === null ? fallback : raw;
    } catch (e) {
      return fallback;
    }
  }

  function storageSet(key, value) {
    try { localStorage.setItem(key, value); } catch (e) { /* private mode */ }
  }

  function rgba(hex, alpha) {
    if (!hex) return `rgba(255,255,255,${alpha})`;
    if (hex.startsWith('rgba') || hex.startsWith('rgb')) return hex;
    const h = hex.replace('#', '');
    const n = parseInt(h.length === 3 ? h.split('').map(x => x + x).join('') : h, 16);
    return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${alpha})`;
  }

  function fmtScore(n) {
    return String(Math.max(0, Math.round(n))).padStart(7, '0');
  }

  function fmtShort(n) {
    if (n >= 1000000) return (n / 1000000).toFixed(2) + 'M';
    if (n >= 1000) return (n / 1000).toFixed(1) + 'k';
    return String(Math.round(n));
  }

  class OrbitGame {
    constructor() {
      this.canvas = $('scene');
      this.c = this.canvas.getContext('2d', { alpha: false });
      this.audio = new window.OrbitAudio();

      this.mode = 'songselect';
      this.clock = 0;
      this.lastFrame = performance.now();
      this.lastBeat = -1;
      this.songTime = 0;
      this.previewTime = 0;
      this.preview = false;
      this.previewAcc = null;
      this.silentMode = false;
      this.silentStart = 0;
      this.runId = 0;
      this.settingsOpen = false;
      this.calibrationOpen = false;
      this.calib = null;

      this.noteR = 20;
      this.coreR = 30;
      this.corePulse = 0;
      this.corePop = 0;
      this.beatPulse = 0;
      this.lineBase = 320;

      this.stars = [];
      this.bgCanvas = null;

      this.particles = [];
      this.shockwaves = [];
      this.judgments = [];
      this.ringFlashes = [];
      this.shake = 0;
      this.missFlash = 0;

      this.selectedDiff = storageGet(STORE_DIFF, 'd1');
      if (!DIFFS.some(d => d.id === this.selectedDiff)) this.selectedDiff = 'd1';

      this.volume = parseInt(storageGet(STORE_VOLUME, '72'), 10);
      if (!Number.isFinite(this.volume)) this.volume = 72;
      this.volume = clamp(this.volume, 0, 100);

      this.flowSpeed = parseFloat(storageGet(STORE_FLOW, '3'));
      if (!Number.isFinite(this.flowSpeed)) this.flowSpeed = 3;
      this.flowSpeed = clamp(this.flowSpeed, 1, 5);
      this.offsetMs = parseInt(storageGet(STORE_OFFSET, '0'), 10);
      if (!Number.isFinite(this.offsetMs)) this.offsetMs = 0;
      this.offsetMs = clamp(this.offsetMs, -200, 200);

      this.best = this._loadBests();
      this.chartCache = {};
      DIFFS.forEach(d => {
        this.chartCache[d.id] = C.getChart(d.id);
      });

      const params = new URLSearchParams(location.search);
      this.previewCombo = clamp(parseInt(params.get('combo') || '0', 10) || 0, 0, 999);

      this._cacheDom();
      this._buildSongSelect();
      this._buildMenu();
      this._bindEvents();
      this._syncVolumeUI();
      this._syncPlaybackUI();
      this.resize();
      this.coreR = this.noteR * 1.5;
      this._showSongSelect(true);

      if (params.has('preview')) {
        const id = params.get('preview');
        const t = parseFloat(params.get('t') || '33');
        if (DIFFS.some(d => d.id === id)) {
          this.selectDifficulty(id, false);
          this.startPreview(id, Number.isFinite(t) ? t : 33);
        }
      }

      window.__ORBIT = this;
      requestAnimationFrame(this._loop);
    }

    /* =========================================================
       setup / storage / menu
       ========================================================= */
    _cacheDom() {
      this.dom = {
        menu: $('menu'),
        songSelect: $('songSelect'),
        songList: $('songList'),
        selectSettingsBtn: $('selectSettingsBtn'),
        backToSongs: $('backToSongs'),
        menuSettingsBtn: $('menuSettingsBtn'),
        pauseSettingsBtn: $('pauseSettingsBtn'),
        settingsOverlay: $('settingsOverlay'),
        settingsVolume: $('settingsVolume'),
        settingsVolumeOut: $('settingsVolumeOut'),
        flowSlider: $('flowSlider'),
        flowOut: $('flowOut'),
        offsetSlider: $('offsetSlider'),
        offsetOut: $('offsetOut'),
        calibrateBtn: $('calibrateBtn'),
        closeSettingsBtn: $('closeSettingsBtn'),
        calibrationOverlay: $('calibrationOverlay'),
        calibTapBtn: $('calibTapBtn'),
        calibCore: $('calibCore'),
        calibBeat: $('calibBeat'),
        calibCount: $('calibCount'),
        calibValue: $('calibValue'),
        calibStatus: $('calibStatus'),
        calibStartBtn: $('calibStartBtn'),
        calibApplyBtn: $('calibApplyBtn'),
        calibCloseBtn: $('calibCloseBtn'),
        hud: $('hud'),
        pauseOverlay: $('pauseOverlay'),
        results: $('results'),
        tutorial: $('tutorial'),
        tutorialIcon: $('tutorialIcon'),
        tutorialTitle: $('tutorialTitle'),
        tutorialBody: $('tutorialBody'),
        tutorialKeys: $('tutorialKeys'),
        tutorialStep: $('tutorialStep'),
        difficultyList: $('difficultyList'),
        startBtn: $('startBtn'),
        bestLine: $('bestLine'),
        scoreDisplay: $('scoreDisplay'),
        judgedDisplay: $('judgedDisplay'),
        hudDiff: $('hudDiff'),
        progressFill: $('progressFill'),
        progressHead: $('progressHead'),
        timeNow: $('timeNow'),
        timeTotal: $('timeTotal'),
        pauseBtn: $('pauseBtn'),
        pauseScore: $('pauseScore'),
        pauseCombo: $('pauseCombo'),
        pauseAcc: $('pauseAcc'),
        volumeSlider: $('volumeSlider'),
        volumeOut: $('volumeOut'),
        pauseVolume: $('pauseVolume'),
        pauseVolumeOut: $('pauseVolumeOut'),
        resultDiff: $('resultDiff'),
        resultSong: $('resultSong'),
        rankLetter: $('rankLetter'),
        resultScore: $('resultScore'),
        resultAcc: $('resultAcc'),
        statPerfect: $('statPerfect'),
        statGood: $('statGood'),
        statMiss: $('statMiss'),
        statCombo: $('statCombo'),
        statTotal: $('statTotal'),
        resultBest: $('resultBest'),
        replayBtn: $('replayBtn'),
        backMenuBtn: $('backMenuBtn'),
        resumeBtn: $('resumeBtn'),
        restartPauseBtn: $('restartPauseBtn'),
        quitBtn: $('quitBtn')
      };
      this.keyCaps = {};
      document.querySelectorAll('.key-cap').forEach(el => {
        this.keyCaps[el.dataset.key] = el;
      });
    }

    _loadBests() {
      try {
        const parsed = JSON.parse(storageGet(STORE_BEST, '{}'));
        return parsed && typeof parsed === 'object' ? parsed : {};
      } catch (e) {
        return {};
      }
    }

    _saveBest(diffId, score, acc, maxCombo) {
      const old = this.best[diffId];
      if (score <= 0 && !old) return false;
      if (!old || score > old.score || (score === old.score && acc > old.acc)) {
        this.best[diffId] = {
          score: Math.round(score),
          acc: Number(acc.toFixed(2)),
          maxCombo
        };
        storageSet(STORE_BEST, JSON.stringify(this.best));
        return !old || score > old.score;
      }
      return false;
    }

    _buildMenu() {
      this.dom.difficultyList.innerHTML = DIFFS.map(d => {
        const chart = this.chartCache[d.id];
        const best = this.best[d.id];
        return `<button class="diff-card" type="button" data-diff="${d.id}" style="--card:${d.color}" aria-pressed="false">
          <span class="diff-en">DIFFICULTY ${String(d.level).padStart(2, '0')}</span>
          <span class="diff-name">${d.label}</span>
          <span class="diff-level">${chart.noteCount} NOTES</span>
          <span class="diff-best">${best ? 'BEST ' + fmtShort(best.score) : 'NO RECORD'}</span>
        </button>`;
      }).join('');
      this.cardEls = Array.from(this.dom.difficultyList.querySelectorAll('.diff-card'));

      this.cardEls.forEach(el => {
        el.addEventListener('click', () => this.selectDifficulty(el.dataset.diff));
      });
      this.selectDifficulty(this.selectedDiff, false);
    }

    selectDifficulty(id, persist = true) {
      if (!DIFFS.some(d => d.id === id)) return;
      this.selectedDiff = id;
      this.cardEls.forEach(el => {
        const on = el.dataset.diff === id;
        el.classList.toggle('selected', on);
        el.setAttribute('aria-pressed', on ? 'true' : 'false');
      });
      const d = DIFFS.find(x => x.id === id);
      const best = this.best[id];
      this.dom.bestLine.textContent = best
        ? `PERSONAL BEST · ${d.label} · ${fmtScore(best.score)} · ${best.acc.toFixed(2)}%`
        : `尚无记录 · ${d.label} · ${this.chartCache[id].noteCount} NOTES`;
      if (persist) storageSet(STORE_DIFF, id);
    }

    _refreshMenuBests() {
      this.cardEls.forEach(el => {
        const best = this.best[el.dataset.diff];
        const label = el.querySelector('.diff-best');
        if (label) label.textContent = best ? 'BEST ' + fmtShort(best.score) : 'NO RECORD';
      });
      this.selectDifficulty(this.selectedDiff, false);
    }

    _buildSongSelect() {
      const song = C.SONG;
      const d1 = this.chartCache.d1.noteCount;
      const d2 = this.chartCache.d2.noteCount;
      const d3 = this.chartCache.d3.noteCount;
      this.dom.songList.innerHTML = `<button class="song-card" type="button" data-song="track1" role="listitem">
        <div class="song-art">
          <span class="cover-orbit o1"></span>
          <span class="cover-orbit o2"></span>
          <span class="cover-line l1"></span>
          <span class="cover-line l2"></span>
          <span class="cover-note n1"></span>
          <span class="cover-note n2"></span>
          <span class="cover-note n3"></span>
          <span class="cover-code">TRACK 01</span>
        </div>
        <div class="song-copy">
          <span class="song-card-kicker">LOCAL TRACK / BPM ${song.bpm}</span>
          <strong class="song-card-title">${song.title}</strong>
          <span class="song-card-artist">${song.artist}</span>
          <div class="song-chips">
            <span class="song-chip">2:37</span>
            <span class="song-chip">BPM ${song.bpm}</span>
            <span class="song-chip">难度 1 · ${d1} NOTES</span>
            <span class="song-chip">难度 2 · ${d2} NOTES</span>
            <span class="song-chip">难度 3 · ${d3} NOTES</span>
          </div>
          <span class="song-pick">选择这首曲目 <b>→</b></span>
        </div>
      </button>`;
      const card = this.dom.songList.querySelector('.song-card');
      if (card) card.addEventListener('click', () => this._showMenu(false));
    }

    _showSongSelect(instant) {
      this.mode = 'songselect';
      this.settingsOpen = false;
      this.calibrationOpen = false;
      this._stopCalibration();
      this.dom.songSelect.classList.remove('hidden');
      this.dom.menu.classList.add('hidden');
      this.dom.hud.classList.add('hidden');
      this.dom.pauseOverlay.classList.add('hidden');
      this.dom.results.classList.add('hidden');
      this.dom.settingsOverlay.classList.add('hidden');
      this.dom.calibrationOverlay.classList.add('hidden');
      this.dom.tutorial.classList.add('hidden');
      if (instant) this.clock = 0;
    }

    _syncVolumeUI() {
      this.dom.volumeSlider.value = String(this.volume);
      this.dom.pauseVolume.value = String(this.volume);
      this.dom.settingsVolume.value = String(this.volume);
      this.dom.volumeOut.textContent = String(this.volume);
      this.dom.pauseVolumeOut.textContent = String(this.volume);
      this.dom.settingsVolumeOut.textContent = String(this.volume);
      this.audio.setVolume(this.volume);
    }

    setVolume(v) {
      this.volume = Math.round(clamp(Number(v) || 0, 0, 100));
      storageSet(STORE_VOLUME, String(this.volume));
      this.dom.volumeSlider.value = String(this.volume);
      this.dom.pauseVolume.value = String(this.volume);
      this.dom.settingsVolume.value = String(this.volume);
      this.dom.volumeOut.textContent = String(this.volume);
      this.dom.pauseVolumeOut.textContent = String(this.volume);
      this.dom.settingsVolumeOut.textContent = String(this.volume);
      this.audio.setVolume(this.volume);
    }

    _syncPlaybackUI() {
      this.dom.flowSlider.value = this.flowSpeed.toFixed(1);
      this.dom.flowOut.textContent = 'x' + this.flowSpeed.toFixed(1);
      this.dom.offsetSlider.value = String(this.offsetMs);
      this.dom.offsetOut.textContent = (this.offsetMs >= 0 ? '+' : '') + this.offsetMs + ' ms';
    }

    setFlowSpeed(v) {
      this.flowSpeed = clamp(Math.round(Number(v) * 10) / 10, 1, 5);
      storageSet(STORE_FLOW, String(this.flowSpeed));
      this._syncPlaybackUI();
    }

    setOffsetMs(v) {
      this.offsetMs = Math.round(clamp(Number(v) || 0, -200, 200));
      storageSet(STORE_OFFSET, String(this.offsetMs));
      this._syncPlaybackUI();
    }

    openSettings() {
      if (this.mode === 'playing') return;
      this.settingsOpen = true;
      this._syncVolumeUI();
      this._syncPlaybackUI();
      this.dom.settingsOverlay.classList.remove('hidden');
    }

    closeSettings() {
      this.settingsOpen = false;
      this._closeCalibration(true);
      this.dom.settingsOverlay.classList.add('hidden');
    }

    _travelTime() {
      return 4 / this.flowSpeed;
    }

    /* =========================================================
       latency calibration: tap once every 3rd beat
       ========================================================= */
    _openCalibration() {
      this.settingsOpen = true;
      this.calibrationOpen = true;
      this.dom.calibrationOverlay.classList.remove('hidden');
      this._resetCalibrationUI();
    }

    _resetCalibrationUI() {
      if (this.calib && this.calib.ctx) {
        try { this.calib.ctx.close(); } catch (e) { /* ignore */ }
      }
      if (this.calib) {
        clearInterval(this.calib.interval);
        clearTimeout(this.calib.startTimer);
      }
      this.calib = null;
      this.dom.calibBeat.textContent = '—';
      this.dom.calibCount.textContent = '0 / 8';
      this.dom.calibValue.textContent = '—';
      this.dom.calibStatus.textContent = '点击“开始”播放校准节拍。每 3 拍点击一次圆圈。';
      this.dom.calibStartBtn.textContent = '开始';
      this.dom.calibApplyBtn.disabled = true;
      this.dom.calibTapBtn.classList.remove('beat', 'strong');
      this.dom.calibCore.textContent = '点击';
    }

    _playCalibrationClick(strong) {
      const ctx = this.calib && this.calib.ctx;
      if (!ctx) return;
      const t = ctx.currentTime;
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(strong ? 1568 : 880, t);
      gain.gain.setValueAtTime(.0001, t);
      gain.gain.exponentialRampToValueAtTime(strong ? .09 : .035, t + .003);
      gain.gain.exponentialRampToValueAtTime(.0001, t + .06);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(t);
      osc.stop(t + .08);
    }

    async _startCalibration() {
      if (this.calib && this.calib.running) {
        this._resetCalibrationUI();
      }
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) {
        this.dom.calibStatus.textContent = '当前浏览器不支持音频校准。';
        return;
      }
      let ctx;
      try {
        ctx = new AC();
        await ctx.resume();
      } catch (e) {
        this.dom.calibStatus.textContent = '无法启动校准音频，请检查系统音频。';
        return;
      }
      this.calib = {
        ctx,
        running: true,
        beatMs: 500,
        beatIndex: 0,
        strongTimes: [],
        taps: [],
        suggested: null,
        interval: null,
        startTimer: null
      };
      this.dom.calibCount.textContent = '0 / 8';
      this.dom.calibValue.textContent = '—';
      this.dom.calibApplyBtn.disabled = true;
      this.dom.calibStatus.textContent = '准备中……听到强拍后点击圆圈。';
      this.dom.calibStartBtn.textContent = '重新开始';
      this.dom.calibCore.textContent = '等待';

      const tick = () => {
        if (!this.calib || !this.calib.running) return;
        const strong = this.calib.beatIndex % 3 === 2;
        this._playCalibrationClick(strong);
        if (strong) {
          this.calib.strongTimes.push({ t: performance.now(), used: false });
          if (this.calib.strongTimes.length > 24) this.calib.strongTimes.shift();
          this.dom.calibBeat.textContent = '强拍';
        } else {
          this.dom.calibBeat.textContent = String((this.calib.beatIndex % 3) + 1);
        }
        this.dom.calibTapBtn.classList.remove('beat', 'strong');
        void this.dom.calibTapBtn.offsetWidth;
        this.dom.calibTapBtn.classList.add(strong ? 'strong' : 'beat');
        this.dom.calibTapBtn.classList.toggle('strong', strong);
        this.calib.beatIndex++;
      };

      this.calib.startTimer = setTimeout(() => {
        if (!this.calib || !this.calib.running) return;
        this.dom.calibStatus.textContent = '跟着节拍：每 3 拍点击一次圆圈。';
        this.dom.calibCore.textContent = '点击';
        tick();
        this.calib.interval = setInterval(tick, this.calib.beatMs);
      }, 900);
    }

    _tapCalibration() {
      if (!this.calib || !this.calib.running) {
        this.dom.calibStatus.textContent = '请先点击“开始”，再跟随强拍点击。';
        return;
      }
      const now = performance.now();
      const strong = this.calib.strongTimes
        .filter(s => !s.used && Math.abs(now - s.t) <= 320)
        .sort((a, b) => Math.abs(now - a.t) - Math.abs(now - b.t))[0];
      this.dom.calibTapBtn.classList.remove('beat', 'strong');
      void this.dom.calibTapBtn.offsetWidth;
      this.dom.calibTapBtn.classList.add('beat');
      if (!strong) {
        this.dom.calibStatus.textContent = '请等强拍再点击。跟着“强拍”提示。';
        return;
      }
      strong.used = true;
      this.calib.taps.push(now - strong.t);
      const count = this.calib.taps.length;
      this.dom.calibCount.textContent = `${Math.min(count, 8)} / 8`;
      this.dom.calibStatus.textContent = count < 8
        ? '已记录。继续每 3 拍点击一次。'
        : '校准完成。';
      if (count >= 8) this._finishCalibration();
    }

    _finishCalibration() {
      clearInterval(this.calib.interval);
      clearTimeout(this.calib.startTimer);
      this.calib.running = false;
      const taps = this.calib.taps.slice(2);
      const avg = taps.reduce((a, b) => a + b, 0) / Math.max(1, taps.length);
      const suggested = Math.round(clamp(avg, -200, 200));
      this.calib.suggested = suggested;
      this.dom.calibValue.textContent = (suggested >= 0 ? '+' : '') + suggested + ' ms';
      this.dom.calibStatus.textContent = `校准完成，建议偏移 ${suggested >= 0 ? '+' : ''}${suggested}ms。可以应用该值。`;
      this.dom.calibApplyBtn.disabled = false;
      this.dom.calibStartBtn.textContent = '重新开始';
      this.dom.calibCore.textContent = '完成';
    }

    _closeCalibration(fromSettings) {
      const had = !!this.calib;
      if (this.calib) {
        this.calib.running = false;
        clearInterval(this.calib.interval);
        clearTimeout(this.calib.startTimer);
        try { this.calib.ctx.close(); } catch (e) { /* ignore */ }
        this.calib = null;
      }
      this.calibrationOpen = false;
      this.dom.calibrationOverlay.classList.add('hidden');
      if (!fromSettings && this.settingsOpen) this.dom.settingsOverlay.classList.remove('hidden');
      if (had) {
        this.dom.calibStatus.textContent = '已关闭校准音频。';
        this.dom.calibApplyBtn.disabled = true;
      }
    }

    _stopCalibration() {
      if (this.calib) {
        this.calib.running = false;
        clearInterval(this.calib.interval);
        clearTimeout(this.calib.startTimer);
        try { this.calib.ctx.close(); } catch (e) { /* ignore */ }
        this.calib = null;
      }
    }

    /* =========================================================
       events
       ========================================================= */
    _bindEvents() {
      window.addEventListener('resize', () => this.resize());

      this.dom.startBtn.addEventListener('click', () => this.startGame());
      this.dom.pauseBtn.addEventListener('click', () => this.pauseGame());
      this.dom.resumeBtn.addEventListener('click', () => this.resumeGame());
      this.dom.restartPauseBtn.addEventListener('click', () => this.startGame(this.selectedDiff));
      this.dom.quitBtn.addEventListener('click', () => this.quitToMenu());
      this.dom.replayBtn.addEventListener('click', () => this.startGame(this.selectedDiff));
      this.dom.backMenuBtn.addEventListener('click', () => this.quitToMenu());
      this.dom.backToSongs.addEventListener('click', () => this._showSongSelect(false));
      this.dom.selectSettingsBtn.addEventListener('click', () => this.openSettings());
      this.dom.menuSettingsBtn.addEventListener('click', () => this.openSettings());
      this.dom.pauseSettingsBtn.addEventListener('click', () => this.openSettings());
      this.dom.closeSettingsBtn.addEventListener('click', () => this.closeSettings());
      this.dom.calibrateBtn.addEventListener('click', () => this._openCalibration());
      this.dom.calibStartBtn.addEventListener('click', () => this._startCalibration());
      this.dom.calibTapBtn.addEventListener('click', () => this._tapCalibration());
      this.dom.calibApplyBtn.addEventListener('click', () => {
        if (this.calib && Number.isFinite(this.calib.suggested)) {
          this.setOffsetMs(this.calib.suggested);
          this.dom.calibStatus.textContent = '已应用建议偏移。可以关闭窗口继续游戏。';
        }
      });
      this.dom.calibCloseBtn.addEventListener('click', () => this._closeCalibration());

      const onVolume = (e) => this.setVolume(e.target.value);
      this.dom.volumeSlider.addEventListener('input', onVolume);
      this.dom.pauseVolume.addEventListener('input', onVolume);
      this.dom.settingsVolume.addEventListener('input', onVolume);
      this.dom.flowSlider.addEventListener('input', (e) => this.setFlowSpeed(e.target.value));
      this.dom.offsetSlider.addEventListener('input', (e) => this.setOffsetMs(e.target.value));

      window.addEventListener('keydown', (e) => this._onKeyDown(e));

      document.addEventListener('visibilitychange', () => {
        if (document.hidden && this.mode === 'playing') this.pauseGame();
      });
      window.addEventListener('blur', () => {
        if (this.mode === 'playing') this.pauseGame();
      });
    }

    _onKeyDown(e) {
      const tag = e.target && e.target.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') {
        if (e.code === 'Escape') {
          if (this.calibrationOpen) this._closeCalibration();
          else if (this.settingsOpen) this.closeSettings();
          else if (this.mode === 'paused') this.resumeGame();
        }
        return;
      }
      if (e.repeat) {
        if (['Space', 'Escape'].includes(e.code) || e.code.startsWith('Arrow')) e.preventDefault();
        return;
      }

      if (this.calibrationOpen) {
        if (e.code === 'Space') {
          e.preventDefault();
          this._tapCalibration();
        } else if (e.code === 'Escape') {
          e.preventDefault();
          this._closeCalibration();
        }
        return;
      }

      if (this.settingsOpen) {
        if (e.code === 'Escape') {
          e.preventDefault();
          this.closeSettings();
        }
        return;
      }

      if (this.mode === 'songselect') {
        if (e.code === 'Enter' || e.code === 'Space') {
          e.preventDefault();
          this._showMenu(false);
        }
        return;
      }

      if (this.mode === 'menu') {
        if (e.code === 'Enter' || e.code === 'Space') {
          e.preventDefault();
          this.startGame();
        }
        return;
      }

      if (this.mode === 'results') {
        if (e.code === 'KeyR' || e.code === 'Enter') {
          e.preventDefault();
          this.startGame(this.selectedDiff);
        } else if (e.code === 'Escape') {
          e.preventDefault();
          this.quitToMenu();
        }
        return;
      }

      if (this.mode === 'paused') {
        if (e.code === 'Escape' || e.code === 'Space') {
          e.preventDefault();
          this.resumeGame();
        }
        return;
      }

      if (this.mode === 'preview') {
        if (e.code === 'Escape') {
          e.preventDefault();
          this.quitToMenu();
        }
        return;
      }

      if (this.mode !== 'playing') return;

      if (e.code === 'Escape' || e.code === 'Space') {
        e.preventDefault();
        this.pauseGame();
        return;
      }
      if (e.ctrlKey || e.metaKey || e.altKey) return;

      const codeMap = {
        KeyQ: 'q', KeyW: 'w', KeyE: 'e', KeyR: 'r',
        KeyU: 'u', KeyI: 'i', KeyO: 'o', KeyP: 'p'
      };
      const key = codeMap[e.code];
      if (key && KEY_COLOR[key]) {
        e.preventDefault();
        this.pressKey(key);
      }
    }

    /* =========================================================
       flow
       ========================================================= */
    _showMenu(instant) {
      this.mode = 'menu';
      this.preview = false;
      this.chart = null;
      this.settingsOpen = false;
      this.calibrationOpen = false;
      this._stopCalibration();
      this.particles.length = 0;
      this.judgments.length = 0;
      this.shockwaves.length = 0;
      this.ringFlashes.length = 0;
      this.dom.songSelect.classList.add('hidden');
      this.dom.menu.classList.remove('hidden');
      this.dom.hud.classList.add('hidden');
      this.dom.pauseOverlay.classList.add('hidden');
      this.dom.results.classList.add('hidden');
      this.dom.settingsOverlay.classList.add('hidden');
      this.dom.calibrationOverlay.classList.add('hidden');
      this.dom.tutorial.classList.add('hidden');
      this._refreshMenuBests();
      if (instant) this.clock = 0;
    }

    startGame(diffId) {
      const nowMs = performance.now();
      if (this._startLockUntil && nowMs < this._startLockUntil) return;
      this._startLockUntil = nowMs + 450;

      const id = diffId || this.selectedDiff;
      if (!DIFFS.some(d => d.id === id)) return;
      this.selectedDiff = id;
      storageSet(STORE_DIFF, id);
      this.runId++;
      const runId = this.runId;

      this.chart = this.chartCache[id];
      this.playNotes = this.chart.notes.map(n => Object.assign({}, n, {
        status: 'pending',
        grade: null,
        hitAt: 0
      }));

      this.totalNotes = this.playNotes.length;
      this.score = 0;
      this.combo = 0;
      this.maxCombo = 0;
      this.judged = 0;
      this.weightedSum = 0;
      this.counts = { perfect: 0, good: 0, miss: 0 };
      this.lastBeat = -1;
      this.songTime = 0;
      this.beatPulse = 0;
      this.missFlash = 0;
      this.shake = 0;
      this.corePulse = 0;
      this.corePop = 0;
      this.previewAcc = null;
      this.particles.length = 0;
      this.shockwaves.length = 0;
      this.judgments.length = 0;
      this.ringFlashes.length = 0;
      this.silentMode = false;
      this.coreR = this.noteR * 1.5;
      this.tutorialIndex = -1;
      this.dom.tutorial.classList.add('hidden');

      this.dom.menu.classList.add('hidden');
      this.dom.songSelect.classList.add('hidden');
      this.dom.results.classList.add('hidden');
      this.dom.pauseOverlay.classList.add('hidden');
      this.dom.settingsOverlay.classList.add('hidden');
      this.dom.calibrationOverlay.classList.add('hidden');
      this.dom.hud.classList.remove('hidden');
      this.dom.timeTotal.textContent = C.formatTime(DURATION);
      this.dom.hudDiff.textContent = this.chart.difficulty.label;
      this.updateHUD(true);

      if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
      this.mode = 'playing';
      this._updateTutorial(0);

      this.audio.onEnded = () => {
        if (this.mode === 'playing') this.endGame();
      };
      this.audio.stop(0);
      this.audio.start(this.volume).then(() => {
        if (runId !== this.runId) return;
      }).catch((err) => {
        console.warn('Audio start failed:', err);
        if (runId !== this.runId) return;
        this.audio.stop(0);
        this.silentMode = true;
        this.silentStart = performance.now();
        this.showToast('音频未能启动，请确认 assets/track.mp3 存在后刷新页面。');
      });
    }

    startPreview(id, t) {
      this.runId++;
      this.audio.stop(0);
      this.chart = this.chartCache[id];
      this.playNotes = this.chart.notes.map(n => Object.assign({}, n, {
        status: 'pending', grade: null, hitAt: 0
      }));
      this.totalNotes = this.playNotes.length;
      this.score = 0;
      this.combo = this.previewCombo || 0;
      this.maxCombo = this.combo;
      this.judged = 0;
      this.weightedSum = 0;
      this.counts = { perfect: 0, good: 0, miss: 0 };
      this.previewTime = clamp(t, 0, DURATION);
      this.songTime = this.previewTime;
      this.preview = true;
      this.previewAcc = 98.6;
      this.mode = 'preview';
      this.coreR = this.noteR * (1.5 + (1 - Math.exp(-this.combo / 26)));
      this.tutorialIndex = -1;
      this.dom.menu.classList.add('hidden');
      this.dom.songSelect.classList.add('hidden');
      this.dom.hud.classList.remove('hidden');
      this.dom.tutorial.classList.add('hidden');
      this.dom.hudDiff.textContent = this.chart.difficulty.label;
      this.dom.timeTotal.textContent = C.formatTime(DURATION);
      this.updateHUD(true);
      this._updateTutorial(this.previewTime);
    }

    async pauseGame() {
      if (this.mode !== 'playing') return;
      this.timeFrozen = this.getGameTime();
      this.songTime = this.timeFrozen;
      this.mode = 'paused';
      this.dom.pauseScore.textContent = fmtScore(this.score);
      this.dom.pauseCombo.textContent = String(this.combo);
      this.dom.pauseAcc.textContent = this.displayAccuracy().toFixed(2) + '%';
      this.dom.pauseOverlay.classList.remove('hidden');
      if (!this.silentMode) await this.audio.pause();
    }

    async resumeGame() {
      if (this.mode !== 'paused') return;
      this.dom.pauseOverlay.classList.add('hidden');
      this.mode = 'playing';
      if (this.silentMode) {
        this.silentStart = performance.now() - this.timeFrozen * 1000;
      } else {
        await this.audio.resume();
      }
      this.lastFrame = performance.now();
      if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
    }

    quitToMenu() {
      this.runId++;
      this.audio.stop(.3);
      this._showMenu(false);
    }

    endGame() {
      if (this.mode !== 'playing') return;
      this.mode = 'results';
      this.audio.stop(1.2);

      for (const n of this.playNotes) {
        if (n.status === 'pending') this._registerMiss(n, true);
      }
      this.updateHUD(true);
      this.dom.hud.classList.add('hidden');
      this.dom.tutorial.classList.add('hidden');

      const acc = this.accuracy();
      const grade = this._rank(acc);
      const diff = this.chart.difficulty;
      const isNew = this._saveBest(diff.id, this.score, acc, this.maxCombo);
      const best = this.best[diff.id] || { score: 0, acc: 0, maxCombo: 0 };

      this.dom.resultSong.textContent = this.chart.title;
      this.dom.resultDiff.textContent = diff.label;
      this.dom.rankLetter.textContent = grade;
      this.dom.resultScore.textContent = fmtScore(this.score);
      this.dom.resultAcc.textContent = acc.toFixed(2) + '%';
      this.dom.statPerfect.textContent = String(this.counts.perfect);
      this.dom.statGood.textContent = String(this.counts.good);
      this.dom.statMiss.textContent = String(this.counts.miss);
      this.dom.statCombo.textContent = String(this.maxCombo);
      this.dom.statTotal.textContent = String(this.totalNotes);
      this.dom.resultBest.textContent = `${isNew ? 'NEW PERSONAL BEST' : 'PERSONAL BEST'} · ${fmtScore(best.score)} · ${best.acc.toFixed(2)}%`;
      this.dom.resultBest.classList.toggle('new', isNew);

      const rankEl = this.dom.rankLetter;
      rankEl.style.animation = 'none';
      void rankEl.offsetHeight;
      rankEl.style.animation = '';

      this.dom.results.classList.remove('hidden');
      this._refreshMenuBests();
    }

    _rank(acc) {
      if (acc >= 98) return 'S';
      if (acc >= 95) return 'A';
      if (acc >= 91) return 'B';
      if (acc >= 85) return 'C';
      return 'D';
    }

    getGameTime() {
      if (this.preview) return this.previewTime;
      if (this.mode === 'paused') return this.timeFrozen || 0;
      if (this.silentMode) return Math.max(0, (performance.now() - this.silentStart) / 1000);
      return this.audio.songTime;
    }

    /* =========================================================
       judgement
       ========================================================= */
    accuracy() {
      if (!this.judged) return 100;
      return clamp((this.weightedSum / this.judged) * 100, 0, 100);
    }

    displayAccuracy() {
      if (this.preview && this.previewAcc !== null) return this.previewAcc;
      return this.accuracy();
    }

    pressKey(key) {
      if (this.mode !== 'playing') return;
      const color = KEY_COLOR[key];
      if (!color) return;
      const visualT = this.getGameTime();
      const judgeT = visualT - this.offsetMs / 1000;
      this.pulseKey(key);

      let best = null;
      let bestKey = Infinity;
      for (const n of this.playNotes) {
        if (n.status !== 'pending') continue;
        if (n.type !== 'white' && n.type !== color) continue;
        const dt = Math.abs(n.time - judgeT);
        const ms = Math.round(dt * 1000);
        if (ms > 60) continue;
        if (ms < bestKey) {
          bestKey = ms;
          best = n;
        }
      }

      if (!best) {
        this._emptyTap(color, visualT);
        return;
      }

      const delta = judgeT - best.time;
      const ms = Math.round(Math.abs(delta) * 1000);
      const grade = ms <= 40 ? 'perfect' : 'good';
      best.status = 'hit';
      best.grade = grade;
      best.hitAt = judgeT;

      const prevCombo = this.combo;
      this.combo++;
      this.maxCombo = Math.max(this.maxCombo, this.combo);
      this.judged++;
      this.counts[grade]++;
      this.weightedSum += ACC_WEIGHT[grade];
      const gain = Math.round(BASE_SCORE[grade] * (1 + Math.min(prevCombo, 100) * .005));
      this.score += gain;

      const scene = this._sceneState(visualT);
      const x = scene.cx;
      const y = scene.cy;

      this._addBurst(x, y, best.type, grade);
      this._addShockwave(x, y, best.type);
      this.ringFlashes.push({
        rel: -Math.PI / 2,
        color: NOTE[best.type].main,
        life: .34,
        maxLife: .34
      });
      this.shake = Math.min(4, this.shake + (grade === 'perfect' ? .5 : .9));
      this.corePulse = 1;
      this.corePop = 1;

      this.showJudgment(grade, delta, best.type, scene);
      this.updateHUD();
    }

    _emptyTap(color, t) {
      const scene = this._sceneState(t);
      this.ringFlashes.push({
        rel: -Math.PI / 2 + (color === 'red' ? -.18 : .18),
        color: color === 'red' ? '#ff4d73' : '#49ccff',
        life: .14,
        maxLife: .14
      });
    }

    _registerMiss(note, silent) {
      if (note.status !== 'pending') return;
      note.status = 'miss';
      note.grade = 'miss';
      this.combo = 0;
      this.judged++;
      this.counts.miss++;
      this.weightedSum += ACC_WEIGHT.miss;
      this.missFlash = Math.min(1, this.missFlash + (silent ? .1 : .55));
      if (!silent) {
        this.shake = Math.min(6, this.shake + 2);
        const scene = this._sceneState(this.getGameTime());
        const x = scene.cx;
        const y = scene.cy;
        this._addBurst(x, y, 'miss', 'miss');
        this.showJudgment('miss', 0, 'white', scene);
        this.corePulse = .35;
      }
      this.updateHUD();
    }

    /* =========================================================
       HUD
       ========================================================= */
    updateHUD(force) {
      const scoreText = fmtScore(this.score || 0);
      if (force || this._hudScore !== scoreText) {
        this.dom.scoreDisplay.textContent = scoreText;
        this._hudScore = scoreText;
      }

      const judgedText = `${this.judged || 0} / ${this.totalNotes || 0}`;
      if (force || this._hudJudged !== judgedText) {
        this.dom.judgedDisplay.textContent = judgedText;
        this._hudJudged = judgedText;
      }

      const t = this.mode === 'preview' ? this.previewTime : Math.max(0, this.songTime || 0);
      const pct = clamp(t / DURATION, 0, 1) * 100;
      this.dom.progressFill.style.width = pct.toFixed(3) + '%';
      this.dom.progressHead.style.left = pct.toFixed(3) + '%';
      const nowText = C.formatTime(t);
      if (force || this._hudTime !== nowText) {
        this.dom.timeNow.textContent = nowText;
        this._hudTime = nowText;
      }
    }

    _updateTutorial(t) {
      const list = this.chart && this.chart.tutorial;
      const el = this.dom.tutorial;
      if (!list || !list.length) {
        el.classList.add('hidden');
        this.tutorialIndex = -1;
        return;
      }
      let idx = -1;
      for (let i = 0; i < list.length; i++) {
        if (t >= list[i].start && t < list[i].end) {
          idx = i;
          break;
        }
      }
      if (idx < 0) {
        el.classList.add('hidden');
        this.tutorialIndex = -1;
        return;
      }
      if (idx === this.tutorialIndex) {
        el.classList.remove('hidden');
        return;
      }
      const step = list[idx];
      this.tutorialIndex = idx;
      this.dom.tutorialTitle.textContent = step.title;
      this.dom.tutorialBody.textContent = step.body;
      this.dom.tutorialStep.textContent = `教学 ${idx + 1}/${list.length}`;
      this.dom.tutorialIcon.className = 'tutorial-icon ' + (step.type || 'mixed');
      this.dom.tutorialKeys.innerHTML = (step.keys || []).map(k => {
        const c = KEY_COLOR[k.toLowerCase()] || 'white';
        return `<kbd class="tutorial-key ${c}">${k}</kbd>`;
      }).join('');
      el.classList.remove('hidden');
    }

    pulseKey(key) {
      const el = this.keyCaps[key];
      if (!el) return;
      el.classList.remove('active');
      void el.offsetWidth;
      el.classList.add('active');
      clearTimeout(el._activeTimer);
      el._activeTimer = setTimeout(() => el.classList.remove('active'), 100);
    }

    showToast(message) {
      const el = document.createElement('div');
      el.className = 'toast';
      el.textContent = message;
      document.getElementById('app').appendChild(el);
      requestAnimationFrame(() => el.classList.add('show'));
      setTimeout(() => {
        el.classList.remove('show');
        setTimeout(() => el.remove(), 320);
      }, 3600);
    }

    /* =========================================================
       scene / effects
       ========================================================= */
    _sceneState(time) {
      const chart = this.chart || this.chartCache[this.selectedDiff];
      const ring = C.ringAt(chart, Math.max(0, time));
      const cx = ring.x * this.w;
      const cy = ring.y * this.h;
      const R = this.coreR || this.noteR * 1.5;
      const lines = chart.lines.map(line => {
        const state = C.lineAt(line, Math.max(0, time));
        return {
          line,
          tint: line.tint || '#9ac9ff',
          angle: state.angle,
          length: this.lineBase * state.lengthFactor
        };
      });
      return {
        cx, cy, R,
        rot: ring.rot,
        lines,
        noteR: this.noteR,
        heat: new Array(lines.length).fill(0)
      };
    }

    _addBurst(x, y, type, grade) {
      const palette = type === 'white'
        ? [NOTE.white.main, NOTE.red.main, NOTE.blue.main]
        : type === 'miss'
          ? ['#767d99', '#aab2ce']
          : [NOTE[type].main, NOTE[type].light];
      const power = grade === 'perfect' ? 1.15 : grade === 'good' ? .95 : .6;
      const count = grade === 'miss' ? 7 : 14;
      for (let i = 0; i < count; i++) {
        const a = Math.random() * TAU;
        const speed = (45 + Math.random() * 200) * power;
        this.particles.push({
          x, y,
          vx: Math.cos(a) * speed,
          vy: Math.sin(a) * speed - 16,
          size: 1 + Math.random() * 2.2,
          life: .32 + Math.random() * .4,
          maxLife: .72,
          color: palette[Math.floor(Math.random() * palette.length)],
          streak: Math.random() < .3
        });
      }
    }

    _addShockwave(x, y, type) {
      const color = type === 'miss' ? '#8d93aa' : NOTE[type].main;
      this.shockwaves.push({
        x, y, r: 5,
        maxR: type === 'white' ? 46 : 38,
        life: .36, maxLife: .36, color
      });
    }

    showJudgment(grade, delta, type, scene) {
      const last = this.judgments[this.judgments.length - 1];
      if (last && last.grade === grade && this.clock - last.born < .09) {
        last.count = Math.min(9, (last.count || 1) + 1);
        last.life = last.maxLife;
        last.born = this.clock;
        return;
      }
      let sub = '';
      if (grade === 'good') {
        const ms = Math.round(Math.abs(delta) * 1000);
        sub = (delta < 0 ? 'EARLY' : 'LATE') + ' · ' + ms + 'ms';
      }
      this.judgments.push({
        grade,
        text: LABELS[grade],
        color: grade === 'miss' ? JCOLORS.miss : JCOLORS[grade],
        x: scene.cx,
        y: Math.max(82, scene.cy - scene.R - 28),
        life: .72,
        maxLife: .72,
        count: 1,
        sub,
        born: this.clock
      });
      if (this.judgments.length > 5) this.judgments.shift();
    }

    _updateEffects(dt) {
      for (let i = this.particles.length - 1; i >= 0; i--) {
        const p = this.particles[i];
        p.life -= dt;
        if (p.life <= 0) {
          this.particles.splice(i, 1);
          continue;
        }
        p.x += p.vx * dt;
        p.y += p.vy * dt;
        p.vx *= Math.exp(-2.4 * dt);
        p.vy *= Math.exp(-2.4 * dt);
        p.vy += 18 * dt;
      }
      for (let i = this.shockwaves.length - 1; i >= 0; i--) {
        const s = this.shockwaves[i];
        s.life -= dt;
        if (s.life <= 0) this.shockwaves.splice(i, 1);
      }
      for (let i = this.judgments.length - 1; i >= 0; i--) {
        const j = this.judgments[i];
        j.life -= dt;
        if (j.life <= 0) this.judgments.splice(i, 1);
      }
      for (let i = this.ringFlashes.length - 1; i >= 0; i--) {
        this.ringFlashes[i].life -= dt;
        if (this.ringFlashes[i].life <= 0) this.ringFlashes.splice(i, 1);
      }
      this.shake *= Math.exp(-7 * dt);
      this.missFlash *= Math.exp(-3.2 * dt);
      this.corePulse *= Math.exp(-8 * dt);
      this.corePop *= Math.exp(-10 * dt);
      this.beatPulse *= Math.exp(-7 * dt);
    }

    /* =========================================================
       main loop / update
       ========================================================= */
    _loop = (ts) => {
      const raw = (ts - this.lastFrame) / 1000;
      const dt = clamp(Number.isFinite(raw) ? raw : 0, 0, .05);
      this.lastFrame = ts;

      if (this.mode !== 'paused') this.clock += dt;

      if (this.mode === 'playing') {
        this.songTime = this.getGameTime();
        this._updatePlaying(dt);
        this._updateEffects(dt);
      } else if (this.mode === 'results') {
        this._updateEffects(dt);
      } else if (this.mode === 'preview') {
        this.songTime = this.previewTime;
        this._updateEffects(dt);
      }

      this._render();
      requestAnimationFrame(this._loop);
    };

    _updatePlaying(dt) {
      const t = this.songTime;
      if (!Number.isFinite(t)) return;

      if (t >= 0) {
        const beat = Math.floor(t / BEAT);
        if (beat !== this.lastBeat) {
          this.lastBeat = beat;
          this.beatPulse = 1;
        }

        const target = this.noteR * (1.5 + (1 - Math.exp(-this.combo / 26)));
        this.coreR += (target - this.coreR) * (1 - Math.exp(-13 * dt));

        const judgeT = t - this.offsetMs / 1000;
        for (const n of this.playNotes) {
          if (n.status === 'pending' && judgeT - n.time > JUDGE.good + .0005) {
            this._registerMiss(n, false);
          }
        }
      }

      this.updateHUD();
      this._updateTutorial(t);
      if (t >= DURATION + 1.65) this.endGame();
    }

    /* =========================================================
       rendering primitives
       ========================================================= */
    resize() {
      const oldNoteR = this.noteR;
      this.w = window.innerWidth;
      this.h = window.innerHeight;
      this.dpr = clamp(window.devicePixelRatio || 1, 1, 2);
      this.canvas.width = Math.max(1, Math.round(this.w * this.dpr));
      this.canvas.height = Math.max(1, Math.round(this.h * this.dpr));
      this.c.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);

      this.noteR = clamp(Math.min(this.w, this.h) * .03, 16, 28);
      this.lineBase = Math.min(this.w, this.h) * .45;
      if (this.coreR > 0) this.coreR *= this.noteR / oldNoteR;
      else this.coreR = this.noteR * 1.5;
      if (!Number.isFinite(this.coreR)) this.coreR = this.noteR * 1.5;

      if (!this.stars.length) this._makeStars();
      this._makeBackground();
    }

    _makeStars() {
      this.stars = [];
      const count = this.w < 700 ? 80 : 150;
      for (let i = 0; i < count; i++) {
        this.stars.push({
          x: Math.random(),
          y: Math.random(),
          r: .35 + Math.random() * 1.5,
          a: .2 + Math.random() * .65,
          phase: Math.random() * TAU,
          speed: .25 + Math.random() * .9,
          drift: 1.5 + Math.random() * 5,
          sway: 1 + Math.random() * 6,
          big: Math.random() < .08
        });
      }
    }

    _makeBackground() {
      const w = Math.max(1, this.w);
      const h = Math.max(1, this.h);
      const bg = document.createElement('canvas');
      bg.width = w;
      bg.height = h;
      const g = bg.getContext('2d');

      const base = g.createLinearGradient(0, 0, w * .8, h);
      base.addColorStop(0, '#080d1e');
      base.addColorStop(.45, '#050815');
      base.addColorStop(1, '#03050d');
      g.fillStyle = base;
      g.fillRect(0, 0, w, h);

      const nebula = g.createRadialGradient(w * .76, h * .34, 0, w * .76, h * .34, Math.max(w, h) * .62);
      nebula.addColorStop(0, 'rgba(85,57,170,.20)');
      nebula.addColorStop(.38, 'rgba(55,40,130,.11)');
      nebula.addColorStop(1, 'rgba(0,0,0,0)');
      g.fillStyle = nebula;
      g.fillRect(0, 0, w, h);

      const teal = g.createRadialGradient(w * .08, h * .92, 0, w * .08, h * .92, Math.max(w, h) * .45);
      teal.addColorStop(0, 'rgba(27,139,146,.12)');
      teal.addColorStop(1, 'rgba(0,0,0,0)');
      g.fillStyle = teal;
      g.fillRect(0, 0, w, h);

      const crimson = g.createRadialGradient(w * .95, h * .88, 0, w * .95, h * .88, Math.max(w, h) * .35);
      crimson.addColorStop(0, 'rgba(126,31,73,.10)');
      crimson.addColorStop(1, 'rgba(0,0,0,0)');
      g.fillStyle = crimson;
      g.fillRect(0, 0, w, h);

      const horizonY = h * .73;
      const horizon = g.createLinearGradient(0, horizonY - 50, 0, horizonY + 90);
      horizon.addColorStop(0, 'rgba(93,148,255,0)');
      horizon.addColorStop(.5, 'rgba(93,148,255,.028)');
      horizon.addColorStop(1, 'rgba(93,148,255,0)');
      g.fillStyle = horizon;
      g.fillRect(0, horizonY - 50, w, 140);

      const vig = g.createRadialGradient(w * .5, h * .48, Math.min(w, h) * .16, w * .5, h * .5, Math.max(w, h) * .76);
      vig.addColorStop(0, 'rgba(0,0,0,0)');
      vig.addColorStop(.72, 'rgba(1,2,8,.20)');
      vig.addColorStop(1, 'rgba(1,2,8,.76)');
      g.fillStyle = vig;
      g.fillRect(0, 0, w, h);

      this.bgCanvas = bg;
    }

    _drawBackground() {
      const c = this.c;
      if (this.bgCanvas) c.drawImage(this.bgCanvas, 0, 0, this.w, this.h);
      c.save();
      c.globalCompositeOperation = 'lighter';
      const t = this.clock;
      for (const s of this.stars) {
        const x = s.x * this.w + Math.sin(t * .07 * s.speed + s.phase) * s.sway;
        const y = (s.y * this.h + t * s.drift) % this.h;
        const a = s.a * (.5 + .5 * Math.sin(t * s.speed + s.phase));
        if (a <= .01) continue;
        c.fillStyle = `rgba(196,214,255,${a.toFixed(3)})`;
        if (s.big) {
          c.fillRect(x - .8, y - 3, 1.6, 6);
          c.fillRect(x - 3, y - .8, 6, 1.6);
        } else {
          c.fillRect(x, y, s.r, s.r);
        }
      }
      c.restore();
    }

    _drawGlow(scene) {
      const c = this.c;
      const combo = (this.mode === 'menu' || this.mode === 'results') ? 42 : this.combo;
      const warm = combo >= 30;
      c.save();
      c.globalCompositeOperation = 'lighter';
      const glow = c.createRadialGradient(scene.cx, scene.cy, 0, scene.cx, scene.cy, scene.R * 5.2);
      glow.addColorStop(0, warm ? 'rgba(255,190,112,.10)' : 'rgba(94,134,255,.10)');
      glow.addColorStop(.32, warm ? 'rgba(255,108,127,.055)' : 'rgba(101,90,255,.04)');
      glow.addColorStop(1, 'rgba(0,0,0,0)');
      c.fillStyle = glow;
      c.fillRect(scene.cx - scene.R * 5.3, scene.cy - scene.R * 5.3, scene.R * 10.6, scene.R * 10.6);
      c.restore();
    }

    _drawLines(scene) {
      const c = this.c;
      c.save();
      for (let i = 0; i < scene.lines.length; i++) {
        const line = scene.lines[i];
        const heat = scene.heat[i] || 0;
        const dirX = Math.cos(line.angle);
        const dirY = Math.sin(line.angle);
        const inner = scene.R + 1;
        const outer = scene.R + line.length;
        const x1 = scene.cx + dirX * inner;
        const y1 = scene.cy + dirY * inner;
        const x2 = scene.cx + dirX * outer;
        const y2 = scene.cy + dirY * outer;

        const grad = c.createLinearGradient(x1, y1, x2, y2);
        grad.addColorStop(0, rgba(line.tint, .55 + heat * .32));
        grad.addColorStop(.65, rgba(line.tint, .18 + heat * .2));
        grad.addColorStop(1, rgba(line.tint, .045));

        c.strokeStyle = rgba(line.tint, .045 + heat * .05);
        c.lineWidth = 5;
        c.lineCap = 'round';
        c.beginPath();
        c.moveTo(x1, y1);
        c.lineTo(x2, y2);
        c.stroke();

        c.strokeStyle = grad;
        c.lineWidth = 1.15 + heat * .9;
        c.beginPath();
        c.moveTo(x1, y1);
        c.lineTo(x2, y2);
        c.stroke();

        // Inward chevron near the outer end.
        const cx2 = scene.cx + dirX * (outer - 15);
        const cy2 = scene.cy + dirY * (outer - 15);
        const nx = -dirY, ny = dirX;
        c.strokeStyle = rgba(line.tint, .22 + heat * .22);
        c.lineWidth = .9;
        c.beginPath();
        c.moveTo(cx2 + nx * 3, cy2 + ny * 3);
        c.lineTo(cx2 - dirX * 4, cy2 - dirY * 4);
        c.lineTo(cx2 - nx * 3, cy2 - ny * 3);
        c.stroke();
      }

      // small lane-end knots
      for (let i = 0; i < scene.lines.length; i++) {
        const line = scene.lines[i];
        const heat = scene.heat[i] || 0;
        const dirX = Math.cos(line.angle);
        const dirY = Math.sin(line.angle);
        const lx = scene.cx + dirX * (scene.R + line.length);
        const ly = scene.cy + dirY * (scene.R + line.length);
        c.fillStyle = rgba(line.tint, .25 + heat * .45);
        c.beginPath();
        c.arc(lx, ly, 2.2 + heat * 1.2, 0, TAU);
        c.fill();
      }
      c.restore();
    }

    _drawCore(scene, opts) {
      const c = this.c;
      opts = opts || {};
      const combo = opts.combo !== undefined ? opts.combo : (this.combo || 0);
      const acc = opts.acc !== undefined ? opts.acc : this.displayAccuracy();
      const R = scene.R;
      const warm = combo >= 30;

      c.save();
      c.translate(scene.cx, scene.cy);

      // decorative orbit arcs
      c.save();
      c.globalCompositeOperation = 'lighter';
      c.rotate(scene.rot + this.clock * .18);
      c.strokeStyle = 'rgba(117,205,255,.18)';
      c.lineWidth = .9;
      c.lineCap = 'round';
      c.beginPath();
      c.arc(0, 0, R + 9, .15, 1.05);
      c.stroke();
      c.strokeStyle = 'rgba(255,126,158,.16)';
      c.beginPath();
      c.arc(0, 0, R + 9, 3.3, 4.2);
      c.stroke();
      c.restore();

      // disc
      const disc = c.createRadialGradient(0, -R * .15, R * .05, 0, 0, R);
      disc.addColorStop(0, 'rgba(18,25,50,.97)');
      disc.addColorStop(.7, 'rgba(8,13,29,.94)');
      disc.addColorStop(1, 'rgba(4,8,18,.9)');
      c.fillStyle = disc;
      c.beginPath();
      c.arc(0, 0, R, 0, TAU);
      c.fill();

      // inner rings
      c.strokeStyle = 'rgba(182,215,255,.09)';
      c.lineWidth = .7;
      c.beginPath();
      c.arc(0, 0, R * .78, 0, TAU);
      c.stroke();
      c.setLineDash([1, 7]);
      c.strokeStyle = 'rgba(182,215,255,.08)';
      c.beginPath();
      c.arc(0, 0, R * .9, 0, TAU);
      c.stroke();
      c.setLineDash([]);

      // outer rim
      const rim = c.createLinearGradient(-R, -R, R, R);
      rim.addColorStop(0, 'rgba(98,225,255,.9)');
      rim.addColorStop(.42, 'rgba(240,250,255,.96)');
      rim.addColorStop(.7, 'rgba(255,255,255,.9)');
      rim.addColorStop(1, warm ? 'rgba(255,222,150,.92)' : 'rgba(255,137,164,.86)');
      c.strokeStyle = rim;
      c.lineWidth = 2.2;
      c.shadowColor = warm ? '#ffe0a0' : '#bcecff';
      c.shadowBlur = 20;
      c.beginPath();
      c.arc(0, 0, R, 0, TAU);
      c.stroke();
      c.shadowBlur = 0;

      // lane anchors
      c.fillStyle = 'rgba(232,246,255,.55)';
      for (const line of scene.lines) {
        const x = Math.cos(line.angle) * R;
        const y = Math.sin(line.angle) * R;
        c.beginPath();
        c.arc(x, y, 1.2, 0, TAU);
        c.fill();
      }

      // pulse ring
      if (this.corePulse > .01) {
        c.strokeStyle = rgba(warm ? '#ffe2a3' : '#c9f3ff', this.corePulse * .42);
        c.lineWidth = 1.2;
        c.beginPath();
        c.arc(0, 0, R + (1 - this.corePulse) * 18, 0, TAU);
        c.stroke();
      }

      // hit flashes on rim
      if (this.ringFlashes.length) {
        c.save();
        c.globalCompositeOperation = 'lighter';
        for (const f of this.ringFlashes) {
          const a = clamp(f.life / f.maxLife, 0, 1);
          c.strokeStyle = rgba(f.color, a * .95);
          c.lineWidth = 2.5 + a * 3.5;
          c.shadowColor = f.color;
          c.shadowBlur = 15 * a;
          c.beginPath();
          c.arc(0, 0, R, f.rel - .13, f.rel + .13);
          c.stroke();
        }
        c.restore();
      }

      // centre HUD text
      const pop = 1 + this.corePop * .035;
      c.save();
      c.scale(pop, pop);
      c.textAlign = 'center';
      c.textBaseline = 'middle';
      c.fillStyle = 'rgba(176,196,231,.58)';
      c.font = `600 ${Math.max(5.2, R * .13).toFixed(1)}px "Cascadia Mono", Consolas, monospace`;
      c.letterSpacing = '1.2px';
      c.fillText('COMBO', 0, -R * .42);
      c.letterSpacing = '0px';

      const comboText = String(combo);
      let comboFont = clamp(R * .6, 12, 32);
      c.font = `600 ${comboFont.toFixed(1)}px "Bahnschrift", "Segoe UI", sans-serif`;
      const maxComboWidth = R * 1.35;
      while (c.measureText(comboText).width > maxComboWidth && comboFont > 8) {
        comboFont -= 1;
        c.font = `600 ${comboFont.toFixed(1)}px "Bahnschrift", "Segoe UI", sans-serif`;
      }
      c.fillStyle = '#f7f9ff';
      c.shadowColor = warm ? 'rgba(255,220,150,.55)' : 'rgba(157,221,255,.45)';
      c.shadowBlur = 14;
      c.fillText(comboText, 0, -R * .02);
      c.shadowBlur = 0;

      c.fillStyle = 'rgba(126,247,222,.86)';
      c.font = `500 ${Math.max(7, R * .19).toFixed(1)}px "Cascadia Mono", Consolas, monospace`;
      c.letterSpacing = '.3px';
      c.fillText(`${acc.toFixed(1)}%`, 0, R * .5);
      c.letterSpacing = '0px';
      c.restore();

      c.restore();
    }

    _drawNotes(scene, t) {
      const c = this.c;
      const visible = [];
      const travel = this._travelTime();
      for (const n of this.playNotes) {
        if (n.status !== 'pending') continue;
        const lead = n.time - t;
        if (lead > travel || lead < -.12) continue;
        const line = scene.lines[n.lane];
        const p = clamp(lead / travel, -.2, 1);
        const dist = (scene.R + line.length) * p;
        const x = scene.cx + Math.cos(line.angle) * dist;
        const y = scene.cy + Math.sin(line.angle) * dist;
        const alpha = lead < 0
          ? clamp(1 + lead / .12, 0, 1)
          : clamp((1 - p) / .12, 0, 1);
        visible.push({ n, x, y, lead, alpha, angle: line.angle, type: n.type, p });
      }
      visible.sort((a, b) => b.lead - a.lead);
      for (const v of visible) {
        this._drawNote(v.x, v.y, scene.noteR, v.type, v.angle, v.alpha, {
          lead: v.lead,
          travel
        });
      }
    }

    _drawNote(x, y, r, type, angle, alpha, opts) {
      if (alpha <= .01) return;
      const c = this.c;
      const col = NOTE[type] || NOTE.white;
      const lead = opts && opts.lead !== undefined ? opts.lead : 0;
      const travel = opts && opts.travel ? opts.travel : 1;
      const dirX = Math.cos(angle);
      const dirY = Math.sin(angle);

      // trail
      c.save();
      c.globalCompositeOperation = 'lighter';
      const trail = c.createLinearGradient(
        x + dirX * r, y + dirY * r,
        x + dirX * (r + 44), y + dirY * (r + 44)
      );
      trail.addColorStop(0, rgba(col.main, .32 * alpha));
      trail.addColorStop(1, rgba(col.main, 0));
      c.strokeStyle = trail;
      c.lineWidth = Math.max(2, r * .34);
      c.lineCap = 'round';
      c.beginPath();
      c.moveTo(x + dirX * r * 1.15, y + dirY * r * 1.15);
      c.lineTo(x + dirX * (r + 44), y + dirY * (r + 44));
      c.stroke();
      c.restore();

      // approach halo
      if (lead > 0) {
        const p = clamp(lead / travel, 0, 1);
        c.save();
        c.strokeStyle = rgba(col.main, (.09 + (1 - p) * .2) * alpha);
        c.lineWidth = 1;
        c.beginPath();
        c.arc(x, y, r * (1.2 + p * .95), 0, TAU);
        c.stroke();
        c.restore();
      }

      // circular body
      c.save();
      c.globalAlpha = alpha;
      c.shadowColor = col.main;
      c.shadowBlur = r * (lead <= .1 ? 1.9 : 1.15);

      const grad = c.createRadialGradient(-r * .3, -r * .35, r * .1, 0, 0, r);
      grad.addColorStop(0, '#ffffff');
      grad.addColorStop(.28, col.light);
      grad.addColorStop(.82, col.main);
      grad.addColorStop(1, col.dark);
      c.fillStyle = grad;
      c.beginPath();
      c.arc(x, y, r, 0, TAU);
      c.fill();
      c.shadowBlur = 0;

      c.strokeStyle = 'rgba(3,7,16,.78)';
      c.lineWidth = Math.max(1, r * .085);
      c.stroke();

      // glossy highlight
      c.beginPath();
      c.arc(x - r * .26, y - r * .3, r * .26, 0, TAU);
      c.fillStyle = 'rgba(255,255,255,.75)';
      c.fill();

      if (type === 'white') {
        c.strokeStyle = 'rgba(255,255,255,.8)';
        c.lineWidth = 1;
        for (let i = 0; i < 4; i++) {
          const a = i * TAU / 4 + Math.PI / 4;
          c.beginPath();
          c.moveTo(x + Math.cos(a) * r * .38, y + Math.sin(a) * r * .38);
          c.lineTo(x + Math.cos(a) * r * .72, y + Math.sin(a) * r * .72);
          c.stroke();
        }
      } else {
        c.beginPath();
        c.arc(x, y, r * .16, 0, TAU);
        c.fillStyle = 'rgba(255,255,255,.9)';
        c.fill();
      }
      c.restore();
    }

    _drawParticles() {
      const c = this.c;
      c.save();
      c.globalCompositeOperation = 'lighter';
      for (const p of this.particles) {
        const a = clamp(p.life / p.maxLife, 0, 1);
        c.strokeStyle = rgba(p.color, a * .75);
        c.fillStyle = rgba(p.color, a * .85);
        c.lineWidth = p.size * .65;
        if (p.streak) {
          c.beginPath();
          c.moveTo(p.x, p.y);
          c.lineTo(p.x - p.vx * .025, p.y - p.vy * .025);
          c.stroke();
        } else {
          c.beginPath();
          c.arc(p.x, p.y, p.size * a + .4, 0, TAU);
          c.fill();
        }
      }
      c.restore();
    }

    _drawShockwaves() {
      const c = this.c;
      c.save();
      c.globalCompositeOperation = 'lighter';
      for (const s of this.shockwaves) {
        const p = 1 - s.life / s.maxLife;
        const r = s.r + (s.maxR - s.r) * Math.pow(p, .5);
        const a = (1 - p) * .5;
        c.strokeStyle = rgba(s.color, a);
        c.lineWidth = 1.6 * (1 - p) + .4;
        c.beginPath();
        c.arc(s.x, s.y, r, 0, TAU);
        c.stroke();
      }
      c.restore();
    }

    _drawJudgments() {
      const c = this.c;
      for (const j of this.judgments) {
        const age = j.maxLife - j.life;
        const p = clamp(age / j.maxLife, 0, 1);
        const alpha = clamp(j.life / .24, 0, 1) * clamp(age / .055, 0, 1);
        const scale = .88 + Math.min(1, age / .08) * .12;
        const y = j.y - p * 26;
        const label = j.text + (j.count > 1 ? ' ×' + j.count : '');
        c.save();
        c.globalAlpha = alpha;
        c.translate(j.x, y);
        c.scale(scale, scale);
        c.textAlign = 'center';
        c.textBaseline = 'middle';
        c.font = j.grade === 'miss' ? '700 18px "Bahnschrift", "Segoe UI", sans-serif'
          : '700 22px "Bahnschrift", "Segoe UI", sans-serif';
        c.letterSpacing = '2.5px';

        const tw = c.measureText(label).width;
        const boxW = Math.max(74, tw + 28);
        const boxH = j.sub ? 39 : 29;
        c.fillStyle = 'rgba(4,8,18,.62)';
        c.strokeStyle = rgba(j.color, .28);
        c.lineWidth = 1;
        c.beginPath();
        c.roundRect(-boxW / 2, -boxH / 2 - 1, boxW, boxH, 4);
        c.fill();
        c.stroke();

        c.fillStyle = j.color;
        c.shadowColor = j.color;
        c.shadowBlur = 16;
        c.fillText(label, 0, 0);
        c.shadowBlur = 0;
        if (j.sub) {
          c.font = '500 8px "Cascadia Mono", Consolas, monospace';
          c.letterSpacing = '1.5px';
          c.fillStyle = 'rgba(205,219,245,.72)';
          c.fillText(j.sub, 0, 18);
        }
        c.letterSpacing = '0px';
        c.restore();
      }
    }

    /* =========================================================
       render frames
       ========================================================= */
    _render() {
      if (!this.w || !this.h) return;
      this.c.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
      if (this.mode === 'menu') this._renderMenu();
      else if (this.mode === 'songselect') this._renderMenu();
      else if (this.mode === 'results') this._renderResults();
      else if (this.mode === 'preview') this._renderGame(this.previewTime);
      else this._renderGame(this.songTime);
    }

    _renderMenu() {
      this._drawBackground();
      const t = this.clock;
      const wide = this.w > 980;
      const cx = wide ? this.w * .755 : this.w * .66;
      const cy = this.h * (.47 + Math.sin(t * .2) * .006);
      const R = clamp(Math.min(this.w, this.h) * .072, 38, 76);
      const noteR = R / 2.25;
      const lineBase = Math.min(this.w, this.h) * (wide ? .37 : .31);
      const chart = this.chartCache.d2;

      const lines = chart.lines.map(line => {
        const state = C.lineAt(line, Math.max(0, t * .8));
        return {
          line,
          tint: line.tint || '#9ac9ff',
          angle: state.angle,
          length: lineBase * state.lengthFactor
        };
      });
      const scene = {
        cx, cy, R,
        rot: t * .1,
        lines,
        noteR,
        heat: new Array(lines.length).fill(0)
      };

      const demoTypes = ['red', 'blue', 'white', 'red', 'blue', 'white'];
      const demoNotes = [];
      for (let lane = 0; lane < lines.length; lane++) {
        for (let k = 0; k < 3; k++) {
          const lead = .16 + ((t * .18 + lane * .37 + k * .29) % 1) * 1.15;
          const p = clamp(lead / 1.35, 0, 1);
          const line = lines[lane];
          const dist = (R + line.length) * p;
          demoNotes.push({
            x: cx + Math.cos(line.angle) * dist,
            y: cy + Math.sin(line.angle) * dist,
            type: demoTypes[(lane * 3 + k) % demoTypes.length],
            angle: line.angle,
            lead,
            alpha: clamp((1 - p) / .15, 0, 1),
            p
          });
          scene.heat[lane] = Math.max(scene.heat[lane], 1 - p);
        }
      }

      this._drawGlow(scene);
      this._drawLines(scene);

      // faint outer orbit
      const c = this.c;
      c.save();
      c.translate(cx, cy);
      c.rotate(-t * .05);
      c.strokeStyle = 'rgba(158,190,255,.075)';
      c.lineWidth = .7;
      c.setLineDash([2, 9]);
      c.beginPath();
      c.arc(0, 0, R + lineBase * .88, 0, TAU);
      c.stroke();
      c.setLineDash([]);
      c.restore();

      this._drawCore(scene, { combo: this.demoCombo || 47, acc: 98.6 });

      for (const n of demoNotes) {
        this._drawNote(n.x, n.y, noteR, n.type, n.angle, n.alpha, {
          lead: n.lead,
          travel: 1.35
        });
      }

      c.save();
      c.fillStyle = 'rgba(158,175,214,.48)';
      c.font = '9px "Cascadia Mono", Consolas, monospace';
      c.letterSpacing = '3px';
      c.textAlign = 'right';
      c.fillText('しーけー  /  230 BPM', cx + R + lineBase * .78, cy + R + lineBase * .9);
      c.letterSpacing = '0px';
      c.restore();
    }

    _renderGame(t) {
      this._drawBackground();
      const scene = this._sceneState(t);

      // heat each lane from incoming notes
      for (const n of this.playNotes) {
        if (n.status !== 'pending') continue;
        const lead = n.time - t;
        if (lead >= 0 && lead <= .9) {
          const h = 1 - lead / .9;
          if (h > scene.heat[n.lane]) scene.heat[n.lane] = h;
        }
      }

      this._drawGlow(scene);

      const sx = (Math.random() - .5) * this.shake;
      const sy = (Math.random() - .5) * this.shake;
      const c = this.c;
      c.save();
      c.translate(sx, sy);

      this._drawLines(scene);
      this._drawCore(scene);
      this._drawNotes(scene, t);
      this._drawShockwaves();
      this._drawParticles();

      c.restore();

      this._drawJudgments();

      if (this.missFlash > .01) {
        const mg = c.createRadialGradient(this.w * .5, this.h * .5, Math.min(this.w, this.h) * .2, this.w * .5, this.h * .5, Math.max(this.w, this.h) * .72);
        mg.addColorStop(0, 'rgba(255,40,75,0)');
        mg.addColorStop(1, `rgba(255,35,72,${(.2 * this.missFlash).toFixed(3)})`);
        c.fillStyle = mg;
        c.fillRect(0, 0, this.w, this.h);
      }
    }

    _renderResults() {
      this._drawBackground();
      const t = this.clock;
      const cx = this.w * .5;
      const cy = this.h * .52;
      const R = clamp(Math.min(this.w, this.h) * .085, 44, 90);
      const noteR = R / 2.2;
      const chart = this.chartCache[this.selectedDiff];
      const lines = chart.lines.map(line => {
        const st = C.lineAt(line, t * .6);
        return {
          line,
          tint: line.tint || '#9ac9ff',
          angle: st.angle,
          length: Math.min(this.w, this.h) * .39 * st.lengthFactor
        };
      });
      const scene = {
        cx, cy, R,
        rot: t * .1,
        lines,
        noteR,
        heat: new Array(lines.length).fill(0)
      };
      const c = this.c;
      c.save();
      c.globalAlpha = .2;
      this._drawGlow(scene);
      this._drawLines(scene);
      this._drawCore(scene, { combo: this.maxCombo || 0, acc: this.accuracy() });
      c.restore();
    }
  }

  window.addEventListener('load', () => {
    new OrbitGame();
  });
})();
