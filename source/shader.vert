#version 450
#extension GL_ARB_separate_shader_objects : enable

// Ensure this is equal to the one defined in renderer.d
#define MAX_MODEL_UNIFORMS 1000

layout (binding = 0) uniform Uniforms {
    mat4 models[MAX_MODEL_UNIFORMS];
    mat4 view;
    mat4 projection;
} ubo;


// These locations correspond to values in getVertexAttributeDescription().
layout (location = 0) in  vec3 inPosition;
layout (location = 1) in  vec3 inNormal;

layout (location = 0) out vec3 outColour;


uint getEntityId() {
    /*
        TODO:
            - Sort entity data by vertex buffer
            - Set a uniform before each instanced draw of each vbuf containing
              the offset into the models[] array
            - Add that to the instance ID to get the actual index into models[]
    */
    return gl_InstanceIndex;
}


void main() {
    outColour   = abs(inNormal);
    gl_Position = ubo.projection
                * ubo.view
                * ubo.models[getEntityId()]
                * vec4(inPosition, 1.0);
}