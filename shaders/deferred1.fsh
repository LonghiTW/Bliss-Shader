#version 120
#extension GL_EXT_gpu_shader4 : enable

//Computes volumetric clouds at variable resolution (default 1/4 res)
#define HQ_CLOUDS	//Renders detailled clouds for viewport
#define CLOUDS_QUALITY 0.5 //[0.1 0.125 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.9 1.0]
#define TAA

flat varying vec3 sunColor;
flat varying vec3 moonColor;
flat varying vec3 avgAmbient;
flat varying float tempOffsets;

uniform sampler2D depthtex0;
// uniform sampler2D colortex4;
uniform sampler2D noisetex;

uniform vec3 sunVec;
uniform vec2 texelSize;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform int frameCounter;
uniform int framemod8;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;

uniform mat4 gbufferModelView;
// flat varying vec2 TAA_Offset;


vec3 toScreenSpace(vec3 p) {
	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
    vec3 p3 = p * 2. - 1.;
    vec4 fragposition = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
    return fragposition.xyz / fragposition.w;
}
float R2_dither(){
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha.x * gl_FragCoord.x + alpha.y * gl_FragCoord.y + 1.0/1.6180339887 * frameCounter);
}
float R2_dither2(){
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha.x * (1.0-gl_FragCoord.x) + alpha.y * (1.0-gl_FragCoord.y) + 1.0/1.6180339887 * frameCounter);
}
float interleaved_gradientNoise(){
	vec2 alpha = vec2(0.75487765, 0.56984026);
	vec2 coord = vec2(alpha.x * gl_FragCoord.x,alpha.y * gl_FragCoord.y)+ 1.0/1.6180339887 * frameCounter;
	float noise = fract(52.9829189*fract(0.06711056*coord.x + 0.00583715*coord.y));
	return noise;
}
#include "lib/sky_gradient.glsl"
#include "lib/volumetricClouds.glsl"
#include "/lib/res_params.glsl"
const vec2[8] offsets = vec2[8](vec2(1./8.,-3./8.),
							vec2(-1.,3.)/8.,
							vec2(5.0,1.)/8.,
							vec2(-3,-5.)/8.,
							vec2(-5.,5.)/8.,
							vec2(-7.,-1.)/8.,
							vec2(3,7.)/8.,
							vec2(7.,-7.)/8.);
float blueNoise(){
  return fract(texelFetch2D(noisetex, ivec2(1.0-gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 * frameCounter);
}
float blueNoise2(){
  return fract(texelFetch2D(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 * frameCounter);
}

vec3 normVec (vec3 vec){
	return vec*inversesqrt(dot(vec,vec));
}
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

void main() {
/* DRAWBUFFERS:0 */
float phi = 2 * 3.14159265359;
float noise = fract(fract(frameCounter * (1.0 / phi)) + interleaved_gradientNoise() )	;


	#ifdef VOLUMETRIC_CLOUDS
	vec2 halfResTC = vec2(floor(gl_FragCoord.xy)/CLOUDS_QUALITY/RENDER_SCALE+0.5+(vec2(tempOffsets)*(texelSize/4))*CLOUDS_QUALITY*RENDER_SCALE*0.5);

	vec3 fragpos = toScreenSpace(vec3(halfResTC*texelSize,1.0));
	vec3 p3 = mat3(gbufferModelViewInverse) * fragpos;
	vec3 np3 = normVec(p3);


	vec4 currentClouds = renderClouds(fragpos,vec3(0.), R2_dither(),sunColor/150.,moonColor/150.,avgAmbient/150.,blueNoise2());
	gl_FragData[0] = currentClouds ;


	#else
		gl_FragData[0] = vec4(0.0,0.0,0.0,1.0);
	#endif

}
