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

  // ---- IMAGE-BASED LIGHTING: bake a DARKENED, COOL-TINTED RoomEnvironment into a PMREM cube
  //      for scene.environment. This three r160 has no scene.environmentIntensity, so instead of
  //      a bright neutral studio (which washed the blacks and desaturated the crystals to grey),
  //      we scale the room's emissive area-lights + point light WAY down and tint them deep
  //      teal/indigo BEFORE baking. Result: scene.environment acts only as subtle, cool PBR
  //      reflection fill — the dark key light + colored point lights still own the mood, blacks
  //      stay deep. Boulders/ground/crystals get real reflections without a studio wash.
  const room = new RoomEnvironment();
  const IBL_GAIN = 0.16;                       // crush the IBL brightness (was effectively 1.0)
  const IBL_TINT = new THREE.Color(0x2b5a72);  // deep teal/indigo cast on the reflections
  room.traverse((o)=>{
    const m = o.material;
    if(!m) return;
    if(m.isMeshBasicMaterial){                 // the emissive "area light" panels
      m.color.multiplyScalar(IBL_GAIN); m.color.multiply(IBL_TINT).multiplyScalar(2.0);
    } else if(m.isMeshStandardMaterial){       // room + box surfaces (bounce)
      m.color.lerp(IBL_TINT, 0.5).multiplyScalar(0.5);
    }
  });
  room.traverse((o)=>{ if(o.isPointLight){ o.intensity *= IBL_GAIN; o.color.copy(IBL_TINT); } });

  const pmrem = new THREE.PMREMGenerator(renderer);
  pmrem.compileEquirectangularShader();
  const envRT = pmrem.fromScene(room, 0.04);
  scene.environment = envRT.texture;
  room.dispose && room.dispose();
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

  // Moody vignette last: strong, cinematic darkening that crushes the corners toward black so
  // the frame reads like the reference cavern (deep blacks, hero pops) — not a bright studio.
  const vignette = new ShaderPass(VignetteShader);
  vignette.uniforms.offset.value = 1.15;
  vignette.uniforms.darkness.value = 1.35;
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
