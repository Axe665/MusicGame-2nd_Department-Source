/* =========================================================
   Two-lane rhythm chart runtime
   Song: アトロポスと最果の探求者 / しーけー
   BPM 230, 4/4, first downbeat 1.200 s, duration 157.76 s.
   The note list lives in js/chart-data.js.
   ========================================================= */
(function (global) {
  'use strict';

  const DATA = global.SONG_CHART;
  if (!DATA) throw new Error('SONG_CHART data is missing.');

  const TAU = Math.PI * 2;
  const BPM = DATA.bpm;
  const BEAT = 60 / BPM;
  const BAR = BEAT * 4;
  const OFFSET = DATA.offset;
  const DURATION = DATA.duration;
  const LANE_COUNT = 2;

  const RED_KEYS = ['q', 'w', 'e', 'r'];
  const BLUE_KEYS = ['u', 'i', 'o', 'p'];
  const KEY_ORDER = [...RED_KEYS, ...BLUE_KEYS];
  const KEY_COLOR = {};
  RED_KEYS.forEach(k => { KEY_COLOR[k] = 'red'; });
  BLUE_KEYS.forEach(k => { KEY_COLOR[k] = 'blue'; });

  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

  const DIFFICULTIES = [
    {
      id: 'd1',
      label: '难度 1',
      level: 1,
      color: '#7ef7de',
      travel: DATA.charts.d1.travelTime,
      motion: 0.72,
      lineMotion: 0.68,
      desc: '基础节奏，双轨慢速流动。'
    },
    {
      id: 'd2',
      label: '难度 2',
      level: 2,
      color: '#49ccff',
      travel: DATA.charts.d2.travelTime,
      motion: 1,
      lineMotion: 1,
      desc: '完整八分节奏与双押。'
    },
    {
      id: 'd3',
      label: '难度 3',
      level: 3,
      color: '#ff4d73',
      travel: DATA.charts.d3.travelTime,
      motion: 1.18,
      lineMotion: 1.28,
      desc: '密集八分与十六分填充。'
    }
  ];

  function sectionAt(time) {
    const bar = (Math.max(0, time) - OFFSET) / BAR;
    for (const s of DATA.sections) {
      if (bar >= s.start && bar < s.end) return s;
    }
    return DATA.sections[DATA.sections.length - 1];
  }

  /**
   * Two straight lanes, one on each side of the core. Their colours are
   * decorative; every note colour can appear on both lanes.
   */
  function buildLines(diff) {
    return DATA.lines.map((def, lane) => {
      const path = [];
      const beatStep = BEAT / 2;
      for (let time = 0; time <= DURATION + 2; time += beatStep) {
        const section = sectionAt(time);
        const intensity = section.intensity || 0;
        const beatPos = (time - OFFSET) / BEAT;
        const beatFrac = beatPos - Math.floor(beatPos);
        const barIndex = Math.floor(beatPos / 4);

        // The lanes step into a new position each bar, and give a small
        // outward pulse on every beat. This is intentionally stronger than
        // the old slow drift so the lines visibly ride the music.
        const steps = [0.16, -0.08, 0.20, -0.12];
        const barStep = steps[((barIndex % 4) + 4) % 4]
          * (0.55 + intensity * 0.65)
          * diff.lineMotion
          * (lane === 0 ? 1 : -1);
        const beatSwing = Math.sin((beatPos + lane * 0.5) * Math.PI)
          * 0.032 * diff.lineMotion;
        const slowDrift = Math.sin(time * 0.13 + 1.2 + lane * 0.7)
          * (0.008 + intensity * 0.012) * diff.lineMotion;
        const beatPulse = Math.exp(-beatFrac * 7);
        const lengthFactor = clamp(
          0.93 + Math.sin(beatPos * Math.PI / 2 + lane * 0.9) * 0.025
          + beatPulse * 0.06 + intensity * 0.025,
          0.76, 1.12
        );

        path.push({
          time,
          angle: def.baseAngle + barStep + beatSwing + slowDrift,
          lengthFactor
        });
      }
      return {
        id: lane,
        tint: def.tint,
        baseAngle: def.baseAngle,
        path
      };
    });
  }

  function buildCoreKeys(diff) {
    const keys = [];
    for (let time = 0; time <= DURATION + 2; time += BEAT * 2) {
      const section = sectionAt(time);
      const intensity = section.intensity || 0;
      const mx = .055 + intensity * .05;
      const my = .038 + intensity * .035;
      const x = .5 + Math.sin(time * .31 + .4) * mx * diff.motion
        + Math.sin(time * .11 + 1.7) * mx * .22 * diff.motion;
      const y = .5 + Math.sin(time * .43 + 1.1) * my * diff.motion
        + Math.cos(time * .17 + .2) * my * .28 * diff.motion;
      keys.push({
        time,
        x: clamp(x, .34, .66),
        y: clamp(y, .35, .65),
        rot: time * .018 * diff.motion
      });
    }
    return keys;
  }

  const cache = Object.create(null);
  function getChart(id) {
    if (cache[id]) return cache[id];
    const meta = DIFFICULTIES.find(d => d.id === id) || DIFFICULTIES[1];
    const raw = DATA.charts[meta.id];
    if (!raw) throw new Error('Unknown chart: ' + id);
    const notes = raw.notes.map(n => Object.assign({}, n));
    const chart = {
      title: DATA.title,
      artist: DATA.artist,
      bpm: BPM,
      offset: OFFSET,
      duration: DURATION,
      bar: BAR,
      laneCount: LANE_COUNT,
      difficulty: {
        id: meta.id,
        label: raw.label,
        level: raw.level,
        color: raw.color,
        travel: meta.travel,
        motion: meta.motion,
        lineMotion: meta.lineMotion,
        desc: meta.desc
      },
      notes,
      lines: buildLines(meta),
      coreKeys: buildCoreKeys(meta),
      tutorial: meta.id === 'd1' ? DATA.tutorial : [],
      noteCount: notes.length,
      sections: DATA.sections
    };
    cache[id] = chart;
    return chart;
  }

  function ringAt(chart, time) {
    const keys = chart.coreKeys;
    const t = Math.max(0, time);
    if (t <= keys[0].time) return { x: keys[0].x, y: keys[0].y, rot: keys[0].rot };
    if (t >= keys[keys.length - 1].time) {
      const k = keys[keys.length - 1];
      return { x: k.x, y: k.y, rot: k.rot };
    }
    let lo = 0;
    let hi = keys.length - 1;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if (keys[mid].time <= t) lo = mid;
      else hi = mid;
    }
    const a = keys[lo], b = keys[hi];
    let p = clamp((t - a.time) / Math.max(.0001, b.time - a.time), 0, 1);
    p = p * p * (3 - 2 * p);
    return {
      x: a.x + (b.x - a.x) * p,
      y: a.y + (b.y - a.y) * p,
      rot: a.rot + (b.rot - a.rot) * p
    };
  }

  function lineAt(line, time) {
    const keys = line.path;
    const t = Math.max(0, time);
    if (t <= keys[0].time) return { angle: keys[0].angle, lengthFactor: keys[0].lengthFactor };
    if (t >= keys[keys.length - 1].time) {
      const k = keys[keys.length - 1];
      return { angle: k.angle, lengthFactor: k.lengthFactor };
    }
    let lo = 0;
    let hi = keys.length - 1;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if (keys[mid].time <= t) lo = mid;
      else hi = mid;
    }
    const a = keys[lo], b = keys[hi];
    let p = clamp((t - a.time) / Math.max(.0001, b.time - a.time), 0, 1);
    p = p * p * (3 - 2 * p);
    return {
      angle: a.angle + (b.angle - a.angle) * p,
      lengthFactor: a.lengthFactor + (b.lengthFactor - a.lengthFactor) * p
    };
  }

  function formatTime(sec) {
    sec = Math.max(0, sec);
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return m + ':' + String(s).padStart(2, '0');
  }

  global.OrbitChart = {
    BPM, BEAT, BAR, DURATION, OFFSET, TAU, LANE_COUNT,
    RED_KEYS, BLUE_KEYS, KEY_ORDER, KEY_COLOR,
    DIFFICULTIES,
    SONG: DATA,
    getChart,
    ringAt,
    lineAt,
    formatTime,
    clamp
  };
})(window);
