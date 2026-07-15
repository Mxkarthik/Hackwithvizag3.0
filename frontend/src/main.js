import "./style.css";
import * as THREE from "three";

const scene = new THREE.Scene();

const camera = new THREE.PerspectiveCamera(
    45, // Field Of View
    window.innerWidth / window.innerHeight,  // Aspect Ratio
    0.1, // Near Plane
    100 // Far plane 
);

camera.position.z = 8;


const renderer = new THREE.WebGLRenderer({
    canvas: document.querySelector("#bg"),
    antialias: true,
});

renderer.setSize(
    window.innerWidth,
    window.innerHeight
);

renderer.setPixelRatio(
    Math.min(window.devicePixelRatio, 2)
);

renderer.setAnimationLoop(() => {

    renderer.render(scene, camera);

});