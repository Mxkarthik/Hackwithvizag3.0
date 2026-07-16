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
// buildHeroComposition()  — Phase 10: orientation corrected, 6-strip composition
// =============================================================================
//
// ROTATION: -Math.PI/4  (strips lean \\ — top-right to bottom-left)
//
// COMPOSITION MODEL
// -----------------
// 6 strips forming a dense diagonal slab system.
// Derived directly from the Phase 9.5 7-strip composition by:
//   1. Negating all X positions (mirrors the composition left↔right)
//   2. Flipping rotation sign (+PI/4 → -PI/4)
//   3. Removing slab-6 (exit accent — least visible, <5% of visible area)
//   4. Updating phase offsets from SEVENTH → SIXTH intervals
//
// All Y positions, Z depths, scale values, emission, color intensity,
// light intensity, sweep speeds, and all other properties are unchanged.
//
// VIEWPORT BEHAVIOUR (Y extents identical to Phase 9.5)
//   slab-0  Y:[−0.57, +6.27]  crops TOP  +2.54u  — entry from upper-right
//   slab-1  Y:[−2.17, +5.41]  crops TOP  +1.68u  — upper band
//   slab-2  Y:[−3.67, +4.71]  crops TOP  +0.98u  — HERO, foreground
//   slab-3  Y:[−4.35, +3.07]  crops BOT  −0.62u  — mid companion
//   slab-4  Y:[−5.00, +1.54]  crops BOT  −1.27u  — lower-mid, receding
//   slab-5  Y:[−5.51, +0.15]  crops BOT  −1.78u  — lower exit band
// =============================================================================
export function buildHeroComposition() {
    const BASE_SPEED = 0.18;
    const CYCLE      = 1.0 / BASE_SPEED;   // ≈ 5.56 s
    const SIXTH      = CYCLE / 6;           // ≈ 0.93 s — one sixth of cycle

    const ROT = -Math.PI / 4;   // -45° — strips lean \\

    const PANELS = [

        // ── slab-0: Entry band ───────────────────────────────────────────────
        // World: 8.8 × 0.86.  Crops top +2.54u.
        // X mirrored from Phase 9.5: -1.71 → +1.71
        // Enters from upper-right. Creates the dark upper-right triangle
        // that anchors the entry corner of the composition.
        {
            id:               'panel-slab-0',
            position:         { x:  1.71, y:  2.85, z: -0.08 },
            scale:            { x:  2.50, y:  1.05 },
            rotation:         ROT,
            phaseOffset:      0 * SIXTH,
            sweepSpeed:       BASE_SPEED * 0.982,
            emissionStrength: 1.00,
            colorIntensity:   0.38,
            lightIntensity:   0.88,
        },

        // ── slab-1: Upper band ───────────────────────────────────────────────
        // World: 9.8 × 0.92.  Crops top +1.68u.
        // X mirrored: -0.93 → +0.93
        // Second-longest strip — establishes the scale of the system.
        {
            id:               'panel-slab-1',
            position:         { x:  0.93, y:  1.62, z: -0.02 },
            scale:            { x:  2.50, y:  1.05 },
            rotation:         ROT,
            phaseOffset:      1 * SIXTH,
            sweepSpeed:       BASE_SPEED * 1.018,
            emissionStrength: 1.10,
            colorIntensity:   0.44,
            lightIntensity:   0.94,
        },

        // ── slab-2: HERO ─────────────────────────────────────────────────────
        // World: 10.8 × 1.05.  Crops top +0.98u. Spans 80% viewport width.
        // X mirrored: -0.03 → +0.03  (hero remains near-centre)
        // Dominant element — widest, thickest, highest emission.
        // Slightly in front (z=+0.10) — foreground layer.
        {
            id:               'panel-slab-2',
            position:         { x:  0.03, y:  0.52, z:  0.10 },
            scale:            { x:  2.50, y:  1.05 },
            rotation:         ROT,
            phaseOffset:      2 * SIXTH,
            sweepSpeed:       BASE_SPEED * 1.000,
            emissionStrength: 1.22,
            colorIntensity:   0.54,
            lightIntensity:   1.00,
        },

        // ── slab-3: Mid band ─────────────────────────────────────────────────
        // World: 9.6 × 0.90.  Crops bottom −0.62u.
        // X mirrored: +0.88 → -0.88
        // Strong mid companion — forms the visual spine with the hero.
        {
            id:               'panel-slab-3',
            position:         { x: -0.88, y: -0.64, z:  0.04 },
            scale:            { x:  2.50, y:  1.05 },
            rotation:         ROT,
            phaseOffset:      3 * SIXTH,
            sweepSpeed:       BASE_SPEED * 0.975,
            emissionStrength: 1.12,
            colorIntensity:   0.46,
            lightIntensity:   0.96,
        },

        // ── slab-4: Lower-mid band ───────────────────────────────────────────
        // World: 8.4 × 0.84.  Crops bottom −1.27u.
        // X mirrored: +1.66 → -1.66
        // Over a third below the viewport. Reinforces the downward exit.
        {
            id:               'panel-slab-4',
            position:         { x: -1.66, y: -1.73, z: -0.06 },
            scale:            { x:  2.50, y:  1.05 },
            rotation:         ROT,
            phaseOffset:      4 * SIXTH,
            sweepSpeed:       BASE_SPEED * 1.024,
            emissionStrength: 1.05,
            colorIntensity:   0.42,
            lightIntensity:   0.92,
        },

        // ── slab-5: Lower band ───────────────────────────────────────────────
        // World: 7.2 × 0.80.  Crops bottom −1.78u.
        // X mirrored: +2.43 → -2.43
        // Only a thin slice visible at top. Confirms the system exits below-left.
        // Deepest back (z=−0.14).
        {
            id:               'panel-slab-5',
            position:         { x: -2.43, y: -2.68, z: -0.14 },
            scale:            { x:  2.50, y:  1.05 },
            rotation:         ROT,
            phaseOffset:      5 * SIXTH,
            sweepSpeed:       BASE_SPEED * 0.978,
            emissionStrength: 0.96,
            colorIntensity:   0.38,
            lightIntensity:   0.86,
        },

    ];

    return PANELS.map(cfg => createStrip(cfg));
}
