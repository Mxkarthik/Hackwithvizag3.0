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

// Future-compatible uniforms for the next phases
uniform float uTime;
uniform vec3 uBaseColor;
uniform vec3 uLightColor;       // Brand color applied as the wider colored fringe (Phase 5)
uniform float uLightPosition;   // Owned and animated by JavaScript — do NOT derive in shader
uniform float uLightWidth;      // σ_U of the horizontal (long-axis) Gaussian lobe
uniform float uLightIntensity;  // Peak brightness of the white lobe
uniform float uColorIntensity;  // Relative strength of the colored lobe vs. the white lobe
uniform float uEmissionStrength; // HDR multiplier for light layers — feeds UnrealBloomPass (Phase 6)
uniform float uEnableEmission;  // Debug toggle: 1.0 = HDR emission on, 0.0 = Phase 5 LDR output
uniform float uMetalStrength;
uniform float uNoiseStrength;

// =============================================================================
// HELPER: getSurfaceVariation  (Phase 6.5 — two-octave anisotropic noise)
// =============================================================================
// Generates a deterministic procedural surface variation value in [0, 1].
// Simulates the microscopic roughness of brushed / anodized aluminium.
//
// UV orientation: U = long axis, V = short axis.
// Grain runs along U → many fine cells along U, few tall cells along V.
//
// Two-octave Value Noise:
//   Octave 1 — ANISO_SCALE_1 = vec2(128.0, 32.0)
//              128 cells along U (fine grain), 32 along V (tall strands)
//              Weight 0.7 — dominant structural layer
//   Octave 2 — ANISO_SCALE_2 = vec2(256.0, 64.0)
//              Very fine micro-detail on top of octave 1
//              Weight 0.3 — detail layer
//
// Why two octaves instead of one:
//   A single octave at this density produces a repeating moire pattern.
//   A second octave at 2× frequency breaks the periodicity while adding
//   fine micro-detail. The sum is smooth, band-limited, and pattern-free.
//
// Why Value Noise over Perlin/Simplex:
//   The output is a scalar roughness value, not a directional gradient.
//   Value Noise maps directly to a roughness convention and is cheaper.
// =============================================================================

// Deterministic 2D hash: maps a vec2 lattice coordinate to a float in [0, 1].
float hash2(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

// Single-octave Value Noise with Hermite interpolation.
float valueNoise(vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);
    vec2 u = f * f * (3.0 - 2.0 * f);   // Hermite smoothstep: 3t² - 2t³

    float a = hash2(i + vec2(0.0, 0.0));
    float b = hash2(i + vec2(1.0, 0.0));
    float c = hash2(i + vec2(0.0, 1.0));
    float d = hash2(i + vec2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float getSurfaceVariation(vec2 uv) {
    // Grain runs along U (long axis). Many fine cells along U, tall strands along V.
    const vec2 ANISO_SCALE_1 = vec2(128.0, 32.0);  // octave 1 — structural layer
    const vec2 ANISO_SCALE_2 = vec2(256.0, 64.0);  // octave 2 — micro-detail layer

    float o1 = valueNoise(uv * ANISO_SCALE_1);
    float o2 = valueNoise(uv * ANISO_SCALE_2);

    // Weighted sum — octave 1 dominates, octave 2 adds fine detail.
    return o1 * 0.7 + o2 * 0.3;
}

void main() {
    // -----------------------------------------------------------------
    // LAYER 1: Dark Base Color
    // -----------------------------------------------------------------
    // vec3(0.052) — premium almost-black base within the [0.045, 0.060] target.
    vec3 baseColor = uBaseColor;

    // -----------------------------------------------------------------
    // LAYER 2: Vertical Depth
    // -----------------------------------------------------------------
    // Subtle V-axis gradient (bottom → top) for three-dimensional depth.
    // Max addition of 0.006 — imperceptible individually, cumulative with other layers.
    float verticalGradientFactor = vUv.y;
    vec3 bottomOffset = vec3(0.0);
    vec3 topOffset    = vec3(0.006);
    vec3 verticalDepth = mix(bottomOffset, topOffset, verticalGradientFactor);

    // -----------------------------------------------------------------
    // LAYER 3: Anisotropic Static Metallic Reflection  (Phase 6.5 refined)
    // -----------------------------------------------------------------
    // Models the ambient environment reflection on brushed anodized aluminium.
    // On anisotropic metal the ambient reflection is:
    //   • Wide along the grain (U axis, long axis) — σ_U = 0.18
    //   • Very tight across the grain (V axis, short axis) — σ_V = 0.08
    //
    // This produces a thin horizontal streak centred at V=0.5, spanning
    // most of the strip's length — matching the reference appearance.
    //
    // Previous model: single 1D Gaussian along U only (no V compression).
    // That produced a uniform band equal brightness top-to-bottom.
    // The 2D anisotropic model compresses the band to a realistic streak.
    //
    // Aspect ratio: σ_U / σ_V = 0.18 / 0.08 = 2.25:1  (elliptical, horizontal)

    const float STATIC_SIGMA_U = 0.18;  // wide along U (long axis / grain direction)
    const float STATIC_SIGMA_V = 0.08;  // tight along V (short axis / cross-grain)
    const float STATIC_PEAK    = 0.012; // peak brightness — slightly reduced for subtlety

    float staticDistU  = vUv.x - 0.5;
    float staticDistV  = vUv.y - 0.5;
    float staticGaussU = exp(-(staticDistU * staticDistU) / (2.0 * STATIC_SIGMA_U * STATIC_SIGMA_U));
    float staticGaussV = exp(-(staticDistV * staticDistV) / (2.0 * STATIC_SIGMA_V * STATIC_SIGMA_V));
    vec3 metallicReflection = vec3(staticGaussU * staticGaussV * STATIC_PEAK * uMetalStrength);

    // -----------------------------------------------------------------
    // LAYER 4: Edge Falloff
    // -----------------------------------------------------------------
    // Darkens left and right edges (U axis extremes) for 3D curvature.
    float leftEdge   = smoothstep(0.0, 0.15, vUv.x);
    float rightEdge  = smoothstep(1.0, 0.85, vUv.x);
    float edgeFalloff = leftEdge * rightEdge;

    // -----------------------------------------------------------------
    // LAYER 5: Soft Tonal Adjustment
    // -----------------------------------------------------------------
    // Combines Layers 1–4 into baseMaterial — stored independently
    // so Layer 9 can apply HDR scaling only to the light contributions.
    vec3 blendedColor = baseColor + verticalDepth + metallicReflection;
    vec3 baseMaterial = blendedColor * edgeFalloff;

    // -----------------------------------------------------------------
    // LAYER 6: Procedural Surface Variation  (Phase 6.5 refined)
    // -----------------------------------------------------------------
    // Two-octave Value Noise over anisotropic UV space.
    // Grain aligned along U (long axis). Output in [0, 1].
    //
    // Modulation depth reduced from 0.30 → 0.12.
    // Fine brushed aluminium shows implied grain, not visible grain.
    // The 12% variation is below the perceptual threshold as standalone
    // texture but introduces subtle roughness-based light attenuation.
    float surfaceVariation = getSurfaceVariation(vUv) * uNoiseStrength;

    // -----------------------------------------------------------------
    // LAYER 7: Anisotropic Specular Sweep  (Phase 6.5 refined)
    // -----------------------------------------------------------------
    // UV orientation: U = long axis, V = short axis.
    //
    // The specular streak on brushed metal is:
    //   • Elongated along the grain (U axis) — σ_U is wide (= uLightWidth)
    //   • Compressed across the grain (V axis) — σ_V is very tight
    //
    // uLightPosition sweeps along U (vUv.x). The highlight moves across
    // the long axis, and the streak extends along that same long axis.
    //
    // Previous σ_V = 0.35 — too tall, produced a nearly circular/oval spot.
    // Refined σ_V = 0.05 — very tight across V, producing a long thin streak.
    // Refined σ_U = uLightWidth = 0.05 — tighter peak (was 0.08).
    //
    // Aspect ratio at these σ values: σ_V_streak / σ_U_peak = ?
    // Wait — the streak IS the U dimension. The light sweeps along U.
    // The tightness of the sweep is σ_U. The height of the streak is σ_V.
    // Streak height (V) / sweep width (U) = 0.5 / 0.05 = 10:1 elongation
    // along V relative to the sweep cross-section width.
    // This means the streak is tall (spans V) but narrow (tight in U at any moment).

    const float SWEEP_SIGMA_V      = 0.50;  // streak height along V (short axis)
    const float ROUGHNESS_MODULATION = 0.12; // max light attenuation from surface roughness

    // Distance from light centre along U (sweep axis).
    float hDist     = vUv.x - uLightPosition;
    float hVariance = 2.0 * uLightWidth * uLightWidth;   // 2σ_U²
    float hGaussian = exp(-(hDist * hDist) / hVariance);

    // Attenuation along V (cross-sweep axis) — tight to form a streak.
    float vDist     = vUv.y - 0.5;
    float vVariance = 2.0 * SWEEP_SIGMA_V * SWEEP_SIGMA_V;  // 2σ_V²
    float vGaussian = exp(-(vDist * vDist) / vVariance);

    // Roughness modulation — surface grain attenuates specular peak.
    float roughnessMod = 1.0 - surfaceVariation * ROUGHNESS_MODULATION;

    // White light contribution — stored independently for Layer 9.
    float lightMask         = hGaussian * vGaussian * roughnessMod;
    vec3  lightContribution = vec3(lightMask) * uLightIntensity;

    // -----------------------------------------------------------------
    // LAYER 8: Anisotropic Colored Illumination  (Phase 6.5 refined)
    // -----------------------------------------------------------------
    // Colored lobe is wider than the white lobe along U (sweep axis)
    // to produce the white-core / color-fringe effect.
    // Vertical spread kept close to the white lobe — color stays in
    // the streak, does not bleed into a color oval.
    //
    // Previous COLOR_SPREAD_FACTOR = 2.5 → σ_color_U = 0.20 (too wide, blob-like).
    // Refined  COLOR_SPREAD_FACTOR_U = 1.6 → σ_color_U = 0.08 (tight fringe).
    // Vertical spread factor = 1.1 → σ_color_V ≈ 0.55 (barely wider than streak).

    const float COLOR_SPREAD_U = 1.6;  // colored lobe is 1.6× wider than white along U
    const float COLOR_SPREAD_V = 1.1;  // barely taller than white along V

    float hSigmaColor    = uLightWidth * COLOR_SPREAD_U;
    float hVarianceColor = 2.0 * hSigmaColor * hSigmaColor;
    float hGaussianColor = exp(-(hDist * hDist) / hVarianceColor);

    float vSigmaColor    = SWEEP_SIGMA_V * COLOR_SPREAD_V;
    float vVarianceColor = 2.0 * vSigmaColor * vSigmaColor;
    float vGaussianColor = exp(-(vDist * vDist) / vVarianceColor);

    float colorMask         = hGaussianColor * vGaussianColor * roughnessMod;
    vec3  colorContribution = uLightColor * colorMask * uColorIntensity;

    // -----------------------------------------------------------------
    // LAYER 9: HDR Emission & Composition  (Phase 6 — unchanged)
    // -----------------------------------------------------------------
    // baseMaterial is never HDR-scaled.
    // Only lightContribution + colorContribution are scaled by uEmissionStrength.
    //
    // uEnableEmission float toggle:
    //   1.0 → HDR path (Phase 6+): light scaled by uEmissionStrength, no clamp.
    //   0.0 → LDR path (Phase 5):  light at face value, output clamped.

    vec3 lightSum  = lightContribution + colorContribution;

    vec3 hdrColor  = baseMaterial + lightSum * uEmissionStrength;
    vec3 ldrColor  = clamp(baseMaterial + lightSum, 0.0, 1.0);

    vec3 finalColor = mix(ldrColor, hdrColor, uEnableEmission);

    gl_FragColor = vec4(finalColor, 1.0);
}
