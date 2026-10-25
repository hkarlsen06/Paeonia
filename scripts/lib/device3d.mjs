// 3D iPhone and iPad models for the App Store screenshot renderer.
// WebGL runs on SwiftShader, so reruns match to within a few levels per channel.
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';

const threeDir = path.resolve(createRequire(import.meta.url).resolve('three'), '../..');
const types = { '.html': 'text/html', '.js': 'text/javascript', '.png': 'image/png', '.ttf': 'font/ttf', '.otf': 'font/otf' };

// Each device in millimetres. capture is the simulator screenshot size, which is also the App Store
// panel size, and ppi makes that capture fill the display exactly. bevel is the radius of the rounded
// frame edge. screenRadius is the display's corner in capture pixels. island is the Dynamic Island
// in capture pixels, and camera the diameter of a front camera centred in the right-hand bezel.
// buttons are [edge, centre from the top (left and right edges) or from the right (top edge),
// length, sapphire].
export const MODELS = {
  iPhone: { // iPhone 17 Pro Max
    capture: [1320, 2868], ppi: 460,
    width: 78, height: 163.4, depth: 8.75, radius: 13.5, bevel: 1.4, screenRadius: 186,
    island: { width: 378, height: 111, top: 33 },
    button: { width: 1.4, depth: 2.6, radius: 0.6 },
    buttons: [['left', 31, 7], ['left', 46, 13], ['left', 62, 13], ['right', 50, 19], ['right', 112, 17, true]],
  },
  iPad: { // iPad Pro 13-inch (M5). The corners and buttons follow Simulator's tablet5 device chrome.
    capture: [2064, 2752], ppi: 264,
    width: 215.5, height: 281.6, depth: 5.1, radius: 14.4, bevel: 1, screenRadius: 62,
    camera: 2.2,
    button: { width: 1.1, depth: 2, radius: 0.5 },
    buttons: [['right', 22.5, 10], ['right', 34.6, 10], ['top', 18.4, 12]],
  },
};

export const launch = chromium =>
  chromium.launch({ headless: true, args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });

// Put this in the page's HTML so renderDevices can reach three.js.
export const threeImports = `
    <script type="importmap">{"imports":{"three":"/three/build/three.module.js","three/addons/":"/three/examples/jsm/"}}</script>
    <script type="module">
      import * as THREE from 'three';
      import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
      import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
      import { mergeVertices } from 'three/addons/utils/BufferGeometryUtils.js';
      window.lib = { THREE, RoomEnvironment, RoundedBoxGeometry, mergeVertices };
    </script>`;

// Opens a page of the given size that serves html at /, three.js, captures under /capture/ and the font under /font.
export async function openPage(browser, { width, height, html, captures, font }) {
  const tab = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
  await tab.route('http://render.local/**', async route => {
    const [scope, ...rest] = decodeURIComponent(new URL(route.request().url()).pathname).slice(1).split('/');
    const file = scope === 'three' ? path.join(threeDir, ...rest)
      : scope === 'capture' ? path.join(captures, ...rest)
      : scope.startsWith('font') && font ? font : null;
    await route.fulfill(file
      ? { body: await readFile(file), contentType: types[path.extname(file)] }
      : { body: html, contentType: types['.html'] });
  });
  await tab.goto('http://render.local/');
  await tab.waitForFunction(() => window.lib);
  return tab;
}

// Runs in the page. Fits each panel's caption, then builds the model, one of MODELS, renders each
// capture on it into its own transparent canvas and places that canvas on the strip. A panel is the
// model's capture size; spec.x and spec.height are fractions of it. A device's visual centre, the
// middle of its outline on screen, sits halfway between the bottom of its panel's caption and the
// bottom of the panel. A spec with spotlight dims the screen around spotlights[spec.screen], an
// element's frame in capture pixels. Its { dim, padding, radius, feather, lift, glow, scale } are the
// darkening (0 to 1), the room left around the element, the corner radius and the soft edge in
// pixels, how much larger the lit element is drawn, the colour of its glowing outline and sparkles,
// and an optional size factor for the outline, shadow and sparkles. Returns the centres in pixels;
// throws if the layout is broken.
export async function renderDevices({ model, layout, finish, captures, spotlights }) {
  const { THREE, RoomEnvironment, RoundedBoxGeometry, mergeVertices } = window.lib;
  const { width, height, depth, radius, bevel: B } = model;
  const [W, H] = model.capture;
  const glassW = width - 2 * B, glassH = height - 2 * B;
  const pxPerMm = model.ppi / 25.4;
  const outline = (w, h, r) => {
    const s = new THREE.Shape(), x = w / 2, y = h / 2;
    s.moveTo(-x + r, -y);
    s.lineTo(x - r, -y); s.quadraticCurveTo(x, -y, x, -y + r);
    s.lineTo(x, y - r); s.quadraticCurveTo(x, y, x - r, y);
    s.lineTo(-x + r, y); s.quadraticCurveTo(-x, y, -x, y - r);
    s.lineTo(-x, -y + r); s.quadraticCurveTo(-x, -y, -x + r, -y);
    return s;
  };

  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
  const gl = renderer.getContext();
  const gpu = gl.getParameter(gl.getExtension('WEBGL_debug_renderer_info')?.UNMASKED_RENDERER_WEBGL ?? gl.RENDERER);
  if (!/swiftshader/i.test(gpu)) throw new Error(`WebGL is not on SwiftShader (${gpu}); output would vary by GPU`);
  renderer.setPixelRatio(1);
  renderer.setClearColor(0, 0);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;

  const scene = new THREE.Scene();
  scene.environment = new THREE.PMREMGenerator(renderer).fromScene(new RoomEnvironment(), 0.04).texture;
  const key = new THREE.DirectionalLight('#ffffff', 2.5);
  key.position.set(-1.5, 2, 3);
  scene.add(key);

  const device = new THREE.Group();
  scene.add(device);
  const metal = new THREE.MeshPhysicalMaterial({ color: finish, metalness: 1, roughness: 0.32, clearcoat: 0.4 });
  let frame = new THREE.ExtrudeGeometry(outline(glassW, glassH, radius - B), {
    depth: depth - 2 * B, bevelEnabled: true, bevelSize: B, bevelThickness: B, bevelSegments: 12, curveSegments: 32,
  });
  // Extrusions come out flat shaded. Weld the vertices so the rounded edge shades smoothly.
  frame.deleteAttribute('uv');
  frame.deleteAttribute('normal');
  frame = mergeVertices(frame);
  frame.computeVertexNormals();
  frame.translate(0, 0, -(depth - 2 * B) / 2);
  device.add(new THREE.Mesh(frame, metal));

  const sapphire = new THREE.MeshPhysicalMaterial({ color: '#111318', metalness: 0.2, roughness: 0.1, clearcoat: 1 });
  const { width: bw, depth: bd, radius: br } = model.button;
  for (const [edge, offset, length, isSapphire] of model.buttons) {
    const inset = 0.1 + (isSapphire ? 0.4 : 0);
    const material = isSapphire ? sapphire : metal;
    const button = edge === 'top'
      ? new THREE.Mesh(new RoundedBoxGeometry(length, bw, bd, 4, br), material)
      : new THREE.Mesh(new RoundedBoxGeometry(bw, length, bd, 4, br), material);
    if (edge === 'top') button.position.set(width / 2 - offset, height / 2 - inset, 0);
    else button.position.set((edge === 'left' ? -1 : 1) * (width / 2 - inset), height / 2 - offset, 0);
    device.add(button);
  }

  const glassGeometry = new THREE.ShapeGeometry(outline(glassW, glassH, radius - B), 32);
  const uv = glassGeometry.attributes.uv; // Shape coordinates in millimetres; map them onto the texture.
  for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) / glassW + 0.5, uv.getY(i) / glassH + 0.5);
  const glassMaterial = new THREE.MeshBasicMaterial({ toneMapped: false });
  const glass = new THREE.Mesh(glassGeometry, glassMaterial);
  glass.position.z = depth / 2 + 0.01;
  device.add(glass);

  // Darkens the screen around element, an element's frame in capture pixels, so the element is the
  // first thing the eye finds even in the small preview strip. The element is drawn again a little
  // larger with a soft shadow under it, so it lifts off the dimmed screen, and gets a glowing
  // outline with a few sparkles on it. The capture sits at x0, y0 on the screen canvas.
  function spotlight(c, capture, x0, y0, element, { dim, padding, radius, feather, lift, glow, scale: k = 1 }) {
    const { width: w, height: h } = c.canvas;
    const lit = { x: x0 + element.x - padding, y: y0 + element.y - padding,
      width: element.width + 2 * padding, height: element.height + 2 * padding };
    const cx = lit.x + lit.width / 2, cy = lit.y + lit.height / 2;
    const scaled = { width: lit.width * lift, height: lit.height * lift };
    scaled.x = cx - scaled.width / 2;
    scaled.y = cy - scaled.height / 2;
    // The shade is cut out with an opaque blurred shape that ends a feather beyond the lit area.
    // The fill is opaque, because destination-out removes only as much shade as the fill's alpha.
    const shade = document.createElement('canvas');
    shade.width = w; shade.height = h;
    const s = shade.getContext('2d');
    s.fillStyle = `rgba(0, 0, 0, ${dim})`;
    s.fillRect(0, 0, w, h);
    s.globalCompositeOperation = 'destination-out';
    s.filter = `blur(${feather / 2}px)`;
    s.fillStyle = '#000';
    s.beginPath();
    s.roundRect(scaled.x - feather, scaled.y - feather, scaled.width + 2 * feather, scaled.height + 2 * feather,
      radius + feather);
    s.fill();
    c.drawImage(shade, 0, 0);

    const card = new Path2D();
    card.roundRect(scaled.x, scaled.y, scaled.width, scaled.height, radius * lift);
    c.save();
    c.shadowColor = '#12030cb3';
    c.shadowBlur = 60 * k;
    c.shadowOffsetY = 24 * k;
    c.fillStyle = '#2a0b1d';
    c.fill(card);
    c.restore();
    c.save();
    c.clip(card);
    c.drawImage(capture, lit.x - x0, lit.y - y0, lit.width, lit.height,
      scaled.x, scaled.y, scaled.width, scaled.height);
    c.restore();

    c.save();
    c.strokeStyle = glow;
    c.shadowColor = glow;
    for (const [lineWidth, blur] of [[14, 70], [8, 36], [5, 12]]) {
      c.lineWidth = lineWidth * k;
      c.shadowBlur = blur * k;
      c.stroke(card);
    }
    c.restore();

    // Four-pointed sparkles on the outline, where a corner rounds off and midway along two sides.
    const sparkle = (x, y, size) => {
      c.save();
      c.translate(x, y);
      c.shadowColor = glow;
      c.shadowBlur = size * 0.9;
      c.fillStyle = '#fff6fa';
      c.beginPath();
      for (let i = 0; i < 4; i++) {
        const a = i * Math.PI / 2;
        c.lineTo(Math.cos(a) * size, Math.sin(a) * size);
        c.quadraticCurveTo(0, 0, Math.cos(a + Math.PI / 2) * size, Math.sin(a + Math.PI / 2) * size);
      }
      c.fill();
      c.restore();
    };
    const corner = radius * lift * (1 - Math.SQRT1_2);
    sparkle(scaled.x + scaled.width - corner, scaled.y + corner, 34 * k);
    sparkle(scaled.x, scaled.y + scaled.height * 0.62, 22 * k);
    sparkle(scaled.x + scaled.width * 0.3, scaled.y + scaled.height, 26 * k);
    sparkle(scaled.x + scaled.width + 10 * k, scaled.y + scaled.height * 0.4, 14 * k);
  }

  // Shrink long translations until they fit their panel and break no word.
  await document.fonts.ready;
  const captionBottoms = [];
  for (const [index, section] of [...document.querySelectorAll('section')].entries()) {
    const slot = Number(section.dataset.slot);
    const leaves = () => {
      const text = section.getBoundingClientRect();
      return text.left < slot * W || text.right > (slot + 1) * W
        || [...section.children].some(line => line.scrollWidth > line.clientWidth);
    };
    // The page sets the full size. Shrink in steps of 4/104 of it, down to 76/104.
    const full = parseFloat(getComputedStyle(section).fontSize);
    let size = full;
    while (leaves()) {
      if ((size -= full * 4 / 104) < full * 72 / 104) {
        throw new Error(`Panel ${index + 1} text leaves its screenshot even at ${Math.round(full * 76 / 104)}px`);
      }
      section.style.fontSize = `${size}px`;
    }
    const headline = section.querySelector('h1');
    const lines = Math.round(headline.getBoundingClientRect().height / parseFloat(getComputedStyle(headline).lineHeight));
    if (lines !== 2) throw new Error(`Panel ${index + 1} headline wraps to ${lines} line(s), not 2: ${headline.textContent}`);
    captionBottoms[slot] = section.getBoundingClientRect().bottom;
  }

  const fov = 16;
  const vertex = new THREE.Vector3();
  const layer = document.createElement('div');
  document.body.append(layer);
  const centres = [];
  for (const spec of layout) {
    const capture = new Image();
    capture.src = `/capture/${captures[spec.screen]}`;
    await capture.decode();
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(glassW * pxPerMm);
    canvas.height = Math.round(glassH * pxPerMm);
    const c = canvas.getContext('2d');
    const cw = capture.naturalWidth, ch = capture.naturalHeight;
    const x0 = (canvas.width - cw) / 2, y0 = (canvas.height - ch) / 2;
    c.fillStyle = '#030304';
    c.fillRect(0, 0, canvas.width, canvas.height);
    c.save();
    c.beginPath();
    c.roundRect(x0, y0, cw, ch, model.screenRadius);
    c.clip();
    c.drawImage(capture, x0, y0);
    if (spec.spotlight) spotlight(c, capture, x0, y0, spotlights[spec.screen], spec.spotlight);
    c.restore();
    if (model.island) {
      const { width: iw, height: ih, top } = model.island;
      c.fillStyle = '#000';
      c.beginPath();
      c.roundRect(canvas.width / 2 - iw / 2, y0 + top, iw, ih, ih / 2);
      c.fill();
    }
    if (model.camera) {
      const r = model.camera / 2 * pxPerMm;
      const lens = c.createRadialGradient(0, 0, 0, 0, 0, r);
      lens.addColorStop(0, '#1b2236');
      lens.addColorStop(0.5, '#07080c');
      lens.addColorStop(1, '#0b0b0e');
      c.save();
      c.translate((canvas.width + x0 + cw) / 2, canvas.height / 2);
      c.fillStyle = lens;
      c.beginPath();
      c.arc(0, 0, r, 0, 2 * Math.PI);
      c.fill();
      c.restore();
    }
    const glare = c.createLinearGradient(0, 0, canvas.width, canvas.height * 0.6);
    glare.addColorStop(0, '#ffffff14');
    glare.addColorStop(0.46, '#ffffff05');
    glare.addColorStop(0.46, '#ffffff00');
    c.fillStyle = glare;
    c.fillRect(0, 0, canvas.width, canvas.height);
    glassMaterial.map?.dispose();
    glassMaterial.map = new THREE.CanvasTexture(canvas);
    glassMaterial.map.colorSpace = THREE.SRGBColorSpace;
    glassMaterial.map.anisotropy = renderer.capabilities.getMaxAnisotropy();
    glassMaterial.needsUpdate = true;

    // Frame the camera so the device is spec.height of the panel tall, with room for any rotation.
    const devicePx = spec.height * H, size = Math.ceil(devicePx * 1.35);
    const distance = (height * size / devicePx) / 2 / Math.tan(THREE.MathUtils.degToRad(fov / 2));
    // Near and far hug the device. The glass sits 0.01 mm above the frame, and a near plane far in
    // front of a large device leaves too little depth precision to keep the frame behind it.
    const camera = new THREE.PerspectiveCamera(fov, 1, distance - height, distance + height);
    camera.position.z = distance;
    device.rotation.set(...spec.rotate.map(THREE.MathUtils.degToRad), 'ZYX');
    device.updateMatrixWorld();
    renderer.setSize(size, size, false);
    renderer.render(scene, camera);

    // Where the device's outline falls in the rendered square. A tilt moves it off the square's centre.
    const extent = { left: Infinity, top: Infinity, right: -Infinity, bottom: -Infinity };
    const positions = frame.attributes.position;
    for (let i = 0; i < positions.count; i++) {
      vertex.fromBufferAttribute(positions, i).applyMatrix4(device.matrixWorld).project(camera);
      const x = (vertex.x + 1) / 2 * size, y = (1 - vertex.y) / 2 * size;
      extent.left = Math.min(extent.left, x); extent.right = Math.max(extent.right, x);
      extent.top = Math.min(extent.top, y); extent.bottom = Math.max(extent.bottom, y);
    }
    const panel = Math.floor(spec.x), captionBottom = captionBottoms[panel];
    const centre = { x: spec.x * W, y: (captionBottom + H) / 2 };
    const left = centre.x - (extent.left + extent.right) / 2, top = centre.y - (extent.top + extent.bottom) / 2;
    const box = { left: left + extent.left, right: left + extent.right, top: top + extent.top, bottom: top + extent.bottom };

    // Every device stays inside its own panel, clear of the caption, so no screenshot cuts off part of it.
    const margin = 0.02 * W;
    if (box.left < panel * W + margin || box.right > (panel + 1) * W - margin) {
      throw new Error(`The ${spec.screen} device is cut off at the edge of panel ${panel + 1}`);
    }
    if (box.top < captionBottom + margin) {
      throw new Error(`The ${spec.screen} device is too tall for the space under the panel ${panel + 1} caption`);
    }
    centres.push(centre);

    const image = new Image();
    image.src = renderer.domElement.toDataURL('image/png');
    await image.decode();
    Object.assign(image.style, { left: `${left}px`, top: `${top}px`, width: `${size}px`, height: `${size}px` });
    image.alt = spec.screen;
    layer.append(image);
  }
  renderer.dispose();
  return centres;
}
