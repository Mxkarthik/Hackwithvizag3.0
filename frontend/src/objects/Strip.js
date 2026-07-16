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
// buildHeroComposition()  — Phase 9.5 final reference-matched composition
// =============================================================================
//
// COMPOSITION MODEL
// -----------------
// 7 strips forming a dense diagonal slab system at +Math.PI/4 rotation.
// Strips lean like / (top-left to bottom-right).
//
// Positions and sizes derived directly from pixel-accurate measurement of
// the reference image, converted to world-space coordinates at camera z=9.
//
// SYSTEM PROPERTIES
// -----------------
// Strip thickness (scaleY): 0.76–1.05 world units  (~1/8 of viewport height)
// Strip length   (scaleX): 1.50–2.70 → world 6.0–10.8 units
// Pitch between centres:   ~1.10–1.25 world units
// Horizontal coverage:     ~80% of 13.25-unit viewport width
// Vertical coverage:       all 7 strips span from +6.27 to −5.80 world units
//
// CROPPING INTENT
// ---------------
// Every strip crops at least one viewport edge.
// Upper strips (0–2) crop the top. Lower strips (3–6) crop the bottom.
// The composition reads as a window into a much larger layered structure.
//
// HIERARCHY
// ---------
//   slab-2  HERO       — widest (10.8), thickest (1.05), max emission
//   slab-1  UPPER      — second longest (9.8), strong secondary
//   slab-3  MID        — nearly hero width (9.6), anchors lower half
//   slab-0  ENTRY      — long (8.8) but mostly above viewport
//   slab-4  LOWER-MID  — receding (8.4), exits bottom
//   slab-5  LOWER      — dimmer (7.2), mostly below frame
//   slab-6  ACCENT     — smallest (6.0), barely visible — exit strip
//
// DEPTH LAYERING (z values, depthWrite:false — scene add order matters)
//   +0.10  slab-2 hero         → foreground
//   +0.04  slab-3 mid          → near-foreground
//   +0.02  slab-6 accent       → mid
//   +0.00  slab-?              → mid
//   −0.02  slab-1 upper        → mid-back
//   −0.06  slab-4 lower-mid    → back
//   −0.08  slab-0 entry        → back
//   −0.14  slab-5 lower        → deepest back
//
// TIMING
//   Base sweep speed: 0.18 cycles/s (≈ 5.56 s per pass)
//   7 phase offsets at SEVENTH intervals — evenly staggered at t=0
//   Per-strip speed variation ±2–3% causes natural drift over time
// =============================================================================
export function buildHeroComposition() {
    const BASE_SPEED = 0.18;
    const CYCLE      = 1.0 / BASE_SPEED;     // ≈ 5.56 s
    const SEVENTH    = CYCLE / 7;             // ≈ 0.79 s — one seventh of cycle

    const ROT = Math.PI / 4;   // +45° — strips lean /

    // -------------------------------------------------------------------------
    // PANELS — every value individually designed to match the reference.
    // Positions derived from reference pixel measurements at camera z=9.
    // -------------------------------------------------------------------------
    const PANELS = [

        // ── slab-0: Entry band ───────────────────────────────────────────────
        // World: 8.8 × 0.86.  Projected half-span ≈ 3.42.
        // Y range: [−0.57, +6.27] → crops top by +2.54 units.
        // Only the lower half is visible. Creates the dark upper-left triangle
        // that is the viewer's entry point into the composition.
        // Dimmer emission — it is partially behind the frame.
        {
            id:               'panel-slab-0',
            position:         { x: -1.71, y:  2.85, z: -0.08 },
            scale:            { x:  2.20, y:  0.86 },
            rotation:         ROT,
            phaseOffset:      0 * SEVENTH,
            sweepSpeed:       BASE_SPEED * 0.982,
            emissionStrength: 1.00,
            colorIntensity:   0.38,
            lightIntensity:   0.88,
        },

        // ── slab-1: Upper band ───────────────────────────────────────────────
        // World: 9.8 × 0.92.  Projected half-span ≈ 3.79.
        // Y range: [−2.17, +5.41] → crops top by +1.68 units.
        // Second-longest strip. First band the eye resolves as nearly-complete.
        // Establishes the scale of the system before the hero reveals itself.
        {
            id:               'panel-slab-1',
            position:         { x: -0.93, y:  1.62, z: -0.02 },
            scale:            { x:  2.45, y:  0.92 },
            rotation:         ROT,
            phaseOffset:      1 * SEVENTH,
            sweepSpeed:       BASE_SPEED * 1.018,
            emissionStrength: 1.10,
            colorIntensity:   0.44,
            lightIntensity:   0.94,
        },

        // ── slab-2: HERO ─────────────────────────────────────────────────────
        // World: 10.8 × 1.05.  Projected half-span ≈ 4.19.
        // Y range: [−3.67, +4.71] → crops top +0.98.
        // X range: [−4.22, +4.16] → spans 80% of viewport width.
        // THE dominant element. Widest, thickest, highest emission.
        // Centre near screen midpoint, slightly above horizontal axis.
        // Slightly in front (z=+0.10) — foreground layer.
        // The light sweep is most visible and prominent on this strip.
        {
            id:               'panel-slab-2',
            position:         { x: -0.03, y:  0.52, z:  0.10 },
            scale:            { x:  2.70, y:  1.05 },
            rotation:         ROT,
            phaseOffset:      2 * SEVENTH,
            sweepSpeed:       BASE_SPEED * 1.000,
            emissionStrength: 1.22,
            colorIntensity:   0.54,
            lightIntensity:   1.00,
        },

        // ── slab-3: Mid band ─────────────────────────────────────────────────
        // World: 9.6 × 0.90.  Projected half-span ≈ 3.71.
        // Y range: [−4.35, +3.07] → crops bottom by −0.62 units.
        // Nearly hero-width at 9.6 units — reads as a strong companion.
        // Together with the hero, this strip forms the visual spine.
        // Slightly forward (z=+0.04).
        {
            id:               'panel-slab-3',
            position:         { x:  0.88, y: -0.64, z:  0.04 },
            scale:            { x:  2.40, y:  0.90 },
            rotation:         ROT,
            phaseOffset:      3 * SEVENTH,
            sweepSpeed:       BASE_SPEED * 0.975,
            emissionStrength: 1.12,
            colorIntensity:   0.46,
            lightIntensity:   0.96,
        },

        // ── slab-4: Lower-mid band ───────────────────────────────────────────
        // World: 8.4 × 0.84.  Projected half-span ≈ 3.27.
        // Y range: [−5.00, +1.54] → crops bottom by −1.27 units.
        // Over a third of this strip is below the viewport.
        // Reinforces the downward exit of the composition.
        // Behind (z=−0.06).
        {
            id:               'panel-slab-4',
            position:         { x:  1.66, y: -1.73, z: -0.06 },
            scale:            { x:  2.10, y:  0.84 },
            rotation:         ROT,
            phaseOffset:      4 * SEVENTH,
            sweepSpeed:       BASE_SPEED * 1.024,
            emissionStrength: 1.05,
            colorIntensity:   0.42,
            lightIntensity:   0.92,
        },

        // ── slab-5: Lower band ───────────────────────────────────────────────
        // World: 7.2 × 0.80.  Projected half-span ≈ 2.83.
        // Y range: [−5.51, +0.15] → crops bottom by −1.78 units.
        // Only a thin slice of this strip's upper edge is visible.
        // Confirms the system continues below the frame.
        // Deepest back (z=−0.14) — intentionally recedes.
        {
            id:               'panel-slab-5',
            position:         { x:  2.43, y: -2.68, z: -0.14 },
            scale:            { x:  1.80, y:  0.80 },
            rotation:         ROT,
            phaseOffset:      5 * SEVENTH,
            sweepSpeed:       BASE_SPEED * 0.978,
            emissionStrength: 0.96,
            colorIntensity:   0.38,
            lightIntensity:   0.86,
        },

        // ── slab-6: Exit accent ──────────────────────────────────────────────
        // World: 6.0 × 0.76.  Projected half-span ≈ 2.39.
        // Y range: [−5.80, −1.02] → entirely below −1.02 world units.
        //   Crops bottom by −2.07 units. Only the very top sliver is visible.
        // This strip is barely perceptible — it is the final confirmation
        // that the slab system extends far beyond the bottom-right corner.
        // Minimal emission — it should barely register.
        {
            id:               'panel-slab-6',
            position:         { x:  3.08, y: -3.41, z:  0.02 },
            scale:            { x:  1.50, y:  0.76 },
            rotation:         ROT,
            phaseOffset:      6 * SEVENTH,
            sweepSpeed:       BASE_SPEED * 1.012,
            emissionStrength: 0.88,
            colorIntensity:   0.32,
            lightIntensity:   0.80,
        },

    ];

    return PANELS.map(cfg => createStrip(cfg));
}
