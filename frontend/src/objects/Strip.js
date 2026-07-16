import * as THREE from "three";
import vertexShader from "../shaders/strip.vert.glsl";
import fragmentShader from "../shaders/strip.frag.glsl";

// 1. Configurable properties for the strip
const STRIP_CONFIG = {
    width: 4,
    height: 1,
    rotation: Math.PI / 4
};

// 2. Factory function using composition to create and return the THREE.Mesh
export default function createStrip() {
    // Instantiate geometry using the configuration object (no hardcoding)
    const geometry = new THREE.PlaneGeometry(
        STRIP_CONFIG.width,
        STRIP_CONFIG.height
    );

    // Dedicated uniforms object prepared for Phase 2 and future animations
    const uniforms = {
        uTime: {
            value: 0
        },
        uBaseColor: {
            value: new THREE.Color(0.052, 0.052, 0.052)
        },
        uLightColor: {
            value: new THREE.Color("#EC044F")
        },
        uLightPosition: {
            value: 0.0
        },
        uLightWidth: {
            value: 0.2
        },
        uMetalStrength: {
            value: 1.0
        },
        uNoiseStrength: {
            value: 0.0
        }
    };

    // Instantiate custom shader material using imported shaders and uniforms
    const material = new THREE.ShaderMaterial({
        vertexShader,
        fragmentShader,
        uniforms,
        transparent: true,
        depthWrite: false
    });

    // Create the mesh composition
    const mesh = new THREE.Mesh(geometry, material);

    // Apply the rotation from configuration
    mesh.rotation.z = STRIP_CONFIG.rotation;

    return mesh;
}
