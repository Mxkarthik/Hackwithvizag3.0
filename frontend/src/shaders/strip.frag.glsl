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
    vec3 verticalDepth = mix(vec3(0.0), vec3(0.011), verticalGradientFactor);

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

    const float STATIC_SIGMA_U  = 0.18;
    const float STATIC_SIGMA_V  = 0.08;
    const float STATIC_PEAK     = 0.012;
    const float STATIC_BREAKUP  = 0.25;  // surface variation influence on static streak

    float staticDistU  = vUv.x - 0.5;
    float staticDistV  = vUv.y - 0.5;
    float staticGaussU = exp(-(staticDistU * staticDistU) / (2.0 * STATIC_SIGMA_U * STATIC_SIGMA_U));
    float staticGaussV = exp(-(staticDistV * staticDistV) / (2.0 * STATIC_SIGMA_V * STATIC_SIGMA_V));

    // Surface variation will be computed in Layer 6 — forward-declare to allow
    // Layer 3 to use it. GLSL evaluates in source order, so we call
    // getSurfaceVariation() here directly (it has no dependency on later layers).
    float surfaceVariation  = getSurfaceVariation(vUv) * uNoiseStrength;
    float staticBreakupMod  = 1.0 - surfaceVariation * STATIC_BREAKUP;
    vec3  metallicReflection = vec3(staticGaussU * staticGaussV * STATIC_PEAK * uMetalStrength * staticBreakupMod);

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

    const float EDGE_CATCH_PEAK = 0.018;

    float leftEdge    = smoothstep(0.0,  0.15, vUv.x);
    float rightEdge   = smoothstep(1.0,  0.85, vUv.x);
    float edgeFalloff = leftEdge * rightEdge;

    float catchLeft   = pow(1.0 - smoothstep(0.0,  0.06, vUv.x), 2.5);
    float catchRight  = pow(1.0 - smoothstep(0.94, 1.0,  vUv.x), 2.5);
    float edgeCatch   = (catchLeft + catchRight) * EDGE_CATCH_PEAK;

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

    float vCenterBrightness = 1.0 + 0.04 * (1.0 - 4.0 * (vUv.y - 0.5) * (vUv.y - 0.5));
    vec3  baseMicroTexture  = vec3(surfaceVariation * 0.006 - 0.003);

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

    const float SWEEP_SIGMA_V        = 0.30;   // V-axis streak height (tightened Phase 9 — elongated streak)
    const float ROUGHNESS_MODULATION = 0.15;  // max roughness attenuation (Phase 9 — refined brushed-metal)

    const float SEC_OFFSET_U  =  0.04;   // secondary lobe U offset from primary
    const float TER_OFFSET_U  = -0.08;   // tertiary lobe U offset from primary
    const float SEC_INTENSITY =  0.22;   // secondary lobe relative intensity
    const float TER_INTENSITY =  0.07;   // tertiary lobe relative intensity

    // Shared V-axis attenuation (same for all lobes — same strip geometry)
    float vDist     = vUv.y - 0.5;
    float vVariance = 2.0 * SWEEP_SIGMA_V * SWEEP_SIGMA_V;
    float vGaussian = exp(-(vDist * vDist) / vVariance);

    // Shared roughness modulation
    float roughnessMod = 1.0 - surfaceVariation * ROUGHNESS_MODULATION;

    // --- Primary lobe ---
    float hDist_P    = vUv.x - uLightPosition;
    float hVar_P     = 2.0 * uLightWidth * uLightWidth;
    float hGauss_P   = exp(-(hDist_P * hDist_P) / hVar_P);

    // Micro-shimmer — high-frequency noise over the primary lobe
    // Only the top percentile of the noise produces a visible glint.
    // Phase 9: threshold lowered 0.60→0.55 (more micro-glints),
    //          multiplier reduced 0.25→0.20 (each glint subtler).
    float microGlint  = valueNoise(vUv * vec2(512.0, 8.0));
    float glintMask   = pow(max(microGlint - 0.55, 0.0) / 0.45, 2.0);
    float shimmerMod  = 1.0 + glintMask * 0.20 * hGauss_P;  // attenuated by lobe

    float primaryMask = hGauss_P * vGaussian * roughnessMod * shimmerMod;

    // --- Secondary lobe (white, offset along U) ---
    float hSigma_S   = uLightWidth * 1.8;
    float hVar_S     = 2.0 * hSigma_S * hSigma_S;
    float hDist_S    = vUv.x - (uLightPosition + SEC_OFFSET_U);
    float hGauss_S   = exp(-(hDist_S * hDist_S) / hVar_S);

    float vSigma_S   = SWEEP_SIGMA_V * 0.85;
    float vVar_S     = 2.0 * vSigma_S * vSigma_S;
    float vGauss_S   = exp(-(vDist * vDist) / vVar_S);

    float secondaryMask = hGauss_S * vGauss_S * roughnessMod;

    // --- Tertiary lobe (white, offset opposite direction along U) ---
    float hSigma_T   = uLightWidth * 2.5;   // reduced from 3.0 — prevents U bleed (Phase 9)
    float hVar_T     = 2.0 * hSigma_T * hSigma_T;
    float hDist_T    = vUv.x - (uLightPosition + TER_OFFSET_U);
    float hGauss_T   = exp(-(hDist_T * hDist_T) / hVar_T);

    float vSigma_T   = SWEEP_SIGMA_V * 1.60;   // increased from 1.20 — tertiary clearly softest (Phase 9)
    float vVar_T     = 2.0 * vSigma_T * vSigma_T;
    float vGauss_T   = exp(-(vDist * vDist) / vVar_T);

    float tertiaryMask = hGauss_T * vGauss_T * roughnessMod;

    // Combined white light contribution — all three lobes, stored independently
    vec3 lightContribution =
        vec3(primaryMask)   * uLightIntensity              // primary
      + vec3(secondaryMask) * uLightIntensity * SEC_INTENSITY  // secondary
      + vec3(tertiaryMask)  * uLightIntensity * TER_INTENSITY; // tertiary

    // =========================================================================
    // LAYER 8: Colored Illumination  (Phase 7.5 — primary lobe only)
    // =========================================================================
    // The brand-color fringe follows the PRIMARY lobe only.
    // Secondary and tertiary lobes remain neutral white — they are off-angle
    // reflections that show the material's intrinsic colour, not the light's
    // chromatic character. This matches premium anodized metal behaviour.
    //
    // Architecture unchanged from Phase 6.5:
    //   COLOR_SPREAD_U = 1.6 → σ_color_U = uLightWidth × 1.6
    //   COLOR_SPREAD_V = 1.1 → σ_color_V = SWEEP_SIGMA_V × 1.1
    // The color lobe is wider than the white primary lobe, producing the
    // white-core / pink-fringe appearance.

    const float COLOR_SPREAD_U = 1.6;
    const float COLOR_SPREAD_V = 1.1;

    float hSigmaColor    = uLightWidth * COLOR_SPREAD_U;
    float hVarColor      = 2.0 * hSigmaColor * hSigmaColor;
    float hGaussColor    = exp(-(hDist_P * hDist_P) / hVarColor);   // anchored to primary

    float vSigmaColor    = SWEEP_SIGMA_V * COLOR_SPREAD_V;
    float vVarColor      = 2.0 * vSigmaColor * vSigmaColor;
    float vGaussColor    = exp(-(vDist * vDist) / vVarColor);

    float colorMask         = hGaussColor * vGaussColor * roughnessMod;
    vec3  colorContribution = uLightColor * colorMask * uColorIntensity;

    // =========================================================================
    // LAYER 9: HDR Emission & Composition  (unchanged)
    // =========================================================================
    vec3 lightSum   = lightContribution + colorContribution;

    vec3 hdrColor   = baseMaterial + lightSum * uEmissionStrength;
    vec3 ldrColor   = clamp(baseMaterial + lightSum, 0.0, 1.0);

    vec3 finalColor = mix(ldrColor, hdrColor, uEnableEmission);

    gl_FragColor = vec4(finalColor, 1.0);
}
