import "./style.css";
import * as THREE from "three";
import createStrip from "./objects/Strip.js";

const scene = new THREE.Scene();

const camera = new THREE.PerspectiveCamera(
    45, // Field Of View
    window.innerWidth / window.innerHeight,  // Aspect Ratio
    0.1, // Near Plane
    100 // Far plane 
);

camera.position.z = 8;


const renderer = new THREE.WebGLRenderer({
    canvas: document.querySelector("#bg"),
    antialias: true,
});

renderer.setSize(
    window.innerWidth,
    window.innerHeight
);

renderer.setPixelRatio(
    Math.min(window.devicePixelRatio, 2)
);

const stripMesh = createStrip();
scene.add(stripMesh);

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
    // fract() produces a [0, 1) sawtooth that loops perfectly every (1/SWEEP_SPEED) seconds.
    // We remap it to [SWEEP_MIN, SWEEP_MAX] so the light travels past both edges.
    const sweep = (t * SWEEP_SPEED) % 1.0;           // sawtooth [0, 1)
    uniforms.uLightPosition.value = SWEEP_MIN + sweep * (SWEEP_MAX - SWEEP_MIN);

    renderer.render(scene, camera);
});


