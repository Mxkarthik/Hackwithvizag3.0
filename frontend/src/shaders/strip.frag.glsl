varying vec2 vUv;

// Future-compatible uniforms for the next phases
uniform float uTime;
uniform vec3 uBaseColor;
uniform vec3 uLightColor;
uniform float uLightPosition;
uniform float uLightWidth;
uniform float uMetalStrength;
uniform float uNoiseStrength;

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

    // Clamp the final color to prevent any clipping/harsh highlights and keep it premium.
    gl_FragColor = vec4(clamp(finalColor, 0.0, 1.0), 1.0);
}
