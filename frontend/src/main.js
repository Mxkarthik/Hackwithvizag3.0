import "./style.css";
import * as THREE from "three";
import { EffectComposer }  from "three/examples/jsm/postprocessing/EffectComposer.js";
import { RenderPass }      from "three/examples/jsm/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/examples/jsm/postprocessing/UnrealBloomPass.js";
import { OutputPass }      from "three/examples/jsm/postprocessing/OutputPass.js";
import { buildHeroComposition } from "./objects/Strip.js";

// ---------------------------------------------------------------------------
// Scene
// ---------------------------------------------------------------------------
const scene = new THREE.Scene();

// Camera at z=9 — the hero composition spans y ≈ +3.3 to y ≈ -3.8,
// fitting comfortably within the 7.46-unit frustum height at this distance.
const camera = new THREE.PerspectiveCamera(
    45,
    window.innerWidth / window.innerHeight,
    0.1,
    100
);
camera.position.z = 9;

// ---------------------------------------------------------------------------
// Renderer
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
// Hero composition — six asymmetric panels
// ---------------------------------------------------------------------------
// buildHeroComposition() returns Array<StripInstance>.
// Each instance owns its own ShaderMaterial and uniforms.
// All instances share one PlaneGeometry and one compiled GPU shader program.
// Panel sizing is applied via mesh.scale — no geometry duplication.
// ---------------------------------------------------------------------------
const strips = buildHeroComposition();
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
composer.addPass(new RenderPass(scene, camera));

// ---------------------------------------------------------------------------
// Bloom configuration
// ---------------------------------------------------------------------------
const BLOOM_THRESHOLD = 0.90;
const BLOOM_STRENGTH  = 0.18;
const BLOOM_RADIUS    = 0.35;

const bloomPass = new UnrealBloomPass(
    new THREE.Vector2(window.innerWidth, window.innerHeight),
    BLOOM_STRENGTH,
    BLOOM_RADIUS,
    BLOOM_THRESHOLD
);
composer.addPass(bloomPass);
composer.addPass(new OutputPass());

// ---------------------------------------------------------------------------
// Animation loop
// ---------------------------------------------------------------------------
// main.js only: converts timestamp, calls update on each strip, renders.
// All uniform writes are delegated to StripInstance.update(t).
// ---------------------------------------------------------------------------
renderer.setAnimationLoop((timeMs) => {
    const t = timeMs * 0.001;
    strips.forEach(strip => strip.update(t));
    composer.render();
});

// ---------------------------------------------------------------------------
// Resize handler
// ---------------------------------------------------------------------------
window.addEventListener("resize", () => {
    const w = window.innerWidth;
    const h = window.innerHeight;

    camera.aspect = w / h;
    camera.updateProjectionMatrix();

    renderer.setSize(w, h);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

    composer.setSize(w, h);
    bloomPass.resolution.set(w, h);
});
