#version 460 core

in vec3 fPos;
out vec4 fCol;

fnl_state noise = fnlCreateState(0);

void main() {
    noise.noise_type = FNL_NOISE_PERLIN;
    noise.fractal_type = FNL_FRACTAL_FBM;
    noise.frequency = 2.85;

    float n = fnlGetNoise3D(noise, fPos.x,fPos.y,fPos.z);
    fCol = vec4(n,n,n,1);
}
