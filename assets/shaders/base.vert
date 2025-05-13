#version 460 core

uniform mat4 model;
uniform mat4 view;
uniform mat4 proj;

layout(binding = 0, std430) readonly buffer SSBO { 
    int data[];
};

out vec3 fPos;

const vec3 facePosses[] = vec3[](
    vec3(0,0,1), vec3(0,1,1), vec3(1,1,1), vec3(1,1,1), vec3(1,0,1), vec3(0,0,1), // front
    vec3(1,1,0), vec3(0,1,0), vec3(0,0,0), vec3(0,0,0), vec3(1,0,0), vec3(1,1,0), // back
    vec3(0,0,0), vec3(0,1,0), vec3(0,1,1), vec3(0,1,1), vec3(0,0,1), vec3(0,0,0), // left
    vec3(1,1,1), vec3(1,1,0), vec3(1,0,0), vec3(1,0,0), vec3(1,0,1), vec3(1,1,1), // right
    vec3(0,1,1), vec3(0,1,0), vec3(1,1,0), vec3(1,1,0), vec3(1,1,1), vec3(0,1,1), // top
    vec3(1,0,0), vec3(0,0,0), vec3(0,0,1), vec3(0,0,1), vec3(1,0,1), vec3(1,0,0)  // bottom
);

void main() {
    int index = gl_VertexID / 36;
    int packdata = data[index];
    int cVertexID = gl_VertexID % 36;

    int x = (packdata) & 0x3FF;
    int y = (packdata >> 10) & 0x3FF;
    int z = (packdata >> 20) & 0x3FF;
    vec3 pos = vec3(x,y,z);

    pos += facePosses[cVertexID];

    gl_Position = proj * view * model * vec4(pos,1);

    fPos = (model * vec4(pos,1)).xyz;
}
