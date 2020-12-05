#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(binding  = 0) uniform UniformBufferObject {
    mat4 model;
    mat4 view;
    mat4 projection;
} ubo;

layout(location = 0) in  vec3 inPosition;
layout(location = 1) in  vec3 inNormal;

layout(location = 0) out vec3 outColour;

void main() {
    outColour   = abs(inNormal);
    //outColour   = vec3(inPosition.z * 0.7 + 0.3);
    gl_Position = ubo.projection * ubo.view * ubo.model * vec4(inPosition, 1.0);
    //gl_Position = vec4(inPosition, 1.0) * ubo.model * ubo.view * ubo.projection;
}