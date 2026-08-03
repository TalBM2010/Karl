// RENDER PIPELINE  —  owned by the render-overhaul.  Real image-based lighting (PMREM +
// RoomEnvironment) so every PBR MeshStandard/Physical surface picks up true ambient
// reflections, plus a proper post stack:  RenderPass -> UnrealBloom -> OutputPass (ACES
// tone-map + sRGB) -> FXAA -> Vignette.  This is the single source of truth for how the
// scene reaches the screen; env.js only builds world content now.
//
// Proven headless (see test/assettest.html): PMREMGenerator + RoomEnvironment + UnrealBloomPass
// + OutputPass all render under software GL with errors:[]. We reuse that exact approach and
// add cheap FXAA + a moody vignette. Tone-mapping happens ONLY in OutputPass (no double grade).
import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { FXAAShader } from 'three/addons/shaders/FXAAShader.js';
import { VignetteShader } from 'three/addons/shaders/VignetteShader.js';

export function initRender(renderer, scene, camera){
  // ---- tone-mapping lives here (OutputPass applies it). RenderPass renders LINEAR into the
  //      composer's HalfFloat buffer; only OutputPass tone-maps + sRGB-encodes to screen.
  //      Exposure kept LOW on purpose: the mood is a dark, high-contrast Diablo-IV cavern with
  //      DEEP blacks — the dark directional key + colored crystal point lights drive brightness,
  //      NOT the IBL. A bright studio exposure would wash the blacks and flatten the scene.
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 0.92;
  renderer.outputColorSpace = THREE.SRGBColorSpace;

  // The capture runs under software GL — render the 3D buffer a touch below 1:1 (bloom + FXAA
  // hide the softness) so the multi-pass chain stays well within the capture time budget.
  const RES_SCALE = 0.72;
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.25) * RES_SCALE);
  renderer.setSize(window.innerWidth, window.innerHeight);

  // ---- IMAGE-BASED LIGHTING: bake RoomEnvironment into a PMREM cube for scene.environment.
  //      Gives all PBR materials real specular reflections + soft ambient (no HDRI asset needed).
  const pmrem = new THREE.PMREMGenerator(renderer);
  pmrem.compileEquirectangularShader();
  const envRT = pmrem.fromScene(new RoomEnvironment(), 0.04);
  scene.environment = envRT.texture;
  // NOTE: scene.background is a tintable Color owned by env.js/floors.js — we do NOT touch it,
  // only scene.environment (the IBL source). Keeping them separate preserves the floor retints.

  // ---- POST STACK
  const composer = new EffectComposer(renderer); // default RT is HalfFloatType -> HDR headroom
  composer.addPass(new RenderPass(scene, camera));

  // Tuned bloom: only bright emissives (crystals / abilities / sparks / loot beams) bloom,
  // not the whole frame. strength .6 / radius .5 / threshold .8 per the brief.
  const bloom = new UnrealBloomPass(
    new THREE.Vector2(window.innerWidth, window.innerHeight), 0.6, 0.5, 0.8);
  composer.addPass(bloom);

  // OutputPass = ACES tone-map + sRGB encode in one correct step.
  composer.addPass(new OutputPass());

  // FXAA after tone-map/encode (operates in display space = correct edge luma).
  const fxaa = new ShaderPass(FXAAShader);
  composer.addPass(fxaa);

  // Moody vignette last: deepen + frame the corners so blacks stay rich, hero pops.
  const vignette = new ShaderPass(VignetteShader);
  vignette.uniforms.offset.value = 0.95;
  vignette.uniforms.darkness.value = 1.12;
  composer.addPass(vignette);

  function applyFxaaResolution(){
    const db = renderer.getDrawingBufferSize(new THREE.Vector2());
    fxaa.material.uniforms.resolution.value.set(1 / Math.max(1, db.x), 1 / Math.max(1, db.y));
  }

  function setSize(w, h){
    renderer.setSize(w, h);
    composer.setPixelRatio(renderer.getPixelRatio()); // keeps composer RTs at the render scale
    composer.setSize(w, h);                            // sizes every pass (incl. bloom) correctly
    applyFxaaResolution();
  }
  setSize(window.innerWidth, window.innerHeight);

  return {
    composer,
    render(){ composer.render(); },
    setSize,
    dispose(){ composer.dispose && composer.dispose(); envRT.dispose(); pmrem.dispose(); }
  };
}
