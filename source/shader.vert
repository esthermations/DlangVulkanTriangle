#version 450

layout(location = 0) out vec4 vertex;

vec2 positions[3] = {
    vec2(+0.0, -0.5),
    vec2(+0.5, +0.5),
    vec2(-0.5, +0.5),
};

void main() {
    vertex = vec4(positions[gl_VertexIndex], 0.0, 1.0);
    gl_Position = vertex;
}