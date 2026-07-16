import "./style.css";
import * as THREE from "three";
import { EffectComposer }  from "three/examples/jsm/postprocessing/EffectComposer.js";
import { RenderPass }      from "three/examples/jsm/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/examples/jsm/postprocessing/UnrealBloomPass.js";
import { OutputPass }      from "three/examples/jsm/postprocessing/OutputPass.js";
import createStrip from "./objects/Strip.js";

// ---------------------------------------------------------------------------
// Scene
// ---------------------------------------------------------------------------
const scene = new THREE.Scene();

const camera = new THREE.PerspectiveCamera(
    45, // Field Of View
    window.innerWidth / window.innerHeight,  // Aspect Ratio
    0.1, // Near Plane
    100  // Far Plane
);
camera.position.z = 8;

// ---------------------------------------------------------------------------
// Renderer
// ---------------------------------------------------------------------------
// toneMapping and toneMappingExposure are read by OutputPass.
// ACESFilmicToneMapping applies a physically-based S-curve that keeps the
// dark base near-black while compressing HDR highlights into display range.
// ---------------------------------------------------------------------------
const renderer = new THREE.WebGLRenderer({
    canvas: document.querySelector("#bg"),
    antialias: true,
});

renderer.setSize(window.innerWidth, window.innerHeight);
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.toneMapping         = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 0.9;  // slight reduction from 1.0 — compensates for lower uEmissionStrength

// ---------------------------------------------------------------------------
// Strip mesh
// ---------------------------------------------------------------------------
const stripMesh = createStrip();
scene.add(stripMesh);

// ---------------------------------------------------------------------------
// Post-processing — EffectComposer
// ---------------------------------------------------------------------------
// A HalfFloatType render target is required so values above 1.0 (produced by
// the HDR emission layer) are preserved between passes.
// FloatType would also work but costs twice the VRAM for no perceptible gain.
// ---------------------------------------------------------------------------
const renderTarget = new THREE.WebGLRenderTarget(
    window.innerWidth  * Math.min(window.devicePixelRatio, 2),
    window.innerHeight * Math.min(window.devicePixelRatio, 2),
    { type: THREE.HalfFloatType }
);

const composer = new EffectComposer(renderer, renderTarget);

// Pass 1 — RenderPass
// Renders the scene (strip + shader) into the HDR buffer.
// All nine shader layers execute here. Output may contain values > 1.0.
composer.addPass(new RenderPass(scene, camera));

// ---------------------------------------------------------------------------
// Bloom configuration — named constants for easy future tuning / animation.
//
// BLOOM_THRESHOLD  Pixels below this luminance do not contribute to bloom.
//                  Raised to 0.90 — only the brightest highlight pixels bloom.
//                  Dark base (~0.052) and static reflection (~0.067) are unaffected.
//
// BLOOM_STRENGTH   Reduced to 0.18 — bloom supports the reflection, does not dominate.
//                  At uEmissionStrength=1.1 the HDR headroom above threshold is ~0.20.
//                  A strength of 0.18 produces a delicate glow, not a halo.
//
// BLOOM_RADIUS     Reduced to 0.35 — bloom stays close to the highlight edge.
//                  No large soft halo. Bleed is contained to ~10–15px at 1080p.
// ---------------------------------------------------------------------------
const BLOOM_THRESHOLD = 0.90;
const BLOOM_STRENGTH  = 0.18;
const BLOOM_RADIUS    = 0.35;

// Pass 2 — UnrealBloomPass
// Extracts pixels above BLOOM_THRESHOLD, blurs them via a dual Kawase
// downsample/upsample pyramid, then additively blends back onto the buffer.
const bloomPass = new UnrealBloomPass(
    new THREE.Vector2(window.innerWidth, window.innerHeight),
    BLOOM_STRENGTH,
    BLOOM_RADIUS,
    BLOOM_THRESHOLD
);
composer.addPass(bloomPass);

// Pass 3 — OutputPass
// Applies renderer.toneMapping (ACESFilmic) and converts linear → sRGB.
// Must be the final pass. Without this, the canvas receives raw linear HDR.
composer.addPass(new OutputPass());

// ---------------------------------------------------------------------------
// Animation configuration
// ---------------------------------------------------------------------------
// SWEEP_SPEED  — full left-to-right cycles per second.
// SWEEP_MIN    — UV X position where the light enters  (slightly left of 0).
// SWEEP_MAX    — UV X position where the light exits   (slightly right of 1).
//
// Overshooting the [0, 1] UV range ensures the highlight fades in/out
// naturally via the Gaussian decay rather than popping at the strip edge.
// ---------------------------------------------------------------------------
const SWEEP_SPEED = 0.18;   // cycles / second
const SWEEP_MIN   = -0.2;   // entry position in UV X space
const SWEEP_MAX   =  1.2;   // exit  position in UV X space

renderer.setAnimationLoop((timeMs) => {
    const uniforms = stripMesh.material.uniforms;

    // Convert browser timestamp (milliseconds) to seconds.
    const t = timeMs * 0.001;
    uniforms.uTime.value = t;

    // Compute the light's current X position in UV space.
    // % 1.0 produces a [0, 1) sawtooth that loops perfectly every (1/SWEEP_SPEED) seconds.
    // We remap it to [SWEEP_MIN, SWEEP_MAX] so the light travels past both edges.
    const sweep = (t * SWEEP_SPEED) % 1.0;           // sawtooth [0, 1)
    uniforms.uLightPosition.value = SWEEP_MIN + sweep * (SWEEP_MAX - SWEEP_MIN);

    // composer.render() executes all three passes in sequence:
    // RenderPass → UnrealBloomPass → OutputPass
    composer.render();
});

// ---------------------------------------------------------------------------
// Resize handler
// ---------------------------------------------------------------------------
// Both renderer and composer must be resized together.
// The bloom pass resolution also needs updating to avoid stretching artefacts.
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
