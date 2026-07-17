varying vec2 vUv;

// =============================================================================
// UV ORIENTATION NOTE
// =============================================================================
// PlaneGeometry(width=4, height=1) maps:
//   U (vUv.x)  →  strip long axis   (width  = 4 units)
//   V (vUv.y)  →  strip short axis  (height = 1 unit)
//
// All anisotropic effects (grain, specular streaks, reflections) are
// elongated along U and compressed along V.
// =============================================================================

// Uniforms
uniform float uTime;
uniform vec3  uBaseColor;
uniform vec3  uLightColor;        // Brand color — primary lobe only (Phase 5)
uniform float uLightPosition;     // Owned and animated by JavaScript
uniform float uLightWidth;        // σ_U of the primary horizontal Gaussian lobe
uniform float uLightIntensity;    // Peak brightness of the primary white lobe
uniform float uColorIntensity;    // Strength of the brand-color fringe
uniform float uEmissionStrength;  // HDR multiplier for light layers
uniform float uEnableEmission;    // Debug toggle: 1.0 = HDR, 0.0 = LDR clamp
uniform float uMetalStrength;
uniform float uNoiseStrength;
uniform float uSecondaryReflection;

// =============================================================================
// HELPER: hash2
// =============================================================================
// Deterministic 2D → float hash. No trig, pure ALU.
// =============================================================================
float hash2(vec2 p) {
    p  = fract(p * vec2(127.1, 311.7));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

// =============================================================================
// HELPER: valueNoise
// =============================================================================
// Single-octave Value Noise with Hermite (C1) interpolation.
// Returns [0, 1].
// =============================================================================
float valueNoise(vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);
    vec2 u = f * f * (3.0 - 2.0 * f);   // smoothstep: 3t² − 2t³

    float a = hash2(i + vec2(0.0, 0.0));
    float b = hash2(i + vec2(1.0, 0.0));
    float c = hash2(i + vec2(0.0, 1.0));
    float d = hash2(i + vec2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// =============================================================================
// HELPER: getSurfaceVariation  (Phase 7.5 — three-octave anisotropic noise)
// =============================================================================
// Generates a procedural roughness scalar in [0, 1].
// Simulates the microscopic surface structure of brushed / anodized aluminium.
//
// UV orientation: U = long axis, V = short axis.
// Grain runs along U — many fine cells along U, tall strands along V.
//
// Three octaves:
//   Octave 1 — vec2(128, 32)   structural layer,  weight 0.65
//   Octave 2 — vec2(256, 64)   fine detail,        weight 0.25
//   Octave 3 — vec2(512,  8)   micro-facet layer,  weight 0.10
//              Very high U frequency, nearly 1D along U.
//              Simulates individual scratch facets on the metal surface.
//
// Output sharpening:
//   The weighted sum produces a mid-range scalar [0,1].
//   A centre-biased power remap pushes values toward extremes:
//     centered  = noise − 0.5
//     sharpened = centered² × sign(centered) × 4.0
//     output    = clamp(0.5 + sharpened, 0.0, 1.0)
//   This creates occasional micro-spikes above the average without
//   introducing uniform grain. The result resembles fine scratch facets
//   that catch light only at certain angles.
// =============================================================================
float getSurfaceVariation(vec2 uv) {
    const vec2 ANISO_SCALE_1 = vec2(128.0,  32.0);  // structural
    const vec2 ANISO_SCALE_2 = vec2(256.0,  64.0);  // fine detail
    const vec2 ANISO_SCALE_3 = vec2(512.0,   8.0);  // micro-facet (near-1D along U)

    float o1 = valueNoise(uv * ANISO_SCALE_1);
    float o2 = valueNoise(uv * ANISO_SCALE_2);
    float o3 = valueNoise(uv * ANISO_SCALE_3);

    // Weighted sum — structural layer dominates, micro-facet adds sharp detail.
    float raw = o1 * 0.65 + o2 * 0.25 + o3 * 0.10;

    // Centre-biased sharpening remap.
    // Pushes values away from 0.5 toward local extremes.
    // sign() preserves which side of the centre each value is on.
    float centered  = raw - 0.5;
    float sharpened = centered * centered * sign(centered) * 4.0;
    return clamp(0.5 + sharpened, 0.0, 1.0);
}

void main() {

    // =========================================================================
    // LAYER 1: Dark Base Color
    // =========================================================================
    // vec3(0.052) — premium almost-black within [0.045, 0.060].
    vec3 baseColor = uBaseColor;

    // =========================================================================
    // LAYER 2: Vertical Depth  (Phase 7.5 — conservatively increased)
    // =========================================================================
    // Subtle V-axis gradient adds three-dimensional depth.
    // Increased from 0.006 → 0.011 — strip still nearly disappears unlit.
    float verticalGradientFactor = vUv.y;
    vec3 verticalDepth = vec3(0.0);

    // =========================================================================
    // LAYER 3: Anisotropic Static Metallic Reflection  (Phase 7.5 refined)
    // =========================================================================
    // 2D anisotropic Gaussian: wide along U (grain), tight along V (cross-grain).
    // Produces a thin ambient streak at V=0.5 spanning most of the strip length.
    //
    // Phase 7.5 addition: surfaceVariation micro-breakup is applied to the
    // static reflection so the ambient streak is not perfectly smooth —
    // it has the same micro-facet character as the rest of the surface.
    // Breakup amplitude is very low (0.25 modulation) to keep it subliminal.

    const float STATIC_SIGMA_U  = 0.42;  // broad low-level ambient glass field
    const float STATIC_SIGMA_V  = 0.36;  // reaches across the glass without lighting its edges
    const float STATIC_PEAK     = 0.0;   // unlit glass matches the black background
    const float STATIC_BREAKUP  = 0.35;

    float staticDistU  = vUv.x - 0.5;
    float staticDistV  = vUv.y - 0.5;
    float staticGaussU = exp(-(staticDistU * staticDistU) / (2.0 * STATIC_SIGMA_U * STATIC_SIGMA_U));
    float staticGaussV = exp(-(staticDistV * staticDistV) / (2.0 * STATIC_SIGMA_V * STATIC_SIGMA_V));

    // Surface variation will be computed in Layer 6 — forward-declare to allow
    // Layer 3 to use it. GLSL evaluates in source order, so we call
    // getSurfaceVariation() here directly (it has no dependency on later layers).
    float surfaceVariation  = getSurfaceVariation(vUv) * uNoiseStrength;
    float staticBreakupMod  = 1.0 - surfaceVariation * STATIC_BREAKUP;
    // Neutral ambient reflection — no warm tint.
    // Project color identity is preserved; warmth comes from the brand accent sweep.
    float staticScalar   = staticGaussU * staticGaussV * STATIC_PEAK * uMetalStrength * staticBreakupMod;
    vec3  metallicReflection = vec3(staticScalar);

    // =========================================================================
    // LAYER 4: Edge Falloff + Edge Catch Light  (Phase 7.5 refined)
    // =========================================================================
    // A. Darkening falloff — identical to previous phases.
    //    Removes the flat rectangular appearance of the plane.
    // B. Edge catch light — additive brightening at the extreme U edges.
    //    Simulates grazing-angle ambient light revealing the strip's thickness.
    //    Kept extremely subtle (EDGE_CATCH_PEAK = 0.018) — reveals the edge
    //    without creating a glowing border.
    //    pow(…, 2.5) concentrates the catch light within ~5% of each edge.

    const float EDGE_CATCH_PEAK = 0.0;    // boundaries read exclusively from black gaps

    float leftEdge    = smoothstep(0.0,  0.15, vUv.x);
    float rightEdge   = smoothstep(1.0,  0.85, vUv.x);
    float edgeFalloff = leftEdge * rightEdge;

    float catchLeft   = pow(1.0 - smoothstep(0.0,  0.06, vUv.x), 2.5);
    float catchRight  = pow(1.0 - smoothstep(0.94, 1.0,  vUv.x), 2.5);
    // Edge catch light modulated by staticGaussV — strongest at V-centre,
    // fades toward V-extremes, simulating curvature-dependent grazing light.
    float edgeCatch   = (catchLeft + catchRight) * EDGE_CATCH_PEAK * staticGaussV;

    // =========================================================================
    // LAYER 5: Soft Tonal Adjustment  (Phase 7.5 — V-center brightness + micro-texture)
    // =========================================================================
    // Combines Layers 1–4 into baseMaterial.
    // Phase 7.5 adds two subtle enhancements:
    //
    // A. V-centre brightness boost (+4% at mid-height, 0% at edges).
    //    Makes the flat plane feel slightly convex across its short axis.
    //    Formula: 1.0 + 0.04 × (1 − 4(V−0.5)²)
    //      At V=0.5: factor = 1.04
    //      At V=0.0 or V=1.0: factor = 1.0
    //
    // B. Micro-texture from surfaceVariation ±0.003 — adds imperceptible
    //    surface character to the unlit base. The ±0.003 range is below
    //    the perceptual threshold as standalone texture but combines with
    //    the edge and gradient layers to give premium surface depth.

    float vCenterBrightness = 1.0 + 0.05 * (1.0 - 4.0 * (vUv.y - 0.5) * (vUv.y - 0.5));  // 0.07→0.05: proportionally correct at lower base

    // Phase 23 — Permanent Brand Material
    // Reuses uLightColor (#EC044F) from the existing uniform — no hardcoded color.
    // surfaceVariation is already computed — zero additional ALU.
    //
    // The three-octave noise (structural + detail + micro-facet) produces a
    // bimodal distribution after the sharpening remap: most fragments are near
    // zero (dark), occasional micro-facets spike toward 1.0 (tinted).
    // This gives the organic, fine-grain character of premium coated glass.
    //
    // Luminance variation: a second, coarser noise octave sampled at vec2(64, 16)
    // is added at low weight to create slow large-scale brightness variation within
    // the brand coating — preventing it from looking uniformly flat.
    // This second sample is deterministic and static (no uTime input).
    //
    // BRAND_NOISE_INTENSITY = 0.05 — validated as barely perceptible against black
    // while providing clear material presence on close inspection.
    // edgeFalloff ensures the tint naturally fades toward the U-axis strip boundaries.
    const float BRAND_NOISE_INTENSITY = 0.05;

    float brandGrain      = surfaceVariation;  // fine bimodal grain — already computed
    float brandField      = valueNoise(vUv * vec2(64.0, 16.0));  // coarse luminance field
    float brandNoise      = brandGrain * 0.80 + brandField * 0.20;  // organic combination

    vec3  baseMicroTexture = uLightColor * brandNoise * BRAND_NOISE_INTENSITY * edgeFalloff;

    vec3 blendedColor = baseColor + verticalDepth + metallicReflection + vec3(edgeCatch);
    vec3 baseMaterial = blendedColor * edgeFalloff * vCenterBrightness + baseMicroTexture;

    // =========================================================================
    // LAYER 6: Procedural Surface Variation  (computed above in Layer 3)
    // =========================================================================
    // surfaceVariation is already computed and available from Layer 3.
    // This section is a comment placeholder to maintain layer numbering.
    // surfaceVariation = getSurfaceVariation(vUv) * uNoiseStrength  ← done above.

    // =========================================================================
    // LAYER 7: Anisotropic Specular Sweep — Primary + Secondary + Tertiary
    //          (Phase 7.5 refined)
    // =========================================================================
    // UV orientation: U = long axis (sweep axis), V = short axis.
    //
    // Three lobes, all anchored to uLightPosition:
    //
    //   Primary   σ_U = uLightWidth         σ_V = SWEEP_SIGMA_V          intensity 1.00
    //   Secondary σ_U = uLightWidth × 1.8   σ_V = SWEEP_SIGMA_V × 0.85   intensity 0.22
    //   Tertiary  σ_U = uLightWidth × 3.0   σ_V = SWEEP_SIGMA_V × 1.20   intensity 0.07
    //
    // Offsets along U:
    //   Secondary  +SEC_OFFSET_U  = +0.04  (slightly ahead of primary)
    //   Tertiary   +TER_OFFSET_U  = -0.08  (slightly behind primary)
    //
    // All three lobes animate together — offsets are constants relative to
    // uLightPosition, so they sweep in lockstep. This is physically correct:
    // secondary/tertiary reflections are geometric consequences of the same
    // light source, not independent lights.
    //
    // Micro-shimmer:
    //   A high-frequency noise sample (512×8 scale) is used to add micro-glint
    //   variation inside the primary lobe. Only the top ~40% of noise values
    //   produce any glint (pow curve). Multiplier range [1.0, 1.25].
    //   Deterministic — no time input, no flicker.
    //
    // Roughness modulation (ROUGHNESS_MODULATION = 0.12):
    //   Applied to all three lobes identically — the surface roughness
    //   attenuates every lobe, preserving consistent material character.

    const float TRAVEL_SIGMA_U        = 0.026;  // slender profile along travel axis
    const float CROSS_PANEL_SIGMA_V   = 0.42;   // soft spread across the panel
    const float ROUGHNESS_MODULATION  = 0.10;   // micro-surface breaks up reflections
    const float PRIMARY_INTENSITY     = 0.32;   // restrained studio reflection core
    const float REFLECTION_INTENSITY  = 0.22;   // overall reflection scale
    const float PANEL_EXPOSURE        = 0.018;  // faint glass reveal around the streak

    // Feathering lobes — leading and trailing soft edges of each reflection
    const float SEC_OFFSET_U  =  0.018;
    const float TER_OFFSET_U  = -0.032;
    const float SEC_INTENSITY =  0.045;
    const float TER_INTENSITY =  0.020;

    // The band travels along the long panel axis. Reversing the increasing
    // sweep makes its screen-space motion run from the upper end to the lower.
    // Its wide cross-panel profile reproduces the reference's soft horizontal
    // reflection rather than a bright rail running along the strip.
    float vDist          = vUv.y - 0.5;
    float travelPosition = 1.0 - uLightPosition;

    // Shared roughness modulation
    float roughnessMod = 1.0 - surfaceVariation * ROUGHNESS_MODULATION;

    // =========================================================================
    // DUAL REFLECTION SYSTEM — Phase 21
    // =========================================================================
    //
    // Primary reflection:   travelPosition = 1.0 - uLightPosition  (top → bottom)
    // Counter reflection:   counterPos     = uLightPosition + PHASE_OFFSET (bottom → top)
    //
    // PHASE_OFFSET (0.14) breaks the perfect mirror symmetry. Without it the
    // two reflections would always be at exact UV complements — too mechanical.
    // With 0.14 the counter reflection arrives at the meeting point slightly
    // earlier each cycle, making each interaction feel distinct.
    //
    // INTERFERENCE MODEL
    // When the two reflections are close (separation < OVERLAP_RANGE):
    //   overlapFactor → 1.0 (smooth, continuous, no branching)
    //
    //   Both reflections widen:
    //     V-axis (across panel): up to +30% — primary breathing direction
    //     U-axis (along travel): up to +12% — subtle, gives the "soft merge" feel
    //
    //   Energy conservation: peak brightness reduced by (σ_nominal/σ_effective)²
    //   so the integrated brightness per unit area stays constant — no hotspots.
    //
    //   Blending: quadratic mean × 2 replaces simple sum during overlap.
    //   quad_mean(A,B) = sqrt((A²+B²)/2) × 2
    //   This is ≤ A+B (never brighter than sum) and ≥ max(A,B)
    //   (never darker than the brighter lobe). Produces a smooth, physically
    //   plausible merge without any hard transitions.
    // =========================================================================

    const float PHASE_OFFSET          = 0.17;   // visual rhythm offset — less predictable than 0.14

    const float OVERLAP_RANGE         = 0.35;   // interaction begins shortly before visual contact
    const float INTERFERENCE_SPREAD_V = 0.40;   // cross-panel breathing — subtle, elegant
    const float INTERFERENCE_SPREAD_U = 0.22;   // longitudinal breathing — slight lengthening
    const float SECONDARY_INTENSITY   = 0.80;   // counter reflection slightly dimmer

    float counterPos    = uLightPosition + PHASE_OFFSET;

    // overlapFactor: 0 = far apart, 1 = coincident
    float separation    = abs(travelPosition - counterPos);
    float overlapFactor = 1.0 - smoothstep(0.0, OVERLAP_RANGE, separation);

    // Interference-modulated effective sigma — expands smoothly during overlap
    float effSigmaV = CROSS_PANEL_SIGMA_V * (1.0 + overlapFactor * INTERFERENCE_SPREAD_V);
    float effSigmaU = TRAVEL_SIGMA_U      * (1.0 + overlapFactor * INTERFERENCE_SPREAD_U);

    // Energy-conserving attenuation: peak ∝ (nominal_area / effective_area)²
    // Keeps the brightness-per-unit-area constant regardless of spread.
    float nominalArea   = CROSS_PANEL_SIGMA_V * TRAVEL_SIGMA_U;
    float effectiveArea = effSigmaV * effSigmaU;
    float interferenceAtten = (nominalArea * nominalArea) / (effectiveArea * effectiveArea);

    float uVar_eff = 2.0 * effSigmaU * effSigmaU;
    float vVar_eff = 2.0 * effSigmaV * effSigmaV;

    // --- Primary lobe (top → bottom) ---
    float uDist_P  = vUv.x - travelPosition;
    float uGauss_P = exp(-(uDist_P * uDist_P) / uVar_eff);
    float vGauss_P = exp(-(vDist   * vDist)   / vVar_eff);

    float microGlint = valueNoise(vUv * vec2(512.0, 8.0));
    float glintMask  = pow(max(microGlint - 0.45, 0.0) / 0.55, 1.5);
    float shimmerMod = 1.0 + glintMask * 0.08 * uGauss_P;

    float primaryMask = uGauss_P * vGauss_P * roughnessMod * shimmerMod * interferenceAtten;

    // --- Counter lobe (bottom → top) — identical optical model, slightly dimmer ---
    float uDist_C  = vUv.x - counterPos;
    float uGauss_C = exp(-(uDist_C * uDist_C) / uVar_eff);
    float vGauss_C = exp(-(vDist   * vDist)   / vVar_eff);

    // Offset noise sample slightly so the two reflections have independent sparkle
    float microGlint_C = valueNoise(vUv * vec2(512.0, 8.0) + vec2(17.3, 0.0));
    float glintMask_C  = pow(max(microGlint_C - 0.45, 0.0) / 0.55, 1.5);
    float shimmerMod_C = 1.0 + glintMask_C * 0.08 * uGauss_C;

    float counterMask = uGauss_C * vGauss_C * roughnessMod * shimmerMod_C
                        * interferenceAtten * SECONDARY_INTENSITY;

    // --- Smooth energy-conserving blend ---
    // When apart: sum (independent lobes)
    // When overlapping: quadratic mean × 2 (no accumulation, smooth merge)
    float sumMasks  = primaryMask + counterMask;
    float quadMean  = sqrt((primaryMask * primaryMask + counterMask * counterMask) * 0.5) * 2.0;
    float blendedMask = mix(sumMasks, quadMean, overlapFactor);

    // --- Feathering lobes — use effSigmaU so they breathe with the main body ---
    float uSigma_S  = effSigmaU * 1.75;
    float uVar_S    = 2.0 * uSigma_S * uSigma_S;
    float uDist_S   = vUv.x - (travelPosition + SEC_OFFSET_U);
    float uGauss_S  = exp(-(uDist_S * uDist_S) / uVar_S);
    float vSigma_S  = CROSS_PANEL_SIGMA_V * 1.02;
    float vVar_S    = 2.0 * vSigma_S * vSigma_S;
    float vGauss_S  = exp(-(vDist * vDist) / vVar_S);
    float featherMask = uGauss_S * vGauss_S * roughnessMod;

    float uSigma_T  = effSigmaU * 2.50;
    float uVar_T    = 2.0 * uSigma_T * uSigma_T;
    float uDist_T   = vUv.x - (travelPosition + TER_OFFSET_U);
    float uGauss_T  = exp(-(uDist_T * uDist_T) / uVar_T);
    float vSigma_T  = CROSS_PANEL_SIGMA_V * 1.08;
    float vVar_T    = 2.0 * vSigma_T * vSigma_T;
    float vGauss_T  = exp(-(vDist * vDist) / vVar_T);
    float trailMask = uGauss_T * vGauss_T * roughnessMod;

    // --- Panel exposure — faint glass reveal around both reflections ---
    // Phase 22: panelExposure is removed. Material visibility is now driven
    // entirely by the reflection masks below.

    // --- Combined light contribution ---
    // Both primary and counter lobes use uLightColor (same optical model).
    // Feather lobes carry the same tint — they are part of the same reflection.
    vec3 lightContribution =
        uLightColor * blendedMask  * uLightIntensity * PRIMARY_INTENSITY
      + uLightColor * featherMask  * uLightIntensity * SEC_INTENSITY
      + uLightColor * trailMask    * uLightIntensity * TER_INTENSITY;

    // =========================================================================
    // LAYER 8: Brand-color fringe — anchored to primary lobe only
    // =========================================================================
    // The #EC044F tint follows the primary (top→bottom) reflection.
    // The counter reflection is white-only — like a fill light vs. the key light.
    // COLOR_SPREAD_U / COLOR_SPREAD_V produce the white-core / pink-fringe shape.

    const float COLOR_SPREAD_U = 1.6;
    const float COLOR_SPREAD_V = 1.55;

    float uSigmaColor = TRAVEL_SIGMA_U * COLOR_SPREAD_U;
    float uVarColor   = 2.0 * uSigmaColor * uSigmaColor;
    float uGaussColor = exp(-(uDist_P * uDist_P) / uVarColor);   // primary only

    float vSigmaColor = CROSS_PANEL_SIGMA_V * COLOR_SPREAD_V;
    float vVarColor   = 2.0 * vSigmaColor * vSigmaColor;
    float vGaussColor = exp(-(vDist * vDist) / vVarColor);

    float colorMask         = uGaussColor * vGaussColor * roughnessMod;
    vec3  colorContribution = uLightColor * colorMask * uColorIntensity;

    // =========================================================================
    // LAYER 9: HDR Emission & Composition — Phase 22 Reflection-Revealed Glass
    // =========================================================================
    //
    // The base material is no longer added unconditionally.
    // Instead, material visibility is driven by the combined reflection presence.
    //
    // REFLECTION PRESENCE
    // A smooth energy-based combination of all three mask contributions:
    //   reflectionField = sqrt(blendedMask² + featherMask² + trailMask²)
    // This is the L2-norm (Euclidean length) of the three fields — it is strictly
    // greater than any individual component (never falsely suppresses one lobe),
    // always smooth, and avoids the C1 discontinuity that max() introduces at
    // its crossover points. It naturally captures the full spread of the
    // reflection's influence — the feather/trail lobes give the field a wider
    // radius than the core, so the panel begins emerging before the bright streak
    // arrives and lingers briefly after it departs.
    //
    // REVEAL FACTOR
    // A smooth power-curve lift of reflectionField:
    //   revealFactor = clamp(reflectionField × REVEAL_SCALE, 0.0, 1.0)
    // REVEAL_SCALE controls sensitivity. A value of 4.5 means the material
    // reaches ~50% opacity when reflectionField ≈ 0.11 — during the approach
    // of the wide trailing lobe, well before the white core arrives.
    //
    // RESIDUAL PRESENCE
    // A tiny constant floor (RESIDUAL = 0.008) is added to revealFactor before
    // clamping. This prevents the material from ever reaching mathematical zero —
    // it exists at 0.8% opacity at all times. This single value stops the glass
    // from feeling digitally absent between reflections, while remaining completely
    // imperceptible to the viewer against the black background.
    //
    // The result: the panel slowly emerges from darkness as the reflection
    // approaches (driven by the widening feather lobe), is fully revealed when
    // the core passes, and gracefully dissolves back into near-black as the
    // trailing lobe fades — all continuous, no popping, no abrupt transitions.
    // =========================================================================

    const float REVEAL_SCALE = 4.5;   // sensitivity of material reveal to reflection presence
    const float RESIDUAL     = 0.008; // imperceptible floor — prevents mathematical zero

    // Smooth energy-based combination of all reflection influences
    float reflectionField = sqrt(
        blendedMask  * blendedMask  +
        featherMask  * featherMask  +
        trailMask    * trailMask
    );

    // Reveal factor: smooth power lift from near-zero, clipped to [residual, 1.0]
    float revealFactor = clamp(reflectionField * REVEAL_SCALE + RESIDUAL, 0.0, 1.0);

    // Material is revealed only where the reflection is present
    vec3 revealedBase = baseMaterial * revealFactor;

    vec3 lightSum   = (lightContribution + colorContribution) * REFLECTION_INTENSITY;

    vec3 hdrColor   = revealedBase + lightSum * uEmissionStrength;
    vec3 ldrColor   = clamp(revealedBase + lightSum, 0.0, 1.0);

    vec3 finalColor = mix(ldrColor, hdrColor, uEnableEmission);

    gl_FragColor = vec4(finalColor, 1.0);
}
