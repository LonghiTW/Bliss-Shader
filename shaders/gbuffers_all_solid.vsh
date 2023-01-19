#include "lib/settings.glsl"
#include "/lib/res_params.glsl"
#include "/lib/bokeh.glsl"


#ifndef USE_LUMINANCE_AS_HEIGHTMAP
#ifndef MC_NORMAL_MAP
#undef POM
#endif
#endif

#ifdef POM
#define MC_NORMAL_MAP
#endif

/*
!! DO NOT REMOVE !!
This code is from Chocapic13' shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!
*/
uniform int worldDay;
varying vec4 lmtexcoord;
varying vec4 color;
varying float VanillaAO;
varying vec4 NoSeasonCol;
varying vec4 normalMat;
#ifdef POM
varying vec4 vtexcoordam; // .st for add, .pq for mul
varying vec4 vtexcoord;
#endif


#ifdef MC_NORMAL_MAP
	varying vec4 tangent;
	attribute vec4 at_tangent;
	varying vec3 FlatNormals;
#endif

out vec3 test_motionVectors; 
in vec3 at_velocity;  

uniform float frameTimeCounter;
const float PI48 = 150.796447372*WAVY_SPEED;
float pi2wt = PI48*frameTimeCounter;

attribute vec4 mc_Entity;
uniform int blockEntityId;
uniform int entityId;

flat varying float blockID;
flat varying vec4 TESTMASK;
flat varying int lightningBolt;


uniform int frameCounter;
uniform float aspectRatio;
uniform float viewHeight;
uniform float viewWidth;
uniform sampler2D colortex4;
uniform int hideGUI;
uniform float screenBrightness;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
attribute vec4 mc_midTexCoord;
uniform vec3 cameraPosition;
uniform vec2 texelSize;
uniform int framemod8;
const vec2[8] offsets = vec2[8](vec2(1./8.,-3./8.),
							vec2(-1.,3.)/8.,
							vec2(5.0,1.)/8.,
							vec2(-3,-5.)/8.,
							vec2(-5.,5.)/8.,
							vec2(-7.,-1.)/8.,
							vec2(3,7.)/8.,
							vec2(7.,-7.)/8.);
#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)
vec4 toClipSpace3(vec3 viewSpacePosition) {
    return vec4(projMAD(gl_ProjectionMatrix, viewSpacePosition),-viewSpacePosition.z);
}

vec2 calcWave(in vec3 pos) {

    float magnitude = abs(sin(dot(vec4(frameTimeCounter, pos),vec4(1.0,0.005,0.005,0.005)))*0.5+0.72)*0.013;
	vec2 ret = (sin(pi2wt*vec2(0.0063,0.0015)*4. - pos.xz + pos.y*0.05)+0.1)*magnitude;

    return ret;
}

vec3 calcMovePlants(in vec3 pos) {
    vec2 move1 = calcWave(pos );
	float move1y = -length(move1);
   return vec3(move1.x,move1y,move1.y)*5.*WAVY_STRENGTH;
}

vec3 calcWaveLeaves(in vec3 pos, in float fm, in float mm, in float ma, in float f0, in float f1, in float f2, in float f3, in float f4, in float f5) {

    float magnitude = abs(sin(dot(vec4(frameTimeCounter, pos),vec4(1.0,0.005,0.005,0.005)))*0.5+0.72)*0.013;
	vec3 ret = (sin(pi2wt*vec3(0.0063,0.0224,0.0015)*1.5 - pos))*magnitude;

    return ret;
}

vec3 calcMoveLeaves(in vec3 pos, in float f0, in float f1, in float f2, in float f3, in float f4, in float f5, in vec3 amp1, in vec3 amp2) {
    vec3 move1 = calcWaveLeaves(pos      , 0.0054, 0.0400, 0.0400, 0.0127, 0.0089, 0.0114, 0.0063, 0.0224, 0.0015) * amp1;
    return move1*5.*WAVY_STRENGTH;
}
vec3 srgbToLinear2(vec3 srgb){
    return mix(
        srgb / 12.92,
        pow(.947867 * srgb + .0521327, vec3(2.4) ),
        step( .04045, srgb )
    );
}
vec3 blackbody2(float Temp)
{
    float t = pow(Temp, -1.5);
    float lt = log(Temp);

    vec3 col = vec3(0.0);
         col.x = 220000.0 * t + 0.58039215686;
         col.y = 0.39231372549 * lt - 2.44549019608;
         col.y = Temp > 6500. ? 138039.215686 * t + 0.72156862745 : col.y;
         col.z = 0.76078431372 * lt - 5.68078431373;
         col = clamp(col,0.0,1.0);
         col = Temp < 1000. ? col * Temp * 0.001 : col;

    return srgbToLinear2(col);
}
// float luma(vec3 color) {
// 	return dot(color,vec3(0.21, 0.72, 0.07));
// }

	#define SEASONS_VSH
	#include "/lib/climate_settings.glsl"

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

void main() {
	lmtexcoord.xy = (gl_MultiTexCoord0).xy;
	FlatNormals = normalize(gl_NormalMatrix * gl_Normal);
	TESTMASK = vec4(normalize(gl_NormalMatrix * gl_Normal), 1.0);
	
	TESTMASK.r = blockEntityId == 222 ? 255 : TESTMASK.r;
	
	blockID = mc_Entity.x;

	#ifdef ENTITIES
		test_motionVectors = at_velocity;
	#endif

	#ifdef POM
		vec2 midcoord = (gl_TextureMatrix[0] *  mc_midTexCoord).st;
		vec2 texcoordminusmid = lmtexcoord.xy-midcoord;
		vtexcoordam.pq  = abs(texcoordminusmid)*2;
		vtexcoordam.st  = min(lmtexcoord.xy,midcoord-texcoordminusmid);
		vtexcoord.xy    = sign(texcoordminusmid)*0.5+0.5;
	#endif

	vec2 lmcoord = gl_MultiTexCoord1.xy/255.;
	lmtexcoord.zw = lmcoord;
	vec3 position = mat3(gl_ModelViewMatrix) * vec3(gl_Vertex) + gl_ModelViewMatrix[3].xyz;
	
	color = gl_Color;
	VanillaAO = 1.0 - clamp(color.a,0,1);
	if (color.a < 0.3) color.a = 1.0; // fix vanilla ao on some custom block models.

	bool istopv = gl_MultiTexCoord0.t < mc_midTexCoord.t;

	#ifdef MC_NORMAL_MAP
		tangent = vec4(normalize(gl_NormalMatrix *at_tangent.rgb),at_tangent.w);
	#endif

	normalMat = vec4(normalize(gl_NormalMatrix *gl_Normal), 1.0);

#ifdef ENTITIES

	#ifdef mob_SSS
		#ifdef Variable_Penumbra_Shadows
			normalMat.a = entityId == 1100 ? 0.65 : normalMat.a;
			normalMat.a = entityId == 1200 ? 0.65 : normalMat.a;
		#endif
	#endif

			normalMat.a = 0.45;

	gl_Position = ftransform();

#endif



#ifdef WORLD

	normalMat = vec4(normalize(gl_NormalMatrix *gl_Normal),mc_Entity.x == 10004 || mc_Entity.x == 10003 ? 0.5 : mc_Entity.x == 10001 ? 0.6 : 1.0);

	normalMat.a = mc_Entity.x == 10006 || mc_Entity.x == 200 || mc_Entity.x == 100061 ? 0.6 : normalMat.a; // 0.6 weak SSS
	normalMat.a = blockEntityId == 10010 ? 0.65 : normalMat.a; // banners

	#ifdef misc_block_SSS
		normalMat.a = (mc_Entity.x == 10007 || mc_Entity.x == 10008) ? 0.55 : normalMat.a; // 0.55 abnormal block strong sss
	#endif

	normalMat.a = mc_Entity.x == 10005 ? 0.8 : normalMat.a;


	#ifdef WAVY_PLANTS
		if ((mc_Entity.x == 10001 && istopv) && abs(position.z) < 64.0) {
    vec3 worldpos = mat3(gbufferModelViewInverse) * position + gbufferModelViewInverse[3].xyz + cameraPosition;
		worldpos.xyz += calcMovePlants(worldpos.xyz)*lmtexcoord.w - cameraPosition;
    position = mat3(gbufferModelView) * worldpos + gbufferModelView[3].xyz;
		}

		if (mc_Entity.x == 10003 && abs(position.z) < 64.0) {
    vec3 worldpos = mat3(gbufferModelViewInverse) * position + gbufferModelViewInverse[3].xyz + cameraPosition;
		worldpos.xyz += calcMoveLeaves(worldpos.xyz, 0.0040, 0.0064, 0.0043, 0.0035, 0.0037, 0.0041, vec3(1.0,0.2,1.0), vec3(0.5,0.1,0.5))*lmtexcoord.w  - cameraPosition;
    position = mat3(gbufferModelView) * worldpos + gbufferModelView[3].xyz;
		}
	#endif

	if (mc_Entity.x == 100 ){
		color.rgb = normalize(color.rgb)*sqrt(3.0);
		normalMat.a = 0.9;
	}

	gl_Position = toClipSpace3(position);
	
	
	

	#ifdef SEPARATE_AO

		// #if indirect_effect == 1 || indirect_effect == 0
		// 	lmtexcoord.zw *= sqrt(color.a);
		// #endif
		
	#else
		color.rgb *= color.a;
	#endif	

	// if (mc_Entity.x == 10099 ) seasonColor.rgb = (gl_Color.rgb * blackbody2(sin(frameTimeCounter)*12000 + 14000)) * (1.0 - floor(luma(gl_Color.rgb)+(1.0/255.)));

#endif

	// seasonColor = color;
	NoSeasonCol.rgb = gl_Color.rgb;
	#ifdef Seasons
	#ifndef BLOCKENTITIES
	#ifndef ENTITIES 
		YearCycleColor(color.rgb, gl_Color.rgb);
	#endif
	#endif
	#endif 

	#ifdef TAA_UPSCALING
		gl_Position.xy = gl_Position.xy * RENDER_SCALE + RENDER_SCALE * gl_Position.w - gl_Position.w;
	#endif
	#ifdef TAA
		gl_Position.xy += offsets[framemod8] * gl_Position.w * texelSize;
	#endif

	#ifdef DOF_JITTER
		vec2 jitter = clamp(jitter_offsets[frameCounter % 64], -1.0, 1.0);
		jitter = rotate(frameCounter) * jitter;
		jitter.y *= aspectRatio;
		jitter.x *= DOF_ANAMORPHIC_RATIO;

		#if DOF_JITTER_FOCUS < 0
		float focusMul = gl_Position.z - mix(pow(512.0, screenBrightness), 512.0 * screenBrightness, 0.25);
		#else
		float focusMul = gl_Position.z - DOF_JITTER_FOCUS;
		#endif

		vec2 totalOffset = (jitter * JITTER_STRENGTH) * focusMul * 1e-2;
		gl_Position.xy += hideGUI >= 1 ? totalOffset : vec2(0);
	#endif
}
