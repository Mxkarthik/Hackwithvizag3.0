varying vec2 vUv;

// Future-compatible uniforms for the next phases
uniform float uTime;
uniform vec3 uBaseColor;
uniform vec3 uLightColor;       // Brand color applied as the wider colored fringe (Phase 5)
uniform float uLightPosition;   // Owned and animated by JavaScript — do NOT derive in shader
uniform float uLightWidth;      // Standard deviation (σ) of the horizontal Gaussian lobe
uniform float uLightIntensity;  // Peak brightness of the white lobe
uniform float uColorIntensity;  // Relative strength of the colored lobe vs. the white lobe
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
    // surfaceVariation is consumed by Layer 7 to modulate the light sweep.
    float surfaceVariation = getSurfaceVariation(vUv) * uNoiseStrength;

    // -----------------------------------------------------------------
    // LAYER 7: Procedural Light Sweep  (Phase 4)
    // -----------------------------------------------------------------
    // A physically-inspired Gaussian illumination mask that moves across
    // the strip. The sweep position is entirely owned by JavaScript —
    // uLightPosition is computed and uploaded every frame from main.js.
    // The shader is responsible only for rendering the mask.
    //
    // Structure:
    //   A. Horizontal Gaussian — the core specular lobe shape.
    //   B. Vertical Gaussian  — simulates light wrapping over strip curvature.
    //   C. Roughness modulation — surfaceVariation attenuates the lobe
    //      where micro-facets scatter the light (high roughness = lower peak).
    //   D. Additive composite — light is added on top of finalColor so it
    //      is not double-attenuated by the edge falloff applied in Layer 5.

    // Named constants — no magic numbers.
    // σ for the horizontal lobe is uLightWidth (tunable uniform).
    // σ for the vertical attenuation is fixed; describes strip curvature.
    const float VERTICAL_SIGMA        = 0.35;  // vertical Gaussian std-deviation
    const float ROUGHNESS_MODULATION  = 0.30;  // max fractional attenuation from roughness

    // A. Horizontal Gaussian lobe
    //    exp( -x² / 2σ² )  evaluated at the signed distance from the light centre.
    float hDist       = vUv.x - uLightPosition;
    float hVariance   = 2.0 * uLightWidth * uLightWidth;    // 2σ²
    float hGaussian   = exp(-(hDist * hDist) / hVariance);

    // B. Vertical Gaussian attenuation
    //    Centred at vUv.y = 0.5 (mid-height of the strip).
    //    Makes the highlight brightest at the centre and subtly dimmer at
    //    the top/bottom edges, approximating light wrap on a curved surface.
    float vDist       = vUv.y - 0.5;
    float vVariance   = 2.0 * VERTICAL_SIGMA * VERTICAL_SIGMA;  // 2σ²
    float vGaussian   = exp(-(vDist * vDist) / vVariance);

    // C. Roughness modulation
    //    surfaceVariation ∈ [0, uNoiseStrength]. High roughness scatters
    //    incoming light, reducing the apparent specular peak at that point.
    float roughnessMod = 1.0 - surfaceVariation * ROUGHNESS_MODULATION;

    // D. Composite light contribution
    //    uLightIntensity controls peak brightness — kept as a uniform so
    //    Phase 5 can animate it (fade in/out, pulse, etc.) from JavaScript.
    //    Light color is vec3(1.0) (white) — the white energy source.
    //    The colored fringe is added in Layer 8.
    float lightMask         = hGaussian * vGaussian * roughnessMod;
    vec3  lightContribution = vec3(lightMask) * uLightIntensity;

    // Add the white light on top of the fully composited base material.
    finalColor += lightContribution;

    // -----------------------------------------------------------------
    // LAYER 8: Colored Illumination  (Phase 5)
    // -----------------------------------------------------------------
    // A second, wider Gaussian lobe at the same position as the white
    // lobe. Because it is broader, it dominates at the edges of the
    // highlight while the narrow white lobe dominates at the centre.
    //
    // Result: white core → brand color fringe, with no manual transitions.
    // The effect emerges purely from the two-lobe width difference.
    //
    // Shares uLightPosition, vGaussian, roughnessMod, and hDist with
    // Layer 7 — no redundant calculations.
    //
    // COLOR_SPREAD_FACTOR defines how much wider the colored lobe is
    // relative to the white lobe (σ_color = uLightWidth × COLOR_SPREAD_FACTOR).

    const float COLOR_SPREAD_FACTOR = 2.5;  // colored lobe is 2.5× wider than white

    // Wider horizontal Gaussian using the same centre (hDist) already computed above.
    float hSigmaColor    = uLightWidth * COLOR_SPREAD_FACTOR;
    float hVarianceColor = 2.0 * hSigmaColor * hSigmaColor;         // 2σ²
    float hGaussianColor = exp(-(hDist * hDist) / hVarianceColor);

    // Reuse vGaussian and roughnessMod from Layer 7 — same physics apply.
    float colorMask         = hGaussianColor * vGaussian * roughnessMod;
    vec3  colorContribution = uLightColor * colorMask * uColorIntensity;

    // Additive composite — color adds energy on top of the white lobe.
    // At the peak both lobes sum toward white (clamped).
    // Away from the peak the white has decayed and the brand color dominates.
    finalColor += colorContribution;

    // Clamp the final color to prevent any clipping/harsh highlights and keep it premium.
    gl_FragColor = vec4(clamp(finalColor, 0.0, 1.0), 1.0);
}
