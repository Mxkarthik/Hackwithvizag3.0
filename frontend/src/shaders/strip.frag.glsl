varying vec2 vUv;

// Future-compatible uniforms for the next phases
uniform float uTime;
uniform vec3 uBaseColor;
uniform vec3 uLightColor;
uniform float uLightPosition;
uniform float uLightWidth;
uniform float uMetalStrength;
uniform float uNoiseStrength;

// =============================================================================
// HELPER: getSurfaceVariation
// =============================================================================
// Generates a deterministic procedural surface variation value in [0, 1].
// This simulates a microscopic roughness map for anisotropic brushed metal.
//
// Pipeline:
//   1. hash2() — deterministic 2D → float hash via dot-product scrambling.
//      Produces a unique pseudo-random value for each integer lattice cell.
//
//   2. Hermite interpolation (smoothstep curve: 3t² - 2t³) applied to the
//      fractional position within each cell. This removes the visible grid
//      discontinuity that plain linear interpolation would produce.
//
//   3. Value Noise via bilinear interpolation of the four surrounding
//      lattice corner hashes, blended with the Hermite weights.
//      Value Noise is chosen over Perlin/Simplex because:
//        • It is cheaper (no gradient table needed).
//        • Its output is purely scalar, matching a roughness map convention.
//        • The result is smooth, band-limited, and artifact-free.
//
//   4. Anisotropic UV stretch: uv * vec2(8.0, 64.0) makes the noise cells
//      narrow horizontally and long vertically, replicating the directional
//      grain pattern of machined brushed metal.
// =============================================================================

// Deterministic 2D hash: maps a vec2 lattice coordinate to a float in [0, 1].
// The magic constants are chosen to break spatial coherence without trig calls.
float hash2(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

// Value Noise with Hermite interpolation over a stretched anisotropic UV space.
float getSurfaceVariation(vec2 uv) {
    // Anisotropic stretch: narrow horizontal cells, long vertical cells.
    // Simulates the directional micro-grain of brushed / machined metal.
    const vec2 ANISO_SCALE = vec2(8.0, 64.0);
    vec2 st = uv * ANISO_SCALE;

    // Separate integer cell coordinate from fractional position within cell.
    vec2 i = floor(st);
    vec2 f = fract(st);

    // Hermite smoothing curve (smoothstep: 3t² - 2t³).
    // Removes C0 discontinuities at cell boundaries that bilinear alone produces.
    vec2 u = f * f * (3.0 - 2.0 * f);

    // Sample the four surrounding lattice corners.
    float a = hash2(i + vec2(0.0, 0.0));
    float b = hash2(i + vec2(1.0, 0.0));
    float c = hash2(i + vec2(0.0, 1.0));
    float d = hash2(i + vec2(1.0, 1.0));

    // Bilinear interpolation using the Hermite weights.
    // mix(a, b, u.x) interpolates along X, then the two results are
    // interpolated along Y — standard 2D bilinear on a unit cell.
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void main() {
    // -----------------------------------------------------------------
    // LAYER 1: Dark Base Color
    // -----------------------------------------------------------------
    // We use the uBaseColor uniform which is configured at vec3(0.052)
    // to provide a premium, almost-black base that remains within
    // the target range of 0.045 to 0.060.
    vec3 baseColor = uBaseColor;

    // -----------------------------------------------------------------
    // LAYER 2: Vertical Depth
    // -----------------------------------------------------------------
    // A very subtle vertical gradient to create three-dimensional depth.
    // We smoothly interpolate (mix) from bottom to top using vUv.y.
    // The top is only slightly brighter than the bottom (max addition of 0.006).
    float verticalGradientFactor = vUv.y;
    vec3 bottomOffset = vec3(0.0);
    vec3 topOffset = vec3(0.006);
    vec3 verticalDepth = mix(bottomOffset, topOffset, verticalGradientFactor);

    // -----------------------------------------------------------------
    // LAYER 3: Gaussian Metallic Reflection
    // -----------------------------------------------------------------
    // Simulates a soft, cylindrical metallic reflection.
    // We use a Gaussian-style bell curve: exp(-k * x^2) centered at vUv.x = 0.5.
    // High k value (12.0) defines a diffused metallic reflection band in the center.
    // We scale it down to 0.015 to prevent sharp reflections and keep it soft.
    float distFromCenter = vUv.x - 0.5;
    float k = 12.0;
    float gaussianReflection = exp(-k * distFromCenter * distFromCenter);
    vec3 metallicReflection = vec3(gaussianReflection * 0.015 * uMetalStrength);

    // -----------------------------------------------------------------
    // LAYER 4: Edge Falloff
    // -----------------------------------------------------------------
    // To remove the flat, uniform appearance of a 2D rectangle, we darken
    // the left and right edges.
    // We use smoothstep to smoothly fade out the edges near x=0.0 and x=1.0.
    float leftEdge = smoothstep(0.0, 0.15, vUv.x);
    float rightEdge = smoothstep(1.0, 0.85, vUv.x);
    float edgeFalloff = leftEdge * rightEdge;

    // -----------------------------------------------------------------
    // LAYER 5: Soft Tonal Adjustment
    // -----------------------------------------------------------------
    // We combine the base color, vertical depth, and metallic reflection,
    // and then apply the edge falloff.
    vec3 blendedColor = baseColor + verticalDepth + metallicReflection;
    vec3 finalColor = blendedColor * edgeFalloff;

    // -----------------------------------------------------------------
    // LAYER 6: Procedural Surface Variation  (Phase 3 — data only)
    // -----------------------------------------------------------------
    // Generates a scalar roughness-like value derived from Value Noise
    // over an anisotropic UV space that mimics brushed-metal micro-grain.
    //
    // uNoiseStrength scales the raw noise output so the intensity can be
    // tuned from JS without touching the shader.
    //
    // IMPORTANT: surfaceVariation is intentionally NOT applied to any
    // visual output here. It is computed and held in a local variable,
    // ready to be consumed by the moving-light calculations in Phase 4.
    // Modifying color, brightness, reflection, or gradients with it now
    // would contaminate Phase 4's physically-correct light interaction.
    float surfaceVariation = getSurfaceVariation(vUv) * uNoiseStrength;

    // Clamp the final color to prevent any clipping/harsh highlights and keep it premium.
    gl_FragColor = vec4(clamp(finalColor, 0.0, 1.0), 1.0);
}
