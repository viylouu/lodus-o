#version 460 core

uniform float texSize;
uniform vec3 camPos;

in vec3 fPos;
flat in int norm;

out vec4 fCol;

fnl_state noise = fnlCreateState(0);

float scale_based_on_tex_size(float x) {
    return 2.2 * log(.7 * x + 1) + 1.3;
}

void main() {
    noise.noise_type = FNL_NOISE_PERLIN;
    noise.fractal_type = FNL_FRACTAL_FBM;
    noise.frequency = 2.85;

    float dist = distance(camPos, fPos);

    float scale = scale_based_on_tex_size(texSize);
    int steps = int(ceil(scale));

    if(texSize == 0) {
        steps = 8;
    }

    noise.octaves = 1;
    
    for (int i = 0; i < steps; i++) {
        if (dist < 6 * pow(3, i-1)) {
            noise.octaves = steps - i;
            break;
        }
    }
    

    vec3 rPos = fPos;
    if (texSize != 0) {
        rPos = floor(rPos * texSize) / texSize;
    }

    // fix for werid "clipping" issues
    switch(norm) {
        case 0:
        case 1:
            rPos.z = fPos.z; break;
        case 2:
        case 3:
            rPos.x = fPos.x; break;
        case 4:
        case 5:
            rPos.y = fPos.y; break;
    }

    float n = fnlGetNoise3D(noise, rPos.x,rPos.y,rPos.z) *.5+.5;

    fCol = mix(vec4(0,0,0,1),vec4(1,1,1,1), n);
} 
