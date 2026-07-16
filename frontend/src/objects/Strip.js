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
// All six strip meshes reference this single geometry object.
// The GPU receives one VBO upload regardless of instance count.
// =============================================================================
const SHARED_GEOMETRY = new THREE.PlaneGeometry(4, 1);

// Shader sources are imported as strings by vite-plugin-glsl.
// Three.js WebGLPrograms caches compiled programs keyed on the source strings.
// All six ShaderMaterial instances share one compiled GPU program.
const VERTEX_SHADER   = vertexShader;
const FRAGMENT_SHADER = fragmentShader;

// =============================================================================
// DEFAULT CONFIG
// =============================================================================
// All createStrip() parameters are optional — defaults are applied here.
// Values match the Phase 6.5 tuned baseline.
// =============================================================================
const DEFAULTS = {
    id:               "strip",
    position:         new THREE.Vector3(0, 0, 0),
    rotation:         Math.PI / 4,
    phaseOffset:      0.0,           // seconds — shifts sweep start time
    sweepSpeed:       0.18,          // cycles / second
    sweepMin:        -0.2,           // UV X entry (slightly past left edge)
    sweepMax:         1.2,           // UV X exit  (slightly past right edge)
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
// The caller is responsible for:
//   1. Adding instance.mesh to the scene.
//   2. Calling instance.update(t) every frame with wall-clock seconds.
//
// SHADER FILES ARE NOT MODIFIED — this factory is purely JS architecture.
// =============================================================================
export function createStrip(config = {}) {
    // -------------------------------------------------------------------------
    // Merge config with defaults
    // -------------------------------------------------------------------------
    const cfg = {
        id:               config.id               ?? DEFAULTS.id,
        position:         config.position         ?? DEFAULTS.position,
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
    // Per-instance uniforms
    // -------------------------------------------------------------------------
    // Each strip owns a completely independent uniforms object.
    // Mutating one strip's uniforms has zero effect on any other strip.
    // -------------------------------------------------------------------------
    const uniforms = {
        uTime:            { value: 0 },
        uBaseColor:       { value: new THREE.Color(0.052, 0.052, 0.052) },
        uLightColor:      { value: new THREE.Color("#EC044F") },
        uLightPosition:   { value: cfg.sweepMin },
        uLightWidth:      { value: 0.05 },
        uLightIntensity:  { value: cfg.lightIntensity },
        uColorIntensity:  { value: cfg.colorIntensity },
        uEmissionStrength:{ value: cfg.emissionStrength },
        uEnableEmission:  { value: 1.0 },
        uMetalStrength:   { value: 1.0 },
        uNoiseStrength:   { value: 0.4 },
    };

    // -------------------------------------------------------------------------
    // Material — references SHARED shader sources, owns independent uniforms
    // -------------------------------------------------------------------------
    const material = new THREE.ShaderMaterial({
        vertexShader:   VERTEX_SHADER,
        fragmentShader: FRAGMENT_SHADER,
        uniforms,
        transparent: true,
        depthWrite:  false,
    });

    // -------------------------------------------------------------------------
    // Mesh — references SHARED_GEOMETRY
    // -------------------------------------------------------------------------
    const mesh = new THREE.Mesh(SHARED_GEOMETRY, material);
    mesh.position.copy(cfg.position);
    mesh.rotation.z = cfg.rotation;
    mesh.name = cfg.id;   // useful for scene inspection / debugging

    // -------------------------------------------------------------------------
    // Animation state (private to this instance)
    // -------------------------------------------------------------------------
    // sweepSpeed is mutable — setLightSpeed() can change it after construction.
    let currentSweepSpeed = cfg.sweepSpeed;

    // -------------------------------------------------------------------------
    // StripInstance public API
    // -------------------------------------------------------------------------

    /**
     * update(t)
     * Call every frame with wall-clock time in seconds.
     * Computes uLightPosition from the phase-offset sawtooth and uploads
     * uTime and uLightPosition to this strip's uniforms.
     * No other code should write to this strip's uniforms each frame.
     */
    function update(t) {
        // Apply phaseOffset to produce an independent starting phase.
        // Adding a constant time offset shifts the sweep's starting position
        // without affecting the sweep speed or loop period.
        const localT  = t + cfg.phaseOffset;
        const sweep   = (localT * currentSweepSpeed) % 1.0;  // [0, 1) sawtooth

        uniforms.uTime.value          = t;
        uniforms.uLightPosition.value = cfg.sweepMin + sweep * (cfg.sweepMax - cfg.sweepMin);
    }

    /**
     * setLightColor(color)
     * Accepts a THREE.Color, a hex string, or a hex number.
     * Updates this strip's uLightColor uniform immediately.
     */
    function setLightColor(color) {
        if (color instanceof THREE.Color) {
            uniforms.uLightColor.value.copy(color);
        } else {
            uniforms.uLightColor.value.set(color);
        }
    }

    /**
     * setEmission(value)
     * Sets uEmissionStrength — controls HDR headroom fed to UnrealBloomPass.
     * Range: 0.0 (no emission, bloom-free) → 2.0+ (strong HDR bloom).
     */
    function setEmission(value) {
        uniforms.uEmissionStrength.value = value;
    }

    /**
     * setColorIntensity(value)
     * Sets uColorIntensity — controls the strength of the brand color fringe.
     * Range: 0.0 (white only) → 1.0 (full color fringe).
     */
    function setColorIntensity(value) {
        uniforms.uColorIntensity.value = value;
    }

    /**
     * setLightSpeed(value)
     * Changes the sweep speed in cycles/second at runtime.
     * Deterministic — the new speed takes effect on the next update() call.
     */
    function setLightSpeed(value) {
        currentSweepSpeed = value;
    }

    // Return the public StripInstance interface
    return {
        id:               cfg.id,
        mesh,
        update,
        setLightColor,
        setEmission,
        setColorIntensity,
        setLightSpeed,
    };
}

// =============================================================================
// buildStripSystem()
// =============================================================================
// Convenience factory that creates six strip instances arranged in a 2×3
// debug grid for visual inspection.
//
// Layout (world space, camera at z=8):
//
//   Strip 0 (top-left)      Strip 1 (top-right)
//   Strip 2 (mid-left)      Strip 3 (mid-right)
//   Strip 4 (bot-left)      Strip 5 (bot-right)
//
// Phase offsets are evenly distributed across one full cycle period so no
// two strips have their light at the same position at any given moment.
// =============================================================================
export function buildStripSystem() {
    const STRIP_COUNT  = 6;
    const SWEEP_SPEED  = 0.18;                      // cycles / second
    const CYCLE_PERIOD = 1.0 / SWEEP_SPEED;         // ≈ 5.56 seconds
    const PHASE_STEP   = CYCLE_PERIOD / STRIP_COUNT; // evenly-spaced offsets

    // 2×3 grid layout
    // Columns: left x = -2.6,  right x = +2.6
    // Rows (top → bottom): y = +2.4, 0.0, -2.4
    const GRID = [
        { col: 0, row: 0 },  // Strip 0 — top-left
        { col: 1, row: 0 },  // Strip 1 — top-right
        { col: 0, row: 1 },  // Strip 2 — mid-left
        { col: 1, row: 1 },  // Strip 3 — mid-right
        { col: 0, row: 2 },  // Strip 4 — bot-left
        { col: 1, row: 2 },  // Strip 5 — bot-right
    ];

    const COL_X = [-2.6, 2.6];   // X position per column
    const ROW_Y = [ 2.4, 0.0, -2.4];   // Y position per row

    // Vary emissionStrength and colorIntensity slightly across strips to
    // visually confirm the per-instance uniform system is working.
    // These are debug-layout values — Phase 8 will use final composition values.
    const PER_STRIP_OVERRIDES = [
        { emissionStrength: 1.1, colorIntensity: 0.45 },
        { emissionStrength: 1.1, colorIntensity: 0.45 },
        { emissionStrength: 1.1, colorIntensity: 0.45 },
        { emissionStrength: 1.1, colorIntensity: 0.45 },
        { emissionStrength: 1.1, colorIntensity: 0.45 },
        { emissionStrength: 1.1, colorIntensity: 0.45 },
    ];

    const strips = [];

    for (let i = 0; i < STRIP_COUNT; i++) {
        const { col, row } = GRID[i];
        const overrides    = PER_STRIP_OVERRIDES[i];

        strips.push(createStrip({
            id:               `strip-${i}`,
            position:         new THREE.Vector3(COL_X[col], ROW_Y[row], 0),
            rotation:         Math.PI / 4,
            phaseOffset:      i * PHASE_STEP,        // deterministic, evenly-spaced
            sweepSpeed:       SWEEP_SPEED,
            emissionStrength: overrides.emissionStrength,
            colorIntensity:   overrides.colorIntensity,
        }));
    }

    return strips;
}
