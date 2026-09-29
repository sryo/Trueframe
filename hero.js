import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';

// ---------------------------------------------------------------------------
// Constants and helpers
// ---------------------------------------------------------------------------

const TAU = Math.PI * 2;
const PHONE = { W: 0.0715, H: 0.150, T: 0.0083, R: 0.0115 };
const PT = 2;
const SW = 402;
const SH = 874;
const CAP = 512;
const LENS_FOV = { '0.5': 20, '1x': 10, '2x': 6 };
const INTERVALS = [0.25, 0.5, 1, 2, 5];
const INTERVAL_LABELS = ['0.25s', '0.5s', '1s', '2s', '5s'];
const KEEP_THRESHOLD = 0.4;
const MAX_ELIGIBLE = 50;
const HEART_PERIOD = 60 / 52;
const VIEW_CAM_POS = new THREE.Vector3(0, 1.5, 0.12);
const VIEW_CAM_TARGET = new THREE.Vector3(-0.35, 1.18, -6);
const DOG_AREA = { x0: -6, x1: 1.5, z0: -15, z1: -9 };
const FONT = '-apple-system, "SF Pro Display", "Helvetica Neue", Helvetica, Arial, sans-serif';

const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const rand = (a, b) => a + Math.random() * (b - a);
const deg = (d) => (d * Math.PI) / 180;
const smoothstep = (a, b, x) => {
  const t = clamp((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
};
const easeOutCubic = (t) => 1 - Math.pow(1 - t, 3);
const easeInCubic = (t) => t * t * t;
const easeInOutCubic = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const easeOutBack = (t, s = 1.4) => 1 + (s + 1) * Math.pow(t - 1, 3) + s * Math.pow(t - 1, 2);
const damp = (a, b, rate, dt) => lerp(a, b, 1 - Math.exp(-rate * dt));
const wrapAngle = (a) => Math.atan2(Math.sin(a), Math.cos(a));
const font = (weight, size) => `${weight} ${size}px ${FONT}`;

// Exact critically damped spring step; s = { x, v }.
function springStep(s, target, omega, dt) {
  const x = s.x - target;
  const v = s.v;
  const ex = Math.exp(-omega * dt);
  s.x = target + (x + (v + omega * x) * dt) * ex;
  s.v = (v - omega * (v + omega * x) * dt) * ex;
}

function roundRectPath(c, x, y, w, h, r) {
  const k = Math.min(r, w / 2, h / 2);
  c.beginPath();
  c.moveTo(x + k, y);
  c.arcTo(x + w, y, x + w, y + h, k);
  c.arcTo(x + w, y + h, x, y + h, k);
  c.arcTo(x, y + h, x, y, k);
  c.arcTo(x, y, x + w, y, k);
  c.closePath();
}

function roundedRectShape(w, h, r) {
  const s = new THREE.Shape();
  const x = -w / 2, y = -h / 2;
  s.moveTo(x + r, y);
  s.lineTo(x + w - r, y);
  s.absarc(x + w - r, y + r, r, -Math.PI / 2, 0, false);
  s.lineTo(x + w, y + h - r);
  s.absarc(x + w - r, y + h - r, r, 0, Math.PI / 2, false);
  s.lineTo(x + r, y + h);
  s.absarc(x + r, y + h - r, r, Math.PI / 2, Math.PI, false);
  s.lineTo(x, y + r);
  s.absarc(x + r, y + r, r, Math.PI, Math.PI * 1.5, false);
  return s;
}

function flatRoundedRect(w, h, r) {
  const geo = new THREE.ShapeGeometry(roundedRectShape(w, h, r), 24);
  geo.computeBoundingBox();
  const b = geo.boundingBox;
  const pos = geo.attributes.position;
  const uv = geo.attributes.uv;
  for (let i = 0; i < pos.count; i++) {
    uv.setXY(i, (pos.getX(i) - b.min.x) / (b.max.x - b.min.x), (pos.getY(i) - b.min.y) / (b.max.y - b.min.y));
  }
  uv.needsUpdate = true;
  return geo;
}

// Offsets that repeat a mark across the edges of a tiling canvas so it wraps seamlessly.
const TILE_OFFSETS = (s) => [[0, 0], [s, 0], [-s, 0], [0, s], [0, -s]];

function canvasTexture(size, paint) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  paint(c.getContext('2d'), size);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

function haptic() {
  try {
    navigator.vibrate?.([22, 98, 16]);
  } catch {
    // Vibration is best effort.
  }
}

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------

const heroEl = document.getElementById('hero');
const stageEl = document.getElementById('stage');

try {
  if (!stageEl) throw new Error('no stage');
  start(stageEl);
} catch {
  stageEl?.querySelector('canvas[data-hero]')?.remove();
  heroEl?.classList.add('hero--fallback');
}

function start(stage) {
  if (!document.createElement('canvas').getContext('webgl2')) throw new Error('no webgl2');

  const reduceQuery = window.matchMedia?.('(prefers-reduced-motion: reduce)');
  let reduced = !!reduceQuery?.matches;
  reduceQuery?.addEventListener?.('change', (e) => { reduced = e.matches; });

  // -------------------------------------------------------------------------
  // Renderer and scene
  // -------------------------------------------------------------------------

  const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.toneMapping = THREE.NoToneMapping;
  renderer.outputColorSpace = THREE.SRGBColorSpace;

  const canvas = renderer.domElement;
  canvas.dataset.hero = '';
  Object.assign(canvas.style, {
    position: 'absolute', inset: '0', width: '100%', height: '100%', display: 'block',
    userSelect: 'none', webkitUserSelect: 'none', webkitTouchCallout: 'none',
  });
  canvas.style.touchAction = 'pan-y';
  stage.appendChild(canvas);

  const scene = new THREE.Scene();
  const horizonColor = new THREE.Color('#f79a45');
  scene.fog = new THREE.Fog(horizonColor.clone(), 24, 170);

  // Everything is unlit and drawn in flat fills. A colour can drift from `a` to `b`
  // across the shape (along an axis in object or world space) to shift hue, never to
  // model volume. With facets on, each face
  // is shaded softly between a warm lit tone and a cool dusk shadow by how much it faces
  // the low sun behind the scene; `hard` snaps that to exactly two tones per face for
  // the illustrated hand and arm. Every flat colour
  // then gets the same muted dusk grade. `flashUniform` pushes every flat material
  // toward warm white while the phone's flash fires.
  const FLAT_LIGHT = new THREE.Vector3(-0.35, 0.55, -1).normalize();
  const sunDir = new THREE.Vector3(-0.3, 0.078, -1).normalize();
  // Screen-print stipple: blends between two tones become a scatter of grain. Cells are
  // about 2 CSS px at any pixel ratio, and interleaved gradient noise spreads the dots
  // evenly so they read as fine grain instead of clumps.
  const STIPPLE_GLSL = `
    float stippleNoise(vec2 p) { p = floor(p); return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }
    float stipple(float t) {
      float k = smoothstep(0.3, 0.7, t);
      return mix(k, step(stippleNoise(gl_FragCoord.xy / ${(2 * renderer.getPixelRatio()).toFixed(1)}), k) * step(0.001, k), 0.5);
    }`;
  const FLASH_TINT = new THREE.Color('#fff4e0');
  const flashUniform = { value: 0 };
  function flat({
    a, b = a, axis = [0, 1, 0], from = 0, to = 1, space = 'local', facets = true, hard = false, map = null,
  }) {
    const m = new THREE.MeshBasicMaterial({ map });
    const mode = a === b ? 0 : space === 'world' ? 2 : 1;
    m.defines = { FLAT_MODE: mode };
    if (facets) m.defines.FLAT_FACETS = '';
    if (hard) m.defines.FLAT_HARD = '';
    const uniforms = {
      uFlatA: { value: new THREE.Color(a) },
      uFlatB: { value: new THREE.Color(b) },
      uFlatAxis: { value: new THREE.Vector3(...axis).normalize() },
      uFlatRange: { value: new THREE.Vector2(from, to) },
      uFlatLight: { value: FLAT_LIGHT },
      uSunDir: { value: sunDir },
      uFlash: flashUniform,
      uFlashTint: { value: FLASH_TINT },
    };
    m.onBeforeCompile = (shader) => {
      Object.assign(shader.uniforms, uniforms);
      shader.vertexShader = shader.vertexShader
        .replace('#include <common>', `#include <common>
          varying vec3 vFlatWorld;
          varying vec3 vFlatNormal;
          varying float vFlatT;
          uniform vec3 uFlatAxis;
          uniform vec2 uFlatRange;`)
        .replace('#include <begin_vertex>', `#include <begin_vertex>
          vec4 flatWp = vec4(transformed, 1.0);
          #ifdef USE_INSTANCING
            flatWp = instanceMatrix * flatWp;
          #endif
          flatWp = modelMatrix * flatWp;
          vFlatWorld = flatWp.xyz;
          vec3 flatObjN = normal;
          #ifdef USE_INSTANCING
            flatObjN = mat3(instanceMatrix) * flatObjN;
          #endif
          vFlatNormal = normalize(mat3(modelMatrix) * flatObjN);
          #if FLAT_MODE == 1
            vFlatT = (dot(transformed, uFlatAxis) - uFlatRange.x) / (uFlatRange.y - uFlatRange.x);
          #elif FLAT_MODE == 2
            vFlatT = (dot(flatWp.xyz, uFlatAxis) - uFlatRange.x) / (uFlatRange.y - uFlatRange.x);
          #else
            vFlatT = 0.0;
          #endif`);
      shader.fragmentShader = shader.fragmentShader
        .replace('#include <common>', `#include <common>
          varying vec3 vFlatWorld;
          varying vec3 vFlatNormal;
          varying float vFlatT;
          uniform vec3 uFlatA;
          uniform vec3 uFlatB;
          uniform vec3 uFlatLight;
          uniform float uFlash;
          uniform vec3 uFlashTint;
          uniform vec3 uSunDir;
          ${STIPPLE_GLSL}`)
        .replace('vec4 diffuseColor = vec4( diffuse, opacity );', `vec4 diffuseColor = vec4(mix(uFlatA, uFlatB, stipple(clamp(vFlatT, 0.0, 1.0))), opacity);
          #ifdef FLAT_FACETS
            #ifdef FLAT_HARD
              vec3 flatN = normalize(cross(dFdx(vFlatWorld), dFdy(vFlatWorld)));
              if (dot(flatN, cameraPosition - vFlatWorld) < 0.0) flatN = -flatN;
              float flatLit = step(0.0, dot(flatN, uFlatLight));
            #else
              vec3 flatN = normalize(vFlatNormal);
              if (!gl_FrontFacing) flatN = -flatN;
              float flatLit = smoothstep(-0.6, 0.8, dot(flatN, uFlatLight));
            #endif
            diffuseColor.rgb *= mix(vec3(0.5, 0.52, 0.78), vec3(1.06, 0.94, 0.78), stipple(flatLit));
          #endif
          vec3 flatV = normalize(cameraPosition - vFlatWorld);
          float flatDist = length(cameraPosition - vFlatWorld);
          // How directly this point sits against the low sun from where the viewer stands.
          float flatSunward = max(dot(-flatV, uSunDir), 0.0);
          float flatLuma = dot(diffuseColor.rgb, vec3(0.299, 0.587, 0.114));
          diffuseColor.rgb = mix(vec3(flatLuma), diffuseColor.rgb, 0.95) * vec3(0.84, 0.77, 0.76);
          diffuseColor.rgb = clamp((diffuseColor.rgb - 0.4) * 1.06 + 0.4, 0.0, 1.0);
          #ifdef FLAT_FACETS
            // Backlit rim: edges turned away from the viewer catch the low sun behind them,
            // added after the grade so the sunset colour stays hot.
            vec3 flatRimN = normalize(vFlatNormal);
            if (!gl_FrontFacing) flatRimN = -flatRimN;
            float flatEdge = 1.0 - max(dot(flatRimN, flatV), 0.0);
            float flatRim = pow(flatEdge, 1.6) * (0.3 + 0.7 * max(dot(-flatV, uFlatLight), 0.0)) * smoothstep(-0.45, 0.35, dot(flatRimN, uFlatLight));
            flatRim *= 0.8 + 1.2 * pow(flatSunward, 6.0);
            diffuseColor.rgb = mix(diffuseColor.rgb, vec3(1.0, 0.44, 0.26), stipple(flatRim * 2.4) * 0.7);
          #endif
          // Veiling glow: anything seen against the sun sinks into its warm haze, more with distance.
          float flatVeil = pow(flatSunward, 30.0) * smoothstep(30.0, 140.0, flatDist) + pow(flatSunward, 140.0) * 0.3;
          diffuseColor.rgb = mix(diffuseColor.rgb, vec3(1.0, 0.56, 0.4), stipple(flatVeil) * 0.45);`)
        .replace('#include <opaque_fragment>', `outgoingLight = mix(outgoingLight, uFlashTint, uFlash);
          #include <opaque_fragment>`);
    };
    m.userData.flat = uniforms;
    return m;
  }

  const camera = new THREE.PerspectiveCamera(34, 1, 0.02, 700);
  camera.position.copy(VIEW_CAM_POS);
  camera.lookAt(VIEW_CAM_TARGET);

  const beamTime = { value: 0 };
  const sky = new THREE.Mesh(
    new THREE.SphereGeometry(500, 48, 24),
    new THREE.ShaderMaterial({
      uniforms: {
        band0: { value: horizonColor.clone() },
        band1: { value: new THREE.Color('#f25a6a') },
        band2: { value: new THREE.Color('#d63fd0') },
        band3: { value: new THREE.Color('#4a25c0') },
        glow1: { value: new THREE.Color('#ffb060') },
        glow2: { value: new THREE.Color('#ffd9a0') },
        sunCol: { value: new THREE.Color('#fff4e2') },
        haloCol: { value: new THREE.Color('#ffe2b8') },
        sunDir: { value: sunDir },
        beamTime: beamTime,
      },
      vertexShader: /* glsl */ `
        varying vec3 vDir;
        void main() {
          vDir = position;
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }`,
      fragmentShader: /* glsl */ `
        uniform vec3 band0;
        uniform vec3 band1;
        uniform vec3 band2;
        uniform vec3 band3;
        uniform vec3 sunCol;
        uniform vec3 haloCol;
        uniform vec3 glow1;
        uniform vec3 glow2;
        uniform vec3 sunDir;
        uniform float beamTime;
        varying vec3 vDir;
        ${STIPPLE_GLSL}
        // Colour bands meeting in a stippled seam.
        float edge(float at, float y) { return stipple(smoothstep(at - 0.045, at + 0.045, y)); }
        void main() {
          vec3 d = normalize(vDir);
          float y = max(d.y, 0.0);
          vec3 col = band0;
          col = mix(col, band1, edge(0.07, y));
          col = mix(col, band2, edge(0.2, y));
          col = mix(col, band3, edge(0.42, y));
          col *= 0.88;
          float s = dot(d, sunDir);
          float ss = max(s, 0.0);
          // Light bleeding out of the sun: a smooth wash that warms the bands around it,
          // strongest along the horizon where the low sun sits.
          float azim = max(dot(normalize(d.xz + vec2(1e-5)), normalize(sunDir.xz)), 0.0);
          float horizonGlow = (1.0 - smoothstep(0.0, 0.16, y)) * pow(azim, 6.0);
          col += glow1 * (pow(ss, 5.0) * 0.22 + horizonGlow * 0.18);
          col = mix(col, glow1, stipple(pow(ss, 16.0)) * 0.7);
          col = mix(col, glow2, stipple(pow(ss, 70.0)) * 0.85);
          // Sunbeams: a few long wedges fanning out of the sun, uneven in width, turning slowly,
          // fading out with distance from it and dissolving into stipple at their edges.
          vec3 beamRight = normalize(cross(sunDir, vec3(0.0, 1.0, 0.0)));
          vec3 beamUp = cross(beamRight, sunDir);
          vec3 rel = d - sunDir * s;
          float beamAngle = atan(dot(rel, beamUp), dot(rel, beamRight)) + beamTime * 0.02;
          float beamShape = sin(beamAngle * 7.0) * 0.6 + sin(beamAngle * 3.0 + 1.3) * 0.4;
          float beams = smoothstep(0.25, 0.75, beamShape) * smoothstep(0.55, 0.985, s) * (1.0 - smoothstep(0.994, 0.998, s));
          col = mix(col, glow2, stipple(beams) * 0.42);
          col = mix(col, haloCol, smoothstep(0.994, 0.9986, s) * 0.8);
          col = mix(col, sunCol, smoothstep(0.99895, 0.99905, s));
          col += sunCol * smoothstep(0.99895, 0.9999, s) * 0.15;
          gl_FragColor = vec4(col, 1.0);
          #include <colorspace_fragment>
        }`,
      side: THREE.BackSide,
      depthWrite: false,
      fog: false,
    }),
  );
  sky.renderOrder = -1;
  sky.frustumCulled = false;
  scene.add(sky);


  // Long shadows pointing away from the sun, drawn by the ground itself: under a shadow the
  // ground takes the same darkening as its darker patches, never anything darker. Each entry
  // is an ellipse (centre x, centre z, half width, half length) along SHADOW_DIR.
  const SHADOW_DIR = new THREE.Vector3(0.1, 0, 1).normalize();
  const MAX_SHADOWS = 8;
  const shadowUniform = { value: Array.from({ length: MAX_SHADOWS }, () => new THREE.Vector4(0, 0, 0, 0)) };
  function setShadow(i, x, z, width, length) {
    shadowUniform.value[i].set(x + SHADOW_DIR.x * length * 0.42, z + SHADOW_DIR.z * length * 0.42, width / 2, length / 2);
  }

  // Ground: three flat fields, indigo near, violet mid, magenta far, meeting at ragged
  // wavy lines rather than a smooth ramp, dotted with flat patches and painted with
  // little tuft marks in the next tone up, like strokes of a brush on a poster.
  // The grass rows share these tones, so each clump reads as a piece of the field it stands in.
  const GROUND = { near: '#2c1472', mid: '#5424a0', far: '#c23cc0', patch: '#c4b4e4' };
  // Each field line is a base depth plus sine waves [amplitude, frequency, phase]; the same
  // table places the hedges in JS and draws the seam in the ground shader.
  const EDGES = {
    edgeNear: [-7.2, [0.28, 1.3, 0.4], [0.16, 3.1, 2.0]],
    edgeFar: [-19, [0.9, 0.45, 1.0], [0.4, 1.7, 0]],
  };
  const edgeFn = ([base, ...waves]) => (x) => waves.reduce((z, [a, f, ph]) => z + a * Math.sin(x * f + ph), base);
  const EDGE_NEAR = edgeFn(EDGES.edgeNear);
  const EDGE_FAR = edgeFn(EDGES.edgeFar);
  const EDGE_GLSL = Object.entries(EDGES).map(([name, [base, ...waves]]) =>
    `float ${name}(float x) { return ${base.toFixed(2)}${waves.map(([a, f, ph]) => ` + ${a.toFixed(2)} * sin(x * ${f.toFixed(2)} + ${ph.toFixed(2)})`).join('')}; }`,
  ).join('\n');
  const MAX_ANISO = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  const groundGeo = new THREE.PlaneGeometry(600, 600, 1, 1);
  groundGeo.rotateX(-Math.PI / 2);
  const groundTex = canvasTexture(256, (c, s) => {
    c.fillStyle = '#ffffff';
    c.fillRect(0, 0, s, s);
    c.fillStyle = GROUND.patch;
    for (let i = 0; i < 14; i++) {
      const x = rand(0, s), y = rand(0, s), rx = rand(10, 30), ry = rx * rand(0.5, 0.9), r = rand(0, TAU);
      for (const [ox, oy] of TILE_OFFSETS(s)) {
        c.beginPath();
        c.ellipse(x + ox, y + oy, rx, ry, r, 0, TAU);
        c.fill();
      }
    }
  });
  groundTex.wrapS = groundTex.wrapT = THREE.RepeatWrapping;
  groundTex.repeat.set(40, 40);
  groundTex.anisotropy = MAX_ANISO;
  // Tuft marks: three tapered strokes fanning out of one root, white on black. Canvas up
  // maps to away from the viewer, so the strokes stand upright on screen.
  const HATCH_TILE = 2.6;
  const hatchTex = canvasTexture(512, (c, s) => {
    c.fillStyle = '#000';
    c.fillRect(0, 0, s, s);
    c.fillStyle = '#fff';
    const stroke = (x0, y0, x1, y1, w) => {
      const dx = x1 - x0, dy = y1 - y0, l = Math.hypot(dx, dy), nx = (-dy / l) * w, ny = (dx / l) * w;
      for (const [ox, oy] of TILE_OFFSETS(s)) {
        c.beginPath();
        c.moveTo(x0 + nx + ox, y0 + ny + oy);
        c.lineTo(x1 + ox, y1 + oy);
        c.lineTo(x0 - nx + ox, y0 - ny + oy);
        c.fill();
      }
    };
    for (let i = 0; i < 70; i++) {
      const x = rand(0, s), y = rand(0, s), h = rand(26, 46), n = 2 + Math.floor(Math.random() * 2);
      for (let j = 0; j < n; j++) {
        const lean = (j - (n - 1) / 2) * rand(5, 9) + rand(-3, 3);
        stroke(x + lean * 0.15, y, x + lean, y - h * rand(0.7, 1), rand(2, 2.8));
      }
    }
  });
  hatchTex.colorSpace = THREE.NoColorSpace;
  hatchTex.wrapS = hatchTex.wrapT = THREE.RepeatWrapping;
  hatchTex.anisotropy = MAX_ANISO;
  // The near/mid and mid/far seams are drawn by the ground shader below, not by flat()'s ramp.
  const groundMat = flat({ a: GROUND.near, b: GROUND.mid, space: 'world', facets: false, map: groundTex });
  const groundCompile = groundMat.onBeforeCompile;
  groundMat.onBeforeCompile = (shader, r) => {
    groundCompile(shader, r);
    shader.uniforms.uShadows = shadowUniform;
    shader.uniforms.uShadowDir = { value: new THREE.Vector2(SHADOW_DIR.x, SHADOW_DIR.z) };
    shader.uniforms.uShadowSide = { value: new THREE.Vector2(SHADOW_DIR.z, -SHADOW_DIR.x) };
    shader.uniforms.uPatch = { value: new THREE.Color(GROUND.patch) };
    shader.uniforms.uGroundFar = { value: new THREE.Color(GROUND.far) };
    shader.uniforms.uHatch = { value: hatchTex };
    shader.fragmentShader = shader.fragmentShader
      .replace('void main() {', `uniform vec4 uShadows[${MAX_SHADOWS}];
        uniform vec2 uShadowDir;
        uniform vec2 uShadowSide;
        uniform vec3 uPatch;
        uniform vec3 uGroundFar;
        uniform sampler2D uHatch;
        ${EDGE_GLSL}
        float groundHatch(vec2 offset) {
          vec2 huv = vec2(vFlatWorld.x, -vFlatWorld.z) / ${HATCH_TILE.toFixed(1)} + offset;
          return smoothstep(0.35, 0.75, texture2D(uHatch, huv).r);
        }
        // Near field to mid field: a ragged line with a thin stippled fringe in front of it,
        // plus the near field's tuft marks painted in the mid tone.
        float groundNearMid() {
          float z = vFlatWorld.z, e = edgeNear(vFlatWorld.x);
          return max(stipple(smoothstep(-e - 0.3, -e + 0.02, -z)), groundHatch(vec2(0.0)));
        }
        // Mid field to far field, with sparser marks in the far tone across the mid field,
        // kept off the dog's play area so it stays a clean flat stage.
        float groundMidFar() {
          float z = vFlatWorld.z, e1 = edgeNear(vFlatWorld.x), e2 = edgeFar(vFlatWorld.x);
          float field = stipple(smoothstep(-e2 - 1.4, -e2 + 0.05, -z));
          float midMarks = step(z, e1 - 0.4) * groundHatch(vec2(0.37, 0.61)) * step(0.0, sin(vFlatWorld.x * 0.8 + 1.0) + sin(vFlatWorld.z * 1.1));
          vec2 play = step(vec2(${DOG_AREA.x0.toFixed(1)}, ${DOG_AREA.z0.toFixed(1)}), vFlatWorld.xz) * step(vFlatWorld.xz, vec2(${DOG_AREA.x1.toFixed(1)}, ${DOG_AREA.z1.toFixed(1)}));
          midMarks *= 1.0 - play.x * play.y;
          return max(field, midMarks);
        }
        void main() {`)
      .replace('stipple(clamp(vFlatT, 0.0, 1.0))), opacity);', `groundNearMid()), opacity);
        diffuseColor.rgb = mix(diffuseColor.rgb, uGroundFar, groundMidFar());`)
      .replace('#include <map_fragment>', `vec3 groundBase = diffuseColor.rgb;
        #include <map_fragment>
        bool shaded = false;
        for (int i = 0; i < ${MAX_SHADOWS}; i++) {
          vec4 e = uShadows[i];
          if (e.z <= 0.0) continue;
          vec2 d = vFlatWorld.xz - e.xy;
          vec2 q = vec2(dot(d, uShadowSide) / e.z, dot(d, uShadowDir) / e.w);
          if (dot(q, q) < 1.0) {
            shaded = true;
            break;
          }
        }
        if (shaded) diffuseColor.rgb = groundBase * uPatch;`);
  };
  const ground = new THREE.Mesh(groundGeo, groundMat);
  scene.add(ground);

  // Grass: flat cut-paper clumps with zig-zag crowns, turned to face the viewer and laid
  // in rows. Each row holds one tone of the ground, its crown tips stippled into the next
  // tone up; the rows along the field lines are dense hedges that give each field a ragged
  // top edge against the one behind it.
  const grassTime = { value: 0 };
  {
    function clumpGeo(spikes) {
      const pos = [0, 0, 0], idx = [];
      const pts = [[-0.5, 0]];
      for (let i = 0; i < spikes; i++) {
        const x0 = -0.5 + i / spikes, x1 = -0.5 + (i + 1) / spikes;
        const apexX = lerp(x0, x1, rand(0.3, 0.7)) + rand(-0.05, 0.05);
        const edgeFade = 1 - Math.pow(Math.abs(apexX) * 2, 2) * 0.45;
        pts.push([apexX, rand(0.7, 1) * edgeFade]);
        if (i < spikes - 1) pts.push([x1, rand(0.42, 0.6) * edgeFade]);
      }
      pts.push([0.5, 0]);
      for (const [x, y] of pts) pos.push(x, y, 0);
      for (let i = 1; i < pts.length - 1; i++) idx.push(0, i, i + 1);
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      geo.setAttribute('normal', new THREE.Float32BufferAttribute(new Array(pos.length).fill(0).map((_, i) => (i % 3 === 2 ? 1 : 0)), 3));
      geo.setIndex(idx);
      return geo;
    }

    function clumpMat(body, crown) {
      // Local y runs 0 at the root to 1 at the tallest spike; the crown tone takes over near the tips.
      const mat = flat({ a: body, b: crown, axis: [0, 1, 0], from: 0.5, to: 0.85, facets: false });
      mat.side = THREE.DoubleSide;
      const flatCompile = mat.onBeforeCompile;
      mat.onBeforeCompile = (shader, r) => {
        flatCompile(shader, r);
        shader.uniforms.uTime = grassTime;
        shader.vertexShader = 'uniform float uTime;\n' + shader.vertexShader.replace(
          '#include <begin_vertex>',
          `#include <begin_vertex>
          #ifdef USE_INSTANCING
            vec2 ip = vec2(instanceMatrix[3].x, instanceMatrix[3].z);
          #else
            vec2 ip = vec2(0.0);
          #endif
          float sway = sin(uTime * 1.3 + ip.x * 0.6 + ip.y * 0.4) * 0.6 + sin(uTime * 2.3 + ip.x * 1.1) * 0.25;
          transformed.x += sway * 0.05 * position.y * position.y;`,
        );
      };
      return mat;
    }

    const shapes = [clumpGeo(7), clumpGeo(9), clumpGeo(11)];
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), up = new THREE.Vector3(0, 1, 0);
    const p = new THREE.Vector3(), sc = new THREE.Vector3();
    const inPlay = (x, z) => x > DOG_AREA.x0 - 0.8 && x < DOG_AREA.x1 + 0.8 && z > DOG_AREA.z0 - 0.5 && z < DOG_AREA.z1 + 1.2;
    function addRow(mat, items) {
      const perShape = shapes.map(() => []);
      for (const it of items) perShape[Math.floor(Math.random() * shapes.length)].push(it);
      perShape.forEach((list, s) => {
        if (!list.length) return;
        const mesh = new THREE.InstancedMesh(shapes[s], mat, list.length);
        list.forEach(([x, z, w, h], i) => {
          p.set(x, 0, z);
          q.setFromAxisAngle(up, Math.atan2(VIEW_CAM_POS.x - x, VIEW_CAM_POS.z - z));
          sc.set(w * (Math.random() < 0.5 ? -1 : 1), h, 1);
          mesh.setMatrixAt(i, m.compose(p, q, sc));
        });
        mesh.frustumCulled = false;
        scene.add(mesh);
      });
    }

    // Foreground clumps: indigo bodies melting into the near field, violet crowns.
    const fore = [];
    for (let i = 0; i < 260; i++) {
      const x = rand(-9, 9), z = rand(-6.6, -3.2);
      if (z < EDGE_NEAR(x) + 0.4) continue;
      const h = rand(0.18, 0.36) * lerp(1.25, 0.8, smoothstep(-3.2, -6.6, z));
      fore.push([x, z, h * rand(1.3, 2.2), h]);
    }
    // A front row of larger clumps toward the sides frames the view.
    for (let i = 0; i < 70; i++) {
      const x = rand(-7, 7), z = rand(-5.2, -3.4);
      if (Math.abs(x) < 1.3) continue;
      const h = rand(0.34, 0.6);
      fore.push([x, z, h * rand(1.5, 2.3), h]);
    }
    addRow(clumpMat(GROUND.near, GROUND.mid), fore);

    // The near field's ragged top edge: a dense indigo hedge on the field line, kept low
    // where the dog plays behind it.
    const hedgeNear = [];
    for (let x = -22; x < 18; x += rand(0.18, 0.34)) {
      const z = EDGE_NEAR(x) + rand(-0.05, 0.12);
      const low = x > DOG_AREA.x0 - 0.8 && x < DOG_AREA.x1 + 0.8;
      const h = low ? rand(0.1, 0.17) : rand(0.2, 0.4);
      hedgeNear.push([x, z, h * rand(1.6, 2.6), h]);
    }
    addRow(clumpMat(GROUND.near, GROUND.near), hedgeNear);

    // Mid field clumps: violet with magenta crowns, sparse, clear of the dog's play area.
    const mid = [];
    for (let i = 0; i < 420; i++) {
      const x = rand(-24, 20), z = rand(-18, -8);
      if (z > EDGE_NEAR(x) - 0.5 || z < EDGE_FAR(x) + 0.8 || inPlay(x, z)) continue;
      const h = rand(0.18, 0.34);
      mid.push([x, z, h * rand(1.4, 2.2), h]);
    }
    addRow(clumpMat(GROUND.mid, GROUND.far), mid);

    // The mid field's ragged top edge against the magenta far field.
    const hedgeFar = [];
    for (let x = -40; x < 34; x += rand(0.35, 0.7)) {
      const z = EDGE_FAR(x) + rand(-0.1, 0.25);
      const h = rand(0.28, 0.55);
      hedgeFar.push([x, z, h * rand(1.6, 2.6), h]);
    }
    addRow(clumpMat(GROUND.mid, GROUND.mid), hedgeFar);

    // A few magenta clumps scattered across the far field.
    const far = [];
    for (let i = 0; i < 90; i++) {
      const x = rand(-45, 40), z = rand(-34, -20);
      if (z > EDGE_FAR(x) - 1) continue;
      const h = rand(0.35, 0.7);
      far.push([x, z, h * rand(1.5, 2.4), h]);
    }
    addRow(clumpMat(GROUND.far, GROUND.far), far);
  }

  // Trees and hills in the middle and far distance.
  {
    const trunkMat = flat({ a: '#1c0c40' });
    const leafNear = ['#33188a', '#401c9c', '#2c1480'].map((c) => new THREE.Color(c));
    const leafFar = new THREE.Color('#a24cb4'), trunkFar = new THREE.Color('#7a2e90');
    const trunkGeo = new THREE.CylinderGeometry(0.1, 0.16, 2.2, 6);
    const leafGeo = new THREE.IcosahedronGeometry(1.3, 0);
    const trees = [[-10, -17, 1.1], [-13.5, -21, 1.4], [7.5, -18, 1], [11, -26, 1.5], [-4, -30, 1.2], [18, -40, 1.8], [-22, -38, 1.7]];
    // The sun sits low behind the trees, so their shadows stretch toward the viewer.
    trees.forEach(([x, z, s], i) => {
      setShadow(i, x, z, 2 * s, 15 * s);
      const tree = new THREE.Group();
      // Trees further off fade toward the haze.
      const haze = smoothstep(17, 34, -z) * 0.85;
      const leafMats = leafNear.map((c) => flat({ a: '#' + c.clone().lerp(leafFar, haze).getHexString() }));
      const trunk = new THREE.Mesh(trunkGeo, haze > 0 ? flat({ a: '#' + new THREE.Color('#1c0c40').lerp(trunkFar, haze).getHexString() }) : trunkMat);
      trunk.position.y = 1.1;
      tree.add(trunk);
      for (let j = 0; j < 3; j++) {
        const leaf = new THREE.Mesh(leafGeo, leafMats[j]);
        leaf.position.set(rand(-0.5, 0.5), 2.6 + j * 0.55, rand(-0.5, 0.5));
        leaf.scale.setScalar(rand(0.8, 1.15) * (1 - j * 0.18));
        leaf.rotation.set(rand(0, TAU), rand(0, TAU), 0);
        tree.add(leaf);
      }
      tree.position.set(x, 0, z);
      tree.scale.setScalar(s);
      scene.add(tree);
    });

    const hillGeo = new THREE.SphereGeometry(1, 24, 12);
    const hills = [
      [-140, -110, 70, 7, 25], [-60, -95, 55, 5, 22], [10, -120, 80, 6, 26], [90, -100, 60, 6, 24],
      [170, -120, 70, 8, 30], [-25, -70, 30, 3.5, 14], [45, -65, 28, 3, 12],
    ];
    const near = new THREE.Color('#9c2a90'), far = new THREE.Color('#f6a28a');
    for (const [x, z, sx, sy, sz] of hills) {
      const hill = new THREE.Mesh(hillGeo, flat({ a: '#' + near.clone().lerp(far, smoothstep(60, 120, -z)).getHexString(), facets: false }));
      hill.position.set(x, 0, z);
      hill.scale.set(sx, sy, sz);
      scene.add(hill);
    }

  }

  // -------------------------------------------------------------------------
  // Phone model
  // -------------------------------------------------------------------------

  const uiCanvas = document.createElement('canvas');
  uiCanvas.width = SW * PT;
  uiCanvas.height = SH * PT;
  const g = uiCanvas.getContext('2d');
  const uiTex = new THREE.CanvasTexture(uiCanvas);
  uiTex.colorSpace = THREE.SRGBColorSpace;
  uiTex.anisotropy = MAX_ANISO;

  const frameMat = flat({ a: '#d98e7e' });
  const frontGlassMat = flat({ a: '#111111', facets: false });
  const screenMat = new THREE.MeshBasicMaterial({ map: uiTex, toneMapped: false });
  const backMat = flat({ a: '#c9776b' });
  const lensGlassMat = flat({ a: '#1e1a22', facets: false });
  const darkMat = flat({ a: '#1a1618', facets: false });
  const flashMat = flat({ a: '#fff3d6', facets: false });

  const phone = new THREE.Group();
  scene.add(phone);

  const { W, H, T, R } = PHONE;
  const BS = 0.0012, BT = 0.0015;
  const bodyGeo = new THREE.ExtrudeGeometry(roundedRectShape(W - 2 * BS, H - 2 * BS, R - BS), {
    depth: T - 2 * BT, bevelEnabled: true, bevelThickness: BT, bevelSize: BS, bevelSegments: 4, curveSegments: 24,
  });
  bodyGeo.translate(0, 0, -(T - 2 * BT) / 2);
  const body = new THREE.Mesh(bodyGeo, frameMat);
  phone.add(body);

  const GW = W - 2 * BS - 0.0002, GH = H - 2 * BS - 0.0002, GR = R - BS - 0.0001;
  const frontGlass = new THREE.Mesh(flatRoundedRect(GW, GH, GR), frontGlassMat);
  frontGlass.position.z = T / 2 + 0.00006;
  phone.add(frontGlass);

  // The screen keeps the UI canvas aspect so its pixels stay square.
  const SCW = GW - 2 * 0.0018, SCH = (SCW * SH) / SW;
  const screenMesh = new THREE.Mesh(flatRoundedRect(SCW, SCH, GR - 0.0018), screenMat);
  screenMesh.position.z = T / 2 + 0.00012;
  phone.add(screenMesh);

  const backGeo = flatRoundedRect(GW, GH, GR);
  backGeo.rotateY(Math.PI);
  const backGlass = new THREE.Mesh(backGeo, backMat);
  backGlass.position.z = -T / 2 - 0.00006;
  phone.add(backGlass);

  const PLW = GW - 0.0012, PLH = 0.042, PLD = 0.0015;
  const plateauGeo = new THREE.ExtrudeGeometry(roundedRectShape(PLW - 0.0008, PLH - 0.0008, GR - 0.001), {
    depth: PLD - 0.0008, bevelEnabled: true, bevelThickness: 0.0004, bevelSize: 0.0004, bevelSegments: 3, curveSegments: 20,
  });
  plateauGeo.translate(0, 0, 0.0004);
  plateauGeo.rotateY(Math.PI);
  const plateau = new THREE.Mesh(plateauGeo, flat({ a: '#b8665c' }));
  plateau.position.set(0, GH / 2 - 0.0006 - PLH / 2, -T / 2 - 0.00006);
  phone.add(plateau);
  const PLATE_FACE_Z = -T / 2 - 0.00006 - PLD;

  // Lens positions are in phone space; +x shows on the left when looking at the back.
  const LENS_MAIN = [0.0205, 0.0625];
  const lensSpots = [LENS_MAIN, [0.0205, 0.0415], [0.0055, 0.052]];
  const lensSideGeo = new THREE.CylinderGeometry(0.0086, 0.0082, 0.0017, 40, 1, true).rotateX(Math.PI / 2);
  const lensWallGeo = new THREE.CylinderGeometry(0.0061, 0.0061, 0.0004, 40, 1, true).rotateX(Math.PI / 2);
  const lensRingGeo = new THREE.RingGeometry(0.0061, 0.0082, 40).rotateY(Math.PI);
  const lensGlassGeo = new THREE.CircleGeometry(0.0061, 40).rotateY(Math.PI);
  const apertureGeo = new THREE.CircleGeometry(0.0026, 32).rotateY(Math.PI);
  for (const [x, y] of lensSpots) {
    const lens = new THREE.Group();
    lens.position.set(x, y, PLATE_FACE_Z);
    const side = new THREE.Mesh(lensSideGeo, frameMat);
    side.position.z = -0.00085;
    const ring = new THREE.Mesh(lensRingGeo, frameMat);
    ring.position.z = -0.0017;
    const wall = new THREE.Mesh(lensWallGeo, darkMat);
    wall.position.z = -0.0015;
    const glass = new THREE.Mesh(lensGlassGeo, lensGlassMat);
    glass.position.z = -0.0013;
    const aperture = new THREE.Mesh(apertureGeo, darkMat);
    aperture.position.z = -0.00133;
    lens.add(side, ring, wall, glass, aperture);
    phone.add(lens);
  }
  const flashDisc = new THREE.Mesh(new THREE.CircleGeometry(0.0034, 32).rotateY(Math.PI), flashMat);
  flashDisc.position.set(-0.0215, 0.0625, PLATE_FACE_Z - 0.00005);
  const sensorDisc = new THREE.Mesh(new THREE.CircleGeometry(0.0023, 32).rotateY(Math.PI), darkMat);
  sensorDisc.position.set(-0.0215, 0.043, PLATE_FACE_Z - 0.00005);
  phone.add(flashDisc, sensorDisc);

  function addButton(side, y, len, protrude, mat) {
    const b = new THREE.Mesh(new RoundedBoxGeometry(0.0014, len, 0.0034, 2, 0.0006), mat);
    b.position.set(side * (W / 2 - 0.0007 + protrude), y, 0);
    phone.add(b);
  }
  addButton(-1, 0.047, 0.0075, 0.0006, frameMat);
  addButton(-1, 0.03, 0.011, 0.0006, frameMat);
  addButton(-1, 0.016, 0.011, 0.0006, frameMat);
  addButton(1, 0.026, 0.017, 0.0006, frameMat);
  addButton(1, -0.018, 0.012, 0.0001, darkMat);

  // A cartoon right hand holding the phone from behind: palm on the back, thumb over the
  // +x edge, three fingers curled around the -x edge. The screen faces +z in phone space.
  const skinMat = flat({ a: '#ff8fbe', hard: true });
  const hand = new THREE.Group();
  phone.add(hand);
  const UP = new THREE.Vector3(0, 1, 0);
  function limb(from, to, r) {
    const a = new THREE.Vector3(...from), b = new THREE.Vector3(...to);
    const dir = b.clone().sub(a);
    const m = new THREE.Mesh(new THREE.CapsuleGeometry(r, dir.length(), 3, 8), skinMat);
    m.position.copy(a).add(b).multiplyScalar(0.5);
    m.quaternion.setFromUnitVectors(UP, dir.normalize());
    hand.add(m);
  }
  const backZ = -T / 2 - 0.0005;
  const palm = new THREE.Mesh(new THREE.SphereGeometry(1, 8, 6), skinMat);
  palm.scale.set(0.034, 0.044, 0.015);
  palm.position.set(0.004, -0.05, backZ - 0.013);
  hand.add(palm);
  limb([0.024, -0.076, backZ - 0.01], [W / 2 + 0.004, -0.038, T / 2 - 0.001], 0.0095);
  for (const y of [-0.022, -0.044, -0.066]) {
    const edge = [-W / 2 - 0.005, y - 0.003, -0.003];
    limb([-0.016, y, backZ - 0.012], edge, 0.0095);
    limb(edge, [-W / 2 - 0.002, y - 0.005, T / 2 - 0.001], 0.009);
  }
  const WRIST_LOCAL = new THREE.Vector3(0.008, -0.086, backZ - 0.012);
  const FOREARM_LOCAL = new THREE.Vector3(0.5, -0.8, 0.15).normalize();
  // Rounds off the hose's open end where it meets the palm.
  const wristBall = new THREE.Mesh(new THREE.SphereGeometry(0.0245, 8, 6), skinMat);
  wristBall.position.copy(WRIST_LOCAL);
  hand.add(wristBall);

  // The arm is one rubber hose from a shoulder below the frame to the wrist, re-bent
  // every frame so it follows the phone wherever it goes.
  const HOSE_SEGMENTS = 24, HOSE_RADIAL = 8, HOSE_R = 0.023;
  const hoseCurve = new THREE.CubicBezierCurve3(
    new THREE.Vector3(), new THREE.Vector3(), new THREE.Vector3(), new THREE.Vector3(),
  );
  // Built once for its index and uv layout; updateHose rewrites the rings in place every frame.
  const hoseGeo = new THREE.TubeGeometry(hoseCurve, HOSE_SEGMENTS, HOSE_R, HOSE_RADIAL);
  const hoseMat = flat({ a: '#7a48f0', b: '#ff8fbe', space: 'world', hard: true });
  const hose = new THREE.Mesh(hoseGeo, hoseMat);
  hose.frustumCulled = false;
  scene.add(hose);

  const phoneHit = [body, frontGlass, screenMesh, backGlass, plateau, ...hand.children];
  const LENS_LOCAL = new THREE.Vector3(LENS_MAIN[0], LENS_MAIN[1], PLATE_FACE_Z - 0.003);

  const flashOverlay = document.getElementById('heroFlash');
  let flashAt = -10;

  // -------------------------------------------------------------------------
  // Screen UI (canvas 2D, drawn in points)
  // -------------------------------------------------------------------------

  const lunarAge = ((((Date.now() / 1000 - 947182440) / 86400) % 29.53059) + 29.53059) % 29.53059;
  const fullMoon = Math.abs(lunarAge - 29.53059 / 2) < 0.5;
  const HOME_DIM = fullMoon ? 0.5 : 0.3;
  const HOME_BRIGHT = fullMoon ? 0.9 : 0.6;
  const CAPTURE_REST = 0.12;

  const WORD_X = 28;
  const WORD_BASE = SH - 50;
  g.font = font(300, 15);
  const HEART = { x: WORD_X + g.measureText('trueframe').width + 3 + 4, y: WORD_BASE - 4.5 };

  g.font = font(600, 56);
  const headLines = [];
  for (const para of ['hold to your heart', 'to capture life']) {
    let line = '';
    for (const word of para.split(' ')) {
      const test = line ? `${line} ${word}` : word;
      if (line && g.measureText(test).width > SW - 56) {
        headLines.push(line);
        line = word;
      } else {
        line = test;
      }
    }
    headLines.push(line);
  }
  const lastHeadBase = WORD_BASE - 41;
  const headBaselines = headLines.map((_, i) => lastHeadBase - (headLines.length - 1 - i) * 64);

  const CLUSTER = { x: SW - 20 - 130, y: 60, w: 130, h: 134 };
  const FLASH_POS = [CLUSTER.x + 38, CLUSTER.y + 38];
  const LENS_SLOTS = {
    '0.5': [CLUSTER.x + 38, CLUSTER.y + 96],
    '2x': [CLUSTER.x + 92, CLUSTER.y + 38],
    '1x': [CLUSTER.x + 92, CLUSTER.y + 96],
  };
  const WHEEL = { x: SW - 20 - 120, y: CLUSTER.y + CLUSTER.h + 12, w: 120, h: 32 };

  const ui = {
    mode: 'home',
    homeAt: 0,
    lens: '1x',
    flash: true,
    interval: 2,
    wheelFrom: 2,
    wheelTo: 2,
    wheelAt: -10,
    lensScale: { '0.5': 0.86, '1x': 1, '2x': 0.86 },
    beats: [],
    celebration: null,
    dirty: true,
  };
  let nextHomeBeat = 0.4;
  let pendingDouble = [];

  function addBeat(t, peak, rise, fall) {
    ui.beats.push({ t, peak, rise, fall });
    if (ui.beats.length > 8) ui.beats.shift();
  }

  function setMode(mode) {
    ui.mode = mode;
    ui.beats.length = 0;
    ui.dirty = true;
  }

  function heartAlpha(t) {
    const rest = ui.mode === 'home' ? HOME_DIM : CAPTURE_REST;
    let a = rest;
    for (const b of ui.beats) {
      const d = t - b.t;
      if (d < 0) continue;
      const env = d < b.rise ? d / b.rise : 1 - easeOutCubic(clamp((d - b.rise) / b.fall, 0, 1));
      a = Math.max(a, rest + (b.peak - rest) * env);
    }
    return a;
  }

  // Resting 52 bpm; about one beat in 500 is skipped and followed by two quick beats.
  function updateHomeBeats(t) {
    if (ui.mode !== 'home' || t < nextHomeBeat) return;
    if (pendingDouble.length) {
      const b = pendingDouble.shift();
      addBeat(b, HOME_BRIGHT, 0.05, 0.85);
      nextHomeBeat = pendingDouble.length ? pendingDouble[0] : b + HEART_PERIOD;
      return;
    }
    if (Math.random() < 1 / 500) {
      const first = nextHomeBeat + HEART_PERIOD * 1.6;
      pendingDouble = [first, first + 0.25];
      nextHomeBeat = first;
      return;
    }
    addBeat(nextHomeBeat, HOME_BRIGHT, 0.05, 0.85);
    nextHomeBeat += HEART_PERIOD;
  }

  function wheelPos(t) {
    return lerp(ui.wheelFrom, ui.wheelTo, easeInOutCubic(clamp((t - ui.wheelAt) / 0.25, 0, 1)));
  }

  function heartPath(cx, cy, s) {
    const w = s, h = s * 0.92, top = cy - h / 2;
    g.beginPath();
    g.moveTo(cx, top + h * 0.28);
    g.bezierCurveTo(cx, top, cx - w * 0.5, top, cx - w * 0.5, top + h * 0.3);
    g.bezierCurveTo(cx - w * 0.5, top + h * 0.58, cx - w * 0.12, top + h * 0.78, cx, top + h);
    g.bezierCurveTo(cx + w * 0.12, top + h * 0.78, cx + w * 0.5, top + h * 0.58, cx + w * 0.5, top + h * 0.3);
    g.bezierCurveTo(cx + w * 0.5, top, cx, top, cx, top + h * 0.28);
    g.closePath();
  }

  function drawHeart(alpha, glow) {
    g.save();
    if (glow > 0) {
      g.shadowColor = `rgba(255,255,255,${glow})`;
      g.shadowBlur = 16;
    }
    g.fillStyle = `rgba(255,255,255,${alpha})`;
    heartPath(HEART.x, HEART.y, 8);
    g.fill();
    g.restore();
  }

  function drawStatusBar() {
    g.fillStyle = '#fff';
    g.font = font(600, 17);
    g.textAlign = 'left';
    g.textBaseline = 'alphabetic';
    g.fillText('9:41', 50, 36);
    for (let i = 0; i < 4; i++) {
      const h = 4 + i * 2.4;
      roundRectPath(g, 296 + i * 4.6, 33 - h, 3, h, 0.9);
      g.fill();
    }
    const wx = 327, wy = 33;
    g.beginPath();
    g.moveTo(wx, wy);
    g.arc(wx, wy, 3.4, -Math.PI * 0.75, -Math.PI * 0.25);
    g.closePath();
    g.fill();
    g.strokeStyle = '#fff';
    g.lineWidth = 1.7;
    g.lineCap = 'round';
    for (const r of [6.6, 9.8]) {
      g.beginPath();
      g.arc(wx, wy, r, -Math.PI * 0.75, -Math.PI * 0.25);
      g.stroke();
    }
    g.globalAlpha = 0.4;
    roundRectPath(g, 342, 23.5, 25, 12, 3.6);
    g.lineWidth = 1;
    g.stroke();
    roundRectPath(g, 368, 27.5, 1.6, 4, 0.8);
    g.fill();
    g.globalAlpha = 1;
    roundRectPath(g, 344, 25.5, 21, 8, 2);
    g.fill();

    roundRectPath(g, (SW - 126) / 2, 11, 126, 37, 18.5);
    g.fillStyle = '#000';
    g.fill();
    g.strokeStyle = '#0a0a0a';
    g.lineWidth = 1;
    g.stroke();
  }

  function drawLens(key) {
    const [cx, cy] = LENS_SLOTS[key];
    const s = ui.lensScale[key];
    const sel = clamp((s - 0.86) / 0.14, 0, 1);
    const r = 26 * s;
    g.beginPath();
    g.arc(cx, cy, r, 0, TAU);
    g.fillStyle = 'rgba(255,255,255,0.08)';
    g.fill();
    const gr = g.createRadialGradient(cx, cy, 0, cx, cy, r * 0.55);
    gr.addColorStop(0, 'rgba(0,0,0,0.6)');
    gr.addColorStop(1, 'rgba(0,0,0,0.3)');
    g.beginPath();
    g.arc(cx, cy, r * 0.55, 0, TAU);
    g.fillStyle = gr;
    g.fill();
    if (sel > 0.01) {
      g.beginPath();
      g.arc(cx, cy, r - 0.5, 0, TAU);
      g.lineWidth = 1;
      g.strokeStyle = `rgba(255,255,255,${0.6 * sel})`;
      g.stroke();
    }
    g.font = font(500, 12);
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillStyle = `rgba(255,255,255,${lerp(0.3, 0.9, sel)})`;
    g.fillText(key, cx, cy + 0.5);
  }

  function drawFlash() {
    const [cx, cy] = FLASH_POS;
    const on = ui.flash;
    g.beginPath();
    g.arc(cx, cy, 12, 0, TAU);
    g.fillStyle = on ? 'rgba(255,214,10,0.16)' : 'rgba(255,255,255,0.08)';
    g.fill();
    const k = 0.62;
    const pts = [[2, -9], [-6, 1.5], [-0.5, 1.5], [-2, 9], [6, -1.5], [0.5, -1.5]];
    g.beginPath();
    pts.forEach(([x, y], i) => (i ? g.lineTo(cx + x * k, cy + y * k) : g.moveTo(cx + x * k, cy + y * k)));
    g.closePath();
    if (on) {
      g.fillStyle = '#FFD60A';
      g.fill();
    } else {
      g.lineWidth = 1.1;
      g.lineJoin = 'round';
      g.strokeStyle = 'rgba(255,255,255,0.2)';
      g.stroke();
      g.beginPath();
      g.moveTo(cx - 6, cy - 6);
      g.lineTo(cx + 6, cy + 6);
      g.stroke();
    }
  }

  function drawWheel(t) {
    const { x, y, w, h } = WHEEL;
    const cx = x + w / 2, cy = y + h / 2;
    const pos = wheelPos(t);
    g.save();
    roundRectPath(g, x, y, w, h, h / 2);
    g.fillStyle = 'rgba(255,255,255,0.08)';
    g.fill();
    g.clip();
    roundRectPath(g, cx - 16, cy - 12, 32, 24, 8);
    g.fillStyle = 'rgba(255,255,255,0.15)';
    g.fill();
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    INTERVAL_LABELS.forEach((label, i) => {
      const d = Math.abs(i - pos);
      if (d > 2.6) return;
      const alpha = d < 1 ? lerp(1, 0.3, d) : 0.3 * (1 - clamp((d - 1) / 1.6, 0, 1));
      g.font = font(d < 0.5 ? 700 : 400, 10 * (1 - 0.12 * Math.min(d, 2)));
      g.fillStyle = `rgba(255,255,255,${alpha})`;
      g.fillText(label, cx + (i - pos) * 32, cy + 0.5);
    });
    g.restore();
  }

  function drawHome(t, ha) {
    const e = t - ui.homeAt;
    const rise = reduced ? 0 : 12;
    drawStatusBar();

    g.textAlign = 'left';
    g.textBaseline = 'alphabetic';
    g.font = font(600, 56);
    headLines.forEach((line, i) => {
      const k = easeOutCubic(clamp((e - i * 0.12) / 0.5, 0, 1));
      if (k <= 0) return;
      g.fillStyle = `rgba(255,255,255,${0.2 * k})`;
      g.fillText(line, 28, headBaselines[i] + rise * (1 - k));
    });

    const wk = easeOutCubic(clamp((e - headLines.length * 0.12) / 0.5, 0, 1));
    if (wk > 0) {
      g.font = font(300, 15);
      g.fillStyle = `rgba(255,255,255,${0.2 * wk})`;
      g.fillText('trueframe', WORD_X, WORD_BASE + rise * (1 - wk));
    }
    drawHeart(ha, 0);

    const ck = clamp((e - 0.1) / 0.5, 0, 1);
    if (ck > 0) {
      g.save();
      g.globalAlpha = 0.7 * ck;
      roundRectPath(g, CLUSTER.x, CLUSTER.y, CLUSTER.w, CLUSTER.h, 20);
      g.fillStyle = 'rgba(255,255,255,0.06)';
      g.fill();
      g.lineWidth = 0.75;
      g.strokeStyle = 'rgba(255,255,255,0.12)';
      g.stroke();
      drawFlash();
      for (const key of Object.keys(LENS_SLOTS)) drawLens(key);
      drawWheel(t);
      g.restore();
    }
  }

  function drawPhoto(img, x, y, rot, along, across, dir, alpha) {
    if (alpha <= 0.002 || along <= 0.001 || across <= 0.001) return;
    g.save();
    g.globalAlpha = alpha;
    g.translate(x, y);
    if (along !== 1 || across !== 1) {
      g.rotate(dir);
      g.scale(along, across);
      g.rotate(-dir);
    }
    g.rotate(rot);
    roundRectPath(g, -48, -48, 96, 96, 10);
    g.save();
    g.clip();
    g.drawImage(img, -48, -48, 96, 96);
    g.restore();
    g.lineWidth = 1;
    g.strokeStyle = 'rgba(255,255,255,0.15)';
    g.stroke();
    g.restore();
  }

  function drawCelebration(t, ha) {
    const c = ui.celebration;
    const e = t - c.t0;

    if (c.reduced) {
      const a = Math.min(clamp(e / 0.3, 0, 1), clamp((c.end - e) / 0.3, 0, 1));
      for (const p of c.photos) drawPhoto(p.frame.canvas, p.x, p.y, p.a, 1, 1, 0, a);
      drawHeart(ha, 0);
      return;
    }

    c.photos.forEach((p, i) => {
      const collapseStart = c.collapseAt + 0.03 * i;
      if (e < collapseStart) {
        const rp = clamp((e - 0.03 * i) / 0.5, 0, 1);
        if (rp <= 0) return;
        drawPhoto(p.frame.canvas, p.x, p.y + 200 * (1 - easeOutBack(rp)), p.a, 1, 1, 0, Math.min(1, rp * 3));
        return;
      }
      // Falling into the heart: eased-in travel, stretched along the path and squeezed across it,
      // then shrinking to nothing as it arrives.
      const q = clamp((e - collapseStart) / 0.55, 0, 1);
      if (q >= 1) return;
      const m = easeInCubic(q);
      const dir = Math.atan2(HEART.y - p.y, HEART.x - p.x);
      const shrink = 1 - smoothstep(0.55, 1, q);
      const along = (1 + 0.3 * smoothstep(0, 0.6, q)) * shrink;
      const across = lerp(1, 0.2, smoothstep(0, 0.8, q)) * shrink;
      drawPhoto(
        p.frame.canvas, lerp(p.x, HEART.x, m), lerp(p.y, HEART.y, m),
        p.a * (1 - m), along, across, dir, 1 - smoothstep(0.7, 1, q),
      );
    });

    const bt = e - c.burstAt;
    if (bt >= 0 && c.sparks) {
      g.save();
      g.globalCompositeOperation = 'lighter';
      const [gr0, gg0, gb0] = c.glow;
      const ga = 0.55 * Math.exp(-bt * 3.2);
      const grad = g.createRadialGradient(HEART.x, HEART.y, 0, HEART.x, HEART.y, 60);
      grad.addColorStop(0, `rgba(${gr0},${gg0},${gb0},${ga})`);
      grad.addColorStop(1, `rgba(${gr0},${gg0},${gb0},0)`);
      g.fillStyle = grad;
      g.fillRect(HEART.x - 60, HEART.y - 60, 120, 120);

      const rp = clamp(bt / 0.7, 0, 1);
      if (rp < 1) {
        g.beginPath();
        g.arc(HEART.x, HEART.y, 6 + 64 * easeOutCubic(rp), 0, TAU);
        g.lineWidth = lerp(2, 0.5, rp);
        g.strokeStyle = `rgba(255,255,255,${0.45 * (1 - rp)})`;
        g.stroke();
      }

      // Distance follows 1 - e^(-kt), normalised so each spark reaches its full reach at end of life.
      const k = 3.2;
      for (const s of c.sparks) {
        const u = bt / s.life;
        if (u >= 1) continue;
        const travel = (1 - Math.exp(-k * bt)) / (1 - Math.exp(-k * s.life));
        g.globalAlpha = Math.pow(1 - u, 1.4);
        g.fillStyle = s.col;
        g.beginPath();
        g.arc(HEART.x + Math.cos(s.a) * s.d * travel, HEART.y + Math.sin(s.a) * s.d * travel, s.r * (1 - 0.5 * u), 0, TAU);
        g.fill();
      }
      g.restore();
    }
    drawHeart(ha, Math.max(0, ha - CAPTURE_REST));
  }

  function drawUI(t, ha) {
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.globalAlpha = 1;
    g.globalCompositeOperation = 'source-over';
    g.fillStyle = '#000';
    g.fillRect(0, 0, uiCanvas.width, uiCanvas.height);
    g.setTransform(PT, 0, 0, PT, 0, 0);
    g.imageSmoothingQuality = 'high';
    if (ui.mode === 'home') drawHome(t, ha);
    else if (ui.mode === 'capture') drawHeart(ha, Math.max(0, (ha - CAPTURE_REST) * 1.6));
    else drawCelebration(t, ha);
    uiTex.needsUpdate = true;
  }

  let lastHeartA = -1;
  let lastDrawAt = -1;
  function updateUI(t, dt) {
    let lensBusy = false;
    for (const key of Object.keys(ui.lensScale)) {
      const target = key === ui.lens ? 1 : 0.86;
      ui.lensScale[key] = damp(ui.lensScale[key], target, 16, dt);
      if (Math.abs(ui.lensScale[key] - target) > 0.002) lensBusy = true;
    }
    updateHomeBeats(t);
    updateCelebration(t);

    const ha = heartAlpha(t);
    const busy = ui.mode === 'celebrate'
      || (ui.mode === 'home' && t - ui.homeAt < 1.3)
      || t - ui.wheelAt < 0.3
      || lensBusy;
    const heartChanged = Math.abs(ha - lastHeartA) > 0.003;
    if (!(busy || ui.dirty || (heartChanged && t - lastDrawAt >= 1 / 30))) return;
    drawUI(t, ha);
    lastHeartA = ha;
    lastDrawAt = t;
    ui.dirty = false;
  }

  function uiTap(x, y) {
    if (ui.mode !== 'home') return false;
    if (Math.hypot(x - FLASH_POS[0], y - FLASH_POS[1]) < 18) {
      ui.flash = !ui.flash;
      ui.dirty = true;
      return true;
    }
    for (const [key, [cx, cy]] of Object.entries(LENS_SLOTS)) {
      if (Math.hypot(x - cx, y - cy) < 27) {
        ui.lens = key;
        ui.dirty = true;
        return true;
      }
    }
    const { x: wx, y: wy, w, h } = WHEEL;
    if (x >= wx - 4 && x <= wx + w + 4 && y >= wy - 6 && y <= wy + h + 6) {
      const cx = wx + w / 2;
      let idx = Math.round(ui.wheelTo + (x - cx) / 32);
      if (idx === ui.wheelTo) idx += x < cx ? -1 : 1;
      idx = clamp(idx, 0, INTERVALS.length - 1);
      if (idx !== ui.interval) {
        ui.wheelFrom = wheelPos(time);
        ui.wheelTo = idx;
        ui.wheelAt = time;
        ui.interval = idx;
      }
      return true;
    }
    return x >= CLUSTER.x && x <= CLUSTER.x + CLUSTER.w && y >= CLUSTER.y && y <= CLUSTER.y + CLUSTER.h;
  }

  // -------------------------------------------------------------------------
  // Dog
  // -------------------------------------------------------------------------

  const dog = (() => {
    // The coat shifts from orange to orange-red toward the paws, in world height.
    const coat = flat({ a: '#e89a4c', b: '#e0673a', axis: [0, -1, 0], from: -0.6, to: -0.12, space: 'world' });
    const cream = flat({ a: '#fbe3c4' });
    const ears = flat({ a: '#c9602e' });
    const black = flat({ a: '#2a1a14', facets: false });
    const sphere = (r) => new THREE.SphereGeometry(r, 16, 12);
    const capsule = (r, l) => new THREE.CapsuleGeometry(r, l, 4, 12);
    const add = (parent, geo, mat, [x, y, z], [rx, ry, rz] = [0, 0, 0], [sx, sy, sz] = [1, 1, 1]) => {
      const m = new THREE.Mesh(geo, mat);
      m.position.set(x, y, z);
      m.rotation.set(rx, ry, rz);
      m.scale.set(sx, sy, sz);
      parent.add(m);
      return m;
    };

    const root = new THREE.Group();
    const bodyPivot = new THREE.Group();
    bodyPivot.position.y = 0.495;
    root.add(bodyPivot);
    add(bodyPivot, capsule(0.14, 0.4), coat, [0, 0, 0], [Math.PI / 2, 0, 0], [0.92, 1, 1]);
    add(bodyPivot, sphere(0.15), cream, [0, -0.035, 0.22], [0, 0, 0], [0.85, 0.95, 0.9]);
    add(bodyPivot, sphere(0.15), coat, [0, 0.01, -0.2], [0, 0, 0], [0.95, 0.95, 0.95]);

    const neck = new THREE.Group();
    neck.rotation.order = 'YXZ';
    neck.position.set(0, 0.07, 0.26);
    bodyPivot.add(neck);
    add(neck, capsule(0.075, 0.12), coat, [0, 0.08, 0.03], [0.45, 0, 0]);

    const head = new THREE.Group();
    head.rotation.order = 'YXZ';
    head.position.set(0, 0.17, 0.07);
    neck.add(head);
    add(head, sphere(0.105), coat, [0, 0, 0], [0, 0, 0], [0.95, 0.92, 1.05]);
    add(head, capsule(0.05, 0.07), cream, [0, -0.035, 0.1], [Math.PI / 2, 0, 0], [1, 1, 0.9]);
    add(head, sphere(0.024), black, [0, -0.02, 0.178]);
    const eyes = [
      add(head, sphere(0.014), black, [0.045, 0.03, 0.085]),
      add(head, sphere(0.014), black, [-0.045, 0.03, 0.085]),
    ];
    // A wide grin, folded away until the dog shows it off.
    const mouth = new THREE.Group();
    mouth.position.set(0, -0.062, 0.125);
    mouth.scale.setScalar(0.001);
    head.add(mouth);
    add(mouth, sphere(0.05), black, [0, 0, 0], [0, 0, 0], [1.25, 0.55, 0.5]);
    add(mouth, capsule(0.012, 0.09), flat({ a: '#f4efe6', facets: false }), [0, 0.016, 0.012], [0, 0, Math.PI / 2]);
    add(mouth, sphere(0.026), flat({ a: '#e0707a' }), [0, -0.016, 0.012], [0, 0, 0], [1, 0.6, 0.8]);
    const earPivots = [1, -1].map((side) => {
      const ear = new THREE.Group();
      ear.position.set(side * 0.075, 0.05, -0.005);
      ear.userData.side = side;
      head.add(ear);
      add(ear, sphere(0.06), ears, [0, -0.055, 0], [0, 0, 0], [0.35, 1, 0.8]);
      return ear;
    });

    const tail = new THREE.Group();
    tail.rotation.order = 'YXZ';
    tail.position.set(0, 0.07, -0.32);
    bodyPivot.add(tail);
    add(tail, capsule(0.03, 0.24), coat, [0, 0.14, 0]);

    // Leg order: front left, front right, hind left, hind right.
    const legs = [[0.085, 0.2, true], [-0.085, 0.2, true], [0.085, -0.2, false], [-0.085, -0.2, false]].map(([x, z, front]) => {
      const hip = new THREE.Group();
      hip.position.set(x, -0.07, z);
      bodyPivot.add(hip);
      add(hip, capsule(front ? 0.042 : 0.058, 0.13), coat, [0, -0.1, 0]);
      const knee = new THREE.Group();
      knee.position.y = -0.2;
      hip.add(knee);
      add(knee, capsule(0.034, 0.14), front ? cream : coat, [0, -0.1, 0]);
      add(knee, sphere(0.038), cream, [0, -0.205, 0.02], [0, 0, 0], [1, 0.55, 1.35]);
      return { hip, knee, front, side: Math.sign(x) };
    });

    scene.add(root);
    return { root, body: bodyPivot, neck, head, ears: earPivots, tail, legs, eyes, mouth };
  })();

  const GAITS = {
    run: { speed: 4.2, freq: 3.0, amp: 0.8, offs: [0, 0.1, 0.55, 0.65], bob: 0.05, pitch: 0.09, harm: 1 },
    trot: { speed: 1.8, freq: 2.4, amp: 0.5, offs: [0, 0.5, 0.5, 0], bob: 0.018, pitch: 0.02, harm: 2 },
    walk: { speed: 0.75, freq: 1.3, amp: 0.34, offs: [0, 0.5, 0.75, 0.25], bob: 0.01, pitch: 0.015, harm: 2 },
  };
  const STAND = {
    bodyY: 0.495, bodyZ: 0, pitch: 0, frontHip: 0, frontKnee: 0, hindHip: -0.2, hindKnee: 0.35,
    neckX: 0, headX: 0, headYaw: 0, tail: -0.8, wagAmp: 0.3, wagFreq: 2.2, ear: 0,
    // Lying on a side: body roll, extra neck and head turn, and how far the top hind leg is raised.
    roll: 0, neckTurn: 0, headTurn: 0, raise: 0,
  };
  const POSES = {
    run: { ...STAND, neckX: 0.3, headX: -0.2, tail: -1.35, wagAmp: 0.12, wagFreq: 3, ear: 0.7 },
    trot: { ...STAND, neckX: 0.15, tail: -0.9, wagAmp: 0.35, wagFreq: 3, ear: 0.3 },
    walk: { ...STAND, neckX: 0.1, wagAmp: 0.3, wagFreq: 2, ear: 0.1 },
    sit: {
      ...STAND, bodyY: 0.36, bodyZ: -0.05, pitch: -0.62, frontHip: 0.62, hindHip: -0.58, hindKnee: 2.3,
      neckX: 0.35, headX: 0.25, tail: -2.3, wagAmp: 0.35, wagFreq: 3.5,
    },
    look: { ...STAND, neckX: -0.1, headX: -0.05, tail: -0.6, wagAmp: 0.7, wagFreq: 7, ear: -0.15 },
    // After a sprint: flops onto its right side, the top hind leg in the air, head curled back to lick it.
    lick: {
      ...STAND, bodyY: 0.2, frontHip: 0.3, frontKnee: 0.4, hindHip: -0.1, hindKnee: 0.6,
      neckX: 0.1, headX: 0.5, tail: -1.4, wagAmp: 0.2, wagFreq: 2, ear: 0.2,
      roll: 1.4, neckTurn: 1.6, headTurn: 1.25, raise: 1,
    },
    sniff: {
      ...STAND, bodyY: 0.47, pitch: 0.18, frontHip: -0.18, frontKnee: 0.25, neckX: 1.35, headX: 0.5,
      tail: -0.7, wagAmp: 0.25, wagFreq: 1.8, ear: -0.3,
    },
  };

  const dogSim = {
    x: -1.2, z: -7.2, yaw: 0.6, speed: 0, state: 'look', timer: 2.5, tx: 0, tz: 0,
    gait: 'trot', phase: 0, wag: 0, amp: 0, time: 0, pose: { ...STAND },
    stunt: null, stuntAt: -1, nextStunt: 0,
  };
  // Something odd the dog does while the phone is at your heart, one per press, alternating.
  const STUNTS = { tornado: 3.2, belly: 3.4, butterfly: 4.6, grin: 3.2 };
  const STUNT_ORDER = ['tornado', 'butterfly', 'belly', 'grin'];

  const butterfly = (() => {
    const group = new THREE.Group();
    const wingMat = flat({ a: '#f2c14e', b: '#e07a3a', axis: [1, 0, 0], from: 0, to: 0.07, facets: false });
    wingMat.side = THREE.DoubleSide;
    const wingGeo = new THREE.BufferGeometry().setFromPoints([
      new THREE.Vector3(0, 0, 0.02), new THREE.Vector3(0.07, 0, 0.05), new THREE.Vector3(0.06, 0, -0.035),
      new THREE.Vector3(0, 0, 0.02), new THREE.Vector3(0.06, 0, -0.035), new THREE.Vector3(0, 0, -0.03),
    ]);
    const wings = [1, -1].map((side) => {
      const w = new THREE.Mesh(wingGeo, wingMat);
      w.scale.x = side;
      group.add(w);
      return w;
    });
    group.visible = false;
    group.scale.setScalar(3);
    scene.add(group);
    return { group, wings, x: 0, y: 0, z: 0, dir: 0 };
  })();
  const isMoving = (state) => state === 'run' || state === 'trot' || state === 'walk';

  function nextDogState() {
    const s = dogSim;
    if (s.state === 'run' && Math.random() < 0.1) {
      s.state = 'lick';
      s.timer = rand(3, 4.5);
      return;
    }
    if (isMoving(s.state) && Math.random() < 0.62) {
      const r = Math.random();
      if (r < 0.38) { s.state = 'sit'; s.timer = rand(2.5, 4.5); }
      else if (r < 0.72) { s.state = 'look'; s.timer = rand(1.6, 3.2); }
      else { s.state = 'sniff'; s.timer = rand(1.8, 3.4); }
      return;
    }
    let tx, tz, tries = 0;
    do {
      tx = rand(DOG_AREA.x0, DOG_AREA.x1);
      tz = rand(DOG_AREA.z0, DOG_AREA.z1);
    } while (Math.hypot(tx - s.x, tz - s.z) < 2.5 && ++tries < 12);
    s.tx = tx;
    s.tz = tz;
    s.state = reduced ? 'walk' : Math.random() < 0.65 ? 'run' : 'trot';
    s.timer = 12;
  }

  function dogStep(dt) {
    const s = dogSim;
    s.time += dt;
    s.timer -= dt;
    if (reduced && (s.state === 'run' || s.state === 'trot')) s.state = 'walk';

    const camAngle = wrapAngle(Math.atan2(VIEW_CAM_POS.x - s.x, VIEW_CAM_POS.z - s.z) - s.yaw);
    if (s.stuntAt >= 0 && s.time >= s.stuntAt) {
      s.stuntAt = -1;
      if (!reduced && !s.stunt) {
        const kind = STUNT_ORDER[s.nextStunt++ % STUNT_ORDER.length];
        s.stunt = { kind, t: 0, dur: STUNTS[kind] };
        s.state = kind === 'grin' ? 'sit' : 'look';
        s.timer = 99;
        if (kind === 'butterfly') {
          const cx = (DOG_AREA.x0 + DOG_AREA.x1) / 2, cz = (DOG_AREA.z0 + DOG_AREA.z1) / 2;
          butterfly.dir = Math.atan2(cx - s.x, cz - s.z) + rand(-0.6, 0.6);
          butterfly.x = s.x + Math.sin(butterfly.dir) * 1.2;
          butterfly.z = s.z + Math.cos(butterfly.dir) * 1.2;
          butterfly.group.visible = true;
        }
      }
    }
    if (s.stunt) {
      const st = s.stunt;
      st.t += dt;
      // The tornado spins up to about three turns a second and back down over 2.4 s.
      if (st.kind === 'tornado' && st.t < 2.4) s.yaw += Math.sin(Math.PI * st.t / 2.4) * TAU * 3 * dt;
      if (st.kind === 'butterfly') {
        // It zigzags away just ahead of the dog, then gives up on the ground and climbs out of reach.
        const b = butterfly;
        b.dir += Math.sin(st.t * 2.3) * 1.4 * dt;
        b.x = clamp(b.x + Math.sin(b.dir) * 1.9 * dt, DOG_AREA.x0, DOG_AREA.x1);
        b.z = clamp(b.z + Math.cos(b.dir) * 1.9 * dt, DOG_AREA.z0, DOG_AREA.z1);
        b.y = 0.75 + Math.sin(st.t * 5) * 0.18 + Math.max(0, st.t - (st.dur - 1.2)) ** 2 * 3;
        s.tx = b.x;
        s.tz = b.z;
        s.state = 'run';
      }
      if (st.kind === 'grin') s.yaw += clamp(camAngle, -2.5 * dt, 2.5 * dt);
      if (st.t >= st.dur) {
        if (st.kind === 'butterfly') butterfly.group.visible = false;
        s.stunt = null;
        s.state = 'walk';
        nextDogState();
      }
    }

    let wantSpeed = 0;
    if (isMoving(s.state)) {
      const dx = s.tx - s.x, dz = s.tz - s.z;
      const dist = Math.hypot(dx, dz);
      const turn = s.state === 'run' ? 2.4 : 1.8;
      s.yaw += clamp(wrapAngle(Math.atan2(dx, dz) - s.yaw), -turn * dt, turn * dt);
      wantSpeed = GAITS[s.state].speed * clamp(dist / 1.5, 0.3, 1);
      s.gait = s.state;
      if (!s.stunt && (dist < 0.4 || s.timer <= 0)) nextDogState();
    } else {
      if (s.state === 'look' && !s.stunt && Math.abs(camAngle) > 1.0) s.yaw += Math.sign(camAngle) * 0.8 * dt;
      if (s.timer <= 0) nextDogState();
    }

    if (s.stunt && s.stunt.kind !== 'butterfly') wantSpeed = 0;
    s.speed = damp(s.speed, wantSpeed, 3, dt);
    s.x = clamp(s.x + Math.sin(s.yaw) * s.speed * dt, DOG_AREA.x0 - 0.5, DOG_AREA.x1 + 0.5);
    s.z = clamp(s.z + Math.cos(s.yaw) * s.speed * dt, DOG_AREA.z0 - 0.5, DOG_AREA.z1 + 0.5);

    const G = GAITS[s.gait];
    const norm = clamp(s.speed / G.speed, 0, 1);
    s.phase += dt * G.freq * TAU * Math.max(0.35, norm);
    s.amp = damp(s.amp, G.amp * norm, 6, dt);

    const target = POSES[s.state];
    for (const key of Object.keys(target)) s.pose[key] = damp(s.pose[key], target[key], 5, dt);
    let yawTarget = 0;
    if (s.state === 'look' || s.state === 'sit') yawTarget = clamp(camAngle, -1.1, 1.1);
    else if (s.state === 'sniff') yawTarget = Math.sin(s.time * 1.3) * 0.3;
    s.pose.headYaw = damp(s.pose.headYaw, yawTarget, 4, dt);
    s.wag += dt * s.pose.wagFreq * TAU;
  }


  function applyDog() {
    const s = dogSim, P = s.pose, G = GAITS[s.gait];
    const a = s.amp, ph = s.phase, n = a / G.amp;
    dog.root.position.set(s.x, 0, s.z);
    dog.root.rotation.y = s.yaw;
    setShadow(MAX_SHADOWS - 1, s.x, s.z, 0.46, 3.2);
    dog.body.position.set(0, P.bodyY + G.bob * n * (0.5 + 0.5 * Math.sin(ph * G.harm)), P.bodyZ);
    dog.body.rotation.x = P.pitch + G.pitch * n * Math.sin(ph * G.harm + 0.8);
    dog.legs.forEach((L, i) => {
      const lp = ph + G.offs[i] * TAU;
      const swing = a * Math.sin(lp);
      const lift = Math.max(0, -Math.cos(lp)) * a;
      L.hip.rotation.x = (L.front ? P.frontHip : P.hindHip) + swing;
      L.hip.rotation.z = 0;
      L.knee.rotation.x = L.front ? P.frontKnee + lift * 1.3 : P.hindKnee + lift * 1.1;
    });
    const sniffing = s.state === 'sniff' ? Math.sin(s.time * 9) * 0.05
      : s.state === 'lick' ? Math.max(0, Math.sin(s.time * 11)) * 0.12 : 0;
    dog.neck.rotation.x = P.neckX + sniffing;
    dog.neck.rotation.y = P.headYaw * 0.45 + P.neckTurn;
    dog.head.rotation.x = P.headX;
    dog.head.rotation.y = P.headYaw * 0.55 + P.headTurn;
    dog.head.rotation.z = 0;
    for (const ear of dog.ears) {
      ear.rotation.x = P.ear + Math.sin(ph * 2) * 0.35 * n;
      ear.rotation.z = ear.userData.side * (0.25 + 0.15 * n * Math.sin(ph * 2 + 1));
    }
    dog.tail.rotation.x = P.tail;
    dog.tail.rotation.y = Math.sin(s.wag) * P.wagAmp;
    // Rolled toward -x, the left hind leg is the one on top.
    dog.body.rotation.z = P.roll;
    if (P.raise > 0.001) {
      const top = dog.legs[2];
      top.hip.rotation.z = 1.35 * P.raise;
      top.hip.rotation.x = lerp(top.hip.rotation.x, -0.5, P.raise);
      top.knee.rotation.x = lerp(top.knee.rotation.x, 0.3, P.raise);
    }
    dog.mouth.scale.setScalar(0.001);
    for (const eye of dog.eyes) eye.scale.y = 1;
    if (s.stunt) applyStunt(s.stunt, P);
    dog.root.updateMatrixWorld(true);
  }

  function applyStunt(st, P) {
    const t = st.t;
    if (st.kind === 'butterfly') {
      const b = butterfly;
      b.group.position.set(b.x, b.y, b.z);
      b.group.rotation.set(0, b.dir, 0);
      const flap = Math.sin(t * 34) * 1.1;
      b.wings[0].rotation.z = flap;
      b.wings[1].rotation.z = -flap;
      // Leaps and snaps at the air every so often.
      const leap = Math.max(0, Math.sin(t * TAU / 1.3)) ** 2;
      dog.body.position.y += leap * 0.3;
      dog.neck.rotation.x -= leap * 0.9;
      dog.head.rotation.x -= leap * 0.4;
      return;
    }
    if (st.kind === 'grin') {
      const k = smoothstep(0.5, 0.9, t) * (1 - smoothstep(st.dur - 0.4, st.dur, t));
      dog.mouth.scale.setScalar(Math.max(0.001, k * 1.5));
      for (const eye of dog.eyes) eye.scale.y = 1 - 0.75 * k;
      dog.head.rotation.z = Math.sin(t * 1.6) * 0.12 * k;
      dog.neck.rotation.y = 0;
      dog.head.rotation.y = 0;
      return;
    }
    if (st.kind === 'tornado') {
      const spin = t < 2.4 ? Math.sin(Math.PI * t / 2.4) : 0;
      dog.neck.rotation.y = 0.9 * spin;
      dog.head.rotation.y = 0.7 * spin;
      dog.body.rotation.z = -0.28 * spin;
      dog.legs.forEach((L, i) => { L.hip.rotation.x += Math.sin(t * 22 + i * Math.PI) * 0.45 * spin; });
      // Dizzy afterwards: swaying and stumbling in place.
      const w = t - 2.4;
      if (w > 0) {
        const fade = Math.max(0, 1 - w / 0.8);
        dog.body.rotation.z = Math.sin(w * 9) * 0.28 * fade;
        dog.head.rotation.z = Math.sin(w * 7 + 1) * 0.35 * fade;
        dog.root.position.x += Math.sin(w * 5) * 0.06 * fade;
      }
      return;
    }
    // Belly up: flop onto its back, tipped to one side, with the legs splayed out sideways and
    // paws curled, paddling lazily. Then roll back and shake it off.
    const k = smoothstep(0, 0.35, t) * (1 - smoothstep(st.dur - 0.7, st.dur - 0.3, t));
    dog.body.rotation.z = Math.PI * 0.78 * easeInOutCubic(k);
    dog.body.position.y = lerp(dog.body.position.y, 0.2, k);
    dog.legs.forEach((L, i) => {
      const pedal = t * 9 + i * Math.PI / 2;
      L.hip.rotation.x = lerp(L.hip.rotation.x, (L.front ? 0.55 : -0.45) + Math.sin(pedal) * 0.3, k);
      L.hip.rotation.z = L.side * 0.75 * k;
      L.knee.rotation.x = lerp(L.knee.rotation.x, (L.front ? 1.5 : 0.9) + Math.cos(pedal) * 0.25, k);
    });
    dog.tail.rotation.y = lerp(dog.tail.rotation.y, Math.sin(t * 16) * 0.6, k);
    dog.head.rotation.z = Math.sin(t * 2.2) * 0.3 * k;
    const shake = smoothstep(st.dur - 0.35, st.dur - 0.25, t) * (1 - smoothstep(st.dur - 0.05, st.dur, t));
    dog.body.rotation.z += Math.sin(t * 60) * 0.14 * shake;
  }

  // -------------------------------------------------------------------------
  // Phone poses
  // -------------------------------------------------------------------------

  const baseQuat = new THREE.Quaternion();
  const baseQuatInv = new THREE.Quaternion();
  const pose = {
    idle: { p: new THREE.Vector3(), r: new THREE.Vector3() },
    pressed: { p: new THREE.Vector3() },
  };
  const springs = Array.from({ length: 6 }, () => ({ x: 0, v: 0 }));
  const pressW = { x: 0, v: 0 };
  const aim = { yaw: 0, pitch: -0.08 };
  let springsReady = false;

  function computeLayout(aspect) {
    const land = smoothstep(0.8, 1.3, aspect);
    camera.aspect = aspect;
    camera.fov = lerp(50, 34, smoothstep(0.75, 1.25, aspect));
    camera.updateProjectionMatrix();
    camera.position.copy(VIEW_CAM_POS);
    camera.lookAt(VIEW_CAM_TARGET);
    camera.updateMatrixWorld();
    baseQuat.copy(camera.quaternion);
    baseQuatInv.copy(baseQuat).invert();

    // Distance that makes the phone fill the wanted share of the viewport height,
    // pushed back further when the viewport is narrow enough for width to bind.
    const tanV = Math.tan(deg(camera.fov / 2));
    const fill = lerp(0.42, 0.52, land);
    const fitH = PHONE.H / (fill * 2 * tanV);
    const fitW = PHONE.W / (0.46 * 2 * tanV * aspect);
    const d = Math.max(fitH, fitW);
    const toLocal = (nx, ny, dist, out) => out.set(nx * dist * tanV * aspect, ny * dist * tanV, -dist);
    toLocal(lerp(0, 0.34, land), lerp(0.3, 0.26, land), d, pose.idle.p);
    pose.idle.r.set(deg(6), deg(lerp(-12, -18, land)), deg(-3));
    // Pressed means against your heart: low on the left, only its top showing.
    toLocal(lerp(-0.35, -0.08, land), -0.72 - fill / 0.8, d * 0.8, pose.pressed.p);

    if (!springsReady) {
      springsReady = true;
      const init = [...pose.idle.p.toArray(), ...pose.idle.r.toArray()];
      springs.forEach((s, i) => { s.x = init[i]; s.v = 0; });
    }
  }

  const tmpE = new THREE.Euler(0, 0, 0, 'YXZ');
  const tmpQ = new THREE.Quaternion();
  const tmpV = new THREE.Vector3();
  const tmpV2 = new THREE.Vector3();
  const localPos = new THREE.Vector3();

  function placePhone(lp, rx, ry, rz) {
    phone.position.copy(lp).applyQuaternion(baseQuat).add(VIEW_CAM_POS);
    tmpE.set(rx, ry, rz, 'YXZ');
    phone.quaternion.copy(baseQuat).multiply(tmpQ.setFromEuler(tmpE));
    phone.updateMatrixWorld(true);
  }

  // Yaw and pitch (camera-local, YXZ) that point the phone's back at the dog from `from`.
  function aimAtDog(from) {
    dog.body.getWorldPosition(tmpV2).sub(VIEW_CAM_POS).applyQuaternion(baseQuatInv).sub(from);
    return { yaw: Math.atan2(-tmpV2.x, -tmpV2.z), pitch: Math.atan2(tmpV2.y, Math.hypot(tmpV2.x, tmpV2.z)) };
  }

  const SHOULDER_LOCAL = new THREE.Vector3(0.24, -0.36, -0.12);
  const hoseTmp = new THREE.Vector3();
  const HOSE_RAMP_AXIS = new THREE.Vector3(-0.95, 0.3, 0).normalize();
  function updateHose() {
    const [p0, p1, p2, p3] = [hoseCurve.v0, hoseCurve.v1, hoseCurve.v2, hoseCurve.v3];
    p0.copy(SHOULDER_LOCAL).applyQuaternion(baseQuat).add(VIEW_CAM_POS);
    p1.set(0.1, 0.12, -0.16).add(SHOULDER_LOCAL).applyQuaternion(baseQuat).add(VIEW_CAM_POS);
    p3.copy(WRIST_LOCAL).applyMatrix4(phone.matrixWorld);
    hoseTmp.copy(FOREARM_LOCAL).applyQuaternion(phone.quaternion);
    p2.copy(p3).addScaledVector(hoseTmp, 0.16);
    rebuildTube();

    // The arm's colour runs along a tilted screen direction, so its bands cross the arm at an
    // angle. The ramp spans the visible stretch of forearm, red below and pink toward the hand.
    const ramp = hoseMat.userData.flat;
    ramp.uFlatAxis.value.copy(HOSE_RAMP_AXIS).applyQuaternion(camera.quaternion);
    ramp.uFlatRange.value.set(
      hoseCurve.getPoint(0.8, hoseTmp).dot(ramp.uFlatAxis.value),
      hoseCurve.getPoint(0.985, hoseTmp).dot(ramp.uFlatAxis.value),
    );
  }

  // Rewrites the tube's rings in place, the same way TubeGeometry lays them out: rings evenly
  // spaced by arc length, oriented by parallel-transported frames, so nothing is allocated.
  const HOSE_SAMPLES = 64;
  const hoseLengths = new Float32Array(HOSE_SAMPLES + 1);
  const hoseP = new THREE.Vector3(), hosePrevP = new THREE.Vector3();
  const hoseT = new THREE.Vector3(), hosePrevT = new THREE.Vector3();
  const hoseN = new THREE.Vector3(), hoseB = new THREE.Vector3(), hoseAxis = new THREE.Vector3();
  const hoseD = [new THREE.Vector3(), new THREE.Vector3(), new THREE.Vector3()];
  function hoseTangent(t, out) {
    const { v0, v1, v2, v3 } = hoseCurve, u = 1 - t;
    hoseD[0].subVectors(v1, v0).multiplyScalar(3 * u * u);
    hoseD[1].subVectors(v2, v1).multiplyScalar(6 * u * t);
    hoseD[2].subVectors(v3, v2).multiplyScalar(3 * t * t);
    return out.copy(hoseD[0]).add(hoseD[1]).add(hoseD[2]).normalize();
  }
  function hoseParamAt(u) {
    const target = u * hoseLengths[HOSE_SAMPLES];
    let i = 0;
    while (i < HOSE_SAMPLES - 1 && hoseLengths[i + 1] < target) i++;
    const span = hoseLengths[i + 1] - hoseLengths[i];
    return (i + (span > 0 ? (target - hoseLengths[i]) / span : 0)) / HOSE_SAMPLES;
  }
  function rebuildTube() {
    hoseCurve.getPoint(0, hosePrevP);
    hoseLengths[0] = 0;
    for (let i = 1; i <= HOSE_SAMPLES; i++) {
      hoseCurve.getPoint(i / HOSE_SAMPLES, hoseP);
      hoseLengths[i] = hoseLengths[i - 1] + hoseP.distanceTo(hosePrevP);
      hosePrevP.copy(hoseP);
    }
    const pos = hoseGeo.attributes.position.array, nor = hoseGeo.attributes.normal.array;
    let k = 0;
    for (let i = 0; i <= HOSE_SEGMENTS; i++) {
      const t = hoseParamAt(i / HOSE_SEGMENTS);
      hoseCurve.getPoint(t, hoseP);
      hoseTangent(t, hoseT);
      if (i === 0) {
        // First normal: perpendicular to the tangent, off its smallest axis.
        const ax = Math.abs(hoseT.x), ay = Math.abs(hoseT.y), az = Math.abs(hoseT.z);
        hoseAxis.set(ax <= ay && ax <= az ? 1 : 0, ay < ax && ay <= az ? 1 : 0, az < ax && az < ay ? 1 : 0);
        hoseAxis.crossVectors(hoseT, hoseAxis).normalize();
        hoseN.crossVectors(hoseT, hoseAxis);
      } else {
        hoseAxis.crossVectors(hosePrevT, hoseT);
        if (hoseAxis.length() > Number.EPSILON) {
          hoseAxis.normalize();
          hoseN.applyAxisAngle(hoseAxis, Math.acos(clamp(hosePrevT.dot(hoseT), -1, 1)));
        }
      }
      hoseB.crossVectors(hoseT, hoseN);
      hosePrevT.copy(hoseT);
      for (let j = 0; j <= HOSE_RADIAL; j++) {
        const v = (j / HOSE_RADIAL) * TAU, sn = Math.sin(v), cs = -Math.cos(v);
        const nx = cs * hoseN.x + sn * hoseB.x, ny = cs * hoseN.y + sn * hoseB.y, nz = cs * hoseN.z + sn * hoseB.z;
        const nl = Math.hypot(nx, ny, nz) || 1;
        nor[k] = nx / nl;
        nor[k + 1] = ny / nl;
        nor[k + 2] = nz / nl;
        pos[k] = hoseP.x + HOSE_R * nor[k];
        pos[k + 1] = hoseP.y + HOSE_R * nor[k + 1];
        pos[k + 2] = hoseP.z + HOSE_R * nor[k + 2];
        k += 3;
      }
    }
    hoseGeo.attributes.position.needsUpdate = true;
    hoseGeo.attributes.normal.needsUpdate = true;
  }

  const prevQ = new THREE.Quaternion();
  let angSpeed = 0;
  const mouse = { x: 0, y: 0, tx: 0, ty: 0 };

  function updatePhone(t, dt) {
    const pressed = !!session;
    springStep(pressW, pressed ? 1 : 0, 7.5, dt);
    const pw = clamp(pressW.x, 0, 1);
    const iw = 1 - pw;

    if (pressed) {
      const want = aimAtDog(pose.pressed.p);
      aim.yaw = damp(aim.yaw, clamp(want.yaw, -0.7, 0.7), 5, dt);
      aim.pitch = damp(aim.pitch, clamp(want.pitch, -0.35, 0.08), 5, dt);
    }
    const tgt = pressed
      ? [...pose.pressed.p.toArray(), aim.pitch, aim.yaw, 0]
      : [...pose.idle.p.toArray(), ...pose.idle.r.toArray()];
    springs.forEach((s, i) => springStep(s, tgt[i], 7.5, dt));

    let fy = 0, frx = 0, fry = 0, frz = 0;
    if (!reduced) {
      fy = Math.sin(t * 0.9) * 0.0035;
      frx = Math.sin(t * 0.7) * 0.02 - mouse.y * 0.05;
      fry = Math.sin(t * 0.53) * 0.025 + mouse.x * 0.08;
      frz = Math.sin(t * 0.61 + 1) * 0.01;
    }

    // Breathing plus walking sway, roughly 1 to 3 degrees, so the aim wanders.
    const k = reduced ? 0.5 : 1;
    const breath = Math.sin(t * TAU * 0.22);
    const step = Math.sin(t * TAU * 0.9);
    const sx = k * 0.003 * Math.sin(t * 1.7);
    const sy = k * (0.004 * breath + 0.0015 * step);
    const srx = k * (0.018 * breath + 0.012 * Math.sin(t * 1.9 + 1) + 0.008 * step * step * step);
    const sry = k * (0.022 * Math.sin(t * 0.83 + 0.4) + 0.012 * Math.sin(t * 2.1) + 0.005 * Math.sin(t * 5.2 + 2));
    const srz = k * (0.02 * Math.sin(t * 1.05 + 2) + 0.008 * Math.sin(t * 3.1));

    localPos.set(springs[0].x + pw * sx, springs[1].x + iw * fy + pw * sy, springs[2].x);
    placePhone(
      localPos,
      springs[3].x + iw * frx + pw * srx,
      springs[4].x + iw * fry + pw * sry,
      springs[5].x + iw * frz + pw * srz,
    );

    const dot = Math.abs(clamp(phone.quaternion.dot(prevQ), -1, 1));
    angSpeed = dt > 0 ? (2 * Math.acos(dot)) / dt : 0;
    prevQ.copy(phone.quaternion);
  }

  // -------------------------------------------------------------------------
  // Capture
  // -------------------------------------------------------------------------

  const captureCam = new THREE.PerspectiveCamera(42, 1, 0.05, 700);
  const canHalf = renderer.extensions.has('EXT_color_buffer_float') || renderer.extensions.has('EXT_color_buffer_half_float');
  const hdrRT = new THREE.WebGLRenderTarget(CAP, CAP, {
    type: canHalf ? THREE.HalfFloatType : THREE.UnsignedByteType, samples: 4,
  });
  const ldrRT = new THREE.WebGLRenderTarget(CAP, CAP, { depthBuffer: false });

  // Render targets skip the renderer's output conversion, so the photo gets its own sRGB pass.
  const postScene = new THREE.Scene();
  const postCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const postQuad = new THREE.Mesh(
    new THREE.PlaneGeometry(2, 2),
    new THREE.ShaderMaterial({
      uniforms: { tSrc: { value: hdrRT.texture } },
      vertexShader: /* glsl */ `
        varying vec2 vUv;
        void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`,
      fragmentShader: /* glsl */ `
        uniform sampler2D tSrc;
        varying vec2 vUv;
        vec3 toSRGB(vec3 c) {
          return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
        }
        void main() {
          // Sampled upside down so the read-back rows come out top first, ready for ImageData.
          vec3 c = clamp(texture2D(tSrc, vec2(vUv.x, 1.0 - vUv.y)).rgb, 0.0, 1.0);
          c = clamp(mix(vec3(dot(c, vec3(0.2126, 0.7152, 0.0722))), c, 1.25), 0.0, 1.0);
          c = mix(c, c * c * (3.0 - 2.0 * c), 0.5);
          vec2 q = vUv - 0.5;
          c *= 1.0 - dot(q, q) * 0.45;
          gl_FragColor = vec4(toSRGB(c), 1.0);
        }`,
      depthTest: false,
      depthWrite: false,
    }),
  );
  postQuad.frustumCulled = false;
  postScene.add(postQuad);

  function captureFrame(fov) {
    captureCam.fov = fov;
    captureCam.updateProjectionMatrix();
    captureCam.position.copy(LENS_LOCAL).applyMatrix4(phone.matrixWorld);
    captureCam.quaternion.copy(phone.quaternion);
    captureCam.updateMatrixWorld(true);

    phone.visible = false;
    hose.visible = false;
    // Shots are taken before this frame's flash is applied to the scene, so the photo keeps the
    // dusk colours; even a faint wash turns the deep indigo foreground grey.
    renderer.setRenderTarget(hdrRT);
    renderer.render(scene, captureCam);
    renderer.setRenderTarget(ldrRT);
    renderer.render(postScene, postCam);
    renderer.setRenderTarget(null);
    phone.visible = true;
    hose.visible = true;

    const cv = document.createElement('canvas');
    cv.width = cv.height = CAP;
    const cx = cv.getContext('2d');
    const img = cx.createImageData(CAP, CAP);
    const capBuf = new Uint8Array(img.data.buffer);
    renderer.readRenderTargetPixels(ldrRT, 0, 0, CAP, CAP, capBuf);
    cx.putImageData(img, 0, 0);

    let r = 0, gg = 0, b = 0, n = 0;
    for (let i = 0; i < capBuf.length; i += 4 * 97) {
      r += capBuf[i];
      gg += capBuf[i + 1];
      b += capBuf[i + 2];
      n++;
    }
    return { canvas: cv, color: [r / n, gg / n, b / n] };
  }

  // Stand-in for the app's aesthetics score: any frame with the dog in it is a keeper, a little
  // better when centred; frames that miss the dog are the ones left out.
  function scoreShot(cam, shake) {
    dog.body.getWorldPosition(tmpV);
    tmpV2.copy(tmpV).applyMatrix4(cam.matrixWorldInverse);
    if (tmpV2.z >= 0) return 0.1;
    tmpV.project(cam);
    if (Math.abs(tmpV.x) > 0.95 || Math.abs(tmpV.y) > 0.95) return 0.1;
    const centred = Math.max(0, 1 - Math.hypot(tmpV.x, tmpV.y));
    return 0.6 + 0.35 * centred - Math.min(0.1, shake * 0.3);
  }

  function vivid([r, gg, b]) {
    const m = (r + gg + b) / 3;
    return [r, gg, b].map((c) => Math.round(clamp(lerp(m + (c - m) * 1.8, 255, 0.28), 0, 255)));
  }

  // -------------------------------------------------------------------------
  // Session and celebration
  // -------------------------------------------------------------------------

  const hintEl = document.getElementById('heroHint');
  const hintIdle = hintEl ? hintEl.innerHTML : '';
  let hintTimer = 0;
  function setHint(text, restoreMs) {
    if (!hintEl) return;
    clearTimeout(hintTimer);
    if (text === hintIdle) hintEl.innerHTML = text;
    else hintEl.textContent = text;
    if (restoreMs) hintTimer = setTimeout(() => { hintEl.innerHTML = hintIdle; }, restoreMs);
  }

  let session = null;
  let time = 0;

  function beginSession() {
    if (session || ui.mode === 'celebrate') return;
    const want = aimAtDog(pose.pressed.p);
    aim.yaw = clamp(want.yaw + rand(-0.02, 0.02), -0.7, 0.7);
    aim.pitch = clamp(want.pitch + rand(-0.02, 0.02), -0.35, 0.08);
    session = { frames: [], best: null, nextShot: time + INTERVALS[ui.interval] };
    if (!dogSim.stunt) dogSim.stuntAt = dogSim.time + 0.6;
    setMode('capture');
    addBeat(time, 0.4, 0.05, 0.6);
    haptic();
    setHint('Capturing.');
  }

  function endSession() {
    if (!session) return;
    const s = session;
    session = null;
    const kept = s.frames.length ? s.frames : s.best ? [s.best] : [];
    if (!kept.length) {
      goHome(false);
      setHint(hintIdle);
      return;
    }
    startCelebration(kept);
  }

  function takeShot() {
    const s = session;
    if (ui.flash && INTERVALS[ui.interval] >= 1) {
      flashAt = time;
      if (flashOverlay && !reduced) {
        flashOverlay.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 260, easing: 'cubic-bezier(0.2, 0, 0.4, 1)' });
      }
    }
    const shot = captureFrame(LENS_FOV[ui.lens]);
    const frame = { ...shot, score: scoreShot(captureCam, angSpeed), t: time };
    addBeat(time, 0.4, 0.05, 0.6);
    haptic();
    if (frame.score >= KEEP_THRESHOLD) {
      s.frames.push(frame);
      if (s.frames.length >= MAX_ELIGIBLE) endSession();
    } else {
      s.best ??= frame;
    }
  }

  function updateSession() {
    if (!session || time < session.nextShot) return;
    session.nextShot = time + INTERVALS[ui.interval];
    takeShot();
  }

  function updateFlash() {
    const k = Math.exp(-(time - flashAt) / 0.08);
    flashUniform.value = k > 0.01 ? 0.45 * k : 0;
  }

  function startCelebration(kept) {
    const chosen = kept.slice().sort((a, b) => b.score - a.score).slice(0, 7).sort((a, b) => a.t - b.t);
    const n = chosen.length;
    // Fan: photos sit on an arc of radius 240 around a pivot below the screen centre, placed so the
    // arc's middle lands at 45% of the screen height. Few photos get a proportionally narrower spread.
    const spread = n > 1 ? deg(25) * Math.min(1, (n - 1) / 6) : 0;
    const radius = 240;
    const pivotX = SW / 2, pivotY = SH * 0.45 + radius;
    const photos = chosen.map((frame, i) => {
      const a = n > 1 ? lerp(-spread, spread, i / (n - 1)) : 0;
      return { frame, a, x: pivotX + radius * Math.sin(a), y: pivotY - radius * Math.cos(a) };
    });
    const collapseAt = 0.5 + 0.03 * (n - 1) + 0.7;
    const burstAt = collapseAt + 0.03 * (n - 1) + 0.55;
    const colors = chosen.map((f) => vivid(f.color));
    const glow = [0, 1, 2].map((ch) => Math.round(colors.reduce((sum, c) => sum + c[ch], 0) / n));
    ui.celebration = {
      t0: time + 0.5, photos, collapseAt, burstAt, colors, glow, sparks: null, kept: kept.length,
      reduced, end: reduced ? 2.0 : burstAt + 1.15,
    };
    setMode('celebrate');
  }

  function updateCelebration(t) {
    const c = ui.celebration;
    if (!c) return;
    const e = t - c.t0;
    if (!c.reduced && !c.sparks && e >= c.burstAt) {
      c.sparks = Array.from({ length: 28 }, (_, i) => {
        const [r, gg, b] = c.colors[i % c.colors.length];
        return { a: rand(0, TAU), d: rand(40, 110), r: rand(1.6, 3.2), col: `rgb(${r},${gg},${b})`, life: rand(0.85, 1.15) };
      });
      addBeat(t, 0.8, 0.04, 0.9);
    }
    if (e >= c.end) {
      ui.celebration = null;
      goHome(true);
      const k = c.kept;
      setHint(k === 1 ? '1 photo kept.' : k ? `${k} photos kept.` : 'Nothing kept.', 5000);
    }
  }

  function goHome(landing) {
    setMode('home');
    ui.homeAt = time;
    pendingDouble = [];
    if (landing) {
      addBeat(time, Math.min(1, HOME_BRIGHT + 0.3), 0.05, 1.0);
      haptic();
      nextHomeBeat = time + HEART_PERIOD;
    } else {
      nextHomeBeat = time + 0.4;
    }
  }

  // -------------------------------------------------------------------------
  // Interaction
  // -------------------------------------------------------------------------

  const raycaster = new THREE.Raycaster();
  const ndc = new THREE.Vector2();
  function pick(clientX, clientY) {
    const rect = canvas.getBoundingClientRect();
    ndc.set(((clientX - rect.left) / rect.width) * 2 - 1, -((clientY - rect.top) / rect.height) * 2 + 1);
    raycaster.setFromCamera(ndc, camera);
    return raycaster.intersectObjects(phoneHit, false)[0] || null;
  }

  let activePointer = null;
  let keyHeld = false;
  let hoverXY = null;

  canvas.addEventListener('pointerdown', (e) => {
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    const hit = pick(e.clientX, e.clientY);
    if (!hit) return;
    if (hit.object === screenMesh && hit.uv && uiTap(hit.uv.x * SW, (1 - hit.uv.y) * SH)) return;
    if (session) return;
    activePointer = e.pointerId;
    if (e.pointerType === 'mouse') e.preventDefault();
    pressedOnce = true;
    lastInteract = time;
    beginSession();
  });
  const release = (e) => {
    if (activePointer === null || e.pointerId !== activePointer) return;
    activePointer = null;
    endSession();
  };
  canvas.addEventListener('pointerup', release);
  canvas.addEventListener('pointercancel', release);
  canvas.addEventListener('pointerleave', release);
  window.addEventListener('pointerup', release);
  canvas.addEventListener('contextmenu', (e) => {
    if (activePointer !== null || pick(e.clientX, e.clientY)) e.preventDefault();
  });
  canvas.addEventListener('pointermove', (e) => {
    if (e.pointerType === 'mouse') hoverXY = [e.clientX, e.clientY];
  });
  canvas.addEventListener('pointerleave', () => { hovering = false; });

  // Action prompt beside the phone: on hover with a mouse, or after a quiet moment on touch.
  const promptEl = document.getElementById('heroPrompt');
  const coarsePointer = matchMedia('(pointer: coarse)').matches;
  const PROMPT_LOCAL = new THREE.Vector3(-W / 2 - 0.012, 0.02, 0);
  const promptPos = new THREE.Vector3();
  let hovering = false;
  let pressedOnce = false;
  let lastInteract = 0;
  let promptOn = false;
  function updatePrompt() {
    if (!promptEl) return;
    const idle = ui.mode === 'home' && !session && pressW.x < 0.05;
    const quiet = time - lastInteract > (pressedOnce ? 20 : 1.5);
    const show = idle && (hovering || (coarsePointer && quiet));
    if (show !== promptOn) {
      promptOn = show;
      promptEl.classList.toggle('is-on', show);
    }
    if (!show) return;
    promptPos.copy(PROMPT_LOCAL).applyMatrix4(phone.matrixWorld).project(camera);
    const x = ((promptPos.x + 1) / 2) * canvas.clientWidth;
    const y = ((1 - promptPos.y) / 2) * canvas.clientHeight;
    promptEl.style.transform = `translate(${x.toFixed(1)}px, ${y.toFixed(1)}px) translate(-100%, -50%)`;
  }
  window.addEventListener('pointermove', (e) => {
    if (e.pointerType !== 'mouse') return;
    const r = stage.getBoundingClientRect();
    mouse.tx = clamp(((e.clientX - r.left) / r.width) * 2 - 1, -1, 1);
    mouse.ty = clamp(-(((e.clientY - r.top) / r.height) * 2 - 1), -1, 1);
  }, { passive: true });

  const isHoldKey = (e) => e.code === 'Space' || e.key === ' ' || e.key === 'Enter';
  stage.addEventListener('keydown', (e) => {
    if (!isHoldKey(e)) return;
    e.preventDefault();
    if (e.repeat || keyHeld) return;
    keyHeld = true;
    beginSession();
  });
  stage.addEventListener('keyup', (e) => {
    if (!isHoldKey(e)) return;
    e.preventDefault();
    if (!keyHeld) return;
    keyHeld = false;
    endSession();
  });
  stage.addEventListener('blur', () => {
    if (!keyHeld) return;
    keyHeld = false;
    endSession();
  });

  // -------------------------------------------------------------------------
  // Loop
  // -------------------------------------------------------------------------

  function update(dt) {
    time += dt;
    const t = time;
    if (!reduced) {
      grassTime.value += dt;
      beamTime.value += dt;
    }

    dogStep(dt);
    applyDog();

    mouse.x = damp(mouse.x, reduced ? 0 : mouse.tx, 3, dt);
    mouse.y = damp(mouse.y, reduced ? 0 : mouse.ty, 3, dt);
    camera.position.set(VIEW_CAM_POS.x + mouse.x * 0.012, VIEW_CAM_POS.y + mouse.y * 0.006, VIEW_CAM_POS.z);
    camera.lookAt(VIEW_CAM_TARGET);
    camera.updateMatrixWorld();

    updatePhone(t, dt);
    updateHose();
    updateSession();
    updateFlash();
    updateUI(t, dt);
    updatePrompt();

    if (hoverXY) {
      hovering = !!pick(hoverXY[0], hoverXY[1]);
      canvas.style.cursor = hovering ? 'pointer' : '';
      hoverXY = null;
    }
  }

  let running = false;
  let rafId = 0;
  let lastNow = 0;
  function frame(now) {
    rafId = requestAnimationFrame(frame);
    const dt = Math.min(0.05, Math.max(0, (now - lastNow) / 1000));
    lastNow = now;
    update(dt);
    renderer.render(scene, camera);
  }

  let heroVisible = true;
  function refreshRunning() {
    const on = heroVisible && !document.hidden;
    if (on === running) return;
    running = on;
    if (on) {
      lastNow = performance.now();
      rafId = requestAnimationFrame(frame);
    } else {
      cancelAnimationFrame(rafId);
      activePointer = null;
      keyHeld = false;
      endSession();
    }
  }

  function resize() {
    const w = Math.max(1, stage.clientWidth), h = Math.max(1, stage.clientHeight);
    renderer.setSize(w, h, false);
    computeLayout(w / h);
  }

  resize();
  new ResizeObserver(resize).observe(stage);
  update(0);
  renderer.render(scene, camera);

  if ('IntersectionObserver' in window) {
    new IntersectionObserver((entries) => {
      heroVisible = entries[entries.length - 1].isIntersecting;
      refreshRunning();
    }).observe(heroEl || stage);
  }
  document.addEventListener('visibilitychange', refreshRunning);
  refreshRunning();
}
