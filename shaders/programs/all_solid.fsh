#extension GL_EXT_gpu_shader4 : enable
#extension GL_ARB_shader_texture_lod : enable

#include "/lib/settings.glsl"



flat varying int NameTags;

#ifndef USE_LUMINANCE_AS_HEIGHTMAP
#ifndef MC_NORMAL_MAP
#undef POM
#endif
#endif

#ifdef POM
#define MC_NORMAL_MAP
#endif


varying float VanillaAO;

const float mincoord = 1.0/4096.0;
const float maxcoord = 1.0-mincoord;

const float MAX_OCCLUSION_DISTANCE = MAX_DIST;
const float MIX_OCCLUSION_DISTANCE = MAX_DIST*0.9;
const int   MAX_OCCLUSION_POINTS   = MAX_ITERATIONS;

uniform vec2 texelSize;
uniform int framemod8;

#ifdef POM
varying vec4 vtexcoordam; // .st for add, .pq for mul
varying vec4 vtexcoord;

#endif

#include "/lib/res_params.glsl"
varying vec4 lmtexcoord;
varying vec4 color;
varying vec4 NoSeasonCol;
varying vec4 seasonColor;
uniform float far;
varying vec4 normalMat;
#ifdef MC_NORMAL_MAP
varying vec4 tangent;
uniform float wetness;
uniform sampler2D normals;
uniform sampler2D specular;
varying vec3 FlatNormals;
#endif

#ifdef POM
	vec2 dcdx = dFdx(vtexcoord.st*vtexcoordam.pq)*exp2(Texture_MipMap_Bias);
	vec2 dcdy = dFdy(vtexcoord.st*vtexcoordam.pq)*exp2(Texture_MipMap_Bias);
#endif

flat varying int lightningBolt;
uniform sampler2D texture;
uniform sampler2D colortex1;//albedo(rgb),material(alpha) RGBA16
uniform float frameTimeCounter;
uniform int frameCounter;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform float rainStrength;
uniform sampler2D noisetex;//depth
uniform sampler2D depthtex0;
in vec3 test_motionVectors;

flat varying float blockID;


// float interleaved_gradientNoise(){
// 	return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y)+frameTimeCounter*51.9521);
// }
// float interleaved_gradientNoise(){
// 	vec2 alpha = vec2(0.75487765, 0.56984026);
// 	vec2 coord = vec2(alpha.x * gl_FragCoord.x,alpha.y * gl_FragCoord.y)+ 1.0/1.6180339887 * frameCounter;
// 	float noise = fract(52.9829189*fract(0.06711056*coord.x + 0.00583715*coord.y));
// 	return noise;
// }
float interleaved_gradientNoise(){
	vec2 coord = gl_FragCoord.xy;
	float noise = fract(52.9829189*fract(0.06711056*coord.x + 0.00583715*coord.y));
	return noise;
}
float blueNoise(){
  return fract(texelFetch2D(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 * frameCounter);
}
float R2_dither(){
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha.x * gl_FragCoord.x + alpha.y * gl_FragCoord.y + 1.0/1.6180339887 * frameCounter) ;
}
vec2 decodeVec2(float a){
    const vec2 constant1 = 65535. / vec2( 256., 65536.);
    const float constant2 = 256. / 255.;
    return fract( a * constant1 ) * constant2 ;
}
mat3 inverse(mat3 m) {
  float a00 = m[0][0], a01 = m[0][1], a02 = m[0][2];
  float a10 = m[1][0], a11 = m[1][1], a12 = m[1][2];
  float a20 = m[2][0], a21 = m[2][1], a22 = m[2][2];

  float b01 = a22 * a11 - a12 * a21;
  float b11 = -a22 * a10 + a12 * a20;
  float b21 = a21 * a10 - a11 * a20;

  float det = a00 * b01 + a01 * b11 + a02 * b21;

  return mat3(b01, (-a22 * a01 + a02 * a21), (a12 * a01 - a02 * a11),
              b11, (a22 * a00 - a02 * a20), (-a12 * a00 + a02 * a10),
              b21, (-a21 * a00 + a01 * a20), (a11 * a00 - a01 * a10)) / det;
}

vec3 viewToWorld(vec3 viewPosition) {
    vec4 pos;
    pos.xyz = viewPosition;
    pos.w = 0.0;
    pos = gbufferModelViewInverse * pos;
    return pos.xyz;
}
vec3 worldToView(vec3 worldPos) {
    vec4 pos = vec4(worldPos, 0.0);
    pos = gbufferModelView * pos;
    return pos.xyz;
}
vec4 encode (vec3 n, vec2 lightmaps){
	n.xy = n.xy / dot(abs(n), vec3(1.0));
	n.xy = n.z <= 0.0 ? (1.0 - abs(n.yx)) * sign(n.xy) : n.xy;
    vec2 encn = clamp(n.xy * 0.5 + 0.5,-1.0,1.0);
	
    return vec4(encn,vec2(lightmaps.x,lightmaps.y));
}


#ifdef MC_NORMAL_MAP
	vec3 applyBump(mat3 tbnMatrix, vec3 bump, float puddle_values){
		float bumpmult = clamp(puddle_values,0.0,1.0);
		bump = bump * vec3(bumpmult, bumpmult, bumpmult) + vec3(0.0f, 0.0f, 1.0f - bumpmult);
		return normalize(bump*tbnMatrix);
	}
#endif

//encoding by jodie
float encodeVec2(vec2 a){
    const vec2 constant1 = vec2( 1., 256.) / 65535.;
    vec2 temp = floor( a * 255. );
	return temp.x*constant1.x+temp.y*constant1.y;
}
float encodeVec2(float x,float y){
    return encodeVec2(vec2(x,y));
}

#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)

vec3 toScreenSpace(vec3 p) {
	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
    vec3 p3 = p * 2. - 1.;
    vec4 fragposition = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
    return fragposition.xyz / fragposition.w;
}
vec3 toClipSpace3(vec3 viewSpacePosition) {
    return projMAD(gbufferProjection, viewSpacePosition) / -viewSpacePosition.z * 0.5 + 0.5;
}
#ifdef POM
vec4 readNormal(in vec2 coord)
{
	return texture2DGradARB(normals,fract(coord)*vtexcoordam.pq+vtexcoordam.st,dcdx,dcdy);
}
vec4 readTexture(in vec2 coord)
{
	return texture2DGradARB(texture,fract(coord)*vtexcoordam.pq+vtexcoordam.st,dcdx,dcdy);
}
#endif
float luma(vec3 color) {
	return dot(color,vec3(0.21, 0.72, 0.07));
}


vec3 toLinear(vec3 sRGB){
	return sRGB * (sRGB * (sRGB * 0.305306011 + 0.682171111) + 0.012522878);
}


const vec2[8] offsets = vec2[8](vec2(1./8.,-3./8.),
									vec2(-1.,3.)/8.,
									vec2(5.0,1.)/8.,
									vec2(-3,-5.)/8.,
									vec2(-5.,5.)/8.,
									vec2(-7.,-1.)/8.,
									vec2(3,7.)/8.,
									vec2(7.,-7.)/8.);
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
float densityAtPosSNOW(in vec3 pos){
	pos /= 18.;
	pos.xz *= 0.5;
	vec3 p = floor(pos);
	vec3 f = fract(pos);
	f = (f*f) * (3.-2.*f);
	vec2 uv =  p.xz + f.xz + p.y * vec2(0.0,193.0);
	vec2 coord =  uv / 512.0;
	vec2 xy = texture2D(noisetex, coord).yx;
	return mix(xy.r,xy.g, f.y);
}

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

/* RENDERTARGETS: 1,7,8,15,10 */
void main() {


    float phi = 2 * 3.14159265359;
	float noise = fract(fract(frameCounter * (1.0 / phi)) + interleaved_gradientNoise() )	;

	vec3 normal = normalMat.xyz;
	vec3 normal2 = normalMat.xyz;

	#ifdef MC_NORMAL_MAP
		vec3 tangent2 = normalize(cross(tangent.rgb,normal)*tangent.w);
		mat3 tbnMatrix = mat3(tangent.x, tangent2.x, normal.x,
							  tangent.y, tangent2.y, normal.y,
							  tangent.z, tangent2.z, normal.z);
	#endif

	vec2 tempOffset=offsets[framemod8];

	vec3 fragpos = toScreenSpace(gl_FragCoord.xyz*vec3(texelSize/RENDER_SCALE,1.0)-vec3(vec2(tempOffset)*texelSize*0.5,0.0));
	vec3 worldpos = mat3(gbufferModelViewInverse) * fragpos + gbufferModelViewInverse[3].xyz + cameraPosition;


	float lightmap = clamp( (lmtexcoord.w-0.8) * 10.0,0.,1.);


	#ifdef POM
		// vec2 tempOffset=offsets[framemod8];
		vec2 adjustedTexCoord = fract(vtexcoord.st)*vtexcoordam.pq+vtexcoordam.st;
		// vec3 fragpos = toScreenSpace(gl_FragCoord.xyz*vec3(texelSize/RENDER_SCALE,1.0)-vec3(vec2(tempOffset)*texelSize*0.5,0.0));
		vec3 viewVector = normalize(tbnMatrix*fragpos);
		float dist = length(fragpos);

		gl_FragDepth = gl_FragCoord.z;

		#ifdef WORLD
	    	if (dist < MAX_OCCLUSION_DISTANCE) {

				float depthmap = readNormal(vtexcoord.st).a;
				float used_POM_DEPTH = 1.0;

	   	 	if ( viewVector.z < 0.0 && depthmap < 0.9999 && depthmap > 0.00001) {	

	  				#ifdef Adaptive_Step_length
						vec3 interval = (viewVector.xyz /-viewVector.z/MAX_OCCLUSION_POINTS * POM_DEPTH) * clamp(1.0-pow(depthmap,2),0.1,1.0) ;
						used_POM_DEPTH = 1.0;
	  				#else
	  					vec3 interval = viewVector.xyz /-viewVector.z/MAX_OCCLUSION_POINTS*POM_DEPTH;
					#endif
					vec3 coord = vec3(vtexcoord.st, 1.0);

					coord += interval * used_POM_DEPTH;

					float sumVec = 0.5;
					for (int loopCount = 0; (loopCount < MAX_OCCLUSION_POINTS) && (1.0 - POM_DEPTH + POM_DEPTH * readNormal(coord.st).a  ) < coord.p  && coord.p >= 0.0; ++loopCount) {
						coord = coord+interval * used_POM_DEPTH; 
						sumVec += 1.0 * used_POM_DEPTH; 
					}
	
					if (coord.t < mincoord) {
	  					if (readTexture(vec2(coord.s,mincoord)).a == 0.0) {
	  						coord.t = mincoord;
	  						discard;
	  					}
	  				}
	  				adjustedTexCoord = mix(fract(coord.st)*vtexcoordam.pq+vtexcoordam.st, adjustedTexCoord, max(dist-MIX_OCCLUSION_DISTANCE,0.0)/(MAX_OCCLUSION_DISTANCE-MIX_OCCLUSION_DISTANCE));

	  				vec3 truePos = fragpos + sumVec*inverse(tbnMatrix)*interval;
	  				// #ifdef Depth_Write_POM
	  					gl_FragDepth = toClipSpace3(truePos).z;
	  				// #endif
				}
	    	}
		#endif

		//////////////////////////////// 
		//////////////////////////////// ALBEDO
		//////////////////////////////// 

		vec4 Albedo = texture2DGradARB(texture, adjustedTexCoord.xy,dcdx,dcdy) * color;
		
		#ifdef ENTITIES
			if(NameTags == 1) Albedo = texture2D(texture, lmtexcoord.xy, Texture_MipMap_Bias) * color;
		#endif

		#ifdef WORLD
			if (Albedo.a > 0.1) Albedo.a = normalMat.a;
			else Albedo.a = 0.0;
		#endif

		#ifdef HAND
			if (Albedo.a > 0.1) Albedo.a = 0.75;
			else Albedo.a = 0.0;
		#endif

		//////////////////////////////// 
		//////////////////////////////// NORMAL
		//////////////////////////////// 

		#ifdef MC_NORMAL_MAP
			vec3 NormalTex = texture2DGradARB(normals, adjustedTexCoord.xy, dcdx,dcdy).rgb;
			NormalTex.xy = NormalTex.xy*2.0-1.0;
			NormalTex.z = clamp(sqrt(1.0 - dot(NormalTex.xy, NormalTex.xy)),0.0,1.0);

			normal = applyBump(tbnMatrix,NormalTex, 1.0);
		#endif

		//////////////////////////////// 
		//////////////////////////////// SPECULAR
		//////////////////////////////// 

		gl_FragData[2] = texture2DGradARB(specular, adjustedTexCoord.xy,dcdx,dcdy);

		//////////////////////////////// 
		//////////////////////////////// FINALIZE
		//////////////////////////////// 

		vec4 data1 = clamp(encode(viewToWorld(normal), lmtexcoord.zw),0.,1.0);
		gl_FragData[0] = vec4(encodeVec2(Albedo.x,data1.x),encodeVec2(Albedo.y,data1.y),encodeVec2(Albedo.z,data1.z),encodeVec2(data1.w,Albedo.w));
		
		gl_FragData[1].a = 0.0;

	#else

		//////////////////////////////// 
		//////////////////////////////// NORMAL
		//////////////////////////////// 

		#ifdef MC_NORMAL_MAP
			vec4 NormalTex = texture2D(normals, lmtexcoord.xy, Texture_MipMap_Bias).rgba;
			NormalTex.xy = NormalTex.xy*2.0-1.0;
			NormalTex.z = clamp(sqrt(1.0 - dot(NormalTex.xy, NormalTex.xy)),0.0,1.0) ;

			normal = applyBump(tbnMatrix, NormalTex.xyz,  1.0);
		#endif


		//////////////////////////////// 
		//////////////////////////////// SPECULAR
		//////////////////////////////// 

		vec4 SpecularTex = texture2D(specular, lmtexcoord.xy, Texture_MipMap_Bias);
		gl_FragData[2] = SpecularTex;
		
		//////////////////////////////// 
		//////////////////////////////// ALBEDO
		//////////////////////////////// 

		vec4 Albedo = texture2D(texture, lmtexcoord.xy, Texture_MipMap_Bias) * color;

		
		#ifdef WhiteWorld
			Albedo.rgb = vec3(1.0);
		#endif
		
		#ifdef WORLD
			if (Albedo.a > 0.1) Albedo.a = normalMat.a;
			else Albedo.a = 0.0;
		#endif

		#ifdef HAND
			if (Albedo.a > 0.1) Albedo.a = 0.75;
			else Albedo.a = 0.0;
		#endif

		//////////////////////////////// 
		//////////////////////////////// FINALIZE
		//////////////////////////////// 
		

		vec4 data1 = clamp( encode(viewToWorld(normal),  blueNoise()*lmtexcoord.zw/50.0+lmtexcoord.zw	),0.0,1.0);

		gl_FragData[0] =  vec4(encodeVec2(Albedo.x,data1.x),	encodeVec2(Albedo.y,data1.y),	encodeVec2(Albedo.z,data1.z),	encodeVec2(data1.w,Albedo.w));

		#ifdef WORLD
			gl_FragData[1].a = 0.0;
		#endif
	
	#endif

	gl_FragData[3] = vec4(FlatNormals* 0.5 + 0.5,VanillaAO);


	gl_FragData[4].x = 0;

	#ifdef ENTITIES
		gl_FragData[4].x = 1;
	#endif
}