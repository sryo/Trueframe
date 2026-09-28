import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
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
const LENS_FOV = { '0.5': 58, '1x': 30, '2x': 16 };
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

function hash2(x, y) {
  const s = Math.sin(x * 127.1 + y * 311.7) * 43758.5453;
  return s - Math.floor(s);
}

function valueNoise(x, y) {
  const xi = Math.floor(x), yi = Math.floor(y);
  const xf = x - xi, yf = y - yi;
  const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
  return lerp(
    lerp(hash2(xi, yi), hash2(xi + 1, yi), u),
    lerp(hash2(xi, yi + 1), hash2(xi + 1, yi + 1), u),
    v,
  );
}

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
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;

  const canvas = renderer.domElement;
  canvas.dataset.hero = '';
  Object.assign(canvas.style, {
    position: 'absolute', inset: '0', width: '100%', height: '100%', display: 'block',
    userSelect: 'none', webkitUserSelect: 'none', webkitTouchCallout: 'none',
  });
  canvas.style.touchAction = 'pan-y';
  stage.appendChild(canvas);

  const scene = new THREE.Scene();
  const horizonColor = new THREE.Color('#f0b089');
  scene.fog = new THREE.Fog(horizonColor.clone(), 16, 150);

  const camera = new THREE.PerspectiveCamera(34, 1, 0.02, 700);
  camera.position.copy(VIEW_CAM_POS);
  camera.lookAt(VIEW_CAM_TARGET);

  const sunDir = new THREE.Vector3(-0.3, 0.078, -1).normalize();

  const sky = new THREE.Mesh(
    new THREE.SphereGeometry(500, 48, 24),
    new THREE.ShaderMaterial({
      uniforms: {
        zenith: { value: new THREE.Color('#1d2544') },
        mid: { value: new THREE.Color('#6b5a78') },
        horizon: { value: horizonColor.clone() },
        below: { value: new THREE.Color('#d99a78') },
        sunDir: { value: sunDir },
      },
      vertexShader: /* glsl */ `
        varying vec3 vDir;
        void main() {
          vDir = position;
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }`,
      fragmentShader: /* glsl */ `
        uniform vec3 zenith;
        uniform vec3 mid;
        uniform vec3 horizon;
        uniform vec3 below;
        uniform vec3 sunDir;
        varying vec3 vDir;
        void main() {
          vec3 d = normalize(vDir);
          vec3 col;
          if (d.y >= 0.0) {
            float t = sqrt(d.y);
            col = mix(horizon, mid, smoothstep(0.02, 0.45, t));
            col = mix(col, zenith, smoothstep(0.4, 0.95, t));
          } else {
            col = mix(horizon, below, smoothstep(0.0, 0.06, -d.y));
          }
          float s = max(dot(d, sunDir), 0.0);
          col += vec3(1.0, 0.55, 0.3) * (pow(s, 6.0) * 0.3 + pow(s, 48.0) * 0.45);
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

  scene.add(new THREE.HemisphereLight('#b8a6c9', '#3b3222', 1.1));

  const dogCenter = new THREE.Vector3(-2.2, 0, -12);
  const sun = new THREE.DirectionalLight('#ffc79a', 2.5);
  sun.position.copy(dogCenter).addScaledVector(new THREE.Vector3(-0.35, 0.28, -1).normalize(), 30);
  sun.target.position.copy(dogCenter);
  sun.castShadow = true;
  sun.shadow.mapSize.set(1024, 1024);
  Object.assign(sun.shadow.camera, { left: -7, right: 7, top: 7, bottom: -7, near: 10, far: 50 });
  sun.shadow.camera.updateProjectionMatrix();
  sun.shadow.bias = -0.0004;
  sun.shadow.normalBias = 0.02;
  scene.add(sun, sun.target);

  // Ground: large-scale tone variation in vertex colours, fine speckle in a tiling texture.
  const groundGeo = new THREE.PlaneGeometry(600, 600, 160, 160);
  groundGeo.rotateX(-Math.PI / 2);
  {
    const pos = groundGeo.attributes.position;
    const colors = new Float32Array(pos.count * 3);
    const base = new THREE.Color('#4f5a38');
    const warm = new THREE.Color('#6e6a3a');
    const dark = new THREE.Color('#3c4629');
    const c = new THREE.Color();
    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i), z = pos.getZ(i);
      const n1 = valueNoise(x * 0.08, z * 0.08);
      const n2 = valueNoise(x * 0.35 + 17, z * 0.35 - 9);
      c.copy(base).lerp(warm, smoothstep(0.45, 0.8, n1) * 0.8).lerp(dark, smoothstep(0.55, 0.9, n2) * 0.5);
      colors[i * 3] = c.r;
      colors[i * 3 + 1] = c.g;
      colors[i * 3 + 2] = c.b;
    }
    groundGeo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  }
  const groundTex = canvasTexture(256, (c, s) => {
    c.fillStyle = '#e6e6e6';
    c.fillRect(0, 0, s, s);
    for (let i = 0; i < 1600; i++) {
      const v = Math.floor(rand(170, 255));
      c.fillStyle = `rgba(${v},${v},${v},0.3)`;
      c.beginPath();
      c.ellipse(rand(0, s), rand(0, s), rand(1, 5), rand(1, 3), rand(0, TAU), 0, TAU);
      c.fill();
    }
  });
  groundTex.wrapS = groundTex.wrapT = THREE.RepeatWrapping;
  groundTex.repeat.set(80, 80);
  groundTex.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  const ground = new THREE.Mesh(
    groundGeo,
    new THREE.MeshStandardMaterial({ vertexColors: true, map: groundTex, roughness: 1 }),
  );
  ground.receiveShadow = true;
  scene.add(ground);

  // Grass: tapered blades in tufts, swaying in the vertex shader.
  const grassTime = { value: 0 };
  {
    const segs = 4;
    const pos = [], col = [], nor = [], idx = [];
    for (let i = 0; i <= segs; i++) {
      const y = i / segs;
      const w = 0.06 * Math.pow(1 - y, 0.8);
      const z = y * y * 0.18;
      const shade = lerp(0.38, 1, Math.pow(y, 0.7));
      if (i < segs) {
        pos.push(-w, y, z, w, y, z);
        col.push(shade, shade, shade, shade, shade, shade);
        nor.push(0, 1, 0, 0, 1, 0);
      } else {
        pos.push(0, y, z);
        col.push(shade, shade, shade);
        nor.push(0, 1, 0);
      }
    }
    for (let i = 0; i < segs - 1; i++) {
      const a = i * 2;
      idx.push(a, a + 1, a + 2, a + 1, a + 3, a + 2);
    }
    const last = (segs - 1) * 2;
    idx.push(last, last + 1, last + 2);
    const bladeGeo = new THREE.BufferGeometry();
    bladeGeo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    bladeGeo.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
    bladeGeo.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
    bladeGeo.setIndex(idx);

    const grassMat = new THREE.MeshStandardMaterial({ vertexColors: true, side: THREE.DoubleSide, roughness: 0.9 });
    grassMat.onBeforeCompile = (shader) => {
      shader.uniforms.uTime = grassTime;
      shader.vertexShader = 'uniform float uTime;\n' + shader.vertexShader.replace(
        '#include <begin_vertex>',
        `#include <begin_vertex>
        #ifdef USE_INSTANCING
          vec2 ip = vec2(instanceMatrix[3].x, instanceMatrix[3].z);
        #else
          vec2 ip = vec2(0.0);
        #endif
        float sway = sin(uTime * 1.6 + ip.x * 0.7 + ip.y * 0.45) * 0.6 + sin(uTime * 2.9 + ip.x * 1.3) * 0.25;
        transformed.x += sway * 0.12 * position.y * position.y;`,
      );
    };

    const count = 6000;
    const grass = new THREE.InstancedMesh(bladeGeo, grassMat, count);
    const palette = ['#5a6534', '#6d7039', '#7f7a3e', '#4b5630', '#8c8446'].map((h) => new THREE.Color(h));
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler();
    const p = new THREE.Vector3(), sc = new THREE.Vector3();
    let k = 0;
    while (k < count) {
      const tx = rand(-16, 12), tz = rand(-26, -2.4);
      const inPlay = tx > -5.5 && tx < 4.5 && tz > -10.5 && tz < -4.5;
      const tuftH = inPlay ? rand(0.1, 0.2) : rand(0.14, 0.42);
      const blades = 5 + Math.floor(Math.random() * 4);
      for (let b = 0; b < blades && k < count; b++, k++) {
        p.set(tx + rand(-0.07, 0.07), 0, tz + rand(-0.07, 0.07));
        e.set(rand(-0.25, 0.25), rand(0, TAU), rand(-0.25, 0.25));
        q.setFromEuler(e);
        const h = tuftH * rand(0.6, 1.15);
        sc.set(h, h, h);
        grass.setMatrixAt(k, m.compose(p, q, sc));
        grass.setColorAt(k, palette[Math.floor(Math.random() * palette.length)]);
      }
    }
    scene.add(grass);
  }

  // Trees and hills in the middle and far distance.
  {
    const trunkMat = new THREE.MeshStandardMaterial({ color: '#4a3526', roughness: 0.9, flatShading: true });
    const leafMats = ['#3e4a2a', '#4a5530', '#36422a'].map(
      (c) => new THREE.MeshStandardMaterial({ color: c, roughness: 0.9, flatShading: true }),
    );
    const trunkGeo = new THREE.CylinderGeometry(0.1, 0.16, 2.2, 6);
    const leafGeo = new THREE.IcosahedronGeometry(1.3, 0);
    const trees = [[-10, -17, 1.1], [-13.5, -21, 1.4], [7.5, -18, 1], [11, -26, 1.5], [-4, -30, 1.2], [18, -40, 1.8], [-22, -38, 1.7]];
    for (const [x, z, s] of trees) {
      const tree = new THREE.Group();
      const trunk = new THREE.Mesh(trunkGeo, trunkMat);
      trunk.position.y = 1.1;
      tree.add(trunk);
      for (let i = 0; i < 3; i++) {
        const leaf = new THREE.Mesh(leafGeo, leafMats[i]);
        leaf.position.set(rand(-0.5, 0.5), 2.6 + i * 0.55, rand(-0.5, 0.5));
        leaf.scale.setScalar(rand(0.8, 1.15) * (1 - i * 0.18));
        leaf.rotation.set(rand(0, TAU), rand(0, TAU), 0);
        tree.add(leaf);
      }
      tree.position.set(x, 0, z);
      tree.scale.setScalar(s);
      scene.add(tree);
    }

    const hillGeo = new THREE.SphereGeometry(1, 24, 12);
    const hills = [
      [-140, -110, 70, 7, 25], [-60, -95, 55, 5, 22], [10, -120, 80, 6, 26], [90, -100, 60, 6, 24],
      [170, -120, 70, 8, 30], [-25, -70, 30, 3.5, 14], [45, -65, 28, 3, 12],
    ];
    const near = new THREE.Color('#55543f'), far = new THREE.Color('#6f6552');
    for (const [x, z, sx, sy, sz] of hills) {
      const hill = new THREE.Mesh(
        hillGeo,
        new THREE.MeshStandardMaterial({ color: near.clone().lerp(far, smoothstep(60, 120, -z)), roughness: 1 }),
      );
      hill.position.set(x, 0, z);
      hill.scale.set(sx, sy, sz);
      scene.add(hill);
    }

    const sunTex = canvasTexture(256, (c, s) => {
      const gr = c.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
      gr.addColorStop(0, 'rgba(255,248,230,1)');
      gr.addColorStop(0.07, 'rgba(255,232,195,1)');
      gr.addColorStop(0.16, 'rgba(255,190,120,0.5)');
      gr.addColorStop(0.45, 'rgba(255,150,90,0.12)');
      gr.addColorStop(1, 'rgba(255,140,80,0)');
      c.fillStyle = gr;
      c.fillRect(0, 0, s, s);
    });
    const sunSprite = new THREE.Sprite(new THREE.SpriteMaterial({
      map: sunTex, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, fog: false,
    }));
    sunSprite.position.copy(sunDir).multiplyScalar(420);
    sunSprite.scale.setScalar(110);
    scene.add(sunSprite);
  }

  // -------------------------------------------------------------------------
  // Phone model
  // -------------------------------------------------------------------------

  const pmrem = new THREE.PMREMGenerator(renderer);
  const envTex = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  pmrem.dispose();

  const uiCanvas = document.createElement('canvas');
  uiCanvas.width = SW * PT;
  uiCanvas.height = SH * PT;
  const g = uiCanvas.getContext('2d');
  const uiTex = new THREE.CanvasTexture(uiCanvas);
  uiTex.colorSpace = THREE.SRGBColorSpace;
  uiTex.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());

  const frameMat = new THREE.MeshPhysicalMaterial({
    color: '#95635B', metalness: 1, roughness: 0.3, envMap: envTex, envMapIntensity: 1.1,
  });
  const frontGlassMat = new THREE.MeshPhysicalMaterial({
    color: '#030304', roughness: 0.05, clearcoat: 1, clearcoatRoughness: 0.03, envMap: envTex, envMapIntensity: 0.9,
  });
  const screenMat = new THREE.MeshStandardMaterial({
    color: '#000000', emissive: '#ffffff', emissiveMap: uiTex, emissiveIntensity: 1,
    roughness: 0.1, metalness: 0, envMap: envTex, envMapIntensity: 0.6, toneMapped: false,
  });
  const backMat = new THREE.MeshPhysicalMaterial({
    color: '#ad7a70', roughness: 0.5, clearcoat: 0.35, clearcoatRoughness: 0.45, envMap: envTex, envMapIntensity: 0.9,
  });
  const lensGlassMat = new THREE.MeshPhysicalMaterial({
    color: '#0a0b16', metalness: 0.4, roughness: 0.06, clearcoat: 1, clearcoatRoughness: 0.02,
    iridescence: 0.9, iridescenceIOR: 1.5, iridescenceThicknessRange: [260, 420],
    envMap: envTex, envMapIntensity: 1.4,
  });
  const darkMat = new THREE.MeshPhysicalMaterial({
    color: '#0c0b0d', roughness: 0.2, clearcoat: 1, envMap: envTex, envMapIntensity: 0.8,
  });
  const flashMat = new THREE.MeshStandardMaterial({
    color: '#efe6d2', roughness: 0.35, emissive: '#fff2d9', emissiveIntensity: 0.05, envMap: envTex,
  });

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
  const plateau = new THREE.Mesh(plateauGeo, frameMat);
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
  const skinMat = new THREE.MeshStandardMaterial({
    color: '#c68a67', roughness: 0.75, flatShading: true, envMap: envTex, envMapIntensity: 0.5,
  });
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
  const hose = new THREE.Mesh(new THREE.TubeGeometry(hoseCurve, HOSE_SEGMENTS, HOSE_R, HOSE_RADIAL), skinMat);
  hose.frustumCulled = false;
  scene.add(hose);

  const phoneHit = [body, frontGlass, screenMesh, backGlass, plateau, ...hand.children];
  const LENS_LOCAL = new THREE.Vector3(LENS_MAIN[0], LENS_MAIN[1], PLATE_FACE_Z - 0.003);
  const FLASH_LOCAL = new THREE.Vector3(-0.0215, 0.0625, PLATE_FACE_Z - 0.01);

  const flashLight = new THREE.SpotLight('#fff4e6', 0, 40, deg(38), 0.5, 1);
  scene.add(flashLight, flashLight.target);
  const flashOverlay = document.getElementById('heroFlash');
  const BACK_LOCAL = new THREE.Vector3(0, 0, -1);
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
    const coat = new THREE.MeshStandardMaterial({ color: '#c98d4f', roughness: 0.85 });
    const cream = new THREE.MeshStandardMaterial({ color: '#e3b884', roughness: 0.85 });
    const ears = new THREE.MeshStandardMaterial({ color: '#a86f3c', roughness: 0.85 });
    const black = new THREE.MeshStandardMaterial({ color: '#141110', roughness: 0.4 });
    const sphere = (r) => new THREE.SphereGeometry(r, 16, 12);
    const capsule = (r, l) => new THREE.CapsuleGeometry(r, l, 4, 12);
    const add = (parent, geo, mat, [x, y, z], [rx, ry, rz] = [0, 0, 0], [sx, sy, sz] = [1, 1, 1]) => {
      const m = new THREE.Mesh(geo, mat);
      m.position.set(x, y, z);
      m.rotation.set(rx, ry, rz);
      m.scale.set(sx, sy, sz);
      m.castShadow = true;
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
    add(head, sphere(0.014), black, [0.045, 0.03, 0.085]);
    add(head, sphere(0.014), black, [-0.045, 0.03, 0.085]);
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
      return { hip, knee, front };
    });

    scene.add(root);
    return { root, body: bodyPivot, neck, head, ears: earPivots, tail, legs };
  })();

  const GAITS = {
    run: { speed: 4.2, freq: 3.0, amp: 0.8, offs: [0, 0.1, 0.55, 0.65], bob: 0.05, pitch: 0.09, harm: 1 },
    trot: { speed: 1.8, freq: 2.4, amp: 0.5, offs: [0, 0.5, 0.5, 0], bob: 0.018, pitch: 0.02, harm: 2 },
    walk: { speed: 0.75, freq: 1.3, amp: 0.34, offs: [0, 0.5, 0.75, 0.25], bob: 0.01, pitch: 0.015, harm: 2 },
  };
  const STAND = {
    bodyY: 0.495, bodyZ: 0, pitch: 0, frontHip: 0, frontKnee: 0, hindHip: -0.2, hindKnee: 0.35,
    neckX: 0, headX: 0, headYaw: 0, tail: -0.8, wagAmp: 0.3, wagFreq: 2.2, ear: 0,
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
    sniff: {
      ...STAND, bodyY: 0.47, pitch: 0.18, frontHip: -0.18, frontKnee: 0.25, neckX: 1.35, headX: 0.5,
      tail: -0.7, wagAmp: 0.25, wagFreq: 1.8, ear: -0.3,
    },
  };

  const dogSim = {
    x: -1.2, z: -7.2, yaw: 0.6, speed: 0, state: 'look', timer: 2.5, tx: 0, tz: 0,
    gait: 'trot', phase: 0, wag: 0, amp: 0, time: 0, pose: { ...STAND },
  };
  const isMoving = (state) => state === 'run' || state === 'trot' || state === 'walk';

  function nextDogState() {
    const s = dogSim;
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
    let wantSpeed = 0;
    if (isMoving(s.state)) {
      const dx = s.tx - s.x, dz = s.tz - s.z;
      const dist = Math.hypot(dx, dz);
      const turn = s.state === 'run' ? 2.4 : 1.8;
      s.yaw += clamp(wrapAngle(Math.atan2(dx, dz) - s.yaw), -turn * dt, turn * dt);
      wantSpeed = GAITS[s.state].speed * clamp(dist / 1.5, 0.3, 1);
      s.gait = s.state;
      if (dist < 0.4 || s.timer <= 0) nextDogState();
    } else {
      if (s.state === 'look' && Math.abs(camAngle) > 1.0) s.yaw += Math.sign(camAngle) * 0.8 * dt;
      if (s.timer <= 0) nextDogState();
    }

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
    dog.body.position.set(0, P.bodyY + G.bob * n * (0.5 + 0.5 * Math.sin(ph * G.harm)), P.bodyZ);
    dog.body.rotation.x = P.pitch + G.pitch * n * Math.sin(ph * G.harm + 0.8);
    dog.legs.forEach((L, i) => {
      const lp = ph + G.offs[i] * TAU;
      const swing = a * Math.sin(lp);
      const lift = Math.max(0, -Math.cos(lp)) * a;
      L.hip.rotation.x = (L.front ? P.frontHip : P.hindHip) + swing;
      L.knee.rotation.x = L.front ? P.frontKnee + lift * 1.3 : P.hindKnee + lift * 1.1;
    });
    const sniffing = s.state === 'sniff' ? Math.sin(s.time * 9) * 0.05 : 0;
    dog.neck.rotation.x = P.neckX + sniffing;
    dog.neck.rotation.y = P.headYaw * 0.45;
    dog.head.rotation.x = P.headX;
    dog.head.rotation.y = P.headYaw * 0.55;
    for (const ear of dog.ears) {
      ear.rotation.x = P.ear + Math.sin(ph * 2) * 0.35 * n;
      ear.rotation.z = ear.userData.side * (0.25 + 0.15 * n * Math.sin(ph * 2 + 1));
    }
    dog.tail.rotation.x = P.tail;
    dog.tail.rotation.y = Math.sin(s.wag) * P.wagAmp;
    dog.root.updateMatrixWorld(true);
  }

  // -------------------------------------------------------------------------
  // Phone poses
  // -------------------------------------------------------------------------

  const baseQuat = new THREE.Quaternion();
  const baseQuatInv = new THREE.Quaternion();
  const pose = {
    idle: { p: new THREE.Vector3(), r: new THREE.Vector3() },
    pressed: { p: new THREE.Vector3(), r: new THREE.Vector3() },
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
  function updateHose() {
    const [p0, p1, p2, p3] = [hoseCurve.v0, hoseCurve.v1, hoseCurve.v2, hoseCurve.v3];
    p0.copy(SHOULDER_LOCAL).applyQuaternion(baseQuat).add(VIEW_CAM_POS);
    p1.set(0.1, 0.12, -0.16).add(SHOULDER_LOCAL).applyQuaternion(baseQuat).add(VIEW_CAM_POS);
    p3.copy(WRIST_LOCAL).applyMatrix4(phone.matrixWorld);
    hoseTmp.copy(FOREARM_LOCAL).applyQuaternion(phone.quaternion);
    p2.copy(p3).addScaledVector(hoseTmp, 0.16);
    // Curves cache their arc-length table; it has to be rebuilt after moving the points.
    hoseCurve.needsUpdate = true;
    const next = new THREE.TubeGeometry(hoseCurve, HOSE_SEGMENTS, HOSE_R, HOSE_RADIAL);
    hose.geometry.attributes.position.array.set(next.attributes.position.array);
    hose.geometry.attributes.normal.array.set(next.attributes.normal.array);
    hose.geometry.attributes.position.needsUpdate = true;
    hose.geometry.attributes.normal.needsUpdate = true;
    next.dispose();
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
      aim.yaw = damp(aim.yaw, clamp(want.yaw, -0.3, 0.3), 2.2, dt);
      aim.pitch = damp(aim.pitch, clamp(want.pitch, -0.35, 0.08), 2.2, dt);
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
  const capBuf = new Uint8Array(CAP * CAP * 4);

  // Render targets skip the renderer's tone mapping, so the photo gets its own ACES and sRGB pass.
  const postScene = new THREE.Scene();
  const postCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const postQuad = new THREE.Mesh(
    new THREE.PlaneGeometry(2, 2),
    new THREE.ShaderMaterial({
      uniforms: { tSrc: { value: hdrRT.texture }, exposure: { value: 1.05 } },
      vertexShader: /* glsl */ `
        varying vec2 vUv;
        void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`,
      fragmentShader: /* glsl */ `
        uniform sampler2D tSrc;
        uniform float exposure;
        varying vec2 vUv;
        vec3 rrtOdt(vec3 v) {
          vec3 a = v * (v + 0.0245786) - 0.000090537;
          vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
          return a / b;
        }
        vec3 aces(vec3 color) {
          const mat3 inMat = mat3(
            vec3(0.59719, 0.07600, 0.02840),
            vec3(0.35458, 0.90834, 0.13383),
            vec3(0.04823, 0.01566, 0.83777));
          const mat3 outMat = mat3(
            vec3(1.60475, -0.10208, -0.00327),
            vec3(-0.53108, 1.10813, -0.07276),
            vec3(-0.07367, -0.00605, 1.07602));
          color *= exposure / 0.6;
          color = outMat * rrtOdt(inMat * color);
          return clamp(color, 0.0, 1.0);
        }
        vec3 toSRGB(vec3 c) {
          return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
        }
        void main() {
          vec3 c = aces(texture2D(tSrc, vUv).rgb);
          vec2 q = vUv - 0.5;
          c *= 1.0 - dot(q, q) * 0.55;
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
    renderer.setRenderTarget(hdrRT);
    renderer.render(scene, captureCam);
    renderer.setRenderTarget(ldrRT);
    renderer.render(postScene, postCam);
    renderer.readRenderTargetPixels(ldrRT, 0, 0, CAP, CAP, capBuf);
    renderer.setRenderTarget(null);
    phone.visible = true;
    hose.visible = true;

    const cv = document.createElement('canvas');
    cv.width = cv.height = CAP;
    const cx = cv.getContext('2d');
    const img = cx.createImageData(CAP, CAP);
    const row = CAP * 4;
    for (let y = 0; y < CAP; y++) img.data.set(capBuf.subarray((CAP - 1 - y) * row, (CAP - y) * row), y * row);
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

  // Score: how centred the dog is (radial distance of its projected centre, 0 at 0.9 NDC or off-frame),
  // weighted by how much of the frame it fills, minus a penalty for hand shake at the moment of capture.
  function scoreShot(cam, shake) {
    dog.body.getWorldPosition(tmpV);
    const dist = cam.position.distanceTo(tmpV);
    tmpV2.copy(tmpV).applyMatrix4(cam.matrixWorldInverse);
    let score = 0;
    if (tmpV2.z < 0) {
      tmpV.project(cam);
      if (Math.abs(tmpV.x) <= 1 && Math.abs(tmpV.y) <= 1) {
        const centred = Math.max(0, 1 - Math.hypot(tmpV.x, tmpV.y) / 0.9);
        const frac = 0.85 / (dist * 2 * Math.tan(deg(cam.fov / 2)));
        const size = Math.sqrt(clamp(frac / 0.2, 0, 1));
        score = Math.pow(centred, 0.8) * (0.55 + 0.45 * size);
      }
    }
    return score - Math.min(0.35, shake * 1.2) + (Math.random() - 0.5) * 0.08;
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
    aim.yaw = clamp(want.yaw + rand(-0.06, 0.06), -0.3, 0.3);
    aim.pitch = clamp(want.pitch + rand(-0.04, 0.04), -0.35, 0.08);
    session = { frames: [], eligible: 0, best: null, nextShot: time + INTERVALS[ui.interval] };
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
      updateFlash();
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
      if (++s.eligible >= MAX_ELIGIBLE) endSession();
    } else if (!s.best || frame.score > s.best.score) {
      s.best = frame;
    }
  }

  function updateSession() {
    if (!session || time < session.nextShot) return;
    session.nextShot = time + INTERVALS[ui.interval];
    takeShot();
  }

  function updateFlash() {
    const k = Math.exp(-(time - flashAt) / 0.08);
    flashLight.intensity = k > 0.01 ? 40 * k : 0;
    if (flashLight.intensity > 0) {
      flashLight.position.copy(FLASH_LOCAL).applyMatrix4(phone.matrixWorld);
      flashLight.target.position.copy(BACK_LOCAL).applyQuaternion(phone.quaternion).multiplyScalar(10).add(flashLight.position);
      flashLight.target.updateMatrixWorld();
    }
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
    if (!reduced) grassTime.value += dt;

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
  applyDog();
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
