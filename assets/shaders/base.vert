#version 460 core

uniform mat4 projview;

layout(binding = 0, std430) readonly buffer SSBO { 
    int data[];
};

out vec3 fPos;
flat out int norm;

const vec3 facePosses[] = vec3[](
    vec3(0,0,1), vec3(0,1,1), vec3(1,1,1), vec3(1,1,1), vec3(1,0,1), vec3(0,0,1), // front
    vec3(1,1,0), vec3(0,1,0), vec3(0,0,0), vec3(0,0,0), vec3(1,0,0), vec3(1,1,0), // back
    vec3(0,0,0), vec3(0,1,0), vec3(0,1,1), vec3(0,1,1), vec3(0,0,1), vec3(0,0,0), // left
    vec3(1,1,1), vec3(1,1,0), vec3(1,0,0), vec3(1,0,0), vec3(1,0,1), vec3(1,1,1), // right
    vec3(0,1,1), vec3(0,1,0), vec3(1,1,0), vec3(1,1,0), vec3(1,1,1), vec3(0,1,1), // top
    vec3(1,0,0), vec3(0,0,0), vec3(0,0,1), vec3(0,0,1), vec3(1,0,1), vec3(1,0,0)  // bottom
);

void main() {
    int index = gl_VertexID / 6;
    int packdata = data[index];
    int cVertexID = gl_VertexID % 6;

    int x = (packdata) & 0x3F;
    int y = (packdata >> 6) & 0x3F;
    int z = (packdata >> 12) & 0x3F;
    vec3 pos = vec3(x,y,z);

    int normal = (packdata >> 18) & 0x7;

    pos += facePosses[cVertexID + normal * 6];

    gl_Position = projview * vec4(pos,1);

    fPos = pos;

    norm = normal;
}
