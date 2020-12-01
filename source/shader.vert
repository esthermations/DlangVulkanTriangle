#version 450

layout(binding  = 0) uniform UniformBufferObject {
    mat4 model;
    mat4 view;
    mat4 projection;
} ubo;

layout(location = 0) in  vec3 inPosition;
layout(location = 1) in  vec3 inNormal;
//layout(location = 1) in  vec3 inColour;

layout(location = 0) out vec3 outColour;

void main() {
    outColour   = abs(inNormal);
    gl_Position = ubo.projection * ubo.view * ubo.model * vec4(inPosition, 1.0);
}