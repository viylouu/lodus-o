#version 460 core

#define BLENDMODE_ADD 0
#define BLENDMODE_SUB 1
#define BLENDMODE_MUL 2
#define BLENDMODE_DIV 3
#define BLENDMODE_MIX 4

uniform float texSize;
uniform vec3 camPos;
uniform int seed;

in vec3 fPos;
flat in int norm;

out vec4 fCol;

fnl_state noise = fnlCreateState(0);

struct texture {
    int layerSI;
    int layers;
};

struct texLayer { 
    vec4 col_dark;
    vec4 col_light;
    float contrast;
    float frequency;
    int fractal;
    int octaves;
    int blend;
    int noise;
    int seed_off;
};

layout(binding = 1, std430) readonly buffer TSSBO {
    texture texs[];
}; layout(binding = 2, std430) readonly buffer LSSBO {
    texLayer lays[];
};

void main() {
    texture t = texs[0];

    vec3 final = vec3(0);

    bool domix;
    vec3 mixn; 
    vec3 mixp;

    for (int i = 0; i < t.layers; i++) {
        texLayer l = lays[t.layerSI + i];

        noise.noise_type = l.noise;
        noise.fractal_type = l.fractal;
        noise.frequency = l.frequency;
        noise.seed = l.seed_off + seed;

        if (l.fractal != FNL_FRACTAL_NONE && l.octaves > 0) {
            float dist = distance(camPos, fPos);

            int steps = l.octaves;

            noise.octaves = 1;
            
            for (int j = 0; j < steps; j++) {
                if (dist < 4 * pow(3, j-1) + 8) {
                    noise.octaves = steps - j;
                    break;
                }
            }
        }
        
        vec3 rPos = fPos;
        if (texSize != 0) {
            vec3 eps = vec3(0.00001);
            vec3 off = vec3(0);
            switch(norm) {
                case 0: off = vec3(0,0,1);  break;
                case 1: off = vec3(0,0,-1); break;
                case 2: off = vec3(-1,0,0); break;
                case 3: off = vec3(1,0,0);  break;
                case 4: off = vec3(0,1,0);  break;
                case 5: off = vec3(0,-1,0); break;
            }

            rPos -= off * eps;

            rPos = floor(rPos * texSize) / texSize;
        }

        float n = fnlGetNoise3D(noise, rPos.x,rPos.y,rPos.z);
        n = sign(n) * pow(abs(n), 2-l.contrast);
        n = n *.5+.5;

        vec3 col = mix(l.col_dark.rgb, l.col_light.rgb, n);

        if (domix) {
            domix = false;
            col = mix(mixp, col, mixn);
        }

        if(i != t.layers-1) {
            if(lays[t.layerSI + i + 1].blend == BLENDMODE_MIX) {
                mixp = col;
                continue;
            }
        }

        switch(l.blend) {
            case BLENDMODE_ADD:
                final += col; break;
            case BLENDMODE_SUB:
                final -= col; break;
            case BLENDMODE_MUL:
                final *= col; break;
            case BLENDMODE_DIV:
                final /= max(col, vec3(0.00001)); break;
            case BLENDMODE_MIX:
                if (i != 0 && i != t.layers-1) {
                    domix = true;
                    mixn = col;
                } else {
                    final = vec3(1,0,1);
                }
        }
    }

    fCol = vec4(final,1);
} 
