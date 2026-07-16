import * as THREE from "three";
import vertexShader   from "../shaders/strip.vert.glsl";
import fragmentShader from "../shaders/strip.frag.glsl";

// =============================================================================
// SHARED RESOURCES  (module scope — created once, reused by every instance)
// =============================================================================
// PlaneGeometry(4, 1) — UV orientation:
//   U (vUv.x) → long axis  (width  = 4 units)
//   V (vUv.y) → short axis (height = 1 unit)
//
// UV coordinates span [0,1]×[0,1] regardless of mesh.scale.
// The shader's noise, Gaussians, and edge falloffs are UV-space operations,
// so material character scales proportionally with panel size — correct.
// =============================================================================
const SHARED_GEOMETRY = new THREE.PlaneGeometry(4, 1);

// Shader sources imported as strings by vite-plugin-glsl.
// Three.js WebGLPrograms caches programs keyed on source strings —
// all instances share one compiled GPU program.
const VERTEX_SHADER   = vertexShader;
const FRAGMENT_SHADER = fragmentShader;

// =============================================================================
// DEFAULT CONFIG
// =============================================================================
const DEFAULTS = {
    id:               "strip",
    position:         new THREE.Vector3(0, 0, 0),
    scale:            { x: 1.0, y: 1.0 },   // multiplied onto base geometry (4×1)
    rotation:         Math.PI / 4,
    phaseOffset:      0.0,     // seconds — shifts sweep start time
    sweepSpeed:       0.18,    // cycles / second
    sweepMin:        -0.2,     // UV X entry (slightly past left edge)
    sweepMax:         1.2,     // UV X exit  (slightly past right edge)
    emissionStrength: 1.1,
    colorIntensity:   0.45,
    lightIntensity:   1.0,
};

// =============================================================================
// createStrip(config) — Strip System factory
// =============================================================================
// Returns a StripInstance:
//   { id, mesh, update(t), setLightColor(c), setEmission(v),
//     setColorIntensity(v), setLightSpeed(v) }
//
// Caller responsibilities:
//   1. Add instance.mesh to the scene.
//   2. Call instance.update(t) every frame with wall-clock seconds.
//
// Shader files are NOT modified — purely JS architecture.
// =============================================================================
export function createStrip(config = {}) {
    const cfg = {
        id:               config.id               ?? DEFAULTS.id,
        position:         config.position         ?? DEFAULTS.position,
        scale:            config.scale            ?? DEFAULTS.scale,
        rotation:         config.rotation         ?? DEFAULTS.rotation,
        phaseOffset:      config.phaseOffset      ?? DEFAULTS.phaseOffset,
        sweepSpeed:       config.sweepSpeed       ?? DEFAULTS.sweepSpeed,
        sweepMin:         config.sweepMin         ?? DEFAULTS.sweepMin,
        sweepMax:         config.sweepMax         ?? DEFAULTS.sweepMax,
        emissionStrength: config.emissionStrength ?? DEFAULTS.emissionStrength,
        colorIntensity:   config.colorIntensity   ?? DEFAULTS.colorIntensity,
        lightIntensity:   config.lightIntensity   ?? DEFAULTS.lightIntensity,
    };

    // -------------------------------------------------------------------------
    // Per-instance uniforms — completely independent per strip
    // -------------------------------------------------------------------------
    const uniforms = {
        uTime:             { value: 0 },
        uBaseColor:        { value: new THREE.Color(0.052, 0.052, 0.052) },
        uLightColor:       { value: new THREE.Color("#EC044F") },
        uLightPosition:    { value: cfg.sweepMin },
        uLightWidth:       { value: 0.05 },
        uLightIntensity:   { value: cfg.lightIntensity },
        uColorIntensity:   { value: cfg.colorIntensity },
        uEmissionStrength: { value: cfg.emissionStrength },
        uEnableEmission:   { value: 1.0 },
        uMetalStrength:    { value: 1.0 },
        uNoiseStrength:    { value: 0.4 },  // improved via 3-octave noise (Phase 7.5)
    };

    // -------------------------------------------------------------------------
    // Material — shared shader sources, independent uniforms
    // -------------------------------------------------------------------------
    const material = new THREE.ShaderMaterial({
        vertexShader:   VERTEX_SHADER,
        fragmentShader: FRAGMENT_SHADER,
        uniforms,
        transparent: true,
        depthWrite:  false,
    });

    // -------------------------------------------------------------------------
    // Mesh — shared geometry, independent material + scale
    // -------------------------------------------------------------------------
    const mesh = new THREE.Mesh(SHARED_GEOMETRY, material);
    mesh.position.set(
        cfg.position.x ?? 0,
        cfg.position.y ?? 0,
        cfg.position.z ?? 0
    );
    mesh.scale.set(cfg.scale.x, cfg.scale.y, 1.0);
    mesh.rotation.z = cfg.rotation;
    mesh.name = cfg.id;

    // Private mutable animation state
    let currentSweepSpeed = cfg.sweepSpeed;

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /** Call every frame with wall-clock seconds. Writes uTime + uLightPosition. */
    function update(t) {
        const localT  = t + cfg.phaseOffset;
        const sweep   = (localT * currentSweepSpeed) % 1.0;
        uniforms.uTime.value          = t;
        uniforms.uLightPosition.value = cfg.sweepMin + sweep * (cfg.sweepMax - cfg.sweepMin);
    }

    /** Set brand color — accepts THREE.Color, hex string, or hex number. */
    function setLightColor(color) {
        if (color instanceof THREE.Color) {
            uniforms.uLightColor.value.copy(color);
        } else {
            uniforms.uLightColor.value.set(color);
        }
    }

    /** Set HDR emission multiplier (0.0 → 2.0+). */
    function setEmission(value) {
        uniforms.uEmissionStrength.value = value;
    }

    /** Set brand-color fringe intensity (0.0 = white only → 1.0 = full color). */
    function setColorIntensity(value) {
        uniforms.uColorIntensity.value = value;
    }

    /** Change sweep speed in cycles/second at runtime. */
    function setLightSpeed(value) {
        currentSweepSpeed = value;
    }

    return { id: cfg.id, mesh, update, setLightColor, setEmission, setColorIntensity, setLightSpeed };
}

// =============================================================================
// buildStripSystem()  — Phase 7 debug grid  (preserved)
// =============================================================================
// Six strips in a 2×3 grid with evenly-distributed phase offsets.
// Used for material and system validation — not the final hero layout.
// =============================================================================
export function buildStripSystem() {
    const STRIP_COUNT  = 6;
    const SWEEP_SPEED  = 0.18;
    const CYCLE_PERIOD = 1.0 / SWEEP_SPEED;
    const PHASE_STEP   = CYCLE_PERIOD / STRIP_COUNT;

    const GRID = [
        { col: 0, row: 0 }, { col: 1, row: 0 },
        { col: 0, row: 1 }, { col: 1, row: 1 },
        { col: 0, row: 2 }, { col: 1, row: 2 },
    ];
    const COL_X = [-2.6,  2.6];
    const ROW_Y = [ 2.4,  0.0, -2.4];

    return GRID.map(({ col, row }, i) =>
        createStrip({
            id:          `strip-${i}`,
            position:    { x: COL_X[col], y: ROW_Y[row], z: 0 },
            phaseOffset: i * PHASE_STEP,
            sweepSpeed:  SWEEP_SPEED,
        })
    );
}

// =============================================================================
// buildHeroComposition()  — Phase 8 final hero layout
// =============================================================================
// Six panels in an asymmetric diagonal composition.
//
// DESIGN PRINCIPLES
// -----------------
// • Strong size hierarchy: panels range from 2.4 to 5.6 world-units wide.
// • Irregular vertical spacing — no two panels share the same Y gap.
// • Lateral offset cascade — each panel steps further right as it descends,
//   creating a diagonal flow that matches the π/4 strip rotation.
// • Z depth layering: ±0.30 range creates natural overlap without z-fighting
//   (depthWrite:false on all panels).
// • Timing: phase offsets cover the full cycle; sweep speeds vary ±5%
//   so the pattern evolves organically over ~30 seconds without appearing
//   random at first glance.
//
// PANEL ROLES
// -----------
//  0  "hero"      — dominant, widest, highest position
//  1  "accent"    — medium, steps right and down, slightly behind hero
//  2  "wide"      — second-widest, anchors the middle band, pushed left
//  3  "slim"      — narrowest, recedes far right and deep into Z
//  4  "mid"       — medium-wide, lower-left, in front of the Z stack
//  5  "tail"      — medium, lowest, steps right, closes the cascade
//
// PANEL DATA
// ----------
// position:  { x, y, z }   world-space centre
// scale:     { x, y }      multiplied onto PlaneGeometry(4,1)
//                          effective world size = (4·scaleX) × (1·scaleY)
// phaseOffset: seconds     deterministic — no random() calls
// sweepSpeed:  cycles/s    varies slightly to desynchronise over time
//
// All panels share rotation = Math.PI / 4
// =============================================================================
export function buildHeroComposition() {
    // -----------------------------------------------------------------------
    // Shared base speed — cycle period ≈ 5.56 s.
    // Phase offsets are 1/6 of the cycle apart so at t=0 the six lights
    // are evenly spread across the UV range (staggered, not bunched).
    // -----------------------------------------------------------------------
    const BASE_SPEED   = 0.18;
    const CYCLE        = 1.0 / BASE_SPEED;   // ≈ 5.56 s
    const SIXTH        = CYCLE / 6;           // ≈ 0.93 s

    // -----------------------------------------------------------------------
    // Hero panel definitions — edit only this array to change the composition
    // -----------------------------------------------------------------------
    const PANELS = [
        // ---- Panel 0: hero ----
        // Widest panel, sits high and slightly left of centre.
        // Strongest emission — commands the top of the composition.
        {
            id:               'panel-hero',
            position:         { x: -1.20, y:  2.80, z:  0.00 },
            scale:            { x:  1.40, y:  0.55 },
            phaseOffset:      0 * SIXTH,
            sweepSpeed:       BASE_SPEED,
            emissionStrength: 1.20,
            colorIntensity:   0.52,
            lightIntensity:   1.00,
        },

        // ---- Panel 1: accent ----
        // Medium width, steps right and drops from the hero.
        // Slightly behind (z=-0.12) so it reads as secondary depth.
        {
            id:               'panel-accent',
            position:         { x:  1.80, y:  1.30, z: -0.12 },
            scale:            { x:  0.90, y:  0.42 },
            phaseOffset:      1 * SIXTH,
            sweepSpeed:       BASE_SPEED * 0.96,
            emissionStrength: 1.08,
            colorIntensity:   0.42,
            lightIntensity:   0.95,
        },

        // ---- Panel 2: wide ----
        // Second-widest. Anchors the centre-left.
        // Pushed furthest left and slightly forward in Z.
        // Its extra width creates visual tension with the narrower panels
        // on the right side of the composition.
        {
            id:               'panel-wide',
            position:         { x: -2.60, y: -0.20, z:  0.08 },
            scale:            { x:  1.30, y:  0.52 },
            phaseOffset:      2 * SIXTH,
            sweepSpeed:       BASE_SPEED * 1.05,
            emissionStrength: 1.15,
            colorIntensity:   0.48,
            lightIntensity:   0.98,
        },

        // ---- Panel 3: slim ----
        // Narrowest panel. Far right, low, pushed deep into Z (-0.28).
        // Creates the strongest depth cue — the eye reads it as distant.
        {
            id:               'panel-slim',
            position:         { x:  2.80, y: -0.95, z: -0.28 },
            scale:            { x:  0.62, y:  0.34 },
            phaseOffset:      3 * SIXTH,
            sweepSpeed:       BASE_SPEED * 0.93,
            emissionStrength: 0.95,
            colorIntensity:   0.36,
            lightIntensity:   0.88,
        },

        // ---- Panel 4: mid ----
        // Medium-wide, lower-left band. Slightly in front of the Z stack.
        // Bridges the visual gap between the wide anchor and the lower panels.
        {
            id:               'panel-mid',
            position:         { x: -1.00, y: -2.20, z:  0.04 },
            scale:            { x:  1.05, y:  0.46 },
            phaseOffset:      4 * SIXTH,
            sweepSpeed:       BASE_SPEED * 1.02,
            emissionStrength: 1.10,
            colorIntensity:   0.44,
            lightIntensity:   0.96,
        },

        // ---- Panel 5: tail ----
        // Closes the diagonal cascade. Steps right and drops to the bottom.
        // Medium width — heavier than the slim panel, lighter than mid.
        {
            id:               'panel-tail',
            position:         { x:  1.40, y: -3.30, z: -0.10 },
            scale:            { x:  0.82, y:  0.40 },
            phaseOffset:      5 * SIXTH,
            sweepSpeed:       BASE_SPEED * 0.97,
            emissionStrength: 1.00,
            colorIntensity:   0.40,
            lightIntensity:   0.92,
        },
    ];

    return PANELS.map(cfg => createStrip({ ...cfg, rotation: Math.PI / 4 }));
}
