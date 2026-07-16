import "./style.css";
import * as THREE from "three";
import { EffectComposer }  from "three/examples/jsm/postprocessing/EffectComposer.js";
import { RenderPass }      from "three/examples/jsm/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/examples/jsm/postprocessing/UnrealBloomPass.js";
import { OutputPass }      from "three/examples/jsm/postprocessing/OutputPass.js";
import { buildStripSystem } from "./objects/Strip.js";

// ---------------------------------------------------------------------------
// Scene
// ---------------------------------------------------------------------------
const scene = new THREE.Scene();

// Camera pulled back to z=8 — the 2×3 grid spans ±2.6 X and ±2.4 Y,
// which fits comfortably in a 45° FOV frustum at this distance.
const camera = new THREE.PerspectiveCamera(
    45,
    window.innerWidth / window.innerHeight,
    0.1,
    100
);
camera.position.z = 8;

// ---------------------------------------------------------------------------
// Renderer
// ---------------------------------------------------------------------------
// ACESFilmicToneMapping and toneMappingExposure are consumed by OutputPass.
// ---------------------------------------------------------------------------
const renderer = new THREE.WebGLRenderer({
    canvas: document.querySelector("#bg"),
    antialias: true,
});

renderer.setSize(window.innerWidth, window.innerHeight);
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.toneMapping         = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 0.9;

// ---------------------------------------------------------------------------
// Strip System — six independent instances, 2×3 debug grid
// ---------------------------------------------------------------------------
// buildStripSystem() returns Array<StripInstance>.
// Each instance owns its own ShaderMaterial and uniforms.
// All instances share one PlaneGeometry and one compiled GPU shader program.
// ---------------------------------------------------------------------------
const strips = buildStripSystem();
strips.forEach(strip => scene.add(strip.mesh));

// ---------------------------------------------------------------------------
// Post-processing — EffectComposer
// ---------------------------------------------------------------------------
const renderTarget = new THREE.WebGLRenderTarget(
    window.innerWidth  * Math.min(window.devicePixelRatio, 2),
    window.innerHeight * Math.min(window.devicePixelRatio, 2),
    { type: THREE.HalfFloatType }
);

const composer = new EffectComposer(renderer, renderTarget);

// Pass 1 — RenderPass: renders all six strips into the HDR buffer.
composer.addPass(new RenderPass(scene, camera));

// ---------------------------------------------------------------------------
// Bloom configuration
// ---------------------------------------------------------------------------
const BLOOM_THRESHOLD = 0.90;
const BLOOM_STRENGTH  = 0.18;
const BLOOM_RADIUS    = 0.35;

// Pass 2 — UnrealBloomPass
const bloomPass = new UnrealBloomPass(
    new THREE.Vector2(window.innerWidth, window.innerHeight),
    BLOOM_STRENGTH,
    BLOOM_RADIUS,
    BLOOM_THRESHOLD
);
composer.addPass(bloomPass);

// Pass 3 — OutputPass: ACESFilmic tone mapping + linear → sRGB.
composer.addPass(new OutputPass());

// ---------------------------------------------------------------------------
// Animation loop
// ---------------------------------------------------------------------------
// main.js responsibilities here are minimal and deliberate:
//   1. Convert timeMs to seconds.
//   2. Call strip.update(t) for every strip — all uniform writes happen there.
//   3. Call composer.render().
//
// main.js does NOT manipulate any uniforms directly.
// ---------------------------------------------------------------------------
renderer.setAnimationLoop((timeMs) => {
    const t = timeMs * 0.001;

    // Delegate all animation state to each strip instance.
    strips.forEach(strip => strip.update(t));

    composer.render();
});

// ---------------------------------------------------------------------------
// Resize handler
// ---------------------------------------------------------------------------
window.addEventListener("resize", () => {
    const w  = window.innerWidth;
    const h  = window.innerHeight;

    camera.aspect = w / h;
    camera.updateProjectionMatrix();

    renderer.setSize(w, h);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

    composer.setSize(w, h);
    bloomPass.resolution.set(w, h);
});
