#version 460 core

uniform float texSize;

in vec3 fPos;
flat in int norm;

out vec4 fCol;

fnl_state noise = fnlCreateState(0);

void main() {
    noise.noise_type = FNL_NOISE_PERLIN;
    noise.fractal_type = FNL_FRACTAL_FBM;
    noise.frequency = 2.85;

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
    fCol = vec4(n,n,n,1);
} 
